# Bare-Metal Interface

The kernel and demos depend on a platform layer (`bmX86/` on x86) that implements
the interface declared in `kernel/include/baremetal.h`.  Each architecture port
must provide the functions and macros listed below.

## Required by `bm_ui_*` / `bm_init`

Declared in `kernel/include/baremetal.h`:

| Function | Purpose |
|----------|---------|
| `bm_init()` | Initialise video hardware, set up framebuffer |
| `bm_ui_ready()` | Return `_IO_OK` if framebuffer is available |
| `bm_ui_clear(c)` | Fill whole framebuffer with 32‑bit colour `c` |
| `bm_ui_width()` | Framebuffer width in pixels |
| `bm_ui_height()` | Framebuffer height in pixels |
| `bm_ui_bpp()` | Bits per pixel |
| `bm_ui_fill_rect(x,y,w,h,c)` | Fill a rectangle with colour `c` |

## Required by `bm_flush` / console

Console output (via `bm_puts`, `bm_printf`) calls `bm_flush()`, which the
platform implements by registering a `console_be` backend:

```c
struct console_be {
    void (*write)(char c);
    void (*flush)(void);
};
void console_register_be(struct console_be *be);
```

The backend's `flush()` is responsible for drawing the text grid to
the framebuffer after each `bm_puts` / `bm_printf` batch.

## Required for demos

Declared in `bmX86/io.h`:

| Function | Purpose |
|----------|---------|
| `void mdelay(unsigned int ms)` | Blocking millisecond‑level delay using PIT counter 0 |

`mdelay` is used by `demo_orbit()` to pace frames.  Other architectures
must provide the same signature with whatever timer is available (e.g. a
system tick counter or a PIT equivalent).

## Required for GDB stub

Declared in `gdb-stub/gdb_io.h`:

| Function | Purpose |
|----------|---------|
| `int gdb_io_init(void)` | Set up serial channel for GDB |
| `int gdb_io_getc(void)` | Read one byte, return < 0 on error / abort |
| `void gdb_io_putc(int c)` | Write one byte |

The stub uses serial I/O with IO‑abort support (CR4 bit 24 on x86) so that
breakpoint‑triggered reads do not deadlock.

## Required for RTC

Declared in `bmX86/rtc.h`:

| Function | Purpose |
|----------|---------|
| `int rtc_read_time(h,m,s)` | Read hours, minutes, seconds from CMOS RTC |
| `int rtc_format_ts(buf,len)` | Write a timestamp string into `buf` |

## Porting checklist

- Implemement `kernel/include/baremetal.h` API (video init, framebuffer ops)
- Implement `bmX86/io.h` API (at minimum `mdelay`)
- Implement GDB serial I/O (`gdb-stub/gdb_io.h`)
- Implement RTC (CMOS on x86, or equivalent)
- Register a `console_be` for print output
