#include "vga.h"
#include "font_8x16.h"
#include "rtc.h"

static struct fb_info fb;
static volatile unsigned char *fb_mem;

#define CON_ROWS 25
#define CON_COLS 80

static char con_buf[CON_ROWS][CON_COLS];
static int con_total;
static int con_row;
static int con_col;

static void outb(unsigned short port, unsigned char val) {
    __asm__ volatile("outb %0, %1" : : "a"(val), "Nd"(port));
}

static unsigned char inb(unsigned short port) {
    unsigned char val;
    __asm__ volatile("inb %1, %0" : "=a"(val) : "Nd"(port));
    return val;
}

static void outw(unsigned short port, unsigned short val) {
    __asm__ volatile("outw %0, %1" : : "a"(val), "Nd"(port));
}

static unsigned short inw(unsigned short port) {
    unsigned short val;
    __asm__ volatile("inw %1, %0" : "=a"(val) : "Nd"(port));
    return val;
}

static void outl(unsigned short port, unsigned int val) {
    __asm__ volatile("outl %0, %1" : : "a"(val), "Nd"(port));
}

static unsigned int inl(unsigned short port) {
    unsigned int val;
    __asm__ volatile("inl %1, %0" : "=a"(val) : "Nd"(port));
    return val;
}

static void serial_out(char c) {
    outb(0x3F8, (unsigned char)c);
}

/* ---- PCI ---- */

#define PCI_ADDR_PORT  0xCF8
#define PCI_DATA_PORT  0xCFC

static unsigned int pci_read(unsigned char bus, unsigned char dev,
                             unsigned char func, unsigned char offset) {
    unsigned int addr = 0x80000000u | ((unsigned int)bus << 16)
                      | ((unsigned int)dev << 11)
                      | ((unsigned int)func << 8)
                      | (offset & 0xFC);
    outl(PCI_ADDR_PORT, addr);
    return inl(PCI_DATA_PORT);
}

static unsigned int pci_find_vga_bar0(void) {
    unsigned int bus, dev;
    for (bus = 0; bus < 256; bus++)
        for (dev = 0; dev < 32; dev++) {
            unsigned int id = pci_read(bus, dev, 0, 0);
            if ((id & 0xFFFF) == 0xFFFF)
                continue;
            unsigned int class = pci_read(bus, dev, 0, 8);
            if ((class >> 16) == 0x0300) {
                unsigned int bar0 = pci_read(bus, dev, 0, 0x10);
                return bar0 & 0xFFFFFFF0u;
            }
        }
    return 0;
}

/* ---- Bochs VBE ---- */

#define VBE_PORT_IDX  0x1CE
#define VBE_PORT_DATA 0x1CF

#define VBE_ID      0
#define VBE_XRES    1
#define VBE_YRES    2
#define VBE_BPP     3
#define VBE_ENABLE  4

#define VBE_DISABLED     0x00
#define VBE_ENABLED      0x01
#define VBE_LFB_ENABLED  0x40

static unsigned short vbe_read_reg(unsigned short idx) {
    outw(VBE_PORT_IDX, idx);
    return inw(VBE_PORT_DATA);
}

static void vbe_write_reg(unsigned short idx, unsigned short val) {
    outw(VBE_PORT_IDX, idx);
    outw(VBE_PORT_DATA, val);
}

static int vbe_try_init(void) {
    vbe_write_reg(VBE_ID, 0xB0C0);
    if (vbe_read_reg(VBE_ID) < 0xB0C0)
        return 0;

    vbe_write_reg(VBE_ENABLE, VBE_DISABLED);
    vbe_write_reg(VBE_XRES, 1024);
    vbe_write_reg(VBE_YRES, 768);
    vbe_write_reg(VBE_BPP, 32);
    vbe_write_reg(VBE_ENABLE, VBE_ENABLED | VBE_LFB_ENABLED);

    return 1;
}

/* ---- VGA mode 0x13 ---- */

static void vga_set_mode13(void) {
    int i;

    outb(0x3C2, 0x63);

    outb(0x3C4, 0x00); outb(0x3C5, 0x03);
    outb(0x3C4, 0x01); outb(0x3C5, 0x01);
    outb(0x3C4, 0x02); outb(0x3C5, 0x0F);
    outb(0x3C4, 0x03); outb(0x3C5, 0x00);
    outb(0x3C4, 0x04); outb(0x3C5, 0x0E);

    outb(0x3D4, 0x11); outb(0x3D5, 0x0E);

    static const unsigned char crtc[25] = {
        0x5F, 0x4F, 0x50, 0x82, 0x54, 0x80, 0xBF, 0x1F,
        0x00, 0x41, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x9C, 0x0E, 0x8F, 0x28, 0x40, 0x9C, 0x0E, 0xA3,
        0xFF
    };
    for (i = 0; i < 25; i++) {
        outb(0x3D4, i);
        outb(0x3D5, crtc[i]);
    }

    outb(0x3CE, 0x00); outb(0x3CF, 0x00);
    outb(0x3CE, 0x01); outb(0x3CF, 0x00);
    outb(0x3CE, 0x02); outb(0x3CF, 0x00);
    outb(0x3CE, 0x03); outb(0x3CF, 0x00);
    outb(0x3CE, 0x04); outb(0x3CF, 0x00);
    outb(0x3CE, 0x05); outb(0x3CF, 0x40);
    outb(0x3CE, 0x06); outb(0x3CF, 0x05);
    outb(0x3CE, 0x07); outb(0x3CF, 0x0F);
    outb(0x3CE, 0x08); outb(0x3CF, 0xFF);

    inb(0x3DA);
    for (i = 0; i < 16; i++) {
        outb(0x3C0, i);
        outb(0x3C0, i);
    }
    outb(0x3C0, 0x10); outb(0x3C0, 0x01);
    outb(0x3C0, 0x11); outb(0x3C0, 0x00);
    outb(0x3C0, 0x12); outb(0x3C0, 0x0F);
    outb(0x3C0, 0x13); outb(0x3C0, 0x00);
    outb(0x3C0, 0x14); outb(0x3C0, 0x00);
    outb(0x3C0, 0x20);
}

/* ---- Framebuffer ---- */

static int offset(int x, int y) {
    return (y * fb.width + x) * (fb.bpp / 8);
}

static void init(void) {
    unsigned int bar0 = pci_find_vga_bar0();

    if (bar0 && vbe_try_init()) {
        fb.width  = 1024;
        fb.height = 768;
        fb.bpp    = 32;
        fb.addr   = bar0;
    } else {
        vga_set_mode13();
        fb.width  = 320;
        fb.height = 200;
        fb.bpp    = 8;
        fb.addr   = 0xA0000;
    }

    fb_mem = (volatile unsigned char *)fb.addr;

    struct fb_info *handshake = (struct fb_info *)0x600;
    handshake->width  = fb.width;
    handshake->height = fb.height;
    handshake->bpp    = fb.bpp;
    handshake->addr   = fb.addr;
}

static void putpixel(int x, int y, unsigned int color) {
    if (x < 0 || x >= fb.width || y < 0 || y >= fb.height)
        return;
    int off = offset(x, y);
    if (fb.bpp == 8) {
        fb_mem[off] = (unsigned char)color;
    } else {
        fb_mem[off + 0] = (unsigned char)color;
        fb_mem[off + 1] = (unsigned char)(color >> 8);
        fb_mem[off + 2] = (unsigned char)(color >> 16);
        if (fb.bpp >= 32)
            fb_mem[off + 3] = (unsigned char)(color >> 24);
    }
}

static void fill_rect(int x, int y, int w, int h, unsigned int color) {
    int px, py;
    for (py = y; py < y + h; py++)
        for (px = x; px < x + w; px++)
            putpixel(px, py, color);
}

static void clear(unsigned int color) {
    fill_rect(0, 0, fb.width, fb.height, color);
}

static int get_width(void)  { return fb.width; }
static int get_height(void) { return fb.height; }

/* ---- Font ---- */

static void draw_char(int x, int y, char c, unsigned int color) {
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
                putpixel(x + col, y + row, color);
    }
}

static void draw_str(int x, int y, const char *s, unsigned int color) {
    while (*s) {
        draw_char(x, y, *s++, color);
        x += FONT_WIDTH;
        if (x + FONT_WIDTH > fb.width)
            break;
    }
}

/* ---- Console ---- */

static void con_scroll(void) {
    int i, j;
    for (i = 0; i < CON_ROWS - 1; i++)
        for (j = 0; j < CON_COLS; j++)
            con_buf[i][j] = con_buf[i + 1][j];
    for (j = 0; j < CON_COLS; j++)
        con_buf[CON_ROWS - 1][j] = ' ';
    con_row = CON_ROWS - 1;
}

static void con_newline(void) {
    con_col = 0;
    con_row++;
    con_total++;
    if (con_row >= CON_ROWS)
        con_scroll();
}

static void con_putchar(char c) {
    if (c == '\n') {
        serial_out(c);
        con_newline();
        return;
    }
    if (c < ' ') {
        serial_out(c);
        return;
    }

    if (con_col == 0) {
        int i;
        char ts[9];
        rtc_format_ts(ts);
        for (i = 0; i < 9; i++) {
            serial_out(ts[i]);
            if (con_col < CON_COLS)
                con_buf[con_row][con_col++] = ts[i];
        }
    }

    serial_out(c);

    if (con_col >= CON_COLS)
        con_newline();

    con_buf[con_row][con_col++] = c;
}

static void con_flush(void) {
    int i, j;
    int rows = con_total < CON_ROWS ? con_total : CON_ROWS;
    if (con_total == 0)
        return;
    for (i = 0; i < rows; i++) {
        int yy = i * FONT_HEIGHT + 2;
        if (yy + FONT_HEIGHT > fb.height)
            break;
        for (j = 0; j < CON_COLS; j++)
            if (con_buf[i][j])
                draw_char(2 + j * FONT_WIDTH, yy, con_buf[i][j], 0xFFFFFF);
    }
}

static void con_write(const char *s) {
    while (*s)
        con_putchar(*s++);
}

static void console_flush(void) {
    con_flush();
}

static void console_write(const char *s) {
    con_write(s);
}

/* ---- baremetal.h API ---- */

#include "baremetal.h"

void bm_init(void) { init(); }
void bm_puts(const char *s) { console_write(s); }
void bm_flush(void) { console_flush(); }
int  bm_ui_ready(void) { return fb.addr != 0; }
void bm_ui_clear(unsigned int color) { clear(color); }
void bm_ui_fill_rect(int x, int y, int w, int h, unsigned int color) { fill_rect(x, y, w, h, color); }
void bm_ui_draw_char(int x, int y, unsigned char c, unsigned int fg, unsigned int bg) { (void)bg; draw_char(x, y, (char)c, fg); }
void bm_ui_draw_str(int x, int y, const char *s, unsigned int fg, unsigned int bg) { (void)bg; draw_str(x, y, s, fg); }
int  bm_ui_width(void) { return get_width(); }
int  bm_ui_height(void) { return get_height(); }
int  bm_ui_bpp(void) { return fb.bpp; }

/* ---- Exported ops ---- */

const struct fb_ops vga = {
    .init           = init,
    .putpixel       = putpixel,
    .fill_rect      = fill_rect,
    .clear          = clear,
    .get_width      = get_width,
    .get_height     = get_height,
    .draw_char      = draw_char,
    .draw_str       = draw_str,
    .console_write  = console_write,
    .console_flush  = console_flush,
    .write_ts       = write_timestamp,
};
