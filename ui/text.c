#include "ui.h"
#include "baremetal.h"
#include "console.h"
#include "font_8x16.h"
#include "io.h"

/* ---- screen backend (25×80 grid for console) ---- */

#define SCR_ROWS 25
#define SCR_COLS 80

static char scr_grid[SCR_ROWS][SCR_COLS];
static int scr_row;
static int scr_col;

static void scr_scroll(void) {
    int i, j;
    for (i = 0; i < SCR_ROWS - 1; i++)
        for (j = 0; j < SCR_COLS; j++)
            scr_grid[i][j] = scr_grid[i + 1][j];
    for (j = 0; j < SCR_COLS; j++)
        scr_grid[SCR_ROWS - 1][j] = ' ';
    scr_row = SCR_ROWS - 1;
}

static void scr_be_write(const char *s, int len) {
    int i;
    for (i = 0; i < len; i++) {
        char c = s[i];
        if (c == '\n') {
            scr_col = 0;
            scr_row++;
            if (scr_row >= SCR_ROWS)
                scr_scroll();
        } else if (c >= ' ') {
            if (scr_col < SCR_COLS)
                scr_grid[scr_row][scr_col++] = c;
            if (scr_col >= SCR_COLS) {
                scr_col = 0;
                scr_row++;
                if (scr_row >= SCR_ROWS)
                    scr_scroll();
            }
        }
    }
}

static void scr_be_flush(void) {
    int i, j;
    if (bm_ui_ready() != _IO_OK)
        return;
    int fw = bm_ui_width();
    int fh = bm_ui_height();
    for (i = 0; i <= scr_row; i++) {
        int yy = 2 + i * FONT_HEIGHT;
        if (yy + FONT_HEIGHT > fh)
            break;
        for (j = 0; j < SCR_COLS; j++) {
            if (scr_grid[i][j])
                ui_draw_char(2 + j * FONT_WIDTH, yy,
                             (unsigned char)scr_grid[i][j],
                             0xFFFFFF, 0);
        }
    }
}

static struct console_be scr_be = { scr_be_write, scr_be_flush };

/* ---- scaled font rendering uses fill_rect per glyph pixel ---- */

static void draw_char_scaled(int x, int y, char c, unsigned int color, int sz) {
    unsigned char ch = (unsigned char)c;
    if (ch < FONT_FIRST || ch > FONT_LAST) ch = '?';
    if (ch < FONT_FIRST) return;
    unsigned int idx = ch - FONT_FIRST;
    int row, col, dy, dx;
    for (row = 0; row < FONT_HEIGHT; row++) {
        unsigned char bits = font8x16[idx][row];
        for (col = 0; col < FONT_WIDTH; col++) {
            if (!(bits & (0x80 >> col)))
                continue;
            for (dy = 0; dy < sz; dy++)
                for (dx = 0; dx < sz; dx++)
                    bm_ui_fill_rect(x + col * sz + dx, y + row * sz + dy,
                                    1, 1, color);
        }
    }
}

/* ---- ui API (text rendering, font-aware) ---- */

static void draw_char_1x(int x, int y, char c, unsigned int color) {
    int row, col;
    unsigned char ch = (unsigned char)c;
    if (ch < FONT_FIRST || ch > FONT_LAST)
        ch = '?';
    if (ch < FONT_FIRST)
        return;
    unsigned int idx = ch - FONT_FIRST;
    for (row = 0; row < FONT_HEIGHT; row++) {
        unsigned char bits = font8x16[idx][row];
        for (col = 0; col < FONT_WIDTH; col++)
            if (bits & (0x80 >> col))
                bm_ui_fill_rect(x + col, y + row, 1, 1, color);
    }
}

void ui_draw_char(int x, int y, unsigned char c, unsigned int fg, unsigned int bg) {
    (void)bg;
    draw_char_1x(x, y, (char)c, fg);
}

void ui_draw_str(int x, int y, const char *s, unsigned int fg, unsigned int bg) {
    (void)bg;
    while (*s) {
        draw_char_1x(x, y, *s++, fg);
        x += FONT_WIDTH;
    }
}

void ui_draw_char_sz(int x, int y, unsigned char c, unsigned int fg, int sz) {
    draw_char_scaled(x, y, (char)c, fg, sz);
}

void ui_draw_str_sz(int x, int y, const char *s, unsigned int fg, int sz) {
    while (*s) {
        draw_char_scaled(x, y, *s++, fg, sz);
        x += FONT_WIDTH * sz;
    }
}

/* ---- UI init ---- */

void ui_init(void) {
    console_register_be(&scr_be);
}
