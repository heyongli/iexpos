file build/kernel.elf
set architecture i386:x86-64
target remote localhost:1234
hbreak setup_main
continue
