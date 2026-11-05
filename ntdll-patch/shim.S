
    .intel_syntax noprefix
    .text
    .globl shim_entry3

shim_entry3:
    push    SCRATCH_REG
    mov     SCRATCH_REG, [rsp + (LOAD_PATH_SLOT + 8)]    
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    mov     r10, rsp
    and     rsp, -16
    sub     rsp, 0x60
    mov     [rsp+0x58], r10
    lea     rax, [rip + LDR_GETDLLHANDLE]
    mov     [rsp+0x38], rax
    lea     rax, [rip + LDR_LOADDLL]
    mov     [rsp+0x40], rax
    lea     rax, [rip + NT_PROTECT]
    mov     [rsp+0x48], rax
    lea     rcx, [rsp+0x38]
    mov     rdx, WM_REG
    mov     r8, SCRATCH_REG
    call    detour_build_module
    mov     rsp, [rsp+0x58]
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    pop     SCRATCH_REG
    .byte   STOLEN_BYTES
    jmp     BM_RESUME
