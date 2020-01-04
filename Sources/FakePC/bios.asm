;;;
;;; bios.asm
;;;
;;; Created by Simon Evans on 07/12/2020.
;;;

                %macro OFFSET 1
                    times %1 - ($ - $$)   db 0x90
                %endmacro

                ;; 4K BIOS Located at FF000, entry point at FFFF:0000 at end

                BIOS_SEG    EQU     0xF000


                ORG     0xF000          ; F000:F000  => FF000

biosinit:
                cli
                cld
                mov     ax, 0
                mov     ss, ax
                mov     sp, 0x800       ; Stack at 0x800
                mov     es, ax
                mov     di, ax          ; ES:DI => interrupt table @ 0000:0000

                mov     bx, 0xf000
                mov     ds, bx
                mov     dx, dummy_vector
                mov     cx, 256

idt_loop:
                mov     ax, dx
                stosw
                mov     ax, bx
                stosw
                loop    idt_loop

                ;; Setup individual INT handlers
                ;; The Segment is alreay set, just patch in the offset
                mov     si, vectors
set_vectors:
                lodsw                   ; starting interrupt
                mov     di, ax
                shl     di, 2
                lodsw                   ; count of vectors - 0 if nothing more to do
                test    ax, ax          
                jz      set_vector_end
                mov     cx, ax          

set_vector:
                lodsw                   ; vector IP
                stosw                   ; ES:DI => IP
                add     di, 2           ; skip next interrupt's segment
                loop    set_vector
                jmp     set_vectors

set_vector_end:                
                ;; Setup BDA - BIOS Data Area
                mov     ax, 1
                out     0xe6, ax

                call    setup_pic
        ;;                 call    setup_pit
                sti
                ;; Boot the system
                int     0x19


dummy_vector:
                iret

                ;; Video
int_10h:
                out     0xE0, ax
                iret

                ;; Equipment List
int_11h:
                push    ds
                xor     ax, ax
                mov     ds ,ax
                mov     ax, [0x410]
                pop     ds
                iret

                ;; Memory size
int_12h:
                push    ds
                xor     ax, ax
                mov     ds, ax
                mov     ax, [0x413]
                pop     ds
                iret


                ;; Disk IO
int_13h:
                out     0xe1, ax
                retf    2               ; preserve carry flag

                ;; Serial Ports
int_14h:
                out     0xe2, AX
                iret

                ;; System Services
int_15h:
                out     0xe3, ax
                retf    2               ; preserve CF

%include "Sources/FakePC/keyboard.asm"
%include "Sources/FakePC/irq.asm"
                
                ;; Printer
int_17h:
                out     0xe5, ax
                iret

                ;; 18h Basic / Boot Failure
int_18h:
                cld
                mov     si, msg_no_basic
                call    print
                cli
                hlt


                ;; Reboot / Startup
int_19h:
                mov     ax, 0x0201
                mov     cx, 0x0001      ; Track 0 Sector 1
                mov     dx, 0x0000      ; Drive 0 (A:) Head 0
                mov     bx, 0x7C0
                mov     es, bx
                mov     bx, dx          ; ES:BX => 0x7C00
                int     0x13
                jnc     loaded_ok

                ;; Try the hard drive
                mov     ax, 0x0201
                mov     dl, 0x80
                int     0x13
                jnc     loaded_ok
                int     0x18            ; Fall back to ROM

loaded_ok:
                jmp     0x0:0x7C00


                ;; Time of day
int_1ah:
                iret

print:          ;; DS:SI => ASCIIZ string
                lodsb
                test    al,al
                je      .end
                mov     ah, 0x0e
                int     0x10
                jmp     print
.end:
                ret

;; DATA

msg_no_basic:   db      "No BASIC ROM Installed", 0x0A, 0x0D, 0


                ALIGN   2
vectors:        ;; Starting interrupt, vector count, vectors
                dw      0x08, 2
                dw      irq_0,
                dw      irq_1,
                dw      0x10, 11
                dw      int_10h
                dw      int_11h,
                dw      int_12h,
                dw      int_13h,
                dw      int_14h,
                dw      int_15h,
                dw      int_16h,
                dw      int_17h,
                dw      int_18h,
                dw      int_19h,
                dw      int_1ah,
                dw      0x0, 0

                ;; 8086 Startup at FFFF:0000 => FFFF0
                ;; BIOS Loaded at 0xFF000
                times   4080 - ($-$$) db 0
                jmp     0xF000:0xF000

                db      "12/27/19", 0
                db      0xFC
                db      0
                OFFSET  4096
