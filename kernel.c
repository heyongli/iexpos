#include "baremetal.h"
#include "ui.h"

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

    bm_ui_clear(0x0f1729);
    bm_flush();

    bm_ui_fill_rect(412, 420, 96, 96, 0x60a5fa);
    bm_ui_fill_rect(516, 420, 96, 96, 0x34d399);
    bm_ui_fill_rect(412, 524, 96, 96, 0xf472b6);
    bm_ui_fill_rect(516, 524, 96, 96, 0xfbbf24);

    progress_init();
    {
        unsigned char h, m, s0;
        int cur = 0;
        bm_rtc_read(&h, &m, &s0);
        progress_set(0);
        while (cur < 100) {
            unsigned char s;
            bm_rtc_read(&h, &m, &s);
            int diff = s - s0;
            if (diff < 0) diff += 60;
            int t = diff * 20;
            if (t > 100) t = 100;
            while (cur < t) { cur++; progress_set(cur); }
        }
        progress_text("done");
    }

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
