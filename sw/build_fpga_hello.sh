#!/usr/bin/env bash
# build_fpga_hello.sh — assemble the FPGA bring-up demo into firmware.mem
# ($readmemh, one 32-bit word per line) for three_sipp_es_fpga.
set -euo pipefail
cd "$(dirname "$0")"
if [ -n "${RISCV_TC:-}" ]; then
  if [ -d "${RISCV_TC}/bin" ]; then
    export RISCV_TC="${RISCV_TC}/bin"
  fi
  export PATH="${RISCV_TC}:${PATH}"
fi
PFX="${RISCV_TC:+$RISCV_TC/}"

if [ -z "${GCC:-}" ]; then
  for tuple in riscv-none-elf riscv32-unknown-elf riscv64-unknown-elf riscv-elf riscv64-elf; do
    if command -v "${PFX}${tuple}-gcc" &>/dev/null; then
      GCC="${PFX}${tuple}-gcc"
      OBJCOPY="${OBJCOPY:-${PFX}${tuple}-objcopy}"
      break
    fi
  done
fi
GCC="${GCC:-${PFX}riscv-none-elf-gcc}"
OBJCOPY="${OBJCOPY:-${PFX}riscv-none-elf-objcopy}"

if ! command -v "$GCC" &>/dev/null; then
  echo "ERROR: RISC-V GCC toolchain not found. Set RISCV_TC or GCC env vars." >&2
  exit 1
fi
OUT="${1:-firmware.mem}"

"$GCC" -march=rv32imc -mabi=ilp32 -nostdlib -nostartfiles -fno-pic \
       -Wl,--no-relax -T fpga_hello.ld fpga_hello.S -o fpga_hello.elf
"$OBJCOPY" -O binary fpga_hello.elf fpga_hello.bin
PY="${PYTHON:-$(command -v python3 || command -v python)}"
"$PY" bin2hex.py fpga_hello.bin "$OUT"
echo "wrote $OUT"
