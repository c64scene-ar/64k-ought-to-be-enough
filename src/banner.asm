; Invite intro for Flashparty 2018
; Pungas de Villa Martelli - http://pungas.space
;
; code: riq (http://retro.moe)

bits    16
cpu     8086

extern label_model
extern lz4_decompress, lz4_decompress_small
extern dzx7_speed, dzx7_size, dzx7_original
extern irq_8_cleanup, irq_8_init

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; MACROS
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
%define DEBUG 0                                 ;0=diabled, 1=enabled
%define EMULATOR 1                              ;1=run on emulator

GFX_SEG         equ     0x1800                  ;0x1800 for PCJr with 32k video ram
                                                ;0xb800 for Tandy
VGA_ADDRESS     equ     0x03da                  ;Tandy == PCJr.
VGA_DATA        equ     0x03da                  ;Tandy = 0x03de. PCJr. 0x03da


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; CODE
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
section .text

global banner_start
banner_start:
        cld

        mov     ax,banner_data                  ;init segments
        mov     ds,ax                           ;these values must always be true
        mov     ax,GFX_SEG                      ; through the whole intro.
        mov     es,ax                           ; push/pop otherwise

        call    banner_init

        call    banner_main_loop

        call    banner_cleanup

        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
banner_init:

        call    command_next                    ;initialize next command

        mov     ax,banner_irq_8
        call    irq_8_init

        mov     ax,0x0004                       ;320x200 4 colors
        int     0x10

        ret


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
banner_cleanup:
        call    irq_8_cleanup
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
banner_main_loop:

.main_loop:
        cmp     byte [should_decompress],1      ;should decompress image?
        jz      .decompress_letter

        call    key_pressed                     ;key pressed?
        jz      .main_loop

        ret                                     ;exit main loop.

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.decompress_letter:
        int 3
        sub     ax,ax
        mov     al,[letter_to_decompress]
        shl     ax,1                            ;each address takes 2 bytes
        mov     bx,ax                           ;uses bx for index
        mov     si,[letter_idx + bx]            ;ds:si: compressed data

        mov     ax,0x1800                       ;es:di (destination)
        mov     es,ax
        mov     di,0x4000

        call    lz4_decompress

        dec     byte [should_decompress]        ;flag that decompress finished
        jmp     .main_loop                      ;return to main loop

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
key_pressed:
%if EMULATOR
        cli                                     ;on emulator, test for keyboard buffer

        push    ds
        push    ax

        sub     ax,ax
        mov     ds,ax                           ;ds = zero page
        mov     ax,[0x041a]                     ;keyboard buffer head
        cmp     ax,[0x041c]                     ;keyboard buffer tail

        pop     ax
        pop     ds
        sti
%else
        in      al,0x62                         ;on real hardware, test keystroke missed?
        and     al,1                            ; so that we can disable IRQ9
%endif
        ret


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
banner_irq_8:
        push    es                              ;since we might be interrupting
        push    ds                              ; the decompressor routine, we need to
        push    si                              ; save all registers
        push    di
        push    dx
        push    cx
        push    bx
        push    ax
        pushf

        mov     ax,banner_data                  ;update segments
        mov     ds,ax
        mov     ax,0x1800
        mov     es,ax

        call    play_music
        call    update_state_machine

        mov     al,0x20                         ;send the EOI signal
        out     0x20,al                         ; to the IRQ controller

        popf
        pop     ax
        pop     bx
        pop     cx
        pop     dx
        pop     di
        pop     si
        pop     ds
        pop     es

        iret


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
play_music:
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
update_state_machine:
        cmp     byte [should_decompress],0      ;is decompressing?
        jnz     .exit                           ; if so, exit

        call    [command_current_fn]            ;call current command

.exit:
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
command_next:
        mov     bx,[command_idx]
        mov     al,[commands + bx]              ;command to initialize

        sub     ax,ax                           ;ax = 0
        shl     al,1                            ;each address takes 2 bytes
        xchg    bx,ax                           ;bx = ax

        inc     word [command_idx]

        mov     ax,[command_updates + bx]       ;cache current update function
        mov     [command_current_fn],ax         ; for future use

        jmp     [command_inits + bx]            ;call correct init function


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
command_init_display:
        int 3
        mov     bx,[command_idx]
        mov     al,[commands + bx]

        inc     word [command_idx]

        mov     [letter_to_decompress],al
        mov     byte [should_decompress],1
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; do nothing. wait until decompress finishes (from main loop) and
; execute next command when that happens
command_update_display:
        cmp     byte [should_decompress],0
        jnz     .exit

        jmp     command_next

.exit:
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
command_init_flash:
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
command_update_flash:
        call    command_next
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
command_init_delay:
        inc     word [command_idx]
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
command_update_delay:
        call    command_next
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
command_init_black:
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
command_update_black:
        call    command_next
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
command_init_end:
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
command_update_end:
        call    command_next
        ret



;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; DATA GFX
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
section .banner_data data

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; compress data
letter_p_lz4:
        incbin 'src/p.raw.lz4'
letter_v_lz4:
        incbin 'src/v.raw.lz4'
letter_m_lz4:
        incbin 'src/m.raw.lz4'
letter_invites_lz4:
        incbin 'src/invites.raw.lz4'
letter_you_lz4:
        incbin 'src/you.raw.lz4'
letter_to_lz4:
        incbin 'src/to.raw.lz4'
letter_flashparty_lz4:
        incbin 'src/fp.raw.lz4'
letter_2018_lz4:
        incbin 'src/2018.raw.lz4'

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; vars
should_decompress:      db 0                    ;0 when no decompress is needed, nor in progress
                                                ; 1 when decompress is requested or in progress
letter_to_decompress:   db 0                    ;idx of the image to decompress

command_idx:            dw 0                    ;index of current command. index in the
                                                ; 'command' variable. [command + command_idx] gives
                                                ; you the current command
command_current_fn:     dw 0                    ; current command function. address of the function to call

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; pointers to the data. each one has its own index
letter_idx:
        dw letter_p_lz4                         ;0
        dw letter_v_lz4                         ;1
        dw letter_m_lz4                         ;2
        dw letter_invites_lz4                   ;3
        dw letter_you_lz4                       ;4
        dw letter_you_lz4                       ;5
        dw letter_to_lz4                        ;6
        dw letter_flashparty_lz4                ;7
        dw letter_2018_lz4                      ;8


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; available tokens
DISPLAY         equ 0                             ;letter to display
FLASH           equ 1
DELAY           equ 2
BLACK           equ 3
END             equ 4

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
command_inits:
        dw      command_init_display
        dw      command_init_flash
        dw      command_init_delay
        dw      command_init_black
        dw      command_init_end

command_updates:
        dw      command_update_display
        dw      command_update_flash
        dw      command_update_delay
        dw      command_update_black
        dw      command_update_end

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; available tokens
commands:
        db DISPLAY,0                            ;p
        db DISPLAY,1                            ;v
        db DISPLAY,2                            ;m
        db BLACK
        db DELAY,100

        db DISPLAY,0                            ;p
        db DELAY,75
        db DISPLAY,1                            ;v
        db DELAY,75
        db DISPLAY,2                            ;m
        db BLACK
        db DELAY,75

        db DISPLAY,0                            ;p
        db DELAY,50
        db DISPLAY,1                            ;v
        db DELAY,50
        db DISPLAY,2                            ;m
        db BLACK
        db DELAY,50

        db DISPLAY,0                            ;p
        db DELAY,25
        db DISPLAY,1                            ;v
        db DELAY,25
        db DISPLAY,2                            ;m
        db BLACK
        db DELAY,25

        db DISPLAY,0                            ;p
        db DELAY,5
        db DISPLAY,1                            ;v
        db DELAY,5
        db DISPLAY,2                            ;m
        db BLACK
        db DELAY,5

        db DISPLAY,0                            ;p
        db DELAY,5
        db DISPLAY,1                            ;v
        db DELAY,5
        db DISPLAY,2                            ;m
        db BLACK
        db DELAY,5

        db DISPLAY,4                            ;invites
        db DELAY,30
        db DISPLAY,5                            ;you
        db DELAY,30
        db DISPLAY,6                            ;to
        db DELAY,30

        db DISPLAY,7                            ;flash party
        db DELAY,30
        db FLASH
        db DELAY,5
        db FLASH
        db DELAY,5
        db FLASH
        db DELAY,5
        db FLASH
        db DELAY,5
        db FLASH
        db DELAY,5
        db FLASH
        db DELAY,30

        db DISPLAY,8                            ;2018
        db DELAY,150

        db END
