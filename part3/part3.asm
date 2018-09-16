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

VIDEO_SEG               equ     0xb800          ;graphics segment (32k offset)
PRE_RENDER_BUFFER_SIZE  equ     80*40           ;40 rows for buffer


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

        mov     ax,VIDEO_SEG                    ;video segment
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
        mov     si,gfx_pampa                    ;ds:si src
        sub     di,di                           ;es:di dst
        mov     cx,8192
        call    lz4_decompress
%endif


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

        call    main_init

        ;fall through
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
main_loop:

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

        cmp     byte [trigger_pre_render],0     ;should we pre-render text?
        jnz     .pre_render_text

        cmp     byte [end_condition],0          ;animation finished?
        jz      main_loop                      ;no, so keep looping

.exit:
        call    music_cleanup
        call    irq_8_cleanup

        mov     ax,0x4c00                       ;ricarDOS: load next file
        int     0x21                            ;DOS: exit to DOS

.pre_render_text:
        call    pre_render_text
        jmp     main_loop

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; main_init
; add here initialization
main_init:
        ; init vars
        ;convert cs:pre_render_buffer into a segment
        mov     ax,cs                                   ;new seg = cs + (offset >> 4)
        mov     bx,pre_render_buffer                    ;offset, which is already 16-byte aligned
        mov     cl,4
        shr     bx,cl                                   ;divided 16
        add     ax,bx                                   ;converted to segment
        mov     [pre_render_buffer_seg],ax              ;store segment for pre_render_buffer

        ; init music
        mov     ax,pvm_song                             ;start music offset
        call    music_init

        ; init "command" related stuff
        call    cmd_init                                ;initialize commands

        ; init timer handler
        ; should be the last one to get initialized
        mov     ax,irq_8_handler                        ;irq 8 callback
        mov     cx,199                                  ;horizontal raster line
        jmp     irq_8_init

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; pre_render_text
pre_render_text:

        les     di,[pre_render_buffer_seg_off]          ;es:di: dst buffer

        ; clean existing buffer first
        mov     cx,PRE_RENDER_BUFFER_SIZE/2             ;buffer size / 2 since we do it in word
        sub     ax,ax                                   ;color black
        rep stosw                                       ;clean buffer

        int 3
        mov     si,text_to_pre_render                   ;si: pointer to letters to render

.l0:
        lodsb                                           ;al = letter to render
        or      al,al                                   ;al = 0 ? end rendering
        jz      .exit                                   ; if, so exit

        sub     al,0x20                                 ;table starts at 'space' (0x20)
                                                        ; make it zero index
        sub     bh,bh
        mov     bl,al                                   ;bx = index to table
        shl     bx,1                                    ;multiply by 2. each entry takes 2 bytes

        push    si                                      ;save si
        mov     si,[svg_letter_table+bx]                ;pointer to letter
        call    draw_svg_letter_with_shadow             ;draw letter

        mov     ax, [svg_letter_spacing]
        add     byte [poly_translation_x],al            ;x offset
        add     byte [poly_translation_y],ah            ;y offset

        pop     si                                      ;restore si
        jmp     .l0                                     ;and start with next letter

.exit:
        mov     ax,VIDEO_SEG
        mov     es,ax                                   ;restore es

        mov     byte [trigger_pre_render],0             ;say pre-render finished
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

        push    cs
        pop     ds

%if DEBUG
        call    inc_d020
%endif

        call    music_play                      ;play music
        call    [commands_current_anim]         ;play current anim

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
; Command routines
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; init
cmd_init:
        mov     ax,commands_data
        mov     [commands_data_idx],ax

        jmp     cmd_process_next

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; cmd_process_next
cmd_process_next:
        mov     si,[commands_data_idx]                  ;si = command pointer
        lodsb                                           ;load next command in al
        mov     [commands_data_idx],si                  ;update index

        xchg    ax,bx                                   ;bx contains ax
        sub     bh,bh                                   ;bx = pointer
        shl     bl,1
        shl     bl,1                                    ;al *= 4 (init, anim)

        lea     si,[commands_entry_tbl + bx]

        lodsw                                           ;ax = address to init
        xchg    ax,bx                                   ;bx = ax
        lodsw                                           ;ax = address to anim
        mov     [commands_current_anim],ax              ;save anim address
        jmp     bx                                      ;call init

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
cmd_no_anim:
        ret
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; cmd_end
cmd_end_init:
        mov     byte [end_condition],1                  ;end of part III
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; cmd_in_scroll_up
cmd_in_scroll_up_init:
        mov     byte [var_command_in_cnt],40            ;bytes to scroll
        mov     ax,pre_render_buffer
        mov     word [var_command_si_offset],ax         ;from which row should get the data
        ret

cmd_in_scroll_up_anim:
        dec     byte [var_command_in_cnt]
        jnz     .l0
        jmp     cmd_process_next

.l0:
        mov     cx,80/2                         ;40 words == 80 bytes
        mov     si,[var_command_si_offset]      ;ds:si = src (local buffer)
        mov     di,80*99                        ;es:di = dst (video) dst = row 99
        sub     ax,ax                           ;color black
        rep movsw
        mov     [var_command_si_offset],si      ;update si

        jmp     helper_video_scroll_up_1_row

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; cmd_out_scroll_up
cmd_out_scroll_up_init:
        mov     byte [var_command_out_cnt],40   ;bytes to scroll
        ret

cmd_out_scroll_up_anim:
        ; scroll up one row
        dec     byte [var_command_out_cnt]
        jnz     .l0
        jmp     cmd_process_next

.l0:
        call    helper_video_scroll_up_1_row

        ; set row 99 as black
        mov     cx,80/2                         ;40 words == 80 bytes
        mov     di,80*99                        ;80 bytes per row. dst = row 99
        sub     ax,ax                           ;color black
        rep stosw

        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
helper_video_scroll_up_1_row:
        mov     bp,ds                           ;save ds for later
        mov     ax,VIDEO_SEG
        mov     ds,ax                           ;ds = 0xb800 (video segment)

        mov     di,80*60                        ;80 bytes per row. dst = row 60
        mov     si,80*61                        ;80 bytes per row. src = row 61
        mov     cx,80*39/2                      ;copy 39 rows (in words)
        rep movsw

        mov     ds,bp
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; cmd_in_scroll_down
cmd_in_scroll_down_init:
        mov     byte [var_command_in_cnt],40            ;rows to scroll
        mov     ax,pre_render_buffer + 40*80 - 2        ;data starts from bottom (first row, bottom one)
        mov     word [var_command_si_offset],ax         ;from which row should get the data
        ret

cmd_in_scroll_down_anim:
        dec     byte [var_command_in_cnt]
        jnz     .l0
        jmp     cmd_process_next

.l0:
        std
        mov     cx,80/2                         ;40 words == 80 bytes
        mov     si,[var_command_si_offset]      ;ds:si = src
        mov     di,80*61-2                      ;es:di = dst (video) dst = row 60
        sub     ax,ax                           ;color black
        rep movsw
        mov     [var_command_si_offset],si      ;update si

        jmp     helper_video_scroll_down_1_row

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; cmd_in_scroll_down_r
cmd_in_scroll_down_r_init:
        mov     byte [var_command_in_cnt],40            ;rows to scroll
        mov     ax,pre_render_buffer                    ;in reverse mode, we start from top
        mov     word [var_command_si_offset],ax         ;from which row should get the data
        ret

cmd_in_scroll_down_r_anim:
        dec     byte [var_command_in_cnt]
        jnz     .l0
        jmp     cmd_process_next

.l0:
        mov     cx,80/2                         ;40 words == 80 bytes
        mov     si,[var_command_si_offset]      ;ds:si = src
        mov     di,80*60                        ;es:di = dst (video) dst = row 60
        sub     ax,ax                           ;color black
        rep movsw
        mov     [var_command_si_offset],si      ;update si

        jmp     helper_video_scroll_down_1_row

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; cmd_out_scroll_down
cmd_out_scroll_down_init:
        mov     byte [var_command_out_cnt],40   ;bytes to scroll
        ret

cmd_out_scroll_down_anim:
        ; scroll up one row
        dec     byte [var_command_out_cnt]
        jnz     .l0
        jmp     cmd_process_next

.l0:
        call    helper_video_scroll_down_1_row

        ; set row 99 as black
        mov     cx,80/2                         ;40 words == 80 bytes
        mov     di,80*60                        ;80 bytes per row. dst = row 60
        sub     ax,ax                           ;color black
        rep stosw

        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
helper_video_scroll_down_1_row:
        mov     bp,ds                           ;save ds for later
        mov     ax,VIDEO_SEG
        mov     ds,ax                           ;es = ds = 0xb800 (video segment)

        std                                     ;reverse si/di

        mov     di,80*100-2                     ;80 bytes per row. dst = row 99
        mov     si,80*99-2                      ;80 bytes per row. src = row 98
        mov     cx,(80/2)*39                    ;copy 39 rows (in words)
        rep movsw                               ;copy them

        cld                                     ;restore direction flag to forward
        mov     ds,bp
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; cmd_pre_render
cmd_pre_render_init:
        mov     bp,es                           ;save es for later
        mov     ax,ds
        mov     es,ax                           ;es=ds=cs

        mov     si,[commands_data_idx]
        mov     di,text_to_pre_render

.l0:    lodsb
        stosb                                   ;copy text to render
        or      al,al
        jnz     .l0                             ;copy until al=0

        mov     es,bp                           ;restore es
        mov     [commands_data_idx],si          ;update index

        mov     byte [trigger_pre_render],1     ;tell "main thread" to pre-render text
        ret


cmd_pre_render_anim:
        cmp     byte [trigger_pre_render],0     ;pre-render finished?
        jz      .next_command                   ;yes, call next command
        ret
.next_command:
        jmp     cmd_process_next


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; cmd_rotation
cmd_rotation_init:
        mov     si,[commands_data_idx]
        lodsb                                   ;al = new scale
        mov     [poly_rotation],al              ;set new rotation angle
        mov     [commands_data_idx],si          ;update index
        jmp     cmd_process_next                ;no animation... process next command

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; cmd_scale
cmd_scale_init:
        mov     si,[commands_data_idx]
        lodsb                                   ;al = new scale
        mov     [poly_scale],al                 ;set new scale factor
        mov     [commands_data_idx],si          ;update index
        jmp     cmd_process_next                ;no animation... process next command

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; cmd_translate
cmd_translate_init:
        mov     si,[commands_data_idx]
        lodsw                                   ;ax = new x,y
        mov     [poly_translation],ax           ;set new translation offset
        mov     [commands_data_idx],si          ;update index
        jmp     cmd_process_next                ;no animation... process next command

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; cmd_char_spacing
cmd_char_spacing_init:
        mov     si,[commands_data_idx]
        lodsw                                   ;ax = new x,y spacing
        mov     [svg_letter_spacing],ax         ;set new spacing between chars
        mov     [commands_data_idx],si          ;update index
        jmp     cmd_process_next                ;no animation... process next command

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; cmd_shadow_palette
cmd_shadow_palette_init:
        mov     si,[commands_data_idx]
        lodsw                                   ;ax = color shadow #1 and #0
        mov     [svg_letter_shadow_colors],ax   ;shadow colors
        lodsb                                   ;al = foregrond color
        mov     [svg_letter_shadow_colors+2],al
        mov     [commands_data_idx],si          ;update index
        jmp     cmd_process_next                ;no animation... process next command

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; cmd_shadow_dir
cmd_shadow_dir_init:
        mov     si,[commands_data_idx]
        lodsw                                   ;ax = shadow direction
        mov     [svg_letter_shadow_dir],ax      ;shadow dir
        mov     [commands_data_idx],si          ;update index
        jmp     cmd_process_next                ;no animation... process next command

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; cmd_wait:
cmd_wait_init:
        mov     si,[commands_data_idx]
        lodsb                                   ;al=cycles to wait
        mov     [commands_data_idx],si          ;update index
        mov     [var_command_wait_delay],al
        ret


cmd_wait_anim:
        dec     byte [var_command_wait_delay]
        jz      .next_command
        ret
.next_command:
        jmp     cmd_process_next

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; SVG drawing routines
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
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
draw_svg_letter_with_shadow:
        push    word [poly_translation]                 ;save original translation

        mov     [tmp_poly_offset],si

        ; outer shadow
        mov     al,[svg_letter_shadow_colors]           ;color for letter (shadow #1)
        mov     byte [Line08_color],al
        call    draw_svg_letter

        ; middle shadow
        mov     si,[tmp_poly_offset]
        mov     ax,[svg_letter_shadow_dir]              ;ax = offset for shadow
        add     byte [poly_translation_x],al
        add     byte [poly_translation_y],ah
        mov     al,[svg_letter_shadow_colors+1]         ;color for letter (shadow #0)
        mov     byte [Line08_color],al
        call    draw_svg_letter

        ; foreground
        mov     si,[tmp_poly_offset]
        mov     ax,[svg_letter_shadow_dir]              ;ax = offset for shadow
        add     byte [poly_translation_x],al
        add     byte [poly_translation_y],ah
        mov     al,[svg_letter_shadow_colors+2]         ;color for letter (foreground)
        mov     byte [Line08_color],al
        call    draw_svg_letter

        pop     word [poly_translation]                 ;restore original translation
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; draw_svg_letter_zoomed
; IN:
;       si := poly offset
draw_svg_letter_zoomed:
        mov     [tmp_poly_offset],si

        mov     byte [Line08_color],1
        call    draw_svg_letter

        mov     si,[tmp_poly_offset]
        dec     byte [poly_scale]                       ;scale -= 1
        mov     byte [Line08_color],9
        call    draw_svg_letter

        mov     si,[tmp_poly_offset]
        dec     byte [poly_scale]                       ;scale -= 1
        mov     byte [Line08_color],15
        call    draw_svg_letter

        mov     si,[tmp_poly_offset]
        dec     byte [poly_scale]                       ;scale -= 1
        mov     byte [Line08_color],1
        call    draw_svg_letter

        mov     si,[tmp_poly_offset]
        dec     byte [poly_scale]                       ;scale -= 1
        mov     byte [Line08_color],9
        call    draw_svg_letter

        mov     si,[tmp_poly_offset]
        dec     byte [poly_scale]                       ;scale -= 1
        mov     byte [Line08_color],15
        call    draw_svg_letter

        mov     si,[tmp_poly_offset]
        dec     byte [poly_scale]                       ;scale -= 1
        mov     byte [Line08_color],1
        call    draw_svg_letter

        mov     byte [poly_scale],0                     ;restore scale
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

        add     al,[poly_rotation]              ;al := al + rotation
        mov     cl,[poly_scale]                 ;scale := scale >> scale_factor
        shr     ah,cl                           ;scale: divide by 2 or 4
                                                ; if [poly_scale] is bigger than 2, they are going
                                                ; to bee too small

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
        mov     cx,[poly_prev_point]            ;restore previous point
        mov     [poly_prev_point],ax            ;save current point for later

        mov     dx,[poly_translation]           ;dx = translation
        ; coordinates should be added separately, otherwise
        ; borrow/carry could affect Y
        add     al,dl                           ;x1 += x translation
        add     ah,dh                           ;y1 += y translation

        mov     bl,ah                           ;bx = y1 (LSB), bh (MSB) already 0
        sub     ah,ah                           ;ax = x1 (MSB)

        add     cl,dl                           ;x2 += x translation
        add     ch,dh                           ;y2 += y translation

        mov     dl,ch                           ;dx = y2 (LSB)
        sub     dh,dh                           ;dx = y2 (MSB)
        sub     ch,ch                           ;cx = x1 (MSB)

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

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; SVG drawing related
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
poly_rotation:          db      0               ;rotation: between 0 and 255
poly_scale:             db      0               ;scale: cannot be greater than max radius

tmp_poly_offset:        dw      0               ;tmp var to store poly offset

svg_letter_spacing:     dw      0               ;x,y: spacing in pixels between letters
svg_letter_shadow_dir:  dw      0               ;x,y: shadow direction
svg_letter_shadow_colors:                       ;colors used for letters with shadows
        db              8                       ;outer color
        db              7                       ;inner color
        db              15                      ;foreground color
video_addr_offset:      dw      0               ;should be 0 when rendering to video
                                                ; directly, but when using the pre-render
                                                ; buffer, it should contain the address
                                                ; of the pre-render buffer

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; command related stuff
CMD_END                 equ     0
CMD_IN_SCROLL_UP        equ     1
CMD_OUT_SCROLL_UP       equ     2
CMD_PRE_RENDER          equ     3
CMD_ROTATION            equ     4
CMD_SCALE               equ     5
CMD_TRANSLATE           equ     6
CMD_WAIT                equ     7
CMD_IN_SCROLL_DOWN      equ     8
CMD_IN_SCROLL_DOWN_R    equ     9               ;reversed scroll down
CMD_OUT_SCROLL_DOWN     equ     10
CMD_CHAR_SPACING        equ     11
CMD_SHADOW_PALETTE      equ     12
CMD_SHADOW_DIR          equ     13

CMD_OUT_SCROLL_LEFT     equ     9
CMD_OUT_SCROLL_RIGHT    equ     10
CMD_OUT_SWEEP_DOWN      equ     11
CMD_OUT_SWEEP_UP        equ     12
CMD_OUT_SWEEP_LEFT      equ     13
CMD_OUT_SWEEP_RIGHT     equ     14
CMD_OUT_SWEEP_PIXEL     equ     15

commands_current_anim:  dw      0               ;address of current anim

commands_data_idx:      dw      0               ;index in commands_data
commands_data:
        ; credits
        db      CMD_WAIT,60
        db      CMD_TRANSLATE,20,20             ;set new x,y
        db      CMD_SCALE,1                     ;scalea for fonts, the bigger, the samller
        db      CMD_ROTATION,0
        db      CMD_CHAR_SPACING,20,0           ;spacing between chars
        db      CMD_SHADOW_PALETTE,8,7,15       ;colos for shadow+foreground
        db      CMD_SHADOW_DIR,0xff,0xff        ;shadow direction
        db      CMD_PRE_RENDER, 'CREDITS',0     ;string in buffer
        db      CMD_IN_SCROLL_DOWN_R,
        db      CMD_OUT_SCROLL_DOWN,
        db      CMD_WAIT,60
        db      CMD_IN_SCROLL_UP,
        db      CMD_WAIT,60
        db      CMD_OUT_SCROLL_UP,

        ; part i
        db      CMD_WAIT,60
        db      CMD_TRANSLATE,20,20             ;set new x,y
        db      CMD_SCALE,0                     ;set new scale
        db      CMD_ROTATION,0                  ;set new rotation
        db      CMD_PRE_RENDER, 'PART I:',0
        db      CMD_IN_SCROLL_UP,
        db      CMD_WAIT,30
        db      CMD_OUT_SCROLL_UP,

        db      CMD_WAIT,255
        db      CMD_WAIT,255
        db      CMD_WAIT,255
        db      CMD_WAIT,255
        db      CMD_WAIT,255
        db      CMD_WAIT,255
        db      CMD_WAIT,255
        db      CMD_WAIT,255
        db      CMD_WAIT,255
        db      CMD_WAIT,255
        db      CMD_WAIT,255
        db      CMD_WAIT,255
        db      CMD_WAIT,255
        db      CMD_WAIT,255
        db      CMD_WAIT,255
        db      CMD_WAIT,255
        ; end
        db      CMD_END

commands_entry_tbl:
        dw      cmd_end_init,                   cmd_no_anim,            ; 0
        dw      cmd_in_scroll_up_init,          cmd_in_scroll_up_anim,  ; 1
        dw      cmd_out_scroll_up_init,         cmd_out_scroll_up_anim, ; 2
        dw      cmd_pre_render_init,            cmd_pre_render_anim,    ; 3
        dw      cmd_rotation_init,              cmd_no_anim,            ; 4
        dw      cmd_scale_init,                 cmd_no_anim,            ; 5
        dw      cmd_translate_init,             cmd_no_anim,            ; 6
        dw      cmd_wait_init,                  cmd_wait_anim,          ; 7
        dw      cmd_in_scroll_down_init,        cmd_in_scroll_down_anim,        ; 8
        dw      cmd_in_scroll_down_r_init,      cmd_in_scroll_down_r_anim,      ; 9
        dw      cmd_out_scroll_down_init,       cmd_out_scroll_down_anim,       ; 10
        dw      cmd_char_spacing_init,          cmd_no_anim,                    ; 11
        dw      cmd_shadow_palette_init,        cmd_no_anim,                    ; 12
        dw      cmd_shadow_dir_init,            cmd_no_anim,                    ; 13


; since only one command can be run at the same time, this variable is shared
; accross all commands... with different names.
; 1st word for tmp vars
var_command_in_cnt:
var_command_out_cnt:
var_command_wait_delay:
var_tmp_dw_0:
var_tmp_db_0: db        0
var_tmp_db_1: db        0

;2nd word for tmp vars
var_command_si_offset:
var_tmp_dw_1:
var_tmp_db_2: db        0
var_tmp_db_3: db        0

; text that should be renderer. ends with 0
text_to_pre_render:
        times   32      db      0

trigger_pre_render:
        db      0                               ;boolean. if 1, tells main thread
                                                ; to pre-render text.
                                                ; 0, whne pre-render finished

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; fake segment...
; space used to pre-render the letters, and then with a "in" effect is placed
; in the video memory
align 16
pre_render_buffer:
        times PRE_RENDER_BUFFER_SIZE db      0x00

pre_render_buffer_seg_off:                      ;pre calculated seg/offsset address
pre_render_buffer_off:                          ;pre calculated offset
        dw              0                       ;offset
pre_render_buffer_seg:                          ;pre calculated seg
        dw              0                       ;segment

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; includes
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
%include 'part3/elipse_table.asm'
%include 'part3/svg_font.asm'
%include 'common/utils.asm'
%include 'common/music_player.asm'
%include 'common/draw_line_160_100_16color.asm'

