#include "include/serial_dev.h"
#include "include/uart.h"

static struct serial_dev dev;
static int dev_initialized = 0;

void serial_dev_init(void) {
    if (!dev_initialized) {
        dev.write = serial_dev_write;
        dev.flush = (void (*)(void))0;
        dev_initialized = 1;
    }
}

void serial_dev_write(const char *s, int len) {
    for (int i = 0; i < len; i++)
        uart_busy_write(s[i]);
}

void serial_dev_flush(void) {
    /* No hardware flush needed for 16550 UART */
}