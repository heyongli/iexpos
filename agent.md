# iexpos — Project Documentation & Workflow Guide

> This file is the project index, **no need to load all content at once**.
> **Always read `design.md` first** — it contains the x86 memory map, known gotchas, and the project's design decisions. This overrides principle #1 for this one file.
> Working Principles:
> 1. load `design.md`
> 2. When modifying a module, Read its source file(s) directly, don't load unrelated files at the same time
> 3. Only read files needed for the current task, stop when done


## Doc per Module

Each module's design decisions, gotchas, and debug history belong in that
module's own doc file (`docs/<module>.md`). `design.md` only contains
cross-cutting concerns (memory map, architecture overview). Don't put
module-specific content in `design.md`.

## work flow

- After modifying source files, run `make clean all` to verify compilation, then run the **module-specific test** (e.g. `tests/vga.sh` for VGA, `tests/serial.sh` for serial). Only if asked to commit, run `./test.sh` to execute all tests and fix any failures found.
- change code should update related docs
-  Build & Test , do make clean all and rebuild test for any change
-  run specific test for code changes
-  run all test cases before commit code



## Key Conventions

- do not commit code without permit
- C: `-m32 -ffreestanding -fno-PIC -nostdlib -fno-asynchronous-unwind-tables`
- ASM kernel: NASM `-f elf32`; boot: NASM `-f bin [org 0x7c00]`
- Linker: `ld -m elf_i386 -Ttext 0x7E00 -e entry --oformat binary -n`
- No standard library, stack: `mov esp, 0x7C00`
- kernel.bin first 4 bytes is entry.asm (linked first)
- Kernel load address: 0x7E00, BSS uses `-n` to avoid hitting 0xA0000, but `-n` alone is insufficient when a single BSS array exceeds ~640 KB (spans into VGA hole 0xA0000–0xBFFFF). Large buffers must be pointers allocated from extended memory (≥ 0x100000).

GDB (QEMU) debugging details: `docs/gdb-qemu.md`
Debug serial port markers: `docs/serial.md`

I/O port reference: `docs/io-ports.md`.
