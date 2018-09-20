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
%define EMULATOR 0                              ;1=run on emulator

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
        mov     ax,0x008a                       ;set video mode a, don't clean screen
        int     0x10                            ;620x200 4 colors

        mov     bl,0
        mov     al,0
        call    change_palette

        mov     bl,1
        mov     al,14
        call    change_palette

        mov     bl,2
        mov     al,12
        call    change_palette

        mov     bl,3
        mov     al,10
        call    change_palette

        mov     ax,0x0583                       ;set CPU/CRT pages
        mov     bx,0x0202                       ;use page 2 for video memory/map 0xb800
        int     0x10                            ;page 2 means: starts at 0x0800 (32k offset)

        ; preconditions that should be valid... always
        push    cs                              ;ds = cs
        pop     ds
        mov     ax,VIDEO_SEG                    ;es = 0xb800 (video segment)
        mov     es,ax
        cld

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

        call    main_init

        ; fall through

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
        ; main loop - phase 0
.keep_waiting:
        cmp     byte [trigger_switch_to_160100],0       ;time to switch to 160x100 video mode?
        jz      .keep_waiting                           ; no, keep waiting

        ; disable timer
        ; FIXME: instead of disabling the timer, I should
        ; find out why it crashes... and/or switch video mode manually
        call    irq_8_cleanup

        ; display 2nd graphics
        call    set_vid_160_100_16

        ; enable timer again, to prevent crashes
        mov     ax,irq_8_handler                        ;irq 8 callback
        mov     cx,148                                  ;horizontal raster line
        call    irq_8_init

        ; decompress "pampa" image
        mov     si,graphic_lz4                          ;ds:si src
        sub     di,di                                   ;es:di dst
        mov     cx,8192
        call    lz4_decompress

        mov     byte [trigger_switch_to_160100],0       ;tell "other thread" that we
                                                        ; are done with the switch to 160x100
        ; main loop - phase 1
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
        jmp     exit

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
        mov     cx,148                                  ;horizontal raster line
        jmp     irq_8_init

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; pre_render_text
pre_render_text:

        les     di,[pre_render_buffer_seg_off]          ;es:di: dst buffer

        cmp     byte [should_clean_pre_render_buffer],0 ;should clean render buffer?
        jz      .l0                                     ; no? skip cleaning buffer

        ; clean existing buffer first
        mov     cx,PRE_RENDER_BUFFER_SIZE/2             ;buffer size / 2 since we do it in word
        sub     ax,ax                                   ;color black
        rep stosw                                       ;clean buffer

.l0:

        mov     si,text_to_pre_render                   ;si: pointer to letters to render
.loop:
        lodsb                                           ;al = letter to render
        or      al,al                                   ;al = 0 ? end rendering
        jz      .exit                                   ; if, so exit

        push    si                                      ;save si (current position of text index)

        ; special treatment for "space"... it only advances half the space
        ; and no rendering is required
        cmp     al,0x20                                 ;is space ?
        jnz     .l1                                     ; nope, skip special treatment

        mov     ax,[svg_letter_spacing]                 ;get spacing, divide it by 2
        shr     al,1                                    ;x += spacing x / 2
        shr     ah,1                                    ;y += spacing y / 2
        jmp     .l2

.l1:
        sub     al,0x20                                 ;table starts at 'space' (0x20)
                                                        ; make it zero index
        sub     bh,bh
        mov     bl,al                                   ;bx = index to table
        shl     bx,1                                    ;multiply by 2. each entry takes 2 bytes

        mov     si,[svg_letter_table+bx]                ;pointer to letter
        mov     al,[pre_render_mode]                    ;shadow ? single ? zoom ?
        or      al,al                                   ;mode == 0 ? single trace
        jnz     .with_shadow

        call    draw_svg_letter_single
        jmp     .l3

        ; FIXME: implement other modes
.with_shadow:
        call    draw_svg_letter_with_shadow             ;else, do shadow
        ; fall through
.l3:
        mov     ax,[svg_letter_spacing]
.l2:
        add     byte [poly_translation_x],al            ;x offset
        add     byte [poly_translation_y],ah            ;y offset

        pop     si                                      ;restore si
        jmp     .loop                                   ;and start with next letter

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

        call    [commands_current_anim]         ;play current anim
        call    music_play                      ;play music

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
; cmd_in_sweep_up
cmd_in_sweep_up_init:
        mov     byte [var_command_out_cnt],40   ;bytes to scroll
        mov     ax,pre_render_buffer+40*80-2    ;data starts from bottom (first row, bottom one)
        mov     [var_command_si_offset],ax      ;from which row should get the data
        mov     ax,80*100-2                     ;last row of video segment
        mov     [var_command_di_offset],ax      ;destination offset
        ret

cmd_in_sweep_up_anim:
        ; scroll up one row
        dec     byte [var_command_out_cnt]
        jnz     .l0
        jmp     cmd_process_next

.l0:
        std                                     ;copy backwards
        mov     si,[var_command_si_offset]      ;ds:si = source
        mov     di,[var_command_di_offset]      ;es:di = dst
        mov     cx,80/2                         ;copy 40 words
        rep movsw                               ;do the copy
        cld                                     ;restore forward direction

        mov     [var_command_si_offset],si      ;update source offset
        mov     [var_command_di_offset],di      ;update dst offset
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; cmd_out_sweep_up
cmd_out_sweep_up_init:
        mov     byte [var_command_out_cnt],40   ;bytes to scroll
        mov     ax,80*100-2                     ;last row of video segment
        mov     [var_command_di_offset],ax      ;destination offset
        ret

cmd_out_sweep_up_anim:
        ; scroll up one row
        dec     byte [var_command_out_cnt]
        jnz     .l0
        jmp     cmd_process_next

.l0:
        std                                     ;copy backwards
        sub     ax,ax                           ;color black
        mov     di,[var_command_di_offset]      ;es:di = dst
        mov     cx,80/2                         ;copy 40 words
        rep stosw                               ;do the store
        cld                                     ;restore forward direction

        mov     [var_command_di_offset],di      ;update source offset
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; cmd_fade_out
cmd_fade_out_init:
        mov     byte [var_tmp_db_0],15          ;number of color transitions
        ret

cmd_fade_out_anim:
        ; scroll up one row
        dec     byte [var_tmp_db_0]
        jns     .do
        jmp     cmd_process_next

.do:
        sub     bh,bh
        mov     bl,[var_tmp_db_0]               ;bx transition index
        lea     si,[fadeout_palette_tbl+16+bx]  ;correct index, skipping black colors

        mov     bx,1                            ;start with color 1. color 0 is
                                                ; black, and we are not goig to change it
.loop:  lodsb                                   ;al=new palette color for color #cx
        cmp     al,[palette_fade_prev_val+bx]   ;different than previous color?
        jz      .next_color

        mov     [palette_fade_prev_val+bx],al   ;update new color
        call    change_palette                  ;bl = color index, al = new color

.next_color:
        add     si,15                           ;next color palette. each entry takes 16 bytes
        inc     bx                              ; so add add 15 since lodsb incs si by one
        cmp     bx,16
        jnz     .loop
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; change_palette
; changes one palette color in horizontal retrace
; TODO: convert this function to macro, since it is only called from
; cmd_fade_out_anim
; IN
;       bl = color index
;       al = new color
change_palette:
        mov     bp,bx

        mov     bh,al                           ;save color in bh

        ; wait for horizontal retrace
        mov     dx,0x03da
.wait:
        in      al,dx                           ;wait for horizontal retrace
        ror     al,1
        jc      .wait

.retrace:
        in      al,dx                           ;wait for horizontal retrace
        ror     al,1
        jnc     .retrace

        ; set palette index + new color
        mov     al,bl                           ;color index
        or      al,0x10                         ;index needs to start at 0x10
        out     dx,al                           ;dx=0x03da (register)

        mov     al,bh                           ;set color
        out     dx,al                           ;set new color (data)

        sub     al,al                           ;al = 0 reset
        out     dx,al                           ;reset

        in      al,dx                           ;reset to register again

        mov     bx,bp
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
; cmd_switch_to_160100
cmd_switch_to_160100_init:
        mov     byte [trigger_switch_to_160100],1       ;tell "main thread" to switch to new video mode
        ret


cmd_switch_to_160100_anim:
        cmp     byte [trigger_switch_to_160100],0       ;already switch to 160x100 video mode?
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
; cmd_clean_render_buffer
cmd_clean_render_buffer_init:
        mov     si,[commands_data_idx]
        lodsb                                           ;al = whether or not the render
        mov     [should_clean_pre_render_buffer],al     ; buffer should be cleaned
        mov     [commands_data_idx],si                  ;update index
        jmp     cmd_process_next                        ;no animation... process next command

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; cmd_pre_render_mode
cmd_pre_render_mode_init:
        mov     si,[commands_data_idx]
        lodsb                                           ;al = pre render mode
        mov     [pre_render_mode],al                    ;which drawing method should use
        mov     [commands_data_idx],si                  ;update index
        jmp     cmd_process_next                        ;no animation... process next command

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
; draw_svg_letter_single
; IN:
;       si := vector points
draw_svg_letter_single:
        ; foreground
        mov     al,[svg_letter_shadow_colors+2]         ;color for letter (foreground)
        mov     byte [Line08_color],al
        call    draw_svg_letter
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
        incbin          'part3/uctumi-zamba.pvm'
graphic_lz4:
        incbin          'part3/image_pampa.raw.lz4'

end_condition:
        db              0                       ;if 0, part3 ends

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; SVG drawing related
; poly and line related
poly_prev_point:
        dw              0                       ;cache of previous point
is_poly_previous_point:
        db              0                       ;1 if there is a valid point in poly_prev_point

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
should_clean_pre_render_buffer:
        db              1                       ;boolean. when 1, render buffer will
                                                ; will be cleaned before next render

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
CMD_IN_SWEEP_UP         equ     14
CMD_CLEAN_RENDER_BUFFER equ     15
CMD_OUT_SWEEP_UP        equ     16
CMD_PRE_RENDER_MODE     equ     17
CMD_FADE_OUT            equ     18
CMD_SWITCH_TO_160100    equ     19

;CMD_OUT_SCROLL_LEFT     equ     9
;CMD_OUT_SCROLL_RIGHT    equ     10
;CMD_OUT_SWEEP_LEFT      equ     13
;CMD_OUT_SWEEP_RIGHT     equ     14
;CMD_OUT_SWEEP_PIXEL     equ     15

commands_current_anim:  dw      0               ;address of current anim

commands_data_idx:      dw      0               ;index in commands_data
commands_data:
        db      CMD_WAIT,240                    ;wait 4 seconds
        db      CMD_WAIT,180                    ;wait 3 additional seconds

        db      CMD_SWITCH_TO_160100            ;switch to 160x100 graphics mode

        db      CMD_SHADOW_DIR,0xff,0xff        ;shadow direction
        db      CMD_CLEAN_RENDER_BUFFER,1       ;clean render buffer
        db      CMD_PRE_RENDER_MODE,3           ;3 traces per line

        ; credits =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=;
        db      CMD_WAIT,60
        db      CMD_TRANSLATE,20,20             ;set new x,y
        db      CMD_SCALE,1                     ;scalea for fonts, the bigger, the samller
        db      CMD_ROTATION,0
        db      CMD_CHAR_SPACING,20,0           ;spacing between chars
        db      CMD_SHADOW_PALETTE,8,7,15       ;colos for shadow+foreground
        db      CMD_PRE_RENDER, 'CREDITS',0     ;string in buffer
        db      CMD_IN_SCROLL_DOWN_R,
        db      CMD_OUT_SCROLL_DOWN,
        db      CMD_WAIT,60
        db      CMD_IN_SCROLL_UP,
        db      CMD_WAIT,60
        db      CMD_OUT_SCROLL_UP,
        db      CMD_WAIT,60

        ; part i =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
        db      CMD_TRANSLATE,30,20             ;set new x,y
        db      CMD_SCALE,0                     ;set new scale
        db      CMD_ROTATION,10                 ;set new rotation
        db      CMD_CHAR_SPACING,23,0           ;spacing between chars
        db      CMD_SHADOW_PALETTE,4,12,15      ;colos for shadow+foreground
        db      CMD_PRE_RENDER, 'PART I',0
        db      CMD_IN_SCROLL_UP,
        db      CMD_WAIT,60
        db      CMD_OUT_SCROLL_UP,
        db      CMD_WAIT,60

        ; part i: code & graphics
        db      CMD_TRANSLATE,13,10             ;set new x,y
        db      CMD_SCALE,2                     ;set new scale
        db      CMD_ROTATION,0                  ;set new rotation
        db      CMD_CHAR_SPACING,10,0           ;spacing between chars
        db      CMD_SHADOW_PALETTE,0,9,15       ;colors for shadow+foreground
        db      CMD_PRE_RENDER, 'CODE & GRAPHICS:',0

        db      CMD_CLEAN_RENDER_BUFFER,0       ;don't clean buffer
        db      CMD_SCALE,1                     ;set new scale
        db      CMD_TRANSLATE,66,28             ;set new x,y
        db      CMD_SHADOW_PALETTE,5,13,15      ;colors for shadow+foreground
        db      CMD_CHAR_SPACING,16,0           ;spacing between chars
        db      CMD_PRE_RENDER, 'RIQ',0
        db      CMD_IN_SCROLL_UP,
        db      CMD_WAIT,120


        ; part i: music:
        db      CMD_CLEAN_RENDER_BUFFER,1       ;clean render buffer
        db      CMD_TRANSLATE,60,10             ;set new x,y
        db      CMD_SCALE,2                     ;set new scale
        db      CMD_ROTATION,0                  ;set new rotation
        db      CMD_CHAR_SPACING,10,0           ;spacing between chars
        db      CMD_SHADOW_PALETTE,0,9,15       ;colors for shadow+foreground
        db      CMD_PRE_RENDER, 'MUSIC:',0

        db      CMD_CLEAN_RENDER_BUFFER,0       ;don't clean buffer
        db      CMD_SCALE,1                     ;set new scale
        db      CMD_TRANSLATE,42,28             ;set new x,y
        db      CMD_SHADOW_PALETTE,5,13,15      ;colors for shadow+foreground
        db      CMD_CHAR_SPACING,18,0           ;spacing between chars
        db      CMD_PRE_RENDER, 'UCTUMI',0
        db      CMD_IN_SCROLL_UP,
        db      CMD_WAIT,120


        ; part i: small font:
        db      CMD_CLEAN_RENDER_BUFFER,1       ;clean render buffer
        db      CMD_TRANSLATE,30,10             ;set new x,y
        db      CMD_SCALE,2                     ;set new scale
        db      CMD_ROTATION,0                  ;set new rotation
        db      CMD_CHAR_SPACING,10,0           ;spacing between chars
        db      CMD_SHADOW_PALETTE,0,9,15       ;colors for shadow+foreground
        db      CMD_PRE_RENDER, 'SMALL FONTS:',0

        db      CMD_CLEAN_RENDER_BUFFER,0       ;don't clean buffer
        db      CMD_SCALE,1                     ;set new scale
        db      CMD_SHADOW_PALETTE,5,13,15      ;colors for shadow+foreground
        db      CMD_CHAR_SPACING,14,0           ;spacing between chars
        db      CMD_TRANSLATE,34,28             ;set new x,y
        db      CMD_ROTATION,5                  ;set new rotation
        db      CMD_PRE_RENDER, 'ARLEQUIN',0
        db      CMD_IN_SCROLL_UP,
        db      CMD_WAIT,120

        ; part i: big font:
        db      CMD_CLEAN_RENDER_BUFFER,1       ;clean render buffer
        db      CMD_TRANSLATE,44,12             ;set new x,y
        db      CMD_SCALE,2                     ;set new scale
        db      CMD_ROTATION,0                  ;set new rotation
        db      CMD_CHAR_SPACING,10,0           ;spacing between chars
        db      CMD_SHADOW_PALETTE,0,9,15       ;colors for shadow+foreground
        db      CMD_PRE_RENDER, 'BIG FONTS',0

        db      CMD_CLEAN_RENDER_BUFFER,0       ;don't clean render buffer
        db      CMD_TRANSLATE,46,26             ;set new x,y
        db      CMD_PRE_RENDER, 'BASED ON:',0
        db      CMD_IN_SCROLL_UP,
        db      CMD_WAIT,120

        db      CMD_CLEAN_RENDER_BUFFER,1       ;clean render buffer
        db      CMD_SHADOW_PALETTE,0,13,15      ;colors for shadow+foreground
        db      CMD_SCALE,2
        db      CMD_CHAR_SPACING,9,0            ;spacing between chars
        db      CMD_TRANSLATE,14,12             ;set new x,y
        db      CMD_PRE_RENDER, "ANDREW GLASSNER'S",0

        db      CMD_CLEAN_RENDER_BUFFER,0       ;dont clean render buffer
        db      CMD_TRANSLATE,50,26             ;set new x,y
        db      CMD_PRE_RENDER, 'NOTEBOOK',0
        db      CMD_IN_SCROLL_UP,
        db      CMD_WAIT,120

        ; part ii =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=;
        db      CMD_OUT_SCROLL_UP,
        db      CMD_CLEAN_RENDER_BUFFER,1       ;clean render buffer
        db      CMD_TRANSLATE,18,20             ;set new x,y
        db      CMD_SCALE,0                     ;set new scale
        db      CMD_ROTATION,-5                 ;set new rotation
        db      CMD_CHAR_SPACING,25,0           ;spacing between chars
        db      CMD_SHADOW_PALETTE,2,10,15      ;colos for shadow+foreground
        db      CMD_PRE_RENDER, 'PART II',0
        db      CMD_IN_SWEEP_UP
        db      CMD_WAIT,120
        db      CMD_OUT_SWEEP_UP

        ; part ii: graphics
        db      CMD_TRANSLATE,44,10             ;set new x,y
        db      CMD_SCALE,2                     ;set new scale
        db      CMD_ROTATION,0                  ;set new rotation
        db      CMD_CHAR_SPACING,10,0           ;spacing between chars
        db      CMD_SHADOW_PALETTE,0,9,15       ;colors for shadow+foreground
        db      CMD_PRE_RENDER, 'GRAPHICS:',0

        db      CMD_CLEAN_RENDER_BUFFER,0       ;don't clean buffer
        db      CMD_SCALE,1                     ;set new scale
        db      CMD_ROTATION,2                  ;set new rotation
        db      CMD_TRANSLATE,30,28             ;set new x,y
        db      CMD_SHADOW_PALETTE,5,13,15      ;colors for shadow+foreground
        db      CMD_CHAR_SPACING,18,0           ;spacing between chars
        db      CMD_PRE_RENDER, 'ALAKRAN',0
        db      CMD_IN_SCROLL_UP,
        db      CMD_WAIT,120

        ; part ii: music:
        db      CMD_CLEAN_RENDER_BUFFER,1       ;clean render buffer
        db      CMD_TRANSLATE,58,10             ;set new x,y
        db      CMD_SCALE,2                     ;set new scale
        db      CMD_ROTATION,0                  ;set new rotation
        db      CMD_CHAR_SPACING,10,0           ;spacing between chars
        db      CMD_SHADOW_PALETTE,0,9,15       ;colors for shadow+foreground
        db      CMD_PRE_RENDER, 'MUSIC:',0

        db      CMD_CLEAN_RENDER_BUFFER,0       ;don't clean buffer
        db      CMD_SCALE,1                     ;set new scale
        db      CMD_TRANSLATE,42,28             ;set new x,y
        db      CMD_SHADOW_PALETTE,5,13,15      ;colors for shadow+foreground
        db      CMD_CHAR_SPACING,18,0           ;spacing between chars
        db      CMD_PRE_RENDER, 'UCTUMI',0
        db      CMD_IN_SCROLL_UP,
        db      CMD_WAIT,120


        ; part ii: fonts:
        db      CMD_CLEAN_RENDER_BUFFER,1       ;clean render buffer
        db      CMD_TRANSLATE,60,10             ;set new x,y
        db      CMD_SCALE,2                     ;set new scale
        db      CMD_ROTATION,0                  ;set new rotation
        db      CMD_CHAR_SPACING,10,0           ;spacing between chars
        db      CMD_SHADOW_PALETTE,0,9,15       ;colors for shadow+foreground
        db      CMD_PRE_RENDER, 'FONTS:',0

        db      CMD_CLEAN_RENDER_BUFFER,0       ;don't clean buffer
        db      CMD_SCALE,1                     ;set new scale
        db      CMD_SHADOW_PALETTE,5,13,15      ;colors for shadow+foreground
        db      CMD_CHAR_SPACING,18,0           ;spacing between chars
        db      CMD_TRANSLATE,20,28             ;set new x,y
        db      CMD_ROTATION,0                  ;set new rotation
        db      CMD_PRE_RENDER, 'ARLEQUIN',0
        db      CMD_IN_SCROLL_UP,
        db      CMD_WAIT,120

        ; part ii: code
        db      CMD_CLEAN_RENDER_BUFFER,1       ;clean render buffer
        db      CMD_TRANSLATE,62,10             ;set new x,y
        db      CMD_SCALE,2                     ;set new scale
        db      CMD_ROTATION,0                  ;set new rotation
        db      CMD_CHAR_SPACING,10,0           ;spacing between chars
        db      CMD_SHADOW_PALETTE,0,9,15       ;colors for shadow+foreground
        db      CMD_PRE_RENDER, 'CODE:',0

        db      CMD_CLEAN_RENDER_BUFFER,0       ;don't clean buffer
        db      CMD_SCALE,1                     ;set new scale
        db      CMD_TRANSLATE,66,28             ;set new x,y
        db      CMD_SHADOW_PALETTE,5,13,15      ;colors for shadow+foreground
        db      CMD_CHAR_SPACING,16,0           ;spacing between chars
        db      CMD_PRE_RENDER, 'RIQ',0
        db      CMD_IN_SCROLL_UP,
        db      CMD_WAIT,120

        ; part iii =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
        db      CMD_OUT_SCROLL_UP,
        db      CMD_CLEAN_RENDER_BUFFER,1       ;clean render buffer
        db      CMD_TRANSLATE,18,20             ;set new x,y
        db      CMD_SCALE,0                     ;set new scale
        db      CMD_ROTATION,0                  ;set new rotation
        db      CMD_CHAR_SPACING,25,0           ;spacing between chars
        db      CMD_SHADOW_PALETTE,3,11,15      ;colos for shadow+foreground
        db      CMD_PRE_RENDER, 'PART',0

        db      CMD_TRANSLATE,124,20            ;set new x,y
        db      CMD_CLEAN_RENDER_BUFFER,0       ;don't clean buffer
        db      CMD_CHAR_SPACING,8,0            ;spacing between chars
        db      CMD_PRE_RENDER, 'III',0

        db      CMD_IN_SWEEP_UP
        db      CMD_WAIT,120
        db      CMD_OUT_SWEEP_UP

        ; part iii: music:
        db      CMD_CLEAN_RENDER_BUFFER,1       ;clean render buffer
        db      CMD_TRANSLATE,60,10             ;set new x,y
        db      CMD_SCALE,2                     ;set new scale
        db      CMD_ROTATION,0                  ;set new rotation
        db      CMD_CHAR_SPACING,10,0           ;spacing between chars
        db      CMD_SHADOW_PALETTE,0,9,15       ;colors for shadow+foreground
        db      CMD_PRE_RENDER, 'MUSIC:',0

        db      CMD_CLEAN_RENDER_BUFFER,0       ;don't clean buffer
        db      CMD_SCALE,1                     ;set new scale
        db      CMD_TRANSLATE,42,28             ;set new x,y
        db      CMD_SHADOW_PALETTE,5,13,15      ;colors for shadow+foreground
        db      CMD_CHAR_SPACING,18,0           ;spacing between chars
        db      CMD_PRE_RENDER, 'UCTUMI',0
        db      CMD_IN_SCROLL_UP,
        db      CMD_WAIT,120

        ; part iii: graphics
        db      CMD_CLEAN_RENDER_BUFFER,1       ;clean render buffer
        db      CMD_TRANSLATE,44,10             ;set new x,y
        db      CMD_SCALE,2                     ;set new scale
        db      CMD_ROTATION,0                  ;set new rotation
        db      CMD_CHAR_SPACING,10,0           ;spacing between chars
        db      CMD_SHADOW_PALETTE,0,9,15       ;colors for shadow+foreground
        db      CMD_PRE_RENDER, 'GRAPHICS:',0

        db      CMD_CLEAN_RENDER_BUFFER,0       ;don't clean buffer
        db      CMD_SCALE,1                     ;set new scale
        db      CMD_ROTATION,2                  ;set new rotation
        db      CMD_TRANSLATE,30,28             ;set new x,y
        db      CMD_SHADOW_PALETTE,5,13,15      ;colors for shadow+foreground
        db      CMD_CHAR_SPACING,18,0           ;spacing between chars
        db      CMD_PRE_RENDER, 'ALAKRAN',0
        db      CMD_IN_SCROLL_UP,
        db      CMD_WAIT,120

        ; part iii: code & fonts
        db      CMD_CLEAN_RENDER_BUFFER,1       ;clean render buffer
        db      CMD_TRANSLATE,30,10             ;set new x,y
        db      CMD_SCALE,2                     ;set new scale
        db      CMD_ROTATION,0                  ;set new rotation
        db      CMD_CHAR_SPACING,10,0           ;spacing between chars
        db      CMD_SHADOW_PALETTE,0,9,15       ;colors for shadow+foreground
        db      CMD_PRE_RENDER, 'CODE & FONTS:',0

        db      CMD_CLEAN_RENDER_BUFFER,0       ;don't clean buffer
        db      CMD_SCALE,1                     ;set new scale
        db      CMD_TRANSLATE,66,28             ;set new x,y
        db      CMD_SHADOW_PALETTE,5,13,15      ;colors for shadow+foreground
        db      CMD_CHAR_SPACING,16,0           ;spacing between chars
        db      CMD_PRE_RENDER, 'RIQ',0
        db      CMD_IN_SCROLL_UP,
        db      CMD_WAIT,120
        db      CMD_OUT_SCROLL_UP,

        ; greetings =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=;
        db      CMD_CLEAN_RENDER_BUFFER,1       ;clean render buffer
        db      CMD_WAIT,60
        db      CMD_TRANSLATE,18,20             ;set new x,y
        db      CMD_SCALE,1                     ;scalea for fonts, the bigger, the samller
        db      CMD_ROTATION,0
        db      CMD_CHAR_SPACING,16,0           ;spacing between chars
        db      CMD_SHADOW_PALETTE,8,7,15       ;colos for shadow+foreground
        db      CMD_PRE_RENDER, 'GREETINGS',0   ;string in buffer
        db      CMD_IN_SCROLL_DOWN_R,
        db      CMD_OUT_SCROLL_DOWN,
        db      CMD_WAIT,60
        db      CMD_IN_SCROLL_UP,
        db      CMD_WAIT,60
        db      CMD_OUT_SCROLL_UP,
        db      CMD_WAIT,60

        ; hokuto force, LFT
        ; trixter, brutman,
        ;
        ; k2, genesis project
        ; atlantis, impure
        ;
        ; triad
        ;
        ; greetins: people #1

        db      CMD_CLEAN_RENDER_BUFFER,1       ;clean render buffer
        db      CMD_SCALE,2                     ;set new scale
        db      CMD_ROTATION,0                  ;set new rotation
        db      CMD_CHAR_SPACING,8,0            ;spacing between chars

        db      CMD_TRANSLATE,18,12             ;set new x,y
        db      CMD_SHADOW_PALETTE,0,12,15      ;colors for shadow+foreground
        db      CMD_PRE_RENDER, 'HOKUTO FORCE,',0

        db      CMD_CLEAN_RENDER_BUFFER,0       ;don't clean render buffer

        db      CMD_TRANSLATE,124,12             ;set new x,y
        db      CMD_SHADOW_PALETTE,0,9,15       ;colors for shadow+foreground
        db      CMD_PRE_RENDER, 'LFT,',0

        db      CMD_TRANSLATE,20,29             ;set new x,y
        db      CMD_SHADOW_PALETTE,0,7,15       ;colors for shadow+foreground
        db      CMD_PRE_RENDER, 'TRIXTER,',0

        db      CMD_TRANSLATE,91,29             ;set new x,y
        db      CMD_SHADOW_PALETTE,0,13,15      ;colors for shadow+foreground
        db      CMD_PRE_RENDER, 'BRUTMAN,',0

        db      CMD_IN_SCROLL_UP,
        db      CMD_WAIT,240

        ; greetins: people #2
        db      CMD_CLEAN_RENDER_BUFFER,1       ;clean render buffer
        db      CMD_SCALE,2                     ;set new scale
        db      CMD_ROTATION,0                  ;set new rotation

        db      CMD_TRANSLATE,13,12             ;set new x,y
        db      CMD_SHADOW_PALETTE,0,12,15      ;colors for shadow+foreground
        db      CMD_PRE_RENDER, 'K2,',0

        db      CMD_CLEAN_RENDER_BUFFER,0       ;don't clean render buffer

        db      CMD_TRANSLATE,40,12             ;set new x,y
        db      CMD_SHADOW_PALETTE,0,9,15       ;colors for shadow+foreground
        db      CMD_PRE_RENDER, 'GENESIS PROJECT,',0

        db      CMD_TRANSLATE,24,29             ;set new x,y
        db      CMD_SHADOW_PALETTE,0,7,15       ;colors for shadow+foreground
        db      CMD_PRE_RENDER, 'ATLANTIS,',0

        db      CMD_TRANSLATE,97,29             ;set new x,y
        db      CMD_SHADOW_PALETTE,0,13,15      ;colors for shadow+foreground
        db      CMD_PRE_RENDER, 'IMPURE,',0

        db      CMD_IN_SCROLL_UP,
        db      CMD_WAIT,240

        ; greetins: people #3
        db      CMD_CLEAN_RENDER_BUFFER,1       ;clean render buffer
        db      CMD_SCALE,2                     ;set new scale
        db      CMD_ROTATION,0                  ;set new rotation
        db      CMD_CHAR_SPACING,8,0            ;spacing between chars

        db      CMD_TRANSLATE,5,12              ;set new x,y
        db      CMD_SHADOW_PALETTE,0,12,15      ;colors for shadow+foreground
        db      CMD_PRE_RENDER, 'TRIAD;',0

        db      CMD_CLEAN_RENDER_BUFFER,0       ;don't clean render buffer

        db      CMD_TRANSLATE,56,12             ;set new x,y
        db      CMD_SHADOW_PALETTE,0,9,15       ;colors for shadow+foreground
        db      CMD_PRE_RENDER, 'AND THE REST OF',0
        db      CMD_TRANSLATE,12,29             ;set new x,y
        db      CMD_PRE_RENDER, 'THE C64 & PCJR SCENE',0

        db      CMD_IN_SCROLL_UP,
        db      CMD_WAIT,240
        db      CMD_OUT_SCROLL_UP,
        db      CMD_WAIT,240

        ; bye bye =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=;
        ; down: pungas de

        db      CMD_SCALE,1                     ;set new scale
        db      CMD_ROTATION,1                  ;set new rotation
        db      CMD_CHAR_SPACING,16,0           ;spacing between chars
        db      CMD_PRE_RENDER_MODE,0           ;single trace
        db      CMD_SHADOW_PALETTE,8,7,15       ;colors for shadow+foreground

        db      CMD_CLEAN_RENDER_BUFFER,1       ;clean render buffer
        db      CMD_TRANSLATE,19,9              ;set new x,y
        db      CMD_PRE_RENDER, 'PUNGAS DE',0

        db      CMD_CLEAN_RENDER_BUFFER,0       ;don't clean render buffer

        db      CMD_TRANSLATE,49,29             ;set new x,y
        db      CMD_PRE_RENDER, 'VILLA',0

        db      CMD_IN_SCROLL_DOWN_R

        ; down: villa martelli
        db      CMD_CLEAN_RENDER_BUFFER,1       ;clean render buffer
        db      CMD_TRANSLATE,30,9              ;set new x,y
        db      CMD_PRE_RENDER, 'MARTELLI',0

        db      CMD_CLEAN_RENDER_BUFFER,0       ;don't clean render buffer

        db      CMD_IN_SCROLL_DOWN_R
        db      CMD_OUT_SCROLL_DOWN

        ; up: pungas de
        db      CMD_WAIT,60
        db      CMD_CLEAN_RENDER_BUFFER,1       ;clean render buffer

        db      CMD_TRANSLATE,19,9              ;set new x,y
        db      CMD_PRE_RENDER, 'PUNGAS DE',0

        db      CMD_CLEAN_RENDER_BUFFER,0       ;don't clean render buffer

        db      CMD_TRANSLATE,49,29             ;set new x,y
        db      CMD_PRE_RENDER, 'VILLA',0

        db      CMD_IN_SCROLL_UP

        ; down: villa martelli
        db      CMD_CLEAN_RENDER_BUFFER,1       ;clean render buffer

        db      CMD_TRANSLATE,30,9              ;set new x,y
        db      CMD_PRE_RENDER, 'MARTELLI',0

        db      CMD_IN_SCROLL_UP
        db      CMD_OUT_SCROLL_UP
        db      CMD_WAIT,120

        ; "64k RAM ought to be enough" =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
        ;
        db      CMD_CLEAN_RENDER_BUFFER,1       ;clean render buffer
        db      CMD_SCALE,1                     ;set new scale
        db      CMD_ROTATION,0                  ;set new rotation
        db      CMD_TRANSLATE,11,11             ;set new x,y
        db      CMD_CHAR_SPACING,13,0           ;spacing between chars
        db      CMD_SHADOW_PALETTE,1,9,15      ;colors for shadow+foreground
        db      CMD_PRE_RENDER_MODE,3           ;enable shadow again
        db      CMD_PRE_RENDER, '64K RAM OUGHT',0

        db      CMD_CLEAN_RENDER_BUFFER,0       ;dont clean render buffer
        db      CMD_TRANSLATE,16,29             ;set new x,y
        db      CMD_PRE_RENDER, 'TO BE ENOUGH',0

        db      CMD_IN_SCROLL_DOWN_R
        db      CMD_OUT_SCROLL_DOWN
        db      CMD_WAIT,140
        db      CMD_IN_SCROLL_UP

        db      CMD_WAIT,200
        db      CMD_FADE_OUT
        db      CMD_WAIT,240                    ;wait 4 seconds
        db      CMD_WAIT,120                    ;wait 2 more seconds...
                                                ; and if no key is pressed, show easter egg

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
        dw      cmd_in_scroll_down_init,        cmd_in_scroll_down_anim,; 8
        dw      cmd_in_scroll_down_r_init,      cmd_in_scroll_down_r_anim,      ; 9
        dw      cmd_out_scroll_down_init,       cmd_out_scroll_down_anim,       ; 10
        dw      cmd_char_spacing_init,          cmd_no_anim,            ; 11
        dw      cmd_shadow_palette_init,        cmd_no_anim,            ; 12
        dw      cmd_shadow_dir_init,            cmd_no_anim,            ; 13
        dw      cmd_in_sweep_up_init,           cmd_in_sweep_up_anim,   ; 14
        dw      cmd_clean_render_buffer_init,   cmd_no_anim,            ; 15
        dw      cmd_out_sweep_up_init,          cmd_out_sweep_up_anim,  ; 16
        dw      cmd_pre_render_mode_init,       cmd_no_anim,            ; 17
        dw      cmd_fade_out_init,              cmd_fade_out_anim,      ; 18
        dw      cmd_switch_to_160100_init,      cmd_switch_to_160100_anim       ;19


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

;3rd word for tmp vars
var_command_di_offset:
var_tmp_dw_2:
var_tmp_db_4: db        0
var_tmp_db_5: db        0

; 0 - single
; 1 - zoom
; 2 - ???
; 3 - shadow
; render mode: shadow, zoom, etc.
pre_render_mode:        db      3

; text that should be renderer. ends with 0
text_to_pre_render:
        times   32      db      0

trigger_switch_to_160100:
        db      0                               ;booelan. if 1, tells main thread
                                                ; to switch to 160x100 video mode

trigger_pre_render:
        db      0                               ;boolean. if 1, tells main thread
                                                ; to pre-render text.
                                                ; 0, whne pre-render finished
palette_fade_prev_val:
        db      0,1,2,3,4,5,6,7                 ;palette last known values
        db      8,9,10,11,12,13,14,15

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
; exit
; do clean up and exit
; exit routine should be at the very end since it will overwrite semgent 0x60
; and we don't want to overwrite ourselves
exit:
        call    music_cleanup
        call    irq_8_cleanup

        ;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
        ; easter egg starts here
        ;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

        cli
        ; populate keyboard buffer with 'pvm rulez!' so easter egg
        ; can use it
        cld
        sub     ax,ax
        mov     es,ax                           ;es:di = destination. es=0
        mov     di,0x041e                       ; beginning of keyboard buffer
        mov     si,.scan_ascii_codes
        mov     cx,10
        rep movsw                               ;copy new buffer
        mov     word [es:0x041a],0x001e         ;first char
        mov     word [es:0x041c],0x001e+20      ;last char

        ; once keyboard buffer is populated, now manually init "keyboard test" routine.
        ; cannot jump directly to it because it will reset the keyboard,
        ; so we manually initialize it, and jump just after it cleans the
        ; keyboard buffer.
        ;
        ; Copied from PCjr BIOS 0xf000:0x2980, with changes to make it work
        ; in the demo
        mov     ax,0xf000
        mov     ds,ax                           ;ds = bios segment
        mov     ax,0x0060
        mov     es,ax                           ;es = diag segment
        mov     byte [es:0x04df],1              ;keyboard "k" (0 means keyboard "j")
        mov     byte [es:0x04e0],0xff

        call    diag_unpack_sprites

        ; control break handler
        push    ds
        sub     ax,ax
        mov     ds,ax                           ;ds = 0
        mov     dx,0x31f8                       ;control break handler
        mov     ax,0xf000                       ;f000:f831 -> handler
        mov     word [ds:0x006c],dx             ;offset to int 0x1b
        mov     word [ds:0x006e],ax             ;segment to new int 0x1b
        pop     ds

        ; clean data
        sub     di,di
        mov     cx,0x04db
        sub     al,al
        rep stosb                               ;clean 60:0000 -> 60:04da

        ; setup some internal vars
        mov     byte [es:0x04c8],1              ;avoid box collision check
        mov     byte [es:0x04ca],3              ;foreground color: cyan
        push    es
        mov     ax,0x004c
        mov     es,ax                           ;es = 0x4c
        mov     byte [es:0x0001],0              ;clear some kind of flag
        pop     es
        call    diag_init_video

        sti
        jmp     0xf000:0x29e8                   ;jump to rest of "keyboard diag routine"

;        mov     ax,0x4c00                       ;ricarDOS: load next file
;        int     0x21                            ;DOS: exit to DOS

        ;scan/ascii codes used to populate the keyboard buffer
.scan_ascii_codes:
        dw      0x1950                          ;P
        dw      0x2f56                          ;V
        dw      0x324d                          ;M
        dw      0x3920                          ;space
        dw      0x1352                          ;R
        dw      0x1655                          ;U
        dw      0x264c                          ;L
        dw      0x1245                          ;E
        dw      0x2c5a                          ;Z
        dw      0x0221                          ;!


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; diag_unpack_sprites
; mimics more or less what is in the BIOS... tried calling BIOS with faking
; ret/retf bug something failed. didn't have time to debug. this seems to work
diag_unpack_sprites:
        mov     di,0x04e6
        mov     cx,1600
        xor     ax,ax
        rep stosw
        mov     si,0x2734
        mov     di,0x04e8
        mov     cx,96
l0:
        push    cx
        mov     cx,6
        rep movsb
        pop     cx
        add     di,4
        loop    l0
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; diag_init_video
; mimics more or less what is in the BIOS... tried calling BIOS with faking
; ret/retf bug something failed. didn't have time to debug. this seems to work
diag_init_video:
        mov     bl,2
        mov     bh,3
        mov     al,0x83
        mov     ah,5
        int     0x10
        call    clean_16k

        mov     bl,3
        mov     bh,2
        mov     al,0x83
        mov     ah,5
        int     0x10
        call    clean_16k
        ret

clean_16k:
        push    es
        mov     dx,0xb800
        mov     es,dx
        xor     di,di
        mov     cx,0x2000
        xor     ax,ax
        rep stosw
        pop     es
        ret


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; includes
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
%include 'part3/elipse_table.asm'
%include 'part3/svg_font.asm'
%include 'common/fadeout16.asm'
%include 'common/utils.asm'
%include 'common/music_player.asm'
%include 'common/draw_line_160_100_16color.asm'
%include 'common/lz4_8088.asm'

