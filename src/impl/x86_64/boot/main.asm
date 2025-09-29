global start
extern long_mode_start
extern kernel_main

section .text
bits 32

start:
    mov esp, stack_top

    ; the following code is required to check if our cpu supports long mode in order to switch to 64 bits
    call check_multiboot2; checks if we were loaded by a multiboot 2 loader
    call check_cpuid; provides cpu information
    call check_long_mode

    call set_up_page_tables
    call enable_paging

    lgdt [gdt64.pointer];loading the new GDT

    ; to this point the new GDT is loaded but we still can't use 64 bits expressions as the code selector register CS still has values from the old GDT

    jmp gdt64.code:long_mode_start; far jump

    ;print Ok on the screen
    ;mov dword [0xB8000], 0x2f4b2f4f; apparently this is the code for OK

check_multiboot2:
    ;the os is loaded by a multiboot 2 if the first zone of memory contains the magic number
    cmp eax, 0x36d76289
    jne .is_not_multiboot
    ret

.is_not_multiboot:
    mov al, "X" ; X for multiboot error
    jmp error

;LOOK AT OSDev (source code for check_cpuid)
check_cpuid:
    ;Check if CPUID is supported by attempting to flip the ID bit (bit 21)
    ; in the FLAGS register. If we can flip it, CPUID is available.
    pushfd
    pop eax

    ; Copy to ECX as well for comparing later on
    mov ecx, eax 

    ; Flip the ID bit
    xor eax, 1 << 21

    ; Copy EAX to EFLAGS via the stack
    push eax
    popfd

    ; Copy EFLAGS back to EAX ( with the flipped bit if CPUID is supported)
    pushfd
    pop eax

    ;Restore old EFLAGS from the older version stored in ecx 
    push ecx
    popfd

    ;Compare ECX and EAX. If they are equal then that the bit wasn't flipped, and CPUID is not supported.
    cmp eax, ecx
    je .no_cpuid
    ret

.no_cpuid:
    mov al, "C"; for not supporting CPUID
    jmp error


error:
;A screen character consists of a 8 bit color code and a 8 bit ASCII character. We used the color code 4f for all characters, 
;which means white text on red background. 0x52 is an ASCII R, 0x45 is an E, 0x3a is a :, and 0x20 is a space.
   ; little endian too
  
   ; Prints `ERR: ` and the given error code to screen and hangs.
   ; parameter: error code (in ascii) in al
    mov dword [0xB8000], 0x4f524f45
    mov dword [0xB8004], 0x4f3a4f52
    mov dword [0xB8008], 0x4f204f20
    mov byte [0xB800a], al
    hlt

;LOOK AT OSDev (source code for check_long_mode)
;the cpuid instruction implicitly uses the eax register as argument. To test if long mode is available, we need to call cpuid with 0x80000001 in eax. 
;This loads some information to the ecx and edx registers. Long mode is supported if the 29th bit in edx is set.
check_long_mode:
    ; test if the extended processor info is available
    mov eax, 0x80000000    ; implicit argument for cpuid
    cpuid                  ; get highest supported argument 
    cmp eax, 0x80000001    ; it needs to be at least 
    jb .no_long_mode       ; if it's less, the CPU is too old for long mode

    ; use extended info to test if long mode is available
    mov eax, 0x80000001    ; argument for extended processor info
    cpuid                  ; returns various feature bits in ecx and edx
    test edx, 1 << 29      ; test if the LM-bit is set in the D-register
    jz .no_long_mode       ; If it's not set, there is no long mode
    ret

.no_long_mode:
    mov al, "L"; no supporting long mode
    jmp error

set_up_page_tables:
    ; map first P4 entry to P3 table
    mov eax, p3_table
    or eax, 0b11           ; present in memory now + writable
    mov [p4_table], eax

    ; map first P3 entry to P2 table
    mov eax, p2_table
    or eax, 0b11           ; same present and writable
    mov [p3_table], eax

    ; map each P2 entry to a huge 2MiB page
    mov ecx, 0 ;           ; counting variable
    .map_p2_table: 
        ; map ecx-th P2 entry to a huge page that starts at address 2MiB*ecx
        mov eax, 0x200000  ; 2MiB
        mul ecx
        or eax, 0b10000011     ; present + writable + huge page
        mov [p2_table + ecx * 8 ], eax; map each ecx-th entry

        inc ecx            ; increase the counter
        cmp ecx, 512       ; if ecx == 512 the whole P2 table is mapped
        jne .map_p2_table  ; if not, there are still entries to be mapped

    ret

enable_paging:
    ; load P4 to CR3 register ( cpu uses this to access the P4 table)
    ; CR3 register deals with paging has 32 bits
    mov eax, p4_table
    mov cr3, eax

    ;long mode is an extension of Physical Address Extension (PAE) so we need to enable PAE first in cr4
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax

     ; set the long mode bit in the EFER MSR (model specific register)
    mov ecx, 0xC0000080
    rdmsr                  ; Reads the contents of a 64-bit model specific register (MSR) specified in the ECX register into registers EDX:EAX.
    or eax, 1 << 8
    wrmsr                  ; Writes the contents of registers EDX:EAX into the 64-bit model specific register (MSR) specified in the ECX register.

    ; enable paging in the cr0 register
    mov eax, cr0
    or eax, 1 << 31
    mov cr0, eax

    ret

section .bss; staticly allocated variables
;in order to switch to 64 bits, we have to also introduce paging. There are 4 types of pages: 
;Page-Map Level-4 Table (PML4) -> P4
;Page-Directory Pointer Table (PDP) -> P3
;Page-Directory Table (PD) -> P2
;Page Table (PT) -> P1
align 4096      ; assures that the pages are align 
p4_table:
    resb 4096
p3_table:
    resb 4096
p2_table:
    resb 4096
stack_bottom:
    ;allocate 64 bytes of memory for the stack
    resb 64
stack_top:

section .rodata
; we have to create a new Global Data Table such that we can use the 64 bits instruction. Even though Grub offers us a 32 GDT, we have to create a new one;
; A gdt starts with a 0 entry !!
gdt64:
    dq 0 ; zero entry
.code: equ $- gdt64; to calculate the offset from the gdt
    dq ( 1 << 43 ) | ( 1 << 44 ) | (1 << 47) | (1 << 53); code segment
.pointer: ;labels that start with a . are sub-labels of the last label without point. To access -> gdt64.pointer
    dw $ - gdt64 - 1
    dq gdt64

