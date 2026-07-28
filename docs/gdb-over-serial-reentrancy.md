# GDB Reentrancy — iexpos

## Problem

When a GDB client sets a software breakpoint (`Z0,addr,1`) at the entry of
`gdb_handler`, every entry via `gdb_poll()` → `int $3` triggers a nested INT3
before the first instruction of `gdb_handler` executes. If this nested interrupt
is mishandled, the kernel deadlocks or crashes.

## Root Cause

### Trigger Path

```
gdb_poll() → read serial → set gdb_from_poll=1
  → __asm__("int $3")
    → int3_tramp: save regs, call gdb_handler
      → gdb_handler first byte is 0xCC (Z0 breakpoint)
        → CPU triggers nested INT3
          → int3_tramp: gdb_handler_depth already 1, re-enters handler
```

### Key Traps

1. **`gdb_from_poll` misleads nested path**: Outer INT3 comes from
   `gdb_poll`, so `gdb_from_poll = 1`. The nested INT3 is triggered by a
   **hardware breakpoint** (should be `gdb_from_poll = 0`), but the flag is
   still 1 from the outer call. The EIP fixup (`!gdb_from_poll && ... →
   r->eip--`) is skipped, leaving `r->eip` at `gdb_handler + 1` (past the
   breakpoint) instead of `gdb_handler` (the breakpoint address).

2. **Breakpoint address mismatch**: Z0 is set at `gdb_handler` (addr),
   but the nested handler checks `r->eip` which is `addr + 1`. The
   `bp_table` lookup for `addr + 1` finds no entry, so the original byte
   is never restored.

3. **TF single-step infinite loop**: The original `.nested` path used
   `pushfd; or [esp], 0x100; popfd` to set TF on the **current** EFLAGS
   (not the CPU-pushed EFLAGS), causing every subsequent instruction to
   fire INT1. The INT1 handler did the same, creating an infinite INT1 loop.

## Debugging Process

### First build & test

```bash
make clean all && bash tests/gdb-over-serial-reentrancy.sh
```
Output: 4/6 pass, tests 4-6 fail. `? after breakpoint got ''` — no serial
response at all.

### Add debug markers

Inserted `gdb_io_write('R')` in the nested path. Rebuilt — still no output.
The nested path either was never reached or crashed before executing it.

### Disassembly verification

Used `objdump -d build/kernel.elf` to check the trampoline code, confirmed
`inc/dec [gdb_handler_depth]` and `call gdb_handler` were generated correctly.

### Key Insight

Static analysis of the full call chain revealed that `gdb_from_poll` has
incorrect semantics in nested calls. After printing register state,
`gdb_handler`'s struct regs had `eip = addr + 1` instead of `addr`.

### Why gdb-over-serial.sh never caught this

`gdb-over-serial.sh` uses `gdb -batch`, which automatically handles
`qSupported` and other protocol negotiation. GDB never sets a breakpoint
at `gdb_handler`'s entry in normal use, so the reentrancy bug was never
triggered.

## Reentrancy Design

### Final Solution: Remove All Before Entry

**Core idea**: Remove all breakpoints **before** calling `gdb_handler`
from the trampoline, then re-insert them after the handler returns.

```
int3_tramp:
  save registers
  bp_remove_all()    ← remove all breakpoints (including 0xCC at gdb_handler)
  gdb_handler()       ← safe entry, no 0xCC, no reentrancy
  bp_insert_all()     ← restore breakpoints
  restore registers, iret
```

### Key Conventions

- **`bp_remove_all()` does NOT set `active = 0`**: it only restores original
  bytes. The `active` flag stays set so `bp_insert_all()` knows where to write
  0xCC.
- **`bp_remove_all()` / `bp_insert_all()` are global**: called directly from
  the asm trampoline via `extern` declarations.
- **No depth counter needed**: since reentrancy is prevented, `gdb_handler`
  no longer needs a `gdb_handler_depth > 1` check.

### Why Not Fix Inside the Handler

Fixing inside the handler would require:
- Resolving the `gdb_from_poll` semantic conflict
- Correcting EIP and breakpoint table lookup in the nested handler
- Handling the stack frame offset (missing `push ebp` shifts struct regs
  pointer by 4 bytes)

High risk and complex. Prevention at the trampoline level is simpler and
more reliable.

## Design Decision Log

| Approach | Problem | Verdict |
|----------|---------|---------|
| `.nested` TF single-step | `pushfd/or [esp]/popfd` modifies current EFLAGS → infinite INT1 loop | Discarded |
| `.nested` write `[esp+60]` for TF | INT1 still triggers `mov gdb_in_handler, 0` then re-enters handler | Discarded |
| C handler depth detection | `gdb_from_poll` semantic bug, breakpoint address mismatch | Discarded |
| **Trampoline bp_remove_all** | Prevention not fix — simple and reliable | **Adopted** |

## Test Method (gdb-over-serial-reentrancy.sh)

See `tests/gdb-over-serial-reentrancy.sh`.
