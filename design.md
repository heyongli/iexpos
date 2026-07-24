# Design & Debug Journal

## Architecture Overview

```
┌──────────────┐
│   BIOS       │  loads boot sector → 0x7C00
└──────┬───────┘
       │
┌──────▼───────┐
│  boot.asm    │  (16‑bit) set graphics mode,
│              │  read kernel via INT 13h LBA,
│              │  load GDT, switch to PM
└──────┬───────┘
       │
┌──────▼───────┐
│  kernel.c    │  (32‑bit) init VGA driver,
│  vga.c       │  print to COM1 serial,
│              │  draw rectangles
└──────────────┘
```

### Data flow — framebuffer info

```
boot.asm                        kernel / vga.c
─────────                       ─────────────
INT 0x10 → VBE mode info        reads struct from 0x600
     │                                │
     └──→ copy width, height,         │
          bpp, fb_addr to 0x600  ─────┘
                               also 0x10000 raw VBE block
```

---

## Gotchas & Fixes

### 1. GDT descriptor byte ordering (NASM)

**Problem:** The GDT code segment descriptor was incorrectly assembled because
every field was declared with `dw` (16 bits), while the spec requires a mix of
`dw` (16‑bit limit low, base low), `db` (base mid, access, flags+limit high,
base high).

```
;; WRONG — all dw
gdt_code:  dw 0xffff, 0x0000, 0x00, 0x9a, 0xcf, 0x00

;; RIGHT — explicit dw/db
gdt_code:  dw 0xffff
           dw 0x0000
           db 0x00
           db 0x9a
           db 0xcf
           db 0x00
```

NASM's `dw` with multiple operands packs them as consecutive 16‑bit words,
not byte‑by‑byte, corrupting the descriptor.

### 2. BSS section placed into VGA memory

**Problem:** The kernel's BSS (uninitialised static variables) landed at
address ~0xA0000, overlapping the VGA framebuffer. This caused the kernel's
`fb` struct to be silently corrupted the moment any rect was drawn.

**Root cause:** The linker by default aligns sections to page boundaries (4K).
With `.text` at 0x7E00, `.bss` was rounded up to the next 4K page boundary at
0xA0000.

**Fix:** Added `-n` (or `-N`) to the linker flags —
`ld -m elf_i386 -Ttext 0x7E00 -n …`. This disables page alignment and places
BSS immediately after `.rodata`.

### 3. Writing to 0x5FC corrupted INT 13h

**Problem:** Writing a flag byte to `[0x5FC]` (intended to communicate VBE
availability to the C code) caused the subsequent `INT 0x13` disk read to
behave incorrectly or to read corrupt data, resulting in a kernel crash.

**Root cause:** Address 0x5FC lies inside the BIOS Data Area (0x400–0x5FF) and
is used internally by the BIOS during INT 13h operations.

**Fix:** Removed the 0x5FC writes. The kernel now detects VBE availability by
checking `fb.addr`: if it equals `0xA0000`, the mode is legacy VGA 13h;
otherwise VBE mode was set and the raw mode‑info block at 0x10000 can be
parsed.

### 4. Kernel entry point at 0x7E00

**Problem:** The bootloader jumps to `0x7E00`, which was assumed to be
`kernel_main`. After adding helper functions (`serial_print`,
`serial_print_dec`) to `kernel.c`, the compiler placed them **before**
`kernel_main` in the `.text` section. The jump landed in the middle of a
helper function, causing a triple‑fault → CPU reset.

**Fix:** Placed `kernel_main` first in the source file, with forward
declarations for the helper functions. This ensures the first byte of the
kernel binary is always the entry point.

### 5. VBE mode 0x4118 bpp

**Problem:** Mode 0x4118 (VESA defined as 1024×768×32) was reported by QEMU's
VBE as **24 bpp** (bits per pixel), not 32. The original driver assumed `bpp
/ 8 = 4` and wrote a 4th byte (alpha) unconditionally, potentially corrupting
adjacent pixels.

**Fix:** Made putpixel conditionally write the 4th byte only when
`fb.bpp >= 32`. The driver now works with both 24‑bpp and 32‑bpp modes.

### 6. Triple‑fault on KVM without sg

**Problem:** Running QEMU without `sg kvm -c "…"` would sometimes fail to
access KVM permissions.

**Fix:** The Makefile and test scripts wrap QEMU invocations with
`sg kvm -c "…"` to switch to the kvm group.
