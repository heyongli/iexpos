CC      = gcc
LD      = ld
AS      = nasm
CFLAGS  = -g -m32 -ffreestanding -fno-PIC -fno-asynchronous-unwind-tables -nostdlib -nostartfiles -I. -I bmX86 -I ui -I demos -I kernel -I kernel/include
LDFLAGS = -m elf_i386 -Ttext 0x7E00 -e entry --oformat binary -n
LDFLAGS_ELF = -m elf_i386 -Ttext 0x7E00 -e entry -n
BDIR    = build

OBJS = $(BDIR)/entry.o $(BDIR)/console.o $(BDIR)/ui.o $(BDIR)/rtc.o \
       $(BDIR)/setup.o $(BDIR)/vga.o $(BDIR)/orbit.o

all: $(BDIR)/vm-raw.img

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

$(BDIR)/setup.o: kernel/setup.c kernel/include/baremetal.h demos/demos.h | $(BDIR)
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
	cat $^ > $@

$(BDIR)/vm-raw.img: $(BDIR)/image.bin
	qemu-img create -f raw $@ 10M 2>/dev/null
	dd if=$< of=$@ conv=notrunc 2>/dev/null

run: $(BDIR)/vm-raw.img
	sg kvm -c "qemu-system-x86_64 -enable-kvm -m 2G -nographic -smp 2 -vga std -hda $$(pwd)/$(BDIR)/vm-raw.img -net none"

run-curses: $(BDIR)/vm-raw.img
	sg kvm -c "qemu-system-x86_64 -enable-kvm -m 2G -display curses -smp 2 -vga std -hda $$(pwd)/$(BDIR)/vm-raw.img -net none"

debug: $(BDIR)/vm-raw.img $(BDIR)/kernel.elf
	@echo "=== GDB debug ==="
	@echo "Run: gdb -x debug.gdb"
	@echo ""
	sg kvm -c "qemu-system-x86_64 -enable-kvm -m 2G -nographic -smp 2 -vga std -hda $$(pwd)/$(BDIR)/vm-raw.img -net none -s -S"

.PHONY: all run run-curses debug clean

clean:
	rm -rf $(BDIR)
