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

/* bitmap UI — optional, safe to call even if no framebuffer */
int  bm_ui_ready(void);
void bm_ui_clear(unsigned int color);
void bm_ui_fill_rect(int x, int y, int w, int h, unsigned int color);
void bm_ui_draw_char(int x, int y, unsigned char c, unsigned int fg, unsigned int bg);
void bm_ui_draw_str(int x, int y, const char *s, unsigned int fg, unsigned int bg);
void bm_ui_draw_char_sz(int x, int y, unsigned char c, unsigned int fg, int sz);
void bm_ui_draw_str_sz(int x, int y, const char *s, unsigned int fg, int sz);
int  bm_ui_width(void);
int  bm_ui_height(void);
int  bm_ui_bpp(void);

#endif
