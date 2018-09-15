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

        mov     ax,0xb800                       ;video segment
        mov     es,ax                           ;should be restored if modified

        call    set_vid_160_100_16

%if EMULATOR
        jmp     l0
gfx_pampa:
        incbin 'part3/image_pampa.raw.lz4'
%include 'common/lz4_8088.asm'

l0:
        push    cs
        pop     ds
        mov     si,gfx_pampa
        mov     ax,0xb800
        mov     es,ax
        sub     di,di
        mov     cx,8192
        call    lz4_decompress
%endif


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

%if DEBUG
        call    inc_d020
%endif

        call    scroll_anim
        call    music_play

%if DEBUG
        call    dec_d020
%endif


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
; Debug functions
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
%if DEBUG
inc_d020:
        mov     dx,0x03da                       ;show how many raster barts it consumes
        mov     al,2                            ;select border color
        out     dx,al

        mov     dl,0xde                         ;dx=0x03de
        mov     al,0x0f
        out     dx,al                           ;change border to white
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
dec_d020:
        mov     dx,0x03da                       ;show how many raster barts it consumes
        mov     al,2                            ;select border color
        out     dx,al

        mov     dl,0xde                         ;dx=0x03de
        sub     al,al
        out     dx,al                           ;change border back to black

        ret
%endif

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
scroll_anim:
;        mov     si,points
;        mov     word [poly_translation],0x3250       ;x offset = 80, y offset = 50
;        call    draw_poly
;        inc     byte [poly_rotation]
;        inc     byte [Line08_color]


        mov     byte [poly_scale],3

        mov     word [poly_translation],0x500c          ;x offset = 80, y offset = 50
        mov     si,svg_letter_data_C
        call    draw_svg_letter_zoomed

        add     word [poly_translation],0x0014          ;x offset = 80, y offset = 50
        mov     si,svg_letter_data_R
        mov     ax,0xffff                               ;shadow direction
        call    draw_svg_letter_with_shadow

        add     word [poly_translation],0x0014          ;x offset = 80, y offset = 50
        mov     si,svg_letter_data_E
        mov     ax,0xff00                               ;shadow direction
        call    draw_svg_letter_with_shadow

        add     word [poly_translation],0x0014          ;x offset = 80, y offset = 50
        mov     si,svg_letter_data_D
        mov     ax,0x00ff                               ;shadow direction
        call    draw_svg_letter_with_shadow

        add     word [poly_translation],0x0014          ;x offset = 80, y offset = 50
        mov     si,svg_letter_data_I
        mov     ax,0x0100                               ;shadow direction
        call    draw_svg_letter_with_shadow

        add     word [poly_translation],0x0014          ;x offset = 80, y offset = 50
        mov     si,svg_letter_data_T
        mov     ax,0x0101                               ;shadow direction
        call    draw_svg_letter_with_shadow

        add     word [poly_translation],0x0014          ;x offset = 80, y offset = 50
        mov     si,svg_letter_data_S
        mov     ax,0x0001                               ;shadow direction
        call    draw_svg_letter_with_shadow

        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; draw_svg_letter
; IN:
;       si := vector points
draw_svg_letter:
.next_poly:
        call    draw_poly                       ;draw first poly
        cmp     ah,0xff                         ;0xff == end of letter
        jnz     .next_poly                      ; no? draw next poly.
                                                ; yes? SI already points to the correct poly
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; draw_svg_letter_with_shadow
; IN:
;       si := vector points
;       ax := shadow direction. ah=y, al=x
draw_svg_letter_with_shadow:
        push    word [poly_translation]                 ;save original translation

        push    si
        push    ax                                      ;save shadow direction
        mov     byte [Line08_color],4
        call    draw_svg_letter

        pop     ax
        pop     si
        push    si                                      ;save char offset
        push    ax
        add     byte [poly_translation_x],al
        add     byte [poly_translation_y],ah
        mov     byte [Line08_color],12
        call    draw_svg_letter

        pop     ax
        pop     si
        add     byte [poly_translation_x],al
        add     byte [poly_translation_y],ah
        mov     byte [Line08_color],15
        call    draw_svg_letter

        pop     word [poly_translation]                 ;restore original translation
        ret

draw_svg_letter_zoomed:
        push    si
        mov     byte [Line08_color],1
        call    draw_svg_letter

        pop     si
        push    si
        dec     byte [poly_scale]                       ;scale -= 1
        mov     byte [Line08_color],9
        call    draw_svg_letter

        pop     si
        dec     byte [poly_scale]                       ;scale -= 1
        mov     byte [Line08_color],15
        call    draw_svg_letter

        add     byte [poly_scale],2                     ;restore scale
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
        cmp     ah,0xf0                         ; end of poly ?
        ja      .exit

        add     ax,[poly_rotation_and_scale]    ;update angle (rotation) and radius (scale)
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
        mov     bp,[poly_translation]
        mov     cx,[poly_prev_point]            ;restore previous point
        add     cx,bp                           ;update offset for point 1
        mov     [poly_prev_point],ax            ;save current point for later
        add     ax,bp                           ;update offset for point 0
        mov     bl,ah                           ;y0
        sub     ah,ah
        mov     dl,ch                           ;y1
        sub     dh,dh
        sub     ch,ch                           ;x1
        ;sub     bh,bh                          ;not needed, bh is already 0

        mov     [Line08_x1],ax
        mov     [Line08_y1],bx
        mov     [Line08_x2],cx
        mov     [Line08_y2],dx
        call    Line08_draw
        jmp     .loop

.exit:
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
        dw      0                               ;cache of previous point
is_poly_previous_point:
        db      0                               ;1 if there is a valid point in poly_prev_point

; matrix values for current polygon
;       translation
;       rotation
;       scale
poly_translation:                               ;must be together
poly_translation_x:     db      0               ;x
poly_translation_y:     db      0               ;y
poly_rotation_and_scale:                        ;can be accessed by a word
poly_rotation:  db 0                            ;rotation: between 0 and 255
poly_scale:     db 0                            ;scale: cannot be greater than max radius

points:
        ; points are defined in polar coordinates: angle (0-255), radius
        db      254, 21
        db      62, 21
        db      126, 21
        db      190, 21
;        db      254, 42
        db      -1, -1


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; includes
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
%include 'part3/elipse_table.asm'
%include 'part3/svg_font.asm'
%include 'common/utils.asm'
%include 'common/music_player.asm'
%include 'common/draw_line_160_100_16color.asm'

