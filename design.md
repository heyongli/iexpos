# Design & Debug

> This document records **high-level design decisions** that affect the
> project as a whole. Module-specific implementation details, debug flows,
> and problem analysis belong in `docs/<module>.md`.

## Overall Design Decisions

### Why bare metal?

Learning project. No OS, no libc, no runtime — everything from scratch.
This drives every other decision below.

### Toolchain

- **GCC `-m32 -ffreestanding -fno-PIC -nostdlib`** — freestanding, no libc
  dependencies, position-dependent code for a fixed load address.
- **NASM `-f bin`** for boot sector (no ELF overhead, must be 512 bytes),
  **NASM `-f elf32`** for 32-bit entry code linked into the kernel.
- **LD `-Ttext 0x7E00 -e entry --oformat binary -n`** — raw binary at fixed
  address, no ELF loader needed. `-n` disables page alignment to keep BSS
  below 0xA0000 (though insufficient for large arrays — see Memory Map
  Consistency principle).

### Boot strategy

Two-stage: **BIOS → bootloader (512 bytes) → kernel**.

- Stage 1 (`boot.asm`): real-mode, sets VBE graphics, loads kernel from
  disk via INT 13h LBA, switches to protected mode.
- Stage 2 (`entry.asm`): sets up GDT / segment registers / stack, jumps to
  C.
- Kernel (`setup.c + modules`): all C code, linked as a flat binary at
  0x7E00 overwriting the bootloader.

This split keeps the 512-byte boot sector simple (only mode set + disk I/O)
while keeping kernel development in C.

```
BIOS → boot.asm (16-bit, VBE + disk) → entry.asm (PM switch) → kernel C
```

### Debug strategy

- **Serial port (COM1, 0x3F8)** as the primary debug output channel —
  works from real mode through protected mode, no framebuffer needed.
- **QEMU + KVM** as the primary test target — fast, reproducible, supports
  screendump, monitor, GDB stub.
- **GDB over serial** (`docs/gdb-serial.md`) for interactive debugging.
- **No hardware testing** — all development on QEMU.

### Memory model

- **Flat 32-bit protected mode** — no paging, no segmentation (base 0,
  limit 4 GiB for both code and data).
- **Single binary** — kernel is position-dependent, loaded at 0x7E00.
- **Stack at 0x7C00** (grows down, 4 KiB below boot sector).
- **Physical memory map** must be checked manually — no MMU to remap
  around the VGA hole. See Core Principle below.
- **All structures are packed** (`__attribute__((packed))`) to match
  hardware/VBE layouts.

### IO Abort

Busy-waiting loops (UART polling, GDB stub) need a way to be interrupted.
The IO abort provides a **per-CPU flag** that any loop can check, and any
other CPU or interrupt handler can set. Implementation details in
`docs/io-abort.md`.

**Every IO abort check point MUST print an identifying message** (via
`bm_puts`) before exiting the spin loop. This ensures the developer can see
exactly which loop was interrupted, and whether the abort happened early or
late in the boot sequence — without having to single-step through GDB.

### Framebuffer / VGA

The hybrid draw-buffer + YOFF page-flip design and all VGA driver decisions
are documented in `docs/vga-driver.md`.

## Key Implementation Details

### Memory Map Consistency

Every static data region (BSS, stack, heap, framebuffer backbuffer) must be
**explicitly verified** against the x86 physical memory map. The linker has no
knowledge of platform MMIO regions — it places sections purely by its built-in
defaults. This has caused multiple bugs in this project.

#### x86 Physical Memory Map (lower 4 GiB)

| Start    | End      | Region                 | Note                        |
|----------|----------|------------------------|-----------------------------|
| 0x000000 | 0x0005FF | IVT / BDA              | Do not write                |
| 0x000600 | 0x0006FF | fb_info (bootloader)   | Reserved for boot data      |
| 0x007C00 | 0x007DFF | Bootloader             | Overwritten by kernel       |
| 0x007E00 | …        | Kernel (.text,.data,.bss)| Raw binary loaded by BIOS |
| 0x080000 | 0x09FFFF | Conventional RAM       | Stack, small allocations    |
| **0xA0000** | **0xBFFFF** | **VGA legacy hole** | **VGA video memory — writes go to display, not RAM** |
| 0xC0000  | 0xFFFFF  | Video ROM / BIOS       | ROM shadowing               |
| 0x100000 | …        | Extended memory        | Safe for large allocations  |

#### Verification

- Memory map consistency enforced by `tests/check_bss.sh` — run after any
  change to BSS layout.
- Large buffers (framebuffer backbuffers, ≥ 64 KB) must be allocated from
  extended memory (≥ 0x100000), not from BSS.
- Manual check: `nm -n kernel.elf | tail -20` to verify BSS end < 0xA0000.
- For any new static buffer ≥ 64 KB, compute `&buf + sizeof(buf)` and confirm
  it does not intersect 0xA0000–0xBFFFF.
