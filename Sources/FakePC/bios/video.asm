;;;
;;; video.asm
;;;
;;; Created by Simon Evans on 14/04/2020.
;;;
;;; Video BIOS


                ;; Video
int_10h:
                cmp     ah, 0x13
                jg     .int_10_invalid
.int_10_funcs:
                push    si
                mov     si, ax
                and     si, 0xff00
                shr     si, 7
                add     si, .int_10_table
                call    [cs:si]
                pop     si
.int_10_invalid:
                iret
.int_10_table:
                dw      .set_video_mode                 ; Func 00
                dw      .set_txt_mode_cursor            ; Func 01
                dw      .set_cursor_position            ; Func 02
                dw      .get_cursor                     ; Func 03
                dw      .read_light_pen                 ; Func 04
                dw      .set_active_page                ; Func 05
                dw      .scroll_up                      ; Func 06
                dw      .scroll_down                    ; Func 07
                dw      .read_character_at_cursor       ; Func 08
                dw      .write_character_at_cursor      ; Func 09
                dw      .write_char_only_at_cursor      ; Func 0A
                dw      .set_background_colour          ; Func 0B
                dw      .write_pixel                    ; Func 0C
                dw      .read_pixel                     ; Func 0D
                dw      .tty_output                     ; Func 0E
                dw      .get_video_mode                 ; Func 0F
                dw      .palette_register_control       ; Func 10
                dw      .character_generator_control    ; Func 11
                dw      .video_subsystem_control        ; Func 12
                dw      .write_string                   ; Func 13



;;; AH=00h
.set_video_mode:
                out     0xE0, ax
                ret

;;; AH=01h CH = cursor starting scan line (cursor top) (low order 5 bits)
;;;        CL = cursor ending scan line (cursor bottom) (low order 5 bits)
.set_txt_mode_cursor:
                out     0xE0, ax
                push    ds
                push    dx
                mov     dx, 0x40
                mov     ds, dx
                mov     [0x60], cx      ; BDA cursor shape
                pop     dx
                pop     ds
                ret

;;; AH=02h BH = page number (0 for graphics modes) DH = row DL = column
.set_cursor_position:
                call    .valid_video_page
                jc      .set_cursor_position_end
                push    ds
                push    cx
                mov     cx, 0x40
                mov     ds, cx
                mov     cx, bx
                mov     bl, bh
                xor     bh, bh
                shl     bl, 1
                mov     [0x50 + bx], dx
                mov     bx, cx
                pop     cx
                pop     ds
.set_cursor_position_end:
                ret


;;; AH=03h BH=page
.get_cursor:
                push    ds
                mov     dx, 0x40        ; BDA
                mov     ds, dx
                mov     cx, bx
                mov     bl, bh
                xor     bh, bh
                shl     bl, 1
                mov     dx, [0x50 + bx] ; cursor position for page 0 + bh
                mov     bx, cx
                mov     cx, [0x60]      ; cursor shape
                pop     ds
                clc
                ret

;;; AH=04h - Ignore as no light pen present
.read_light_pen:
                mov     ah, 0   ; Not triggered
                mov     bx, 0   ; pixel column
                mov     cx, 0   ; raster line
                mov     dx, 0   ; dh=row dl=column
                ret

;;; AH=05h AL=page
.set_active_page:
                push    bx
                mov     bh, al
                call    .valid_video_page
                jc      .set_active_page_end
                push    ds
                mov     bx, 0x40
                mov     ds, bx
                mov     [0x62], al      ; BDA active page
                pop     ds
                out     0xE0, ax        ; Get the external display to update
.set_active_page_end:
                pop     bx
                ret


;;; AH=06h
.scroll_up:
                out     0xE0, ax
                ret


;;; AH=07h
.scroll_down:
                out     0xE0, ax
                ret


;;; AH=08h
.read_character_at_cursor:
                out     0xE0, ax
                ret


;;; AH=09h
.write_character_at_cursor:
                out     0xE0, ax
                ret


;;; AH=0Ah
.write_char_only_at_cursor:
                out     0xE0, ax
                ret


;;; AH=0Bh
.set_background_colour:
                out     0xE0, ax
                ret


; AH=0Ch        AL = color value (XOR'ED with current pixel if bit 7=1)
;               BH = page number
;               CX = column number (zero based)
;       	DX = row number (zero based)
.write_pixel:
                out     0xE0, ax
                ret


; AH=0Dh        BH = page number
;	        CX = column number (zero based)
;;;             DX = row number (zero based)
;;;  Returns    AL = colour of pixel
.read_pixel:
                out     0xE0, ax
                ret

;;; AH=0Eh
.tty_output:
                out     0xE0, ax
                ret


;;; AH=0Fh
;;; Output:
;;; AH = number of screen columns
;;; AL = mode currently set
;;; BH = current display page
.get_video_mode:
                push    ds
                mov     ax, 0x40
                mov     ds, ax
                mov     al, [0x87] ; bit 7 is set by bit 7 in original video mode requested
                and     ax, 0x0080
                or      ax, [0x49]
                mov     bh, [0x62]
                pop     ds
                ret

;;; AH=10h
.palette_register_control:
                out     0xE0, ax
                ret

;;; AH=11h
.character_generator_control:
                out     0xE0, ax
                ret


;;; AH=12h
.video_subsystem_control:
                out     0xE0, ax
                ret

;;; AH=13h
.write_string:
                out     0xE0, ax
                ret


; BH=page       Checks page is valid for current mode
; Returns:      Carry  Clear: valid  Set invalid
.valid_video_page:
                stc
                push    ds
                push    dx
                push    bx
                mov     dx, 0x40
                mov     ds, dx
                mov     dl, [0x49]      ; active mode
                cmp     dl, 0x10        ; is mode valid?
                jg      .invalid_video_page

                mov     dl, bh
                add     dx, .max_page_for_mode
                mov     bx, dx
                cmp     dl, [cs:bx]
                jg      .invalid_video_page

                clc                     ; page OK for active mode
.invalid_video_page:
                pop     bx
                pop     dx
                pop     ds
                ret

.max_page_for_mode:     db      7 ; Mode 00     7 = Number of pages (8) - 1
                        db      7 ;      01
                        db      7 ;      02
                        db      7 ;      03
                        db      0 ;      04
                        db      0 ;      05
                        db      0 ;      06
                        db      7 ;      07
                        db      0 ;      08
                        db      0 ;      09
                        db      0 ;      0A
                        db      0 ;      0B
                        db      0 ;      0C
                        db      7 ;      0D
                        db      3 ;      0E
                        db      0 ;      0F
                        db      0 ;      10
                        db      0 ;      11
                        db      0 ;      12
                        db      0 ;      13
