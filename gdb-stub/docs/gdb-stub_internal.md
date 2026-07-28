# GDB Stub — Architecture Notes

## The Self-Debugging Kernel Problem

This kernel debugs itself. The same CPU that runs the kernel also handles
the debug exceptions (INT1, INT3) triggered by GDB.  This is unusual:
normally GDB controls a separate target (another machine, a VM, or a
process it forks).  Here, the "remote" stub runs on the very same CPU
that executes the code being debugged.

## How It Works (Without Infinite Recursion)

### Two Completely Independent Mechanisms

The stub relies on two separate ways to enter the debug handler:

| Trigger | How it enters the handler | Use |
|---------|--------------------------|-----|
| **0xCC from GDB** (`Z0`) | CPU executes `0xCC` → INT3 → `int3_tramp` → `gdb_handler` | Real breakpoints |
| **`int $3` from gdb_poll** (`gdb_poll` calls `__asm__("int $3")`) | Software interrupt → same INT3 gate → same handler | Polling for GDB commands between breakpoints |

These are distinguished by the `gdb_from_poll` flag, set to 1 before
`int $3` in `gdb_poll()` and reset to 0 after.  The handler uses this
flag to decide whether to send a `T05` stop reply (only real breakpoints
and single-step get a stop reply; poll-triggered entries just process
GDB packets silently).

### Why No Re-Entrancy Problem

The handler runs a command loop (`while (running)`).  It doesn't return
until GDB sends a resume command (`c`, `s`, `vCont;c`, `vCont;s`).
During this loop, the kernel is effectively suspended — all code
execution is inside `gdb_handler`.  Since `gdb_poll()` cannot be called
while the handler is active, there is no re-entrancy: the `int $3` in
`gdb_poll()` will not fire again until the handler returns and the
kernel loops back to `gdb_poll()`.

### The Polling Cycle

When the kernel is NOT at a breakpoint, it calls `gdb_poll()` in its
main loop.  If a byte arrives on the serial port, `gdb_poll()` stores
it, sets `gdb_from_poll = 1`, and executes `int $3`.  The handler
processes whatever command GDB sent (often a `?` status query or a
register read) and, crucially, does NOT send a `T05` (because
`gdb_from_poll` is 1).  After processing, the handler resumes waiting
for the next command.

If GDB sends a resume command (`continue` / `stepi`), the handler sets
`running = 0` and returns.  The kernel continues normal execution,
calling `gdb_poll()` on each iteration of the main loop.

### Breakpoint Flow

1. User does `break *gdb_poll`
2. GDB sends `Z0,addr,1` → stub saves the byte at `addr` and writes
   `0xCC` there
3. User does `continue`
4. GDB sends `vCont;c` → stub clears TF, sets `running = 0`, returns
5. Kernel resumes, eventually calls `gdb_poll()` again
6. CPU executes `0xCC` at the start of `gdb_poll` → INT3 fires
7. Handler entered with `gdb_from_poll = 0`:
   - Detects `0xCC` before EIP → backs up EIP by 1
   - Sends `T05` stop reply
   - Enters command loop
8. GDB receives `T05`, reports "Breakpoint 1, gdb_poll()..."

### Single-Step Flow

1. User does `stepi`
2. GDB sends `s` or `vCont;s` → stub sets EFLAGS.TF, `running = 0`, returns
3. CPU executes one instruction
4. INT1 fires (TF trap) → `int1_tramp` → `gdb_handler`
5. Handler entered with `gdb_from_poll = 0`, TF already cleared by CPU:
   - EIP is NOT adjusted (no `0xCC` before it)
   - Sends `T05` stop reply

## Register Context Layout

The trampoline in `tramp.asm` saves the full CPU context on the stack
in this order (low → high address):

| Offset | Contents | Source |
|--------|----------|--------|
| +0     | DS       | trampoline `push ds` |
| +4     | ES       | trampoline `push es` |
| +8     | FS       | trampoline `push fs` |
| +12    | GS       | trampoline `push gs` |
| +16    | SS       | trampoline `push ss` |
| +20    | EDI      | `pusha` |
| +24    | ESI      | `pusha` |
| +28    | EBP      | `pusha` |
| +32    | ESP (old)| `pusha` |
| +36    | EBX      | `pusha` |
| +40    | EDX      | `pusha` |
| +44    | ECX      | `pusha` |
| +48    | EAX      | `pusha` |
| +52    | EIP      | CPU interrupt |
| +56    | CS       | CPU interrupt |
| +60    | EFLAGS   | CPU interrupt |

The `struct regs` in C is laid out to exactly match this layout, with `r`
pointing to the DS slot.

## Debugging Journal — Bugs Found and How

### 1. `struct regs` Layout Mismatch (Hardest to Find)

**Symptom**: `set $eax = 0x12345678` then `continue` → "Cannot execute
this command while the target is running."  Everything else (`print`,
`stepi`, `break`, `backtrace`) worked fine.

**False trails**:
- Suspected the `P` (single-register write) handler had a byte-order
  bug.  Fixed it (LE vs BE) — `print` showed correct values but
  `continue` still failed.
- Thought GDB's async mode made it process stdin before the stop
  notification arrived.  Half-right: that's why the *error message*
  appeared, but not why the *breakpoint never fired*.
- Added `set debug remote 1` and noticed `Z0` was re-sent at
  `proceed()` time (after `set`) but sent immediately (before
  `continue`) without `set`.  Chased that red herring for a while.

**How found**: Laid out the trampoline's exact stack order on paper
(offsets from `r`, which points to DS after `push ds`).  Then laid out
the C struct field by field.  They didn't match:

```
Stack (from DS pointer)     C struct expected
[r+0]  DS                   edi
[r+4]  ES                   esi
[r+8]  FS                   ebp
[r+12] GS                   _esp
[r+16] SS                   ebx
[r+20] EDI                  edx
[r+24] ESI                  ecx
[r+28] EBP                  eax      ← set $eax wrote here = EBP!
[r+32] old_ESP              ss
[r+36] EBX                  ds
[r+40] EDX                  es
[r+44] ECX                  fs
[r+48] EAX                  gs
[r+52] EIP                  eip  (correct by accident)
[r+56] CS                   cs   (correct by accident)
[r+60] EFLAGS               eflags (correct by accident)
```

Every general and segment register was shifted by 5 fields.  `r->eax`
read/wrote EBP.  `set $eax` corrupted the frame pointer; after `iret`,
the kernel returned with a garbage EBP, code flow broke, and the
breakpoint at `gdb_poll` was never reached.

**Fix**: Reordered the struct fields to match the actual stack
layout: segment regs first, then general regs, then CPU regs.
`pack_regs`/`unpack_regs`/`P` handler needed no changes (they use
field names, compiler handles offsets).

**Lesson**: Never assume the struct layout matches the asm save order
without verifying offsets on paper.  Comment the struct with the
stack offset of each field.

---

### 2. `gdb_active` Guard Killed Real Breakpoints

**Symptom**: `break *gdb_poll` → `continue` → GDB looped forever
printing "Cannot execute this command while the target is running."

**Root cause**: `if (!gdb_active) return;` at the top of `gdb_handler`.
GDB defers `Z0` insertion to `continue` time, not `break` time.  When
the 0xCC fired, `gdb_active` was 0 (set to 0 after the previous
handler return), so the handler returned immediately without sending
`T05`.  GDB never received a stop notification.

**Fix**: Removed the `gdb_active` guard and the variable entirely.
The `gdb_from_poll` flag is sufficient to distinguish poll entries
from real breakpoints.

---

### 3. TF Leak on `continue` (Single-Step After Continue)

**Symptom**: After `stepi`, doing `continue` would single-step
indefinitely instead of running freely.

**Root cause**: `s` (step) set EFLAGS.TF (`r->eflags |= 0x100`) before
returning, but `c` (continue) never cleared it.  After `stepi`
followed by `continue`, TF was still set, so every instruction
triggered INT1.

**Fix**: Added `r->eflags &= ~0x100` to both `c` and `vCont;c`
handlers.

---

### 4. EIP Adjustment Corrupted Single-Step

**Symptom**: After `stepi`, the reported PC was one byte before the
actual next instruction.

**Root cause**: The handler unconditionally did `r->eip--` for all
INT3 entries.  But INT1 (single-step) and `int $3` from `gdb_poll`
don't need this adjustment — the CPU already pushes the correct EIP.
Only real 0xCC breakpoints need EIP backed up by 1 (the CPU
increments EIP past the 0xCC byte).

**Fix**: Changed to conditional: only back up EIP when
`*(r->eip - 1) == 0xCC`.

---

### 5. `P` Handler Byte Order

**Symptom**: `set $eax = 0x12345678` resulted in EAX = `0x78563412`.

**Root cause**: The `P` handler parsed the hex value as a big-endian
integer, but GDB sends register values in target byte order
(little-endian for x86).  `pack_regs`/`unpack_regs` used LE, so the
`P` handler was inconsistent with the rest of the stub.

**Fix**: Rewrote the `P` parser to accumulate bytes LSB-first,
matching `pack_regs`/`unpack_regs`.

---

### How to Debug the Stub Itself

Since the stub runs on the same CPU it debugs, you can't use GDB to
debug the debugger.  Useful techniques:

1. **`set debug remote 1`** in GDB — shows every packet sent/received.
   Critical for spotting unexpected packets or missing ACKs.

2. **Serial printf from the stub** — use `uart_busy_write` / `bm_puts`
   to dump state at key points.  Compile with `-DDEBUG` for extra
   tracing (controlled by `ABORT_TRACE`).

3. **Packet-level protocol test** — use `tests/gdb-over-serial-protocol.sh`
   (Python) to send raw GDB packets and verify responses without GDB's
   complex state machine getting in the way.

4. **Compare against QEMU's built-in GDB stub** (`qemu -gdb tcp::1234`).
   If a sequence works with QEMU's stub but not yours, the bug is in
   the stub, not in GDB.

5. **Paper trace the stack layout** — write out every push and every
   struct field offset by hand.  This is how the struct/layout mismatch
   was found.

## GDB Remote Protocol Notes

- Register order follows GDB's x86-32 target definition: EAX, ECX, EDX,
  EBX, ESP, EBP, ESI, EDI, EIP, EFLAGS, CS, SS, DS, ES, FS, GS
- `P` (single-register write) uses little-endian byte order matching
  the `pack_regs`/`unpack_regs` functions
- Breakpoints use `Z0`/`z0` (software breakpoint, type 0), inserting
  `0xCC` and saving the original byte in `bp_table[]`
- No hardware breakpoints or watchpoints are supported
