# Bootloader — boot.asm

## Overview

A 512‑byte x86 boot sector that transitions the system from real mode
(16‑bit) to protected mode (32‑bit), sets up a high‑resolution graphics
mode, loads the kernel from disk, and jumps to it at `0x7E00`.

## Execution Flow (Summary)

```
BIOS → boot/boot.asm (INT 13h, 加载扇区到 0x7E00)
     → boot/entry.asm (16→32-bit, LGDT/CR0, PMOK, 跳 0x7E00)
     → kernel/setup.c (C init + 运行 demo)
```

## Execution Flow (Detail)

### 1. Save Boot Drive

```asm
mov [boot_drive], dl
```

The BIOS passes the boot drive number in `DL`. Save it immediately because
later `INT 0x10` calls may clobber `DL`.

### 2. Set Graphics Mode

First tries **VBE mode 0x4118** (1024×768 with linear framebuffer):

- `ES:DI` = `0x1000:0x0000` (buffer for VBE mode info, physical address
  `0x10000`)
- `AX=0x4F01, CX=0x4118` → get mode info
- `AX=0x4F02, BX=0x4118` → set mode
- Check `AX=0x004F` after each call (VBE success code)

If VBE fails, falls back to **VGA mode 13h** (`AX=0x0013`, 320×200×256).

### 3. Publish Framebuffer Info

Writes a 12‑byte `fb_info` structure to `0x600`:

| Offset | Size | Field                   |
|--------|------|-------------------------|
| 0x600  | u16  | width (pixels)          |
| 0x602  | u16  | height (pixels)         |
| 0x604  | u8   | bits per pixel           |
| 0x605  | 3B   | reserved (zero)         |
| 0x608  | u32  | framebuffer base address |

For VBE mode the values come from the mode‑info block at `ES:DI+0x12`,
`+0x14`, `+0x19` and `+0x28`. For VGA 13h they are hard‑coded to
`320 × 200, 8 bpp, 0xA0000`.

### 4. Load Kernel from Disk

Uses `INT 0x13` extended read (`AH=0x42`) with a Disk Address Packet (DAP):

```asm
dap:  db 16, 0, 0, 0       ; packet size, reserved, sector count*, reserved
      dw 0x7E00, 0          ; buffer offset:segment = 0x0000:0x7E00
      dd 1, 0               ; LBA start = sector 1, LBA high = 0
```

*\* Sector count is patched at build time.*  The Makefile computes the exact
number of 512‑byte sectors needed for the kernel and writes it into `boot.bin`
at binary offset 31 (the third DAP byte, which starts at offset 29):

```makefile
# (excerpt from Makefile, inside image.bin recipe)
KERNEL_SECTORS=$$((($$(stat -c%s $(BDIR)/kernel.bin) + 511) / 512))
printf '\\x'"$$(printf '%02x' "$$KERNEL_SECTORS")" |
  dd of=$(BDIR)/boot.bin bs=1 seek=31 count=1 conv=notrunc
```

A post‑patch assertion (via Python) reads back the byte and compares it
to the expected value, catching any offset/length mismatches early.

This keeps `boot.asm` independent of the kernel size — no need to manually
update the DAP when kernel code grows.

### 5. Switch to Protected Mode

```
cli
lgdt [gdt_desc]          ; load GDT (2 descriptors: code + data)
mov eax, cr0
or  eax, 1
mov cr0, eax             ; set PE bit
jmp 0x08:pm_entry        ; far jump flushes prefetch queue
```

The GDT provides a flat 4 GiB code segment (selector `0x08`) and data segment
(selector `0x10`), both ring 0, base 0.

### 6. Protected‑Mode Stub

Sets all segment registers to the data selector, allocates a stack at
`0x7C00` (growing down), prints `PMOK` on serial port `0x3F8`, then jumps to
the kernel at `0x7E00`.

## GDT Layout

| Label      | Offset | Contents                |
|------------|--------|-------------------------|
| gdt        | 0xC0   | null descriptor (8 B)   |
| gdt_code   | 0xC8   | code, ring 0, 32‑bit    |
| gdt_data   | 0xD0   | data, ring 0, R/W       |
| gdt_end    | —      | (label only)            |
| gdt_desc   | 0xD8   | limit=23, base=0x7CC0   |

Each descriptor uses explicit `dw`/`db` directives — see **DESIGN.md §1**.

## Memory Layout

```
0x000000 – 0x0003FF  IVT
0x000400 – 0x0004FF  BDA
0x000500 – 0x0005FF  BIOS data
0x000600 – 0x00060B  fb_info (written by bootloader)
0x007C00 – 0x007DFF  boot sector (stack at 0x7C00, grows down)
0x007E00 – 0x008FFF  kernel (loaded from disk)
0x010000 – 0x0100FF  VBE mode info block (if VBE succeeded)
0x0A0000 – 0x0AFFFF  VGA framebuffer (legacy 13h)
0xFD000000+          VBE linear framebuffer (PCI MMIO)
```
