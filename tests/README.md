# Test Cases

## Test Structure

| Test | Purpose | Method |
|------|---------|--------|
| `serial.sh` | Boot serial output markers | QEMU `-serial file:` + grep |
| `serial-rw.sh` | UART loopback read/write | QEMU `-serial file:` + grep `SRW:P` |
| `console.sh` | Console output (bm_puts) | QEMU `-serial file:` + grep markers |
| `vga.sh` | VGA/VBE resolution detection | QEMU `-serial file:` + grep `Resolution:` |
| `visual.sh` | Framebuffer has visible pixels | QEMU screendump + PPM pixel sum |
| `rtc.sh` | RTC time read | QEMU `-serial file:` + grep timestamp |
| `io-abort.sh` | IO abort mechanism (CR4 bit 24) | QEMU `-serial file:` + grep warning |
| `gdb-qemu.sh` | Real GDB debugging via QEMU `-gdb` | GDB batch: break, step, backtrace |
| `gdb-over-serial-protocol.sh` | GDB serial protocol correctness (raw TCP) | Python: trigger, negotiate, `c`/`s`/regs/mem over TCP |
| `gdb-over-serial.sh` | Real GDB debugging via serial PTY bridge | socat PTY + GDB batch: break, step, set, continue, backtrace, detach |

## Test Purpose Distinction

- `gdb-over-serial-protocol.sh` — Python test that sends GDB remote serial packets directly over TCP to QEMU serial. Verifies the stub parses packets correctly (`?`, `g`, `G`, `m`, `M`, `c`, `P`, `vMustReplyEmpty`, `qSupported`), validates checksums, and sends correct replies. This test is protocol-focused and runs without real GDB.

- `gdb-over-serial.sh` — Tests the full stack: QEMU serial → TCP → socat PTY bridge → real GDB. Verifies that a real GDB client can connect, negotiate, set breakpoints, stepi, modify registers (`set \$reg`), continue, backtrace, and detach through the serial stub. Requires socat.

## Status

GDB-over-serial debugging works: connect → `break *gdb_poll` → `continue` hits breakpoint → `backtrace` shows frame. See `gdb-stub/` for the stub implementation and `gdb-stub/tramp.asm` for interrupt trampolines.

## Running

```bash
./test.sh              # Run all tests
tests/serial.sh        # Run single test (--no-build to skip rebuild)
```

## Notes

- All tests use `-drive file=...,format=raw` for QEMU
- `gdb-qemu.sh` and `gdb-over-serial.sh` require GDB installed
- `gdb-over-serial.sh` requires socat installed
- `gdb-over-serial-protocol.sh` uses direct TCP connection (no PTY), no external dependencies
