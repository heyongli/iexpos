# IO Abort — io.h / os_regs.h

## Purpose

Provide a **per-CPU abort flag** that busy-waiting loops (UART polling, GDB
stub) can check, allowing them to be interrupted from another CPU or an
interrupt handler.

## Implementation: CR4 bit 24

Uses **CR4 bit 24**, a reserved bit on x86-64 CPUs, as the abort flag:

- Sets via `mov cr4, ... | BIT(24)` — single instruction, no memory access
- Reads and clears atomically via `mov cr4, ... & ~BIT(24)` — read-and-clear
- Available on all x86-64 CPUs (reserved, always reads as 0).
- Per-CPU on Intel; on AMD the flag may be visible to other cores, so
  `abort_io` uses IPI when targeting a remote CPU.

## API

```c
/* io.h */
#define _ABORT  BIT(29)   /* returned by busy loops when aborted */

/* os_regs.h (per-arch) */
void abort_io(void);         /* set abort flag on current CPU */
int  is_aborting(void);      /* check and clear abort flag */
int  arch_io_abort_check(void);  /* verify CPU supports CR4 bit 24 */
```

## Usage Example (UART busy write)

```c
while (!(inb(UART_LSR) & LSR_THR_EMPTY)) {
    if (is_aborting())
        return _IO_ERR | _ABORT;
}
```

## Why not a memory flag?

- A memory flag requires a cache-coherent write + read — slower and
  concurrency-sensitive.
- CR4 is a control register; `mov cr4` is serialising and does not go through
  the cache hierarchy.
- No memory needs to be reserved for the flag.

## Verification

- `arch_io_abort_check()` confirms the CPU supports CR4 bit 24 by writing the
  bit and reading it back.
- Test: `tests/io-abort.sh` — boots the kernel and checks for the init OK
  message and absence of the "CPU does not support" warning.
