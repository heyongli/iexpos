# Kernel CLI — `kernel/cli.c`

## Overview

The kernel includes a minimal **CLI (Command Line Interface)** running entirely in
kernel mode. It is a debugging, development, and testing assistant tool — not a
user shell.

## Commands

| Command | Syntax | Description |
|---------|--------|-------------|
| `help` | `help` | Show command list |
| `info` | `info` | Display VGA resolution & BPP |
| `test` | `test` | Run serial loopback test (via gdb_io) |
| `echo` | `echo <text>` | Echo text back |
| `hex` | `hex <n>` | Print decimal `n` as hex (`0x...`) |
| `gdb` | `gdb` | Switch serial to GDB stub mode (exits CLI) |

## Command Details

### `help`
```
$ help
Commands:
  help     - show this help
  info     - show system info
  test     - run serial loopback test
  echo <s> - echo back text
  hex <n>  - show number as hex
  gdb      - switch serial to GDB mode
```

### `info`
```
$ info
Resolution: 1024x768x32
```

Displays current VGA mode from `bm_ui_width()`, `bm_ui_height()`, `bm_ui_bpp()`.

### `test`
```
$ test
SRW:P
```

Runs `gdb_io_loopback_test()` — enables UART loopback mode (MCR bit 4), writes
4 test bytes (0x55, 0xAA, '!', '\n'), reads them back, verifies integrity,
disables loopback, prints `SRW:P` (pass) or `SRW:F` (fail).

### `echo`
```
$ echo hello world
hello world
```

Echoes the argument text back followed by newline.

### `hex`
```
$ hex 255
0x000000ff
```

Converts decimal integer to 8-digit hexadecimal with `0x` prefix.

### `gdb`
```
$ gdb
Switching to GDB mode.
```

Disables CLI mode (`cli_active = 0`). Main loop switches from `cli_poll()` to
`gdb_poll()`. Serial port now speaks GDB remote protocol.

## Architecture

```
Serial RX (COM1) → gdb_io_try_read() → cli_poll() → command parser
                              ↓
                        bm_puts_raw() → serial TX (COM1)
```

- Runs in the main loop via `cli_poll()` (non-blocking, called every frame)
- Uses `bm_puts_raw()` directly for output — bypasses `bm_puts()` timestamping
  to keep CLI interaction responsive and clean
- No stdin/stdout abstraction; reads/writes COM1 directly via `gdb_io` layer

## Integration

```c
// kernel/setup.c
cli_init();                    // after gdb_stub_init()
while (1) {
    if (cli_is_active())
        cli_poll();              // CLI mode
    else
        gdb_poll();              // GDB stub mode
}
```

- `cli_init()` prints the `$ ` prompt and enables CLI mode
- `cli_is_active()` returns 0 after `gdb` command → main loop switches to `gdb_poll()`
- GDB stub can re-enable CLI by setting `cli_active = 1` (future extension)

## Design Notes

- **No stdlib** — uses `baremetal.h` primitives (`bm_puts_raw`, `bm_ui_*`)
- **Fixed buffer** — 128-byte line buffer (`CLI_BUF_SIZE`), line editing via backspace/Ctrl-C
- **No command history** — minimal for kernel-mode debugging
- **Polling I/O** — `gdb_io_data_ready()` + `gdb_io_try_read()` (non-blocking)
- **Single instance** — global state in `cli.c` (`cli_buf`, `cli_pos`, `cli_active`)

## Testing

```bash
./tests/cli.sh
```

Verifies: `help`, `info`, `echo`, `hex` commands via serial TCP.