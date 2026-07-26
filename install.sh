#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
#  install.sh — instalador automático da ponte hashcat + GPU PowerVR
#  Repo: https://github.com/Sleep6ixteen/hascat
#
#  Hardware alvo: MediaTek MT6855 / PowerVR BXM-8-256 (ex: Moto G56 5G)
#  Ambiente: Termux (Android, sem root, sem proot)
# =============================================================================

set -e

# --- Cores ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "${GREEN}✔${NC} $*"; }
info() { echo -e "${CYAN}▶${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
die()  { echo -e "${RED}✘ ERRO:${NC} $*"; exit 1; }

echo -e "\n${BOLD}⚡ hascat installer — hashcat + GPU PowerVR no Termux${NC}"
echo -e "──────────────────────────────────────────────────────\n"

# =============================================================================
# 1. Verificar hardware
# =============================================================================
info "Verificando hardware..."

CHIPSET=$(getprop ro.board.platform 2>/dev/null || echo "")
GPU=$(getprop ro.hardware.egl 2>/dev/null || echo "")

if [[ "$CHIPSET" != *"mt6855"* && "$CHIPSET" != *"mt68"* ]]; then
    warn "Chipset detectado: '${CHIPSET:-desconhecido}'"
    warn "Este instalador foi testado no MediaTek MT6855 (Moto G56 5G)."
    echo -n "Continuar mesmo assim? [s/N] "
    read -r resp
    [[ "$resp" =~ ^[sS]$ ]] || die "Cancelado pelo usuário."
else
    ok "Chipset: $CHIPSET"
fi

# Verificar se as libs do vendor existem
VENDOR_OCL="/vendor/lib64/libOpenCL.so"
[[ -f "$VENDOR_OCL" ]] || die "Não encontrei $VENDOR_OCL — driver PowerVR não presente neste dispositivo."
ok "Driver PowerVR encontrado em /vendor/lib64"

# =============================================================================
# 2. Dependências do Termux
# =============================================================================
info "Instalando dependências..."
pkg install -y clang make python3 git binutils 2>&1 | grep -E "already|installed|upgraded" | head -5
ok "Dependências OK"

# =============================================================================
# 3. Criar estrutura de pastas
# =============================================================================
OCL="$HOME/ocl"
info "Criando $OCL ..."
mkdir -p "$OCL/vendors"
ok "Pasta criada"

# =============================================================================
# 4. Copiar libs do driver PowerVR
# =============================================================================
info "Copiando libs do driver PowerVR de /vendor/lib64..."

LIBS_MAIN=(
    libOpenCL.so
    libsrv_um.so
    libusc.so
    libgpud.so
    libmpvr.so
    libgralloc_extra.so
    libged.so
)

LIBS_MT6855=(
    libPVRMtkutils.so
    libpvr_mapper_utils.so
    libPVROCL.so
)

for lib in "${LIBS_MAIN[@]}"; do
    src="/vendor/lib64/$lib"
    if [[ -f "$src" ]]; then
        cp "$src" "$OCL/"
        ok "  $lib"
    else
        warn "  $lib — não encontrado em /vendor/lib64 (pode estar em subdiretório)"
    fi
done

for lib in "${LIBS_MT6855[@]}"; do
    # Tentar em ordem: mt6855 -> hw/mt6855 -> hw -> raiz
    found=0
    for search_path in \
        "/vendor/lib64/mt6855/$lib" \
        "/vendor/lib64/hw/mt6855/$lib" \
        "/vendor/lib64/hw/$lib" \
        "/vendor/lib64/$lib"
    do
        if [[ -f "$search_path" ]]; then
            cp "$search_path" "$OCL/"
            ok "  $lib (de $search_path)"
            found=1
            break
        fi
    done
    [[ $found -eq 1 ]] || warn "  $lib — não encontrado em nenhum subdiretório"
done

# Mapper gralloc
MAPPER_PATHS=(
    "/vendor/lib64/hw/mt6855/mapper.powervr.so"
    "/vendor/lib64/hw/mapper.powervr.so"
    "/vendor/lib64/mapper.powervr.so"
)
MAPPER_FOUND=0
for p in "${MAPPER_PATHS[@]}"; do
    if [[ -f "$p" ]]; then
        cp "$p" "$OCL/"
        ok "  mapper.powervr.so (de $p)"
        MAPPER_FOUND=1
        break
    fi
done
[[ $MAPPER_FOUND -eq 1 ]] || die "mapper.powervr.so não encontrado — necessário para a ponte funcionar."

# Backup do driver original
cp "$OCL/libPVROCL.so" "$OCL/libPVROCL.so.bak"
ok "  backup libPVROCL.so.bak criado"

# =============================================================================
# 5. Patchear caminhos absolutos nos binários
# =============================================================================
info "Patcheando caminhos absolutos nos binários..."

python3 << 'PYEOF'
import os

ocl = os.path.expanduser("~/ocl")

# Ordem importa: prefixos mais longos primeiro
PREFIXES = [
    b'/system/vendor/lib64/',
    b'/vendor/lib64/mt6855/',
    b'/vendor/lib64/hw/mt6855/',
    b'/vendor/lib64/hw/',
    b'/vendor/lib64/',
]

def patch_lib(path):
    with open(path, 'rb') as f:
        data = f.read()
    changed = False
    for prefix in PREFIXES:
        pos = 0
        while True:
            idx = data.find(prefix, pos)
            if idx < 0:
                break
            # Fim da string = próximo null após o prefixo
            end = data.find(b'\x00', idx + len(prefix))
            if end < 0:
                pos = idx + 1
                continue
            filename = data[idx + len(prefix):end]
            # Novo conteúdo = só o nome do arquivo, padding para manter tamanho
            old_total = end - idx  # inclui prefixo + filename, não inclui o \x00 final
            new_content = filename  # sem prefixo
            if len(new_content) > old_total:
                pos = idx + 1
                continue
            padding = b'\x00' * (old_total - len(new_content))
            data = data[:idx] + new_content + padding + data[end:]
            changed = True
            pos = idx + len(new_content)
    if changed:
        with open(path, 'wb') as f:
            f.write(data)
        print(f"  patched: {os.path.basename(path)}")

for fname in sorted(os.listdir(ocl)):
    if fname.endswith('.so') and not fname.endswith('.bak'):
        patch_lib(os.path.join(ocl, fname))

print("  patching concluído")
PYEOF
ok "Caminhos patcheados"

# =============================================================================
# 6. Arquivo ICD
# =============================================================================
info "Criando registro da plataforma OpenCL..."
echo "$OCL/libPVROCL.so" > "$OCL/vendors/pvr.icd"
ok "pvr.icd criado"

# =============================================================================
# 7. Compilar prophook.so
# =============================================================================
info "Compilando prophook.so..."

PROPHOOK_SRC="$OCL/prophook.c"

# Baixar o prophook.c do repo se não existir
if [[ ! -f "$PROPHOOK_SRC" ]]; then
    info "  Baixando prophook.c do repositório..."
    curl -fsSL "https://raw.githubusercontent.com/Sleep6ixteen/hascat/main/prophook.c" -o "$PROPHOOK_SRC" \
        || die "Falha ao baixar prophook.c"
fi

# Ajustar $HOME hardcoded no fonte
sed -i "s|/data/data/com.termux/files/home|$HOME|g" "$PROPHOOK_SRC"

clang -shared -fPIC -O2 -o "$OCL/prophook.so" "$PROPHOOK_SRC" -ldl \
    || die "Falha ao compilar prophook.so"
ok "prophook.so compilado"

# =============================================================================
# 8. Compilar hashcat com patch
# =============================================================================
HASHCAT_DIR="$HOME/hashcat"

if [[ -f "$HASHCAT_DIR/hashcat" ]]; then
    ok "hashcat já compilado em $HASHCAT_DIR — pulando compilação"
else
    info "Clonando hashcat v7.1.2..."
    git clone --depth=1 --branch v7.1.2 https://github.com/hashcat/hashcat.git "$HASHCAT_DIR" 2>&1 \
        | grep -E "Cloning|done" \
        || git clone --depth=1 https://github.com/hashcat/hashcat.git "$HASHCAT_DIR" 2>&1 \
        | grep -E "Cloning|done"

    info "Aplicando patch de local memory (32768 → 16384)..."
    sed -i 's/device_local_mem_size < 32768/device_local_mem_size < 16384/' "$HASHCAT_DIR/src/backend.c"

    # Verificar patch
    grep -q "device_local_mem_size < 16384" "$HASHCAT_DIR/src/backend.c" \
        || die "Patch não aplicado — verifique src/backend.c manualmente"
    ok "Patch aplicado"

    info "Compilando hashcat (pode demorar ~5 min)..."
    make -C "$HASHCAT_DIR" -j"$(nproc)" IS_ARM=1 CXXFLAGS="-DLITTLE_ENDIAN" 2>&1 \
        | grep -E "^CC|^LD|^MAKE|error:|warning:|Built" \
        | tail -5
    ok "hashcat compilado"
fi

# =============================================================================
# 9. Instalar wrapper hashcat-gpu
# =============================================================================
info "Instalando comando hashcat-gpu..."

WRAPPER="$PREFIX/bin/hashcat-gpu"

cat > "$WRAPPER" << WEOF
#!/data/data/com.termux/files/usr/bin/bash
# hashcat-gpu: hashcat nativo com GPU PowerVR BXM-8-256 (sem root)
# Ponte: libs vendor copiadas + patch de caminhos + hook de namespace (prophook.so)
export LD_PRELOAD="${HOME}/ocl/prophook.so"
export OCL_ICD_VENDORS="${HOME}/ocl/vendors"
export LD_LIBRARY_PATH="${HOME}/ocl"
exec "${HOME}/hashcat/hashcat" "\$@"
WEOF

chmod +x "$WRAPPER"
ok "hashcat-gpu instalado em $WRAPPER"

# =============================================================================
# 10. Teste final
# =============================================================================
echo ""
info "Testando instalação..."

OUTPUT=$(hashcat-gpu -I 2>/dev/null)

if echo "$OUTPUT" | grep -q "PowerVR"; then
    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║   ✔  Instalação concluída com sucesso!   ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo "$OUTPUT" | grep -E "Name|Clock|Memory.Total|Local.Memory|Driver"
    echo ""
    echo -e "  Use: ${BOLD}hashcat-gpu -b -m 1000${NC}  para benchmark NTLM"
    echo -e "  Use: ${BOLD}hashcat-gpu -I${NC}          para ver a GPU"
    echo -e "  Use: ${BOLD}hashcat-gpu --help${NC}       para ajuda completa"
    echo ""
else
    echo ""
    warn "GPU PowerVR não detectada na saída do hashcat-gpu -I"
    warn "Verifique os logs acima e consulte a seção 'Problemas conhecidos' no README."
    echo ""
    echo "$OUTPUT" | head -20
    exit 1
fi
