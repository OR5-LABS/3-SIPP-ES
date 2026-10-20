# FPGA Bring-up

The `fpga/` directory contains a small FPGA SoC wrapper around 3-SIPP-ESR plus
board constraints, for running the core on real hardware.

## What's included

```
fpga/
├── three_sipp_es_fpga.sv        FPGA SoC top (core + UART + GPIO/LED)
├── three_sipp_es_reset_sync.sv  reset synchroniser
├── tb_three_sipp_es_fpga.sv     simulation testbench (UART banner + LED blink)
└── arty_a7/                Digilent Arty A7 (Artix-7) project + XDC
```

## Simulating the FPGA SoC

Before touching hardware you can run the FPGA SoC in simulation — it boots a
small firmware image that prints a UART banner and blinks an LED:

```bash
./build.sh fpga
```

## Building for a board

Each board directory provides a filelist (`*.f`), a build script (`*.tcl`), and
a constraints file (`*.xdc`). With Vivado on your `PATH`:

```bash
cd fpga/arty_a7
vivado -mode batch -source three_sipp_es_arty_a7.tcl
```

The generated bitstream instantiates the core, a UART bridged to the board's
USB-UART, and LEDs/GPIO. Point a serial terminal at the board to see the boot
banner.

## Firmware

The bring-up firmware lives in [`sw/`](https://github.com/OR5-LABS/3-SIPP-ESR/tree/main/sw)
(`fpga_hello.S`, linker script, and a `build_fpga_hello.sh` helper). Replace it
with your own image to run application code on the board.
