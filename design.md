# Design & Debug

> This document records **high-level design decisions** that affect the
> project as a whole. Module-specific implementation details, debug flows,
> and problem analysis belong in `docs/<module>.md`.

## Closure Architecture

The system is split into **autonomous software closures** (reusable,
self-contained libraries with explicit dependencies and no horizontal peer
coupling) and **the kernel main program** that wires them together.

### Closures

| Closure     | Role                                                     | Public header            |
|-------------|----------------------------------------------------------|--------------------------|
| `meta`      | Compile-time contracts (IO semantics, BIT/`_IO_OK`, etc.)| `meta/io.h`              |
| `silx`      | Silicon-native primitives (framebuffer, serial, RTC, …)  | `kernel/include/baremetal.h` + `silx/<arch>/*.h` |
| `gdb-stub`  | GDB remote serial protocol stub over COM1                | `gdb-stub/gdb_stub.h`, `gdb-stub/gdb_io.h` |
| `ui`        | Font + text rendering + console screen backend + widgets | `ui/ui.h`                |

### Main program — `kernel/`

`kernel/` is **not** a closure — it is the host program that consumes the
closures. It contains:

- `setup_main` — the entry point the bootloader jumps to.
- `console.c` — the timestamped text output abstraction (no own UI policy).

The console abstraction is intentionally a kernel concern, not a closure:
it is the single point that wires every closure's diagnostic output to one
place.

### Boot stage — `boot/`

`boot/` is also not a closure — it is the 512-byte real-mode bootloader and
the 16→32-bit PM switch stub. Separate from the kernel binary; linked first
so the BIOS jump to `0x7E00` lands on `entry`. See `docs/bootloader.md`.

### Dependency autonomy

- Explicit dependency graph per closure; closed-loop internals; no peer deps.
- Any closure lifts out of the tree and builds in a separate environment.

### Documentation placement

- **Top-level `docs/`** — external interfaces and cross-cutting concerns
  only. A doc belongs here iff it (a) defines an API contract that other
  closures consume, (b) cross-cuts two or more closures, or (c) describes
  the main program / boot stage (which are not closures).
- **`<closure>/docs/`** — a closure's internal docs. Files are prefixed
  with the closure name (`<closure>_<topic>.md`); the `/` in `silx/x86`
  becomes `_` so the prefix is `silx_x86_` if needed in the future, but
  since subdirs of a closure (like `silx/x86/`) are not closures
  themselves, the prefix is just the top-level closure name.
- Only top-level directories count as closures. `silx/x86/` is the
  x86 implementation of the `silx` closure — internal to it, not a peer.
  `kernel/` and `boot/` are not closures (main program and stage
  respectively).

Current layout:

```
docs/                                  ← external / cross-cutting
├── bare-metal-interface.md              (the platform API contract)
├── bootloader.md                        (boot/ stage — not a closure)
├── kernel.md                            (kernel/ main program — not a closure)
├── io-abort.md                          (cross-cuts silx busy waits + gdb-stub INT3)
├── io-ports.md                          (port reference table)
├── gdb-qemu.md                          (cross-cutting debug how-to)
├── gdb-serial.md                        (gdb-stub protocol; user-facing)
└── serial.md                            (silx/x86/uart.c internals, partly cross-cuts gdb-stub)

silx/docs/silx_vga.md                  ← silx closure-internal (x86 VGA driver)
gdb-stub/docs/gdb-stub_internal.md     ← gdb-stub closure-internal (architecture + debug journal)
ui/docs/ui.md                          ← ui closure-internal (font, text, screen backend, progress)
```

### Hardware execution invariants (silx)

- **Shortest-execution-time rule** — primitives run at bare-silicon speed.
  No implicit pacing, unmanaged long loops, or thread-suspension logic.
- **Busy waits are physical** — polling slow peripherals (UART, external
  FIFO) makes a busy loop unavoidable.
- **`io_abort` interlock (mandatory)** — every busy wait samples the per-CPU
  abort flag via a 1-cycle privileged instruction (CR4 bit 24 on x86) and
  breaks within microseconds when the host sets abort. **Every abort check
  must print an identifying message** (via `bm_puts`) before exiting the spin
  loop, so the developer can see which loop was interrupted and whether the
  abort was early or late — without single-stepping in GDB. Details:
  `docs/io-abort.md`.

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

### Framebuffer / VGA

The hybrid draw-buffer + YOFF page-flip design and all VGA driver decisions
are documented in `silx/docs/silx_vga.md`.

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
