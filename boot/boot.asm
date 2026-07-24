[org 0x7c00]
[bits 16]

    mov [boot_drive], dl

    mov si, dap
    mov ah, 0x42
    mov dl, [boot_drive]
    int 0x13
    jc disk_err

    jmp 0x7E00

disk_err:
    mov dx, 0x3F8
    mov al, 'E'
    out dx, al
    hlt
    jmp disk_err

dap:
    db 0x10, 0x00, 30, 0
    dw 0x7E00
    dw 0
    dd 1
    dd 0

boot_drive: db 0

times 510 - ($ - $$) db 0
dw 0xaa55
