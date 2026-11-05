    .intel_syntax noprefix
    .text
    .globl shim_entry32

shim_entry32:
    pushad
    call    delta_ref
delta_ref:
    pop     ecx
    sub     ecx, offset delta_ref
    mov     ebx, ebp
    mov     esi, WM_REG
    mov     edi, esp
    and     esp, -16
    sub     esp, 0x30
    lea     eax, [ecx + LDR_GETDLLHANDLE]
    mov     [esp+0x0C], eax
    lea     eax, [ecx + LDR_LOADDLL]
    mov     [esp+0x10], eax
    lea     eax, [ecx + NT_PROTECT]
    mov     [esp+0x14], eax
    lea     eax, [ecx + NT_OPENFILE]
    mov     [esp+0x18], eax
    lea     eax, [ecx + NT_READFILE]
    mov     [esp+0x1C], eax
    lea     eax, [ecx + NT_CLOSE]
    mov     [esp+0x20], eax
    mov     [esp+0x24], ecx
    lea     eax, [esp+0x0C]
    mov     [esp+0x00], eax
    mov     [esp+0x04], esi
    mov     [esp+0x08], ebx
    call    _detour_build_module32
    mov     esp, edi
    popad
    .byte   STOLEN_HEAD_BYTES
#if STOLE_BRANCH
    jnz     BM_SKIP
#endif
    jmp     BM_RESUME
