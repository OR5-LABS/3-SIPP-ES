#!/usr/bin/env python3
# ============================================================================
# run_stress.py -- Runner for Stage 5 Stress Tests and Negative Control.
#
# Runs:
#   1. Positive stress run (rtos_stress.hex): Asserts zero deadline misses
#      under continuous background load and shared mutex contention.
#   2. Negative control run (rtos_stress_neg.hex): Asserts that deliberate
#      task overload is detected as a deadline miss.
# ============================================================================
import os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.path.dirname(HERE)
SIM  = os.path.join(CORE, "sim", "tb_three_sipp_es_rtos")
POS_HEX = os.path.join(HERE, "build", "rtos_stress.hex")
NEG_HEX = os.path.join(HERE, "build", "rtos_stress_neg.hex")

def run(hexfile):
    sim_rel = os.path.relpath(SIM, CORE)
    hex_rel = os.path.relpath(hexfile, CORE)
    cmd = [sim_rel, f"+IMEM={hex_rel}", "+MAXCYC=3000000"]
    print(f"[run_stress] Running: {' '.join(cmd)}")
    proc = subprocess.run(cmd, cwd=CORE, capture_output=True, text=True)
    return proc.returncode, proc.stdout + proc.stderr

def main():
    if not os.path.exists(POS_HEX) or not os.path.exists(NEG_HEX):
        sys.exit("ERROR: build/rtos_stress.hex or rtos_stress_neg.hex missing. Run build_rtos.sh stress & stress_neg first.")

    print("\n---------------- POSITIVE STRESS RUN ----------------")
    rc_pos, out_pos = run(POS_HEX)
    print(out_pos)
    if "[STRESS] ALL SCHEDULED TASKS MET DEADLINES: PASS" not in out_pos or "[TB] PASS" not in out_pos:
        sys.exit("[run_stress] FAIL: positive stress run failed")

    print("\n---------------- NEGATIVE CONTROL RUN ----------------")
    rc_neg, out_neg = run(NEG_HEX)
    print(out_neg)
    if "[DEADLINE MISS] Task 1 exceeded deadline!" not in out_neg:
        sys.exit("[run_stress] FAIL: negative control did not trigger expected deadline miss")
    if "[STRESS_NEG] PASS: Deadline miss successfully caught as designed!" not in out_neg or "[TB] PASS" not in out_neg:
        sys.exit("[run_stress] FAIL: negative control harness verification failed")

    print("=" * 60)
    print("[run_stress] STAGE 5 STRESS AND SCHEDULABILITY VERIFICATION PASSED")
    sys.exit(0)

if __name__ == "__main__":
    main()
