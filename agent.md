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

- After modifying source files, run `make clean all` to verify compilation, then run the **module-specific test** (e.g. `tests/vga.sh` for VGA, `tests/serial.sh` for serial). Before committing, run `./test.sh` to ensure all tests pass.
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

## TODO

### High Priority
- [x] **GDB reentrancy** — fixed via `bp_remove_all()`/`bp_insert_all()` in trampoline
- [x] **PIT frame timing** — fixed: PIT channel 0 was never programmed, QEMU kept the counter frozen so `elapsed_pit()` never fired. Added `pit_init()` (count 0 = 65536 free-run) called from `setup.c`
- [ ] **Commit working tree** — gdb reentrancy, PIT timing (fixed via `pit_init`), `is_aborting()` exit, gdb-over-serial test rewrite

### Medium Priority
- [ ] **io abort: cross-CPU** (see `design.md` CR4 bit 24 — per-CPU on Intel, needs IPI)
- [ ] **Reorganise tests into closure dirs** (see `design.md` — per-closure tests → `<closure>/tests/`)
- [ ] **Remove `mdelay(5)` from orbit.c** (already done in working tree, verify no regression)

### Low Priority
- [ ] **Check BSS after `gdb_in_handler`** — run `tests/check_bss.sh`
- [ ] **Visual/flicker test** — verify no regression from framerate limiting

## Debug Tips & Best Practices

### Memory Map
- **BSS must not cross 0xA0000** — `nm -n kernel.elf | tail -20` to verify end < 0xA0000
- Large buffers (≥64 KB) → pointers in extended memory (≥0x100000), not static BSS
- `fb_info` at 0x600–0x6FF (bootloader fills, kernel reads)

### Compiler/Linker
- **`setup_main` first function** in `kernel/setup.c`; helpers as forward declarations above it
- `-nostdlib -ffreestanding -fno-PIC`, stack at 0x7C00
- kernel.bin first 4 bytes = entry.asm (linked first)

### GDB
- QEMU: `make gdb-qemu` (T1) → `gdb -x tests/gdb-qemu.gdb` (T2)
- Serial: `tests/gdb-over-serial.sh` — socat PTY + batch mode
- Reentrancy guard: `gdb_in_handler` set in trampoline before calling `gdb_handler`; nested entry sets TF and IRETs out

### IO
- COM1 0x3F8, polling (no IRQ). LSR+5: bit 5=THRE, bit 6=TEMT
- UART loopback: MCR bit 4=LOOP
- PIT 1.193182 MHz: `PIT_FRAME_TICKS = 16 * (1193182 / 1000)` ≈ 19090
- **Call `pit_init()` before using PIT** — unprogrammed channel 0 keeps the QEMU counter frozen (see `docs/io-ports.md`); count must be 0x0000 (65536 free-run), not 1
- `elapsed_pit(start)` handles 16‑bit wrap via unsigned short subtraction

### Code
- Closures: self-contained, no peer coupling. Internal docs in `<closure>/docs/`
- `kernel/` is host program (not a closure) — wires closures together
- Console → COM1 + 25×80 buffer with RTC timestamp prefix
