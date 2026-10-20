#!/usr/bin/env bash
# run_dhrystone.sh — build Dhrystone and run it on 3-SIPP-ESR simulation.
# Usage: ./run_dhrystone.sh [NUMBER_OF_RUNS]
set -euo pipefail
cd "$(dirname "$0")"

RUNS="${1:-2000000}"

echo "Building Dhrystone for simulation (${RUNS} runs)..."
./src/build_dhrystone.sh "${RUNS}"

if [ ! -f ../obj_dir/Vtb_three_sipp_es ]; then
  echo "Building 3-SIPP-ESR simulator with Verilator..."
  cd ..
  verilator --binary --timing --top tb_three_sipp_es -Wno-fatal -Irtl/common -Irtl rtl/common/three_sipp_es_pkg.sv rtl/common/three_sipp_es_alu.sv rtl/common/three_sipp_es_regfile.sv rtl/common/three_sipp_es_muldiv.sv rtl/common/three_sipp_es_csr.sv rtl/common/three_sipp_es_rvc.sv rtl/common/three_sipp_es_immgen.sv rtl/common/three_sipp_es_branch.sv rtl/common/three_sipp_es_decode.sv rtl/common/three_sipp_es_pmp.sv rtl/three_sipp_es_debug.sv rtl/three_sipp_es_core.sv rtl/three_sipp_es_uart.sv rtl/three_sipp_es_soc.sv tb/tb_three_sipp_es.sv
  cd -
fi

echo "Running Dhrystone on 3-SIPP-ESR simulation..."
# cycle budget scales with the run count (about 330 cycles per run, plus setup)
MAXCYC=$(( RUNS * 500 + 20000000 ))
log=$(mktemp)
../obj_dir/Vtb_three_sipp_es +IMEM=src/dhrystone.hex +MAXCYCLES="$MAXCYC" | tee "$log"
# the run must end with the testbench's PASS verdict (tohost = 1)
if grep -qE 'FAIL|TIMEOUT' "$log" || ! grep -q '^\[TB\] PASS' "$log"; then
  rm -f "$log"; echo "Dhrystone: FAIL (no [TB] PASS verdict)"; exit 1
fi
rm -f "$log"
