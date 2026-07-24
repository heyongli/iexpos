#ifndef CONSOLE_H
#define CONSOLE_H

struct console_be {
    void (*write)(const char *s, int len);
    void (*flush)(void);
};

void console_write(const char *s);
void console_flush(void);
void console_register_be(struct console_be *be);

#endif
