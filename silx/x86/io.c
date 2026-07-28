#include "io.h"

unsigned short pit_read(void) {
    __asm__ volatile("outb %0, %1" : : "a"((unsigned char)0x00), "Nd"((unsigned short)0x43));
    unsigned char low, high;
    __asm__ volatile("inb %1, %0" : "=a"(low) : "Nd"((unsigned short)0x40));
    __asm__ volatile("inb %1, %0" : "=a"(high) : "Nd"((unsigned short)0x40));
    return low | (high << 8);
}

void mdelay(unsigned int ms) {
    unsigned short start = pit_read();
    unsigned int target = ms * 1193u;
    while (1) {
        unsigned int elapsed = (start - (unsigned int)pit_read()) & 0xFFFFu;
        if (elapsed >= target)
            break;
    }
}
