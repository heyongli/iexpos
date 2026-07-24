#include "include/uart.h"

/* x86 serial hardware driver for 16550 UARTs
   WARNING: This module directly accesses x86 I/O ports (inb/outb).
   It cannot be used on other architectures without porting.
   
   Hardware:
   - UART base address: 0x3F8 (COM1)
   - Line Status Register (LSR): 0x3FD
   - Transmit Holding Register (THR): 0x3F8 (write-only)
   - Receive Buffer Register (RBR): 0x3F8 (read-only)
   
   LSR bits (0x3FD):
   - Bit 0: DATA READY (1 = data in RBR)
   - Bit 5: THR EMPTY (1 = THR ready for next byte)
   - Bit 6: TRANSMITTER EMPTY (1 = all data sent)
*/

void uart_peak_write(unsigned char c) {
    /* Write char to Transmit Holding Register (THR) without waiting
       Non-blocking: may lose data if THR is not empty */
    __asm__ volatile("outb %0, %1" : : "a"(c), "Nd"(COM1));
}

void uart_poll_write(unsigned char c) {
    /* Write char to THR, wait for THR empty first (polling) */
    unsigned char lsr;
    do {
        __asm__ volatile("inb %1, %0" : "=a"(lsr) : "Nd"(COM1_LSR));
    } while (!(lsr & 0x20));  /* THRE = 0: THR not empty, wait */
    __asm__ volatile("outb %0, %1" : : "a"(c), "Nd"(COM1));
}

unsigned char uart_poll_in(void) {
    /* Blocking poll read: wait for DATA READY by polling LSR.0
       Busy-wait until byte arrives */
    unsigned char lsr;
    do {
        __asm__ volatile("inb %1, %0" : "=a"(lsr) : "Nd"(COM1_LSR));
    } while (!(lsr & 1));  /* DR = 0: wait for data */
    
    /* Read from Receive Buffer Register (RBR)
       Reading clears DATA READY flag */
    unsigned char c;
    __asm__ volatile("inb %1, %0" : "=a"(c) : "Nd"(COM1));
    return c;
}

void uart_write_buf(const char *s, int len) {
    /* Write string sequentially using uart_poll_write() */
    for (int i = 0; i < len; i++) {
        uart_poll_write(s[i]);
    }
}

int uart_peak(void) {
    /* Non-blocking peek: check if data is available
       Return 1 if DATA READY, 0 otherwise */
    unsigned char lsr;
    __asm__ volatile("inb %1, %0" : "=a"(lsr) : "Nd"(COM1_LSR));
    return lsr & 1;
}
