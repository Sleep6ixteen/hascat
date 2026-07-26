# hascat — hashcat com GPU PowerVR no Termux (sem root)

hashcat v7.1.2 compilado nativo para Android/aarch64, usando a GPU
**PowerVR BXM-8-256 (MediaTek MT6855)** via OpenCL 3.0 — sem root, sem proot.

> **Hardware testado:** Motorola Moto G56 5G (XT2423)  
> Funciona em qualquer aparelho com chip MT6855 e GPU PowerVR BXM-8-256.

---

## Uso

```bash
hashcat-gpu <argumentos normais do hashcat>
```

Exemplos:

```bash
# Listar a GPU detectada
hashcat-gpu -I

# Benchmark
hashcat-gpu -b              # todos os modos (demora)
hashcat-gpu -b -m 1000      # só NTLM (rápido)

# Quebra real
hashcat-gpu -m 0    hashes.txt wordlist.txt              # MD5
hashcat-gpu -m 1000 hashes.txt wordlist.txt              # NTLM
hashcat-gpu -m 1000 hashes.txt -a 3 ?l?l?l?l?d?d        # força bruta
hashcat-gpu -m 1000 hashes.txt wordlist.txt -r rules/best64.rule
```

Todos os argumentos são repassados ao hashcat oficial —
documentação completa em https://hashcat.net/wiki/.

---

## Performance medida (Moto G56 5G)

| Modo        | Hash    | Velocidade  |
|-------------|---------|-------------|
| MD5         | `-m 0`  | ~82 MH/s    |
| NTLM        | `-m 1000` | ~176 MH/s |

**GPU:** PowerVR BXM-8-256 @ 390 MHz, 7.6 GB (memória unificada), OpenCL 3.0, driver 25.1

---

## Por que o OpenCL não funciona direto no Termux

O driver OpenCL deste chip está presente em `/vendor/lib64`, mas bloqueado
para apps em 4 camadas diferentes. Este projeto contorna todas elas:

### Camada 1 — Namespace do linker
As libs do driver (`/vendor/lib64`) vivem num namespace isolado do linker
do Android e não são visíveis para processos de app. Solução: copiar as libs
para `~/ocl/` e patchear os caminhos absolutos embutidos nos binários
(`/system/vendor/...` e `/vendor/...`) para nomes relativos, de modo que
o linker os encontre dentro de `~/ocl/` via `LD_LIBRARY_PATH`.

### Camada 2 — Propriedades de build
O driver verifica `ro.build.type` e `ro.debuggable` antes de inicializar.
Em builds de produção (`user`) ele recusa. Solução: `prophook.so`
(injetado via `LD_PRELOAD`) intercepta `__system_property_get` e reporta
build `userdebug` + `ro.debuggable=1`.

### Camada 3 — Gate do gralloc (causa do erro `-22`)
O módulo `mapper.powervr.so` era carregado pela libOpenCL via
`android_load_sphal_library` — uma função que força carregamento no
namespace isolado `sphal`. Isso fazia o módulo registrar a conexão OpenCL
numa instância diferente da do processo, resultando em
`gr_getDevConnection = -22` (EINVAL). Solução: `prophook.so` também
intercepta `android_load_sphal_library` e carrega o mapper com `dlopen`
normal, no namespace do processo.

### Camada 4 — Requisito de local memory do hashcat
O hashcat exige `device_local_mem_size >= 32 KB`. A GPU reporta 28 KB.
Solução: patch em `src/backend.c`, linha do check
`if (device_local_mem_size < 16384)` — o threshold de rejeição foi
reduzido de 32768 para 16384, deixando o chip passar.

---

## Arquivos deste repositório

| Arquivo | Descrição |
|---------|-----------|
| `prophook.c` | Código-fonte dos hooks (namespace + propriedades + sphal) |
| `hashcat-gpu.sh` | Wrapper que exporta as variáveis e chama o hashcat |
| `clinfo.c` | Diagnóstico OpenCL — lista plataformas e devices |
| `README.md` | Este arquivo |

> Os binários (`.so` do driver, `prophook.so`, `hashcat`) não estão no repo:
> as libs do driver são propriedade da Imagination/Mediatek e não podem ser
> redistribuídas; os binários compilados são reproduzíveis seguindo o guia abaixo.

---

## Reproduzir do zero (guia completo)

### Pré-requisitos
- Termux atualizado (`pkg update`)
- Aparelho com chip **MediaTek MT6855** e GPU **PowerVR BXM-8-256**
- `pkg install clang git make python3`

---

### Passo 1 — Criar a pasta de trabalho

```bash
mkdir ~/ocl
mkdir ~/ocl/vendors
```

---

### Passo 2 — Copiar as libs do driver PowerVR

```bash
# Libs principais
cp /vendor/lib64/libOpenCL.so          ~/ocl/
cp /vendor/lib64/libsrv_um.so          ~/ocl/
cp /vendor/lib64/libusc.so             ~/ocl/
cp /vendor/lib64/libgpud.so            ~/ocl/
cp /vendor/lib64/libmpvr.so            ~/ocl/
cp /vendor/lib64/libgralloc_extra.so   ~/ocl/
cp /vendor/lib64/libged.so             ~/ocl/

# Libs do subdiretório mt6855
cp /vendor/lib64/mt6855/libPVRMtkutils.so    ~/ocl/
cp /vendor/lib64/mt6855/libpvr_mapper_utils.so ~/ocl/
cp /vendor/lib64/mt6855/libPVROCL.so         ~/ocl/
cp /vendor/lib64/mt6855/libPVROCL.so         ~/ocl/libPVROCL.so.bak   # backup

# Mapper (gralloc)
cp /vendor/lib64/hw/mt6855/mapper.powervr.so ~/ocl/
```

---

### Passo 3 — Patchear caminhos absolutos nos binários

O driver tem caminhos hardcoded como `/vendor/lib64/...` e
`/system/vendor/lib64/...`. É preciso substituí-los por nomes curtos
(sem barra, só o nome do arquivo) para que o linker os resolva via
`LD_LIBRARY_PATH=~/ocl`.

```bash
# Exemplo com sed binário (repete para cada lib que tiver caminhos hardcoded)
# Verificar quais libs têm caminhos absolutos:
for f in ~/ocl/*.so; do
  strings "$f" | grep -q '/vendor/lib64' && echo "$(basename $f) tem caminhos"
done

# Patchear (substitui a string preservando o tamanho com padding \0)
# Use o script patch_rpath.py ou faça manualmente com sed -i binário:
cd ~/ocl
python3 - << 'PYEOF'
import os, re

def patch_lib(path):
    with open(path, 'rb') as f:
        data = f.read()
    changed = False
    # Substitui /vendor/lib64/mt6855/ e /vendor/lib64/ por string vazia + nome
    for prefix in [b'/vendor/lib64/mt6855/', b'/vendor/lib64/hw/mt6855/',
                   b'/vendor/lib64/hw/', b'/vendor/lib64/',
                   b'/system/vendor/lib64/']:
        while prefix in data:
            idx = data.index(prefix)
            # Encontra o fim da string (null terminator)
            end = data.index(b'\x00', idx)
            original = data[idx:end]
            filename = original[len(prefix):]
            # Padding com \x00 para manter tamanho
            replacement = filename + b'\x00' * (len(prefix))
            data = data[:idx] + replacement + data[end:]
            changed = True
            print(f"  {path}: {original} -> {filename}")
    if changed:
        with open(path, 'wb') as f:
            f.write(data)

for fname in os.listdir('.'):
    if fname.endswith('.so') and not fname.endswith('.bak'):
        patch_lib(fname)
print("Patching concluído.")
PYEOF
```

---

### Passo 4 — Criar o arquivo ICD (OpenCL platform registry)

```bash
echo "$HOME/ocl/libPVROCL.so" > ~/ocl/vendors/pvr.icd
```

---

### Passo 5 — Compilar o prophook.so

```bash
cd ~/ocl
clang -shared -fPIC -O2 -o prophook.so prophook.c -ldl
```

> **Atenção:** o `prophook.c` deste repo tem os caminhos hardcoded para
> `$HOME/ocl/`. Edite as strings `/data/data/com.termux/files/home/ocl/`
> para o seu `$HOME` real antes de compilar:

```bash
sed -i "s|/data/data/com.termux/files/home|$HOME|g" prophook.c
clang -shared -fPIC -O2 -o prophook.so prophook.c -ldl
```

---

### Passo 6 — Compilar o clinfo (diagnóstico)

```bash
cd ~
clang -o clinfo clinfo.c \
  -I/data/data/com.termux/files/usr/include \
  -L~/ocl -lOpenCL \
  -Wl,-rpath,~/ocl

# Testar:
LD_PRELOAD=~/ocl/prophook.so \
OCL_ICD_VENDORS=~/ocl/vendors \
LD_LIBRARY_PATH=~/ocl \
~/clinfo
```

Deve aparecer: `Platform: PowerVR` e `Device: PowerVR BXM-8-256`.

---

### Passo 7 — Compilar o hashcat com patch

```bash
cd ~
git clone --depth=1 https://github.com/hashcat/hashcat.git
cd hashcat

# Patch: reduzir threshold de local memory de 32 KB para 16 KB
# Arquivo: src/backend.c — linha com: if (device_local_mem_size < 16384)
# (no código original era 32768 — a GPU reporta 28 KB e seria rejeitada)
sed -i 's/device_local_mem_size < 32768/device_local_mem_size < 16384/' src/backend.c

# Verificar se o patch foi aplicado:
grep "device_local_mem_size < " src/backend.c | grep -v dynamic

# Compilar para aarch64 Android
make -j$(nproc) IS_ARM=1 CXXFLAGS="-DLITTLE_ENDIAN"
```

---

### Passo 8 — Instalar o wrapper

Copie o `hashcat-gpu.sh` deste repo para `$PREFIX/bin/hashcat-gpu`:

```bash
cp hashcat-gpu.sh $PREFIX/bin/hashcat-gpu
chmod +x $PREFIX/bin/hashcat-gpu

# Ajustar $HOME se necessário (o script usa $HOME hardcoded):
sed -i "s|/data/data/com.termux/files/home|$HOME|g" $PREFIX/bin/hashcat-gpu
```

O wrapper contém apenas:

```bash
#!/data/data/com.termux/files/usr/bin/bash
export LD_PRELOAD="$HOME/ocl/prophook.so"
export OCL_ICD_VENDORS="$HOME/ocl/vendors"
export LD_LIBRARY_PATH="$HOME/ocl"
exec "$HOME/hashcat/hashcat" "$@"
```

---

### Passo 9 — Testar

```bash
hashcat-gpu -I          # deve listar a GPU PowerVR
hashcat-gpu -b -m 1000  # benchmark NTLM (~176 MH/s no MT6855)
```

---

## Problemas conhecidos

| Problema | Causa | Solução |
|----------|-------|---------|
| `hashcat` sem wrapper não acha a GPU | Faltam `LD_PRELOAD`, `OCL_ICD_VENDORS`, `LD_LIBRARY_PATH` | Sempre use `hashcat-gpu` |
| Atualização OTA quebra tudo | Libs de `/vendor/lib64` mudam | Recopiar libs e reaplicar patches (o `.bak` é referência) |
| Self-test falha em alguns modos | Quirk do driver mobile | Use `--self-test-disable` e verifique os resultados manualmente |
| Nome/vendor trocados no clinfo | Quirk do driver | Inofensivo |
| `gr_getDevConnection = -22` | mapper carregado no namespace errado | Resolvido pelo hook `android_load_sphal_library` no prophook.c |

---

## Mapa de arquivos (instalação completa)

```
$PREFIX/bin/hashcat-gpu     wrapper (variáveis de ambiente)
~/hashcat/                  build completo do hashcat v7.1.2
~/ocl/                      stack do driver PowerVR + prophook.so
~/ocl/libPVROCL.so.bak      driver original (antes dos patches — referência)
~/ocl/prophook.c            fonte dos hooks
~/ocl/vendors/pvr.icd       registro da plataforma OpenCL
~/clinfo                    diagnóstico OpenCL compilado
```

---

## Licença

O código deste repo (`prophook.c`, `clinfo.c`, `hashcat-gpu.sh`) é livre —
use, modifique e redistribua à vontade.  
O hashcat tem sua própria licença (MIT): https://github.com/hashcat/hashcat  
As libs do driver PowerVR são propriedade da Imagination Technologies /
MediaTek — não estão neste repo e não podem ser redistribuídas.
