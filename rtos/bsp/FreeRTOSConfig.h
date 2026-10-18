/* ==========================================================================
 * FreeRTOSConfig.h -- 3-SIPP-ES BSP.
 *
 * Targets the 3-SIPP-ES SoC CLINT for the tick:
 *   CLINT base   = 0x0200_0000
 *   mtime        = 0x0200_BFF8
 *   mtimecmp     = 0x0200_4000
 * In simulation the SoC's `mtime` increments once per clock, so the "clock"
 * for FreeRTOS timing purposes is 1 count/cycle. We pick a small
 * increments-per-tick so preemptive ticks fire quickly inside the sim window.
 * ========================================================================== */
#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

/* ---- Timer / CLINT ------------------------------------------------------- */
/* mtime counts once per cycle in sim. Set CPU_CLOCK/TICK_RATE so that
 * uxTimerIncrementsForOneTick = CPU_CLOCK_HZ / TICK_RATE_HZ = 2000 cycles/tick,
 * i.e. a tick roughly every 2000 mtime counts -- fast enough to preempt within
 * the sim, slow enough to run real work between ticks. */
#define configCPU_CLOCK_HZ                      ( 2000000UL )
#define configTICK_RATE_HZ                      ( 1000 )       /* -> 2000 cyc/tick */
#define configMTIME_BASE_ADDRESS                ( 0x0200BFF8UL )
#define configMTIMECMP_BASE_ADDRESS             ( 0x02004000UL )

/* ---- Scheduler ----------------------------------------------------------- */
#define configUSE_PREEMPTION                    1
#define configUSE_TIME_SLICING                  1
#define configUSE_IDLE_HOOK                     0
#define configUSE_TICK_HOOK                     0
#define configMAX_PRIORITIES                    ( 5 )
#define configMINIMAL_STACK_SIZE                ( 256 )        /* words */
#define configMAX_TASK_NAME_LEN                 ( 12 )
#define configUSE_16_BIT_TICKS                  0
#define configIDLE_SHOULD_YIELD                 1
#define configUSE_MUTEXES                       1
#define configUSE_COUNTING_SEMAPHORES           1
#define configUSE_TASK_NOTIFICATIONS            1
#define configQUEUE_REGISTRY_SIZE               0
#define configCHECK_FOR_STACK_OVERFLOW          2
#define configUSE_TRACE_FACILITY                1

/* ---- ISR stack (port provides it -> no linker symbol needed) ------------- */
#define configISR_STACK_SIZE_WORDS              ( 512 )

/* ---- Memory -------------------------------------------------------------- */
#define configSUPPORT_STATIC_ALLOCATION         0
#define configSUPPORT_DYNAMIC_ALLOCATION        1
#define configTOTAL_HEAP_SIZE                   ( 16 * 1024 )  /* bytes, in DRAM */
#define configAPPLICATION_ALLOCATED_HEAP        0

/* ---- Hooks / asserts ----------------------------------------------------- */
#define configUSE_MALLOC_FAILED_HOOK            1
extern void vAssertCalled( const char * pcFile, unsigned long ulLine );
#define configASSERT( x )    if( ( x ) == 0 ) vAssertCalled( __FILE__, __LINE__ )

/* ---- API inclusion ------------------------------------------------------- */
#define INCLUDE_vTaskPrioritySet                1
#define INCLUDE_uxTaskPriorityGet               1
#define INCLUDE_vTaskDelete                     1
#define INCLUDE_vTaskSuspend                    1
#define INCLUDE_vTaskDelayUntil                 1
#define INCLUDE_vTaskDelay                      1
#define INCLUDE_xTaskGetSchedulerState          1
#define INCLUDE_xTaskGetCurrentTaskHandle       1
#define INCLUDE_uxTaskGetStackHighWaterMark     1
#define INCLUDE_eTaskGetState                   1

#endif /* FREERTOS_CONFIG_H */
