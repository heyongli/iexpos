# Bare-Metal Interface

The kernel and closures depend on a **platform API** declared in
`kernel/include/baremetal.h`. Each architecture port must provide the
functions and macros listed below.

The API is split across closures:

| Function              | Closure      | Doc                                |
|-----------------------|--------------|------------------------------------|
| `bm_puts / bm_flush`  | `kernel`     | `docs/kernel.md`                   |
| `bm_rtc_*`            | `silx/<arch>`| `docs/serial.md` / per-driver      |
| `bm_init`             | `silx/<arch>`| `silx/docs/silx_vga.md`            |
| `arch_io_abort_check` | `silx/<arch>`| `docs/io-abort.md`                 |
| `bm_ui_*` (rect ops)  | `silx/<arch>`| `silx/docs/silx_vga.md`            |
| `fb_swap`             | `silx/<arch>`| `silx/docs/silx_vga.md`            |
| `ui_draw_*`           | `ui`         | `ui/docs/ui.md`                    |

Text rendering (`ui_draw_char`, `ui_draw_str`) is **not** part of the baremetal
contract — it lives in `ui/ui.h` because the font is a ui concern, not a
hardware primitive.

## Required by `bm_init`

`bm_init()` detects the framebuffer mode (bootloader-set VBE, Bochs VBE, or
VGA mode 13h) and sets up `fb_mem`. After return, the framebuffer geometry
is queryable via `bm_ui_width / _height / _bpp`, and the backbuffer is in
extended memory (above the VGA legacy hole).

## Required by `bm_flush` / console

Console output (via `bm_puts`, `bm_printf`) calls `bm_flush()`, which the
platform implements by registering a `console_be` backend:

```c
struct console_be {
    void (*write)(const char *s, int len);
    void (*flush)(void);
};
void console_register_be(struct console_be *be);
```

The backend's `flush()` is responsible for drawing the text grid to the
framebuffer after each `bm_puts` / `bm_printf` batch.

The screen backend is implemented in `ui/text.c` and registered by `ui_init()`.
A port that wants a different console backend can register its own instead.

## Required for demos

Declared in `silx/<arch>/io.h`:

| Function | Purpose |
|----------|---------|
| `void mdelay(unsigned int ms)` | Blocking millisecond‑level delay using PIT counter 0 |

`mdelay` is used by `demo_orbit()` to pace frames. Other architectures must
provide the same signature with whatever timer is available.

## Required for GDB stub

Declared in `gdb-stub/gdb_io.h`:

| Function | Purpose |
|----------|---------|
| `int gdb_io_init(void)` | Set up serial channel for GDB |
| `int gdb_io_getc(void)` | Read one byte, return < 0 on error / abort |
| `void gdb_io_putc(int c)` | Write one byte |

The stub uses serial I/O with IO-abort support (CR4 bit 24 on x86) so that
breakpoint-triggered reads do not deadlock.

## Required for RTC

Declared in `silx/<arch>/rtc.h`:

| Function | Purpose |
|----------|---------|
| `int rtc_read_time(h,m,s)` | Read hours, minutes, seconds from CMOS RTC |
| `int rtc_format_ts(buf,len)` | Write a timestamp string into `buf` |

## Porting checklist

- Implement `kernel/include/baremetal.h` API (video init, framebuffer ops)
- Implement `silx/<arch>/io.h` API (at minimum `mdelay`)
- Implement GDB serial I/O (`gdb-stub/gdb_io.h`)
- Implement RTC (CMOS on x86, or equivalent)
- Provide a `console_be` (the screen backend in `ui/text.c` is the default;
  override it if your port has different needs)
