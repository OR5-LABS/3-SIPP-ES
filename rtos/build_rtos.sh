#!/usr/bin/env bash
# ==========================================================================
# build_rtos.sh -- build the 3-SIPP-ES FreeRTOS demo into a $readmemh IMEM hex.
#
# Compiles the FreeRTOS kernel + RISC-V port + 3-SIPP-ES BSP + demo app, links
# with bsp/three_sipp_es.ld, and emits build/rtos.hex (one 32-bit word per line).
# ==========================================================================
set -euo pipefail
cd "$(dirname "$0")"

# FreeRTOS-Kernel is a fetched dependency (not vendored). Clone the RISC-V-capable
# kernel on first use; only the generic kernel + GCC/RISC-V port are compiled below.
if [ ! -d FreeRTOS-Kernel ]; then
  echo "Fetching FreeRTOS-Kernel (first run)..."
  if command -v git > /dev/null; then
    git clone --depth 1 https://github.com/FreeRTOS/FreeRTOS-Kernel.git
  else
    # no git (e.g. a minimal container): fetch the same branch as a tarball
    python3 - <<'PY'
import io, tarfile, urllib.request, shutil, os
url = "https://github.com/FreeRTOS/FreeRTOS-Kernel/archive/refs/heads/main.tar.gz"
data = urllib.request.urlopen(url, timeout=120).read()
tarfile.open(fileobj=io.BytesIO(data)).extractall(".")
shutil.move("FreeRTOS-Kernel-main", "FreeRTOS-Kernel")
PY
  fi
fi

# RISC-V bare-metal GCC. Tools are taken from PATH; set RISCV_TC=/path/to/bin
# to point at a specific toolchain (e.g. an xpack riscv-none-elf-gcc).
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
      OBJDUMP="${OBJDUMP:-${PFX}${tuple}-objdump}"
      SIZE="${SIZE:-${PFX}${tuple}-size}"
      break
    fi
  done
fi
GCC="${GCC:-${PFX}riscv-none-elf-gcc}"
OBJCOPY="${OBJCOPY:-${PFX}riscv-none-elf-objcopy}"
OBJDUMP="${OBJDUMP:-${PFX}riscv-none-elf-objdump}"
SIZE="${SIZE:-${PFX}riscv-none-elf-size}"

if ! command -v "$GCC" &>/dev/null; then
  echo "ERROR: RISC-V GCC toolchain not found. Set RISCV_TC or GCC env vars." >&2
  exit 1
fi

K=FreeRTOS-Kernel
PORT=$K/portable/GCC/RISC-V
CHIP=$PORT/chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions

# App variant selection: demo (default), neg, smoke, interrupt, timing, stress
VARIANT="${1:-demo}"
XDEF=""
APP_SRC="app/main.c"
OUTBASE="rtos"

case "$VARIANT" in
  demo|"")
    APP_SRC="app/main.c"
    OUTBASE="rtos"
    ;;
  neg)
    APP_SRC="app/main.c"
    XDEF="-DNEG_NO_TICK"
    OUTBASE="rtos_neg"
    echo "== NEGATIVE CONTROL build (tick disabled) =="
    ;;
  smoke)
    APP_SRC="app/test_smoke.c"
    OUTBASE="rtos_smoke"
    ;;
  interrupt)
    APP_SRC="app/test_interrupt.c"
    OUTBASE="rtos_interrupt"
    ;;
  timing)
    APP_SRC="app/test_timing.c"
    OUTBASE="rtos_timing"
    ;;
  stress)
    APP_SRC="app/test_stress.c"
    OUTBASE="rtos_stress"
    ;;
  stress_neg)
    APP_SRC="app/test_stress.c"
    XDEF="-DNEG_OVERLOAD"
    OUTBASE="rtos_stress_neg"
    echo "== NEGATIVE CONTROL build (deliberate overload) =="
    ;;
  *)
    if [ -f "app/${VARIANT}.c" ]; then
      APP_SRC="app/${VARIANT}.c"
      OUTBASE="rtos_${VARIANT}"
    elif [ -f "$VARIANT" ]; then
      APP_SRC="$VARIANT"
      OUTBASE="rtos_$(basename "$VARIANT" .c)"
    else
      echo "Unknown variant: $VARIANT" >&2
      exit 1
    fi
    ;;
esac

mkdir -p build

# rv32imac (3-SIPP-ES is RV32IMAC); ilp32 ABI; freestanding; no relax so gp/la
# and the .data LMA stay put for our hand-rolled crt0.
CFLAGS="-march=rv32imac_zicsr_zifencei -mabi=ilp32 -Os -g \
  -ffunction-sections -fdata-sections -fno-builtin -fno-pic \
  -Wall -Wextra -Wno-unused-parameter \
  -I bsp -I app \
  -I $K/include -I $PORT -I $CHIP"

ASFLAGS="-march=rv32imac_zicsr_zifencei -mabi=ilp32 -I $PORT -I $CHIP -I bsp"

SRCS_C="
  $K/tasks.c $K/queue.c $K/list.c $K/timers.c
  $K/portable/MemMang/heap_4.c
  $PORT/port.c
  bsp/bsp.c
  bsp/libc_stubs.c
  $APP_SRC
"
SRCS_S="
  bsp/start.S
  $PORT/portASM.S
"

OBJS=()
for f in $SRCS_C; do
  o="build/${OUTBASE}_$(echo "$f" | tr '/.' '__').o"
  XF=""
  [ "$f" = "$APP_SRC" ] && XF="$XDEF"
  "$GCC" $CFLAGS $XF -c "$f" -o "$o"
  OBJS+=("$o")
done
for f in $SRCS_S; do
  o="build/${OUTBASE}_$(echo "$f" | tr '/.' '__').o"
  "$GCC" $ASFLAGS -c "$f" -o "$o"
  OBJS+=("$o")
done

"$GCC" -march=rv32imac_zicsr_zifencei -mabi=ilp32 -nostdlib -nostartfiles \
  -fno-pic -Wl,--no-relax -Wl,--gc-sections \
  -T bsp/three_sipp_es.ld "${OBJS[@]}" -lgcc -o "build/${OUTBASE}.elf"

"$OBJCOPY" -O binary "build/${OUTBASE}.elf" "build/${OUTBASE}.bin"
PY="${PYTHON:-$(command -v python3 || command -v python)}"
"$PY" ../sw/bin2hex.py "build/${OUTBASE}.bin" "build/${OUTBASE}.hex"

# size report
echo "---- section sizes ----"
"$SIZE" "build/${OUTBASE}.elf" || true
IMEM_BYTES=$(stat -c%s "build/${OUTBASE}.bin" 2>/dev/null || wc -c < "build/${OUTBASE}.bin")
echo "IMEM image: ${IMEM_BYTES} bytes (limit 32768)"
if [ "$IMEM_BYTES" -gt 32768 ]; then
  echo "ERROR: IMEM image exceeds 32 KB"; exit 1
fi
echo "wrote build/${OUTBASE}.hex"
