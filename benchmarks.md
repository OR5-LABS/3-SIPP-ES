# Benchmark Reports

Detailed results from running CoreMark and Dhrystone 2.1 on the 3-SIPP-ESR core. Measurements are taken in Verilator simulation at a 100 MHz equivalent clock. The Arty A7 board scripts run the same programs on physical hardware at 25 MHz.

Cycle counts are extracted directly from the benchmark output printed over the UART console. Per-second and per-MHz figures are derived from those cycle counts.

---

## Reproducing the Results

Build the Verilator simulator first (only needed once):

```bash
make          # or: ./build.sh
```

Then run the benchmarks:

```bash
cd coremark  && ./run_coremark.sh               # simulation
cd coremark  && ./run_coremark_arty_a7.sh       # Arty A7 @ 25 MHz

cd dhrystone && ./run_dhrystone.sh              # simulation
cd dhrystone && ./run_dhrystone_arty_a7.sh      # Arty A7 @ 25 MHz
```

---

## CoreMark

CoreMark is an industry-standard benchmark designed to stress integer computation — it exercises list processing, matrix operations, and finite-state machine transitions without touching floating point. The score is normalized to clock frequency so cores can be compared regardless of how fast they are clocked.

The port uses the bare-metal `barebones` configuration, compiled at `-O3` with the xPack `riscv-none-elf-gcc` toolchain. 100 iterations are run to meet the minimum valid run requirement.

| Metric | Simulation (100 MHz eq.) |
| :--- | :---: |
| Iterations run | 100 |
| Cycles per iteration | 341,599 |
| Iterations / sec (at 100 MHz) | 292 |
| **CoreMark / MHz** | **2.92** |

### Compiler flags

```
-O3 -march=rv32imac_zicsr_zcb -mabi=ilp32 -fno-common -ffunction-sections -fdata-sections
```

---

## Dhrystone 2.1

Dhrystone is a synthetic workload that focuses on integer and string operations and has historically been used as a proxy for general-purpose CPU performance. The DMIPS score is derived by dividing the Dhrystones/sec figure by 1757 (the VAX 11/780 reference), which gives DMIPS, then normalized to clock frequency.

The port runs 2,000,000 iterations to reduce measurement noise from the simulation clock model.

| Metric | Simulation (100 MHz eq.) |
| :--- | :---: |
| Iterations run | 2,000,000 |
| Cycles per iteration | 338 |
| Dhrystones / sec (at 100 MHz) | 295,857 |
| DMIPS (at 100 MHz) | 168.39 |
| **DMIPS / MHz** | **1.68** |

### Compiler flags

```
-O3 -march=rv32imac_zicsr_zcb -mabi=ilp32 -fno-common -ffunction-sections -fdata-sections
```

---

## Notes

- Results are from Verilator simulation, which is cycle-accurate. Physical FPGA results at 25 MHz will match in cycle count but differ in wall-clock time.
- Neither benchmark uses a data cache or instruction cache — all accesses go to the synchronous single-cycle IMEM and DRAM in the SoC model. A cached configuration would yield significantly higher scores.
- The DSP48E1 blocks used by the hardware multiplier are reflected in the cycle counts for multiply-heavy routines in both benchmarks.
