#ifndef UART_DEV_H
#define UART_DEV_H

/* UART device interface */

struct uart_dev {
    void (*write)(const char *s, int len);
    void (*flush)(void);
};

void uart_dev_init(void);
void uart_dev_write(const char *s, int len);
void uart_dev_flush(void);

#endif
