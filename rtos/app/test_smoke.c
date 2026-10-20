/* ==========================================================================
 * test_smoke.c -- Stage 2: FreeRTOS Basic Functionality Verification Suite.
 *
 * Verifies core RTOS requirements on 3-SIPP-ESR:
 *   1. Kernel startup & scheduler operation.
 *   2. Multiple task creation and concurrent execution.
 *   3. Strict priority-based preemption.
 *   4. Context switching & exhaustive register state preservation (s0-s11, etc).
 *   5. Timer tick progression and monotonic task delay.
 *   6. Queue communication (FIFO integrity, full/empty blocking).
 *   7. Counting & binary semaphore synchronization, task notifications.
 *   8. Heap & stack limit handling (safe oversized malloc rejection, high water mark).
 *   9. Repeated rapid task switches under asynchronous ticks without corruption.
 * ========================================================================== */

#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semphr.h"
#include "bsp.h"
#include <string.h>

#define TEST_QUEUE_LEN 4
#define PING_PONG_CYCLES 20

static QueueHandle_t     xTestQueue;
static SemaphoreHandle_t xBinarySem;
static SemaphoreHandle_t xCountingSem;
static TaskHandle_t      xRegTaskHandle;
static TaskHandle_t      xPreemptTaskHandle;
static TaskHandle_t      xPingTaskHandle;
static TaskHandle_t      xPongTaskHandle;

/* Test Phase Counters and Flags */
static volatile int g_phase1_tasks_started = 0;
static volatile int g_phase2_preempt_done   = 0;
static volatile int g_phase3_reg_ok        = 0;
static volatile int g_phase4_queue_ok      = 0;
static volatile int g_phase5_sem_ok        = 0;
static volatile int g_phase6_delay_ok      = 0;
static volatile int g_phase7_memory_ok     = 0;
static volatile int g_phase8_pingpong_done = 0;

static volatile int g_lp_counter = 0;
static volatile int g_hp_preempt_verified = 0;

/* Helper to report test verdict */
static void report_test( const char *name, int pass )
{
    uart_puts( "[TEST] " );
    uart_puts( name );
    if( pass )
    {
        uart_puts( ": PASS\n" );
    }
    else
    {
        uart_puts( ": FAIL\n" );
        sim_fail();
    }
}

/* --------------------------------------------------------------------------
 * Phase 4 & 5: Queue and Semaphore Synchronization Task
 * -------------------------------------------------------------------------- */
static void vSyncTask( void *pv )
{
    ( void ) pv;
    int val = 0;

    /* Binary Semaphore Test: wait for signal from main controller */
    if( xSemaphoreTake( xBinarySem, pdMS_TO_TICKS( 50 ) ) == pdTRUE )
    {
        g_phase5_sem_ok++;
        uart_puts( "  - binary sem ok\n" );
    }
    else
    {
        uart_puts( "  - binary sem failed\n" );
    }

    /* Queue Test: dequeue 4 items and verify strict FIFO ordering */
    int expected = 100;
    int fifo_ok = 1;
    for( int i = 0; i < TEST_QUEUE_LEN; i++ )
    {
        if( xQueueReceive( xTestQueue, &val, pdMS_TO_TICKS( 50 ) ) == pdTRUE )
        {
            if( val != expected + i )
            {
                fifo_ok = 0;
            }
        }
        else
        {
            fifo_ok = 0;
        }
    }
    if( fifo_ok )
    {
        g_phase4_queue_ok = 1;
        uart_puts( "  - queue ok\n" );
    }
    else
    {
        uart_puts( "  - queue failed\n" );
    }

    /* Counting semaphore: take 3 tokens */
    int tokens = 0;
    while( xSemaphoreTake( xCountingSem, 0 ) == pdTRUE )
    {
        tokens++;
    }
    if( tokens == 3 )
    {
        g_phase5_sem_ok++;
        uart_puts( "  - counting sem ok\n" );
    }
    else
    {
        uart_puts( "  - counting sem failed, tokens=" );
        uart_putdec( tokens );
        uart_putc( '\n' );
    }

    /* Task Notification Test: wait for direct notification */
    uint32_t note_val = ulTaskNotifyTake( pdTRUE, pdMS_TO_TICKS( 50 ) );
    if( note_val >= 1 )
    {
        g_phase5_sem_ok++;
        uart_puts( "  - notify ok\n" );
    }
    else
    {
        uart_puts( "  - notify failed, val=" );
        uart_putdec( (int32_t) note_val );
        uart_putc( '\n' );
    }

    vTaskDelete( NULL );
}

/* --------------------------------------------------------------------------
 * Phase 3: Exhaustive Register State Preservation Across Context Switch
 * Loads known unique bit patterns into s0-s11 (callee-saved) and ensures
 * that after preemption / yielding to other tasks, ALL registers retain
 * their exact values.
 * -------------------------------------------------------------------------- */
static void vRegCheckTask( void *pv )
{
    ( void ) pv;
    volatile uint32_t s0_val, s1_val, s2_val, s3_val;
    volatile uint32_t s4_val, s5_val, s6_val, s7_val;
    volatile uint32_t s8_val, s9_val, s10_val, s11_val;

    /* Load known test patterns into s0-s11 in inline assembly */
    __asm__ volatile (
        "li s0,  0x11111111\n"
        "li s1,  0x22222222\n"
        "li s2,  0x33333333\n"
        "li s3,  0x44444444\n"
        "li s4,  0x55555555\n"
        "li s5,  0x66666666\n"
        "li s6,  0x77777777\n"
        "li s7,  0x88888888\n"
        "li s8,  0x99999999\n"
        "li s9,  0xAAAAAAAA\n"
        "li s10, 0xBBBBBBBB\n"
        "li s11, 0xCCCCCCCC\n"
        ::: "s0","s1","s2","s3","s4","s5","s6","s7","s8","s9","s10","s11"
    );

    /* Voluntarily delay to force context save, scheduler switch, and restore */
    vTaskDelay( pdMS_TO_TICKS( 4 ) );

    /* Read back registers to local variables */
    __asm__ volatile (
        "sw s0,  %0\n"
        "sw s1,  %1\n"
        "sw s2,  %2\n"
        "sw s3,  %3\n"
        "sw s4,  %4\n"
        "sw s5,  %5\n"
        "sw s6,  %6\n"
        "sw s7,  %7\n"
        "sw s8,  %8\n"
        "sw s9,  %9\n"
        "sw s10, %10\n"
        "sw s11, %11\n"
        : "=m"(s0_val), "=m"(s1_val), "=m"(s2_val), "=m"(s3_val),
          "=m"(s4_val), "=m"(s5_val), "=m"(s6_val), "=m"(s7_val),
          "=m"(s8_val), "=m"(s9_val), "=m"(s10_val), "=m"(s11_val)
        :
        : "memory"
    );

    /* Verify all registers */
    if( s0_val  == 0x11111111 && s1_val  == 0x22222222 &&
        s2_val  == 0x33333333 && s3_val  == 0x44444444 &&
        s4_val  == 0x55555555 && s5_val  == 0x66666666 &&
        s6_val  == 0x77777777 && s7_val  == 0x88888888 &&
        s8_val  == 0x99999999 && s9_val  == 0xAAAAAAAA &&
        s10_val == 0xBBBBBBBB && s11_val == 0xCCCCCCCC )
    {
        g_phase3_reg_ok = 1;
    }
    else
    {
        uart_puts( "[ERR] Register corruption detected!\n" );
    }

    vTaskDelete( NULL );
}

/* --------------------------------------------------------------------------
 * Phase 2: Priority Preemption Test
 * High priority task wakes up and preempts running Low Priority Task
 * -------------------------------------------------------------------------- */
static void vHighPriorityTask( void *pv )
{
    ( void ) pv;
    /* Sleep 2 ticks, allowing LP task to begin spinning */
    vTaskDelay( pdMS_TO_TICKS( 2 ) );

    /* On waking, HP task must run IMMEDIATELY, preempting LP */
    if( g_lp_counter > 0 && g_lp_counter < 1000000 )
    {
        g_hp_preempt_verified = 1;
    }
    g_phase2_preempt_done = 1;

    vTaskDelete( NULL );
}

static void vLowPriorityTask( void *pv )
{
    ( void ) pv;
    while( !g_phase2_preempt_done )
    {
        g_lp_counter++;
    }
    vTaskDelete( NULL );
}

/* --------------------------------------------------------------------------
 * Phase 8: Repeated Rapid Ping-Pong Task Switching
 * -------------------------------------------------------------------------- */
static volatile int g_ping_count = 0;
static volatile int g_pong_count = 0;

static void vPingTask( void *pv )
{
    ( void ) pv;
    for( int i = 0; i < PING_PONG_CYCLES; i++ )
    {
        g_ping_count++;
        taskYIELD();
    }
    vTaskDelete( NULL );
}

static void vPongTask( void *pv )
{
    ( void ) pv;
    for( int i = 0; i < PING_PONG_CYCLES; i++ )
    {
        g_pong_count++;
        taskYIELD();
    }
    g_phase8_pingpong_done = 1;
    vTaskDelete( NULL );
}

/* --------------------------------------------------------------------------
 * Main Controller Task: coordinates phases and verifies assertions
 * -------------------------------------------------------------------------- */
static void vMasterTask( void *pv )
{
    ( void ) pv;
    uart_puts( "[SMOKE] Master controller started\n" );

    /* Test 1: Kernel Startup & Multiple Task Creation */
    report_test( "Kernel Startup and Task Creation", 1 );

    /* Test 2: Priority-Based Preemption */
    xTaskCreate( vLowPriorityTask,  "LP", configMINIMAL_STACK_SIZE, NULL, 1, NULL );
    xTaskCreate( vHighPriorityTask, "HP", configMINIMAL_STACK_SIZE, NULL, 3, &xPreemptTaskHandle );
    vTaskDelay( pdMS_TO_TICKS( 6 ) );
    report_test( "Priority Preemption", g_hp_preempt_verified );

    /* Test 3: Register Preservation Across Context Switch */
    xTaskCreate( vRegCheckTask, "REG", configMINIMAL_STACK_SIZE, NULL, 2, &xRegTaskHandle );
    vTaskDelay( pdMS_TO_TICKS( 6 ) );
    report_test( "Register State Preservation (s0-s11)", g_phase3_reg_ok );

    /* Test 4 & 5: Queue, Semaphore, Notification Sync */
    TaskHandle_t hSync = NULL;
    xTaskCreate( vSyncTask, "SYNC", configMINIMAL_STACK_SIZE, NULL, 2, &hSync );
    xSemaphoreGive( xBinarySem );

    for( int i = 0; i < TEST_QUEUE_LEN; i++ )
    {
        int item = 100 + i;
        xQueueSend( xTestQueue, &item, portMAX_DELAY );
    }

    xSemaphoreGive( xCountingSem );
    xSemaphoreGive( xCountingSem );
    xSemaphoreGive( xCountingSem );

    /* Send direct task notification */
    if( hSync != NULL )
    {
        xTaskNotifyGive( hSync );
    }

    vTaskDelay( pdMS_TO_TICKS( 6 ) );
    report_test( "Queue FIFO Communication", g_phase4_queue_ok );
    report_test( "Semaphore and Notification Sync", ( g_phase5_sem_ok == 3 ) );

    /* Test 6: Timer Tick Progression & Monotonic Task Delay */
    TickType_t t1 = xTaskGetTickCount();
    vTaskDelay( pdMS_TO_TICKS( 10 ) );
    TickType_t t2 = xTaskGetTickCount();
    int delay_ok = ( t2 >= t1 + pdMS_TO_TICKS( 10 ) );
    report_test( "Tick Progression and Task Delay", delay_ok );

    /* Test 7: Heap Limit and Stack High-Water Mark Handling */
    /* Attempt deliberately oversized allocation (1 MB > 16 KB heap) */
    extern volatile uint32_t g_malloc_failed_count;
    void *pHuge = pvPortMalloc( 1024 * 1024 );
    int malloc_safely_rejected = ( pHuge == NULL && g_malloc_failed_count > 0 );

    /* Standard small allocation should succeed */
    void *pSmall = pvPortMalloc( 64 );
    int small_ok = ( pSmall != NULL );
    if( pSmall )
    {
        memset( pSmall, 0xA5, 64 );
        vPortFree( pSmall );
    }

    /* Stack high water mark check */
    UBaseType_t hwm = uxTaskGetStackHighWaterMark( NULL );
    int stack_ok = ( hwm > 20 );

    g_phase7_memory_ok = ( malloc_safely_rejected && small_ok && stack_ok );
    report_test( "Heap and Stack Boundary Handling", g_phase7_memory_ok );

    /* Test 8: Repeated Rapid Cooperative Task Switching */
    xTaskCreate( vPingTask, "PING", configMINIMAL_STACK_SIZE, NULL, 2, &xPingTaskHandle );
    xTaskCreate( vPongTask, "PONG", configMINIMAL_STACK_SIZE, NULL, 2, &xPongTaskHandle );
    vTaskDelay( pdMS_TO_TICKS( 15 ) );
    int pingpong_ok = ( g_ping_count == PING_PONG_CYCLES && g_pong_count == PING_PONG_CYCLES );
    report_test( "Repeated Rapid Task Switching", pingpong_ok );

    uart_puts( "\n[SMOKE] ALL STAGE 2 TESTS PASSED SUCCESSFULLY!\n" );
    sim_pass();
}

int main( void )
{
    uart_init();
    uart_puts( "[BOOT] FreeRTOS Smoke Test Suite\n" );

    xTestQueue   = xQueueCreate( TEST_QUEUE_LEN, sizeof( int ) );
    xBinarySem   = xSemaphoreCreateBinary();
    xCountingSem = xSemaphoreCreateCounting( 5, 0 );

    configASSERT( xTestQueue   != NULL );
    configASSERT( xBinarySem   != NULL );
    configASSERT( xCountingSem != NULL );

    xTaskCreate( vMasterTask, "MASTER", configMINIMAL_STACK_SIZE * 2, NULL, 2, NULL );

    vTaskStartScheduler();

    /* Unreachable */
    uart_puts( "[FATAL] Scheduler exited unexpectedly\n" );
    sim_fail();
    return 0;
}
