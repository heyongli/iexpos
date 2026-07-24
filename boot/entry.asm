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
    jmp 0x08:pm_start

[bits 32]
pm_start:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x7C00

    mov dx, 0x3F8
    mov al, 'P'
    out dx, al
    mov al, 'M'
    out dx, al
    mov al, 'O'
    out dx, al
    mov al, 'K'
    out dx, al
    mov al, 0x0A
    out dx, al

    call setup_main
    hlt

gdt:
    dq 0
gdt_code:
    dw 0xffff
    dw 0x0000
    db 0x00
    db 0x9a
    db 0xcf
    db 0x00
gdt_data:
    dw 0xffff
    dw 0x0000
    db 0x00
    db 0x92
    db 0xcf
    db 0x00
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt
