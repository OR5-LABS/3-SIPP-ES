# Dhrystone on 3-SIPP-ESR

This directory contains a bare-metal **Dhrystone 2.1** port for the **3-SIPP-ESR RV32IMC** processor, configured for RTL simulation in Verilator.

## Toolchain & Environment

The benchmark is compiled for a 32-bit RISC-V target with the `IMC` extensions (Integer, Multiply/Divide, Compressed instructions). 

- **Compiler**: RISC-V GCC Toolchain (e.g. `riscv-none-elf-gcc` or `riscv64-unknown-elf-gcc` 13.2+)
- **Simulator**: Verilator
- **Architecture**: `RV32IMC`
- **Compiler Flags**:
  
  ```bash
  -O2 -march=rv32imc -mabi=ilp32 -nostdlib -fno-pic -Wl,--no-relax
  ```

## Performance Results

3-SIPP-ESR achieves a score of **1.26 DMIPS/MHz** in cycle-accurate Verilator simulation.

- **Environment**: Verilator testbench (`tb_three_sipp_es`)
- **Execution**: 2,000,000 iterations (industry standard)
- **DMIPS/MHz**: 1.264

---

## Directory layout

```
dhrystone/
├── run_dhrystone.sh            Simulation run script (Verilator)
└── src/
    ├── dhry.h                  Dhrystone 2.1 header
    ├── dhry_1.c                Dhrystone 2.1 main body
    ├── dhry_2.c                Dhrystone 2.1 procedures
    ├── dhry_port.c             Bare-metal RISC-V port (UART + mtime timer + string helpers)
    ├── string.h                Freestanding string definitions
    ├── start.S                 CRT0: stack setup, BSS clear, _start → main
    ├── link.ld                 Linker script (IMEM @ 0x0, DRAM @ 0x8000_0000)
    └── build_dhrystone.sh      Low-level compiler driver (called by run_dhrystone.sh)
```

## Simulation flow

The simulation script compiles the firmware and runs it through the Verilator
`tb_three_sipp_es` model in one command. Results are printed to stdout.

### Quick start

> [!IMPORTANT]
> Before running the simulation benchmark on a fresh repository, you must first compile the Verilator simulator by running `make sim` or `./build.sh` in the root of the repository.

```bash
# Industry-standard 2 000 000 iterations (default)
./run_dhrystone.sh

# Custom iteration count
./run_dhrystone.sh 5000000
```

### How it works

1. Calls `src/build_dhrystone.sh <RUNS>` which cross-compiles with
   `-DNUMBER_OF_RUNS=<N> -DCLK_FREQ_HZ=100000000 -O2 -march=rv32imc`.
2. Converts the ELF to a `$readmemh`-compatible hex via `sw/bin2hex.py`.
3. Launches `../obj_dir/Vtb_three_sipp_es +IMEM=src/dhrystone.hex`.

## Porting notes

`src/dhry_port.c` provides the three hooks Dhrystone 2.1 requires:

| Symbol | Implementation |
|--------|---------------|
| `uart_putc(char)` | Polls `0x1000_0000` TX-busy bit, then writes |
| `dhr_printf(fmt, …)` | Minimal `%d %u %x %c %s` printf over UART |
| `read_mtime()` | Reads `mtime[31:0]` from CLINT at `0x0200_BFF8` |

The firmware computes elapsed cycles as `mtime_end − mtime_start` (mtime ticks
at `CLK_FREQ_HZ` in the 3-SIPP-ESR SoC) and derives DMIPS/MHz from there.
