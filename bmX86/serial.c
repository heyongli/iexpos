#include "include/uart_dev.h"
#include "include/uart.h"

static struct serial_dev dev;
static int dev_initialized = 0;

static void serial_dev_write(const char *s, int len) {
    uart_write_buf(s, len);
}

static void serial_dev_flush(void) {
    /* No hardware flush needed for 16550 UART */
}

void serial_dev_init(void) {
    if (!dev_initialized) {
        dev.write = serial_dev_write;
        dev.flush = serial_dev_flush;
        dev_initialized = 1;
    }
}

void serial_dev_write(const char *s, int len) {
    uart_write_buf(s, len);
}

void serial_dev_flush(void) {
    /* No hardware flush needed for 16550 UART */
}
