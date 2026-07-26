# Kernel — kernel.c

## Purpose

The C entry point for iexpos. Initialises the VGA driver, prints system
information over serial, runs a graphics test (6 coloured rectangles), and
then halts in an infinite loop.

## Entry Point

The kernel binary is loaded by the bootloader to `0x7E00`. The bootloader
jumps to `0x7E00`, which must be the **first function** in the binary.
`kernel_main` is placed first in the source file to guarantee this.

### GOTCHA: compiler reorders functions

Adding helper functions before `kernel_main` caused the compiler to place
them first in `.text`. The bootloader's jump to `0x7E00` landed in the
middle of a helper, producing a triple‑fault → CPU reset.

**Fix:** keep `kernel_main` as the first function in the source file, with
forward declarations for any helpers.

## Serial Debug Output

Two static helpers provide text output over COM1 (port `0x3F8`).

### `serial_print(const char *s)`

Iterates over a null‑terminated string, sending each byte to the serial port
using the `outb` instruction:

```c
__asm__ volatile("outb %0, %1"
    : : "a"((unsigned char)*s), "Nd"((unsigned short)0x3F8));
```

The `Nd` constraint selects `outb %al, imm8` for ports < 256 and `outb %al,
%dx` for larger ports (0x3F8 > 255, so DX is used).

### `serial_print_dec(int val)`

Converts an integer to its decimal string representation using a small
on‑stack buffer (12 B), then passes the result to `serial_print`. The
conversion uses repeated division‑by‑10, building the string from right to
left.

## Initialisation Sequence

```
kernel_main()
  │
  ├── vga.init()                   read fb_info from 0x600
  │                                optionally refresh from VBE block
  │
  ├── serial_print("[KERNEL] ...") announce mode
  │
  ├── serial_print("WxHxB")        resolution (via vga.get_width/height)
  │
  ├── vga.clear(0x001020)          dark blue background
  │
  ├── vga.fill_rect(…) × 6         draw coloured rectangles
  │
  ├── serial_print("[KERNEL] ...") "Graphics test complete"
  │
  └── while (1) ;                  halt
```

## Graphics Test

Draws six 200 × 200 rectangles:

| X    | Y    | Colour    |
|------|------|-----------|
| 50   | 50   | Blue      |
| 300  | 50   | Green     |
| 550  | 50   | Red       |
| 50   | 300  | Yellow    |
| 300  | 300  | Cyan      |
| 550  | 300  | Magenta   |

All coordinates fit within both VGA 13h (320 × 200) and VBE 1024 × 768 modes.
In VGA 13h the right‑most rectangles (X = 300, 550) are cut off or partially
visible because 320 px is the limit.
