#!/usr/bin/env bash
# build_dhrystone.sh — compile Dhrystone 2.1 for 3-SIPP-ESR simulation.
# Usage: ./build_dhrystone.sh [NUMBER_OF_RUNS]
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

RUNS="${1:-500000}"
LDSCRIPT="${LDSCRIPT:-link.ld}"

FLAGS="-O2 -march=rv32imc -mabi=ilp32 -nostdlib -fno-pic -Wl,--no-relax"
INCLUDES="-I."

echo "Compiling Dhrystone for 3-SIPP-ESR (${RUNS} runs)..."

"$GCC" $FLAGS $INCLUDES -T "$LDSCRIPT" \
    -DNUMBER_OF_RUNS="${RUNS}" \
    -DCLK_FREQ_HZ=100000000 \
    -DCOMPILER_VERSION="\"$("$GCC" --version | head -1)\"" \
    -DCOMPILER_FLAGS="\"$FLAGS\"" \
    start.S \
    dhry_1.c \
    dhry_2.c \
    dhry_port.c \
    -lgcc -o dhrystone.elf

echo "Generating hex..."
"$OBJCOPY" -O binary dhrystone.elf dhrystone.bin
python3 ../../sw/bin2hex.py dhrystone.bin dhrystone.hex
echo "Done. dhrystone.hex is ready."
