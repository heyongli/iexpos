#ifndef UART_DRV_H
#define UART_DRV_H

#include "io_defs.h"

/* 16550 UART serial driver for bare metal x86 */

#define COM1            0x3F8      /* UART base port */
#define COM1_LSR        0x3FD      /* Line Status Register */
#define COM1_MCR        0x3FC      /* Modem Control Register */

/* UART poll readiness — the foundational hardware poll primitive.
   Returns a bitmask using standard IO semantics (READ_READY, WRITE_READY)
   as defined in io_defs.h. All other UART functions compose on this. */
int  uart_peak(void);

/* Hardware-level UART operations, composed on uart_peak() */
void uart_init(void);              /* clear MCR loopback, init UART硬件 */
void uart_peak_write(unsigned char c);       /* non-blocking write to UART */
void uart_poll_write(unsigned char c);       /* blocking write, wait for THR empty */
unsigned char uart_poll_in(void);            /* blocking read, wait for data */
void uart_write_buf(const char *s, int len); /* write buffer (uses poll_write) */

#endif
