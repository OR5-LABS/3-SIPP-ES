/* ==========================================================================
 * start.S -- 3-SIPP-ES FreeRTOS BSP reset / crt0.
 *
 * Reset entry (@ 0x0). Sets gp/sp, copies .data from its IMEM load image to
 * DRAM, zeroes .bss, installs the FreeRTOS trap vector (mtvec ->
 * freertos_risc_v_trap_handler) in DIRECT mode, then calls main().
 * ========================================================================== */
    .section .text.init, "ax"
    .global _start
    .type _start, @function
_start:
    /* Disable interrupts until the scheduler starts. */
    csrw    mie, x0
    csrw    mstatus, x0

    /* gp for linker-relaxed accesses (norelax so it isn't rewritten). */
.option push
.option norelax
    la      gp, __global_pointer$
.option pop

    /* Main/ISR-bootstrap stack. */
    la      sp, _stack_top

    /* ---- copy .data (LMA in IMEM) -> VMA in DRAM ------------------------- */
    la      a0, _data_lma
    la      a1, _data_start
    la      a2, _data_end
1:  bgeu    a1, a2, 2f
    lw      a3, 0(a0)
    sw      a3, 0(a1)
    addi    a0, a0, 4
    addi    a1, a1, 4
    j       1b
2:

    /* ---- zero .bss ------------------------------------------------------- */
    la      a0, _bss_start
    la      a1, _bss_end
3:  bgeu    a0, a1, 4f
    sw      x0, 0(a0)
    addi    a0, a0, 4
    j       3b
4:

    /* ---- install FreeRTOS trap vector (direct mode) --------------------- */
    la      t0, freertos_risc_v_trap_handler
    csrw    mtvec, t0

    /* ---- go -------------------------------------------------------------- */
    call    main

    /* main() should never return; if it does, spin. */
hang:
    j       hang
    .size _start, . - _start
