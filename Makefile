CC      = gcc
LD      = ld
AS      = nasm
CFLAGS  = -g -m32 -ffreestanding -fno-PIC -fno-asynchronous-unwind-tables -nostdlib -nostartfiles -I. -Imeta -I silx -I silx/x86 -I silx/x86/include -I ui -I ui/demos -I kernel -I kernel/include -I gdb-stub
CFLAGS_DEBUG = $(CFLAGS) -DDEBUG
LDFLAGS = -m elf_i386 -Ttext 0x7E00 -e entry --oformat binary -n
LDFLAGS_ELF = -m elf_i386 -Ttext 0x7E00 -e entry -n
BDIR    = build

OBJS = $(BDIR)/entry.o $(BDIR)/console.o $(BDIR)/ui.o $(BDIR)/text.o $(BDIR)/rtc.o \
        $(BDIR)/setup.o $(BDIR)/vga.o $(BDIR)/orbit.o $(BDIR)/progress.o $(BDIR)/gdb_stub.o $(BDIR)/gdb_io.o $(BDIR)/gdb_idt.o $(BDIR)/tramp.o $(BDIR)/serial.o $(BDIR)/uart.o $(BDIR)/io.o

all: $(BDIR)/vm-raw.img $(BDIR)/kernel.elf

$(BDIR):
	mkdir -p $@

$(BDIR)/boot.bin: boot/boot.asm | $(BDIR)
	$(AS) -f bin $< -o $@

$(BDIR)/entry.o: boot/entry.asm | $(BDIR)
	$(AS) -f elf32 $< -o $@

$(BDIR)/vga.o: silx/x86/vga.c silx/x86/vga.h kernel/include/baremetal.h | $(BDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BDIR)/rtc.o: silx/x86/rtc.c silx/x86/rtc.h | $(BDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BDIR)/uart.o: silx/x86/uart.c silx/x86/include/uart.h | $(BDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BDIR)/serial.o: silx/x86/serial.c silx/x86/include/serial_dev.h | $(BDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BDIR)/io.o: silx/x86/io.c silx/x86/io.h | $(BDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BDIR)/setup.o: kernel/setup.c kernel/include/baremetal.h ui/demos/demo.h ui/ui.h gdb-stub/gdb_stub.h | $(BDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BDIR)/gdb_stub.o: gdb-stub/gdb_stub.c gdb-stub/gdb_stub.h | $(BDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BDIR)/gdb_io.o: gdb-stub/gdb_io.c gdb-stub/gdb_io.h | $(BDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BDIR)/gdb_idt.o: gdb-stub/gdb_idt.c gdb-stub/gdb_idt.h | $(BDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BDIR)/tramp.o: gdb-stub/tramp.asm | $(BDIR)
	$(AS) -f elf32 $< -o $@

$(BDIR)/console.o: kernel/console.c kernel/console.h kernel/include/baremetal.h | $(BDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BDIR)/ui.o: ui/ui.c ui/ui.h ui/font_8x16.h kernel/include/baremetal.h | $(BDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BDIR)/text.o: ui/text.c ui/ui.h ui/font_8x16.h kernel/console.h kernel/include/baremetal.h | $(BDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BDIR)/orbit.o: ui/demos/orbit.c ui/demos/demo.h kernel/include/baremetal.h | $(BDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BDIR)/progress.o: ui/demos/demo_progress.c ui/demos/demo.h ui/ui.h | $(BDIR)
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
	sg kvm -c "qemu-system-x86_64 -enable-kvm -m 2G -nographic -smp 2 -vga std -drive file=$$(pwd)/$(BDIR)/vm-raw.img,format=raw -net none"

run-curses: $(BDIR)/vm-raw.img
	sg kvm -c "qemu-system-x86_64 -enable-kvm -m 2G -display curses -smp 2 -vga std -drive file=$$(pwd)/$(BDIR)/vm-raw.img,format=raw -net none"

gdb-qemu: $(BDIR)/vm-raw.img $(BDIR)/kernel.elf
	@echo "=== GDB via QEMU ==="
	@echo "Run: gdb -x tests/gdb-qemu.gdb"
	@echo ""
	sg kvm -c "qemu-system-x86_64 -enable-kvm -m 2G -nographic -smp 2 -vga std -drive file=$$(pwd)/$(BDIR)/vm-raw.img,format=raw -net none -s -S"

gdb-test: $(BDIR)/vm-raw.img $(BDIR)/kernel.elf
	@echo "=== GDB via QEMU (automated test) ==="
	DIR=$(CURDIR) tests/gdb-qemu.sh

.PHONY: all run run-curses gdb-qemu gdb-stub-test clean debug

clean:
	rm -rf $(BDIR) kernel/*.o

debug:
	$(MAKE) CFLAGS="$(CFLAGS_DEBUG)" all
