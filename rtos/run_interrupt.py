#!/usr/bin/env python3
# ============================================================================
# run_interrupt.py -- Self-checking runner for Stage 3 Timer & Interrupt tests.
#
# Asserts:
#   1. CLINT mtime hardware progression
#   2. Timer Interrupt Wake Fidelity (vTaskDelay)
#   3. Software Interrupt (MSIP) Handling & Clearing
#   4. ISR-Driven Task Notification (vTaskNotifyGiveFromISR)
#   5. Competing Interrupts and State Preservation
#
# Returns 0 on complete pass, 1 on any failure or timeout.
# ============================================================================
import os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.path.dirname(HERE)
SIM  = os.path.join(CORE, "sim", "tb_three_sipp_es_rtos")
HEX  = os.path.join(HERE, "build", "rtos_interrupt.hex")

REQUIRED_TESTS = [
    "CLINT mtime hardware progression",
    "Timer Interrupt Wake Fidelity (vTaskDelay)",
    "Software Interrupt (MSIP) Handling & Clearing",
    "ISR-Driven Task Notification (vTaskNotifyGiveFromISR)",
    "Competing Interrupts and State Preservation",
]

def main():
    if not os.path.exists(HEX):
        sys.exit(f"ERROR: {HEX} missing. Run 'bash rtos/build_rtos.sh interrupt' first.")

    sim_rel = os.path.relpath(SIM, CORE)
    hex_rel = os.path.relpath(HEX, CORE)
    cmd = [sim_rel, f"+IMEM={hex_rel}", "+MAXCYC=3000000"]
    print(f"[run_interrupt] Running: {' '.join(cmd)}")
    proc = subprocess.run(cmd, cwd=CORE, capture_output=True, text=True)
    out = proc.stdout + proc.stderr
    print(out)

    errs = []
    if "[BOOT] Timer and Interrupt Test Suite" not in out:
        errs.append("Missing boot banner")

    for t in REQUIRED_TESTS:
        pass_pattern = f"[TEST] {t}: PASS"
        fail_pattern = f"[TEST] {t}: FAIL"
        if pass_pattern not in out:
            if fail_pattern in out:
                errs.append(f"Test failed: {t}")
            else:
                errs.append(f"Test did not complete: {t}")

    if "[INTERRUPT] ALL STAGE 3 TESTS PASSED SUCCESSFULLY!" not in out:
        errs.append("Missing final success banner")

    if "[TB] PASS" not in out:
        errs.append("Testbench did not assert [TB] PASS (tohost != 1)")

    if proc.returncode != 0:
        errs.append(f"Simulator exited with non-zero status {proc.returncode}")

    print("=" * 60)
    if errs:
        print("[run_interrupt] STAGE 3 VERIFICATION FAILED:")
        for e in errs:
            print(f"  - {e}")
        sys.exit(1)
    else:
        print(f"[run_interrupt] STAGE 3 VERIFICATION PASSED: All {len(REQUIRED_TESTS)} sub-tests verified.")
        sys.exit(0)

if __name__ == "__main__":
    main()
