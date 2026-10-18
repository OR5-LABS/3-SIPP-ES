/* three_sipp_es BSP: UART console + sim exit helpers. */
#ifndef THREE_SIPP_ES_BSP_H
#define THREE_SIPP_ES_BSP_H
#include <stdint.h>

/* SoC MMIO */
#define UART_BASE      0x10000000UL
#define UART_TXDATA    (*(volatile uint8_t  *)(UART_BASE + 0x0))
#define UART_STATUS    (*(volatile uint8_t  *)(UART_BASE + 0x0))
#define UART_RXDATA    (*(volatile uint8_t  *)(UART_BASE + 0x4))
#define UART_BAUDDIV   (*(volatile uint8_t  *)(UART_BASE + 0x8))
#define UART_ST_TXBUSY 0x1u

#define TOHOST         (*(volatile uint32_t *)0x20000000UL)

void    uart_init(void);              /* fast baud for sim */
void    uart_putc(char c);
void    uart_puts(const char *s);
void    uart_putdec(int32_t v);       /* signed decimal */
void    uart_puthex(uint32_t v);      /* 0x%08x */
void    sim_pass(void);               /* store 1 to tohost (TB: PASS) */
void    sim_fail(void);               /* store 2 to tohost (TB: FAIL) */

#endif
