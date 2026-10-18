/* ==========================================================================
 * test_stress.c -- Stage 5: Stress Testing and Deadline Verification.
 *
 * Implements a deterministic real-time workload:
 *   - Task 1 (High Prio, P=3): Periodic control task (T=10ms, D=10ms).
 *   - Task 2 (Med Prio,  P=2): Periodic processing task (T=25ms, D=25ms),
 *     competing for a shared Mutex with Task 1.
 *   - Task 3 (Low Prio,  P=1): Continuous background CPU load.
 *
 * Deadline monitoring: Every periodic release verifies completion before D.
 * Negative Control (NEG_OVERLOAD): Overloads computation to prove the harness
 * reliably catches and reports deadline violations.
 * ========================================================================== */

#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include "bsp.h"

#define TASK1_PERIOD_TICKS   pdMS_TO_TICKS( 10 )
#define TASK1_DEADLINE_TICKS pdMS_TO_TICKS( 10 )

#define TASK2_PERIOD_TICKS   pdMS_TO_TICKS( 25 )
#define TASK2_DEADLINE_TICKS pdMS_TO_TICKS( 25 )

#define STRESS_RUN_TICKS     pdMS_TO_TICKS( 80 )

static SemaphoreHandle_t xSharedMutex;

static volatile int g_t1_releases = 0;
static volatile int g_t2_releases = 0;
static volatile int g_deadline_misses = 0;
static volatile int g_stress_done = 0;
static volatile uint32_t g_bg_counter = 0;

/* Synthetic computational load */
static inline void do_work( int iterations )
{
    volatile uint32_t acc = 0x55AA55AA;
    for( int i = 0; i < iterations; i++ )
    {
        acc = ( acc * 1103515245UL + 12345UL ) ^ (uint32_t) i;
    }
}

/* --------------------------------------------------------------------------
 * Task 1: High Priority Periodic Task (Priority 3)
 * -------------------------------------------------------------------------- */
static void vTask1_High( void *pv )
{
    ( void ) pv;
    TickType_t xNextWakeTime = xTaskGetTickCount();

    while( !g_stress_done )
    {
        TickType_t release_tick = xTaskGetTickCount();
        g_t1_releases++;

        /* Compete for shared mutex */
        if( xSemaphoreTake( xSharedMutex, portMAX_DELAY ) == pdTRUE )
        {
            #ifdef NEG_OVERLOAD
            /* Deliberate overload: ~3500 iters takes ~18 ticks (> 10 tick deadline) */
            do_work( 3500 );
            #else
            do_work( 50 );
            #endif
            xSemaphoreGive( xSharedMutex );
        }

        TickType_t finish_tick = xTaskGetTickCount();
        if( ( finish_tick - release_tick ) > TASK1_DEADLINE_TICKS )
        {
            g_deadline_misses++;
            uart_puts( "[DEADLINE MISS] Task 1 exceeded deadline!\n" );
        }

        vTaskDelayUntil( &xNextWakeTime, TASK1_PERIOD_TICKS );
    }
    vTaskDelete( NULL );
}

/* --------------------------------------------------------------------------
 * Task 2: Medium Priority Periodic Task (Priority 2)
 * -------------------------------------------------------------------------- */
static void vTask2_Med( void *pv )
{
    ( void ) pv;
    TickType_t xNextWakeTime = xTaskGetTickCount();

    while( !g_stress_done )
    {
        TickType_t release_tick = xTaskGetTickCount();
        g_t2_releases++;

        if( xSemaphoreTake( xSharedMutex, portMAX_DELAY ) == pdTRUE )
        {
            do_work( 100 );
            xSemaphoreGive( xSharedMutex );
        }

        TickType_t finish_tick = xTaskGetTickCount();
        if( ( finish_tick - release_tick ) > TASK2_DEADLINE_TICKS )
        {
            g_deadline_misses++;
            uart_puts( "[DEADLINE MISS] Task 2 exceeded deadline!\n" );
        }

        vTaskDelayUntil( &xNextWakeTime, TASK2_PERIOD_TICKS );
    }
    vTaskDelete( NULL );
}

/* --------------------------------------------------------------------------
 * Task 3: Low Priority Continuous Background Burner (Priority 1)
 * -------------------------------------------------------------------------- */
static void vTask3_Low( void *pv )
{
    ( void ) pv;
    while( !g_stress_done )
    {
        g_bg_counter++;
        /* Burns CPU continuously without yielding */
        do_work( 20 );
    }
    vTaskDelete( NULL );
}

/* --------------------------------------------------------------------------
 * Orchestrator Task (Priority 4)
 * -------------------------------------------------------------------------- */
static void vStressMasterTask( void *pv )
{
    ( void ) pv;
    uart_puts( "[STRESS] Starting Deterministic Stress & Schedulability Workload\n" );

    #ifdef NEG_OVERLOAD
    uart_puts( "[STRESS] Negative control: Deliberate overload injected\n" );
    #endif

    vTaskDelay( STRESS_RUN_TICKS );

    g_stress_done = 1;

    uart_puts( "\n================ STRESS TEST RESULTS ================\n" );
    uart_puts( "Task 1 Releases (T=10ms) : " ); uart_putdec( g_t1_releases ); uart_putc( '\n' );
    uart_puts( "Task 2 Releases (T=25ms) : " ); uart_putdec( g_t2_releases ); uart_putc( '\n' );
    uart_puts( "Background Cycles Burned : " ); uart_putdec( g_bg_counter ); uart_putc( '\n' );
    uart_puts( "Deadline Misses Detected : " ); uart_putdec( g_deadline_misses ); uart_putc( '\n' );

    #ifdef NEG_OVERLOAD
    if( g_deadline_misses > 0 )
    {
        uart_puts( "[STRESS_NEG] PASS: Deadline miss successfully caught as designed!\n" );
        sim_pass();
    }
    else
    {
        uart_puts( "[STRESS_NEG] FAIL: Overload was not detected!\n" );
        sim_fail();
    }
    #else
    if( g_deadline_misses == 0 && g_t1_releases >= 6 && g_t2_releases >= 2 && g_bg_counter > 0 )
    {
        uart_puts( "[STRESS] ALL SCHEDULED TASKS MET DEADLINES: PASS\n" );
        sim_pass();
    }
    else
    {
        uart_puts( "[STRESS] FAIL: Deadline misses or insufficient releases\n" );
        sim_fail();
    }
    #endif
}

int main( void )
{
    uart_init();
    uart_puts( "[BOOT] FreeRTOS Stress Test Suite\n" );

    xSharedMutex = xSemaphoreCreateMutex();
    configASSERT( xSharedMutex != NULL );

    xTaskCreate( vTask1_High, "T1_HP",  configMINIMAL_STACK_SIZE, NULL, 3, NULL );
    xTaskCreate( vTask2_Med,  "T2_MP",  configMINIMAL_STACK_SIZE, NULL, 2, NULL );
    xTaskCreate( vTask3_Low,  "T3_LP",  configMINIMAL_STACK_SIZE, NULL, 1, NULL );
    xTaskCreate( vStressMasterTask, "M_STR", configMINIMAL_STACK_SIZE * 2, NULL, 4, NULL );

    vTaskStartScheduler();

    uart_puts( "[FATAL] Scheduler returned\n" );
    sim_fail();
    return 0;
}
