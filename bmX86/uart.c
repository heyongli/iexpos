#include "include/uart.h"

/* x86 serial hardware driver for 16550 UARTs
    WARNING: This module directly accesses x86 I/O ports (inb/outb).
    It cannot be used on other architectures without porting.

    Architecture:
    uart_iost() is the sole hardware poll primitive — it reads LSR
    and returns a _READ_READY|_WRITE_READY bitmask using standard IO
    semantics defined in io.h. All other UART functions are
    composed on top of uart_iost().

    Return value convention for try functions:
    - _IO_OK (0) = success
    - _IO_ERR | _NOT_READY = caller must handle (not ready)
    - _IO_ERR | _ABORT = caller must handle (IO aborted)
    - result < 0 means caller must handle the situation

    Hardware:
    - UART base address: 0x3F8 (COM1)
    - Line Status Register (LSR): 0x3FD
    - Transmit Holding Register (THR): 0x3F8 (write-only)
    - Receive Buffer Register (RBR): 0x3F8 (read-only)
    - Modem Control Register (MCR): 0x3FC

    LSR bits (0x3FD):
    - Bit 0: DATA READY (1 = data in RBR)    → _READ_READY
    - Bit 5: THR EMPTY (1 = THR ready)       → _WRITE_READY
    - Bit 6: TRANSMITTER EMPTY (1 = all sent)
*/

int uart_try_write(unsigned char c) {
    if (io_abort_test()) return _IO_ERR | _ABORT;
    if (uart_iost() & _WRITE_READY) {
        __asm__ volatile("outb %0, %1" : : "a"(c), "Nd"(COM1));
        return _IO_OK;
    }
    return _IO_ERR | _NOT_READY;
}

int uart_try_read(unsigned char *c) {
    if (io_abort_test()) return _IO_ERR | _ABORT;
    if (uart_iost() & _READ_READY) {
        __asm__ volatile("inb %1, %0" : "=a"(*c) : "Nd"(COM1));
        return _IO_OK;
    }
    return _IO_ERR | _NOT_READY;
}

int uart_busy_write(unsigned char c) {
    /* Busy write: spin until THR is empty or abort detected.
       Returns _IO_OK on success, _IO_ERR | _ABORT on abort. */
    while (!(uart_iost() & _WRITE_READY)) {
        if (io_abort_test()) return _IO_ERR | _ABORT;
    }
    __asm__ volatile("outb %0, %1" : : "a"(c), "Nd"(COM1));
    return _IO_OK;
}

int uart_busy_read(unsigned char *c) {
    /* Busy read: spin until DATA READY or abort detected.
       Returns _IO_OK on success, _IO_ERR | _ABORT on abort. */
    while (!(uart_iost() & _READ_READY)) {
        if (io_abort_test()) return _IO_ERR | _ABORT;
    }
    __asm__ volatile("inb %1, %0" : "=a"(*c) : "Nd"(COM1));
    return _IO_OK;
}

void uart_init(void) {
    /* Clear MCR (0x3FC) — QEMU default leaves Loopback (bit 4) set,
       which disconnects the chardev (TCP/file) from UART RX.  Without
       this, external bytes never reach RBR and LSR.DR stays 0. */
    __asm__ volatile("outb %0, %1" : : "a"((unsigned char)0), "Nd"((unsigned short)COM1_MCR));
}

int uart_iost(void) {
    /* The sole hardware poll primitive — reads LSR and returns
       a bitmask using standard IO semantics (_READ_READY, _WRITE_READY)
       defined in io.h. All other UART functions compose on this. */
    unsigned char lsr;
    __asm__ volatile("inb %1, %0" : "=a"(lsr) : "Nd"(COM1_LSR));
    int ready = _IO_OK;
    if (lsr & 1) ready |= _READ_READY;
    if (lsr & 0x20) ready |= _WRITE_READY;
    return ready;
}