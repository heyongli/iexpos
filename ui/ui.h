#ifndef UI_H
#define UI_H

/* Register the screen backend with the console (call once after bm_init).
   Must run before the first bm_flush so the screen backend receives any
   already-buffered console output. */
void ui_init(void);

/* Text rendering (font-aware, uses silx framebuffer primitives).
   Sized variants scale the glyph by `sz` (1 = 8x16 px native). */
void ui_draw_char(int x, int y, unsigned char c, unsigned int fg, unsigned int bg);
void ui_draw_str(int x, int y, const char *s, unsigned int fg, unsigned int bg);
void ui_draw_char_sz(int x, int y, unsigned char c, unsigned int fg, int sz);
void ui_draw_str_sz(int x, int y, const char *s, unsigned int fg, int sz);

/* Progress bar (bottom strip) */
void progress_init(void);
void progress_set(int percent);
void progress_text(const char *s);

#endif
