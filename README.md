# 3-SIPP-ES

**3-SIPP-ES** is a compact, high-performance **3-stage pipelined RV32IMAC**
processor core. It executes instructions in a classic in-order
fetch / execute / memory-writeback pipeline with full result forwarding (no
load-use stall), and a dynamic branch predictor — delivering strong
per-clock throughput while staying small and easy to reason about.

The core targets embedded and control-plane roles that want more performance
than a minimal multi-cycle core without the area of an application processor:
microcontrollers, real-time controllers, smart peripherals, and FPGA soft
cores.

---

## Highlights

- **ISA:** `RV32IMACB_Zicsr_Zcb_Zbc_Zifencei`: RV32IMAC, the ratified `B` extension (`Zba`, `Zbb`, `Zbs`), `Zbc` carry-less multiply, `Zcb`, `Zicsr`, `Zifencei`
- **Pipeline:** 3-stage in-order with full W→X forwarding and no load-use stall (only multiply/divide and misaligned accesses stall)
- **Branch Prediction:** 256-entry gshare, 64-entry BTB, and RAS
- **Privilege & Security** (`SECURE` build): Machine and User modes, user-level trap delegation (from the withdrawn `N` extension draft, never ratified; `misa.N` is not set), and 8-region PMP with Smepmp (including machine mode lockdown)
- **Triggers** (both builds): two `Sdtrig` triggers (`mcontrol6` format), execute and load/store address match
- **Memory & Buses:** Hardware misaligned access, native bus, and AXI4-Lite master
- **Debug:** RISC-V external debug via JTAG (Debug Module and JTAG DTM report debug spec 0.13 (`dmstatus.version` = 2))
- **Software & RTOS:** Preemptive FreeRTOS port with UART console
- **Verification:** co-simulation of the smoke program against a golden RV32IM ISA model, an RVFI (riscv-formal interface) trace self-check, **100% pass (90/90) on the official RISC-V Architectural Compliance Test suite** (RV32I, M, C, Zifencei, Privilege), and self-checking directed tests


---

## Repository layout

```
three_sipp_es/
├── rtl/                 core RTL
│   ├── three_sipp_es_core.sv   3-stage pipeline + predictor + forwarding
│   ├── three_sipp_es_soc.sv    minimal SoC (IMEM/DRAM, CLINT, UART, tohost)
│   ├── three_sipp_es_debug.sv  JTAG DTM + RISC-V Debug Module
│   ├── three_sipp_es_axi_lite.sv  AXI4-Lite master bridge
│   ├── three_sipp_es_uart.sv   UART console peripheral
│   └── common/            shared, pre-verified datapath leaf cells
│                          (ALU, multiply/divide, register file, CSR file,
│                           immediate/branch units, decoder, RVC, PMP)
├── arch-test/          official RISC-V architectural compliance test suite & runner
├── tb/                  testbenches (smoke, RVFI, debug, priv, AXI-Lite, RTOS, arch)
├── tools/              golden ISA model + co-simulation driver
├── programs/           test-program builders
├── sw/                 assembly test programs & bring-up firmware
├── rtos/               FreeRTOS port (kernel, BSP, demo app)
├── fpga/               FPGA SoC + Arty A7
├── docs/               documentation site (MkDocs)
└── build.sh            build & test driver
```

## Requirements

- **Verilator 5+** for simulation
- **Python 3.10+** for the test-program builders and co-simulation
- a RISC-V GCC toolchain (`riscv-none-elf-*`) for the FPGA firmware; the FreeRTOS demo and the benchmarks also need its C library (newlib), as shipped in the xPack `riscv-none-elf-gcc`
- *(optional)* Vivado for the Arty A7 FPGA flows

## Build & test

```bash
make                # compile + self-checking smoke test (or ./build.sh)
make arch           # clone-on-demand + official RISC-V Architectural Compliance suite (90/90 PASS)
make rtos           # FreeRTOS preemptive multitasking demo + negative control
make rtos-suite     # FreeRTOS comprehensive verification suite (5 stages, JSON/JUnit output)
make clean          # clean simulation and build artifacts

# All build actions can also be executed directly via build.sh:
./build.sh          # compile + self-checking smoke test
./build.sh cosim    # + co-simulate against the golden ISA model
./build.sh rvfi     # RVFI (formal interface) self-check
./build.sh zcb      # directed Zcb test + its negative control
./build.sh trig     # trigger tests on the default (M-only) SoC
./build.sh debug    # JTAG / Debug-Module self-check
./build.sh priv     # SECURE config: M/U privilege, user-trap delegation, PMP, Smepmp + trigger tests
./build.sh axi      # AXI4-Lite master BFM test
./build.sh fpga     # FPGA SoC sim (UART banner + LED), needs a RISC-V GCC
./build.sh rtos     # FreeRTOS preemptive multitasking demo + negative control
./build.sh rtos-suite # FreeRTOS comprehensive verification suite (5 stages, JSON/JUnit output)
./build.sh arch     # official RISC-V Architectural Compliance suite (90/90 PASS)
./build.sh clean
./run_tests.sh      # all of the above except rtos/benchmarks, checked against tests/expected.txt
```

Every `build.sh` action exits non-zero when its testbench
reports a failure, a timeout, a mismatch or an error, or does not print its
PASS verdict. Tools are taken from `PATH`; set `RISCV_TC=/path/to/bin` to use a
specific `riscv-none-elf-*` or `riscv64-unknown-elf-*` toolchain.

## Test status

Results of `./run_tests.sh` (Verilator 5.020, RISC-V GCC 13.2), recorded in
`tests/expected.txt`:

| Test | What it checks | Result |
| :--- | :--- | :--- |
| `build.sh sim` | smoke program (ALU, M, branches, loads/stores, CSR, traps) | PASS |
| `build.sh cosim` | smoke program retire-by-retire against the golden RV32IM model | PASS |
| `build.sh rvfi` | RVFI trace invariants over the smoke program | PASS |
| `build.sh zcb` | directed Zcb test; the negative control fails as designed | PASS |
| `build.sh debug` | JTAG DTM + Debug Module: halt, GPR/memory access, resume, single-step | PASS |
| `build.sh trig` | trigger breakpoint/watchpoint tests (hit + miss controls) on the default SoC | PASS |
| `build.sh priv` | 24 directed SECURE-core tests: U-mode traps, PMP load/store/AMO/fetch faults, Smepmp MML, trigger breakpoints/watchpoints, user-trap delegation, `mtvec` mode | 24/24 PASS |
| `build.sh axi` | AXI4-Lite master bridge against a slave BFM, incl. SLVERR | PASS |
| `build.sh fpga` | FPGA SoC simulation: UART banner + LED | PASS |
| `build.sh arch` | official RISC-V Architectural Compliance Suite (RV32I, M, C, Zifencei, Privilege) | 90/90 PASS (100%) |

Run separately (need a RISC-V GCC): `./build.sh rtos` (FreeRTOS demo: PASS), `./build.sh rtos-suite` (full RTOS verification suite: PASS), `coremark/run_coremark.sh` (PASS, 100 iterations) and `dhrystone/run_dhrystone.sh` (PASS, 2,000,000 runs).

## RISC-V Architectural Compliance (`riscv-arch-test`)

3-SIPP-ES is verified against the official **RISC-V International Architectural Compliance Test Suite** (`riscv-arch-test` v2 / CTP standard) across unprivileged and privileged ISA specifications:

```bash
make arch               # clones on-demand, builds simulator & executes full 90-test suite
# or:
./build.sh arch         # compile simulator & execute full 90-test architectural test suite
```

Or run individual suites / specific tests directly via the automated multi-threaded test runner:

```bash
python3 arch-test/run_arch_test.py --suite I          # Base integer (38/38 PASS)
python3 arch-test/run_arch_test.py --suite M          # Multiply & divide (8/8 PASS)
python3 arch-test/run_arch_test.py --suite C          # Compressed instructions (27/27 PASS)
python3 arch-test/run_arch_test.py --suite Zifencei    # Instruction fetch fence (1/1 PASS)
python3 arch-test/run_arch_test.py --suite privilege   # Traps & misalignment (16/16 PASS)
python3 arch-test/run_arch_test.py --test jal-01       # Run individual test
```

### Architectural Verification Matrix

| Suite | Specification Scope & Instructions Tested | Tests Run | Result | Architectural Compliance Highlights |
| :--- | :--- | :---: | :---: | :--- |
| **RV32I** | Base Integer Instruction Set | 38 / 38 | **38/38 PASS** | ALU operations, shift logic, branches, wide jumps (`jal`/`jalr`), memory loads & stores |
| **RV32M** | Standard Integer Multiplication & Division | 8 / 8 | **8/8 PASS** | Signed/unsigned multiply (`mul`, `mulh`, `mulhu`, `mulhsu`) and division/remainder (`div`, `divu`, `rem`, `remu`) |
| **RV32C** | Standard Compressed Instructions | 27 / 27 | **27/27 PASS** | 16-bit compressed RVC instructions, stack pointer arithmetic, loads/stores, jumps, and reserved HINTs (`C.LUI`) |
| **Zifencei** | Instruction-Fetch Fence Extension | 1 / 1 | **1/1 PASS** | Self-modifying code synchronization via pipeline fetch invalidation and redirect to `seq_nx` |
| **Privilege** | Traps, System Calls & Alignment | 16 / 16 | **16/16 PASS** | `ecall`, `ebreak` (`mtval` PC tracking), 9 instruction misalign tests, and 5 hardware misaligned data access tests |
| **TOTAL** | | **90 / 90** | **100% PASS** | **100% Spec Compliant** |

#### Specification Highlights Verified:
- **`Zifencei` Pipeline Invalidation:** `FENCE.I` flushes the fetch stage and redirects instruction fetch to the sequential next PC (`fx_pc + 4`), ensuring self-modifying code correctly fetches updated instructions from memory.
- **Hardware Misaligned Data Accesses:** 3-SIPP-ES implements full native hardware misaligned load and store handling (`hw_data_misaligned_support=True`). Misaligned memory operations complete successfully without raising exceptions, as permitted by the RISC-V Unprivileged Specification.
- **RVC Hints:** Reserved encodings (such as `C.LUI rd=x0, nzimm!=0`) are executed as architectural NOPs rather than illegal instruction traps, strictly adhering to Table 16.5 & 16.7 of the RISC-V specification.
- **Breakpoint TVAL:** `ebreak` exceptions record the faulting instruction PC (`fx_pc`) in `mtval` per RISC-V Privileged Specification Section 3.1.17.

## FreeRTOS & Real-Time Verification

3-SIPP-ES has been verified as **RTOS-capable** through repeatable engineering tests across 5 verification stages:

```bash
./build.sh rtos         # quickstart FreeRTOS demo + tick negative control (PASS)
./build.sh rtos-suite   # full 5-stage verification battery (PASS)
```

| Verification Stage | Scope & Invariants Tested | Result |
| :--- | :--- | :---: |
| **Stage 1: Baseline Demo** | Preemption, queue FIFO (1..8), semaphores, negative control stall | **PASS** |
| **Stage 2: Smoke Suite** | 8 areas: multi-tasking, preemption, **register preservation (`s0`–`s11`)**, heap/stack safety | **PASS** |
| **Stage 3: Interrupts** | CLINT timer, software interrupt (`MSIP`), ISR task notifications, competing IRQs | **PASS** |
| **Stage 4: Latency** | Cycle-accurate measurement: $T_{\text{irq}} = 63\text{ cyc}$, $T_{\text{sched}} = 316\text{ cyc}$, jitter $\le 9\text{ cyc}$ | **PASS** |
| **Stage 5: Stress & RTA** | Mutex contention under load, Response-Time Analysis ($R_1 \le D_1$), overload detection | **PASS** |

Detailed reports, fixed-point response-time calculations, and machine-readable results:
* Quickstart & reproduction guide: [`rtos/README.md`](rtos/README.md)
* Comprehensive engineering report: [`docs/rtos-verification/report.md`](docs/rtos-verification/report.md)
* Machine results: [`docs/rtos-verification/results.json`](docs/rtos-verification/results.json) | [`docs/rtos-verification/results_junit.xml`](docs/rtos-verification/results_junit.xml)

## Known limitations

- The default SoC drops data-port stores to IMEM; build with
  `-DTHREE_SIPP_ES_IMEM_WRITABLE` (or set `IMEM_DATA_WRITE=1`) to allow them.
- Only direct `mtvec` mode is implemented (`mtvec.MODE` reads as 0).
- External interrupt line `irq_ext` (MEIP) is tied to ground in the current SoC wrapper (no PLIC instantiated).

## Performance & Benchmarks

3-SIPP-ES has been evaluated across industry-standard embedded benchmarks in simulation and bare-metal execution on physical FPGA silicon.

### CoreMark

> Cycle counts are measured in simulation (`coremark/run_coremark.sh`, 100 iterations; `dhrystone/run_dhrystone.sh`, 2,000,000 runs); per-second figures are computed for a 100 MHz clock. The Arty A7 board scripts run at 25 MHz.

| Metric | Result |
| :--- | :--- |
| Cycles / iteration | 341,599 |
| Iterations / Sec (computed for 100 MHz) | 292 |
| CoreMark / MHz | **2.92** |

### Dhrystone v2.1

| Metric | Result |
| :--- | :--- |
| Cycles / iteration | 338 |
| Dhrystones / sec (computed for 100 MHz) | 295,857 |
| DMIPS (computed for 100 MHz) | 168.39 |
| DMIPS / MHz | **1.68** |

---

## Running Benchmarks

> If you are on a fresh clone, you must build the Verilator simulator first by running `./build.sh` from the repository root.

### CoreMark

To compile and run CoreMark in Verilator simulation:

```bash
cd coremark && ./run_coremark.sh
```

To run on physical hardware (Arty A7-100T FPGA @ 25 MHz):
```bash
cd coremark && ./run_coremark_arty_a7.sh
```

### Dhrystone 2.1

To compile and run the industry-standard 2,000,000-iteration Dhrystone benchmark in simulation:

```bash
cd dhrystone && ./run_dhrystone.sh
```

To synthesize, program, and monitor on the Arty A7-100T board (@ 25 MHz):
```bash
cd dhrystone && ./run_dhrystone_arty_a7.sh
```

---

## FPGA Resource Utilization

Synthesis and implementation were performed using **AMD Vivado 2023.2** targeting the **Xilinx Artix-7 100T** FPGA (`xc7a100tcsg324-1`) on the Digilent Arty A7 evaluation board.

### Implementation Metrics (Post-Route)

| Component / Target | Slice LUTs | Logic LUTs | LUTRAM | Registers (FF) | DSP48E1 | Block RAM (RAMB36) | Timing Slack (WNS) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **3-SIPP-ES Reference SoC** | **15,895** (25.1%) | 7,559 | 8,336 | **2,150** (1.7%) | **12** (5.0%) | **0** (0.0%) | **+1.994 ns** @ 25 MHz |

---

## Configurations

3-SIPP-ES ships in two build-time configurations, selected by a parameter /
define:

| Configuration | LUTs | FFs | DSPs | BRAMs |
|---------------|------|-----|------|-------|
| Default (Machine mode only) | 6,028 | 2,090 | 12 | 0 |
| SECURE (M+U, PMP/ePMP, ECC) | 8,647 | 2,993 | 12 | 0 |

Enable the secure configuration with the `SECURE` RTL parameter, or at compile
time with `-DTHREE_SIPP_ES_SECURE`.


## License

Released under the [MIT License](LICENSE).
