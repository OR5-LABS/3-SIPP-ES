# Timing Instrumentation & Response-Time Analysis: 3-SIPP-ES Core

**Document Version:** 1.0  
**Target Platform:** 3-SIPP-ES (RV32IMAC + B, Zcb)  
**Date:** 2026-10-18  

---

## 1. Overview and Instrumentation Methodology

To quantify real-time behavior without distorting execution semantics, minimally invasive cycle-accurate software probes were embedded using the RISC-V `mcycle` counter CSR.

In the 3-SIPP-ES core, `mcycle` increments unconditionally on every clock cycle. Inline assembly macros read `mcycle` with zero function-call overhead:
```c
static inline uint32_t get_cycle_count( void )
{
    uint32_t c;
    __asm__ volatile( "csrr %0, mcycle" : "=r"(c) );
    return c;
}
```

### 1.1 Measured Latency Decomposition
A real-time response to an event comprises distinct, non-overlapping phases:

$$R_{\text{total}} = T_{\text{irq}} + T_{\text{sched}} + C_{\text{task}}$$

Where:
* **Interrupt Latency ($T_{\text{irq}}$):** Cycles from when the interrupt assertion condition occurs (`t_assert`) to the first instruction of the ISR handler (`t_isr_entry`).
  * Encompasses: current instruction commit + pipeline drain (1–3 cycles) + vector redirect to `mtvec` + FreeRTOS `portASM.S` Machine-mode register save (saving 32 registers to stack).
* **Scheduler Latency ($T_{\text{sched}}$):** Cycles from task unblock inside the ISR (`vTaskNotifyGiveFromISR`) to the first user instruction of the unblocked high-priority task (`t_task_start`).
  * Encompasses: `vTaskSwitchContext()` priority resolution + `portASM.S` context restore + `mret` instruction.
* **Task Execution Time ($C_{\text{task}}$):** Cycles consumed executing the task's algorithm (`t_task_end - t_task_start`).
* **End-to-End Response Time ($R_{\text{task}}$):** Total elapsed time from physical stimulus to task output completion ($t_{\text{task\_end}} - t_{\text{assert}}$).
* **Release Jitter ($J_{\text{rel}}$):** Maximum variation between observed response latencies across multiple releases.

---

## 2. Experimental Measurement Results

A 20-sample run of the test harness (`rtos/app/test_timing.c`) yielded the following cycle distributions:

| Metric | Minimum Observed (Cycles) | Maximum Observed (Cycles) | Mean $\mu$ (Cycles) | Jitter $\Delta$ (Cycles) |
|:---|:---:|:---:|:---:|:---:|
| **Interrupt Latency ($T_{\text{irq}}$)** | **63** | **63** | **63.0** | **0** |
| **Scheduler Latency ($T_{\text{sched}}$)** | **316** | **318** | **316.2** | **2** |
| **Task Execution Time ($C_{\text{task}}$)** | **293** | **300** | **293.4** | **7** |
| **End-to-End Response Time ($R_{\text{task}}$)** | **672** | **681** | **672.6** | **9** |

Machine-readable JSON data is captured in `rtos/timing_results.json`.

---

## 3. Critical Timing Distinction: Observed Latency vs. Proven WCET

> [!WARNING]
> **Engineering Rigor Notice:**
> Maximum observed execution time ($\max C_{\text{obs}}$) under empirical testing is **NOT** a formally proven Worst-Case Execution Time (WCET) upper bound.

1. **Why Observed Max $\ne$ Proven WCET:**
   * Empirical testing only covers the specific execution paths, register contents, and instruction alignments exercised by the test inputs.
   * Multi-cycle operations (e.g., non-restoring divider `three_sipp_es_muldiv.sv` requiring up to 34 cycles for division) can introduce data-dependent variations.
   * Bus contention, flash/SRAM wait states (on FPGA), and asynchronous interrupts striking during multi-word memory accesses can lengthen pipeline stalls beyond the observed 681-cycle window.
2. **Sources of Jitter in 3-SIPP-ES:**
   * **Instruction Multi-cycle Execution:** If an interrupt arrives while the core is executing a multi-cycle `DIV`/`REMU` or waiting on a multi-beat bus transfer, `take_irq` cannot commit until the execute stage is non-frozen.
   * **Branch Prediction Misprediction Penalty:** Flushing the 3-stage pipeline introduces a 2-cycle penalty.
3. **Formal Requirement for Hard Real-Time Certification:**
   To establish a true real-time claim, static analysis or formally proved bound computation ($\text{WCET} = \max_{p \in \text{Paths}} \text{Cost}(p)$) must bound the worst-case divider latency, maximum interrupt disable interval ($T_{\text{cs\_disabled}}$), and longest instruction commit delay.
