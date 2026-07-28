# UI — `ui/`

## Purpose

The UI closure renders **glyph-aware** content on top of the silx framebuffer
primitives. It owns the font, the text rendering routines, the screen console
backend, and the progress-bar widget.

The closure deliberately does not know about pixel formats, PCI, or VGA
registers — those live in `silx/x86`. UI consumes `bm_ui_*` (silx framebuffer
ops) via `kernel/include/baremetal.h` and `console_be` via `kernel/console.h`.

## Files

| File             | Responsibility                                       |
|------------------|------------------------------------------------------|
| `ui/font_8x16.h` | IBM VGA 8×16 font glyph table + `FONT_WIDTH/HEIGHT`  |
| `ui/text.c`      | `ui_draw_*` API, screen console backend, init        |
| `ui/ui.h`        | Public UI API (init, draw, progress)                 |
| `ui/ui.c`        | Progress-bar widget (bottom strip)                   |
| `ui/demos/`      | Demos rendered via `demo_draw()` in the main loop    |

## Init Order — `ui_init()`

```c
bm_init();    // silx: framebuffer up
ui_init();    // ui:   register screen backend with console
```

`ui_init()` registers a `console_be` that flushes a 25×80 character grid to
the framebuffer. Any `bm_puts` output buffered between `bm_init` and
`ui_init` is replayed by `console_register_be`, so init-order races are
absorbed.

## Text Rendering — `ui_draw_*`

| Function                        | Notes                            |
|---------------------------------|----------------------------------|
| `ui_draw_char(x, y, c, fg, bg)` | 8×16 native glyph; `bg` ignored   |
| `ui_draw_str(x, y, s, fg, bg)`  | Advances x by `FONT_WIDTH`        |
| `ui_draw_char_sz(x, y, c, fg, sz)` | Scales glyph by `sz` (1 = native) |
| `ui_draw_str_sz(x, y, s, fg, sz)`  | Stride = `FONT_WIDTH * sz`       |

The native-size variants rasterise each glyph pixel via `bm_ui_fill_rect(1,1)`,
not direct `putpixel` — `putpixel` is silx-internal. This trades a small
amount of speed for the clean closure boundary (silx never leaks its pixel
writer; ui never reaches into silx internals).

The scaled variants scale by issuing `sz × sz` `bm_ui_fill_rect(1,1)` calls
per lit pixel.

## Screen Backend — 25×80 grid

```c
static char scr_grid[25][80];
static int  scr_row, scr_col;
```

`bm_puts` writes feed this grid via `scr_be_write`; `bm_flush` rasterises
the dirty rows via `scr_be_flush`. The flush is a no-op when
`bm_ui_ready() != _IO_OK` (i.e., before framebuffer init).

Each row is drawn at `y = 2 + i * FONT_HEIGHT`, leaving 2 px of top margin.
A row that would overflow the bottom is clipped — no scroll text appears
above row 24.

## Progress Bar — `progress_*`

```c
void progress_init(void);    // bottom strip, dark slate
void progress_set(int pct);  // 0..100
void progress_text(const s); // label on the left
```

Renders 48 px tall at the bottom of the screen. Fill colour is a two-tone
slate (`94a3b8` / `64748b`). Percent text on the right, info text on the
left, scaled by `TXT_SZ = 2` (16 px glyphs).

## Demo Loop

The main loop calls `demo_draw()` every frame. The default demo
(`ui/demos/demo_progress.c`) renders the orbit (`demo_orbit`) and walks the
progress bar from 0 to 100 over a configurable number of frames.

## Why text is not a silx concern

`silx` is the silicon closure: its job is to expose raw framebuffer
primitives and console-grade IO with the minimum abstraction. A font, glyph
rasterisation, or text grid is a **rendering policy** — different closures
may want different fonts, different layouts, or no text at all. Keeping
text out of silx means:

- A non-x86 port of silx doesn't have to ship a VGA ROM font.
- A different UI closure (different font, different layout) can replace
  `ui/` without touching silx.
- `kernel/console.c` remains the single owner of console output policy.
