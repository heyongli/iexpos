#ifndef SERIAL_DEV_H
#define SERIAL_DEV_H

#include "uart.h"

/* Serial device interface */

struct serial_dev {
    void (*write)(const char *s, int len);
    void (*flush)(void);
};

void serial_dev_init(void);
void serial_dev_write(const char *s, int len);
void serial_dev_flush(void);

#endif