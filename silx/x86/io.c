#include "io.h"

/* Arm PIT channel 0 (mode 3, LSB+MSB) with count 0 = 65536 so the 16-bit
 * counter free-runs at the full 1.193182 MHz clock, wrapping 65535->0.
 * Without a programmed count QEMU never starts the counter and pit_read()
 * returns a frozen value (breaks elapsed_pit/mdelay). A small count like 1
 * would be useless too: the counter would only read 0/1 and elapsed_pit
 * could never accumulate to PIT_FRAME_TICKS. */
void pit_init(void) {
    __asm__ volatile("outb %0, %1" : : "a"((unsigned char)0x36), "Nd"((unsigned short)0x43));
    __asm__ volatile("outb %0, %1" : : "a"((unsigned char)0x00), "Nd"((unsigned short)0x40));
    __asm__ volatile("outb %0, %1" : : "a"((unsigned char)0x00), "Nd"((unsigned short)0x40));
}

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
