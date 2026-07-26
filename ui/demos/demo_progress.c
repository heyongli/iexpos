#include "demo.h"
#include "ui.h"
#include "baremetal.h"
#include "console.h"

static int phase;
static int progress_done;
static int printed;

int demo_progress(void) {
    if (phase == 0) {
        progress_init();
        phase = 1;
        return 0;
    }
    progress_set(phase);
    phase++;
    if (phase > 100) {
        progress_text("done");
        phase = 0;
        return 1;
    }
    return 0;
}

void demo_draw(void) {
    bm_ui_clear(0x0f1729);
    console_flush();
    demo_orbit();
    if (!progress_done)
        progress_done = demo_progress();
    else
        progress_set(100);
    if (progress_done && !printed) {
        bm_puts("Graphics test complete\n");
        printed = 1;
    }
}
