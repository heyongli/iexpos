#ifndef OS_REGS_H
#define OS_REGS_H

/* OS-reserved bits in x86 control registers
   CR4 bits 24-31 are reserved on modern CPUs (Family >= 6).
   CPUID is used to verify at boot time. */

/* CPUID: read CPU family number */
static inline unsigned int cpuid_family(void) {
    unsigned int eax;
    __asm__ volatile("cpuid" : "=a"(eax) : "a"(1) : "ebx","ecx","edx");
    return (eax >> 8) & 0xF;    /* bits 11:8 = Base Family */
}

/* CR4 bit 24: io abort flag
   Safe on Family >= 6 (Pentium Pro and later) */
#define CR4_IO_ABORT_BIT  BIT(24)

static inline unsigned int cr4_read(void) {
    unsigned int val;
    __asm__ volatile("mov %%cr4, %0" : "=r"(val));
    return val;
}

static inline void cr4_write(unsigned int val) {
    __asm__ volatile("mov %0, %%cr4" : : "r"(val));
}

/* io abort: test/set/clear via CR4 reserved bit */
static inline int io_abort_test(void) {
    return cr4_read() & CR4_IO_ABORT_BIT;
}

static inline void io_abort_set(void) {
    cr4_write(cr4_read() | CR4_IO_ABORT_BIT);
}

static inline void io_abort_clr(void) {
    cr4_write(cr4_read() & ~CR4_IO_ABORT_BIT);
}

/* boot-time check: verify CPU supports CR4 reserved bit usage */
static inline int io_abort_init(void) {
    return cpuid_family() >= 6;  /* 1 = OK, 0 = CPU too old */
}

#endif
