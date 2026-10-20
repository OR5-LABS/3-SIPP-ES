#!/usr/bin/env bash
# ============================================================================
# 3-SIPP-ESR build & test driver (Verilator).
#
#   ./build.sh [sim|cosim|rvfi|zcb|trig|debug|priv|axi|rtos|rtos-suite|arch|arch-sim|fpga|clean]
#
# 3-SIPP-ESR is a 3-stage in-order RV32IMAC(+B, Zcb) core. The datapath leaf
# cells (ALU / muldiv / regfile / CSR / RVC / immgen / branch / decoder / PMP)
# live in rtl/common; the core, SoC, UART, AXI4-Lite wrapper and the RISC-V
# Debug Module live in rtl/.
#
# Every action exits non-zero when its testbench reports a failure, a timeout,
# a mismatch or an error, or when it does not print its PASS verdict.
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"
VRL="${VERILATOR:-verilator}"
PY="${PYTHON:-$(command -v python3 || command -v python)}"
ACTION="${1:-sim}"

R=rtl
C=rtl/common
DBG=rtl/three_sipp_es_debug.sv

# Shared datapath leaf cells, in elaboration order.
CELLS=( \
  "$C/three_sipp_es_pkg.sv" "$C/three_sipp_es_alu.sv" "$C/three_sipp_es_regfile.sv" \
  "$C/three_sipp_es_muldiv.sv" "$C/three_sipp_es_csr.sv" "$C/three_sipp_es_rvc.sv" \
  "$C/three_sipp_es_immgen.sv" "$C/three_sipp_es_branch.sv" "$C/three_sipp_es_decode.sv" \
  "$C/three_sipp_es_pmp.sv" )

# run_check PASS_REGEX CMD...
# Runs a simulator and echoes its output. Fails (exit 1) if the simulator exits
# non-zero, if any line reports FAIL / TIMEOUT / MISMATCH / an error, or if no
# line matches PASS_REGEX (the testbench's PASS verdict).
run_check() {
  local pass_re="$1"; shift
  local log rc=0
  log=$(mktemp)
  "$@" > "$log" 2>&1 || rc=$?
  cat "$log"
  if [[ $rc -ne 0 ]]; then
    echo "VERDICT: FAIL (simulator exited with status $rc)"; rm -f "$log"; exit 1
  fi
  if grep -qE 'FAIL|TIMEOUT|MISMATCH|%Error|FATAL' "$log"; then
    echo "VERDICT: FAIL (the testbench reported a failure)"; rm -f "$log"; exit 1
  fi
  if ! grep -qE "$pass_re" "$log"; then
    echo "VERDICT: FAIL (no PASS verdict from the testbench)"; rm -f "$log"; exit 1
  fi
  rm -f "$log"
}

if [[ "$ACTION" == "clean" ]]; then
  rm -rf sim build programs/build rtos/build *.vcd
  echo "Cleaned"; exit 0
fi
mkdir -p sim programs/build

if [[ "$ACTION" == "priv" ]]; then
  # Directed M/U + PMP + Smepmp + HW-trigger + N user-trap tests on a SECURE=1 core.
  echo "Building 3-SIPP-ESR SECURE priv/trigger/N sim..."
  "$PY" programs/build_priv.py
  "$PY" programs/build_trig.py
  "$PY" programs/build_ntrap.py
  "$VRL" --binary -j 0 -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC --trace --timescale 1ns/1ps --Mdir sim -o tb_three_sipp_es_priv -I"$C" -I"$R" \
    "${CELLS[@]}" "$R/three_sipp_es_core.sv" tb/tb_three_sipp_es_priv.sv 2>/dev/null
  fail=0
  for t in ustore_fault ustore_ok ecall_u ecall_m ifetch_fault ifetch_ok ucsr_u ucsr_m \
           uload_fault uload_ok mml_mexec mml_mexec_off mml_uload mml_uload_off mml_cfg mtvec_mode uamo_fault uamo_ok \
           exec_hit exec_miss store_hit store_miss udeleg nodel; do
    hex=""
    [[ -f programs/build/priv_$t.hex  ]] && hex=programs/build/priv_$t.hex
    [[ -f programs/build/trig_$t.hex  ]] && hex=programs/build/trig_$t.hex
    [[ -f programs/build/ntrap_$t.hex ]] && hex=programs/build/ntrap_$t.hex
    r=$(sim/tb_three_sipp_es_priv +IMEM="$hex" 2>&1 | grep RESULT || true)
    printf "  %-16s %s\n" "$t" "${r:-RESULT: FAIL (no result line)}"
    [[ "$r" == *PASS* ]] || fail=1
  done
  [[ $fail -eq 0 ]] && echo "priv: ALL PASS" || { echo "priv: FAILURES"; exit 1; }
  exit 0
fi

if [[ "$ACTION" == "rtos" ]]; then
  # Port + run a REAL preemptive RTOS (FreeRTOS) on 3-SIPP-ESR. Builds the kernel
  # + RISC-V port + 3-SIPP-ESR BSP into an IMEM image, runs it on the SoC sim
  # (CLINT tick + UART console) and asserts the transcript plus a negative
  # control (tick disabled -> demo stalls). See rtos/run_rtos.py.
  echo "Building 3-SIPP-ESR FreeRTOS demo (positive + negative-control images)..."
  bash rtos/build_rtos.sh
  bash rtos/build_rtos.sh neg
  echo "Running FreeRTOS demo + assertions..."
  VERILATOR="$VRL" "$PY" rtos/run_rtos.py
  exit $?
fi

if [[ "$ACTION" == "rtos-suite" ]]; then
  echo "Running comprehensive 3-SIPP-ESR FreeRTOS verification suite..."
  VERILATOR="$VRL" "$PY" rtos/run_all.py
  exit $?
fi

if [[ "$ACTION" == "debug" ]]; then
  echo "Building 3-SIPP-ESR debug (JTAG DM) sim..."
  "$VRL" --binary -j 0 -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC --trace --timescale 1ns/1ps --Mdir sim -o tb_three_sipp_es_debug -I"$C" -I"$R" \
    "${CELLS[@]}" "$DBG" \
    "$R/three_sipp_es_core.sv" "$R/three_sipp_es_uart.sv" "$R/three_sipp_es_soc.sv" \
    tb/tb_three_sipp_es_debug.sv
  run_check '^DEBUG: PASS' sim/tb_three_sipp_es_debug
  exit 0
fi

if [[ "$ACTION" == "axi" ]]; then
  # OPTIONAL AXI4-Lite MASTER bridge — standalone leaf cell + slave-mem BFM tb.
  # The default three_sipp_es_soc + compliance path never instantiate it (unchanged).
  echo "Building 3-SIPP-ESR AXI4-Lite MASTER bridge sim..."
  "$VRL" --binary -j 0 -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC --trace --timescale 1ns/1ps --Mdir sim -o tb_three_sipp_es_axi -I"$C" -I"$R" \
    "$C/three_sipp_es_pkg.sv" "$R/three_sipp_es_axi_lite.sv" tb/tb_three_sipp_es_axi.sv
  run_check '^AXI: PASS' sim/tb_three_sipp_es_axi
  exit 0
fi

if [[ "$ACTION" == "fpga" ]]; then
  echo "Building FPGA SoC sim (UART banner + LED blink)..."
  bash sw/build_fpga_hello.sh
  "$VRL" --binary -j 0 -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC --trace --timescale 1ns/1ps --Mdir sim -o tb_three_sipp_es_fpga -DSIMULATION -I"$C" -I"$R" \
    "${CELLS[@]}" "$R/three_sipp_es_core.sv" "$R/three_sipp_es_uart.sv" \
    fpga/three_sipp_es_fpga.sv fpga/tb_three_sipp_es_fpga.sv
  run_check '^FPGA: PASS' sim/tb_three_sipp_es_fpga
  exit 0
fi

# ---- default: smoke (+ optional cosim / rvfi / zcb / trig) ------------------
"$PY" programs/build_smoke.py
echo "Compiling..."
"$VRL" --binary -j 0 -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC --trace --timescale 1ns/1ps --Mdir sim -o tb_three_sipp_es -I"$C" -I"$R" \
  "${CELLS[@]}" "$DBG" \
  "$R/three_sipp_es_core.sv" "$R/three_sipp_es_uart.sv" "$R/three_sipp_es_soc.sv" \
  tb/tb_three_sipp_es.sv
echo "Running smoke..."
run_check '^\[TB\] PASS' sim/tb_three_sipp_es +IMEM=programs/build/smoke.hex

if [[ "$ACTION" == "cosim" ]]; then
  echo "Co-simulating against golden model..."
  VVP="" VERILATOR="$VRL" "$PY" tools/cosim.py \
      --hex programs/build/smoke.hex --sim sim/tb_three_sipp_es
fi

if [[ "$ACTION" == "zcb" ]]; then
  # Directed Zcb test (hand-assembled, programs/build_zcb.py) + its negative
  # control: the control corrupts one expected value, so the program must
  # report FAIL (tohost=2); the action fails if the control passes.
  echo "Building + running the Zcb directed test and its negative control..."
  "$PY" programs/build_zcb.py
  "$PY" programs/build_zcb.py --neg
  run_check '^\[TB\] PASS' sim/tb_three_sipp_es +IMEM=programs/build/zcb.hex
  neg=$(sim/tb_three_sipp_es +IMEM=programs/build/zcb_neg.hex 2>&1 || true)
  if grep -q '^\[TB\] FAIL (code 2)' <<< "$neg"; then
    echo "zcb negative control: failed as designed (tohost=2)"
  else
    echo "$neg"; echo "zcb negative control: FAIL (the corrupted check did not fail)"; exit 1
  fi
  echo "ZCB: PASS"
fi

if [[ "$ACTION" == "trig" ]]; then
  # The Sdtrig trigger unit is not gated by SECURE: run the directed trigger
  # programs (hit + miss negative controls) on the default M-only SoC too.
  echo "Running the trigger tests on the default SoC..."
  "$PY" programs/build_trig.py
  for t in exec_hit exec_miss store_hit store_miss; do
    run_check '^\[TB\] PASS' sim/tb_three_sipp_es +IMEM=programs/build/trig_$t.hex
  done
  echo "TRIG: PASS"
fi

if [[ "$ACTION" == "rvfi" ]]; then
  echo "Building RVFI (riscv-formal interface) self-check..."
  "$VRL" --binary -j 0 -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC --trace --timescale 1ns/1ps --Mdir sim -o tb_three_sipp_es_rvfi -DRISCV_FORMAL -I"$C" -I"$R" \
    "${CELLS[@]}" "$DBG" \
    "$R/three_sipp_es_core.sv" "$R/three_sipp_es_uart.sv" "$R/three_sipp_es_soc.sv" \
    tb/tb_three_sipp_es_rvfi.sv
  run_check '^RVFI: PASS' sim/tb_three_sipp_es_rvfi +IMEM=programs/build/smoke.hex
fi

if [[ "$ACTION" == "arch-sim" ]]; then
  echo "Building 3-SIPP-ESR RISC-V Architectural Test simulator..."
  "$VRL" --binary -j 0 -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC --timescale 1ns/1ps --Mdir sim -o tb_three_sipp_es_arch -I"$C" -I"$R" \
    "${CELLS[@]}" "$R/three_sipp_es_core.sv" tb/tb_three_sipp_es_arch.sv
  exit 0
fi

if [[ "$ACTION" == "arch" ]]; then
  echo "Building 3-SIPP-ESR RISC-V Architectural Test simulator..."
  "$VRL" --binary -j 0 -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC --timescale 1ns/1ps --Mdir sim -o tb_three_sipp_es_arch -I"$C" -I"$R" \
    "${CELLS[@]}" "$R/three_sipp_es_core.sv" tb/tb_three_sipp_es_arch.sv
  echo "Running RISC-V Architectural Compliance Test suite..."
  "$PY" arch-test/run_arch_test.py
  exit $?
fi
