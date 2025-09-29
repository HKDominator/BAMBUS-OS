section .multiboot_header
header_start:
    ; first we need to put the MAGIC NUMBER
    dd 0xE85250D6

    ; need to specify details about the ARCHITECTURE
    dd 0 ; 32-bit protected mode of i386

    ;length of the header
    dd header_end - header_start

    ;32-bit unsigned value which, when added to the other magic fields (i.e. ‘magic’, ‘architecture’ and 
    ;‘header_length’), must have a 32-bit unsigned sum of zero
    dd 0x100000000 - (0xE85250D6 + 0 + ( header_end - header_start))

    ;flags
    dw 0
    dw 0
    dd 8
header_end: