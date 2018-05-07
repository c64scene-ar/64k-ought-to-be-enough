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

.loop:
        call    key_pressed
        jz      .loop

        ret

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

        call    play_music
        call    update_state_machine

        mov     al,0x20                         ;send the EOI signal
        out     0x20,al                         ; to the IRQ controller

        iret


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
play_music:
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
update_state_machine:
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; uncompress letter to 1800:4000
; input: ax=letter to uncompress
uncompress_letter:

        ;assert (ds=banner_data)
        shl     ax,1                            ;each address takes 2 bytes
        mov     bx,ax                           ;uses bx for index
        mov     si,[letter_idx + bx]            ;ds:si: compressed data

        mov     ax,0x1800                       ;es:di (destination)
        mov     es,ax
        mov     di,0x4000

        call    lz4_decompress

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
; available tokens
commands:
        db DELAY,5
        db DISPLAY,0                            ;p
        db DELAY,100
        db DISPLAY,1                            ;v
        db DELAY,100
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
