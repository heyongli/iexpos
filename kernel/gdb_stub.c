#include "gdb_stub.h"

#define COM1            0x3F8
#define IDT_ENTRIES     256
#define BP_TABLE_SIZE   32

/* register context saved by INT3/INT1 handler */
struct regs {
    unsigned int edi, esi, ebp, _esp, ebx, edx, ecx, eax;
    unsigned int ss, ds, es, fs, gs;
    unsigned int eip, cs, eflags;
};

/* IDT entry */
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

/* breakpoint table */
static struct {
    unsigned int  addr;
    unsigned char saved;
    int           active;
} bp_table[BP_TABLE_SIZE];

static volatile int gdb_active;
static volatile int gdb_from_poll;

/* serial — must use outb/inb (x86 port I/O), NOT *(volatile *) memory access.
   GCC on x86 compiles *(0x3F8) to mov, which writes to memory, not UART. */
static void serial_out(char c) {
    __asm__ volatile("outb %0, %1" : : "a"((unsigned char)c), "Nd"((unsigned short)COM1));
}
static char serial_in(void) {
    unsigned char lsr;
    do {
        __asm__ volatile("inb %1, %0" : "=a"(lsr) : "Nd"((unsigned short)0x3FD));
    } while (!(lsr & 1));
    unsigned char c;
    __asm__ volatile("inb %1, %0" : "=a"(c) : "Nd"((unsigned short)COM1));
    return c;
}

/* hex */
static char hex(unsigned char v) {
    return v < 10 ? '0' + v : 'a' + v - 10;
}
static int h2v(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return 0;
}

/* send $payload#ck — GDB packet framing */
static void gdb_send(const char *data) {
    unsigned char ck = 0;
    serial_out('$');
    for (const char *p = data; *p; p++) { ck += *p; serial_out(*p); }
    serial_out('#');
    serial_out(hex(ck >> 4));
    serial_out(hex(ck & 0xF));
}

/* read a packet into buf, return 1 on success
   waits $, reads until #, verifies 2-char checksum, sends +/- ACK */
static int gdb_recv(char *buf, int max) {
    int pos = 0;
    unsigned char ck = 0;
    char c;
    while ((c = serial_in()) != '$');
    while (pos < max - 1) {
        c = serial_in();
        if (c == '#') break;
        buf[pos++] = c;
    }
    buf[pos] = 0;
    int hi = h2v(serial_in()), lo = h2v(serial_in());
    for (int i = 0; i < pos; i++) ck += (unsigned char)buf[i];
    if ((hi << 4 | lo) != ck) { serial_out('-'); return 0; }
    serial_out('+');
    return 1;
}

/* pack regs in GDB x86-32 order (EAX,ECX,EDX,EBX,ESP,EBP,ESI,EDI,EIP,EFLAGS,CS,SS,DS,ES,FS,GS) */
static void pack_regs(struct regs *r, char *out) {
    unsigned int *v[] = {&r->eax, &r->ecx, &r->edx, &r->ebx, &r->_esp,
                         &r->ebp, &r->esi, &r->edi, &r->eip, &r->eflags,
                         &r->cs,  &r->ss,  &r->ds,  &r->es,  &r->fs,  &r->gs};
    char *p = out;
    for (int i = 0; i < 16; i++)
        for (int b = 0; b < 4; b++) {
            unsigned char byte = (*v[i] >> (b * 8)) & 0xFF;
            *p++ = hex(byte >> 4);
            *p++ = hex(byte & 0xF);
        }
    *p = 0;
}

/* unpack GDB hex regs into struct */
static void unpack_regs(const char *hex, struct regs *r) {
    unsigned int *v[] = {&r->eax, &r->ecx, &r->edx, &r->ebx, &r->_esp,
                         &r->ebp, &r->esi, &r->edi, &r->eip, &r->eflags,
                         &r->cs,  &r->ss,  &r->ds,  &r->es,  &r->fs,  &r->gs};
    for (int i = 0; i < 16; i++) {
        unsigned int val = 0;
        for (int b = 0; b < 4; b++)
            val |= (unsigned int)(h2v(hex[i*8+b*2]) << (b*8+4)) | (unsigned int)(h2v(hex[i*8+b*2+1]) << (b*8));
        *v[i] = val;
    }
}

static void set_gate(int n, unsigned int addr) {
    idt[n].offset_lo = addr & 0xFFFF;
    idt[n].sel       = 0x08;
    idt[n].zero      = 0;
    idt[n].attr      = 0x8E;
    idt[n].offset_hi = (addr >> 16) & 0xFFFF;
}

static void bp_remove_all(void) {
    for (int i = 0; i < BP_TABLE_SIZE; i++)
        if (bp_table[i].active) {
            *((volatile unsigned char *)bp_table[i].addr) = bp_table[i].saved;
            bp_table[i].active = 0;
        }
}

static void bp_insert_all(void) {
    for (int i = 0; i < BP_TABLE_SIZE; i++)
        if (bp_table[i].active)
            *((volatile unsigned char *)bp_table[i].addr) = 0xCC;
}

/* C stub handler — called from asm trampoline */
static void gdb_handler(struct regs *r) {
    if (!gdb_active) return;

    /* INT3 from 0xCC breakpoint (gdb_from_poll==0): CPU pushed EIP past 0xCC,
       back up by 1 to re-execute.  For int $3 from gdb_poll (gdb_from_poll==1)
       the CPU already points past the instruction; no adjustment needed. */
    if (!gdb_from_poll)
        r->eip--;

    char buf[256], reply[1024];
    int running = 1;

    gdb_send("T05");

    while (running) {
        if (!gdb_recv(buf, sizeof(buf))) continue;
        switch (buf[0]) {
        case '?': gdb_send("S05"); break;
        case 'c':
            bp_insert_all();
            running = 0;
            break;
        case 's':
            r->eflags |= 0x100;
            bp_insert_all();
            running = 0;
            break;
        case 'g':
            pack_regs(r, reply);
            gdb_send(reply);
            break;
        case 'G':
            unpack_regs(buf + 1, r);
            gdb_send("OK");
            break;
        case 'm': {
            unsigned int a = 0, l = 0;
            char *p = buf + 1;
            while (*p && *p != ',') { a = a * 16 + h2v(*p); p++; }
            if (*p == ',') p++;
            while (*p) { l = l * 16 + h2v(*p); p++; }
            if (l > 512) l = 512;
            char *rp = reply;
            for (unsigned int i = 0; i < l; i++) {
                unsigned char b = *((volatile unsigned char *)(a + i));
                *rp++ = hex(b >> 4); *rp++ = hex(b & 0xF);
            }
            *rp = 0;
            gdb_send(reply);
            break;
        }
        case 'M': {
            unsigned int a = 0, l = 0;
            char *p = buf + 1;
            while (*p && *p != ',') { a = a * 16 + h2v(*p); p++; }
            if (*p == ',') p++;
            while (*p && *p != ':') { l = l * 16 + h2v(*p); p++; }
            if (*p == ':') p++;
            if (l > 512) l = 512;
            for (unsigned int i = 0; i < l; i++)
                *((volatile unsigned char *)(a + i)) = (h2v(p[i*2]) << 4) | h2v(p[i*2+1]);
            gdb_send("OK");
            break;
        }
        case 'Z':
            if (buf[1] == '0' && buf[2] == ',') {
                unsigned int a = 0;
                char *p = buf + 3;
                while (*p && *p != ',') { a = a * 16 + h2v(*p); p++; }
                int found = 0;
                for (int i = 0; i < BP_TABLE_SIZE && !found; i++)
                    if (!bp_table[i].active) {
                        bp_table[i].saved  = *((volatile unsigned char *)a);
                        *((volatile unsigned char *)a) = 0xCC;
                        bp_table[i].addr   = a;
                        bp_table[i].active = 1;
                        found = 1;
                    }
                gdb_send(found ? "OK" : "E02");
            } else gdb_send("E01");
            break;
        case 'z':
            if (buf[1] == '0' && buf[2] == ',') {
                unsigned int a = 0;
                char *p = buf + 3;
                while (*p && *p != ',') { a = a * 16 + h2v(*p); p++; }
                int found = 0;
                for (int i = 0; i < BP_TABLE_SIZE && !found; i++)
                    if (bp_table[i].active && bp_table[i].addr == a) {
                        *((volatile unsigned char *)a) = bp_table[i].saved;
                        bp_table[i].active = 0;
                        found = 1;
                    }
                gdb_send(found ? "OK" : "E02");
            } else gdb_send("E01");
            break;
        case 'k':
            __asm__ volatile("cli; hlt");
            break;
        default:  gdb_send("E01"); break;
        }
    }
}

/* ASM trampolines for INT1 and INT3:
   Stack after INT (low→high):
   EDI ESI EBP _ESP EBX EDX ECX EAX   (pusha, 32 bytes)
   SS DS ES FS GS                      (our push, 20 bytes)
   EIP CS EFLAGS                       (CPU, 12 bytes) */
__asm__(
".globl int1_tramp\n"
"int1_tramp:\n"
"    pusha\n"
"    push %ss\n"
"    push %gs\n"
"    push %fs\n"
"    push %es\n"
"    push %ds\n"
"    mov %esp, %eax\n"
"    pushl %eax\n"
"    call gdb_handler_wrap\n"
"    popl %eax\n"
"    pop %ds\n"
"    pop %es\n"
"    pop %fs\n"
"    pop %gs\n"
"    pop %ss\n"
"    popa\n"
"    iret\n"
"\n"
".globl int3_tramp\n"
"int3_tramp:\n"
"    pusha\n"
"    push %ss\n"
"    push %gs\n"
"    push %fs\n"
"    push %es\n"
"    push %ds\n"
"    mov %esp, %eax\n"
"    pushl %eax\n"
"    call gdb_handler_wrap\n"
"    popl %eax\n"
"    pop %ds\n"
"    pop %es\n"
"    pop %fs\n"
"    pop %gs\n"
"    pop %ss\n"
"    popa\n"
"    iret\n"
"\n"
".globl default_tramp\n"
"default_tramp:\n"
"    iret\n"
);

/* asm labels */
extern void int1_tramp(void), int3_tramp(void), default_tramp(void);

static void gdb_handler_wrap(struct regs *r) {
    gdb_handler(r);
}

void gdb_stub_init(void) {
    /* Clear MCR (0x3FC) — QEMU default leaves Loopback (bit 4) set,
       which disconnects the chardev (TCP/file) from UART RX.  Without
       this, external bytes never reach RBR and LSR.DR stays 0. */
    __asm__ volatile("outb %0, %1" : : "a"((unsigned char)0), "Nd"((unsigned short)0x3FC));
    for (int i = 0; i < IDT_ENTRIES; i++)
        set_gate(i, (unsigned int)&default_tramp);
    set_gate(1, (unsigned int)&int1_tramp);
    set_gate(3, (unsigned int)&int3_tramp);
    __asm__ volatile("lidt %0" : : "m"(idt_desc));
}

/* Serial loopback test: verify THR→RBR round-trip.
   Enables loopback, writes 4 test bytes, reads each back with
   LSR.DR wait, compares.  Outputs SRW:P/F marker for tests. */
void serial_rw_test(void) {
    const unsigned char test[4] = { 0x55, 0xAA, '!', '\n' };
    unsigned char ok = 1;

    __asm__ volatile("outb %0, %1"
        : : "a"((unsigned char)0x10), "Nd"((unsigned short)0x3FC));

    for (int i = 0; i < 4; i++) {
        __asm__ volatile("outb %0, %1"
            : : "a"(test[i]), "Nd"((unsigned short)0x3F8));
        unsigned char lsr;
        do {
            __asm__ volatile("inb %1, %0" : "=a"(lsr) : "Nd"((unsigned short)0x3FD));
        } while (!(lsr & 1));
        unsigned char got;
        __asm__ volatile("inb %1, %0" : "=a"(got) : "Nd"((unsigned short)0x3F8));
        if (got != test[i]) ok = 0;
    }

    __asm__ volatile("outb %0, %1"
        : : "a"((unsigned char)0), "Nd"((unsigned short)0x3FC));

    serial_out('S');
    serial_out('R');
    serial_out('W');
    serial_out(':');
    serial_out(ok ? 'P' : 'F');
    serial_out('\n');
}

static unsigned char inb(unsigned short port) {
    unsigned char v;
    __asm__ volatile("inb %1, %0" : "=a"(v) : "Nd"(port));
    return v;
}
static void outb(unsigned char v, unsigned short port) {
    __asm__ volatile("outb %0, %1" : : "a"(v), "Nd"(port));
}

void gdb_poll(void) {
    /* Check LSR.DR — do NOT read RBR here.  The byte must remain for
       gdb_recv() inside the INT3 handler to consume.  If we read it now,
       gdb_recv will block forever waiting for the $ start-of-packet. */
    if (inb(0x3FD) & 1) {
        gdb_active = 1;
        gdb_from_poll = 1;       /* tell gdb_handler: don't adjust EIP */
        __asm__ volatile("int $3");
        gdb_from_poll = 0;
        gdb_active = 0;
    }
}
