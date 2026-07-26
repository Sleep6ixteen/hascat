#!/data/data/com.termux/files/usr/bin/bash
# hashcat-gpu: hashcat nativo com GPU PowerVR BXM-8-256 (sem root)
# Ponte: libs vendor copiadas + patch de caminhos + hook de namespace (prophook.so)
export LD_PRELOAD="$HOME/ocl/prophook.so"
export OCL_ICD_VENDORS="$HOME/ocl/vendors"
export LD_LIBRARY_PATH="$HOME/ocl"
exec "$HOME/hashcat/hashcat" "$@"
