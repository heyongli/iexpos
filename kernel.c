#include "baremetal.h"
#include "progress.h"

static void write_dec(int val);

void kernel_main(void) {
    bm_puts("entry\n");
    bm_init();
    bm_puts("vga init done\n");

    progress_init();
    progress_text("console");
    progress_set(20);

    bm_puts("Graphics init OK\n");
    progress_set(40);
    progress_text("resolution");

    bm_puts("Resolution: ");
    write_dec(bm_ui_width());
    bm_puts("x");
    write_dec(bm_ui_height());
    bm_puts("x");
    write_dec(bm_ui_bpp());
    bm_puts("\n");
    progress_set(60);
    progress_text("render");

    bm_ui_clear(0x001020);
    bm_flush();
    progress_set(75);
    progress_text("rectangles");

    bm_ui_fill_rect(50,  420, 200, 200, 0x0000FF);
    bm_ui_fill_rect(300, 420, 200, 200, 0x00FF00);
    bm_ui_fill_rect(550, 420, 200, 200, 0xFF0000);
    bm_ui_fill_rect(50,  660, 200, 200, 0xFFFF00);
    bm_ui_fill_rect(300, 660, 200, 200, 0x00FFFF);
    bm_ui_fill_rect(550, 660, 200, 200, 0xFF00FF);
    progress_set(90);
    progress_text("done");

    bm_puts("Graphics test complete\n");
    bm_flush();
    progress_set(100);
    progress_text("done");

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
