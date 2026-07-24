CC      = gcc
LD      = ld
AS      = nasm
CFLAGS  = -g -m32 -ffreestanding -fno-PIC -fno-asynchronous-unwind-tables -nostdlib -nostartfiles -I. -I bmX86 -I ui -I demos -I kernel -I kernel/include
LDFLAGS = -m elf_i386 -Ttext 0x7E00 -e entry --oformat binary -n
LDFLAGS_ELF = -m elf_i386 -Ttext 0x7E00 -e entry -n
BDIR    = build

OBJS = $(BDIR)/entry.o $(BDIR)/console.o $(BDIR)/ui.o $(BDIR)/rtc.o \
        $(BDIR)/setup.o $(BDIR)/vga.o $(BDIR)/orbit.o $(BDIR)/gdb_stub.o $(BDIR)/serial.o $(BDIR)/uart.o

all: $(BDIR)/vm-raw.img $(BDIR)/kernel.elf

$(BDIR):
	mkdir -p $@

$(BDIR)/boot.bin: boot/boot.asm | $(BDIR)
	$(AS) -f bin $< -o $@

$(BDIR)/entry.o: boot/entry.asm | $(BDIR)
	$(AS) -f elf32 $< -o $@

$(BDIR)/vga.o: bmX86/vga.c bmX86/vga.h kernel/include/font_8x16.h kernel/console.h kernel/include/baremetal.h | $(BDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BDIR)/rtc.o: bmX86/rtc.c bmX86/rtc.h | $(BDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BDIR)/uart.o: bmX86/uart.c bmX86/include/uart.h | $(BDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BDIR)/serial.o: bmX86/serial.c bmX86/include/serial_dev.h | $(BDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BDIR)/setup.o: kernel/setup.c kernel/include/baremetal.h demos/demos.h kernel/gdb_stub.h | $(BDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BDIR)/gdb_stub.o: kernel/gdb_stub.c kernel/gdb_stub.h | $(BDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BDIR)/console.o: kernel/console.c kernel/console.h kernel/include/baremetal.h | $(BDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BDIR)/ui.o: ui/ui.c ui/ui.h kernel/include/baremetal.h | $(BDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BDIR)/orbit.o: demos/orbit.c demos/demos.h kernel/include/baremetal.h ui/ui.h | $(BDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BDIR)/kernel.bin: $(OBJS)
	$(LD) $(LDFLAGS) $^ -o $@

$(BDIR)/kernel.elf: $(OBJS)
	$(LD) $(LDFLAGS_ELF) $^ -o $@

$(BDIR)/image.bin: $(BDIR)/boot.bin $(BDIR)/kernel.bin
	tools/patch-boot-sectors $(BDIR)/boot.bin $(BDIR)/kernel.bin; \
	cat $^ > $@

$(BDIR)/vm-raw.img: $(BDIR)/image.bin
	qemu-img create -f raw $@ 10M 2>/dev/null
	dd if=$< of=$@ conv=notrunc 2>/dev/null

run: $(BDIR)/vm-raw.img
	sg kvm -c "qemu-system-x86_64 -enable-kvm -m 2G -nographic -smp 2 -vga std -hda $$(pwd)/$(BDIR)/vm-raw.img -net none"

run-curses: $(BDIR)/vm-raw.img
	sg kvm -c "qemu-system-x86_64 -enable-kvm -m 2G -display curses -smp 2 -vga std -hda $$(pwd)/$(BDIR)/vm-raw.img -net none"

gdb-qemu: $(BDIR)/vm-raw.img $(BDIR)/kernel.elf
	@echo "=== GDB via QEMU ==="
	@echo "Run: gdb -x tests/gdb-qemu.gdb"
	@echo ""
	sg kvm -c "qemu-system-x86_64 -enable-kvm -m 2G -nographic -smp 2 -vga std -hda $$(pwd)/$(BDIR)/vm-raw.img -net none -s -S"

gdb-test: $(BDIR)/vm-raw.img $(BDIR)/kernel.elf
	@echo "=== GDB via QEMU (automated test) ==="
	DIR=$(CURDIR) tests/gdb-qemu.sh

.PHONY: all run run-curses gdb-qemu gdb-stub-test clean

clean:
	rm -rf $(BDIR) kernel/*.o
