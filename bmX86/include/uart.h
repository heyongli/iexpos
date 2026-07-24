#ifndef UART_DRV_H
#define UART_DRV_H

/* 16550 UART serial driver for bare metal x86 */

#define COM1            0x3F8      /* UART base port */
#define COM1_LSR        0x3FD      /* Line Status Register */

/* Hardware-level UART operations (I/O port accesses) */
void uart_peak_write(unsigned char c);       /* non-blocking write to UART */
void uart_poll_write(unsigned char c);       /* blocking write, wait for THR empty */
unsigned char uart_poll_in(void);            /* blocking read, wait for data */
void uart_write_buf(const char *s, int len); /* write buffer (uses poll_write) */
int  uart_peak(void);                        /* non-blocking check if data available */

#endif
