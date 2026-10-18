#!/usr/bin/env python3
# ============================================================================
# run_timing.py -- Self-checking runner and parser for Stage 4 timing tests.
#
# Runs rtos_timing.hex, extracts the JSON timing block, saves timing_results.json,
# and verifies that measurements are within physical reasonable limits.
# ============================================================================
import json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.path.dirname(HERE)
SIM  = os.path.join(CORE, "sim", "tb_three_sipp_es_rtos")
HEX  = os.path.join(HERE, "build", "rtos_timing.hex")
OUT_JSON = os.path.join(HERE, "timing_results.json")

def main():
    if not os.path.exists(HEX):
        sys.exit(f"ERROR: {HEX} missing. Run 'bash rtos/build_rtos.sh timing' first.")

    sim_rel = os.path.relpath(SIM, CORE)
    hex_rel = os.path.relpath(HEX, CORE)
    cmd = [sim_rel, f"+IMEM={hex_rel}", "+MAXCYC=3000000"]
    print(f"[run_timing] Running: {' '.join(cmd)}")
    proc = subprocess.run(cmd, cwd=CORE, capture_output=True, text=True)
    out = proc.stdout + proc.stderr
    print(out)

    if "[TB] PASS" not in out:
        sys.exit("[run_timing] FAIL: testbench did not report [TB] PASS")

    # Extract JSON
    m = re.search(r"\[TIMING_JSON_START\]\s*(\{.*?\})\s*\[TIMING_JSON_END\]", out, re.DOTALL)
    if not m:
        sys.exit("[run_timing] FAIL: could not extract TIMING_JSON from transcript")

    data = json.loads(m.group(1))
    with open(OUT_JSON, "w") as f:
        json.dump(data, f, indent=2)
    print(f"[run_timing] Wrote structured metrics to: {os.path.relpath(OUT_JSON, CORE)}")

    # Integrity assertions on measurements
    irq_max = data["interrupt_latency"]["max"]
    sched_max = data["scheduler_latency"]["max"]
    resp_max = data["response_time"]["max"]

    assert 10 <= irq_max <= 500, f"Interrupt latency out of expected range: {irq_max}"
    assert 50 <= sched_max <= 2000, f"Scheduler latency out of expected range: {sched_max}"
    assert resp_max >= (irq_max + sched_max), "End-to-end response must be >= IRQ + Sched latency"

    print("[run_timing] STAGE 4 TIMING CHARACTERIZATION PASSED")
    sys.exit(0)

if __name__ == "__main__":
    main()
