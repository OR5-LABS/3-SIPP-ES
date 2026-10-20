# Traps & Interrupts

3-SIPP-ESR implements **precise** traps: when an instruction faults, no later
instruction has changed architectural state, and the trapping instruction's PC
is recorded in `mepc` (or `uepc` for a delegated user trap).

## Synchronous exceptions

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

## Interrupts

The core accepts the standard machine interrupt lines, gated by `mstatus.MIE`
and `mie`:

- **Machine timer** (`MTIP`) — driven by the CLINT `mtime` / `mtimecmp`.
- **Machine software** (`MSIP`) — the CLINT software-interrupt register.
- **Machine external** (`MEIP`) — from a platform interrupt source.

On an accepted trap the core saves the PC to `mepc`, records the cause in
`mcause` (and the faulting value in `mtval`), updates `mstatus`, and vectors to
`mtvec`. `MRET` restores the pre-trap state and resumes.

## Delegation to User mode (`N`)

In the `SECURE` configuration with the `N` extension, selected exceptions can be
delegated to User mode via `medeleg`. A delegated trap vectors to `utvec`, saves
`uepc` / `ucause` / `utval`, keeps the core in User mode, and returns with
`URET`. This lets a user-level runtime handle its own traps without entering
Machine mode.
