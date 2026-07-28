#include "ui.h"
#include "baremetal.h"
#include "io.h"

#define BAR_H  48
#define BAR_C  0x1e293b
#define TXT_C  0xf1f5f9
#define INF_C  0x94a3b8

#define TXT_SZ  2

static int bx, by, bw, ready;
static int cur_pct;
static char cur_txt[32];

static void draw_bar(void) {
    int pad = 4, fw = bw - pad * 2, fh = BAR_H - pad * 2;
    bm_ui_fill_rect(bx, by, bw, BAR_H, BAR_C);
    int fill = (fw * cur_pct) / 100;
    if (fill > 0) {
        bm_ui_fill_rect(bx + pad, by + pad, fill, fh / 2, 0x94a3b8);
        bm_ui_fill_rect(bx + pad, by + pad + fh / 2, fill, fh - fh / 2, 0x64748b);
    }
    int tsz = TXT_SZ;
    int ch = 16 * tsz;
    int cw = 8 * tsz;
    int ty = by + (BAR_H - ch) / 2;
    char pbuf[4] = { '0' + cur_pct / 10, '0' + cur_pct % 10, '%', 0 };
    int pclen = 3;
    int pctx = bx + fw - pclen * cw - 4;
    int i;
    for (i = 0; i < pclen; i++)
        ui_draw_char_sz(pctx + 1 + i * cw, ty + 1, pbuf[i], 0x0f1729, tsz);
    for (i = 0; i < pclen; i++)
        ui_draw_char_sz(pctx + i * cw, ty, pbuf[i], TXT_C, tsz);
    int infow = pctx - (bx + 4) - 4;
    if (infow > 0)
        bm_ui_fill_rect(bx + 4, ty + 1, infow + 1, ch + 1, BAR_C);
    if (cur_txt[0]) {
        int len = 0;
        while (cur_txt[len]) len++;
        for (i = 0; i < len; i++)
            ui_draw_char_sz(bx + 4 + 1 + i * cw, ty + 1, cur_txt[i], 0x0f1729, tsz);
        for (i = 0; i < len; i++)
            ui_draw_char_sz(bx + 4 + i * cw, ty, cur_txt[i], INF_C, tsz);
    }
}

void progress_init(void) {
    if (bm_ui_ready() != _IO_OK) return;
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
