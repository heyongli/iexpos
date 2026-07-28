# iexpos — Minimal x86 Protected-Mode OS

A ~1500 LOC x86 OS that boots from BIOS, enters protected mode, reads RTC time,
and renders a bitmap-font console with colour rectangles on screen. Built
from autonomous **software closures** (see `design.md`).

## Architecture

```
boot/         →  real-mode loader (512 B, INT 13h, jump to 0x7E00)
entry.asm     →  16→32-bit PM stub (GDT, CR0, far jump, call setup_main)

meta/         →  compile-time contracts (IO semantics, BIT/_IO_OK)
silx/x86/     →  framebuffer, serial, RTC, IO abort (x86 silicon layer)
gdb-stub/     →  GDB remote serial protocol over COM1
ui/           →  font, text rendering, progress bar, screen console backend
kernel/       →  console abstraction + setup_main entry point
```

- **Console** (`bm_puts` / `bm_flush`) — writes to COM1 serial + 25×80 buffer,
  auto-prepends RTC timestamp per line. Works before video init.
- **RTC** (`bm_rtc_read` / `bm_rtc_format`) — CMOS driver via ports 0x70/0x71.
- **Frame­buffer** (`bm_init` / `bm_ui_*` / `fb_swap`) — PCI probe → Bochs VBE
  (1024×768×32) → VGA mode 13h fallback. Hybrid draw_buf + YOFF page-flip.
- **UI** (`ui_draw_*` / `progress_*`) — text rendered with IBM VGA 8×16 font
  onto the framebuffer; bottom-strip progress bar.

## Quick Start

```bash
make all          # build
./test.sh         # build + boot in QEMU + verify all test suites
make run          # build + launch GUI window
```

Dependencies: `nasm`, `gcc-multilib`, `qemu-system-x86`.
