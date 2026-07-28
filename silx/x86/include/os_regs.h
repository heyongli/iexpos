#ifndef OS_REGS_H
#define OS_REGS_H

/*
 * IO Abort Mechanism
 * =================
 * Uses CR4 bit 24 (reserved on modern CPUs) as a fast abort flag.
 *
 * Purpose: Allow any code DO BUSY WAITING to be aborted.
 * TODO: Work across CPUs via IPI + per-CPU flag, or same CPU.
 *
 * Flow:
 *   1. abort_io()      - Set the bit on target CPU (via IPI if remote)
 *   2. is_aborting()   - Check and clear the bit (read-and-clear)
 *   3. Dead loops should check is_aborting() to allow exit
 *
 * Note: If not cleared promptly, abort_io can disturb all local cpu.
 *
 * Requires: CPU Family >= 6 (Pentium Pro+) - verified at boot.
 */

/* CPUID: read CPU family number */
static inline unsigned int cpuid_family(void) {
    unsigned int eax;
    __asm__ volatile("cpuid" : "=a"(eax) : "a"(1) : "ebx","ecx","edx");
    return (eax >> 8) & 0xF;    /* bits 11:8 = Base Family */
}

/* CR4 bit 24: io abort flag
   Safe on Family >= 6 (Pentium Pro and later) */
#define CR4_IO_ABORT_BIT  BIT(24)

static inline unsigned int _cr4_read(void) {
    unsigned int val;
    __asm__ volatile("mov %%cr4, %0" : "=r"(val));
    return val;
}

static inline void _cr4_write(unsigned int val) {
    __asm__ volatile("mov %0, %%cr4" : : "r"(val));
}

/* io abort: test and clear via CR4 reserved bit */
static inline int is_aborting(void) {
    unsigned int val = _cr4_read();
    int aborting = val & CR4_IO_ABORT_BIT;
    if (aborting)
        _cr4_write(val & ~CR4_IO_ABORT_BIT);
    return aborting;
}

static inline void abort_io(void) {
    _cr4_write(_cr4_read() | CR4_IO_ABORT_BIT);
}

#endif
