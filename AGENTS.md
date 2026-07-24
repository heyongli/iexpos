# AGENTS.md — iexpos Development Guide

## Project Overview

iexpos is a minimal x86 protected-mode OS in ~800 LOC. Seven source files produce
two binaries:

| Binary      | Size  | Description                    |
|-------------|-------|--------------------------------|
| `boot.bin`  | 512 B | Loads kernel from disk, jumps  |
| `kernel.bin`| ~6 KB | PM entry, RTC, graphics, console |

**Execution flow:**

```
BIOS → boot/boot.asm (real mode, INT 13h)
   → kernel at 0x7E00: entry.asm (16→32-bit, LGDT/CR0, "PMOK")
   → kernel_main() in kernel.c (C, via baremetal.h API)
```

`boot.bin` has zero knowledge of graphics or protected mode — it only loads
sectors (30 sectors via DAP) from disk and jumps to `0x7E00`.

## Build & Test

```bash
make clean all   # build
./test.sh        # runs all test suites in tests/
tests/serial.sh  # build + boot + verify serial output (4 checks)
tests/visual.sh  # build + boot + screendump + verify non-blank framebuffer
make run         # build + launch GUI window (via sg kvm)
```

Passing criteria: serial output must contain `PMOK`, `entry`, `Graphics init OK`,
`Graphics test complete` (10 s QEMU timeout allows for 5 s RTC animation).

## Conventions

- **C**: freestanding `-m32 -ffreestanding -fno-PIC -nostdlib -fno-asynchronous-unwind-tables`
- **Assembly (kernel)**: NASM `-f elf32`, linked before C objects to sit at `0x7E00`
- **Assembly (boot)**: NASM `-f bin`, `[org 0x7c00]`
- **Linking**: `ld -m elf_i386 -Ttext 0x7E00 -e entry --oformat binary -n`
- **No standard library** — no `printf`, `malloc`, `string.h`, etc.
- **Stack**: `mov esp, 0x7C00` (grows downward from boot sector top)

## Architecture — platform abstraction via `baremetal.h`

`kernel.c` includes only `baremetal.h` — the single platform API header. All
x86-specific implementation lives under `bmX86/` and `boot/`.

```
baremetal.h    Unified platform API — console, RTC, bitmap UI
console.h      Console backend interface (struct console_be)
console.c      Console subsystem — output cache, timestamps, backend dispatch
ui.h           Progress bar widget API
ui.c           Progress bar widget — clean gray gradient, scaled text, drop shadow
boot/boot.asm   512-byte boot sector — load + jump only (no GDT, no PM switch)
boot/entry.asm  PM transition stub at 0x7E00: LGDT, CR0, far jump, call kernel_main
bmX86/vga.h    struct fb_info (framebuffer geometry)
bmX86/vga.c    Framebuffer driver + PCI/VBE/VGA13 + screen backend for console
bmX86/rtc.h    RTC module header
bmX86/rtc.c    CMOS RTC driver via ports 0x70/0x71, BCD→bin, HH:MM:SS format
font_8x16.h    IBM VGA 8×16 bitmap font (ASCII 0x20–0x7E, Linux kernel source)
kernel.c       kernel_main, write_dec — orchestrates init, 4-icon display, 5s RTC animation
```

### entry.asm — the real-mode-to-PM bridge

`entry.asm` is linked **first** so its first byte sits at `0x7E00`. It runs in
16-bit real mode, loads the GDT, sets CR0.PE, far-jumps to flush the prefetch
queue, then switches to 32-bit mode, sets up segment registers + stack, prints
`PMOK` over serial, and `call`s `kernel_main`. This is the only assembly that
touches CPU control registers or the GDT.

### Graphics init — all in C, no BIOS calls

`vga.c` init:
1. **PCI probe** — scans the PCI bus for a VGA controller (class `0x0300`),
   reads BAR0 to get the linear framebuffer address
2. **Bochs VBE** — programs the VBE display via I/O ports `0x1CE/0x1CF`
   (set 1024×768×32). No INT 0x10 needed — works in protected mode.
3. **VGA fallback** — if PCI/VBE fails, programs VGA mode 0x13 directly via
   VGA registers (`0x3C2`–`0x3DA`), 320×200×8 at `0xA0000`.

### Console subsystem

`console.c` owns all output:
- **4 KB ring buffer** — caches every byte of system output; wraps with
  `~~(overflow)~~` marker when full
- **Timestamp** — auto-prepends `HH:MM:SS ` at each new line start
- **Backend dispatch** — every output byte is forwarded to all registered
  `console_be` backends (write + optional flush)
- **Serial backend** — built-in, always available; writes directly to COM1
- **Screen backend** — registered by `bm_init()` via `console_register_be()`;
  maintains a 25×80 grid, rendered to framebuffer on `bm_flush()` using the
  8×16 bitmap font

When a new backend is registered (e.g. screen during `bm_init()`), the full
4096-byte cache is replayed into it so no early-boot messages are lost.

### baremetal.h API surface

| Function | Purpose | Available before `bm_init()` |
|----------|---------|----|
| `bm_puts(s)` | Write string to console (serial + buffer) | Yes |
| `bm_flush()` | Render buffer to screen | No (no-op) |
| `bm_init()` | Detect PCI/VBE/VGA, set up framebuffer | — |
| `bm_rtc_read(h,m,s)` | Read CMOS RTC | Yes |
| `bm_rtc_format(buf)` | Format as `HH:MM:SS ` | Yes |
| `bm_ui_ready()` | Non-zero if framebuffer active | After init |
| `bm_ui_clear(color)` | Clear framebuffer | After init |
| `bm_ui_fill_rect(...)` | Fill rectangle | After init |
| `bm_ui_width/height/bpp()` | Framebuffer geometry | After init |
| `bm_ui_draw_char_sz(x,y,c,fg,sz)` | Scaled char (8·sz × 16·sz px) | After init |
| `bm_ui_draw_str_sz(x,y,s,fg,sz)` | Scaled string | After init |

Bitmap UI functions are safe to call even when no framebuffer is available
(they become no-ops).

### Progress bar widget (ui.h / ui.c)

`progress_init()` — draws a 48px-tall bar at screen bottom (slate gray bg).
`progress_set(p)` — sets 0–100%, renders a clean gray gradient fill with
`pct%` label (scaled ×2, white text, black shadow).
`progress_text(s)` — sets info label text on the left (gray, with shadow).

Color scheme: background `0x0f1729`, bar `0x1e293b`, fill gradient
`0x94a3b8` → `0x64748b`, text `0xf1f5f9`.

### Swap buffer (vga.c)

`bm_swap()` uses **VBE page flipping** (register 9: Y offset). Two framebuffer
halves at offsets 0 and `fb_size`. After flipping the display, it copies the
new front buffer → new back buffer via `rep movsb` so both halves stay in
sync. Callers need only draw incremental changes before the next swap.

For VGA mode 13h fallback (320×200×8), fall back to copy-based swap.

### Animation (kernel.c)

Boot sequence:
1. Serial init, PCI/VBE/VGA init
2. Clear screen (`0x0f1729`) + flush console log
3. Draw 4 centered 96×96 squares (pastel blue/green/pink/amber) as icon grid
4. Progress bar animates 0→100% while squares orbit screen center (~5 s, 100 frames)
5. Serial "Graphics test complete"

## Known Gotchas

1. **GDT byte order** — use explicit `dw`/`db` per field, never `dw a,b,c`
2. **Linker `-n` flag** — required; without it BSS lands at 0xA0000 (VGA RAM)
3. **Boot entry point** — `entry` in `entry.asm` is the first byte at `0x7E00`
4. **0x5FC is BIOS data** — don't write there
5. **VBE bpp** — QEMU reports mode 0x4118 as 24 bpp, not 32 (handled in putpixel)

## Debugging Skills

### Boot markers — pinpoint which stage fails

The serial output has built-in checkpoints. Read them with `run.sh`:

```bash
./run.sh
```

| Marker | Stage | If missing |
|--------|-------|------------|
| `PMOK` | entry.asm PM switch | GDT broken, CR0 stuck, or far jump wrong |
| `entry` | kernel_main started | Linkage: `extern kernel_main` in entry.asm, or `-e entry` flag |
| `vga init done` | vga.init() returned | PCI probe hung, Bochs VBE port stuck, or VGA register lockup |
| `Graphics init OK` | Console buffer working | Console buffer overflow or font rendering crash |

### Raw serial — zero-dependency debug output

`bm_puts()` works before `bm_init()` — it writes directly to COM1 with
no framebuffer dependency. Use it for early boot checkpoints:

```c
bm_puts("checkpoint\n");
```

The console auto-prepends RTC timestamps, so early output looks like:
`02:48:31 checkpoint`. If `bm_puts` output appears but the next line
doesn't, the crash is between those two points — no VBE, no PCI to blame.

### run.sh — interactive serial console

```bash
./run.sh   # builds + boots, serial on stdio
```

- Type into the terminal → characters go to COM1
- `Ctrl-a c` → switch to QEMU monitor
- `Ctrl-a x` → exit QEMU
- Useful for testing serial input (keyboard driver, shell, etc.)

### Quick failure analysis

| Symptom | Likely cause |
|---------|-------------|
| `PMOK` missing | entry.asm GDT or far jump broken |
| PMOK OK, `entry` missing | `extern kernel_main` not declared, or entry.asm linked after C objects |
| `entry` OK, `vga init done` missing | PCI bus scan stuck, Bochs VBE ID check failed, or VGA register write hung |
| Resolution `320x200x8` | PCI probe found no VGA class 0x0300, or BAR0 was 0; check `-vga std` |
| Rectangles wrong color | 24 bpp vs 32 bpp — QEMU reports 24 but some modes write 4 bytes/pixel |
| No console text on screen | `bm_flush()` not called, or font data missing from binary |

## Quick Reference

| Address    | Contents                             |
|------------|--------------------------------------|
| `0x600`    | `fb_info` (12 B, written by vga.c)   |
| `0x7C00`   | Boot sector + stack (grows down)     |
| `0x7E00`   | `entry.asm` first instruction        |
| `0x10000`  | (unused — was VBE mode info)         |
| `0xA0000`  | VGA legacy framebuffer               |
| `0x1CE`    | Bochs VBE index port                 |
| `0x1CF`    | Bochs VBE data port                  |
| `0xCF8`    | PCI config address port              |
| `0xCFC`    | PCI config data port                 |
| `0x3F8`    | COM1 serial port                     |
