/* ==========================================================================
 * three_sipp_es.ld -- Linker script for the 3-SIP-ESR FreeRTOS BSP.
 *
 * 3-SIP-ESR SoC memory map (see three_sipp_es_soc.sv):
 *   IMEM : 0x0000_0000, 32 KB (8192 words) -- combinational-read program ROM.
 *          Only IMEM is loaded from the +IMEM=<hex> plusarg, so ALL bytes that
 *          must exist at reset (text, rodata, and the *load image* of .data)
 *          live here.
 *   DRAM : 0x8000_0000, 32 KB (8192 words) -- read/write; stack, heap, .bss,
 *          and the run-time copy of .data.
 *
 * .data is placed with VMA in DRAM but LMA (load address) in IMEM; the reset
 * code in start.S copies it across and zeroes .bss before calling main().
 * ========================================================================== */
OUTPUT_ARCH( "riscv" )
ENTRY( _start )

MEMORY
{
  IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 32K
  DRAM (rwx) : ORIGIN = 0x80000000, LENGTH = 32K
}

/* Top of the main (initial/MSP) stack -- highest DRAM address, 16-byte down. */
_stack_top = ORIGIN(DRAM) + LENGTH(DRAM);

SECTIONS
{
  /* ---- code + read-only, resident in IMEM -------------------------------- */
  .text 0x00000000 :
  {
    KEEP(*(.text.init))          /* _start must be first */
    *(.text .text.*)
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)
    . = ALIGN(4);
  } > IMEM

  /* ---- initialized data: VMA in DRAM, LMA (load image) in IMEM ------------ */
  . = ALIGN(4);
  _data_lma = LOADADDR(.data);
  .data 0x80000000 : AT ( ADDR(.text) + SIZEOF(.text) )
  {
    _data_start = .;
    __global_pointer$ = . + 0x400;   /* gp for the compiler's relaxation */
    *(.data .data.*)
    *(.sdata .sdata.*)
    . = ALIGN(4);
    _data_end = .;
  } > DRAM

  /* ---- zero-initialized data --------------------------------------------- */
  .bss (NOLOAD) :
  {
    _bss_start = .;
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(4);
    _bss_end = .;
  } > DRAM

  _end = .;                        /* heap base (heap_4 uses configTOTAL_HEAP) */
}
