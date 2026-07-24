#include "console.h"
#include "baremetal.h"
#include "bmX86/include/serial_dev.h"

#define CON_BUF_SIZE 4096

static char con_buf[CON_BUF_SIZE];
static int con_start;
static int con_len;
static int con_overflow;
static int at_line_start = 1;

static struct console_be *backends[4];
static int n_be;

/* UART write via serial device layer */
static void serial_write(const char *s, int len) {
    serial_dev_write(s, len);
}

static struct console_be serial_be = { serial_write, 0 };

static void buf_put(char c) {
    if (con_len < CON_BUF_SIZE) {
        con_buf[(con_start + con_len) % CON_BUF_SIZE] = c;
        con_len++;
    } else {
        con_buf[con_start] = c;
        con_start = (con_start + 1) % CON_BUF_SIZE;
        con_overflow = 1;
    }
}

void console_register_be(struct console_be *be) {
    if (n_be >= 4)
        return;
    if (con_overflow) {
        char m[] = "\n~~(overflow)~~\n";
        for (int i = 0; m[i]; i++)
            be->write(&m[i], 1);
    }
    for (int i = 0; i < con_len; i++)
        be->write(&con_buf[(con_start + i) % CON_BUF_SIZE], 1);
    backends[n_be++] = be;
}

void console_write(const char *s) {
    if (!n_be)
        console_register_be(&serial_be);

    for (const char *p = s; *p; p++) {
        char c = *p;

        if (at_line_start && c != '\n') {
            char ts[9];
            bm_rtc_format(ts);
            for (int i = 0; i < 9; i++) {
                buf_put(ts[i]);
                for (int j = 0; j < n_be; j++)
                    backends[j]->write(&ts[i], 1);
            }
        }
        at_line_start = (c == '\n');

        buf_put(c);

        for (int j = 0; j < n_be; j++)
            backends[j]->write(&c, 1);
    }
}

void console_flush(void) {
    for (int j = 0; j < n_be; j++)
        if (backends[j]->flush)
            backends[j]->flush();
}

void bm_puts(const char *s) { console_write(s); }
void bm_flush(void) { console_flush(); }
