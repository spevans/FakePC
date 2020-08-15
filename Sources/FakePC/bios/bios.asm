;;;
;;; bios.asm
;;;
;;; Created by Simon Evans on 07/12/2020.
;;;

                %macro OFFSET 1
                    times %1 - ($ - $$)   db 0x00
                %endmacro

                ;; 8K BIOS Located at FE000, entry point at FFFF:0000 at end

                BIOS_SEGMENT    EQU     0xF000
                BIOS_OFFSET     EQU     0xE000

                ORG     BIOS_OFFSET      ; F000:E000  => FE000

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

                ;; set Video Mode 7 (MDA 80x25) ;; TODO determine why it fails if this is moved to after setup_pit
                mov     al, 7
                int     0x10

                call    setup_pic
                call    setup_pit
                sti
                ;; Boot the system
                int     0x19


%include "Sources/FakePC/bios/video.asm"


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

%include "Sources/FakePC/bios/keyboard.asm"
%include "Sources/FakePC/bios/irq.asm"

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


                ;; Time of day - handle functions 0 & 1 directly, pass the others to the HV
int_1ah:        test    ah, ah
                jnz     int_1a_func1
                push    ds
                xor     dx, dx
                mov     ds, dx
                mov     dx, [0x46C]         ; CX:DX number of clock ticks since midnight
                mov     cx, [0x46E]
                mov     al, byte [0x470]    ; Midnight flag
                pop     ds
                iret

int_1a_func1:   cmp     ah, 1
                jnz     int_1a_others
                push    ds
                xor     ax, ax
                mov     ds, ax
                mov     [0x46E], cx
                mov     [0x46C], dx
                mov     byte [0x470], 0
                pop     ds
                iret

int_1a_others:  out 0xE8, ax
                retf    2

                ;; Next 2 interrupts are dummy handlers that are hooked by other programs.
int_1bh:        ;; KEYBOARD - CONTROL-BREAK HANDLER
int_1ch:        ;; TIME - SYSTEM TIMER TICK
dummy_vector:
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

int_1eh:        OFFSET  0x0FC7  ; F000h:EFC7h SYSTEM DATA - DISKETTE PARAMETERS
                db      0       ; first specify byte
                db      1       ; second specify byte
                db      1       ; delay until motor turned off in clock ticks
                db      2       ; Bytes per sector (00h = 128, 01h = 256, 02h = 512, 03h = 1024)
                db      21      ; sectors per track (maximum if different for different tracks)
                db      0x1b    ; length of gap between sectors (2Ah for 5.25", 1Bh for 3.5")
                db      0       ; data length (ignored if bytes-per-sector field nonzero)
                db      0x6c    ; gap length when formatting (50h for 5.25", 6Ch for 3.5")
                db      0xf6    ; format filler byte (default F6h)
                db      1       ; motor start time in 1/8 seconds

int_1dh:        OFFSET  0x10A4  ; F000h:F0A4h INT 1D - SYSTEM DATA - VIDEO PARAMETER TABLES

int_1fh:        OFFSET  0x1A6E  ; F000h:FA6Eh INT 1F - SYSTEM DATA - 8x8 GRAPHICS FONT


msg_no_basic:   db      "No BASIC ROM Installed", 0x0A, 0x0D, 0


                ALIGN   2
vectors:        ;; Starting interrupt, vector count, vectors
                dw      0x08, 2
                dw      irq_0,
                dw      irq_1,
                dw      0x10, 16
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
                dw      int_1bh,
                dw      int_1ch,
                dw      int_1dh,
                dw      int_1eh,
                dw      int_1fh,
                dw      0x0, 0

                ;; 8086 Startup at FFFF:0000 => FFFF0
                ;; BIOS Loaded at 0xFF000
                OFFSET  8192 - 16
                jmp     BIOS_SEGMENT:BIOS_OFFSET

                db      "12/27/19", 0
                db      0xFC
                db      0
                OFFSET  8192
