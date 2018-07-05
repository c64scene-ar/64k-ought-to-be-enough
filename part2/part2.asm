; Invite intro for Flashparty 2018
; Pungas de Villa Martelli - http://pungas.space
;
; code: riq (http://retro.moe)

bits    16
cpu     8086


extern irq_8_cleanup, irq_8_init
extern wait_vertical_retrace
extern dzx7_speed, dzx7_size
extern music_init, music_play, music_cleanup

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; MACROS
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
GFX_SEG         equ     0x1800                  ;graphics segment

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; CODE
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
main:
        resb    0x100                           ;cannot use "org 0x100" when using multiple .o files

        mov     ax,0x0009                       ;320x200 16 colors
        int     0x10

        mov     ax,cs
        mov     ds,ax
        mov     si,image1                       ;ds:si source

        mov     ax,0x1800
        mov     es,ax
        sub     di,di                           ;es:di destination

        call    dzx7_speed


        mov     ax,pvm_song                     ;start music offset
        call    music_init

        ; should be the last one to get initialized
        mov     ax,irq_8_handler
        call    irq_8_init


        sub     ax,ax
        int     0x16                            ;wait key
        int     0x19                            ;reboot

        ret


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
irq_8_handler:
        pushf
        push    es                              ;since we might be interrupting
        push    ds                              ; the main routine, we need to
        push    si                              ; save all used registers
        push    di
        push    dx
        push    cx
        push    bx
        push    ax
        push    bp

        mov     ax,cs
        mov     ds,ax
        mov     ax,GFX_SEG
        mov     es,ax

        call    music_play

        mov     al,0x20                         ;send the EOI signal
        out     0x20,al                         ; to the IRQ controller

        pop     bp
        pop     ax
        pop     bx
        pop     cx
        pop     dx
        pop     di
        pop     si
        pop     ds
        pop     es
        popf

        iret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;DATA
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
pvm_song:
        incbin 'part1/uctumi-song.pvm'

image1:
        incbin 'part2/image1.bin.zx7'

charset:
        incbin 'part2/charset_0x00_0x40.bin'

scroll_text:
        db 'HOLA HOLA, ESTO ES UNA PRUEBA DE SCROLL'
        db 0
