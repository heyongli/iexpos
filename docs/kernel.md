# Kernel — `kernel/`

## Purpose

`kernel/` is the **host main program** — it is *not* a closure. It contains:

- `setup_main` — the C entry point the bootloader jumps to after the PM
  switch in `boot/entry.asm`.
- `console.c` — the timestamped text-output abstraction that every
  closure's diagnostic output is wired through.

The closures (`meta`, `silx`, `gdb-stub`, `ui`) are libraries the kernel
links against. The kernel's job is to initialise them in the right order
and feed the main loop. See `design.md` for the architecture overview.

## Entry Point — `setup_main`

`kernel/setup.c:setup_main` runs after `boot/entry.asm` sets up GDT / segments
/ stack. It must be the **first** function in the kernel binary so the
bootloader's jump to `0x7E00` lands on its first instruction.

### GOTCHA — compiler reorders functions

Adding helper functions before `setup_main` caused the compiler to place them
first in `.text`. The bootloader's jump to `0x7E00` landed in the middle of
a helper, producing a triple-fault → CPU reset.

**Fix:** keep `setup_main` as the first function in `kernel/setup.c`, with
forward declarations for any helpers above it.

## Initialisation Sequence

```
setup_main()
  │
  ├── bm_puts("entry")                  ← serial-only (works before fb)
  │
  ├── bm_init()              silx      detect mode, map framebuffer
  ├── bm_puts("vga init done")
  ├── ui_init()              ui        register screen backend with console
  │
  ├── arch_io_abort_check()  silx      verify CR4 bit 24 usable
  │
  ├── gdb_stub_init()        gdb-stub  install INT1/INT3 handlers, IDT
  ├── bm_puts("gdb stub init done")
  ├── serial_rw_test()       gdb-stub  COM1 loopback sanity (writes SRW:P)
  │
  ├── bm_ui_clear / bm_flush / fb_swap  clear screen
  ├── bm_puts("gdb stub done")
  │
  └── while (1)
        ├── demo_draw()      ui        orbit + progress bar
        ├── fb_swap()        silx      copy back-buffer → VRAM, YOFF flip
        └── gdb_poll()       gdb-stub  non-blocking poll for GDB packet
```

## CLI — `kernel/cli.c`

The kernel includes a minimal **CLI (Command Line Interface)** running entirely in
kernel mode. It is a debugging, development, and testing assistant tool — not a
user shell.

### Design Notes

- **No stdlib** — uses `baremetal.h` primitives (`bm_puts_raw`, `bm_ui_*`)
- **Fixed buffer** — 128-byte line buffer (`CLI_BUF_SIZE`), line editing via backspace/Ctrl-C
- **No command history** — minimal for kernel-mode debugging
- **Polling I/O** — `gdb_io_data_ready()` + `gdb_io_try_read()` (non-blocking)


### Commands

See `docs/kernel-cli.md` for full command reference (`help`, `info`, `test`, `echo`, `hex`, `gdb`).


## Console — `kernel/console.c`

`bm_puts` writes to all registered `console_be` backends and prepends a
`HH:MM:SS` RTC timestamp at the start of every line.

```c
struct console_be {
    void (*write)(const char *s, int len);
    void (*flush)(void);
};
void console_register_be(struct console_be *be);
```

The serial backend is registered lazily inside `console_write` on first use.
The screen backend (text rendering via font) is registered by `ui_init()`.

Backends added after `console_register_be` has buffered output receive the
buffer replay (see `console.c:console_register_be`), so init-order races are
absorbed. A overflow marker (`~~(overflow)~~`) is replayed to backends
attached after a buffer wrap.

## Init Order — `ui_init()` After `bm_init()`

`ui_init()` registers the screen backend (defined in `ui/text.c`) with the
console. It must run **after** `bm_init()` so the framebuffer is ready for
the first `bm_flush`, and **before** any `bm_puts` is meant to appear on the
screen (output buffered between `bm_init` and `ui_init` is replayed).

## Memory — `kernel/include/baremetal.h`

The platform API contract consumed by `kernel/setup.c`, `ui/`, and demos.
Implementation is split across closures:

| Function              | Closure      |
|-----------------------|--------------|
| `bm_puts / bm_flush`  | `kernel`     |
| `bm_rtc_*`            | `silx/x86`   |
| `bm_init`             | `silx/x86`   |
| `arch_io_abort_check` | `silx/x86`   |
| `bm_ui_*` (rect ops)  | `silx/x86`   |
| `fb_swap`             | `silx/x86`   |
| `ui_*` (text rendering)| `ui`         |

Text rendering (`ui_draw_char` / `ui_draw_str`) was deliberately moved out of
`silx/x86` because it depends on the font (`ui/font_8x16.h`), which is a
**ui** concern, not a hardware primitive. See `ui/docs/ui.md` and
`docs/bare-metal-interface.md`.
