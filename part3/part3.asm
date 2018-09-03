;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; "64K RAM Ought to be enough" - Part 3
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; Pungas de Villa Martelli - http://pungas.space
;
; code: riq (http://retro.moe)
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

bits    16
cpu     8086
org     0x100

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; MACROS
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
%define DEBUG 0                                 ;0=diabled, 1=enabled
%define EMULATOR 1                              ;1=run on emulator

GFX_SEG         equ     0x0800                  ;graphics segment (32k offset)


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
section .text
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; CODE
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
start:
        sub     ax,ax
        mov     ds,ax                           ;ds = 0
        mov     word [0x0415],128               ;make BIOS set_video_modo believe that we
                                                ; have at least 128K RAM, otherwise it won't let
                                                ; us set video mode 9

;        mov     ax,0x0089                       ;set video mode 9, don't clean screen
;        int     0x10                            ;320x200 16 colors
;
;        mov     ax,0x0583                       ;set CPU/CRT pages
;        mov     bx,0x0202                       ;use page 2 for video memory/map 0xb800
;        int     0x10                            ;page 2 means: starts at 0x0800 (32k offset)


        push    cs
        pop     ds

        call    set_vid_160_100_16

        call    scroll_anim

        mov     ax,1
        int     0x16
        int     0x20


        ;turning off the drive motor is needed to prevent
        ;it from being on the whole time.
        mov     bp,ds                           ;save ds
        sub     ax,ax
        mov     ds,ax                           ;ds = 0 (zero page)
        mov     byte [0x0440],0                 ;motor count to zero
        and     byte [0x043f],0xf0              ;turn off motor running bits
        mov     al,0x80
        out     0xf2,al                         ;turn off floppy motor
        mov     ds,bp                           ;restore ds

        push    cs
        pop     ds

        mov     ax,pvm_song                     ;start music offset
        call    music_init

        ; should be the last one to get initialized
        mov     ax,irq_8_handler                ;irq 8 callback
        mov     cx,199                          ;horizontal raster line
        call    irq_8_init

.main_loop:

%if EMULATOR
        push    ds
        sub     ax,ax
        mov     ds,ax                           ;ds = zero page
        mov     ax,[0x041a]                     ;keyboard buffer head
        cmp     ax,[0x041c]                     ;keyboard buffer tail
        pop     ds
%else
        in      al,0x62                         ;on real hardware, test keystroke missed?
        and     al,1                            ; so that we can disable IRQ9
%endif
        jnz     .exit

        cmp     byte [end_condition],0          ;animation finished?
        jz      .main_loop                      ;no, so keep looping

.exit:
        call    music_cleanup
        call    irq_8_cleanup

        mov     ax,0x4c00                       ;ricarDOS: load next file
        int     0x21                            ;DOS: exit to DOS


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

        push    cs
        pop     ds

        call    scroll_anim
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
scroll_anim:
        ; Triangle
        ; diagonal 1
        mov     ax,1                            ;x0
        mov     bx,0                            ;y0
        mov     cx,39                           ;x1
        mov     dx,99                           ;y1
        mov     bp,1
        call    Line04

        mov     ax,79                           ;x0
        mov     bx,0                            ;y0
        mov     cx,79                           ;x1
        mov     dx,199                           ;y1
        mov     bp,2
        call    Line04

        mov     ax,0                            ;x0
        mov     bx,99                           ;y0
        mov     cx,159                          ;x1
        mov     dx,99                           ;y1
        mov     bp,1
        call    Line04


        ; diagonal 1
        mov     ax,0                            ;x0
        mov     bx,0                            ;y0
        mov     cx,159                          ;x1
        mov     dx,199                          ;y1
        mov     bp,1
        call    Line04

        ; diagonal 2
        mov     ax,159                          ;x0
        mov     bx,0                            ;y0
        mov     cx,0                            ;x1
        mov     dx,199                          ;y1
        mov     bp,1
        call    Line04

        ; vertical
        mov     ax,79                           ;x0
        mov     bx,0                            ;y0
        mov     cx,79                           ;x1
        mov     dx,199                          ;y1
        mov     bp,1
        call    Line04

        ; horizontal
        mov     ax,0                            ;x0
        mov     bx,99                           ;y0
        mov     cx,159                          ;x1
        mov     dx,99                           ;y1
        mov     bp,1
        call    Line04

        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; set_vid_160_100_16
; Trixter's 160x100 @ 16 color video mode
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
set_vid_160_100_16:
        mov     ax,0x0008                       ;160x200x16 mode
        int     0x10
        mov     ax,0x0580                       ;grab CRT/CPU page registers
        int     0x10

        ; We need to set CRT and CPU page registers with "wrong" video addressing
        ; bits to get the double-pixels to show up}
        sub     al,al                           ;addrssing mode
        mov     cl,3
        shl     bl,cl                           ;cpu page into bits 5-3
        or      al,bl                           ;vv888???
        or      al,bh                           ;vv888ccc
        mov     dx,0x03df
        out     dx,al                           ;set CRT and CPU page registers
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;DATA
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
pvm_song:
        incbin 'part3/uctumi-song.pvm'

end_condition:
        db      0                               ;if 0, part3 ends

line_color:
        dw      0

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; includes
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
%include 'common/utils.asm'
%include 'common/music_player.asm'
%include 'common/draw_line_160_200_16color.asm'

