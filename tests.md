# Test Results

Full pass/fail results for all verification suites. Recorded against **Verilator 5.020** and **RISC-V GCC 13.2**. The regression output is also captured in `tests/expected.txt` and checked by `./run_tests.sh`.

---

## Simulation & RTL Tests

| Test | What it checks | Result |
| :--- | :--- | :---: |
| `build.sh sim` | Smoke program: ALU operations, multiply/divide, branches, loads/stores, CSR access, trap handling | **PASS** |
| `build.sh cosim` | Every retired instruction compared retire-by-retire against a golden RV32IM ISA model | **PASS** |
| `build.sh rvfi` | RISC-V Formal Interface trace invariants checked over the smoke program | **PASS** |
| `build.sh zcb` | All Zcb compressed instructions; negative control (corrupted expected value) fails with exit code 2 | **PASS** |
| `build.sh trig` | `Sdtrig` execute-match and store-match triggers: 4 tests covering hit and miss cases | **PASS** |
| `build.sh debug` | JTAG DTM + Debug Module: halt, GPR and memory read/write, resume, and single-step | **PASS** |
| `build.sh priv` | 24 SECURE-mode directed tests: U-mode traps, PMP load/store/AMO/fetch faults, Smepmp MML, trigger breakpoints/watchpoints, user-trap delegation, `mtvec` base mode | **24/24 PASS** |
| `build.sh axi` | AXI4-Lite master bridge against a slave BFM, including SLVERR fault injection | **PASS** |
| `build.sh fpga` | FPGA SoC simulation: UART startup banner and LED blink sequence | **PASS** |

---

## RISC-V Architectural Compliance

Run with `make arch` or `./build.sh arch`. Upstream test suite cloned on demand from [riscv-non-isa/riscv-arch-test](https://github.com/riscv-non-isa/riscv-arch-test).

| Suite | Scope | Tests | Result |
| :--- | :--- | :---: | :---: |
| **RV32I** | Base integer instructions: ALU, shifts, comparisons, branches, jumps, loads, stores | 38 | **38/38 PASS** |
| **RV32M** | Signed and unsigned multiply (`mul`, `mulh`, `mulhu`, `mulhsu`) and divide/remainder (`div`, `divu`, `rem`, `remu`) | 8 | **8/8 PASS** |
| **RV32C** | 16-bit compressed instructions, stack-pointer arithmetic, compressed loads/stores and jumps, reserved HINT encodings | 27 | **27/27 PASS** |
| **Zifencei** | Instruction-fetch fence (`FENCE.I`) — pipeline flush and refetch | 1 | **1/1 PASS** |
| **Privilege** | `ecall`, `ebreak` (with `mtval` PC capture), instruction misalignment (JAL, JALR, branches), hardware misaligned data accesses | 16 | **16/16 PASS** |
| **Total** | | **90** | **100% PASS** |

---

## RTOS Verification

Run with `make rtos-suite` or `./build.sh rtos-suite`. Reproduction guide: [`rtos/README.md`](rtos/README.md).

| Stage | What it checks | Result |
| :--- | :--- | :---: |
| **Stage 1: Baseline Demo** | Preemptive tick progression, producer/consumer queue ordering (items 1..8), counting semaphore, CPU-bound worker preemption. Negative control: disabling the timer interrupt stalls at item 1, proving preemption is load-bearing | **PASS** |
| **Stage 2: Smoke Suite** | Kernel init and multi-task creation, strict priority-based preemption, full register state preservation (`s0`–`s11` bit patterns preserved across context switches), queue FIFO and blocking, binary and counting semaphores, direct task notifications, `vTaskDelay` fidelity, stack high-water mark, safe heap limit rejection, 40 rapid ping-pong yields under asynchronous ticks | **PASS** |
| **Stage 3: Interrupts** | CLINT `mtime` hardware progression, timer wake accuracy, machine software interrupt (`MSIP`, `mcause 0x80000003`) vectoring and clearing, `vTaskNotifyGiveFromISR` task unblocking, 10 rapid competing interrupts under ticks without register or stack corruption | **PASS** |
| **Stage 4: Latency** | Cycle-accurate interrupt and scheduler latency over 20 iterations using the `mcycle` CSR. Interrupt latency: 63 cycles (min=max=63, jitter=0). Scheduler latency: 316–318 cycles (jitter=2). Results written to `rtos/timing_results.json` | **PASS** |
| **Stage 5: Stress & RTA** | Three-task fixed-priority workload with shared priority-inheritance mutex: task 1 (period 10 ms), task 2 (period 25 ms), task 3 (continuous background). Positive run: 0 deadline misses. Negative control: injected overload reliably produces 3 deadline misses | **PASS** |
| **Platform: MEIP** | Machine External Interrupt (`irq_ext`) is tied to ground in the SoC wrapper — no PLIC instantiated | **SKIPPED** |

---

## Benchmark Results

Measured in Verilator simulation at a 100 MHz equivalent clock.

### CoreMark

| Metric | Value |
| :--- | :--- |
| Iterations run | 100 |
| Cycles per iteration | 341,599 |
| Iterations/sec (at 100 MHz) | 292 |
| **CoreMark/MHz** | **2.92** |

### Dhrystone 2.1

| Metric | Value |
| :--- | :--- |
| Iterations run | 2,000,000 |
| Cycles per iteration | 450 |
| Dhrystones/sec (at 100 MHz) | 222,222 |
| DMIPS (at 100 MHz) | 126.48 |
| **DMIPS/MHz** | **1.26** |
