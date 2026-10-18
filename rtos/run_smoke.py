#!/usr/bin/env python3
# ============================================================================
# run_smoke.py -- Self-checking runner for Stage 2 FreeRTOS smoke tests.
#
# Asserts the completion and individual PASS verdicts for:
#   1. Kernel Startup and Task Creation
#   2. Priority Preemption
#   3. Register State Preservation (s0-s11)
#   4. Queue FIFO Communication
#   5. Semaphore and Notification Sync
#   6. Tick Progression and Task Delay
#   7. Heap and Stack Boundary Handling
#   8. Repeated Rapid Task Switching
#
# Returns 0 on complete pass, 1 on any failure or timeout.
# ============================================================================
import os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.path.dirname(HERE)
SIM  = os.path.join(CORE, "sim", "tb_three_sipp_es_rtos")
HEX  = os.path.join(HERE, "build", "rtos_smoke.hex")

REQUIRED_TESTS = [
    "Kernel Startup and Task Creation",
    "Priority Preemption",
    "Register State Preservation (s0-s11)",
    "Queue FIFO Communication",
    "Semaphore and Notification Sync",
    "Tick Progression and Task Delay",
    "Heap and Stack Boundary Handling",
    "Repeated Rapid Task Switching",
]

def main():
    if not os.path.exists(HEX):
        sys.exit(f"ERROR: {HEX} missing. Run 'bash rtos/build_rtos.sh smoke' first.")

    sim_rel = os.path.relpath(SIM, CORE)
    hex_rel = os.path.relpath(HEX, CORE)
    cmd = [sim_rel, f"+IMEM={hex_rel}", "+MAXCYC=3000000"]
    print(f"[run_smoke] Running: {' '.join(cmd)}")
    proc = subprocess.run(cmd, cwd=CORE, capture_output=True, text=True)
    out = proc.stdout + proc.stderr
    print(out)

    errs = []
    if "[BOOT] FreeRTOS Smoke Test Suite" not in out:
        errs.append("Missing boot banner")

    for t in REQUIRED_TESTS:
        pass_pattern = f"[TEST] {t}: PASS"
        fail_pattern = f"[TEST] {t}: FAIL"
        if pass_pattern not in out:
            if fail_pattern in out:
                errs.append(f"Test failed: {t}")
            else:
                errs.append(f"Test did not complete: {t}")

    if "[SMOKE] ALL STAGE 2 TESTS PASSED SUCCESSFULLY!" not in out:
        errs.append("Missing final success banner")

    if "[TB] PASS" not in out:
        errs.append("Testbench did not assert [TB] PASS (tohost != 1)")

    if proc.returncode != 0:
        errs.append(f"Simulator exited with non-zero status {proc.returncode}")

    print("=" * 60)
    if errs:
        print("[run_smoke] STAGE 2 VERIFICATION FAILED:")
        for e in errs:
            print(f"  - {e}")
        sys.exit(1)
    else:
        print(f"[run_smoke] STAGE 2 VERIFICATION PASSED: All {len(REQUIRED_TESTS)} sub-tests verified.")
        sys.exit(0)

if __name__ == "__main__":
    main()
