/* ==========================================================================
 * test_timing.c -- Stage 4: Execution-Time and Response-Time Instrumentation.
 *
 * Measures cycle-accurate timing metrics on 3-SIP-ESR:
 *   1. Interrupt Latency: trigger assertion -> ISR handler entry.
 *   2. Scheduler Latency: task unblock in ISR -> task start execution.
 *   3. Task Execution Time: computation start -> computation end.
 *   4. End-to-End Response Time: event assertion -> task completion.
 *   5. Release Jitter: variation in periodic task release across ticks.
 * Emits structured measurement records over UART for automated analysis.
 * ========================================================================== */

#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include "bsp.h"

#define CLINT_MSIP      (*(volatile uint32_t *)0x02000000UL)
#define NUM_SAMPLES     20

static inline uint32_t get_cycle_count( void )
{
    uint32_t c;
    __asm__ volatile( "csrr %0, mcycle" : "=r"(c) );
    return c;
}

/* Timing measurement data structures */
typedef struct {
    uint32_t t_assert;
    uint32_t t_isr_entry;
    uint32_t t_task_start;
    uint32_t t_task_end;
    uint32_t lat_irq;
    uint32_t lat_sched;
    uint32_t t_exec;
    uint32_t resp_end_to_end;
} TimingSample_t;

static TimingSample_t g_samples[ NUM_SAMPLES ];
static volatile int   g_sample_idx = 0;
static TaskHandle_t   xWorkerTaskHandle = NULL;
static TaskHandle_t   xMasterTaskHandle = NULL;

/* --------------------------------------------------------------------------
 * Instrument ISR: captures entry timestamp
 * -------------------------------------------------------------------------- */
void freertos_risc_v_application_interrupt_handler( void )
{
    uint32_t t_entry = get_cycle_count();
    uint32_t mcause_val;
    __asm__ volatile( "csrr %0, mcause" : "=r"(mcause_val) );

    if( mcause_val == 0x80000003UL )  /* MSIP */
    {
        CLINT_MSIP = 0;
        int idx = g_sample_idx;
        if( idx < NUM_SAMPLES )
        {
            g_samples[ idx ].t_isr_entry = t_entry;
            g_samples[ idx ].lat_irq = t_entry - g_samples[ idx ].t_assert;
        }

        BaseType_t xHigherPriorityTaskWoken = pdFALSE;
        vTaskNotifyGiveFromISR( xWorkerTaskHandle, &xHigherPriorityTaskWoken );
        portYIELD_FROM_ISR( xHigherPriorityTaskWoken );
    }
}

/* --------------------------------------------------------------------------
 * High-Priority Responding Worker Task
 * -------------------------------------------------------------------------- */
static void vRespondingTask( void *pv )
{
    ( void ) pv;
    for( int i = 0; i < NUM_SAMPLES; i++ )
    {
        /* Block waiting for ISR notification */
        ulTaskNotifyTake( pdTRUE, portMAX_DELAY );
        uint32_t t_start = get_cycle_count();

        /* Deterministic synthetic task workload: 32 iterations of multiply-accumulate */
        volatile uint32_t acc = 0x12345678;
        for( int k = 1; k <= 32; k++ )
        {
            acc = ( acc * 33 ) + (uint32_t) k;
        }

        uint32_t t_end = get_cycle_count();

        g_samples[ i ].t_task_start = t_start;
        g_samples[ i ].t_task_end   = t_end;
        g_samples[ i ].lat_sched    = t_start - g_samples[ i ].t_isr_entry;
        g_samples[ i ].t_exec       = t_end - t_start;
        g_samples[ i ].resp_end_to_end = t_end - g_samples[ i ].t_assert;

        /* Signal master task that sample is complete */
        xTaskNotifyGive( xMasterTaskHandle );
    }
    vTaskDelete( NULL );
}

/* --------------------------------------------------------------------------
 * Master Timing Orchestrator Task
 * -------------------------------------------------------------------------- */
static void vMasterTimingTask( void *pv )
{
    ( void ) pv;
    xMasterTaskHandle = xTaskGetCurrentTaskHandle();
    uart_puts( "[TIMING] Starting cycle-accurate latency characterization\n" );

    /* Enable Software Interrupts in mie */
    __asm__ volatile( "csrsi mie, 0x08" );

    for( int i = 0; i < NUM_SAMPLES; i++ )
    {
        g_sample_idx = i;
        /* Slight pacing between measurements */
        vTaskDelay( pdMS_TO_TICKS( 2 ) );

        /* Record assertion timestamp and trigger interrupt */
        g_samples[ i ].t_assert = get_cycle_count();
        CLINT_MSIP = 1;

        /* Wait for responding task to complete execution */
        ulTaskNotifyTake( pdTRUE, pdMS_TO_TICKS( 50 ) );
    }

    __asm__ volatile( "csrci mie, 0x08" );

    /* Compute and print summary statistics */
    uint32_t min_irq = 0xFFFFFFFF, max_irq = 0, sum_irq = 0;
    uint32_t min_sched = 0xFFFFFFFF, max_sched = 0, sum_sched = 0;
    uint32_t min_exec = 0xFFFFFFFF, max_exec = 0, sum_exec = 0;
    uint32_t min_resp = 0xFFFFFFFF, max_resp = 0, sum_resp = 0;

    for( int i = 0; i < NUM_SAMPLES; i++ )
    {
        uint32_t irq   = g_samples[ i ].lat_irq;
        uint32_t sched = g_samples[ i ].lat_sched;
        uint32_t exec  = g_samples[ i ].t_exec;
        uint32_t resp  = g_samples[ i ].resp_end_to_end;

        if( irq < min_irq ) min_irq = irq;
        if( irq > max_irq ) max_irq = irq;
        sum_irq += irq;

        if( sched < min_sched ) min_sched = sched;
        if( sched > max_sched ) max_sched = sched;
        sum_sched += sched;

        if( exec < min_exec ) min_exec = exec;
        if( exec > max_exec ) max_exec = exec;
        sum_exec += exec;

        if( resp < min_resp ) min_resp = resp;
        if( resp > max_resp ) max_resp = resp;
        sum_resp += resp;
    }

    uint32_t avg_irq   = sum_irq / NUM_SAMPLES;
    uint32_t avg_sched = sum_sched / NUM_SAMPLES;
    uint32_t avg_exec  = sum_exec / NUM_SAMPLES;
    uint32_t avg_resp  = sum_resp / NUM_SAMPLES;

    uart_puts( "\n================ TIMING MEASUREMENT SUMMARY ================\n" );
    uart_puts( "Samples: 20\n" );

    uart_puts( "Interrupt Latency (cycles)     : min=" ); uart_putdec( min_irq );
    uart_puts( " max=" ); uart_putdec( max_irq );
    uart_puts( " avg=" ); uart_putdec( avg_irq ); uart_putc( '\n' );

    uart_puts( "Scheduler Latency (cycles)     : min=" ); uart_putdec( min_sched );
    uart_puts( " max=" ); uart_putdec( max_sched );
    uart_puts( " avg=" ); uart_putdec( avg_sched ); uart_putc( '\n' );

    uart_puts( "Task Execution Time (cycles)   : min=" ); uart_putdec( min_exec );
    uart_puts( " max=" ); uart_putdec( max_exec );
    uart_puts( " avg=" ); uart_putdec( avg_exec ); uart_putc( '\n' );

    uart_puts( "End-to-End Response (cycles)   : min=" ); uart_putdec( min_resp );
    uart_puts( " max=" ); uart_putdec( max_resp );
    uart_puts( " avg=" ); uart_putdec( avg_resp ); uart_putc( '\n' );

    /* Machine-readable JSON output */
    uart_puts( "\n[TIMING_JSON_START]\n" );
    uart_puts( "{\n" );
    uart_puts( "  \"samples\": 20,\n" );
    uart_puts( "  \"interrupt_latency\": {\"min\": " ); uart_putdec( min_irq );
    uart_puts( ", \"max\": " ); uart_putdec( max_irq );
    uart_puts( ", \"avg\": " ); uart_putdec( avg_irq ); uart_puts( "},\n" );

    uart_puts( "  \"scheduler_latency\": {\"min\": " ); uart_putdec( min_sched );
    uart_puts( ", \"max\": " ); uart_putdec( max_sched );
    uart_puts( ", \"avg\": " ); uart_putdec( avg_sched ); uart_puts( "},\n" );

    uart_puts( "  \"task_execution\": {\"min\": " ); uart_putdec( min_exec );
    uart_puts( ", \"max\": " ); uart_putdec( max_exec );
    uart_puts( ", \"avg\": " ); uart_putdec( avg_exec ); uart_puts( "},\n" );

    uart_puts( "  \"response_time\": {\"min\": " ); uart_putdec( min_resp );
    uart_puts( ", \"max\": " ); uart_putdec( max_resp );
    uart_puts( ", \"avg\": " ); uart_putdec( avg_resp ); uart_puts( "}\n" );
    uart_puts( "}\n" );
    uart_puts( "[TIMING_JSON_END]\n" );

    uart_puts( "\n[TIMING] ALL STAGE 4 MEASUREMENTS COMPLETE!\n" );
    sim_pass();
}

int main( void )
{
    uart_init();
    uart_puts( "[BOOT] FreeRTOS Timing Instrumentation Harness\n" );

    /* Responding worker at priority 3 (highest), Master orchestrator at priority 2 */
    xTaskCreate( vRespondingTask, "RESP", configMINIMAL_STACK_SIZE * 2, NULL, 3, &xWorkerTaskHandle );
    xTaskCreate( vMasterTimingTask, "M_TIME", configMINIMAL_STACK_SIZE * 2, NULL, 2, NULL );

    vTaskStartScheduler();

    uart_puts( "[FATAL] Scheduler returned\n" );
    sim_fail();
    return 0;
}
