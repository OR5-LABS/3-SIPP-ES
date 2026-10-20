# FreeRTOS Verification Baseline Report: 3-SIP-ESR Core

**Document Version:** 1.0  
**Target Core:** 3-SIP-ESR (RV32IMAC + B, Zcb; 3-stage pipeline)  
**Date:** 2026-10-18  
**Baseline Git Commit:** `01d2a9fa31b34fd4c2879b072f39cb5c42710bdf`

---

## 1. Executive Summary

This document establishes the reproducible baseline for verifying FreeRTOS support and evaluating real-time capabilities on the **3-SIP-ESR** RISC-V processor.

The core is an in-order, 3-stage (`F -> X -> W`) processor implementing the RV32IMAC ISA plus Bitmanip (`Zba`, `Zbb`, `Zbc`, `Zbs`) and `Zcb`. It features a direct-vectored Machine-mode trap model, a RISC-V standard Core Local Interruptor (CLINT), memory-mapped UART, and debug module.

All baseline targets in the repository test suite (`run_tests.sh`) pass. The original FreeRTOS demonstration (`build.sh rtos`) was inspected, verified, and found to have a toolchain header dependency that prevented out-of-the-box compilation with bare-metal GCC cross-compilers (`gcc-riscv64-unknown-elf`). With minimal freestanding standard headers added to the BSP (`bsp/stdlib.h`, `bsp/string.h`, and corresponding string primitives in `bsp/libc_stubs.c`), the demo compiles and runs deterministically.

---

## 2. Environment and Toolchain Configuration

The baseline was established using the following host and toolchain versions:

| Component | Version / Identifier | Path | Notes |
|:---|:---|:---|:---|
| **OS** | Linux x86_64 (Ubuntu 24.04 LTS kernel) | - | Host platform |
| **Verilator** | `Verilator 5.020 2024-01-01 rev v5.020` | `/usr/bin/verilator` | RTL simulator |
| **Cross GCC** | `riscv64-unknown-elf-gcc (13.2.0)` | `/usr/bin/riscv64-unknown-elf-gcc` | Built with `rv32imac/ilp32` multilib |
| **Binutils** | GNU ld/objcopy/size `2.42` | `/usr/bin/riscv64-unknown-elf-*` | Target: `riscv64-unknown-elf` |
| **Python** | `Python 3.12.3` | `/usr/bin/python3` | Test driver & co-simulator |
| **Vivado** | `Vivado v2023.2 (64-bit)` | `vivado` (in system PATH) | FPGA synthesis & implementation |

---

## 3. Baseline Verification Results

### 3.1 Existing Repository Suite (`./run_tests.sh`)

Every baseline entry listed in `tests/expected.txt` was executed against Verilator simulation models:

| Target Entry | Command | Exit Code | PASS Lines | FAIL Lines | Verdict | Notes |
|:---|:---|:---:|:---:|:---:|:---:|:---|
| `build.sh:sim` | `bash build.sh sim` | 0 | 1 | 1 | **PASS** | Directed smoke tests |
| `build.sh:cosim` | `bash build.sh cosim` | 0 | 1 | 1 | **PASS** | Golden RV32IM model lock-step match |
| `build.sh:rvfi` | `bash build.sh rvfi` | 0 | 2 | 1 | **PASS** | Formal retirement interface invariants |
| `build.sh:zcb` | `bash build.sh zcb` | 0 | 3 | 3 | **PASS** | Zcb directed + load-bearing neg control |
| `build.sh:trig` | `bash build.sh trig` | 0 | 6 | 1 | **PASS** | Sdtrig hardware triggers |
| `build.sh:debug` | `bash build.sh debug` | 0 | 1 | 0 | **PASS** | JTAG Debug Module halt/resume/GPR access |
| `build.sh:priv` | `bash build.sh priv` | 0 | 25 | 0 | **PASS** | 25 M/U privilege + PMP + N-trap tests |
| `build.sh:axi` | `bash build.sh axi` | 0 | 1 | 0 | **PASS** | Standalone AXI4-Lite master bridge |
| `build.sh:fpga` | `bash build.sh fpga` | 0 | 1 | 0 | **PASS** | FPGA top-level simulation (BRAM+UART) |

All 9 repository regression targets pass cleanly with exact count matching.

### 3.2 FreeRTOS Demo Baseline (`build.sh rtos`)

* **Execution Command:** `bash build.sh rtos`
* **Exit Code:** `0`
* **Harness:** `rtos/run_rtos.py` driving Verilator testbench `tb/tb_three_sipp_es_rtos.sv`
* **Observed Transcript:**
  ```text
  [BOOT]freertos
  [P]send:1
  [C]sem
  [C]got:1
  [P]send:2
  [C]sem
  [C]got:2
  [P]send:3
  [C]sem
  [C]got:3
  [P]send:4
  [C]sem
  [C]got:4
  [W]run@21
  [P]send:5
  [C]sem
  [C]got:5
  [P]send:6
  [C]sem
  [C]got:6
  [P]send:7
  [C]sem
  [C]got:7
  [P]send:8
  [C]sem
  [C]got:8
  [DONE]ok
  [TB] tohost write: 0x00000001 at cycle 132830
  [TB] PASS
  ```
* **Negative Control:**
  With timer interrupt disabled in `rtos_neg.hex` (`vPortSetupTimerInterrupt` no-op leaving `mtimecmp = 0xFFFFFFFF_FFFFFFFF`), the kernel halts after sending item 1, timing out deterministically at cycle 300,001.

---

## 4. Hardware Architecture and Interrupt Topology

### 4.1 Memory Map
* `0x0000_0000 - 0x0000_7FFF` (32 KB): **IMEM** (Combinational read ROM/RAM; instructions + initialized data LMA)
* `0x0200_0000 - 0x0200_FFFF`: **CLINT**
  * `0x0200_0000`: `msip` (bit 0 writable, drives software interrupt `irq_soft`)
  * `0x0200_4000`: `mtimecmp[31:0]`
  * `0x0200_4004`: `mtimecmp[63:32]`
  * `0x0200_BFF8`: `mtime[31:0]` (increments 1 count/cycle in simulation)
  * `0x0200_BFFC`: `mtime[63:32]`
* `0x1000_0000 - 0x1000_000F`: **UART** (Base + 0: TX/Status, +4: RX, +8: BAUDDIV)
* `0x2000_0000`: **tohost** (0x1 = PASS, 0x2 = FAIL)
* `0x8000_0000 - 0x8000_7FFF` (32 KB): **DRAM** (Single-cycle SRAM; runtime `.data`, `.bss`, task stacks, FreeRTOS heap)

### 4.2 Trap and Interrupt Mechanism
1. **Interrupt Lines to Core:**
   * `irq_timer`: Asserted when `mtime >= mtimecmp` (MTIP, cause 7).
   * `irq_soft`: Driven by `msip` (MSIP, cause 3).
   * `irq_ext`: Machine External Interrupt line (MEIP, cause 11). **NOTE:** In `three_sipp_es_soc.sv` and `three_sipp_es_fpga.sv`, `irq_ext` is tied to `1'b0`.
2. **Interrupt Acceptance Condition (`take_irq`):**
   Interrupts are accepted on committing, non-branching instructions when `mstatus.MIE == 1` and `mie[cause] == 1`:
   ```verilog
   wire take_irq = fx_valid && !ex_freeze && irq_req && !ex_trap && !dbg_freeze &&
                   !d_is_mret && !is_uret &&
                   !d_is_csr && !d_is_jal && !d_is_jalr && !d_is_branch;
   ```
   * The committing instruction finishes retirement.
   * `trap_epc` is set to `fx_pc + fx_len` (the next sequential instruction).
   * Hardware updates: `mepc <= trap_epc`, `mcause <= {1'b1, 27'd0, irq_cause}`, `mstatus.MPIE <= mstatus.MIE`, `mstatus.MIE <= 0`.
   * Execution vectors directly to `mtvec` (direct mode: bits `1:0` fixed at `2'b00`).
3. **Context Switch / Yield:**
   Triggered synchronously by `ECALL`. `portASM.S` traps to `freertos_risc_v_trap_handler`, saves caller/callee-saved registers to current TCB stack, updates `pxCurrentTCB`, and restores the new task context before executing `mret`.

---

## 5. Verified Behavior vs. Unverified Assumptions

| Capability | Current Status | Supporting Evidence | Limitations / Unverified Assumptions |
|:---|:---:|:---|:---|
| **RV32IMAC ISA Compliance** | **VERIFIED** | Co-simulation (`cosim.py`) & formal retire checks (`rvfi`) | Validated for Machine mode instructions; user-mode traps validated in `priv` test. |
| **Basic FreeRTOS Preemption** | **VERIFIED** | `rtos/run_rtos.py` positive run | High priority Worker was preempted once; negative control proved tick requirement. |
| **Queue / Semaphore Sync** | **VERIFIED** | 8 items sent/received in FIFO order | Tested only with 2 cooperative tasks and small message size (4 bytes). |
| **Full Register State Preservation** | **UNVERIFIED** | Basic execution succeeded | Register clobbering across preemptive ISR was not verified with bit-pattern assertions on all 32 GPRs. |
| **Stack Overflow Protection** | **UNVERIFIED** | Not configured | `configCHECK_FOR_STACK_OVERFLOW` was disabled (0). |
| **Heap Exhaustion Handling** | **UNVERIFIED** | Not configured | `configUSE_MALLOC_FAILED_HOOK` was disabled (0). |
| **External Interrupt Path (`irq_ext`)** | **UNVERIFIED** | Hardware line tied to 0 in SoC | Core CSR logic supports MEIP, but no platform interrupt controller (PLIC) is wired in SoC. |
| **Interrupt Latency & Jitter** | **UNVERIFIED** | None | Cycle-accurate response times, handler entry latency, and jitter have not been measured. |
| **Schedulability & WCET Bounds** | **UNVERIFIED** | None | No response-time analysis ($R_i \le D_i$) has been computed; zero deadline-miss tests have been executed. |
| **Real-Time Capability** | **UNVERIFIED** | FreeRTOS boots, but timing guarantees are unproven | Demonstrating that FreeRTOS runs does NOT prove real-time capability. Upper timing bounds remain uncharacterized. |

---

## 6. Next Steps

With the baseline firmly established and documented, subsequent stages will:
1. **Stage 2:** Deploy an expanded RTOS smoke-test verifying 32-register preservation, stack overflow hooks, heap boundary checks, and rapid multi-task preemption.
2. **Stage 3:** Validate timer and software interrupt integration with cycle-level assertions, watchdog timeouts, and trap vector integrity checks.
3. **Stage 4:** Introduce minimally invasive cycle instrumentation for interrupt latency, scheduler dispatch latency, and task execution times.
4. **Stage 5:** Implement configurable stress workloads and rigorous Response-Time Analysis ($R_i = C_i + B_i + \sum \lceil R_i/T_j \rceil C_j$).
5. **Stage 6:** Package the complete suite into a unified runner with JUnit/JSON reporting and deliver the final verification assessment.
