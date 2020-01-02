                ;; Keyboard

                KBD_FLAGS       EQU     0x17 ; 2 bytes of flags
                KEYBUF_HEAD     EQU     0x1A ; keyboard buffer in BIOS data area
                KEYBUF_TAIL     EQU     0x1C
                KEYBUF_START    EQU     0x80
                KEYBUF_TAIL     EQU     0x82
                
int_16:
                push    ds
                push    bx
                mov     bx, 0x40
                mov     ds, bx
                
                test    ah,ah
                jz      .wait_key       ; Func 0
                dec     ah
                jz      .key_status     ; Func 1
                dec     ah
                jz      .shift_status   ; Func 2
                dec     ah
                jz      .set_rate       ; Func 3
                dec     ah
                jz      .set_click      ; Func 4
                dec     ah
                jz      .write_key      ; Func 5
                sub     ah, 11
                jz      .wait_key       ; Func 0x10
                dec     ah
                jz      .key_status     ; Func 0x11
                dec     ah
                jz      .shift_status

.int_16_end:
                pop     bx
                pop     ds
                iret

.wait_key:
                mov     bx, [KEYBUF_HEAD]
                cmp     bx, [KEYBUF_TAIL]
                jne     .key_ready
                sti
                hlt                     ; wait for a keyboard IRQ
                cli
                jmp     .wait_key

.key_ready:
                mov     ax, [bx]
                add     bx, 2
                mov     [KEYBUF_HEAD], bx
                cmp     bx, [KEYBUF_END]
                jl      .int_16_end
                mov     bx, [KEYBUF_START]
                mov     [KEYBUF_HEAD], bx
                jmp     .int_16_end
                                
.key_status:
                xor     ax, ax
                mov     bx, [KEYBUF_HEAD]
                cmp     bx, [KEYBUF_TAIL]
                je      .no_data
                mov     ax, [bx]
.no_data:                
                test    ax, ax
                pop     bx
                pop     ds
                retf    2               ; preserve ZF 

.shift_status:
                mov     ax, [KBD_FLAGS]
                jmp     .int_16_end
                
.set_rate:
.set_click:
.write_key:
                mov     bx, [KEYBUF_TAIL]
                cmp     bx, [KEYBUF_HEAD]
                je      .int_16_end
                mov     [bx], cx
                add     bx, 2
                cmp     bx, [KEYBUF_END]
                jle     .no_tail_overflow
                mov     bx, [KEYBUF_START]
.no_tail_overflow:                
                mov     [KEYBUF_TAIL], bx
                jmp     .int_16_end
                
