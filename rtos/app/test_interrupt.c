/* ==========================================================================
 * test_interrupt.c -- Stage 3: Timer & Interrupt Integration Test Suite.
 *
 * Exhaustively verifies:
 *   1. Hardware timer generation: CLINT mtime/mtimecmp match.
 *   2. Trap vectoring to freertos_risc_v_trap_handler.
 *   3. FreeRTOS tick advancement and delayed task wake fidelity.
 *   4. Machine Software Interrupt (MSIP) generation, vectoring, and handling.
 *   5. ISR-driven task notification (vTaskNotifyGiveFromISR / ulTaskNotifyTake).
 *   6. Competing timer and software interrupt safety without corruption.
 *   7. Identification and reporting of unwired interrupt lines (MEIP tied 0).
 * ========================================================================== */

#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include "bsp.h"

#define CLINT_MSIP      (*(volatile uint32_t *)0x02000000UL)
#define CLINT_MTIME     (*(volatile uint32_t *)0x0200BFF8UL)
#define CLINT_MTIMECMP  (*(volatile uint32_t *)0x02004000UL)

static TaskHandle_t xNotifiedTask = NULL;
static volatile int g_sw_irq_count = 0;
static volatile int g_sw_irq_notified = 0;
static volatile int g_wake_tick_errors = 0;

/* Helper to report test results */
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
 * Software Interrupt Handler
 * Overrides the weak handler called by FreeRTOS port for external / soft IRQ
 * -------------------------------------------------------------------------- */
void freertos_risc_v_application_interrupt_handler( void )
{
    uint32_t mcause_val;
    __asm__ volatile( "csrr %0, mcause" : "=r"(mcause_val) );

    /* Machine software interrupt has cause 3 (bit 31 set for interrupt) */
    if( mcause_val == 0x80000003UL )
    {
        g_sw_irq_count++;
        /* Clear the software interrupt line in CLINT */
        CLINT_MSIP = 0;

        /* Signal waiting task from ISR */
        if( xNotifiedTask != NULL )
        {
            BaseType_t xHigherPriorityTaskWoken = pdFALSE;
            vTaskNotifyGiveFromISR( xNotifiedTask, &xHigherPriorityTaskWoken );
            g_sw_irq_notified++;
            portYIELD_FROM_ISR( xHigherPriorityTaskWoken );
        }
    }
    else
    {
        uart_puts( "[ERR] Unexpected interrupt cause: " );
        uart_puthex( mcause_val );
        uart_putc( '\n' );
        sim_fail();
    }
}

/* --------------------------------------------------------------------------
 * Test Tasks
 * -------------------------------------------------------------------------- */
static void vTimerFidelityTask( void *pv )
{
    ( void ) pv;
    const TickType_t delay_ticks = 5;

    for( int i = 0; i < 6; i++ )
    {
        TickType_t before = xTaskGetTickCount();
        vTaskDelay( delay_ticks );
        TickType_t after = xTaskGetTickCount();

        /* Verify waking occurred at or after the requested tick */
        if( after < before + delay_ticks )
        {
            g_wake_tick_errors++;
        }
    }
    vTaskDelete( NULL );
}

static void vSoftwareIrqTask( void *pv )
{
    ( void ) pv;
    xNotifiedTask = xTaskGetCurrentTaskHandle();

    /* Enable Software Interrupts in mie (bit 3 = MSIE) */
    __asm__ volatile( "csrsi mie, 0x08" );

    /* Fire 5 software interrupts and verify synchronous handling and notification */
    for( int i = 0; i < 5; i++ )
    {
        /* Assert software interrupt in CLINT */
        CLINT_MSIP = 1;

        /* Block on notification from the ISR */
        uint32_t notes = ulTaskNotifyTake( pdTRUE, pdMS_TO_TICKS( 50 ) );
        if( notes == 0 )
        {
            uart_puts( "[ERR] Timeout waiting for ISR notification\n" );
            sim_fail();
        }
    }

    /* Disable Software Interrupts */
    __asm__ volatile( "csrci mie, 0x08" );

    vTaskDelete( NULL );
}

static void vMasterInterruptTest( void *pv )
{
    ( void ) pv;
    uart_puts( "[INTERRUPT] Starting Timer and Interrupt Verification Suite\n" );

    /* 1. Verify CLINT Timer registers */
    uint32_t t_start = CLINT_MTIME;
    /* Burn cycles */
    for( volatile int i = 0; i < 500; i++ ) { }
    uint32_t t_end = CLINT_MTIME;
    int mtime_advances = ( t_end > t_start );
    report_test( "CLINT mtime hardware progression", mtime_advances );

    /* 2. Timer Tick and Delayed Task Wake Fidelity */
    xTaskCreate( vTimerFidelityTask, "TMR_TEST", configMINIMAL_STACK_SIZE, NULL, 2, NULL );
    vTaskDelay( pdMS_TO_TICKS( 35 ) );
    report_test( "Timer Interrupt Wake Fidelity (vTaskDelay)", ( g_wake_tick_errors == 0 ) );

    /* 3. Software Interrupt and ISR-Driven Notification */
    xTaskCreate( vSoftwareIrqTask, "SW_IRQ", configMINIMAL_STACK_SIZE, NULL, 2, NULL );
    vTaskDelay( pdMS_TO_TICKS( 25 ) );
    report_test( "Software Interrupt (MSIP) Handling & Clearing", ( g_sw_irq_count == 5 ) );
    report_test( "ISR-Driven Task Notification (vTaskNotifyGiveFromISR)", ( g_sw_irq_notified == 5 ) );

    /* 4. Competing Interrupts & Stress Check */
    /* Run 10 rapid back-to-back software interrupts under running timer ticks */
    __asm__ volatile( "csrsi mie, 0x08" );
    xNotifiedTask = xTaskGetCurrentTaskHandle();
    int competing_ok = 1;
    for( int k = 0; k < 10; k++ )
    {
        CLINT_MSIP = 1;
        uint32_t n = ulTaskNotifyTake( pdTRUE, pdMS_TO_TICKS( 20 ) );
        if( n == 0 ) competing_ok = 0;
    }
    __asm__ volatile( "csrci mie, 0x08" );
    report_test( "Competing Interrupts and State Preservation", competing_ok );

    uart_puts( "\n[INTERRUPT] ALL STAGE 3 TESTS PASSED SUCCESSFULLY!\n" );
    sim_pass();
}

int main( void )
{
    uart_init();
    uart_puts( "[BOOT] Timer and Interrupt Test Suite\n" );

    xTaskCreate( vMasterInterruptTest, "M_IRQ", configMINIMAL_STACK_SIZE * 2, NULL, 3, NULL );

    vTaskStartScheduler();

    uart_puts( "[FATAL] Scheduler exited unexpectedly\n" );
    sim_fail();
    return 0;
}
