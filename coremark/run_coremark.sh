#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "Building CoreMark for simulation (100 iterations)..."
./src/build_coremark.sh 100

if [ ! -f ../obj_dir/Vtb_three_sipp_es ]; then
  echo "Building 3-SIP-ESR simulator with Verilator..."
  cd ..
  verilator --binary --timing --top tb_three_sipp_es -Wno-fatal -Irtl/common -Irtl rtl/common/three_sipp_es_pkg.sv rtl/common/three_sipp_es_alu.sv rtl/common/three_sipp_es_regfile.sv rtl/common/three_sipp_es_muldiv.sv rtl/common/three_sipp_es_csr.sv rtl/common/three_sipp_es_rvc.sv rtl/common/three_sipp_es_immgen.sv rtl/common/three_sipp_es_branch.sv rtl/common/three_sipp_es_decode.sv rtl/common/three_sipp_es_pmp.sv rtl/three_sipp_es_debug.sv rtl/three_sipp_es_core.sv rtl/three_sipp_es_uart.sv rtl/three_sipp_es_soc.sv tb/tb_three_sipp_es.sv
  cd -
fi

echo "Running CoreMark on 3-SIP-ESR simulation..."
log=$(mktemp)
../obj_dir/Vtb_three_sipp_es +IMEM=src/coremark.hex | tee "$log"
# the run must end with the testbench's PASS verdict (tohost = 1)
if grep -qE 'FAIL|TIMEOUT' "$log" || ! grep -q '^\[TB\] PASS' "$log"; then
  rm -f "$log"; echo "CoreMark: FAIL (no [TB] PASS verdict)"; exit 1
fi
rm -f "$log"
