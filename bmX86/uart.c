#include "include/uart.h"

/* x86 serial hardware driver for 16550 UARTs
    WARNING: This module directly accesses x86 I/O ports (inb/outb).
    It cannot be used on other architectures without porting.

    Architecture:
    uart_peak() is the sole hardware poll primitive — it reads LSR
    and returns a READ_READY|WRITE_READY bitmask using standard IO
    semantics defined in io_defs.h. All other UART functions are
    composed on top of uart_peak().

    Hardware:
    - UART base address: 0x3F8 (COM1)
    - Line Status Register (LSR): 0x3FD
    - Transmit Holding Register (THR): 0x3F8 (write-only)
    - Receive Buffer Register (RBR): 0x3F8 (read-only)
    - Modem Control Register (MCR): 0x3FC

    LSR bits (0x3FD):
    - Bit 0: DATA READY (1 = data in RBR)    → READ_READY
    - Bit 5: THR EMPTY (1 = THR ready)       → WRITE_READY
    - Bit 6: TRANSMITTER EMPTY (1 = all sent)
*/

void uart_peak_write(unsigned char c) {
    /* Non-blocking write: write only if THR is empty.
       Returns without writing if UART is not ready. */
    if (uart_peak() & WRITE_READY) {
        __asm__ volatile("outb %0, %1" : : "a"(c), "Nd"(COM1));
    }
}

void uart_poll_write(unsigned char c) {
    /* Blocking write: poll until THR is empty, then write. */
    while (!(uart_peak() & WRITE_READY)) {}
    __asm__ volatile("outb %0, %1" : : "a"(c), "Nd"(COM1));
}

unsigned char uart_poll_in(void) {
    /* Blocking poll read: poll until DATA READY, then read RBR. */
    while (!(uart_peak() & READ_READY)) {}
    unsigned char c;
    __asm__ volatile("inb %1, %0" : "=a"(c) : "Nd"(COM1));
    return c;
}

void uart_init(void) {
    /* Clear MCR (0x3FC) — QEMU default leaves Loopback (bit 4) set,
       which disconnects the chardev (TCP/file) from UART RX.  Without
       this, external bytes never reach RBR and LSR.DR stays 0. */
    __asm__ volatile("outb %0, %1" : : "a"((unsigned char)0), "Nd"((unsigned short)COM1_MCR));
}

int uart_peak(void) {
    /* The sole hardware poll primitive — reads LSR and returns
       a bitmask using standard IO semantics (READ_READY, WRITE_READY)
       defined in io_defs.h. All other UART functions compose on this. */
    unsigned char lsr;
    __asm__ volatile("inb %1, %0" : "=a"(lsr) : "Nd"(COM1_LSR));
    int ready = 0;
    if (lsr & 1) ready |= READ_READY;
    if (lsr & 0x20) ready |= WRITE_READY;
    return ready;
}