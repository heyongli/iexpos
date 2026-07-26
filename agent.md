# iexpos — Project Documentation & Workflow Guide

> This file is the project index, **no need to load all content at once**.
> 
> Working Principles:
> 1. Files should first be described in one sentence about their role, then Read specific content; don't preload all context
> 2. When modifying a module, find the corresponding file based on the index below and Read it, don't load unrelated files at the same time
> 3. Only read files needed for the current task, stop when done

## File Index

> **External reference documents are for reference only, load as context only when needed, don't read in advance.**

- boot/boot.asm - Boot loader loads kernel
- boot/entry.asm - GDT+CR0, jump to setup_main

- kernel/setup.c - Entry, bm_init, print, run demo
- kernel/console.c/h - Ring buffer, backend dispatch
- include/baremetal.h - Unified platform API
- include/font_8x16.h - Font

- bmX86/vga.c/h - VGA driver
- bmX86/rtc.c/h - RTC driver
- include/vbe.h - VBE struct

- ui/ui.c/h - Progress bar

- demos/demos.h - Demo entry
- demos/orbit.c - Rotation animation

- tests/serial.sh - Serial test
- tests/visual.sh - Visual test
- tests/gdb-qemu.sh - QEMU single step trace
- docs/gdb-qemu.md - QEMU GDB documentation
- docs/gdb-serial.md - GDB stub implementation
- docs/serial.md - Serial port design
- docs/io-ports.md - I/O port reference

## Build & Test

```bash
make clean all           # Build (output in build/)
./test.sh                # Run all tests
tests/serial.sh          # Run serial test alone
tests/visual.sh          # Run visual test alone
```

## Key Conventions

- do not commit code without permit
- C: `-m32 -ffreestanding -fno-PIC -nostdlib -fno-asynchronous-unwind-tables`
- ASM kernel: NASM `-f elf32`; boot: NASM `-f bin [org 0x7c00]`
- Linker: `ld -m elf_i386 -Ttext 0x7E00 -e entry --oformat binary -n`
- No standard library, stack: `mov esp, 0x7C00`
- kernel.bin first 4 bytes is entry.asm (linked first)
- Kernel load address: 0x7E00, BSS uses `-n` to avoid hitting 0xA0000

GDB (QEMU) debugging details: `docs/gdb-qemu.md`
Debug serial port markers: `docs/serial.md`

I/O port reference: `docs/io-ports.md`.
