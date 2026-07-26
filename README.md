# hashcat-gpu — hashcat com GPU PowerVR no Termux (sem root)

hashcat v7.1.2 compilado nativo para Android/aarch64, usando a GPU
PowerVR BXM-8-256 (MediaTek MT6855) via OpenCL 3.0 — sem root, sem proot.

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
hashcat-gpu -m 0 hashes.txt wordlist.txt              # MD5
hashcat-gpu -m 1000 hashes.txt wordlist.txt           # NTLM
hashcat-gpu -m 1000 hashes.txt -a 3 ?l?l?l?l?d?d      # força bruta
hashcat-gpu -m 1000 hashes.txt wordlist.txt -r rules/best64.rule
```

Todos os argumentos são repassados ao hashcat oficial — a documentação
dele vale 100% aqui (https://hashcat.net/wiki/).

## Performance medida (Moto G56 5G)

| Modo          | Velocidade  |
|---------------|-------------|
| MD5 (0)       | ~82 MH/s    |
| NTLM (1000)   | ~176 MH/s   |

GPU: PowerVR BXM-8-256 @ 390 MHz, 7.6 GB (unificada), OpenCL 3.0, driver 25.1.

## Como funciona (a ponte)

O OpenCL deste chip é bloqueado para apps por 4 camadas. O setup contorna todas:

1. **Namespace do linker** — libs do driver (`/vendor/lib64`) copiadas para
   `~/ocl/` e caminhos absolutos patcheados nos binários.
2. **Propriedades de build** — `prophook.so` (LD_PRELOAD) intercepta
   `__system_property_get` e reporta build `userdebug`.
3. **Gate do gralloc** — o módulo `mapper.powervr.so` era carregado em
   namespace isolado (sphal) e registrava a conexão OpenCL na instância
   errada. O hook `android_load_sphal_library` carrega o módulo no
   namespace do processo. Era a causa do `gr_getDevConnection` = -22.
4. **hashcat** — requisito de local mem reduzido de 32 KB para 16 KB
   (o chip reporta 28 KB) em `src/backend.c`.

## Mapa de arquivos

```
$PREFIX/bin/hashcat-gpu   comando (wrapper com as variáveis de ambiente)
~/hashcat/                build completo do hashcat v7.1.2
~/ocl/                    stack do driver PowerVR + prophook.so (a ponte)
~/ocl/libPVROCL.so.bak    driver original (antes dos patches)
~/ocl/prophook.c          fonte dos hooks (namespace + propriedades)
~/clinfo                  diagnóstico OpenCL (compilado de ~/clinfo.c)
```

## Problemas conhecidos

- **Rodar `hashcat` sem o wrapper não acha a GPU** — as variáveis
  (LD_PRELOAD, OCL_ICD_VENDORS, LD_LIBRARY_PATH) são obrigatórias.
  Use sempre `hashcat-gpu`.
- **Atualização de sistema (OTA)** pode mudar as libs em `/vendor/lib64`.
  Se quebrar, recopie as libs e reaplique os patches (a pasta `~/ocl`
  tem o `.bak` de referência).
- **Alguns modos de hash podem falhar no self-test** — driver mobile.
  Contorno: `--self-test-disable` (teste o resultado depois).
- Nome/vendor do device aparecem trocados no clinfo — quirk do driver,
  inofensivo.

## Reproduzir do zero

1. `cp /vendor/lib64/libOpenCL.so ~/ocl/` + dependências (libsrv_um,
   libusc, libPVRMtkutils, libgpud, libpvr_mapper_utils, libmpvr,
   libgralloc_extra, libged, libPVROCL) — copiar de `/vendor/lib64/`,
   `/vendor/lib64/mt6855/`, `/vendor/lib64/hw/mt6855/`.
2. Patchear caminhos absolutos `/system/vendor/...` e `/vendor/...`
   para nomes relativos nos binários copiados.
3. `cp /vendor/lib64/hw/mapper.powervr.so ~/ocl/`
4. Compilar `~/ocl/prophook.c` → `prophook.so` (clang -shared -fPIC).
5. hashcat: `make -j8 IS_ARM=1 CXXFLAGS="-DLITTLE_ENDIAN"`,
   patch `device_local_mem_size < 32768` → `16384` em `src/backend.c`.
