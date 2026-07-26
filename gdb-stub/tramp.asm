[BITS 32]
section .text

; ------------------------------------------------------------------
; IDT interrupt trampolines
;
; These trampolines are referenced directly by IDT gate entries.
; Each saves the full register context (matching struct regs layout
; in C) and forwards control to gdb_handler().
;
; Stack layout after CPU interrupt (low address → high):
;   pusha  → EDI, ESI, EBP, _ESP, EBX, EDX, ECX, EAX   (32 bytes)
;   manual → SS, GS, FS, ES, DS                         (20 bytes)
;   CPU    → EIP, CS, EFLAGS                            (12 bytes)
;
; _ESP is the value of ESP at the time of pusha, NOT the
; stack pointer at the moment the exception occurred.
; ------------------------------------------------------------------

extern gdb_handler

; ---- INT1 (single-step / debug exception) ----------------------------
; Raised when EFLAGS.TF = 1 after each instruction.
; The C handler distinguishes INT1 from INT3 via gdb_from_poll.
global int1_tramp
int1_tramp:
    pusha
    push ss
    push gs
    push fs
    push es
    push ds
    mov eax, esp
    push eax
    call gdb_handler
    add esp, 4
    pop ds
    pop es
    pop fs
    pop gs
    pop ss
    popa
    iret

; ---- INT3 (breakpoint exception) ------------------------------------
; Triggered by the 0xCC instruction.  Same save/restore sequence
; as INT1; the C handler adjusts EIP based on the source.
global int3_tramp
int3_tramp:
    pusha
    push ss
    push gs
    push fs
    push es
    push ds
    mov eax, esp
    push eax
    call gdb_handler
    add esp, 4
    pop ds
    pop es
    pop fs
    pop gs
    pop ss
    popa
    iret

; ---- default handler (catch-all placeholder) ------------------------
; All 256 IDT entries are initially set to this stub.
; Unhandled interrupts are silently ignored.
global default_tramp
default_tramp:
    iret
