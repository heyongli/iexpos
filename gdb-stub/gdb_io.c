#include "gdb_io.h"
#include "uart.h"
#include "os_regs.h"
#include "io.h"

void gdb_io_init(void) {
    uart_init();
}

void gdb_io_write(unsigned char c) {
    uart_busy_write(c);
}

int gdb_io_read(unsigned char *c) {
    return uart_busy_read(c);
}

int gdb_io_try_read(unsigned char *c) {
    return uart_try_read(c);
}

int gdb_io_data_ready(void) {
    return uart_iost() & _READ_READY;
}

int gdb_io_abort_pending(void) {
    return is_aborting();
}

void gdb_io_loopback_test(void) {
    const unsigned char test[4] = { 0x55, 0xAA, '!', '\n' };
    unsigned char ok = 1;

    __asm__ volatile("outb %0, %1"
        : : "a"((unsigned char)0x10), "Nd"((unsigned short)COM1_MCR));

    for (int i = 0; i < 4; i++) {
        gdb_io_write(test[i]);
        unsigned char got;
        gdb_io_read(&got);
        if (got != test[i]) ok = 0;
    }

    __asm__ volatile("outb %0, %1"
        : : "a"((unsigned char)0), "Nd"((unsigned short)COM1_MCR));

    gdb_io_write('S'); gdb_io_write('R'); gdb_io_write('W');
    gdb_io_write(':'); gdb_io_write(ok ? 'P' : 'F'); gdb_io_write('\n');
}
