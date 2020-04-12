;;;
;;; irq.asm
;;;
;;; Created by Simon Evans on 02/01/2020.
;;;

                ;; PIC IO Ports
                PIC1_CMD_REG    EQU 0x20
                PIC1_DATA_REG   EQU 0x21
                PIC2_CMD_REG    EQU 0xA0
                PIC2_DATA_REG   EQU 0xA1

                ;; 8259 Commands
                ICW1_ICW4       EQU 0x01    ; ICW1/ICW4
                ICW1_SINGLE     EQU 0x02    ; Single (cascade) mode
                ICW1_INTERVAL4  EQU 0x04    ; Call address interval 4 (8)
                ICW1_LEVEL      EQU 0x08    ; Level triggered (edge) mode
                ICW1_INIT       EQU 0x10    ; Initialization

                ICW4_8086       EQU 0x01    ; 8086/88 (MCS-80/85) mode
                ICW4_AUTO       EQU 0x02    ; Auto (normal) EOI
                ICW4_BUF_SLAVE  EQU 0x08    ; Buffered mode/slave
                ICW4_BUF_MASTER EQU 0x0C    ; Buffered mode/master
                ICW4_SFNM       EQU 0x10    ; Special fully nested (not)

                OCW3_READ_IRR   EQU 0x0A    ; OCW3 IRR read
                OCW3_READ_ISR   EQU 0x0B    ; OCW3 ISR read
                EOI             EQU 0x20    ; End of interrupt
                SPECIFIC_EOI    EQU 0x60    ; Specific IRQ (+ irq)
                CASCADE_IRQ     EQU 0x02    ; PIC2 is at IRQ2 on PIC1


                ;; Clock tick interrupt
irq_0:
                push    ds
                push    eax
;                mov     ax, 1
;                out     0xef, ax       ; Debug call
                xor     ax, ax
                mov     ds, ax
                mov     eax, [0x46C]
                inc     eax
                cmp     eax, 1572480    ; 24 hours * 3600 seconds * 18.2 ticks/second
                jl      .not_midnight
                xor     eax, eax
                mov     byte [0x470], 1  ; 'Midnight' flag signals 24 hours have passed since start
.not_midnight:
                mov     [0x46C], eax
                int     0x1c
                mov     al, EOI
                out     PIC1_CMD_REG, al
;                mov     ax, 2
;                out     0xef, ax       ; Debug call

                pop     eax
                pop     ds
                iret

                ;; Keyboard IRQ - The swift code will update the keybaard
                ;; buffer, this IRQ is just here to allow the IRQ to be triggered
                ;; to wake up from HLT or allow anything hooking it to be called.
irq_1:
                push    ax
                mov     al, EOI
                out     PIC1_CMD_REG, al        ; ACK EOI
                pop     ax
                iret


                ;; Setup the PICs
setup_pic:
                ;; mask (disable) IRQs
                cli
                mov     al, 0xff
                out     PIC1_DATA_REG, al
                out     PIC2_DATA_REG, al

                ;; Map IRQ0-7 -> INT08H-0FH and IRQ8-15 -> INT70H-77H
                mov     al, ICW1_ICW4 | ICW1_INIT
                out     PIC1_CMD_REG, al
                mov     al, 0x8
                out     PIC1_DATA_REG, al
                mov     al, 1 << CASCADE_IRQ
                out     PIC1_DATA_REG, al
                mov     al, ICW4_8086
                out     PIC1_DATA_REG, al

                mov     al, ICW1_ICW4 | ICW1_INIT
                out     PIC2_CMD_REG, al
                mov     al, 0x70
                out     PIC2_DATA_REG, al
                mov     al, CASCADE_IRQ
                out     PIC2_DATA_REG, al
                mov     al, ICW4_8086
                out     PIC2_DATA_REG, al
;;;                 mov     cl, 1   ; ;;enable keyboard irq
        ;;                 call    enable_irq
                ret

                ;; Enable IRQ in CL
enable_irq:
                cmp     cl, 16
                jge     bad_irq
                cmp     cl, 7
                jg      .enable_pic2_irq
                in      al, PIC1_DATA_REG
                mov     ah, 1
                shl     ah, cl
                not     ah
                and     al, ah
                out     PIC1_DATA_REG, al
                jmp     irq_done

.enable_pic2_irq:
                in      al, PIC2_DATA_REG
                sub     cl, 7
                mov     ah, 1
                shl     ah, cl
                not     ah
                and     al, ah
                out     PIC2_DATA_REG, al
                jmp     irq_done

                ;; Disable IRQ in CL
disable_irq:
                cmp     cl, 16
                jge     bad_irq
                cmp     cl, 7
                jg      .disable_pic2_irq
                in      al, PIC1_DATA_REG
                mov     ah, 1
                shl     ah, cl
                or      al, ah
                out     PIC1_DATA_REG, al
                jmp     irq_done

.disable_pic2_irq:
                in      al, PIC2_DATA_REG
                sub     cl, 7
                mov     ah, 1
                shl     ah, cl
                or      al, ah
                out     PIC2_DATA_REG, al
irq_done:
                clc
                ret

bad_irq:
                stc
                ret


setup_pit:
        ;;                                 out     0xe3, ax

                mov     al, 0 | 0b00110000 | 0b00000110 | 0b00000000
                out     0x43, al
                mov     al, 0xff
                out     0x40, al
                out     0x40, al
                mov     cl, 0
                call    enable_irq
                ret
