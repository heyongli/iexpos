#include "baremetal.h"
#include "demos/demos.h"
#include "gdb_stub.h"

static void write_dec(int val);

void setup_main(void) {
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

    gdb_stub_init();
    bm_puts("gdb stub init done\n");
    serial_rw_test();

    bm_ui_clear(0x0f1729);
    bm_flush();
    bm_swap();

    bm_puts("gdb stub done\n");

    demo_orbit();

    bm_puts("Graphics test complete\n");

    while (1)
        gdb_poll();
}

static void write_dec(int val) {
    char buf[12], *p = buf + sizeof(buf);
    *--p = 0;
    if (!val) *--p = '0';
    while (val) { *--p = '0' + val % 10; val /= 10; }
    bm_puts(p);
}
