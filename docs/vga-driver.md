# VGA / VBE Framebuffer Driver — vga.c / vga.h

## Purpose

Provides an abstracted, modular framebuffer driver that works with both
legacy VGA mode 13h and VBE linear framebuffer modes (24 bpp or 32 bpp).

## Interface — `struct fb_ops`

Defined in `vga.h`, implemented in `vga.c`. Exported as the global
`const struct fb_ops vga`.

| Member       | Signature                                       | Description              |
|--------------|-------------------------------------------------|--------------------------|
| `init`       | `void (*)(void)`                                | Detect mode, map fb      |
| `putpixel`   | `void (*)(int x, int y, unsigned int color)`    | Draw one pixel           |
| `fill_rect`  | `void (*)(int, int, int, int, unsigned int)`    | Fill rectangle           |
| `clear`      | `void (*)(unsigned int color)`                  | Clear entire screen      |
| `get_width`  | `int (*)(void)`                                 | Return screen width      |
| `get_height` | `int (*)(void)`                                 | Return screen height     |

## Internal State

```c
static struct fb_info fb;              // width, height, bpp, addr
static volatile unsigned char *fb_mem; // pointer to framebuffer
```

`fb` is a struct copy of the data written by the bootloader at `0x600`.

## Module Initialisation — `init()`

```
bootloader writes fb_info to 0x600
         │
         ▼
init: struct copy 0x600 → fb
         │
         ├── fb.addr != 0xA0000?  (VBE mode detected)
         │   └── read full VBE mode-info from 0x10000
         │
         └── fb_mem = fb.addr
```

The check `fb.addr != 0xA0000` distinguishes VBE from VGA 13h. When VBE
succeeded, the raw mode-info block is available at `0x10000` and is parsed
through the `struct vbe_mode_info` (from `vbe.h`), which provides more
detailed information than the simplified `fb_info`.

## Coordinate → Memory Mapping

```c
static int offset(int x, int y) {
    return (y * fb.width + x) * (fb.bpp / 8);
}
```

Pixel stride = `bpp / 8` bytes:
- 8 bpp → 1 B per pixel (indexed colour, VGA 13h)
- 24 bpp → 3 B per pixel (VBE, no alpha)
- 32 bpp → 4 B per pixel (VBE, alpha channel)

## Pixel Writing — `putpixel()`

```c
fb_mem[off + 0] = color;        // B (little-endian)
fb_mem[off + 1] = color >> 8;   // G
fb_mem[off + 2] = color >> 16;  // R
if (fb.bpp >= 32)
    fb_mem[off + 3] = color >> 24; // A (only for 32 bpp)
```

Colour is passed as a packed `0xRRGGBB` or `0xAARRGGBB` value. The byte
order in the framebuffer is little-endian B‑G‑R‑(A), which matches the x86
memory layout.

Bounds checking is performed before writing.

## Rectangle Fill — `fill_rect()`

Simple nested loop over `y → y+h`, `x → x+w`, calling `putpixel()` for each
pixel. Not optimised for performance; serves as a correctness baseline.

## Full‑Screen Clear — `clear()`

Delegates to `fill_rect(0, 0, fb.width, fb.height, color)`.

## Colour Format

The `color` parameter is `unsigned int` = 32 bits. Layout:

```
bits 31..24  23..16  15..8  7..0
┌─────────┬───────┬──────┬──────┐
│  alpha  │  red  │ green│ blue │
│ (unused)│       │      │      │
└─────────┴───────┴──────┴──────┘
```

For 24‑bpp modes the alpha byte is simply not written; the colour value
should set it to `0xFF` so that 32‑bpp modes display correctly.
