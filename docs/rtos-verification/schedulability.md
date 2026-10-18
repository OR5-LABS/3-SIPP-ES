# Schedulability Analysis & Stress Verification: 3-SIPP-ES Core

**Document Version:** 1.0  
**Target Platform:** 3-SIPP-ES Core + FreeRTOS Preemptive Kernel  
**Date:** 2026-10-18  

---

## 1. Task Model and Workload Definitions

The schedulability of the 3-SIPP-ES processor was analyzed under a classical fixed-priority preemptive uniprocessor model with priority-inheritance mutexes and tick interrupt interference.

### 1.1 Synthetic Workload Parameters

| Task | Priority | Period $T_i$ | Deadline $D_i$ | Execution Cost $C_i$ (Observed Max) | Blocking $B_i$ | Jitter $J_i$ | Role / Description |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---|
| **$\tau_1$ (High)** | 3 | $10\text{ ms}$ (20,000 cyc) | $10\text{ ms}$ (20,000 cyc) | $450\text{ cyc}$ | $350\text{ cyc}$ | $9\text{ cyc}$ | Periodic control loop; accesses shared mutex |
| **$\tau_2$ (Med)** | 2 | $25\text{ ms}$ (50,000 cyc) | $25\text{ ms}$ (50,000 cyc) | $850\text{ cyc}$ | $0\text{ cyc}$ | $15\text{ cyc}$ | Periodic processing task; accesses shared mutex |
| **$\tau_3$ (Low)** | 1 | $\infty$ | $\infty$ | Continuous | $0\text{ cyc}$ | N/A | Non-yielding background computation load |
| **$\tau_{\text{ISR}}$** | Highest | $1\text{ ms}$ (2,000 cyc) | $1\text{ ms}$ | $150\text{ cyc}$ | $0\text{ cyc}$ | $0\text{ cyc}$ | FreeRTOS system tick interrupt (`MTIP`) |

---

## 2. Response-Time Analysis Formulation

For each task $\tau_i$, the worst-case response time $R_i$ is computed using the fixed-point recurrence:

$$R_i^{(m+1)} = C_i + B_i + \sum_{j \in hp(i)} \left\lceil \frac{R_i^{(m)} + J_j}{T_j} \right\rceil C_j + \left\lceil \frac{R_i^{(m)}}{T_{\text{tick}}} \right\rceil C_{\text{tick}}$$

Where:
* $hp(i)$ is the set of tasks with priority higher than $\tau_i$.
* $B_i$ is the maximum blocking time caused by lower-priority tasks holding the shared mutex (bounded under FreeRTOS priority inheritance by the longest critical section of any lower priority task).
* $J_j$ is the release jitter of higher priority task $j$.
* $T_{\text{tick}} = 2000\text{ cycles}$ ($1\text{ ms}$ tick period), and $C_{\text{tick}} = 150\text{ cycles}$ (ISR context save, tick advance, and restore).

The recurrence starts at $R_i^{(0)} = C_i + B_i$ and iterates until $R_i^{(m+1)} = R_i^{(m)}$.
* **Pass Condition:** $R_i \le D_i$.
* **Fail Condition:** $R_i > D_i$.

---

## 3. Step-by-Step Response-Time Calculations

### 3.1 Task $\tau_1$ (High Priority)
* $C_1 = 450\text{ cycles}$
* $B_1 = 350\text{ cycles}$ (critical section of $\tau_2$)
* $hp(1) = \emptyset$ (no user tasks higher than $\tau_1$; only tick ISR)

**Iteration 0:**
$$R_1^{(0)} = C_1 + B_1 = 450 + 350 = 800\text{ cycles}$$

**Iteration 1:**
$$R_1^{(1)} = 450 + 350 + \left\lceil \frac{800}{2000} \right\rceil \times 150 = 800 + 1 \times 150 = 950\text{ cycles}$$

**Iteration 2:**
$$R_1^{(2)} = 800 + \left\lceil \frac{950}{2000} \right\rceil \times 150 = 950\text{ cycles}$$

*Fixed point reached:* $R_1 = 950\text{ cycles}$ ($0.475\text{ ms}$).  
**Verdict:** $R_1 = 950 \le D_1 = 20000\text{ cycles}$ $\rightarrow$ **PASS**.

---

### 3.2 Task $\tau_2$ (Medium Priority)
* $C_2 = 850\text{ cycles}$
* $B_2 = 0\text{ cycles}$
* $hp(2) = \{\tau_1\}$ with $T_1 = 20000$, $C_1 = 450$, $J_1 = 9$

**Iteration 0:**
$$R_2^{(0)} = C_2 + B_2 = 850\text{ cycles}$$

**Iteration 1:**
$$R_2^{(1)} = 850 + \left\lceil \frac{850 + 9}{20000} \right\rceil \times 450 + \left\lceil \frac{850}{2000} \right\rceil \times 150 = 850 + 450 + 150 = 1450\text{ cycles}$$

**Iteration 2:**
$$R_2^{(2)} = 850 + \left\lceil \frac{1450 + 9}{20000} \right\rceil \times 450 + \left\lceil \frac{1450}{2000} \right\rceil \times 150 = 1450\text{ cycles}$$

*Fixed point reached:* $R_2 = 1450\text{ cycles}$ ($0.725\text{ ms}$).  
**Verdict:** $R_2 = 1450 \le D_2 = 50000\text{ cycles}$ $\rightarrow$ **PASS**.

---

## 4. Empirical Stress Validation & Negative Control

The analytical model was experimentally validated using the Verilator simulation harness (`rtos/run_stress.py`):

1. **Positive Stress Run (`rtos_stress.hex`):**
   * High-priority Task 1 executed 8 periodic releases ($T=10\text{ ms}$).
   * Medium-priority Task 2 executed 4 periodic releases ($T=25\text{ ms}$).
   * Low-priority Task 3 executed continuous background compute loops (508 loops completed).
   * Contended Mutex was taken and released across task boundaries.
   * **Observed Deadline Misses:** **0** (All deadlines respected).
2. **Negative Control Verification (`rtos_stress_neg.hex`):**
   * Task 1 critical section workload was artificially increased to $3500$ iterations ($\approx 35000\text{ cycles}$, exceeding $D_1 = 20000\text{ cycles}$).
   * Injected Overload result: The harness detected and logged **3 deadline violations**, confirming that the deadline watchdog operates reliably and does not silently pass overloaded schedules.

---

## 5. Limitations of Schedulability Analysis

1. **Static WCET Assumption:**
   The calculations above utilize observed maximum cycle times ($C_{\text{obs}}$). If hardware caches or off-chip DRAM (e.g. DDR3 on Arty A7) are introduced, memory latency jitter will increase $C_i$ significantly.
2. **Interrupt Masking Intervals:**
   FreeRTOS critical sections (`taskENTER_CRITICAL()`) temporarily disable interrupts by clearing `mstatus.MIE`. The longest critical section inside the kernel bounds the minimum achievable interrupt latency.
