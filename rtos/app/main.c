/* ==========================================================================
 * main.c -- 3-SIPP-ESR FreeRTOS demo.
 *
 * Proves a REAL preemptive RTOS running on the 3-SIPP-ESR core:
 *   - Two tasks context-switching under PREEMPTIVE CLINT timer ticks.
 *   - A producer/consumer QUEUE (Producer -> Consumer, integer payloads).
 *   - A counting SEMAPHORE (Producer gives, Consumer takes).
 *   - A compute-bound "Worker" task that must be PREEMPTED by the tick (it
 *     never blocks voluntarily), proving the tick -- not cooperative yielding
 *     -- drives the scheduler.
 *
 * All console output goes through the 3-SIPP-ESR UART; the sim captures it. The
 * Python harness (run_rtos.py) asserts the interleaving + queue values.
 *
 * Transcript vocabulary (stable, machine-checkable):
 *   [BOOT]freertos            once, before scheduler start
 *   [P]send:N                 Producer enqueued value N
 *   [C]got:N                  Consumer dequeued value N
 *   [C]sem                    Consumer took the counting semaphore
 *   [W]run@T                  Worker observed tick-count T (preemption witness)
 *   [DONE]ok                  demo finished -> tohost PASS
 * ========================================================================== */
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semphr.h"
#include "bsp.h"

#define NUM_ITEMS      8          /* how many items the producer sends */
#define QUEUE_LEN      4

static QueueHandle_t     xQueue;
static SemaphoreHandle_t xSem;

/* tick counter sampled by the worker to witness preemption */
static volatile uint32_t g_worker_ticks_seen = 0;
static volatile int      g_consumed = 0;
static volatile int      g_sem_taken = 0;

/* ---- Producer: sends 1..NUM_ITEMS into the queue + gives the semaphore ---- */
static void vProducer( void *pv )
{
    ( void ) pv;
    int i;
    for( i = 1; i <= NUM_ITEMS; i++ )
    {
        /* block up to a few ticks if the queue is full (back-pressure) */
        xQueueSend( xQueue, &i, portMAX_DELAY );
        uart_puts( "[P]send:" ); uart_putdec( i ); uart_putc( '\n' );

        xSemaphoreGive( xSem );          /* signal one unit of work available */

        vTaskDelay( pdMS_TO_TICKS( 5 ) ); /* pace the producer -> Worker window */
    }
    vTaskDelete( NULL );
}

/* ---- Consumer: takes semaphore, then dequeues, prints value --------------- */
static void vConsumer( void *pv )
{
    ( void ) pv;
    int rx;
    for( ;; )
    {
        /* wait for the "work available" signal (counting semaphore) */
        if( xSemaphoreTake( xSem, portMAX_DELAY ) == pdTRUE )
        {
            g_sem_taken++;
            uart_puts( "[C]sem\n" );
        }
        /* now pull the matching item from the queue */
        if( xQueueReceive( xQueue, &rx, portMAX_DELAY ) == pdTRUE )
        {
            g_consumed++;
            uart_puts( "[C]got:" ); uart_putdec( rx ); uart_putc( '\n' );

            if( g_consumed == NUM_ITEMS )
            {
                uart_puts( "[DONE]ok\n" );
                sim_pass();
            }
        }
    }
}

/* ---- Worker: CPU-bound, NEVER blocks. Only the preemptive tick can move the
 *      scheduler off it. It samples the FreeRTOS tick count; if it ever sees
 *      the count advance while it is running, a timer interrupt preempted it. */
static void vWorker( void *pv )
{
    ( void ) pv;
    volatile uint32_t spin;
    TickType_t last = xTaskGetTickCount();
    int reports = 0;
    for( ;; )
    {
        /* burn CPU without yielding */
        for( spin = 0; spin < 4000; spin++ ) { }

        TickType_t now = xTaskGetTickCount();
        if( now != last )
        {
            /* the tick advanced while we were busy-looping => we were preempted
             * (and resumed) across a timer interrupt. */
            last = now;
            g_worker_ticks_seen = (uint32_t) now;
            if( reports < 6 )
            {
                uart_puts( "[W]run@" ); uart_putdec( (int32_t) now ); uart_putc( '\n' );
                reports++;
            }
        }
    }
}

#ifdef NEG_NO_TICK
/* ---- NEGATIVE CONTROL ----------------------------------------------------
 * Override the (weak) port timer setup with a no-op so the CLINT mtimecmp is
 * left at its reset value (0xFFFF...) and the machine timer interrupt NEVER
 * fires. With no tick: xTaskIncrementTick never runs, no preemption happens,
 * and vTaskDelay() blocks forever -- so the Producer stalls after item 1, the
 * Consumer starves, and [DONE]ok is NEVER reached. This proves the preemptive
 * tick is load-bearing: remove it and the identical software cannot make
 * progress. */
void vPortSetupTimerInterrupt( void )
{
    uart_puts( "[NEG]tick-disabled\n" );   /* mtimecmp left at reset -> no IRQ */
}
#endif

void main( void )
{
    uart_init();
    uart_puts( "[BOOT]freertos\n" );

    xQueue = xQueueCreate( QUEUE_LEN, sizeof( int ) );
    xSem   = xSemaphoreCreateCounting( NUM_ITEMS, 0 );
    configASSERT( xQueue != NULL );
    configASSERT( xSem   != NULL );

    /* Consumer highest so it drains promptly; Worker lowest (background CPU
     * hog) so it only runs when A/B are blocked -- and gets preempted. */
    xTaskCreate( vConsumer, "C", configMINIMAL_STACK_SIZE, NULL, 3, NULL );
    xTaskCreate( vProducer, "P", configMINIMAL_STACK_SIZE, NULL, 2, NULL );
    xTaskCreate( vWorker,   "W", configMINIMAL_STACK_SIZE, NULL, 1, NULL );

    vTaskStartScheduler();

    /* never reached */
    uart_puts( "[FATAL]scheduler returned\n" );
    sim_fail();
}
