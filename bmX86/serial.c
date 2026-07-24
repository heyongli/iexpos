#include "include/uart_dev.h"
#include "include/uart.h"

static struct uart_dev dev;
static int dev_initialized = 0;

static void uart_dev_write(const char *s, int len) {
    uart_write_buf(s, len);
}

static void uart_dev_flush(void) {
    /* No hardware flush needed for 16550 UART */
}

void uart_dev_init(void) {
    if (!dev_initialized) {
        dev.write = uart_dev_write;
        dev.flush = uart_dev_flush;
        dev_initialized = 1;
    }
}

void uart_dev_write(const char *s, int len) {
    uart_write_buf(s, len);
}

void uart_dev_flush(void) {
    /* No hardware flush needed for 16550 UART */
}
