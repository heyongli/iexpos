#include "ui.h"
#include "baremetal.h"

#define BAR_H  20
#define BAR_C  0x222222
#define FILL_C 0x00AAFF
#define TXT_C  0xFFFFFF
#define INF_C  0xCCCCCC

static int bx, by, bw, ready;
static int cur_pct;
static char cur_txt[32];

static void draw_bar(void) {
    int pad = 2, fw = bw - pad * 2, fh = BAR_H - pad * 2;
    bm_ui_fill_rect(bx + pad, by + pad, fw, fh, BAR_C);
    int fill = (fw * cur_pct) / 100;
    if (fill > 0)
        bm_ui_fill_rect(bx + pad, by + pad, fill, fh, FILL_C);
    int ty = by + (BAR_H - 16) / 2;
    char pbuf[4] = { '0' + cur_pct / 10, '0' + cur_pct % 10, '%', 0 };
    int pctx = bx + fw - 3 * 8 - 4;
    bm_ui_draw_str(pctx, ty, pbuf, TXT_C, 0);
    int infow = pctx - (bx + 4) - 4;
    if (infow > 0)
        bm_ui_fill_rect(bx + 4, ty, infow, 16, BAR_C);
    if (cur_txt[0])
        bm_ui_draw_str(bx + 4, ty, cur_txt, INF_C, 0);
}

void progress_init(void) {
    if (!bm_ui_ready()) return;
    bw = bm_ui_width();
    bx = 0;
    by = bm_ui_height() - BAR_H;
    cur_pct = 0;
    cur_txt[0] = 0;
    ready = 1;
    bm_ui_fill_rect(bx, by, bw, BAR_H, BAR_C);
    draw_bar();
}

void progress_set(int p) {
    if (!ready) return;
    if (p < 0) p = 0;
    if (p > 100) p = 100;
    cur_pct = p;
    draw_bar();
}

void progress_text(const char *s) {
    if (!ready) return;
    int i;
    for (i = 0; i < 31 && s[i]; i++)
        cur_txt[i] = s[i];
    cur_txt[i] = 0;
    draw_bar();
}
