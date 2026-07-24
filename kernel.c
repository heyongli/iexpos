#include "baremetal.h"

static void write_dec(int val);

void kernel_main(void) {
    bm_puts("entry\n");
    bm_init();
    bm_puts("vga init done\n");
    bm_puts("Graphics init OK\n");
    bm_puts("Resolution: ");
    write_dec(bm_ui_width());
    bm_puts("x");
    write_dec(bm_ui_height());
    bm_puts("x");
    write_dec(bm_ui_bpp());
    bm_puts("\n");
    bm_flush();
    bm_ui_clear(0x001020);
    bm_ui_fill_rect(50, 50, 200, 200, 0x0000FF);
    bm_ui_fill_rect(300, 50, 200, 200, 0x00FF00);
    bm_ui_fill_rect(550, 50, 200, 200, 0xFF0000);
    bm_ui_fill_rect(50, 300, 200, 200, 0xFFFF00);
    bm_ui_fill_rect(300, 300, 200, 200, 0x00FFFF);
    bm_ui_fill_rect(550, 300, 200, 200, 0xFF00FF);
    bm_puts("Graphics test complete\n");
    while (1)
        ;
}

static void write_dec(int val) {
    char buf[12], *p = buf + sizeof(buf);
    *--p = 0;
    if (!val) *--p = '0';
    while (val) { *--p = '0' + val % 10; val /= 10; }
    bm_puts(p);
}
