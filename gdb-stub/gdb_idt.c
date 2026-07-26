#include "gdb_idt.h"

#define IDT_ENTRIES 256

struct idt_entry {
    unsigned short offset_lo;
    unsigned short sel;
    unsigned char  zero;
    unsigned char  attr;
    unsigned short offset_hi;
};

static struct idt_entry idt[IDT_ENTRIES];
static struct {
    unsigned short limit;
    unsigned int   base;
} __attribute__((packed)) idt_desc = { sizeof(idt) - 1, (unsigned int)idt };

extern void int1_tramp(void), int3_tramp(void), default_tramp(void);

static void set_gate(int n, unsigned int addr) {
    idt[n].offset_lo = addr & 0xFFFF;
    idt[n].sel       = 0x08;
    idt[n].zero      = 0;
    idt[n].attr      = 0x8E;
    idt[n].offset_hi = (addr >> 16) & 0xFFFF;
}

void gdb_idt_init(void) {
    for (int i = 0; i < IDT_ENTRIES; i++)
        set_gate(i, (unsigned int)&default_tramp);
    set_gate(1, (unsigned int)&int1_tramp);
    set_gate(3, (unsigned int)&int3_tramp);
    __asm__ volatile("lidt %0" : : "m"(idt_desc));
}
