CC      = gcc
LD      = ld
AS      = nasm
CFLAGS  = -m32 -ffreestanding -fno-PIC -fno-asynchronous-unwind-tables -nostdlib -nostartfiles -I. -I bmX86
LDFLAGS = -m elf_i386 -Ttext 0x7E00 -e entry --oformat binary -n

all: vm-raw.img

boot.bin: boot/boot.asm
	$(AS) -f bin $< -o $@

entry.o: entry.asm
	$(AS) -f elf32 $< -o $@

bmX86/vga.o: bmX86/vga.c bmX86/vga.h font_8x16.h console.h baremetal.h
	$(CC) $(CFLAGS) -c $< -o $@

bmX86/rtc.o: bmX86/rtc.c bmX86/rtc.h
	$(CC) $(CFLAGS) -c $< -o $@

kernel.o: kernel.c baremetal.h ui.h
	$(CC) $(CFLAGS) -c $< -o $@

console.o: console.c console.h baremetal.h
	$(CC) $(CFLAGS) -c $< -o $@

ui.o: ui.c ui.h baremetal.h
	$(CC) $(CFLAGS) -c $< -o $@

kernel.bin: entry.o console.o ui.o bmX86/rtc.o kernel.o bmX86/vga.o
	$(LD) $(LDFLAGS) $^ -o $@

image.bin: boot.bin kernel.bin
	cat $^ > $@

vm-raw.img: image.bin
	qemu-img create -f raw $@ 10M 2>/dev/null
	dd if=$< of=$@ conv=notrunc 2>/dev/null

run: vm-raw.img
	sg kvm -c "qemu-system-x86_64 -enable-kvm -m 2G -nographic -smp 2 -vga std -hda $$(pwd)/vm-raw.img -net none"

run-curses: vm-raw.img
	sg kvm -c "qemu-system-x86_64 -enable-kvm -m 2G -display curses -smp 2 -vga std -hda $$(pwd)/vm-raw.img -net none"

.PHONY: all run run-curses clean

clean:
	rm -f boot.bin entry.o console.o ui.o bmX86/rtc.o bmX86/vga.o kernel.o kernel.bin image.bin vm-raw.img
