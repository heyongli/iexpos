#ifndef VGA_DRV_H
#define VGA_DRV_H

#include "rtc.h"

struct fb_info {
    unsigned short width;
    unsigned short height;
    unsigned char  bpp;
    unsigned char  reserved[3];
    unsigned int   addr;
};

struct fb_ops {
    void (*init)(void);
    void (*putpixel)(int x, int y, unsigned int color);
    void (*fill_rect)(int x, int y, int w, int h, unsigned int color);
    void (*clear)(unsigned int color);
    int  (*get_width)(void);
    int  (*get_height)(void);
    void (*draw_char)(int x, int y, char c, unsigned int color);
    void (*draw_str)(int x, int y, const char *s, unsigned int color);
    void (*console_write)(const char *s);
    void (*console_flush)(void);
    void (*write_ts)(output_fn out);
};

extern const struct fb_ops vga;

#endif
