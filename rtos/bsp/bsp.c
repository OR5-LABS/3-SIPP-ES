/* three_sipp_es BSP: UART console driver + sim exit + FreeRTOS support stubs. */
#include "bsp.h"
#include "FreeRTOS.h"
#include "task.h"

/* ---- UART ---------------------------------------------------------------- */
/* In simulation we don't need a realistic baud rate -- shrink clocks-per-bit
 * to the minimum so the console transcript completes within the cycle budget.
 * (The FPGA build keeps the real 115200 default.) */
void uart_init( void )
{
    UART_BAUDDIV = 2;      /* ~2 cycles/bit -> ~20 cycles per 10-bit frame */
}

void uart_putc( char c )
{
    /* Wait until the TX shifter is free, then push the byte. In simulation the
     * SoC UART also $writes the byte, so the transcript captures the console. */
    while( UART_STATUS & UART_ST_TXBUSY ) { }
    UART_TXDATA = (uint8_t) c;
}

void uart_puts( const char *s )
{
    while( *s ) uart_putc( *s++ );
}

void uart_putdec( int32_t v )
{
    char buf[ 12 ];
    int  i = 0;
    uint32_t u;
    if( v < 0 ) { uart_putc( '-' ); u = (uint32_t)( -v ); }
    else        { u = (uint32_t) v; }
    if( u == 0 ) { uart_putc( '0' ); return; }
    while( u ) { buf[ i++ ] = (char)( '0' + ( u % 10 ) ); u /= 10; }
    while( i ) uart_putc( buf[ --i ] );
}

void uart_puthex( uint32_t v )
{
    const char *h = "0123456789abcdef";
    int i;
    uart_puts( "0x" );
    for( i = 28; i >= 0; i -= 4 )
        uart_putc( h[ ( v >> i ) & 0xF ] );
}

/* ---- sim exit ------------------------------------------------------------ */
void sim_pass( void ) { TOHOST = 1u; for(;;){} }
void sim_fail( void ) { TOHOST = 2u; for(;;){} }

/* ---- FreeRTOS support stubs ---------------------------------------------- */
void vAssertCalled( const char *pcFile, unsigned long ulLine )
{
    (void) pcFile; (void) ulLine;
    taskDISABLE_INTERRUPTS();
    uart_puts( "\n[ASSERT] " );
    uart_puts( pcFile );
    uart_putc( ':' );
    uart_putdec( (int32_t) ulLine );
    uart_putc( '\n' );
    sim_fail();
}

/* handle_exception path calls this for any non-ecall synchronous exception. */
void freertos_risc_v_application_exception_handler( void )
{
    uart_puts( "\n[TRAP] unexpected exception\n" );
    sim_fail();
}

void freertos_risc_v_application_interrupt_handler( void )
{
    uart_puts( "\n[TRAP] unexpected interrupt\n" );
    sim_fail();
}
