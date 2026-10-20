#!/usr/bin/env bash
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

FLAGS="-O2 -march=rv32im -mabi=ilp32 -nostdlib -fno-pic -Wl,--no-relax -fno-builtin"
INCLUDES="-I."

echo "Compiling CoreMark for 3-SIPP-ESR..."

ITERATIONS="${1:-100}"
LDSCRIPT="../../sw/link.ld"

"$GCC" $FLAGS $INCLUDES -T "$LDSCRIPT" \
    -DITERATIONS=$ITERATIONS -DFLAGS_STR="\"$FLAGS\"" \
    -DPERFORMANCE_RUN=1 \
    -DMAIN_HAS_NOARGC=1 \
    -DEE_TICKS_PER_SEC="100000000UL" \
    -DMEM_METHOD=MEM_STATIC \
    -DSEED_METHOD=SEED_VOLATILE \
    -DHAS_FLOAT=0 \
    -DHAS_TIME_H=0 \
    -DUSE_CLOCK=0 \
    -DHAS_STDIO=0 \
    -DHAS_PRINTF=0 \
    -DMULTITHREAD=1 \
    -DUSE_PTHREAD=0 \
    start.S \
    core_portme.c \
    core_list_join.c \
    core_main.c \
    core_matrix.c \
    core_state.c \
    core_util.c \
    -lgcc -o coremark.elf

echo "Generating hex file..."
"$OBJCOPY" -O binary coremark.elf coremark.bin
python3 ../../sw/bin2hex.py coremark.bin coremark.hex 8192
echo "Done. coremark.hex is ready."
