# VGA / VBE Framebuffer Driver — vga.c / vga.h

## Purpose

Provides an abstracted, modular framebuffer driver that works with both
legacy VGA mode 13h and VBE linear framebuffer modes (24 bpp or 32 bpp).

## Double Buffering: Hybrid draw_buf + YOFF page flip

### Design

All rendering goes to `draw_buf` (system RAM at 0x100000, WB cache).
`fb_swap()` copies the back page of VRAM, waits for vblank, then flips
YOFF — the front page is never touched during drawing, so there is no
tearing.

```
console (text) ──┐
UI (progress)  ──┤
demos (orbit)  ──┤
                  ▼
           draw_buf (system RAM at 0x100000, WB cache)
                  │
        fb_swap: rep movsl (bulk 4-byte copy)
                  │
                  ▼
      VRAM back page (real_fb + page * fb_size)
                  │
         vblank wait (port 0x3DA bit 3)
                  │
        YOFF register write (port 0x1CE/0x1CF)
                  ▼
           display controller reads new page
```

### Why this hybrid approach?

| Approach | Problem |
|----------|---------|
| Draw directly to VRAM | Per-pixel `putpixel()` has function-call overhead, bounds checks, offset arithmetic, and non‑aligned byte writes. On WC/UC VRAM each byte write may stall. `rep movsl` is a single streaming instruction that avoids all that overhead. |
| Copy directly to visible page | The display controller may read a partially‑updated frame = tearing. |
| YOFF flip without copy | Requires drawing directly to VRAM (same problem as above). |

The solution: **draw to system RAM** (WB cached, fast per-pixel writes) →
**`rep movsl` bulk copy** to the invisible VRAM page (efficient, 4‑byte
aligned) → **YOFF register change** (instant, display sees only complete
frames). The front page is never written to during drawing, so no tearing.

`fb_mem` always points to `draw_buf` — all drawing code writes to system
RAM. The copy + YOFF flip happens atomically in `fb_swap()`.

### Why not pure YOFF flip (draw directly to VRAM pages)?

Per-pixel writes to VRAM are too slow to complete within a single vblank:

| Metric | Value |
|--------|-------|
| Resolution | 1024 × 768 × 32 bpp |
| Pixels per frame | 786 432 |
| VBlank window (60 Hz) | ≈ 16.7 ms |
| `putpixel()` VRAM (observed) | ~150 ns/pixel = **118 ms/frame** |
| `putpixel()` system RAM (observed) | ~10 ns/pixel = **7.9 ms/frame** |
| `rep movsl` bulk copy (3 MiB) | ~0.3 ms |

Drawing directly to VRAM takes **7× longer than a frame period** — the
display scans out partially‑drawn frames, causing visible flicker. Even
system‑RAM per‑pixel drawing barely fits in one vblank. The hybrid
(`draw_buf` + `rep movsl` + YOFF) completes in ~8.2 ms total, well within
budget, with zero tearing.

### Vblank wait

```c
/* Wait for the start of vblank (rising edge of bit 3).
 * First wait until NOT in vblank, then until IN vblank,
 * so we synchronise to the beginning of the blanking period
 * and have the full vblank window for the register write.
 * Each loop checks is_aborting() so a GDB ^C (CR4 bit 24)
 * can break out of the spin without hanging. */
while (inb(0x3DA) & 0x08) { if (is_aborting()) { bm_puts("fb_swap: io abort\r\n"); return; } }
while (!(inb(0x3DA) & 0x08)) { if (is_aborting()) { bm_puts("fb_swap: io abort\r\n"); return; } }
```

### Analysis of available flip mechanisms

#### VBE 0x4F07 (Set Display Start)
- Standard VESA BIOS call through INT 0x10.
- **Unusable** in protected mode — would need v86 mode or real-mode switch.
- QEMU's VBE emulation of 0x4F07 is incomplete; many versions ignore it.
- **Rejected.**

#### Bochs VBE YOFF (register 9)
- Port I/O at 0x1CE/0x1CF, register 9. No BIOS call needed.
- Scanout address = `LFB_base + YOFF × VW × bpp/8`.
- Works on all QEMU `-vga std` (QEMU's Bochs VBE is the reference
  implementation).
- Used by Linux **bochs-drm** for the same purpose.
- **Instant flip** — no data copy, just one `outw`.
- Video memory must be ≥ 2 frames (on QEMU default 16 MiB this holds).

#### System RAM backbuffer (`draw_buf` + memcpy + YOFF)
- Write to `draw_buf` (system RAM, fast), then `rep movsl` to VRAM back page
  (3 MiB in ~0.3 ms).
- Works with any amount of video memory, including VGA 13h (64 KiB).
- No hardware dependency — portable across QEMU VGA models and real HW.
- **Primary path** — always used.

### Design Decisions

- **Backbuffer in extended memory** (0x100000) — avoids the VGA legacy hole
  at 0xA0000–0xBFFFF where writes would go to video memory instead of RAM.
- **Single backbuffer** — all renderers (console, UI, demos) write to the
  same `fb_mem` (which points to `draw_buf`). No per-module buffers, no
  compositing.
- **No dirty-row tracking** — the full frame is always copied, so no need
  for `scr_row` in the hybrid path.
- **Vsync via vblank wait** — `fb_swap()` waits for port 0x3DA bit 3 rising
  edge before writing YOFF, ensuring the register change happens during
  vertical blanking.
- **IO abort safety** — vblank wait loops check `is_aborting()` on every
  iteration and print an identifying message on abort.
- **32bpp linear** — VBE mode 0x4118 (1024×768), B-G-R-A byte order,
  little-endian.

## Interface — `kernel/include/baremetal.h`

The driver implements the framebuffer subset of the baremetal API declared
in `kernel/include/baremetal.h`. Text rendering (`ui_draw_*`) is **not**
implemented here — it lives in `ui/text.c` (see `ui/docs/ui.md`).

| Function                            | Description                          |
|-------------------------------------|--------------------------------------|
| `bm_init()`                         | Detect mode, set up framebuffer      |
| `bm_ui_ready()`                     | `_IO_OK` once framebuffer is mapped  |
| `bm_ui_clear(color)`                | Fill whole fb with `color`           |
| `bm_ui_fill_rect(x,y,w,h,color)`    | Fill a rectangle                     |
| `bm_ui_width() / _height() / _bpp()`| Framebuffer geometry                 |
| `fb_swap()`                         | Copy back-buffer → VRAM, YOFF flip   |

## Initialisation Flow — `init()`

The init sequence always sets up the hybrid approach:

```
Read fb_info from bootloader (0x600)
         │
    fb.addr ≠ 0xA0000?
         ├── YES ──→ VBE mode already set by bootloader via INT 0x10
         │            Keep the resolution from bootloader.
         │            Write Bochs VBE registers (VIRT_WIDTH etc.) to
         │            enable YOFF support, then set fb_mem = draw_buf.
         │
         └── NO ───→ Try Bochs VBE port I/O (0x1CE/0x1CF) to init mode
                      ├── OK ──→ QEMU/Bochs environment
                      └── FAIL → VGA mode 13h (320×200)

After mode is determined:
    draw_buf ← 0x100000 (extended memory)
    fb_mem   ← draw_buf
    real_fb  ← fb.addr (VRAM physical address)
    fb_size  ← width * height * (bpp / 8)
    fb_flip  = 0   (always copy mode)
```

On **real hardware**, the bootloader's INT 0x10 call sets the VBE
linear framebuffer mode, and `fb_info` at 0x600 has the correct values.
The kernel reads them directly, writes VBE registers to configure YOFF
(so the hardware is ready), then sets `fb_mem = draw_buf`.  No mode is
changed after the bootloader — resolution is preserved.

On **QEMU `-vga std`**, the same flow applies.  The kernel probes Bochs
VBE registers to set the mode if the bootloader didn't, then always
uses the hybrid draw_buf + YOFF path.

The old code tried Bochs VBE **before** reading the bootloader's
`fb_info`, meaning on real HW it would fail the Bochs init and then
**override** the working VBE mode with VGA 13h — losing the
bootloader's resolution. The current flow fixes this by trusting the
bootloader's setup first.

## Internal State

```c
static struct fb_info fb;              // width, height, bpp, addr
static volatile unsigned char *fb_mem; // current draw target (back buffer)
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
         ├── fb_mem = draw_buf (0x100000, extended memory)
         ├── real_fb = fb.addr (VRAM physical address)
         └── fb_size = width * height * (bpp / 8)
```

The screen console backend (text rendering) is **not** registered here. It
is owned by the ui closure and must be wired up separately via `ui_init()`
(see `ui/docs/ui.md`).

The check `fb.addr != 0xA0000` distinguishes VBE from VGA 13h. When VBE
succeeded, the raw mode-info block is available at `0x10000` and is parsed
through the `struct vbe_mode_info` (from `vbe.h`), which provides more
detailed information than the simplified `fb_info`.

All drawing code writes to `fb_mem` (system RAM, WB cached).  `fb_swap()`
copies the frame to the invisible VRAM page and flips YOFF — see the
hybrid approach section above.

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
