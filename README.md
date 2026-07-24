# iexpos — Minimal x86 Protected-Mode OS

A ~800 LOC x86 OS that boots from BIOS, enters protected mode, reads RTC time,
and renders a bitmap-font console with colour rectangles on screen.

## Architecture

```
baremetal.h    →  platform API (console, RTC, bitmap UI)
boot/          →  real-mode loader (512 B, INT 13h, jump to 0x7E00)
entry.asm      →  16→32-bit PM stub (GDT, CR0, far jump, call kernel_main)
bmX86/         →  x86 bare-metal driver layer
kernel.c       →  kernel_main: init, test, infinite loop
```

- **Console** (`bm_puts` / `bm_flush`) — writes to COM1 serial + 25×80 buffer,
  auto-prepends RTC timestamp per line. Works before video init.
- **RTC** (`bm_rtc_read` / `bm_rtc_format`) — CMOS driver via ports 0x70/0x71.
- **Bitmap UI** — PCI probe → Bochs VBE (1024×768×32) → VGA mode 13 fallback.
  Text rendered with IBM VGA 8×16 font onto linear framebuffer.

## Quick Start

```bash
make all          # build
./test.sh         # build + boot in QEMU + verify serial output (4 checks)
make run          # build + launch GUI window
```

Dependencies: `nasm`, `gcc-multilib`, `qemu-system-x86`.
