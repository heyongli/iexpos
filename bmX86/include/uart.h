#ifndef UART_DRV_H
#define UART_DRV_H

#include "io.h"
#include "os_regs.h"

/* 16550 UART serial driver for bare metal x86 */

#define COM1            0x3F8      /* UART base port */
#define COM1_LSR        0x3FD      /* Line Status Register */
#define COM1_MCR        0x3FC      /* Modem Control Register */

/* UART I/O status — the foundational hardware poll primitive.
   Returns a bitmask using standard IO semantics (_READ_READY, _WRITE_READY)
   as defined in io.h. All other UART functions compose on this. */
int  uart_iost(void);

/* Hardware-level UART operations, composed on uart_iost() */
void uart_init(void);              /* clear MCR loopback, init UART硬件 */
int  uart_try_write(unsigned char c);    /* non-blocking write, returns _IO_OK or _IO_ERR | error */
int  uart_try_read(unsigned char *c);     /* non-blocking read, returns _IO_OK or _IO_ERR | error */
int  uart_busy_write(unsigned char c);       /* busy write, returns _IO_OK or _IO_ERR | _ABORT */
int  uart_busy_read(unsigned char *c);       /* busy read, returns _IO_OK or _IO_ERR | _ABORT */

#endif
