# 3-SIPP-ES Technical Documentation

## Table of Contents
- [1. Introduction](#1-introduction)
  - [1.1. What you get](#11-what-you-get)
  - [1.2. Where to start](#12-where-to-start)
  - [1.3. License](#13-license)
- [2. Getting Started](#2-getting-started)
  - [2.1. Prerequisites](#21-prerequisites)
  - [2.2. Build and run the smoke test](#22-build-and-run-the-smoke-test)
  - [2.3. The other test targets](#23-the-other-test-targets)
  - [2.4. Rebuilding the test programs](#24-rebuilding-the-test-programs)
  - [2.5. Next steps](#25-next-steps)
- [3. Architecture](#3-architecture)
  - [3.1. Pipeline](#31-pipeline)
  - [3.2. Hazard handling](#32-hazard-handling)
  - [3.3. Datapath leaf cells](#33-datapath-leaf-cells)
- [4. Branch Prediction](#4-branch-prediction)
  - [4.1. Components](#41-components)
  - [4.2. Operation](#42-operation)
  - [4.3. Verification](#43-verification)
- [5. Instruction Set](#5-instruction-set)
  - [5.1. Base and standard extensions](#51-base-and-standard-extensions)
  - [5.2. Bit-manipulation (`B`)](#52-bit-manipulation-b)
  - [5.3. Code size (`Zcb`)](#53-code-size-zcb)
  - [5.4. Atomics (`A`)](#54-atomics-a)
  - [5.5. Misaligned access](#55-misaligned-access)
  - [5.6. Privileged ISA](#56-privileged-isa)
  - [5.7. Conformance](#57-conformance)
- [6. Configuration Reference](#6-configuration-reference)
  - [6.1. Configurations](#61-configurations)
  - [6.2. Always present](#62-always-present)
  - [6.3. Optional / configurable](#63-optional--configurable)
  - [6.4. Build-driver targets](#64-build-driver-targets)
- [7. Privilege & Security](#7-privilege--security)
  - [7.1. Privilege modes (`SECURE`)](#71-privilege-modes-secure)
  - [7.2. Physical Memory Protection (PMP)](#72-physical-memory-protection-pmp)
  - [7.3. What the tests prove](#73-what-the-tests-prove)
- [8. Control & Status Registers](#8-control--status-registers)
  - [8.1. Machine-mode CSRs](#81-machine-mode-csrs)
  - [8.2. User-trap (`N`) CSRs — `SECURE`](#82-user-trap-n-csrs--secure)
  - [8.3. Protection CSRs — `SECURE`](#83-protection-csrs--secure)
  - [8.4. Debug-trigger CSRs — `SECURE`](#84-debug-trigger-csrs--secure)
  - [8.5. Access rules](#85-access-rules)
- [9. Traps & Interrupts](#9-traps--interrupts)
  - [9.1. Synchronous exceptions](#91-synchronous-exceptions)
  - [9.2. Interrupts](#92-interrupts)
  - [9.3. Delegation to User mode (`N`)](#93-delegation-to-user-mode-n)
- [10. Memory Map](#10-memory-map)
  - [10.1. CLINT (timer)](#101-clint-timer)
  - [10.2. UART](#102-uart)
  - [10.3. Integrating your own map](#103-integrating-your-own-map)
- [11. Bus Integration](#11-bus-integration)
  - [11.1. Native interface](#111-native-interface)
  - [11.2. AXI4-Lite bridge](#112-axi4-lite-bridge)
    - [11.2.1. Verification](#1121-verification)
- [12. Debug](#12-debug)
  - [12.1. Debug Module](#121-debug-module)
  - [12.2. Hardware triggers (`SECURE`)](#122-hardware-triggers-secure)
- [13. Verification](#13-verification)
  - [13.1. Self-checking tests](#131-self-checking-tests)
  - [13.2. Golden co-simulation](#132-golden-co-simulation)
  - [13.3. RVFI (RISC-V Formal Interface)](#133-rvfi-risc-v-formal-interface)
  - [13.4. Debug-Module self-check](#134-debug-module-self-check)
  - [13.5. Constrained-random testing](#135-constrained-random-testing)
  - [13.6. RTOS integration test](#136-rtos-integration-test)
  - [13.7. Performance](#137-performance)
- [14. FPGA Bring-up](#14-fpga-bring-up)
  - [14.1. What's included](#141-whats-included)
  - [14.2. Simulating the FPGA SoC](#142-simulating-the-fpga-soc)
  - [14.3. Building for a board](#143-building-for-a-board)
  - [14.4. Firmware](#144-firmware)


---

## 1. Introduction

**3-SIPP-ES** is a compact, high-performance **3-stage pipelined RV32IMAC**
processor core. It runs a classic in-order fetch / execute / memory-writeback
pipeline with full result forwarding (no load-use stall) and a
dynamic branch predictor — giving strong per-clock throughput in a small,
readable design.

It is built for embedded and control-plane roles that want more performance
than a minimal multi-cycle core without the area of an application processor:
microcontrollers, real-time controllers, smart peripherals, and FPGA soft
cores.

### 1.1. What you get

- **RV32IMAC** base, plus the **`B`** bit-manipulation set (`Zba`/`Zbb`/`Zbc`/`Zbs`)
  and **`Zcb`** code-size instructions, with `Zicsr`.
- A **3-stage in-order pipeline** with full forwarding and no load-use stall.
- A **dynamic branch predictor** — gshare direction predictor + BTB + return
  address stack.
- Optional **M/U/N privilege**, an **8-region PMP** (with ePMP), and hardware
  **debug triggers** in the `SECURE` configuration.
- Hardware **misaligned** load/store support.
- **RISC-V External Debug** (JTAG DTM + Debug Module).
- An **AXI4-Lite** bus wrapper.
- A ready-to-run **FreeRTOS** port.
- A deep **verification** flow: self-checking tests, golden-model
  co-simulation, RVFI, a Debug-Module self-check, and constrained-random
  testing.
- ~**2.92 CoreMark/MHz** on RTL (no caches).

### 1.2. Where to start

- New here? Read [Getting Started](getting-started.md) to build and run the
  self-checking tests.
- Want the microarchitecture? See [Architecture](architecture.md) and
  [Branch Prediction](branch-prediction.md).
- Integrating it into an SoC? See [Memory Map](memory-map.md),
  [Bus Integration](bus-integration.md), and [Debug](debug.md).

### 1.3. License

3-SIPP-ES is released under the [MIT License](https://opensource.org/licenses/MIT).


## 2. Getting Started

### 2.1. Prerequisites

- **Verilator 5+** — the simulator.
- **Python 3.10+** — the test-program builders and the golden co-simulation
  driver.
- *(optional)* a **RISC-V GCC** toolchain (`riscv-none-elf-gcc`) to rebuild the
  assembly test programs from source; prebuilt `.hex` images are included so
  this is not required to run the tests.
- *(optional)* **Vivado** for the FPGA flows.

### 2.2. Build and run the smoke test

```bash
./build.sh
```

Expected output:

```
[TB] Loading IMEM from: programs/build/smoke.hex
[TB] Reset released
[TB] tohost write: 0x00000001 ...
[TB] PASS
```

### 2.3. The other test targets

| Command | What it does |
|---------|--------------|
| `build.sh` (default) | compile the core + SoC, run the self-checking smoke test |
| `build.sh cosim` | run smoke, then lock-step co-simulate against the golden RV32IM ISA model |
| `build.sh rvfi` | build the RVFI (RISC-V Formal Interface) self-check |
| `build.sh debug` | JTAG / Debug-Module self-check (halt / GPR access / resume) |
| `build.sh priv` | `SECURE` config: M/U/N privilege + PMP + trigger directed tests |
| `build.sh axi` | AXI4-Lite master bridge, exercised against a slave-memory BFM |
| `build.sh rtos` | build and run the FreeRTOS preemptive multitasking demo |
| `build.sh clean` | remove build artifacts |

### 2.4. Rebuilding the test programs

The `programs/*.py` builders emit the `.hex` images the testbenches load. They
run automatically as part of `build.sh`. If you have a RISC-V toolchain and want
to regenerate the assembly programs under `sw/`, point `RISCV_TC` at your
toolchain `bin/` directory.

### 2.5. Next steps

- [Architecture](architecture.md) — the pipeline and datapath.
- [Instruction Set](isa.md) — supported extensions.
- [Verification](verification.md) — how the core is checked.


## 3. Architecture

3-SIPP-ES is a **3-stage, in-order, single-issue** pipeline. One instruction is
fetched, executed, and retired per cycle in the common case; variable-latency
operations (multiply, divide, misaligned access, atomics) extend transparently
through a small set of stall conditions.

### 3.1. Pipeline

```
   IF                    EX                        MEM / WB
+---------+          +--------------+          +------------------+
| fetch + |  ----->  | decode +     |  ----->  | data memory +    |
| predict |          | operand read |          | CSR + writeback  |
| (BTB/   |  <-----  | ALU / branch |  <-----  | (commit, trap)   |
|  gshare)|  redirect|  mul/div/AMO |  forward |                  |
+---------+          +--------------+          +------------------+
```

- **IF — instruction fetch + predict.** Fetches the next instruction (32-bit
  or a 16-bit compressed form expanded by the RVC decoder) and consults the
  branch predictor for the next PC. On a predicted-taken branch the front end
  redirects immediately.
- **EX — decode, operand fetch, execute.** Decodes the instruction, reads the
  register file, resolves operands through the forwarding network, and performs
  the ALU / bit-manipulation / branch operation. Multiply/divide is issued to
  the M-unit here; atomics and misaligned accesses drive the memory sequencer.
- **MEM/WB — memory, CSR, writeback.** Performs the data-memory access,
  handles CSR reads/writes, resolves traps precisely, and writes the result
  back to the register file.

### 3.2. Hazard handling

3-SIPP-ES has no scoreboard — correctness comes from a compact set of
mechanisms:

- **Forwarding network:** results are bypassed from later stages back to EX so
  back-to-back dependent instructions do not stall. Because load data produced
  in the memory stage is available to a dependent instruction in EX on the same
  cycle, the forwarding network covers load-use hazards too — there is **no
  load-use stall**.
- **Multi-cycle freeze:** multiply/divide, the two-beat misaligned access, and
  the atomic read-modify-write hold the pipeline until they complete.
- **Redirect / flush:** a branch misprediction (or a trap) flushes the wrongly
  fetched instructions and redirects the front end.

### 3.3. Datapath leaf cells

The reusable datapath blocks live in [`rtl/common/`](https://github.com/OR5-LABS/3-SIPP-ES/tree/main/rtl/common):
the ALU (with the `B` bit-manipulation ops), the multiply/divide unit, the
register file, the CSR file, the immediate generator, the branch comparator,
the instruction decoder, the RVC (compressed) expander, and the PMP checker.
The core, SoC, UART, AXI4-Lite bridge, and Debug Module live in `rtl/`.

See [Branch Prediction](branch-prediction.md) for the predictor, and
[Instruction Set](isa.md) for the supported ISA.


## 4. Branch Prediction

3-SIPP-ES has a **dynamic branch predictor** in the fetch stage. Because branch
resolution otherwise costs a pipeline bubble on every taken branch, prediction
is the single largest contributor to the core's throughput (and the main reason
it reaches ~2.92 CoreMark/MHz).

### 4.1. Components

- **BTB — Branch Target Buffer.** A direct-mapped table that remembers the
  targets of previously-taken control-flow instructions, so the target is known
  in the fetch stage. The index is **halfword-granular** (it includes `pc[1]`)
  so compressed (16-bit) instructions do not alias in the BTB.
- **gshare direction predictor.** A table of 2-bit saturating counters indexed
  by the fetch PC XOR-ed with a global branch-history register, predicting
  taken / not-taken for conditional branches.
- **RAS — Return Address Stack.** A small stack pushed on calls
  (`jal`/`jalr` writing `x1`/`x5`) and popped on returns, so function returns
  are predicted accurately without polluting the BTB.

### 4.2. Operation

On each fetch, the predictor produces a next-PC. A predicted-taken branch
redirects the front end in the same cycle. When the branch actually resolves in
the execute stage:

- a **correct** prediction costs nothing — the pipeline flows;
- a **misprediction** flushes the wrongly-fetched instructions, redirects the
  front end to the correct PC, and updates the predictor tables and global
  history.

Prediction is a pure performance optimisation: mispredicts are always corrected,
so architectural results are identical with or without the predictor.

### 4.3. Verification

The predictor is exercised by the smoke and CoreMark workloads and is covered by
the golden-model co-simulation and the RVFI self-check — the committed
instruction stream is identical to the golden model regardless of prediction
outcomes. See [Verification](verification.md).


## 5. Instruction Set

3-SIPP-ES implements **RV32IMAC** plus the `B` bit-manipulation and `Zcb`
code-size extensions.

### 5.1. Base and standard extensions

| Extension | Description |
|-----------|-------------|
| **RV32I** | base 32-bit integer instruction set |
| **M** | integer multiply / divide (`MUL`, `MULH*`, `DIV*`, `REM*`) |
| **A** | atomics — `LR.W` / `SC.W` and the nine `AMO<op>.W` operations |
| **C** | compressed 16-bit instructions |
| **Zicsr** | control-and-status register access |

### 5.2. Bit-manipulation (`B`)

The full ratified `B` set is supported:

| Sub-extension | Instructions |
|---------------|--------------|
| **Zba** | address generation — `SH1ADD`, `SH2ADD`, `SH3ADD` |
| **Zbb** | basic bit-manip — `ANDN`, `ORN`, `XNOR`, `CLZ`, `CTZ`, `CPOP`, `MIN[U]`, `MAX[U]`, `SEXT.B/H`, `ZEXT.H`, `ROL`, `ROR[I]`, `ORC.B`, `REV8` |
| **Zbc** | carry-less multiply — `CLMUL`, `CLMULH`, `CLMULR` |
| **Zbs** | single-bit — `BCLR`, `BEXT`, `BINV`, `BSET` (+ immediates) |

### 5.3. Code size (`Zcb`)

The `Zcb` compressed encodings shrink common sequences: compressed sub-word
loads/stores (`c.lbu`, `c.lhu`, `c.lh`, `c.sb`, `c.sh`), and compressed
`c.zext.*` / `c.sext.*` / `c.not` / `c.mul`.

### 5.4. Atomics (`A`)

`LR.W` sets a word reservation; `SC.W` succeeds only if the reservation is
still valid; the nine `AMO<op>.W` variants
(`swap`, `add`, `and`, `or`, `xor`, `min`, `max`, `minu`, `maxu`) perform a
read-modify-write to a naturally-aligned word.

### 5.5. Misaligned access

Naturally-misaligned loads and stores are handled **in hardware** as a
two-beat memory sequence rather than trapping.

### 5.6. Privileged ISA

Machine mode is always present. The `SECURE` configuration adds User mode and
the `N` user-trap extension. See
[Privilege & Security](privilege-and-security.md) and [CSRs](csrs.md).

### 5.7. Conformance

The RV32IMAC(+C) behaviour is checked against the official RISC-V unit tests and
lock-step against a golden RV32IM ISA model — see [Verification](verification.md).


## 6. Configuration Reference

3-SIPP-ES is configured at build time. The most important switch is the `SECURE`
configuration; individual features can be included or omitted to trade area for
capability.

### 6.1. Configurations

| Configuration | Privilege | PMP / ePMP | Debug triggers | Use case |
|---------------|-----------|------------|----------------|----------|
| **Default** | Machine only | — | — | smallest footprint |
| **`SECURE`** | Machine + User + N | 8-region PMP + ePMP | breakpoint / watchpoint | isolation & introspection |

Enable the secure configuration with the `SECURE` RTL parameter, or at compile
time with `-DTHREE_SIPP_ES_SECURE`.

### 6.2. Always present

- 3-stage in-order pipeline with full forwarding (no load-use stall)
- RV32IMAC + `B` (Zba/Zbb/Zbc/Zbs) + `Zcb`
- gshare + BTB + RAS branch predictor
- hardware misaligned load/store
- machine-mode traps, timers, and interrupts
- RISC-V External Debug (JTAG DTM + Debug Module)
- native memory interface

### 6.3. Optional / configurable

| Feature | How | Notes |
|---------|-----|-------|
| User + N privilege | `SECURE` | full M/U/N split with trap delegation |
| PMP + ePMP | `SECURE` | 8 regions, TOR/NA4/NAPOT, `mseccfg` |
| Debug triggers | `SECURE` | `mcontrol6` execute + load/store match |
| AXI4-Lite bus | instantiate `three_sipp_es_axi_lite` | optional; default SoC uses the native interface |
| FreeRTOS | `rtos/` | preemptive RTOS port + demo |

### 6.4. Build-driver targets

| Target | Meaning |
|--------|---------|
| `sim` | compile + smoke (default) |
| `cosim` | + golden-model co-simulation |
| `rvfi` | RVFI self-check |
| `debug` | JTAG / Debug-Module self-check |
| `priv` | `SECURE`: M/U/N + PMP + trigger tests |
| `axi` | AXI4-Lite master BFM test |
| `rtos` | FreeRTOS preemptive multitasking demo |
| `clean` | remove build artifacts |

See [Getting Started](getting-started.md) to run them.


## 7. Privilege & Security

3-SIPP-ES runs in **Machine mode** by default. The **`SECURE`** configuration
adds a full privilege split and memory protection, turning the core into a small
isolation-capable processor suitable for trusted control planes.

### 7.1. Privilege modes (`SECURE`)

- **Machine (M)** — full access; the reset mode and trap-handling mode.
- **User (U)** — reduced privilege for application code; M-only CSR access and
  privileged instructions trap to Machine mode.
- **N (user traps)** — selected exceptions can be *delegated* to User mode via
  `medeleg`, handled through the user trap CSRs (`utvec`/`uepc`/`ucause`/…) and
  returned with `URET`, all without leaving User mode.

`mret` drops to the privilege recorded in `mstatus.MPP`; a U-mode `ecall`
returns to Machine mode with cause 8.

### 7.2. Physical Memory Protection (PMP)

The `SECURE` core includes an **8-region PMP**:

- **Matching:** TOR (top-of-range), NA4, and NAPOT.
- **Permissions:** read / write / execute, checked on instruction fetch and on
  load/store *after* address generation.
- **Locking:** locked entries apply to Machine mode too.
- **ePMP (`mseccfg`):** enhanced-PMP semantics (Machine-mode whitelisting,
  rule-lock bypass) for a hardened memory model.

A U-mode access that violates a PMP region raises a precise access fault
(instruction = cause 1, load = cause 5, store/AMO = cause 7) with the faulting
address in `mtval`; the Machine handler can inspect and recover.

### 7.3. What the tests prove

The `build.sh priv` target runs directed tests that demonstrate, each with a
load-bearing negative control:

- entering User mode and returning via `ecall` (correct cause);
- a U-mode M-CSR access trapping as illegal;
- a PMP store violation and an instruction-fetch violation faulting precisely,
  then recovering;
- an `N`-delegated user trap vectoring to `utvec` and returning with `URET`.

See [Debug](debug.md) for the hardware trigger (breakpoint/watchpoint) support,
which shares the `SECURE` build.


## 8. Control & Status Registers

3-SIPP-ES implements the machine-mode CSRs required for trap handling, timers,
and identification, plus the supervisor-of-user (`N`) and protection CSRs in the
`SECURE` configuration.

### 8.1. Machine-mode CSRs

| CSR | Purpose |
|-----|---------|
| `misa` | ISA identification (RV32 + I/M/A/C + B; U/N when `SECURE`) |
| `mstatus` | global interrupt-enable, previous privilege (`MPP`), `MPRV` |
| `mtvec` | machine trap-vector base |
| `mepc` | machine exception PC |
| `mcause` | machine trap cause |
| `mtval` | machine trap value (faulting address / instruction) |
| `mie` / `mip` | interrupt-enable / interrupt-pending |
| `mscratch` | scratch register for trap handlers |
| `mcycle` / `minstret` | cycle and retired-instruction counters |
| `mvendorid` / `marchid` / `mimpid` / `mhartid` | identification |

### 8.2. User-trap (`N`) CSRs — `SECURE`

When the `N` user-trap extension is enabled, the corresponding user-level trap
CSRs are provided: `ustatus`, `uie`, `uip`, `utvec`, `uepc`, `ucause`, `utval`,
`uscratch`, together with `medeleg` / `mideleg` for delegating traps to User
mode and the `URET` instruction. See
[Privilege & Security](privilege-and-security.md).

### 8.3. Protection CSRs — `SECURE`

The 8-region PMP is configured through the standard `pmpcfg0..3` and
`pmpaddr0..15` CSRs, with `mseccfg` for the enhanced-PMP (ePMP) rules.

### 8.4. Debug-trigger CSRs — `SECURE`

Hardware triggers use `tselect`, `tdata1` (`mcontrol6`), `tdata2`, and `tinfo`.
See [Debug](debug.md).

### 8.5. Access rules

CSRs enforce standard privilege and read/write-legality checks: an access to a
machine-mode CSR from User mode, or a write to a read-only CSR, raises an
illegal-instruction exception.


## 9. Traps & Interrupts

3-SIPP-ES implements **precise** traps: when an instruction faults, no later
instruction has changed architectural state, and the trapping instruction's PC
is recorded in `mepc` (or `uepc` for a delegated user trap).

### 9.1. Synchronous exceptions

| Cause | Condition |
|-------|-----------|
| 0 | instruction address misaligned |
| 1 | instruction access / PMP fault |
| 2 | illegal instruction |
| 3 | breakpoint (`EBREAK`, or a hardware trigger) |
| 5 | load access / PMP fault |
| 7 | store/AMO access / PMP fault |
| 8 | environment call from User mode (`SECURE`) |
| 11 | environment call from Machine mode |

### 9.2. Interrupts

The core accepts the standard machine interrupt lines, gated by `mstatus.MIE`
and `mie`:

- **Machine timer** (`MTIP`) — driven by the CLINT `mtime` / `mtimecmp`.
- **Machine software** (`MSIP`) — the CLINT software-interrupt register.
- **Machine external** (`MEIP`) — from a platform interrupt source.

On an accepted trap the core saves the PC to `mepc`, records the cause in
`mcause` (and the faulting value in `mtval`), updates `mstatus`, and vectors to
`mtvec`. `MRET` restores the pre-trap state and resumes.

### 9.3. Delegation to User mode (`N`)

In the `SECURE` configuration with the `N` extension, selected exceptions can be
delegated to User mode via `medeleg`. A delegated trap vectors to `utvec`, saves
`uepc` / `ucause` / `utval`, keeps the core in User mode, and returns with
`URET`. This lets a user-level runtime handle its own traps without entering
Machine mode.


## 10. Memory Map

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

### 10.1. CLINT (timer)

The CLINT exposes a free-running `mtime` and a `mtimecmp` compare register.
When `mtime >= mtimecmp` the machine-timer interrupt (`mip.MTIP`) is raised.
This is the tick source used by the [FreeRTOS port](verification.md) and by the
timer-interrupt tests.

### 10.2. UART

The UART is a minimal transmit console: writing a byte to its data register
emits a character (surfaced on the simulation console). It is the standard-
output path for the RTOS demo and bring-up firmware.

### 10.3. Integrating your own map

The core presents a simple valid/ready instruction-fetch and load/store
interface; the SoC is just one way to wire it up. For a standard fabric, use the
[AXI4-Lite bridge](bus-integration.md). Peripheral bases are parameters/localparams
in `three_sipp_es_soc.sv` and can be relocated to suit your address plan.


## 11. Bus Integration

3-SIPP-ES presents a simple native memory interface out of the core, and ships an
**AXI4-Lite** bridge for dropping the core into a standard SoC fabric.

### 11.1. Native interface

The core drives a lightweight valid/ready instruction-fetch port and a
load/store port with byte strobes. The reference SoC (`three_sipp_es_soc.sv`) wires
these directly to on-chip memories and peripherals — the smallest, lowest-latency
option.

### 11.2. AXI4-Lite bridge

`rtl/three_sipp_es_axi_lite.sv` is an **AXI4-Lite master** that adapts the core's
load/store interface to the five AXI channels (AW / W / B / AR / R) with
`VALID`/`READY` handshakes and byte strobes (`WSTRB`). It carries one
outstanding transaction and propagates the AXI response (`OKAY` / `SLVERR`) back
to the core.

The bridge is an **optional** standalone block: the default SoC and the
compliance path never instantiate it, so enabling AXI never changes the core's
behaviour.

#### 11.2.1. Verification

`build.sh axi` exercises the bridge against a WSTRB-aware slave-memory BFM that
injects wait states on every channel, checking:

- word and sub-word (byte / half, via `WSTRB`) read/write integrity;
- untouched-cell preservation;
- error handling — a poisoned address returns `SLVERR` on both read and write,
  with a load-bearing negative control (expecting `OKAY` there fails).

Expected output:

```
AXI: PASS
```

Use the AXI bridge to attach 3-SIPP-ES to an AXI interconnect, or keep the native
interface for a tightly-coupled memory subsystem.


## 12. Debug

3-SIPP-ES implements **RISC-V External Debug**: a JTAG Transport Module (DTM)
plus a Debug Module (DM) that let an external debugger halt the core and inspect
or modify its state. Hardware triggers add self-hosted breakpoints and
watchpoints.

### 12.1. Debug Module

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

### 12.2. Hardware triggers (`SECURE`)

The `SECURE` build adds `mcontrol6` triggers:

- **Execute (PC-match) breakpoint** — fire when the PC matches `tdata2`.
- **Load/store (address-match) watchpoint** — fire when a data access matches.

A trigger raises a breakpoint exception (cause 3, `mtval` = the matched PC or
address) or enters debug mode. Triggers are programmed through `tselect` /
`tdata1` / `tdata2` and enumerated via `tinfo`. The `build.sh priv` tests cover
both trigger kinds with near-miss negative controls.


## 13. Verification

3-SIPP-ES is verified with a layered flow — from quick self-checking smoke tests
to lock-step co-simulation against an independent golden model and a formal
interface.

### 13.1. Self-checking tests

Every testbench is self-checking: it loads a program, runs it, and asserts an
expected result, signalling PASS/FAIL through the `tohost` handshake. The
directed programs (privilege, PMP, triggers, atomics, misaligned, bit-manip,
`Zcb`) each pair a positive test with a **load-bearing negative control**, so a
check that silently stops working is caught.

### 13.2. Golden co-simulation

`build.sh cosim` runs the smoke program on the RTL **and** on an independent
golden **RV32IM ISA model** (`tools/golden_rv32im.py`), comparing the committed
instruction stream retire-by-retire (PC, instruction, register writes). Any
divergence is reported at the first mismatching instruction.

```
[cosim] MATCH — retires identical. RTL is ISA-correct.
```

### 13.3. RVFI (RISC-V Formal Interface)

`build.sh rvfi` exposes an RVFI retirement port and checks the standard formal
invariants over a real run — instruction-order monotonicity, `x0` always zero,
PC continuity, and that the retired instruction matches memory. A corrupted-field
negative control confirms the checker actually fires.

### 13.4. Debug-Module self-check

`build.sh debug` halts the core over the Debug Module, reads and writes a GPR,
resumes, and confirms the program continues with the debug-written value.

### 13.5. Constrained-random testing

Beyond the directed suite, 3-SIPP-ES is exercised by a constrained-random flow
that generates thousands of legal RV32IMAC programs and lock-steps each against
the golden model, catching corner cases the directed tests do not reach.

### 13.6. RTOS integration test

`build.sh rtos` boots a real **FreeRTOS** image on the SoC and asserts a
multi-task transcript (queue + semaphore + preemptive timer tick), with a
negative control that disables the tick and confirms preemption is required.

### 13.7. Performance

CoreMark, built for RV32IMAC and run on the RTL (no caches), measures
~**2.92 CoreMark/MHz** and ~**1.72 DMIPS/MHz**.


## 14. FPGA Bring-up

The `fpga/` directory contains a small FPGA SoC wrapper around 3-SIPP-ES plus
board constraints, for running the core on real hardware.

### 14.1. What's included

```
fpga/
├── three_sipp_es_fpga.sv        FPGA SoC top (core + UART + GPIO/LED)
├── three_sipp_es_reset_sync.sv  reset synchroniser
├── tb_three_sipp_es_fpga.sv     simulation testbench (UART banner + LED blink)
└── arty_a7/                Digilent Arty A7 (Artix-7) project + XDC
```

### 14.2. Simulating the FPGA SoC

Before touching hardware you can run the FPGA SoC in simulation — it boots a
small firmware image that prints a UART banner and blinks an LED:

```bash
./build.sh fpga
```

### 14.3. Building for a board

Each board directory provides a filelist (`*.f`), a build script (`*.tcl`), and
a constraints file (`*.xdc`). With Vivado on your `PATH`:

```bash
cd fpga/arty_a7
vivado -mode batch -source three_sipp_es_arty_a7.tcl
```

The generated bitstream instantiates the core, a UART bridged to the board's
USB-UART, and LEDs/GPIO. Point a serial terminal at the board to see the boot
banner.

### 14.4. Firmware

The bring-up firmware lives in [`sw/`](https://github.com/OR5-LABS/3-SIPP-ES/tree/main/sw)
(`fpga_hello.S`, linker script, and a `build_fpga_hello.sh` helper). Replace it
with your own image to run application code on the board.
