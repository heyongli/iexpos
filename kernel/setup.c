#include "baremetal.h"
#include "demo.h"
#include "gdb_stub.h"
#include "ui.h"
#include "silx/x86/io.h"
#include "silx/x86/include/os_regs.h"
#include "cli.h"

static void write_dec(int val);

void setup_main(void) {
    bm_puts("entry\n");
    bm_init();
    bm_puts("vga init done\n");
    ui_init();            /* register screen backend with console */

    if (!arch_io_abort_check()) {
        bm_puts("WARNING: CPU does not support io abort (CR4 bit 24)\n");
    }

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
    fb_swap();

    bm_puts("gdb stub done\n");

    /* Initialize CLI */
    cli_init();

    unsigned int last_frame = pit_read();

    while (1) {
        if (elapsed_pit(last_frame) > PIT_FRAME_TICKS) {
            demo_draw();
            fb_swap();
            last_frame = pit_read();
        }
        if (cli_is_active())
            cli_poll();
        else
            gdb_poll();
        if (is_aborting()) return;
    }
}

static void write_dec(int val) {
    char buf[12], *p = buf + sizeof(buf);
    *--p = 0;
    if (!val) *--p = '0';
    while (val) { *--p = '0' + val % 10; val /= 10; }
    bm_puts(p);
}
