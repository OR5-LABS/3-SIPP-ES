# Debug

3-SIPP-ESR implements **RISC-V External Debug**: a JTAG Transport Module (DTM)
plus a Debug Module (DM) that let an external debugger halt the core and inspect
or modify its state. Hardware triggers add self-hosted breakpoints and
watchpoints.

## Debug Module

- **Halt / resume** — request a halt at an instruction boundary; the core enters
  debug mode, saves the PC to `dpc`, sets `dcsr.cause`, and parks. `resume`
  restores `dpc` and continues.
- **Single-step** — execute one instruction and re-enter debug.
- **Register access** — read and write any GPR (and CSRs) through the abstract
  command interface while halted.
- **`ebreak`** — with the relevant `dcsr` bit set, `ebreak` enters debug mode
  instead of trapping.

The DTM/DM (`rtl/three_sipp_es_debug.sv`) presents a standard JTAG interface, so
OpenOCD + GDB drive it in the usual way. `build.sh debug` runs a self-check that
halts the core, reads a computed GPR, writes a new value, resumes, and confirms
the program continues with the debug-written value.

## Hardware triggers (`SECURE`)

The `SECURE` build adds `mcontrol6` triggers:

- **Execute (PC-match) breakpoint** — fire when the PC matches `tdata2`.
- **Load/store (address-match) watchpoint** — fire when a data access matches.

A trigger raises a breakpoint exception (cause 3, `mtval` = the matched PC or
address) or enters debug mode. Triggers are programmed through `tselect` /
`tdata1` / `tdata2` and enumerated via `tinfo`. The `build.sh priv` tests cover
both trigger kinds with near-miss negative controls.
