# Memory Map

The reference SoC (`rtl/three_sipp_es_soc.sv`) wires the core to instruction and data
memory plus a small set of memory-mapped peripherals. The map is intentionally
minimal and easy to relocate for your own integration.

| Region | Role |
|--------|------|
| **IMEM** | instruction memory (loaded from a `.hex` image via `+IMEM=`) |
| **DRAM** | data memory / scratch |
| **CLINT** | core-local interruptor — `mtime` / `mtimecmp` (timer) + software-interrupt register, at the standard base `0x0200_0000` |
| **UART** | character-output console peripheral |
| **tohost** | test-completion handshake at `0x2000_0000` — a store of `1` signals PASS to the testbench |

## CLINT (timer)

The CLINT exposes a free-running `mtime` and a `mtimecmp` compare register.
When `mtime >= mtimecmp` the machine-timer interrupt (`mip.MTIP`) is raised.
This is the tick source used by the [FreeRTOS port](verification.md) and by the
timer-interrupt tests.

## UART

The UART is a minimal transmit console: writing a byte to its data register
emits a character (surfaced on the simulation console). It is the standard-
output path for the RTOS demo and bring-up firmware.

## Integrating your own map

The core presents a simple valid/ready instruction-fetch and load/store
interface; the SoC is just one way to wire it up. For a standard fabric, use the
[AXI4-Lite bridge](bus-integration.md). Peripheral bases are parameters/localparams
in `three_sipp_es_soc.sv` and can be relocated to suit your address plan.
