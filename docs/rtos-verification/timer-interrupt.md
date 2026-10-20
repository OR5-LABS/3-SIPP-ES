# Timer & Interrupt Integration Report: 3-SIPP-ESR Core

**Document Version:** 1.0  
**Target Architecture:** 3-SIPP-ESR (RV32IMAC + B, Zcb)  
**Date:** 2026-10-18  

---

## 1. Overview and Hardware Topology

The 3-SIPP-ESR processor accepts three standard RISC-V Machine-mode interrupt sources:

| Interrupt Signal | RISC-V IRQ Name | MCAUSE | Source Hardware Block | SoC Implementation Status |
|:---|:---|:---:|:---|:---:|
| `irq_timer` | MTIP (Machine Timer) | `0x80000007` | CLINT (`mtime >= mtimecmp`) | **WIRED & FUNCTIONAL** |
| `irq_soft` | MSIP (Machine Software) | `0x80000003` | CLINT (`msip[0]`) | **WIRED & FUNCTIONAL** |
| `irq_ext` | MEIP (Machine External) | `0x8000000B` | Platform Interrupt Controller | **TIED TO 0 IN RTL** |

### 1.1 Architectural Interrupt Pipeline Path
In `rtl/three_sipp_es_core.sv`, interrupt acceptance is gated strictly at the execute (`X`) stage boundary:
```verilog
wire take_irq = fx_valid && !ex_freeze && irq_req && !ex_trap && !dbg_freeze &&
                !d_is_mret && !is_uret &&
                !d_is_csr && !d_is_jal && !d_is_jalr && !d_is_branch;
```
When `take_irq` asserts:
1. The currently executing instruction commits and finishes retirement.
2. The interrupt return address (`trap_epc`) is computed as `fx_pc + fx_len` (the next sequential instruction).
3. CSR updates:
   * `mepc <= trap_epc`
   * `mcause <= {1'b1, 27'd0, irq_cause}`
   * `mstatus.MPIE <= mstatus.MIE`
   * `mstatus.MIE <= 0`
4. The pipeline flushes the fetch stage and redirects `pc` to `mtvec`.
5. On `mret`, `mstatus.MIE` is restored from `MPIE`, and execution resumes at `mepc`.

---

## 2. Supported vs. Unsupported Interrupt Paths

### 2.1 Machine Timer Interrupt (MTIP) - Fully Supported
* **Memory Base:** CLINT at `0x0200_0000`.
* **Hardware Timer Counter:** `mtime` at `0x0200_BFF8` (64-bit). In RTL simulation, increments by 1 every clock cycle.
* **Comparator:** `mtimecmp` at `0x0200_4000` (64-bit).
* **Integration with FreeRTOS:**
  * FreeRTOS port calculates tick increments based on `configCPU_CLOCK_HZ / configTICK_RATE_HZ`.
  * In `xPortSysTickHandler`, the handler programs `mtimecmp = mtimecmp + increment` to schedule the next tick.
  * `xTaskIncrementTick()` is called, waking up blocked tasks whose delay expired.
  * Preemption occurs seamlessly if a waking task has higher priority than the interrupted task.

### 2.2 Machine Software Interrupt (MSIP) - Fully Supported
* **Register:** `0x0200_0000` (`msip`). Bit 0 is writable by software.
* **Operation:** Writing `1` to `0x0200_0000` asserts `irq_soft`, setting `mip[3]`.
* **Integration with FreeRTOS:**
  * Tested in `test_interrupt.c`.
  * Vectors through `freertos_risc_v_trap_handler` to `freertos_risc_v_application_interrupt_handler`.
  * The ISR clears `CLINT_MSIP = 0` and unblocks tasks using `vTaskNotifyGiveFromISR(&xHigherPriorityTaskWoken)`.
  * Context switch is triggered via `portYIELD_FROM_ISR(xHigherPriorityTaskWoken)`.

### 2.3 Machine External Interrupt (MEIP) - Unwired in SoC
* In `rtl/three_sipp_es_soc.sv`:
  ```verilog
  three_sipp_es_core ... .irq_ext(1'b0) ...
  ```
* In `fpga/three_sipp_es_fpga.sv`:
  ```verilog
  three_sipp_es_core ... .irq_ext(1'b0) ...
  ```
* **Implication:** The core datapath and CSR logic fully implement MEIP handling (`mie[11]`, `mip[11]`, cause 11), but no PLIC (Platform-Level Interrupt Controller) is instantiated in the current SoC. All peripheral events (UART) are currently polled or serviced synchronously.

---

## 3. Verification Test Suite and Results

The Stage 3 test harness (`rtos/app/test_interrupt.c` executed via `rtos/run_interrupt.py`) completed with the following results:

| Test Case | Condition Tested | Observed Result | Status |
|:---|:---|:---:|:---:|
| **CLINT mtime hardware progression** | `mtime` advances monotonically with clock cycles | Cycle progression confirmed | **PASS** |
| **Timer Interrupt Wake Fidelity** | Tasks sleeping on `vTaskDelay` wake at the precise tick count | 0 tick waking errors observed | **PASS** |
| **Software Interrupt (MSIP) Handling** | Setting `msip` triggers cause 3 trap; ISR clears bit | 5/5 triggers handled and cleared | **PASS** |
| **ISR-Driven Task Notification** | `vTaskNotifyGiveFromISR` immediately resumes blocked task | 5/5 notifications received | **PASS** |
| **Competing Interrupts Stress** | Rapid back-to-back software interrupts under asynchronous timer ticks | 10/10 handled without state corruption | **PASS** |

Execution confirmed with exit code 0 (`tohost = 1` at cycle 217,294).
