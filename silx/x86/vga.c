#include "vga.h"
#include "baremetal.h"
#include "io.h"
#include "include/os_regs.h"

static struct fb_info fb;
static volatile unsigned char *fb_mem;   /* current draw target (back buffer) */
static volatile unsigned char *real_fb;  /* VGA framebuffer base (PCI BAR0) */
static int fb_size;                      /* bytes per buffer = width*height*bpp/8 */

/* Back-buffer in main RAM, must live above the VGA legacy hole
 * (0xA0000-0xBFFFF) so allocated from extended memory at boot time
 * instead of BSS. */
static volatile unsigned char *draw_buf;

#define VBE_VW    6
#define VBE_VH    7
#define VBE_XOFF  8
#define VBE_YOFF  9

static void putpixel(int x, int y, unsigned int color);
static void fill_rect(int x, int y, int w, int h, unsigned int color);

/* ---- Port I/O ---- */

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
#define VBE_DISABLED     0
#define VBE_ENABLED      BIT(0)
#define VBE_LFB_ENABLED  BIT(6)

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
        return _NOT_READY;
    vbe_write_reg(VBE_ENABLE, VBE_DISABLED);
    vbe_write_reg(VBE_XRES, 1024);
    vbe_write_reg(VBE_YRES, 768);
    vbe_write_reg(VBE_BPP, 32);
    vbe_write_reg(VBE_VW, 1024);
    vbe_write_reg(VBE_XOFF, 0);
    vbe_write_reg(VBE_YOFF, 0);
    vbe_write_reg(VBE_ENABLE, VBE_ENABLED | VBE_LFB_ENABLED);
    return _IO_OK;
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
    {
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
    if (fb.bpp == 32) {
        unsigned int n = fb.width * fb.height;
        __asm__ volatile(
            "cld\n\trep stosl\n"
            : : "a"(color), "D"(fb_mem), "c"(n)
            : "memory"
        );
    } else {
        __asm__ volatile(
            "cld\n\trep stosb\n"
            : : "a"((unsigned char)color), "D"(fb_mem), "c"(fb_size)
            : "memory"
        );
    }
}

static void init(void) {
    /* Step 1: read fb_info written by bootloader at 0x600.
     * Bootloader wrote this via INT 0x10 VBE (or hardcoded for VGA 13h).
     * If addr != 0xA0000, VBE mode was set in real mode — keep it. */
    struct fb_info *bi = (struct fb_info *)0x600;
    int boot_vbe = (bi->addr != 0 && bi->addr != 0xA0000);
    const char *mode_str;

    if (boot_vbe) {
        fb.width  = bi->width;
        fb.height = bi->height;
        fb.bpp    = bi->bpp;
        fb.addr   = bi->addr;
        mode_str = "boot VBE";
    } else {
        unsigned int bar0 = pci_find_vga_bar0();
        if (bar0 && vbe_try_init() == _IO_OK) {
            fb.width  = 1024;
            fb.height = 768;
            fb.bpp    = 32;
            fb.addr   = bar0;
            mode_str = "Bochs VBE";
        } else {
            vga_set_mode13();
            fb.width  = 320;
            fb.height = 200;
            fb.bpp    = 8;
            fb.addr   = 0xA0000;
            mode_str = "VGA 13h";
        }
    }

    fb_size = fb.width * fb.height * (fb.bpp / 8);
    real_fb = (volatile unsigned char *)fb.addr;
    draw_buf = (volatile unsigned char *)0x100000;
    fb_mem = draw_buf;

    if (real_fb && real_fb != (void *)0xA0000 &&
        vbe_read_reg(VBE_ID) >= 0xB0C0) {
        unsigned int stride = fb.width * (fb.bpp / 8);
        vbe_write_reg(VBE_VW, fb.width);
        vbe_write_reg(VBE_VH, fb_size / stride);
        vbe_write_reg(VBE_XOFF, 0);
        vbe_write_reg(VBE_YOFF, 0);
    }

    bi->width  = fb.width;
    bi->height = fb.height;
    bi->bpp    = fb.bpp;
    bi->addr   = (unsigned int)real_fb;

    /* Print status. The screen backend (text rendering + console_be) is
     * owned by ui/text.c and must be initialised by ui_init() after this
     * returns. */
    bm_puts("vga init: ");
    bm_puts(mode_str);
    bm_puts(", ");
    bm_puts("FB copy");
    bm_puts("\n");
}

/* ---- baremetal.h API (framebuffer primitives only) ---- */

void bm_init(void) { init(); }
int  bm_ui_ready(void) { return fb.addr ? _IO_OK : _NOT_READY; }
void bm_ui_clear(unsigned int color) { clear(color); }
void bm_ui_fill_rect(int x, int y, int w, int h, unsigned int color) { fill_rect(x, y, w, h, color); }
int  bm_ui_width(void) { return fb.width; }
int  bm_ui_height(void) { return fb.height; }
int  bm_ui_bpp(void) { return fb.bpp; }

/* Copy draw_buf (system RAM) to VRAM, then YOFF-flip to avoid tearing.
 * The copy always targets the back (invisible) page; the front page is
 * undisturbed during the copy, then YOFF switches instantly. */
void fb_swap(void) {
    static int page;
    if (!real_fb) return;
    unsigned int n = fb_size / 4;
    void *src = (void *)draw_buf;
    page = 1 - page;
    void *dst = (void *)(real_fb + page * fb_size);
    __asm__ volatile(
        "cld\n\trep movsl\n"
        : : "S"(src), "D"(dst), "c"(n)
        : "memory"
    );
    /* Wait for the start of vblank (rising edge of bit 3).
     * First wait until NOT in vblank, then until IN vblank,
     * so we synchronise to the beginning of the blanking period
     * and have the full vblank window for the register write.
     * Each loop checks is_aborting() so a GDB ^C (CR4 bit 24)
     * can break out of the spin without hanging. */
    while (inb(0x3DA) & 0x08) { if (is_aborting()) { bm_puts("fb_swap: io abort\r\n"); return; } }
    while (!(inb(0x3DA) & 0x08)) { if (is_aborting()) { bm_puts("fb_swap: io abort\r\n"); return; } }
    vbe_write_reg(VBE_XOFF, 0);
    vbe_write_reg(VBE_YOFF, page * (fb.height));
}
