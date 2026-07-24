#include "rtc.h"

#define CMOS_ADDR 0x70
#define CMOS_DATA 0x71

static unsigned char cmos_read(unsigned char reg) {
    unsigned char val, addr = reg | 0x80;
    __asm__ volatile("outb %0, %1" : : "a"(addr), "Nd"((unsigned short)CMOS_ADDR));
    __asm__ volatile("inb %1, %0" : "=a"(val) : "Nd"((unsigned short)CMOS_DATA));
    return val;
}

static unsigned char bcd(unsigned char v) {
    return (v >> 4) * 10 + (v & 0x0F);
}

int rtc_read_time(unsigned char *h, unsigned char *m, unsigned char *s) {
    while (cmos_read(0x0A) & 0x80);
    cmos_read(0x00);
    while (cmos_read(0x0A) & 0x80);
    *s = bcd(cmos_read(0x00));
    *m = bcd(cmos_read(0x02));
    *h = bcd(cmos_read(0x04));
    return 1;
}

void rtc_format_ts(char buf[9]) {
    unsigned char h, m, s;
    if (!rtc_read_time(&h, &m, &s)) {
        buf[0] = '?'; buf[1] = '?'; buf[2] = ':';
        buf[3] = '?'; buf[4] = '?'; buf[5] = ':';
        buf[6] = '?'; buf[7] = '?'; buf[8] = ' ';
        return;
    }
    buf[0] = '0' + h / 10; buf[1] = '0' + h % 10; buf[2] = ':';
    buf[3] = '0' + m / 10; buf[4] = '0' + m % 10; buf[5] = ':';
    buf[6] = '0' + s / 10; buf[7] = '0' + s % 10; buf[8] = ' ';
}

void write_timestamp(output_fn out) {
    char buf[10];
    rtc_format_ts(buf);
    buf[9] = '\0';
    out(buf);
}

/* baremetal.h API */
int  bm_rtc_read(unsigned char *h, unsigned char *m, unsigned char *s) { return rtc_read_time(h, m, s); }
void bm_rtc_format(char buf[9]) { rtc_format_ts(buf); }
