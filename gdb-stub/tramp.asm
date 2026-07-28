[BITS 32]
section .text

; ------------------------------------------------------------------
; IDT interrupt trampolines
;
; These trampolines are referenced directly by IDT gate entries.
; Each saves the full register context (matching struct regs layout
; in C) and forwards control to gdb_handler().
;
; CRITICAL: bp_remove_all() is called BEFORE gdb_handler() to remove
; ALL breakpoints (including any at gdb_handler's entry). This
; prevents reentrancy — the handler entry is guaranteed to be free
; of 0xCC. bp_insert_all() re-inserts breakpoints after the handler
; returns.
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
extern gdb_handler_depth
extern bp_remove_all
extern bp_insert_all

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
    inc dword [gdb_handler_depth]
    call bp_remove_all
    mov eax, esp
    push eax
    call gdb_handler
    add esp, 4
    call bp_insert_all
    dec dword [gdb_handler_depth]
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
    inc dword [gdb_handler_depth]
    call bp_remove_all
    mov eax, esp
    push eax
    call gdb_handler
    add esp, 4
    call bp_insert_all
    dec dword [gdb_handler_depth]
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
