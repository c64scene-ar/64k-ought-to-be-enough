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

;        call    scroll_anim

;        mov     ax,1
;        int     0x16
;        int     0x20


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
;        sub     bx,bx                           ;point 0 - point 1
;        mov     cl,[current_rotation]
;        call    get_coords_for_line
;        mov     bp,[current_color]
;        call    Line08
;        inc     byte [current_rotation]
;        inc     byte [current_color]
;        ret
        mov     si,points
        mov     word [poly_offset],0x3250       ;x offset = 80, y offset = 50
        call    draw_poly
        ;inc     byte [rotation_and_scale]
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; draw polygon
; IN:
;       si := poly offset
draw_poly:
        mov     byte [is_poly_previous_point],0

.loop:
        lodsw                                   ;load point
                                                ; al = angle
                                                ; ah = radius
        cmp     ah,0xff                         ; end of poly ?
        jz      .exit

        add     ax,[rotation_and_scale]         ;update angle (rotation) and radius (scale)
                                                ; al := al + cl
                                                ; ah := ah + ch

        mov     bp,si                           ;save si... gets destroyed in get_coords_for_point
        call    get_coords_for_point            ;al := x, ah := y
        mov     si,bp                           ;restore si

        cmp     byte [is_poly_previous_point],0 ;is there already another point in the stack?
        jne     .draw_it

        mov     [poly_prev_point],ax            ;save current point for later
        inc     byte [is_poly_previous_point]   ;flag that a point is already saved
        jmp     .loop                           ;read next point... start again

.draw_it:
        ; draw line... order of points doesn't matter
        ; a line is a line. we are drawing a line from p1 to p0
        mov     bp,[poly_offset]
        mov     cx,[poly_prev_point]            ;restore previous point
        add     cx,bp                           ;update offset for point 1
        mov     [poly_prev_point],ax            ;save current point for later
        add     ax,bp                           ;update offset for point 0
        mov     bl,ah                           ;y0
        cbw                                     ;x0 (ah := 0)
        mov     dl,ch                           ;y1
        sub     dh,dh
        sub     ch,ch                           ;x1
        ;sub     bh,bh                          ;not needed, bh is already 0
        mov     bp,1
        call    Line08
        jmp     .loop

.exit:
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; get_coords_for_line
; in:
;       bx = point idx
;       cl = angle (from 0 to 255). each quadrant has 64 values
; returns:
;       ax = x0
;       bx = y0
;       cx = x1
;       dx = y0
get_coords_for_line:
        mov     dl,cl                           ;dl := cl (angle). saved for later
        shl     bx,1                            ;point offset, since each one takes 2 bytes
        lea     si,[points+bx]

        ; point 0
        lodsw                                   ;al = orig angle, ah = orig radius
        add     al,cl                           ;al = orig angle + new angle

        mov     bp,si                           ;bp := si (saved for later)

        call    get_coords_for_point
        mov     di,ax                           ;di = x,y. save results for later

        ; point 1
        mov     si,bp                           ;restore si from bp

        lodsw                                   ;al = orig angle, ah = orig scale
        add     al,dl                           ;al = orig angle + new angle
        call    get_coords_for_point

        ; translate results to center of screen
        ; translate point 1
        mov     bp,0x3250                       ; bp := 50 * 256 + 80
        add     ax,bp                           ;translate x,y to center of screen
                                                ; y := y + 50 (ah)
                                                ; x := x + 80 (al)
        mov     cl,al                           ;cx = x1
        mov     dl,ah                           ;dx = y1

        ; translate point 0
        add     di,bp                           ;translate x,y to center of screen
        xchg    ax,di                           ;ax := x,y
        mov     bl,ah                           ;bx := y0

        ; clear MSB 8 bits
        cbw                                     ;ax := x0
        sub     bh,bh                           ;bx := y0
        sub     ch,ch                           ;cx := x1
        sub     dh,dh                           ;dx := y1

        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; get_coords_for_point
; we only stored pre-computed values for quadrant 0.
; values for quadrant 1, 2, 3 need to be computed after quadrant 0 by
; inverting / negating certain values.
;
; in:
;       al = angle (from 0 to 255). each quadrant has 64 values
;       ah = radius
; returns:
;       al = x
;       ah = y
; destroys:
;       cx, bx, si
get_coords_for_point:
        mov     cx,ax                           ;cx = angle / radius. cx saved for later
        test    al,0b0100_0000                  ;quadran 1 or 3?
        jz      .l0                             ;no, don't inverse angle

        ;quadrant 1_3 should inverse the search
        ;if requested angle is 1, then return angle 63 (64-1)
        ;64 values per quadrant
        not     al                              ;invert bits, so angle gets reversed

.l0:
        sub     bh,bh
        mov     bl,ah                           ;bx := angle

        shl     bx,1                            ;each elipse radius entry takes 2 bytes
                                                ;using ah ax index, and can't be bigger than 128.
        mov     si,[elipse_table+bx]            ;si := addres of radius-table to use

        and     ax,0b00000000_00111111          ;ah = 0
                                                ; al = filter out quadrant bits
        shl     ax,1                            ;radius_table has x,y coords.
                                                ; multiplying by 2 to get correct idx
        add     si,ax                           ;si has correct offset for coords
        lodsw                                   ;al = x coord
                                                ; ah = y coord

        ; ax already has the x,y coords for quadrant 0
        ; adjust values for correct quadrant
        test    cl,0b1000_0000                  ;quadrants 2 or 3? (128 or higher)
        jz      .quadrant_0_1                   ; nope, skip to quandrant 0 1

        ; quadrants 2 or 3 here
        neg     al                              ;x := -x

        test    cl,0b0100_0000                  ;already know that we are in
                                                ; quadrant 2 or 3. are we in quadrant 2?
        jnz     .exit                           ;exit if in quadrant 3
        ; quadrant 2
        neg     ah                              ;y := -y
        ret

        ; quadrants 0 or 1 here
.quadrant_0_1:
        test    cl,0b0100_0000                  ;quadrant 1?
        jz      .exit                           ; exit if quadrant 0

        ; quadrant 1 here
        neg     ah                              ;y := -y
.exit:
        ret


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
scroll_anim_2:

        ; kite top-right diag
        mov     ax,10                          ;x1
        mov     bx,49                           ;y1
        mov     cx,79                          ;x0
        mov     dx,29                          ;y0
        mov     bp,2
        call    Line08

        ; kite top-left diag
        mov     ax,79                          ;x1
        mov     bx,29                           ;y1
        mov     cx,150                          ;x0
        mov     dx,49                          ;y0
        mov     bp,3
        call    Line08

        ; kite bottom-left diag
        mov     ax,10                           ;x0
        mov     bx,49                           ;y0
        mov     cx,79                           ;x1
        mov     dx,99                          ;y1
        mov     bp,1
        call    Line08

        ; kite bottom-right diag
        mov     ax,150                           ;x1
        mov     bx,49                          ;y1
        mov     cx,79                          ;x0
        mov     dx,99                           ;y0
        mov     bp,1
        call    Line08

        ; kite horiz
        mov     ax,10                           ;x1
        mov     bx,49                           ;y1
        mov     cx,150                          ;x0
        mov     dx,49                           ;y0
        mov     bp,4
        call    Line08

        ; kite vertical
        mov     ax,79                           ;x1
        mov     bx,29                           ;y1
        mov     cx,79                           ;x0
        mov     dx,99                          ;y0
        mov     bp,3
        call    Line08

        ; test vertical 1
        mov     ax,0                            ;x1
        mov     bx,0                            ;y1
        mov     cx,0                            ;x0
        mov     dx,99                          ;y0
        mov     bp,2
        call    Line08

        ; test vertical 2
        mov     ax,1                            ;x1
        mov     bx,0                            ;y1
        mov     cx,1                            ;x0
        mov     dx,99                           ;y0
        mov     bp,4
        call    Line08

        ; test vertical 1
        mov     ax,159                            ;x1
        mov     bx,0                            ;y1
        mov     cx,159                            ;x0
        mov     dx,99                          ;y0
        mov     bp,2
        call    Line08

        ; test vertical 2
        mov     ax,158                          ;x1
        mov     bx,0                            ;y1
        mov     cx,158                         ;x0
        mov     dx,99                          ;y0
        mov     bp,4
        call    Line08

        ; test horizontal 1
        mov     ax,0                            ;x1
        mov     bx,0                            ;y1
        mov     cx,159                          ;x0
        mov     dx,0                            ;y0
        mov     bp,5
        call    Line08

        ; test horizontal 2
        mov     ax,0                            ;x1
        mov     bx,1                            ;y1
        mov     cx,159                          ;x0
        mov     dx,1                            ;y0
        mov     bp,7
        call    Line08

        ; test horizontal 3
        mov     ax,0                            ;x1
        mov     bx,99                            ;y1
        mov     cx,159                          ;x0
        mov     dx,99                            ;y0
        mov     bp,5
        call    Line08

        ; test horizontal 4
        mov     ax,0                            ;x1
        mov     bx,98                            ;y1
        mov     cx,159                          ;x0
        mov     dx,98                            ;y0
        mov     bp,7
        call    Line08

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
        incbin 'part3/uctumi-zamba.pvm'

end_condition:
        db      0                               ;if 0, part3 ends
; poly and line related
poly_prev_point:
        dw      0
is_poly_previous_point:
        db      0                               ;1 if there is a valid point in poly_prev_point
poly_offset:
        dw      0
rotation_and_scale:
        dw      0
current_rotation:
        db      0
current_color:
        db      0
        db      0                               ;ignore
points:
        ; points are defined in polar coordinates: angle (0-255), radius
        db      224, 40
        db      32, 40
        db      96, 40
        db      160, 40
        db      224, 40
        db      -1, -1


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; includes
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
%include 'part3/elipse_table.asm'
%include 'common/utils.asm'
%include 'common/music_player.asm'
%include 'common/draw_line_160_100_16color.asm'

