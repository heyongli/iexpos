# VGA / VBE Framebuffer Driver — vga.c / vga.h

## Purpose

Provides an abstracted, modular framebuffer driver that works with both
legacy VGA mode 13h and VBE linear framebuffer modes (24 bpp or 32 bpp).

## Design Decisions

- **Backbuffer in extended memory** (0x100000) — avoids the VGA legacy hole
  at 0xA0000–0xBFFFF where writes would go to video memory instead of RAM.
- **Single backbuffer** — all renderers (console, UI, demos) write to the
  same `draw_buf`. No per-module buffers, no compositing.
- **Dirty-row tracking** — `scr_row` records the maximum row modified since
  last flush. `bm_flush` only copies rows 0..scr_row, not the whole screen.
- **No vsync** — flush happens on-demand (console_flush, demo frame
  complete). Tearing is acceptable for this project.
- **32bpp linear** — VBE mode 0x4118 (1024×768), B-G-R-A byte order,
  little-endian.

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

### GOTCHA: QEMU reports 24 bpp for VBE mode 0x4118

VBE mode 0x4118 is defined as 1024×768×32, but QEMU's VBE reports it as
**24 bpp**. Writing a 4th alpha byte unconditionally corrupts adjacent
pixels. The driver handles both bpp values by checking `fb.bpp >= 32` before
writing the alpha byte.

---

## VBE Structures — vbe.h

Provides **packed C structs** matching the VESA BIOS Extension (VBE) 3.0
specification. These allow the kernel to parse the mode‑info block written
by the bootloader at `0x10000`.

### `struct vbe_info_block`

Returned by VBE function `AX=0x4F00` (get controller info). Size: 512 B.

| Offset | Type   | Field        | Description              |
|--------|--------|--------------|--------------------------|
| 0x00   | char[4]| `signature`  | `"VESA"`                 |
| 0x04   | u16    | `version`    | BCD version (e.g. 0x0300)|
| 0x06   | u32    | `oem_str`    | Far pointer to OEM name  |
| 0x0A   | u32    | `capabilities`| Feature flags           |
| 0x0E   | u32    | `video_mode` | Pointer to mode list     |
| 0x12   | u16    | `total_mem`  | Video memory in 64 KB    |
| 0x14   | u16    | `oem_ver`    | OEM software version     |
| 0x16   | u32    | `oem_data`   | Far pointer to OEM data  |
| 0x1A   | char[222]| `reserved` | Reserved                 |
| 0x100  | char[256]| `oem`      | OEM data / strings       |

### `struct vbe_mode_info` ★

Returned by VBE function `AX=0x4F01` (get mode info). Size: 256 B. This is
the struct used by the bootloader and VGA driver.

| Offset | Type | Field            | Description                        |
|--------|------|------------------|------------------------------------|
| 0x00   | u16  | `mode_attr`      | Mode attributes (0x0001=supported) |
| 0x02   | u8   | `win_a_attr`     | Window A attributes                |
| 0x03   | u8   | `win_b_attr`     | Window B attributes                |
| 0x04   | u16  | `win_gran`       | Window granularity (KB)            |
| 0x06   | u16  | `win_size`       | Window size (KB)                   |
| 0x08   | u16  | `win_a_seg`      | Window A start segment             |
| 0x0A   | u16  | `win_b_seg`      | Window B start segment             |
| 0x0C   | u32  | `win_func`       | Window positioning function ptr    |
| 0x10   | u16  | `pitch`          | Bytes per scan line                |
| **0x12**| u16  | **`width`**      | **X resolution in pixels**        |
| **0x14**| u16  | **`height`**     | **Y resolution in pixels**        |
| 0x16   | u8   | `w_char`         | Character cell width               |
| 0x17   | u8   | `h_char`         | Character cell height              |
| 0x18   | u8   | `planes`         | Number of planes                   |
| **0x19**| u8   | **`bpp`**        | **Bits per pixel**                |
| 0x1A   | u8   | `banks`          | Number of banks                    |
| 0x1B   | u8   | `mem_model`      | Memory model (0x06=direct colour)  |
| 0x1C   | u8   | `bank_size`      | Bank size (KB)                     |
| 0x1D   | u8   | `image_pages`    | Number of image pages              |
| 0x1F–0x26| —   | colour masks     | Bit positions for R/G/B/A          |
| **0x28**| u32  | **`fb_addr`**    | **Physical linear fb address**    |
| 0x2C   | u32  | `offscreen`      | Off-screen memory offset (VBE 3.0) |
| 0x30   | u16  | `offscreen_size` | Off-screen memory size             |

Fields in **bold** are used by the bootloader and VGA driver.

### Bootloader usage (assembly)

```asm
mov ax, 0x4F01
mov cx, 0x4118          ; mode number
mov es, 0x1000
xor di, di              ; ES:DI = 0x10000 (buffer)
int 0x10                ; get mode info → ES:DI

mov ax, 0x4F02
mov bx, 0x4118
int 0x10                ; set mode

; copy relevant fields to 0x600
mov ax, [es:di+0x12]   ; width
mov [0x600], ax
mov ax, [es:di+0x14]   ; height
mov [0x602], ax
mov al, [es:di+0x19]   ; bpp
mov [0x604], al
mov eax, [es:di+0x28]  ; fb_addr
mov [0x608], eax
```

### C driver usage (vga.c)

```c
volatile struct vbe_mode_info *v = (void *)0x10000;
fb.width  = v->width;
fb.height = v->height;
fb.bpp    = v->bpp;
fb.addr   = v->fb_addr;
```

### `__attribute__((packed))`

Both structs use `__attribute__((packed))` to disable structure padding,
ensuring the memory layout matches the VBE specification exactly. Without
this, the compiler would add alignment padding between fields (e.g. 2 bytes
between `u8` and `u16` fields), corrupting the offsets.

---

## Case Study: White Bar / Flickering

A full-width white bar at screen rows 162–177 (character row 10) and
top-screen flickering were traced to **`draw_buf` in BSS overlapping the VGA
legacy memory hole (0xA0000–0xBFFFF)**.

### Root Cause

The backbuffer was declared as a static BSS array:

```c
static unsigned char draw_buf[1024 * 768 * 4];   // 3 MiB
```

The linker placed BSS at physical address **0xE520**:

| Region           | Address range          |
|------------------|------------------------|
| BSS start        | 0xE520                 |
| draw_buf start   | ~0xE520                |
| draw_buf end     | 0xE520 + 0x300000 = 0x30E520 |
| VGA legacy hole  | **0xA0000 – 0xBFFFF**  |
| Extended memory  | 0x100000+              |

Writes to `draw_buf` offsets 0x91AE0–0xB1AE0 went to VGA video memory
instead of system RAM. Those 16 white rows map to exactly 1024×16×4 bytes
of VGA-mirrored writes — a perfect match.

Flickering occurred because `fill_rect` wrote white to the "VGA mirror"
region on every frame, while `bm_flush` also copied from `draw_buf` to the
real framebuffer — the VGA device latched some writes, corrupting the screen.

### Discovery Method

One shell command + mental arithmetic:

```bash
nm build/kernel.elf | grep draw_buf
# → draw_buf at 0xE520
```

```
0xE520 + 3 MiB = 0x30E520
               → overlaps 0xA0000–0xBFFFF?  YES
```

The white bar's **fixed screen row** was the fingerprint. Computing the
corresponding backbuffer offset and converting to a physical address
immediately identified the VGA hole.

### Fix

```c
// Before:
static unsigned char draw_buf[1024 * 768 * 4];

// After:
static volatile unsigned char *draw_buf;   // pointer, not array
// in init():
draw_buf = (volatile unsigned char *)0x100000;   // extended memory
```

This moved the backbuffer to 0x100000–0x400000, above the VGA hole and the
EBDA.

### Principle

On bare‑metal x86, a **fixed‑position visual anomaly** (stripe, bar, garbage
at a specific scan line) is a strong hint that the corresponding backbuffer
address falls in a **MMIO region** (VGA hole, LAPIC, PCI config space, ...).
Calculate `row × pitch × bytes_per_pixel`, add the buffer base, and check
against the platform memory map before debugging rendering logic.
