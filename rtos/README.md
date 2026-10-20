# FreeRTOS on 3-SIPP-ES: Verification & Reproduction Guide

This directory contains the FreeRTOS kernel port, Board Support Package (BSP), verification test suites, and test runners for the **3-SIPP-ES** 3-stage in-order RV32IMAC(+B, Zcb) RISC-V processor.

---

## 1. Quick Start: Reproducing Verification Tests

### Run the Entire Suite (Single Command)
To compile and execute all five verification stages with automated validation and report generation:

```bash
# From repository root:
./build.sh rtos-suite

# Or directly using Python:
python3 rtos/run_all.py
```

This runs all tests in under 15 seconds and generates:
* **JSON Results:** [`docs/rtos-verification/results.json`](../docs/rtos-verification/results.json)
* **JUnit XML:** [`docs/rtos-verification/results_junit.xml`](../docs/rtos-verification/results_junit.xml)

### Run Individual Test Stages

```bash
# Stage 1: Baseline Demo + Negative Control (asserts tick is required)
bash rtos/build_rtos.sh demo
bash rtos/build_rtos.sh neg
python3 rtos/run_rtos.py

# Stage 2: Comprehensive 8-Phase Functional Smoke Test
bash rtos/build_rtos.sh smoke
python3 rtos/run_smoke.py

# Stage 3: Hardware Timer & Software Interrupt Integration
bash rtos/build_rtos.sh interrupt
python3 rtos/run_interrupt.py

# Stage 4: Cycle-Accurate Latency & Response-Time Characterization
bash rtos/build_rtos.sh timing
python3 rtos/run_timing.py

# Stage 5: Deterministic Stress Workload & Schedulability Overload Check
bash rtos/build_rtos.sh stress
bash rtos/build_rtos.sh stress_neg
python3 rtos/run_stress.py
```

---

## 2. Summary of Verified Features

| Stage / Test Suite | Binary / App | What is Verified | Status |
|:---|:---|:---|:---:|
| **Stage 1: Baseline Demo** | `app/main.c`<br>`rtos.hex` | Preemptive tick progression, producer/consumer queue ordering (items 1..8), counting semaphore (8 takes), CPU-bound worker preemption witness. **Negative Control (`rtos_neg.hex`):** Disabling timer interrupt stalls execution at item 1, proving preemption is strictly load-bearing. | **PASS** |
| **Stage 2: Smoke Suite** | `app/test_smoke.c`<br>`rtos_smoke.hex` | **8 Core Areas:**<br>1. Kernel initialization & multi-task creation.<br>2. Strict priority-based preemption.<br>3. **Full register state preservation (`s0`–`s11` bit patterns `0x11111111`..`0xCCCCCCCC` preserved across preemption).**<br>4. Queue FIFO communication and full/empty blocking.<br>5. Binary and counting semaphores, direct task notifications.<br>6. Timer tick progression and monotonic delay fidelity (`vTaskDelay`).<br>7. Stack high-water mark validation and safe heap limit rejection (`pvPortMalloc(1MB) == NULL`).<br>8. Repeated rapid context switching (40 ping-pong yields under asynchronous ticks). | **PASS** |
| **Stage 3: Interrupts** | `app/test_interrupt.c`<br>`rtos_interrupt.hex` | CLINT `mtime` hardware progression, timer wake accuracy, Machine Software Interrupt (`MSIP`, cause `0x80000003`) vectoring and clearing, `vTaskNotifyGiveFromISR()` task unblocking, and 10 rapid competing interrupts under ticks without register or stack corruption. | **PASS** |
| **Stage 4: Timing** | `app/test_timing.c`<br>`rtos_timing.hex` | Cycle-accurate latency decomposition using RISC-V `mcycle` CSR over 20 iterations. Formally documents distinction between empirical maximums and proven WCET bounds. | **PASS** |
| **Stage 5: Stress & RTA** | `app/test_stress.c`<br>`rtos_stress.hex` | Three fixed-priority tasks: task 1 (10 ms period), task 2 (25 ms period), task 3 (continuous background load), with shared priority-inheritance mutex contention. 0 deadline misses in positive run. **Negative Control (`rtos_stress_neg.hex`):** Injected workload overload reliably triggers and reports 3 deadline misses. | **PASS** |
| **Platform: MEIP** | `rtl/three_sipp_es_soc.sv` | Machine External Interrupt line (`irq_ext`) is tied to `1'b0` in SoC RTL (no PLIC instantiated). | **SKIPPED (UNSUPPORTED)** |

---

## 3. Measured Timing Characteristics

From the Stage 4 cycle-accurate characterization ([`rtos/timing_results.json`](timing_results.json)):

* **Interrupt Latency:** 63 cycles (deterministic; min=63, max=63, jitter=0).
  * Hardware commit + vector redirect to `mtvec` + FreeRTOS 32-register context save to stack.
* **Scheduler Latency:** 316–318 cycles (mean=316.2 cycles, jitter=2 cycles).
  * `vTaskNotifyGiveFromISR()` + `vTaskSwitchContext()` + context restore + `mret`.
* **Task Execution Time:** 293–300 cycles (mean=293.4 cycles).
* **End-to-End Event Response:** 672–681 cycles (mean=672.6 cycles, jitter=9 cycles).

---

## 4. Hardware & Memory Configuration

* **SoC Memory Map:**
  * `0x0000_0000 - 0x0000_7FFF` (32 KB): **IMEM** (Code + Read-only data + Data load image `_data_lma`).
  * `0x0200_0000 - 0x0200_FFFF`: **CLINT** (`msip` at `0x0000`, `mtimecmp` at `0x4000`, `mtime` at `0xBFF8`).
  * `0x1000_0000 - 0x1000_000F`: **UART** (Console TX/RX).
  * `0x2000_0000`: **tohost** (`1 = PASS`, `2 = FAIL`).
  * `0x8000_0000 - 0x8000_7FFF` (32 KB): **DRAM** (Runtime `.data`, `.bss`, stacks, FreeRTOS heap).
* **Tick Configuration ([`bsp/FreeRTOSConfig.h`](bsp/FreeRTOSConfig.h)):**
  * `configCPU_CLOCK_HZ`: `2000000UL`
  * `configTICK_RATE_HZ`: `1000` (Yields `2000 cycles / tick` in simulation).
  * `configTOTAL_HEAP_SIZE`: `16 * 1024` bytes.
  * `configCHECK_FOR_STACK_OVERFLOW`: `2` (Pattern-based checking).
  * `configUSE_MALLOC_FAILED_HOOK`: `1`.

---

## 5. Directory Structure & File Map

```text
rtos/
├── README.md                 # This documentation file
├── FreeRTOS-Kernel/          # Upstream official FreeRTOS kernel (tasks, queue, list, timers, heap_4)
├── app/
│   ├── main.c                # Stage 1 baseline demo application
│   ├── test_smoke.c          # Stage 2 8-phase functional smoke test suite
│   ├── test_interrupt.c      # Stage 3 CLINT timer and MSIP interrupt test suite
│   ├── test_timing.c         # Stage 4 cycle-accurate latency instrumentation harness
│   └── test_stress.c         # Stage 5 periodic stress workload and deadline monitor
├── bsp/
│   ├── FreeRTOSConfig.h      # Kernel configuration and enabled features
│   ├── bsp.h / bsp.c         # UART drivers, sim exit, assertion handlers, stack/heap hooks
│   ├── libc_stubs.c          # Freestanding libc stubs (memcpy, memset, memmove, strncpy, strlen)
│   ├── stdlib.h / string.h   # Freestanding minimal headers for bare-metal compilers
│   ├── start.S               # Reset crt0, data copy (IMEM->DRAM), bss zero, mtvec setup
│   └── three_sipp_es.ld      # Linker script (IMEM @ 0x0, DRAM @ 0x80000000)
├── build/                    # Generated ELF, BIN, and HEX images
├── build_rtos.sh             # Multi-variant compilation driver
├── run_rtos.py               # Stage 1 demo runner & transcript assertions
├── run_smoke.py              # Stage 2 smoke test runner
├── run_interrupt.py          # Stage 3 interrupt test runner
├── run_timing.py             # Stage 4 timing runner & JSON generator
├── run_stress.py             # Stage 5 stress & negative control runner
├── run_all.py                # Stage 6 unified single-command automation runner
└── timing_results.json       # Generated latency distributions
```

---

## 6. Comprehensive Documentation Index

Full technical deliverables are available in `docs/rtos-verification/`:
* **Baseline Report:** [`docs/rtos-verification/baseline.md`](../docs/rtos-verification/baseline.md)
* **Interrupt Report:** [`docs/rtos-verification/timer-interrupt.md`](../docs/rtos-verification/timer-interrupt.md)
* **Timing & WCET Analysis:** [`docs/rtos-verification/timing-instrumentation.md`](../docs/rtos-verification/timing-instrumentation.md)
* **Schedulability Analysis:** [`docs/rtos-verification/schedulability.md`](../docs/rtos-verification/schedulability.md)
* **Final Engineering Report:** [`docs/rtos-verification/report.md`](../docs/rtos-verification/report.md)
* **Machine Results:** [`docs/rtos-verification/results.json`](../docs/rtos-verification/results.json) | [`docs/rtos-verification/results_junit.xml`](../docs/rtos-verification/results_junit.xml)
