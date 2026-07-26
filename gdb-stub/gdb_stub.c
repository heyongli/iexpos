#include "gdb_stub.h"
#include "gdb_io.h"
#include "gdb_idt.h"

#define BP_TABLE_SIZE   32

#ifdef DEBUG
static void abort_trace(const char *op) {
    while (*op) gdb_io_write(*op++);
    gdb_io_write('\n');
}
#define ABORT_TRACE(op) abort_trace(op)
#else
#define ABORT_TRACE(op) ((void)0)
#endif

/* register context saved by INT3/INT1 handler
   Layout matches the trampoline save order in tramp.asm:
   segment regs first, then general regs (pusha order), then CPU-pushed regs.
   r points to DS (first byte pushed by trampoline). */
struct regs {
    unsigned int ds, es, fs, gs, ss;
    unsigned int edi, esi, ebp, _esp, ebx, edx, ecx, eax;
    unsigned int eip, cs, eflags;
};

/* breakpoint table */
static struct {
    unsigned int  addr;
    unsigned char saved;
    int           active;
} bp_table[BP_TABLE_SIZE];

static volatile int gdb_from_poll;
static volatile int gdb_pending_byte;
static volatile int gdb_has_pending;
static volatile int gdb_negotiated;

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

/* string prefix match for GDB command parsing */
static int gdb_match(const char *buf, const char *cmd) {
    while (*cmd) {
        if (*buf++ != *cmd++) return 0;
    }
    return 1;
}

/* send $payload#ck — GDB packet framing */
static void gdb_send(const char *data) {
    unsigned char ck = 0;
    gdb_io_write('$');
    for (const char *p = data; *p; p++) { ck += *p; gdb_io_write(*p); }
    gdb_io_write('#');
    gdb_io_write(hex(ck >> 4));
    gdb_io_write(hex(ck & 0xF));
}

/* read a packet into buf, return 1 on success
   waits $, reads until #, verifies 2-char checksum, sends +/- ACK */
static int gdb_recv(char *buf, int max) {
    int pos = 0;
    unsigned char ck = 0;
    unsigned char c;
    int rc;

    /* Use pending byte from gdb_poll if available */
    if (gdb_has_pending) {
        c = gdb_pending_byte;
        gdb_has_pending = 0;
    } else {
        do { rc = gdb_io_read(&c); } while (rc == 0 && c != '$');
    }
    if (c != '$') {
        do { rc = gdb_io_read(&c); } while (rc == 0 && c != '$');
    }

    while (pos < max - 1) {
        rc = gdb_io_read(&c);
        if (rc != 0) break;
        if (c == '#') break;
        buf[pos++] = c;
    }
    buf[pos] = 0;
    rc = gdb_io_read(&c);
    int hi = (rc == 0) ? h2v(c) : 0;
    rc = gdb_io_read(&c);
    int lo = (rc == 0) ? h2v(c) : 0;
    for (int i = 0; i < pos; i++) ck += (unsigned char)buf[i];
    if ((hi << 4 | lo) != ck) { gdb_io_write('-'); return 0; }
    gdb_io_write('+');
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
static void unpack_regs(const char *hex_str, struct regs *r) {
    unsigned int *v[] = {&r->eax, &r->ecx, &r->edx, &r->ebx, &r->_esp,
                         &r->ebp, &r->esi, &r->edi, &r->eip, &r->eflags,
                         &r->cs,  &r->ss,  &r->ds,  &r->es,  &r->fs,  &r->gs};
    for (int i = 0; i < 16; i++) {
        unsigned int val = 0;
        for (int b = 0; b < 4; b++)
            val |= (unsigned int)(h2v(hex_str[i*8+b*2]) << (b*8+4)) | (unsigned int)(h2v(hex_str[i*8+b*2+1]) << (b*8));
        *v[i] = val;
    }
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
void gdb_handler(struct regs *r) {
    /* Adjust EIP for INT3 from 0xCC breakpoint: CPU pushed EIP past
       the 0xCC byte, so back up by 1 to re-execute the original instruction.
       INT1 (single-step) or int $3 from gdb_poll do not need adjustment.
       Detect by checking the byte preceding EIP. */
    if (!gdb_from_poll && r->eip > 0 &&
        *(volatile unsigned char *)(r->eip - 1) == 0xCC)
        r->eip--;

    char buf[256], reply[1024];
    int running = 1;

    gdb_negotiated = 0;

    /* Only send stop reply for real breakpoints, not poll-triggered ACKs */
    if (!gdb_from_poll)
        gdb_send("T05");

    while (running) {
        if (!gdb_recv(buf, sizeof(buf))) continue;

        /* Handle GDB protocol negotiation */
        if (buf[0] == 'v') {
            if (gdb_match(buf, "vMustReplyEmpty")) {
                gdb_send("OK");
                continue;
            }
            if (gdb_match(buf, "vCont")) {
                if (buf[5] == '?') {
                    gdb_send("vCont;c;C;s;S;");
                } else if (buf[5] == ';' && buf[6] == 'c') {
                    r->eflags &= ~0x100;
                    running = 0;
                } else if (buf[5] == ';' && buf[6] == 's') {
                    r->eflags |= 0x100;
                    running = 0;
                } else {
                    gdb_send("");
                }
                continue;
            }
            gdb_send("");
            continue;
        }
        if (buf[0] == 'H') {
            gdb_send("OK");
            continue;
        }
        if (buf[0] == 'q') {
            if (gdb_match(buf, "qSupported")) {
                if (!gdb_negotiated)
                    gdb_send("PacketSize=200");
                gdb_negotiated = 1;
                continue;
            }
            if (gdb_match(buf, "qTStatus")) {
                gdb_send("T0");
                continue;
            }
            if (gdb_match(buf, "qfThreadInfo")) {
                gdb_send("l1");
                continue;
            }
            if (gdb_match(buf, "qsThreadInfo")) {
                gdb_send("l");
                continue;
            }
            if (gdb_match(buf, "qC")) {
                gdb_send("QC1");
                continue;
            }
            if (gdb_match(buf, "qAttached")) {
                gdb_send("1");
                continue;
            }
            if (gdb_match(buf, "qOffsets")) {
                gdb_send("Text=0;Data=0;Bss=0");
                continue;
            }
            if (gdb_match(buf, "qSymbol")) {
                gdb_send("");
                continue;
            }
            if (gdb_match(buf, "qTfP")) {
                gdb_send("");
                continue;
            }
            if (gdb_match(buf, "qTfV")) {
                gdb_send("");
                continue;
            }
            if (gdb_match(buf, "qXfer")) {
                gdb_send("");
                continue;
            }
            gdb_send("");
            continue;
        }
        if (buf[0] == '+') continue;  /* ACK */
        if (buf[0] == '-') continue;  /* NAK */

        switch (buf[0]) {
        case '?': gdb_send("S05"); break;
        case 'c':
            r->eflags &= ~0x100;
            running = 0;
            break;
        case 's':
            r->eflags |= 0x100;
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
        case 'P': {
            unsigned int reg = 0, val = 0;
            char *p = buf + 1;
            while (*p && *p != '=') { reg = reg * 16 + h2v(*p); p++; }
            if (*p == '=') p++;
            int shift = 0;
            while (*p && shift < 32) {
                val |= (h2v(p[0]) << 4 | h2v(p[1])) << shift;
                shift += 8;
                p += 2;
            }
            unsigned int *regs[] = {&r->eax, &r->ecx, &r->edx, &r->ebx, &r->_esp,
                                    &r->ebp, &r->esi, &r->edi, &r->eip, &r->eflags,
                                    &r->cs,  &r->ss,  &r->ds,  &r->es,  &r->fs,  &r->gs};
            if (reg < 16) {
                *regs[reg] = val;
                gdb_send("OK");
            } else {
                gdb_send("E01");
            }
            break;
        }
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
        case 'D':
            gdb_send("OK");
            running = 0;
            break;
        case 'k':
            __asm__ volatile("cli; hlt");
            break;
        default:  gdb_send("E01"); break;
        }
    }
}

void gdb_stub_init(void) {
    gdb_io_init();
    gdb_idt_init();
}

void serial_rw_test(void) {
    gdb_io_loopback_test();
}

void gdb_poll(void) {
    if (gdb_io_abort_pending()) {
        ABORT_TRACE("ABORT: GDB poll");
        return;
    }
    if (gdb_io_data_ready()) {
        unsigned char c;
        if (gdb_io_try_read(&c) < 0) return;
        /* Drain ACK/NAK bytes — check if $ follows */
        if (c == '+' || c == '-') {
            if (gdb_io_data_ready()) {
                if (gdb_io_try_read(&c) < 0) return;
            } else {
                return;
            }
        }
        gdb_pending_byte = c;
        gdb_has_pending = 1;
        gdb_from_poll = 1;
        __asm__ volatile("int $3");
        gdb_from_poll = 0;
    }
}
