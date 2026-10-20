#!/usr/bin/env python3
# ============================================================================
# run_all.py -- Unified FreeRTOS Verification Suite Runner for 3-SIP-ESR.
#
# Runs all 5 verification stages:
#   - Stage 1: FreeRTOS Demo (positive + negative control without tick)
#   - Stage 2: Basic Functionality & Smoke Suite (8 functional areas)
#   - Stage 3: Timer & Interrupt Integration (CLINT, MSIP, notifications)
#   - Stage 4: Latency & Response-Time Instrumentation (JSON metrics)
#   - Stage 5: Stress Testing & Schedulability (overload negative control)
#
# Emits:
#   - docs/rtos-verification/results.json
#   - docs/rtos-verification/results_junit.xml
# Exits with 0 on complete pass, 1 on any failure.
# ============================================================================
import json, os, subprocess, sys, time
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.path.dirname(HERE)
BUILD_SH = os.path.join(HERE, "build_rtos.sh")
DOCS_DIR = os.path.join(CORE, "docs", "rtos-verification")

os.makedirs(DOCS_DIR, exist_ok=True)

def sh(cmd, **kw):
    return subprocess.run(cmd, cwd=CORE, capture_output=True, text=True, **kw)

def get_git_commit():
    r = sh(["git", "rev-parse", "HEAD"])
    return r.stdout.strip() if r.returncode == 0 else "unknown"

def get_tool_versions():
    vers = {}
    r = sh(["verilator", "--version"])
    vers["verilator"] = r.stdout.strip() if r.returncode == 0 else "not found"
    r = sh(["riscv64-unknown-elf-gcc", "--version"])
    vers["gcc"] = r.stdout.splitlines()[0] if r.returncode == 0 else "not found"
    vers["python"] = sys.version.split()[0]
    return vers

TEST_STAGES = [
    {
        "id": "stage1_demo",
        "name": "Stage 1: Baseline FreeRTOS Demo & Negative Control",
        "build_cmds": [["bash", BUILD_SH, "demo"], ["bash", BUILD_SH, "neg"]],
        "runner": ["python3", os.path.join(HERE, "run_rtos.py")],
    },
    {
        "id": "stage2_smoke",
        "name": "Stage 2: Comprehensive RTOS Smoke Suite (8 Sub-tests)",
        "build_cmds": [["bash", BUILD_SH, "smoke"]],
        "runner": ["python3", os.path.join(HERE, "run_smoke.py")],
    },
    {
        "id": "stage3_interrupt",
        "name": "Stage 3: Timer & Software Interrupt Integration",
        "build_cmds": [["bash", BUILD_SH, "interrupt"]],
        "runner": ["python3", os.path.join(HERE, "run_interrupt.py")],
    },
    {
        "id": "stage4_timing",
        "name": "Stage 4: Latency & Response-Time Characterization",
        "build_cmds": [["bash", BUILD_SH, "timing"]],
        "runner": ["python3", os.path.join(HERE, "run_timing.py")],
    },
    {
        "id": "stage5_stress",
        "name": "Stage 5: Stress Workload & Schedulability Negative Control",
        "build_cmds": [["bash", BUILD_SH, "stress"], ["bash", BUILD_SH, "stress_neg"]],
        "runner": ["python3", os.path.join(HERE, "run_stress.py")],
    },
]

def main():
    print("=" * 72)
    print("     3-SIP-ESR PROCESSOR: FREERTOS VERIFICATION TEST SUITE")
    print("=" * 72)

    commit = get_git_commit()
    tools = get_tool_versions()
    print(f"Git Commit : {commit}")
    print(f"Tools      : Verilator={tools['verilator']}, GCC={tools['gcc']}, Python={tools['python']}\n")

    results = {
        "metadata": {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "git_commit": commit,
            "tools": tools,
            "architecture": "3-SIP-ESR RV32IMAC(+B, Zcb)",
        },
        "unsupported_features": [
            {
                "feature": "MEIP (Machine External Interrupt)",
                "status": "UNSUPPORTED",
                "reason": "Core CSR logic supports MEIP, but irq_ext line is tied to 1'b0 in three_sipp_es_soc.sv (no platform PLIC instantiated)",
            }
        ],
        "stages": [],
    }

    all_pass = True
    total_start = time.time()

    for stage in TEST_STAGES:
        st_name = stage["name"]
        print(f"\n>>> Running {st_name}...")
        t0 = time.time()

        # Build step
        build_err = None
        for bcmd in stage["build_cmds"]:
            b_res = sh(bcmd)
            if b_res.returncode != 0:
                build_err = f"Build failed for {' '.join(bcmd)}:\n{b_res.stdout}\n{b_res.stderr}"
                break

        if build_err:
            print(f"FAILED (Build):\n{build_err}")
            results["stages"].append({
                "id": stage["id"],
                "name": st_name,
                "status": "FAIL",
                "duration_sec": time.time() - t0,
                "log": build_err,
            })
            all_pass = False
            continue

        # Execute runner
        r_res = sh(stage["runner"])
        dur = time.time() - t0
        passed = (r_res.returncode == 0)

        results["stages"].append({
            "id": stage["id"],
            "name": st_name,
            "status": "PASS" if passed else "FAIL",
            "duration_sec": dur,
            "log": r_res.stdout + r_res.stderr,
        })

        if passed:
            print(f"VERDICT: PASS ({dur:.2f}s)")
        else:
            print(f"VERDICT: FAIL ({dur:.2f}s)\nOutput:\n{r_res.stdout}\n{r_res.stderr}")
            all_pass = False

    total_dur = time.time() - total_start
    results["summary"] = {
        "total_stages": len(TEST_STAGES),
        "passed": sum(1 for s in results["stages"] if s["status"] == "PASS"),
        "failed": sum(1 for s in results["stages"] if s["status"] == "FAIL"),
        "unsupported": len(results["unsupported_features"]),
        "total_duration_sec": total_dur,
        "overall_verdict": "PASS" if all_pass else "FAIL",
    }

    # Save JSON results
    json_path = os.path.join(DOCS_DIR, "results.json")
    with open(json_path, "w") as f:
        json.dump(results, f, indent=2)

    # Save JUnit XML
    ts_elem = ET.Element("testsuite", {
        "name": "3-SIP-ESR_FreeRTOS_Verification",
        "tests": str(len(TEST_STAGES) + len(results["unsupported_features"])),
        "failures": str(results["summary"]["failed"]),
        "time": f"{total_dur:.3f}",
    })

    for s in results["stages"]:
        tc = ET.SubElement(ts_elem, "testcase", {
            "name": s["name"],
            "classname": s["id"],
            "time": f"{s['duration_sec']:.3f}",
        })
        if s["status"] != "PASS":
            fail = ET.SubElement(tc, "failure", {"message": "Test stage failed"})
            fail.text = s["log"]

    for u in results["unsupported_features"]:
        tc = ET.SubElement(ts_elem, "testcase", {
            "name": u["feature"],
            "classname": "unsupported",
            "time": "0.0",
        })
        ET.SubElement(tc, "skipped", {"message": u["reason"]})

    xml_path = os.path.join(DOCS_DIR, "results_junit.xml")
    tree = ET.ElementTree(ts_elem)
    tree.write(xml_path, encoding="utf-8", xml_declaration=True)

    # Summary table
    print("\n" + "=" * 72)
    print("                    FINAL VERIFICATION SUMMARY")
    print("=" * 72)
    print(f"{'Stage Name':<56} | {'Status':<10}")
    print("-" * 72)
    for s in results["stages"]:
        print(f"{s['name']:<56} | {s['status']:<10}")
    for u in results["unsupported_features"]:
        print(f"{u['feature']:<56} | {'SKIPPED':<10}")
    print("-" * 72)
    print(f"Overall Result : {results['summary']['overall_verdict']}")
    print(f"Artifacts      : {os.path.relpath(json_path, CORE)}")
    print(f"                 {os.path.relpath(xml_path, CORE)}")
    print("=" * 72)

    sys.exit(0 if all_pass else 1)

if __name__ == "__main__":
    main()
