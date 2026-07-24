#ifndef UART_DRV_H
#define UART_DRV_H

/* 16550 UART serial driver for bare metal x86 */

#define COM1            0x3F8      /* UART base port */
#define COM1_LSR        0x3FD      /* Line Status Register */

/* Hardware-level UART operations (I/O port accesses) */
void uart_write(unsigned char c);              /* write one char to UART */
unsigned char uart_in(void);                   /* read one char from UART (blocks) */
void uart_write_buf(const char *s, int len);   /* write buffer */
int  uart_read_avail(void);                    /* check if data available (non-blocking) */

#endif
