#ifndef BARE_METAL_H
#define BARE_METAL_H

/* console — writes to serial + screen buffer, always available */
void bm_puts(const char *s);
void bm_flush(void);

/* RTC — always available */
int  bm_rtc_read(unsigned char *h, unsigned char *m, unsigned char *s);
void bm_rtc_format(char buf[9]);

/* platform init — detects PCI/VBE/VGA, sets up framebuffer */
void bm_init(void);

/* IO abort mechanism — check if CPU supports CR4 bit 24 */
int arch_io_abort_check(void);

/* bitmap UI primitives — framebuffer ops; text rendering is in ui/ui.h */
int  bm_ui_ready(void);
void bm_ui_clear(unsigned int color);
void bm_ui_fill_rect(int x, int y, int w, int h, unsigned int color);
int  bm_ui_width(void);
int  bm_ui_height(void);
int  bm_ui_bpp(void);

/* swap buffer — copy back buffer to visible framebuffer */
void fb_swap(void);

#endif
