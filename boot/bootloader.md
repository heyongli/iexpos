# Boot Stage — `boot/`

## Overview

A 512-byte x86 boot sector (`boot.asm`) + 16→32-bit PM switch stub (`entry.asm`) that:
1. Loads kernel from disk via INT 13h LBA
2. Switches to protected mode (flat 4 GiB segments)
3. Jumps to kernel entry at `0x7E00`

**Current design:** Kernel is a raw binary linked at `0x7E00` (no ELF parsing in boot stage).

---

## Current Implementation

### Execution Flow

```
BIOS → boot/boot.asm (INT 13h, load sectors to 0x7E00)
     → boot/entry.asm (16→32-bit, LGDT/CR0.PE=1, far jump)
     → kernel/setup.c (C init + main loop)
```

### 1. `boot/boot.asm` — MBR (512 bytes, org 0x7C00)

```asm
[org 0x7c00]
[bits 16]

mov [boot_drive], dl          ; BIOS passes boot drive in DL

; Read kernel via INT 13h AH=0x42 (extended LBA)
mov si, dap
mov ah, 0x42
mov dl, [boot_drive]
int 0x13
jc disk_err

jmp 0x7E00                    ; jump to entry.asm (linked at 0x7E00)
```

**Disk Address Packet (DAP):**
```asm
dap:
    db 0x10, 0x00, 0, 0       ; packet size, reserved, sector count (patched), reserved
    dw 0x7E00, 0              ; buffer offset:segment = 0x0000:0x7E00
    dd 1, 0                   ; LBA start = sector 1 (after MBR)
```

Sector count is patched at build time by Makefile:
```makefile
KERNEL_SECTORS=$$((($$(stat -c%s $(BDIR)/kernel.bin) + 511) / 512))
printf '\\x'"$$(printf '%02x' "$$KERNEL_SECTORS")" | \
    dd of=$(BDIR)/boot.bin bs=1 seek=31 count=1 conv=notrunc
```

### 2. `boot/entry.asm` — PM Switch Stub (linked at 0x7E00)

```asm
[bits 16]
section .text
global entry
extern setup_main

entry:
    cli
    lgdt [gdt_desc]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp 0x08:pm_start         ; far jump to flush prefetch

[bits 32]
pm_start:
    mov ax, 0x10
    mov ds, ax; mov es, ax; mov fs, ax; mov gs, ax; mov ss, ax
    mov esp, 0x7C00           ; stack grows down from 0x7C00
    call setup_main           ; enter C
    hlt
```

**GDT (flat 4 GiB, ring 0):**
| Label | Selector | Base | Limit | Type |
|-------|----------|------|-------|------|
| null  | 0x00     | —    | —     | —    |
| code  | 0x08     | 0    | 4 GiB | exec/read |
| data  | 0x10     | 0    | 4 GiB | read/write |

---

## Known Gotchas

| Issue | Symptom | Fix |
|-------|---------|-----|
| Writing to 0x5FC (BDA) | INT 13h disk reads fail | Never write 0x400–0x5FF |
| GDT descriptor packing | `dw 0xffff,0x0000,0x00,0x9a,0xcf,0x00` corrupts descriptor | Use explicit `dw`/`db` per byte |
| Stack at 0x7C00 | Overwrites MBR if kernel grows | Dedicated stack in bootC (TODO) |
| No VBE/fb_info passed | Kernel must re-detect or assume | bootC will populate `boot_info_t` (TODO) |

---

## Memory Map (Current)

```
0x000000 – 0x0003FF  IVT
0x000400 – 0x0004FF  BDA
0x000500 – 0x0005FF  BIOS data
0x000600 – 0x00060B  fb_info (legacy, written by boot.asm — currently unused)
0x007C00 – 0x007DFF  boot sector (stack at 0x7C00)
0x007E00 – ~0x080000 kernel (raw binary, linked at 0x7E00)
0x0A0000 – 0x0AFFFF  VGA legacy framebuffer (13h fallback)
```

---

## Build Integration (Makefile)

```makefile
# boot.asm → boot.bin (512 bytes)
$(BDIR)/boot.bin: boot/boot.asm | $(BDIR)
	$(AS) -f bin -o $@ $<

# entry.asm → entry.o (ELF, linked into kernel)
$(BDIR)/entry.o: boot/entry.asm | $(BDIR)
	$(AS) -f elf32 -o $@ $<

# kernel.bin = entry.o + all C objs, linked as raw binary at 0x7E00
$(BDIR)/kernel.bin: $(OBJS) $(BDIR)/entry.o
	$(LD) $(LDFLAGS) $^ -o $@
	# LDFLAGS = -m elf_i386 -Ttext 0x7E00 -e entry --oformat binary -n

# image.bin = boot.bin + kernel.bin (concatenated)
$(BDIR)/image.bin: $(BDIR)/boot.bin $(BDIR)/kernel.bin
	tools/patch-boot-sectors $< $^
	cat $< $^ > $@
```

---

## Migration Plan: bootC (ELF Loader in C)

### What is bootC?

**bootC** is a **minimal, self-contained ELF loader written in C** that runs in 32-bit protected mode (flat memory model). It replaces the assembly-only stage2 (`entry.asm`) and takes over all responsibilities of loading, relocating, and passing control to the kernel.

#### Design Philosophy: Kernel Self-Bootstrap

| Principle | Description |
|-----------|-------------|
| **Zero parameter passing** | BootC does **not** construct or pass any `boot_info_t`. It loads the ELF, applies relocations, and `jmp e_entry`. |
| **Kernel owns all hardware detection** | Kernel entry `_start` (asm) → saves `DL` (boot drive) → sets up own stack → calls `main()`. `main()` queries **everything itself** via BIOS: E820, VBE, ACPI, PCI. |
| **Only standard BIOS interface** | `DL` at MBR entry is the **only standard, reliable way** to get boot drive. BootC preserves `DL` through to `_start`; kernel decides whether to save/use it. No BDA, no EDD, no multiboot. |
| **Single responsibility** | BootC = ELF load + relocate + jump. Nothing else. |

#### Component Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ boot.asm (stage1, 512B, 16-bit real mode)                      │
│   • BIOS INT 13h LBA read                                       │
│   • Loads stage2.bin + kernel.elf to high memory (e.g. 0x200000)│
│   • Switches to PM (GDT, CR0.PE=1)                              │
│   • Far jump to stage2_entry  (DL preserved in register)       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ stage2.asm (stage2_entry, 32-bit flat, minimal asm)            │
│   • Sets up dedicated stack (not overlapping MBR)               │
│   • Zeroes .bss                                                  │
│   • Calls bootc_load(kernel_elf_addr, target_base)              │
│   • Receives kernel entry point in EAX                          │
│   • JMP EAX  →  kernel _start  (DL still in register)           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ bootc.c (core loader, pure C, runs in PM)                      │
│                                                                 │
│   uint32_t bootc_load(void *kernel_elf, uint32_t target_base)  │
│   {                                                             │
│       // 1. Validate ELF header (magic, class, endian, arch)   │
│       // 2. Parse Program Headers (PT_LOAD)                    │
│       // 3. Compute load addresses:                            │
│       //    dst = target_base + (p_vaddr - link_base)          │
│       // 4. Bump allocator for physical memory (1MB+)          │
│       // 5. memcpy each segment (filesz), memset BSS (memsz)   │
│       // 6. Find .rela.dyn section, apply relocations:         │
│       //       R_386_32       → *where += delta                │
│       //       R_386_RELATIVE → *where += delta                │
│       // 7. Return kernel entry: e_entry + delta              │
│   }                                                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ _start (kernel/start.asm) — ELF e_entry                        │
│   • cli                                                         │
│   • mov [boot_drive], dl      ; preserve boot drive (only if   │
│                               ; kernel needs INT 13h later)    │
│   • mov esp, KERNEL_STACK_TOP ; own stack, not boot's          │
│   • call main                ; standard cdecl, no arguments   │
│   • cli; hlt                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ main(void) — pure C, zero arguments                           │
│   • e820_query()       → build memory map                      │
│   • vbe_query/set()    → set mode, map framebuffer             │
│   • acpi_find_rsdp()   → parse ACPI tables                     │
│   • bm_init()          → initialize subsystems                 │
│   • ui_init() / gdb_stub_init() / cli_init()                   │
│   • main loop                                                   │
└─────────────────────────────────────────────────────────────────┘
```

#### Key Interfaces

**1. Kernel Entry Contract (ELF `e_entry` = `_start`)**
```asm
; kernel/start.asm
[bits 32]
[global _start]
[extern main]

_start:
    cli
    mov [boot_drive], dl       ; optional: only if kernel uses INT 13h later
    mov esp, KERNEL_STACK_TOP  ; e.g. 0x90000 (below 1MB, safe)
    call main                 ; cdecl, no args
    cli; hlt
```

**2. `main(void)` — Zero Arguments**
```c
// kernel/main.c
void main(void) {
    // All hardware detection done HERE, not in boot
    e820_entry_t mmap[32];
    int mmap_n = e820_query(mmap);
    
    vbe_info_t vbe;
    vbe_query(&vbe);
    vbe_set_mode(1024, 768, 32);
    fb_map(vbe.phys_addr, vbe.pitch, 1024, 768, 32);
    
    acpi_rsdp_t *rsdp = acpi_find_rsdp();
    
    bm_init();
    ui_init();
    gdb_stub_init();
    cli_init();
    while (1) { ... }
}
```

#### What bootC Does NOT Do

| Excluded | Reason |
|----------|--------|
| Construct/pass `boot_info_t` | Kernel queries BIOS directly |
| E820 memory map | `INT 15h AX=E820` available in PM |
| VBE mode setting / framebuffer | Kernel calls `INT 10h AX=4F01/4F02` itself |
| ACPI RSDP search | Kernel scans EBDA/BIOS area in PM |
| Device drivers | Zero hardware init beyond BIOS calls |
| Decompression | Kernel is uncompressed ELF; add LZ4 later if needed |
| Multiboot protocol | Own minimal contract; multiboot shim optional later |

#### Boot Drive (`DL`) — The Only Standard Interface

- BIOS places boot drive number in `DL` when jumping to MBR (`0x7C00`).
- **No other standard, reliable way exists** to retrieve it later (BDA is unreliable, EDD requires drive number as input).
- BootC preserves `DL` through stage1 → stage2 → `_start`.
- Kernel `_start` saves it to a global **only if** it plans to use `INT 13h` later (modules, initrd, chainload). Otherwise ignored.

#### Migration Impact on Other Components

| Component | Change |
|-----------|--------|
| `kernel/setup.c` | Remove `setup_main(void)`; add `main(void)` in `main.c` |
| `kernel/start.asm` (new) | Assembly entry (any name, e.g. `_start`), saves `dl`, sets stack, calls `main` |
| `kernel/link.ld` (new) | `ENTRY(entry_symbol)` — defines `e_entry` |
| `kernel/include/baremetal.h` | Add `main` prototype; remove `setup_main` |
| `silx/x86/vga.c` | Keep VBE query/set; called from `main`, not boot |
| `silx/x86/e820.c` (new) | `e820_query()` using `INT 15h AX=E820` |
| `silx/x86/acpi.c` (new) | `acpi_find_rsdp()` scanning EBDA/BIOS area |
| `Makefile` | New targets: `stage2.bin`, `stage2.o`, `start.o`; kernel linked at `0x100000` with `--emit-relocs`; `image.bin` = boot.bin + stage2.bin + kernel.elf |
| `tools/patch-boot-sectors` | Removed (sector count computed at build for combined stage2+kernel) |

---

### TODO — BootC Implementation

- [ ] Change kernel link address to `0x100000` (1 MB, above ISA hole)
- [ ] Add `--emit-relocs -z norelro` to keep `.rela.dyn`
- [ ] Linker script declares `ENTRY(symbol)` — any symbol name works, ELF `e_entry` is the contract
- [ ] Create `kernel/start.asm` (assembly entry, saves `dl`, sets stack, calls `main`)
- [ ] Create `kernel/main.c` (zero args, all hardware detection here)
- [ ] Create `silx/x86/e820.c` — `e820_query()` via `INT 15h AX=E820`
- [ ] Create `silx/x86/acpi.c` — `acpi_find_rsdp()` scanning EBDA/BIOS
- [ ] Write `boot/stage2.asm` — 32-bit PM entry, sets stack, calls `bootc_load`, jumps to `e_entry`
- [ ] Write `boot/bootc.c` — ELF parser, PT_LOAD loader, `.rela.dyn` relocator
- [ ] Update `Makefile` — targets: `stage2.bin`, `stage2.o`, `start.o`; kernel at `0x100000` with relocations
- [ ] `image.bin` = `boot.bin` + `stage2.bin` + `kernel.elf` (concatenated)
- [ ] Remove `tools/patch-boot-sectors` (sector count at build for combined stage2+kernel)
- [ ] `tests/boot.sh` — verify boot completes
- [ ] `tests/check_bss.sh` — verify BSS < 0xA0000
- [ ] Relocation test — boot at different `target_base` (KASLR prep)

---

## References
- System V ABI i386 — cdecl calling convention
- `meta/io.h` — IO semantics
- `docs/bare-metal-interface.md` — kernel platform API
- `boot/boot.asm`, `boot/entry.asm` — current implementation