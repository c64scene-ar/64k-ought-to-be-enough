;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; "64K RAM Ought to be enough" - Part 1
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

GFX_SEG         equ     0xb800                  ;0x1800 for PCJr with 32k video ram
                                                ;0xb800 for 16k modes
CHAR_OFFSET     equ     (24*8/2)*80             ;start drawing at row 24

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
section .text
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; CODE
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
start:
        cld                                     ;forward direction

        push    cs
        pop     ds                              ;ds=cs
        mov     ax,GFX_SEG
        mov     es,ax                           ;es = GFX segment.
                                                ; should be valid everywhere. if modified
                                                ; use push/pop
        call    intro_init
        call    intro_main_loop
        call    intro_cleanup

        ; set video mode used in next part
        mov     ax,0x0089                       ;320x200x16 mode
        int     0x10                            ;don't clean screen

        mov     ax,0x4c01                       ;ricarDOS: load next file. Don't print anything, just load file.
        int     0x21                            ;DOS: exit

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
intro_init:

        ;init video mode. don't clear screen
        ;display gfx that is already loaded in memory
        mov     ax,0x0088                       ;160x200 16 colors
        int     0x10                            ;don't clean screen

        mov     ax,0x0583                       ;set CPU/CRT pages
        mov     bx,0x0303                       ;use page 3 for video memory/map 0xb800
        int     0x10                            ;page 3 means: starts at 0x0c00 (48k offset)

        call    delete_640

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

        ;init video mode.
        ;display gfx that is already loaded in memory
        mov     ax,0x0004                       ;320x200 4 colors
        int     0x10


        ;init music
        mov     ax,pvm_song                     ;start music offset
        call    music_init                      ;init music

        call    gfx_init

        ; should be the last one to get initialized
        mov     ax,irq_8_handler                ;handler address
        mov     cx,198                          ;horizontal raster line for the IRQ
        jmp     irq_8_init

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; delay
;       in: lenghts of delay
delay:
        push    cx
.l1:
        mov     cx,0x2000
.l0:
        loop    .l0
        dec     bx
        jnz     .l1
        pop     cx
        ret
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; deletes the 0 from 640 converting it to 64
delete_640:

        ;draw diagonal top-left to bottom-right
        mov     di,16
        mov     cx,0                            ;initial values. col
        mov     dx,150                          ;initial values. row
        sub     bx,bx                           ;page 0

.l0:
        mov     ax,0x0c04                       ;draw dot, color red
        int     0x10

        inc     dx                              ;row++
        mov     ax,0x0c04                       ;draw dot, color red
        int     0x10

        inc     dx                              ;row++
        mov     ax,0x0c04                       ;draw dot, color red
        int     0x10

        dec     dx                              ;row--
        dec     dx                              ;row--
        inc     cx                              ;col++
        mov     ax,0x0c04                       ;draw dot, color red
        int     0x10                            ;draw dot

        inc     dx                              ;row++

        call    beep

        dec     di
        jnz     .l0

        ;draw diagonal top-right to bottom-left
        mov     di,16
        mov     cx,16                           ;initial values. col
        mov     dx,150                          ;initial values. row

.l1:
        mov     ax,0x0c04                       ;draw dot, color red
        int     0x10
        inc     dx                              ;row++
        mov     ax,0x0c04                       ;draw dot, color red
        int     0x10

        inc     dx                              ;row++
        mov     ax,0x0c04                       ;draw dot, color red
        int     0x10

        dec     dx                              ;row--
        dec     dx                              ;row--

        dec     cx                              ;col--
        mov     ax,0x0c04                       ;draw dot, color red
        int     0x10                            ;draw dot

        inc     dx                              ;row++

        call    beep

        dec     di
        jnz     .l1

        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; beep
beep:
        push    ax
        push    cx

        mov     al,0b1011_0110
        out     0x43,al

        mov     ax,0x5533
        out     0x42,al
        mov     al,ah
        out     0x42,al

        in      al,0x61
        mov     ah,al
        or      al,3
        out     0x61,al

        mov     cx,0x6000
.delay0:
        loop    .delay0

        mov     al,ah
        out     0x61,al

        mov     cx,0x6000
.delay1:
        loop    .delay1

        pop     cx
        pop     ax
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; draw a big char in the screen.
; only draws the segments that are needed: will turn on/off only the needed
; segments by doing a "diff" (simple xoring masks) of the previous char
;
; IN:
;       si = pointer to table of char to draw
render_bigchar:

        cmp     byte [is_flicker_free],0        ;flicker free enabled?
        jz      .l0                             ; no, so skip

        ; begin: update background color
.wait_retrace:
;        cmp     byte [vert_retrace],0                   ;wait for vertical retrace
;        jz      .wait_retrace
;        mov     byte [vert_retrace],0                   ;clear vert retrace

        mov     dx,0x03da
        mov     cx,[back_fore_color]            ;cx=new color (to be used in xchg later)

        ; change background color to background color
        sub     bx,bx                           ;bx=0 (to be used in xchg later)
        mov     al,0x11                         ;color index = 1
        out     dx,al                           ;dx=0x03da (register)

        mov     al,cl                           ;set color
        out     dx,al                           ;set new color (data)

        xchg    ax,bx                           ;ax = 0
        out     dx,al                           ;reset

        in      al,dx                           ;reset to register again

        ; change foreground color to background color
        sub     bx,bx                           ;bx=0 (to be used in xchg later)
        mov     al,0x10                         ;color index = 0
        out     dx,al                           ;dx=0x03da (register)

        mov     al,cl                           ;fast way to set al with new color
        out     dx,al                           ;set new color (data)

        xchg    ax,bx                           ;fast way to set al to zero
        out     dx,al                           ;update color (register)

        in      al,dx                           ;reset to register again
        ; end: update background color

.l0:
        push    si                                      ;save si for later

        %assign XX 0
        %rep 4                                          ;do it 4 times: 55 segments fit into 64 bits
                mov     ax,[old_segments + XX]          ;read mask of 16-bit
                xor     ax,[si + XX]                    ;xor-it with prev mask
                mov     [segments_to_draw + XX],ax      ;bits that are 'on' are the ones that need to be updated
        %assign XX XX+2
        %endrep


        sub     bx,bx                                   ;index for call table

        %assign XX 0
        %rep 4                                          ;do it 4 times: 55 segments fit in 64 bits
        %push repeat                                    ;push nasm context, needed for local labels
                mov     dx,[segments_to_draw + XX]      ;get mask bit (64-bits mask. 16 at a time)
                mov     ax,[old_segments + XX]          ;whether to call seg_on or seg_off
                mov     cx,16                           ;inner loop: 16 bits
        %$l_inner:
                shr     ax,1                            ;old segs: mask >> 1.
                rcr     dx,1                            ;to draw segs: mask >> 1 (save last previous state in MSB)
                jnc     %$do_nothing                    ; if 0, skip, do nothing

                push    cx                              ;save cx/ax, since they are used in the draw routines
                push    ax
                push    ds

                test    dx,0b10000000_00000000          ;MSB from old_segments
                jnz     %$turn_off                      ;do the opposite: if old was on, turn it off
                call    [seg_on_call_table + bx]        ;turn segment on
                jmp     %$l0
        %$turn_off:
                call    [seg_off_call_table + bx]       ;turn segment off
        %$l0:
                pop     ds
                pop     ax                              ;restore cx/ax
                pop     cx

        %$do_nothing:
                inc     bx                              ;update pointer to next segment to call
                inc     bx
                loop    %$l_inner
        %pop                                            ;pop context
        %assign XX XX+2
        %endrep

        pop     si                                      ;contains pointer to char to draw

        %assign XX 0
        %rep 4                                          ;do it 4 times: 55 segments fit in 64 bits
                mov     ax,[si + XX]                    ;update old_segments
                mov     [old_segments + XX],ax
        %assign XX XX+2
        %endrep

        cmp     byte [is_flicker_free],0                ;flicker free?
        jz      .end                                    ; no, so skip it

        ; begin: update background / foreground color
        call    wait_vertical_retrace
;.l1:    cmp     byte [vert_retrace],0                   ;wait for vertical retrace
;        jz      .l1
;        mov     byte [vert_retrace],0                   ;clear vert retrace
;        mov     dx,0x03da

        sub     bx,bx                                   ;to be used later
        mov     cx,[back_fore_color]                    ;background / foreground colors
        mov     al,0x10                                 ;color index = 0
        out     dx,al                                   ;dx=0x03da (register)

        mov     al,cl                                   ;background color
        out     dx,al                                   ;set new color (data)

        xchg    ax,bx                                   ;ax = 0
        out     dx,al                                   ;reset

        in      al,dx                                   ;reset to register again

        mov     al,0x11                                 ;color index = 1
        out     dx,al                                   ;dx=0x03da (register)

        mov     al,ch                                   ;foreground color
        out     dx,al                                   ;update color (register)

        xchg    ax,bx                                   ;ax = 0
        out     dx,al                                   ;reset

        in      al,dx                                   ;reset to register again
        ; end: update background / foreground color

.end:
        ret


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
intro_cleanup:
        call    irq_8_cleanup
        jmp     music_cleanup

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
intro_main_loop:
.main_loop:
        ;key pressed?
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
        jnz     .exit                           ;exit if

        cmp     byte [bigchar_to_render],0      ;is there any bigchar to render?
        jnz     .render_char

        cmp     byte [end_condition],0          ;animation finished?
        jz      .main_loop                      ;no, so keep looping

.exit:
        ret                                     ;exit main loop.

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.render_char:
        sub     bh,bh                           ;ah = 0. ax will be used
        mov     bl,byte [bigchar_to_render]
        sub     bl,0x20                         ;char table starts at 0x20 (ascii fo space)

        shl     bx,1                            ;pow(ax,3) == ax * 8
        shl     bx,1                            ; since each entry takes 8 bytes
        shl     bx,1                            ; up to 64 segments each
        lea     si,[table_space+bx]
        call    render_bigchar

        mov     al,[bigchar_to_render]
        call    render_smallchar                ;render small char after big char so they are in sync

        mov     byte [bigchar_to_render],0      ;trigger that the char has been rendered
        jmp     .main_loop

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; IN:
;    al = char to render
render_smallchar:
        mov     bl,al                           ;move al into bl
        sub     bh,bh
        sub     bl,0x20                         ;reset offset to 0, since charset starts at 0x20
        mov     cl,4
        shl     bx,cl                           ;multiply by 16, since each char takes 16 bytes

        mov     ax,8192-2                       ;constant used for "add" (reg faster than imm)
        mov     cx,8192+2-80                    ;constant used for "sub" (reg faster than imm)

        lea     si,[charset + bx]               ;calculate source
        mov     di,[char_offset]                ;get destintation
        movsw                                   ;copy 1st row (2 bytes)
        add     di,ax
        movsw                                   ;copy 2nd row (2 bytes)
        sub     di,cx
        movsw                                   ;copy 3rd row (2 bytes)
        add     di,ax
        movsw                                   ;copy 4th row (2 bytes)
        sub     di,cx
        movsw                                   ;copy 5th row (2 bytes)
        add     di,ax
        movsw                                   ;copy 6th row (2 bytes)
        sub     di,cx
        movsw                                   ;copy 7th row (2 bytes)
        add     di,ax
        movsw                                   ;copy 8th row (2 bytes)

        add     word [char_offset],2            ;update cursor for next char

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
        call    text_writer_update

        inc     byte [vert_retrace]             ;flag that a vert retrace occurred

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
gfx_init:
        ; default palette for the 4 CGA colors
        ;call    wait_vertical_retrace
        mov     dx,0x03da
        mov     si,palette_default
        mov     bl,0x10                         ;first color
        sub     di,di                           ;used to xchg with ax
                                                ; (faster way to set ax to 0)
        mov     cx,4                            ;update 4 colors
.l0:
        mov     al,bl                           ;color to update
        out     dx,al                           ;dx=0x03da (register)

        lodsb
        out     dx,ax                           ;color

        xchg    ax,di                           ;fatest way to set al to 0
        out     dx,al                           ;(register)

        in      al,dx                           ;reset to register again
        inc     bl                              ;next color

        loop    .l0

        ; erase bottom line for text writer
        call    text_writer_clean_bottom_line

        ; update some vars
        mov     word [char_offset],CHAR_OFFSET  ;start drawing at row 24
        mov     byte [text_writer_delay],1      ;wait one frame
                                                ; before rendering next char
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
text_writer_update:
        dec     byte [text_writer_delay]
        jz      .l0
        ret
.l0:
        mov     byte [text_writer_delay],7      ;wait a few cycles
.read_char:
        ;bx is being used later, don't overwrite it
        mov     bx, word [text_writer_offset]
        inc     word [text_writer_offset]
        mov     al, [text_writer_msg + bx]

        mov     cl,al                           ;save al in bl, to be used if drawing char
        or      al,al                           ;al == 0? last char ?
        jz      .start_again
        dec     al                              ;al == 1?
        jz      text_writer_clean_bottom_line
        dec     al                              ;al == 2?
        jz      .disable_flicker_free
        dec     al                              ;al == 3?
        jz      .enable_flicker_free
        dec     al                              ;al == 4?
        jz      .change_palette
        dec     al                              ;al == 5?
        jz      .set_horizontal_pos
        dec     al                              ;al == 6?
        jz      .set_delay

        ;fall-through. draw char
.write:
        mov     [bigchar_to_render],cl
        ret

.enable_flicker_free:
        mov     byte [is_flicker_free],1        ;enable flicker free
        jmp     .read_char                      ;read next char

.disable_flicker_free:
        mov     byte [is_flicker_free],0        ;disable flicker free
        jmp     .read_char                      ;read next char

.change_palette:
        ;bx contains index, re-use it
        inc     word [text_writer_offset]       ;update index to text
        inc     bx                              ;update bx (used as index)
        mov     bl,[text_writer_msg + bx]       ;get palette index
        sub     bh,bh                           ;MSB of bx is 0
        shl     bx,1                            ;each palette entry takes 2 bytes
        mov     cx,[palette_tbl + bx]
        mov     [back_fore_color],cx            ;replace palette with new one
        jmp     .read_char                      ;read next char

.set_horizontal_pos:
        ;bx contains index, re-use it
        inc     word [text_writer_offset]       ;update index to text
        inc     bx                              ;update bx (used as index)
        mov     al,[text_writer_msg + bx]       ;get new horizontal position
        sub     ah,ah                           ;ax contains new pos
        shl     ax,1                            ;multiply by 2: each char takes 2 bytes
                                                ; 1 pixels == 2 bits
        add     ax,CHAR_OFFSET                  ;update offset
        mov     word [char_offset], ax
        jmp     .read_char                      ;read next char

.set_delay:
        mov     byte [text_writer_delay],30     ;sets a half-a-second delay
        ret                                     ;dont' read next char, since it will reset
                                                ; the delay

.start_again:
        mov     byte [end_condition],1          ;end animation
        ;mov     word [text_writer_offset],0     ;reset offset
        ; fall-through to text_writer_clean_bottom_line

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
text_writer_clean_bottom_line:
        mov     di,CHAR_OFFSET
        mov     word [char_offset],di           ;reset destination for char
        mov     cx,40*4
        mov     ax,0b10101010_10101010          ;clear color is 0b10
        rep stosw

        mov     di,CHAR_OFFSET + 8192
        mov     cx,40*4
        rep stosw
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; Rest of code: includes
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
%include 'common/utils.asm'
%include 'common/music_player.asm'
%include 'part1/segment55_data.asm'
%include 'part1/segment55_table.asm'

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; DATA
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; music
pvm_song:
        incbin 'part1/uctumi-cumparsita.pvm'

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; vars
end_condition:          db 0                    ;when 1, banner animation sequence finishes

bigchar_to_render:      db 0                    ;when 0, render finished/not needed. else, contains the ASCII to be rendered

is_flicker_free:        db 1                    ;whether or not foreground color is the same as background
                                                ; while painting big char to prevent
                                                ; flicker-free drawing
vert_retrace:           db 0                    ;a verticla retrace have just occurred
palette_default:        db 0, 15, 0, 15         ;black/white, black/white
back_fore_color:        dw 0x000f               ;background / foreground colors
                                                ; used for the big letters

                                                ;   background/foreground
palette_tbl:            dw 0x000f               ;0: white/black
                        dw 0x010f               ;1: white/blue
                        dw 0x0400               ;2: black/red
                        dw 0x0d0b               ;3: magenta/cyan
                        dw 0x0e09               ;4: yellow/blue
                        dw 0x090e               ;5: blue/yellow
                        dw 0x0c08               ;6: red/gray
                        dw 0x080c               ;7: gray/red
                        dw 0x0a05               ;8: green/dark magenta
                        dw 0x050a               ;9: dark magenta/green
                        dw 0x010c               ;10: dark blue/red
                        dw 0x0c01               ;11: red/dark blue
                        dw 0x030e               ;12: dark cyan/yellow
                        dw 0x0e03               ;13: yellow/dark cyan
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
old_segments:
        dw 0,0,0,0

segments_to_draw:
        dw 0,0,0,0

seg_on_call_table:
        dw segment_0_on
        dw segment_1_on
        dw segment_2_on
        dw segment_3_on
        dw segment_4_on
        dw segment_5_on
        dw segment_6_on
        dw segment_7_on
        dw segment_8_on
        dw segment_9_on
        dw segment_10_on
        dw segment_11_on
        dw segment_12_on
        dw segment_13_on
        dw segment_14_on
        dw segment_15_on
        dw segment_16_on
        dw segment_17_on
        dw segment_18_on
        dw segment_19_on
        dw segment_20_on
        dw segment_21_on
        dw segment_22_on
        dw segment_23_on
        dw segment_24_on
        dw segment_25_on
        dw segment_26_on
        dw segment_27_on
        dw segment_28_on
        dw segment_29_on
        dw segment_30_on
        dw segment_31_on
        dw segment_32_on
        dw segment_33_on
        dw segment_34_on
        dw segment_35_on
        dw segment_36_on
        dw segment_37_on
        dw segment_38_on
        dw segment_39_on
        dw segment_40_on
        dw segment_41_on
        dw segment_42_on
        dw segment_43_on
        dw segment_44_on
        dw segment_45_on
        dw segment_46_on
        dw segment_47_on
        dw segment_48_on
        dw segment_49_on
        dw segment_50_on
        dw segment_51_on
        dw segment_52_on
        dw segment_53_on
        dw segment_54_on

seg_off_call_table:
        dw segment_0_off
        dw segment_1_off
        dw segment_2_off
        dw segment_3_off
        dw segment_4_off
        dw segment_5_off
        dw segment_6_off
        dw segment_7_off
        dw segment_8_off
        dw segment_9_off
        dw segment_10_off
        dw segment_11_off
        dw segment_12_off
        dw segment_13_off
        dw segment_14_off
        dw segment_15_off
        dw segment_16_off
        dw segment_17_off
        dw segment_18_off
        dw segment_19_off
        dw segment_20_off
        dw segment_21_off
        dw segment_22_off
        dw segment_23_off
        dw segment_24_off
        dw segment_25_off
        dw segment_26_off
        dw segment_27_off
        dw segment_28_off
        dw segment_29_off
        dw segment_30_off
        dw segment_31_off
        dw segment_32_off
        dw segment_33_off
        dw segment_34_off
        dw segment_35_off
        dw segment_36_off
        dw segment_37_off
        dw segment_38_off
        dw segment_39_off
        dw segment_40_off
        dw segment_41_off
        dw segment_42_off
        dw segment_43_off
        dw segment_44_off
        dw segment_45_off
        dw segment_46_off
        dw segment_47_off
        dw segment_48_off
        dw segment_49_off
        dw segment_50_off
        dw segment_51_off
        dw segment_52_off
        dw segment_53_off
        dw segment_54_off

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
char_offset:
        dw 0                                    ;offset used to render a char
                                                ; from the charset
charset:
        incbin 'part1/charset_0x20_0x60.bin'      ;the charset already expanded for mode 320x200 @ 4 colors

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
text_writer_delay:
        db 0                                    ;ticks to wait until next char it written
text_writer_offset:
        dw 0                                    ;offset in the text. next char to be written
text_writer_msg:

TEXT_CMD_CLEAR_LINE equ 1
TEXT_CMD_FLICKER_FREE_OFF equ 2
TEXT_CMD_FLICKER_FREE_ON equ 3
TEXT_CMD_CHANGE_PALETTE equ 4
TEXT_CMD_START_POS equ 5
TEXT_CMD_DELAY equ 6

           ;0123456789012345678901234567890123456789
;        db 2                                            ;turn off "flicker-free"
;        db '$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%',1
;        db 3                                            ;re-enable "flicker-free"
        db TEXT_CMD_START_POS,8                         ;set start pos
           ;0123456789012345678901234567890123456789
        db         'PUNGAS DE VILLA MARTELLI '
        db TEXT_CMD_DELAY,TEXT_CMD_CLEAR_LINE

        db TEXT_CMD_START_POS,16                         ;set start pos
           ;0123456789012345678901234567890123456789
        db                 'PRESENTS '
        db TEXT_CMD_DELAY,TEXT_CMD_DELAY,TEXT_CMD_CLEAR_LINE

        db TEXT_CMD_START_POS,8                         ;set start pos
           ;0123456789012345678901234567890123456789
        db         'A DEMO FOR THE '
        db TEXT_CMD_CHANGE_PALETTE,1                    ;set palette blue/black
        db                         'IBM PCJR%& '
        db TEXT_CMD_DELAY,TEXT_CMD_CLEAR_LINE
        db TEXT_CMD_CHANGE_PALETTE,0                    ;set palette black/white

        db TEXT_CMD_START_POS,15                        ;set start pos
           ;0123456789012345678901234567890123456789
        db                '%&ANY PCJR '
        db TEXT_CMD_DELAY,TEXT_CMD_CLEAR_LINE

        db TEXT_CMD_START_POS,3                         ;set start pos
           ;0123456789012345678901234567890123456789
        db    'INCLUDING THE 64K-RAM-ONLY VERSION '
        db TEXT_CMD_DELAY,TEXT_CMD_CLEAR_LINE

        db TEXT_CMD_START_POS,8                         ;set start pos
           ;0123456789012345678901234567890123456789',
        db         'WHICH HAPPENS TO BE%& '
        db TEXT_CMD_DELAY,TEXT_CMD_CLEAR_LINE

        db TEXT_CMD_START_POS,9                         ;set start pos
           ;0123456789012345678901234567890123456789',
        db          '%&THE SLOWEST PC EVER! '
        db TEXT_CMD_START_POS,30
        db '! '
        db TEXT_CMD_START_POS,30
        db '! '
        db TEXT_CMD_START_POS,30
        db '! '
        db TEXT_CMD_START_POS,30
        db '! '
        db TEXT_CMD_START_POS,30
        db '! '
        db TEXT_CMD_START_POS,30
        db '! '
        db TEXT_CMD_DELAY,TEXT_CMD_CLEAR_LINE


        db TEXT_CMD_START_POS,4                         ;set start pos
           ;0123456789012345678901234567890123456789',
        db     'EVEN SLOWER THAN THE IBM PC 5150 '
        db TEXT_CMD_DELAY, TEXT_CMD_DELAY, TEXT_CMD_CLEAR_LINE

        db TEXT_CMD_START_POS,18                        ;set start pos
           ;0123456789012345678901234567890123456789',
        db                   'AND%& '
        db TEXT_CMD_DELAY,TEXT_CMD_DELAY,TEXT_CMD_CLEAR_LINE
           ;0123456789012345678901234567890123456789',
        db 'DID YOU KNOW THAT EVEN THE COMMODORE 64 '
        db TEXT_CMD_DELAY,TEXT_CMD_CLEAR_LINE

        db 'HAS MORE MEMORY THAN THE 64K-ONLY PCJR? '
        db TEXT_CMD_DELAY,TEXT_CMD_CLEAR_LINE

        db TEXT_CMD_START_POS,10                         ;set start pos
           ;0123456789012345678901234567890123456789',
        db           'LET ME SAY THAT AGAIN: '
        db TEXT_CMD_DELAY
        db TEXT_CMD_START_POS,10                         ;set start pos
        db           '                      '
        db TEXT_CMD_CLEAR_LINE

        db TEXT_CMD_CHANGE_PALETTE,2
           ;0123456789012345678901234567890123456789',
        db ' THE 64K-RAM-ONLY PCJR IS SO BAD THAT%& '
        db TEXT_CMD_DELAY,TEXT_CMD_CLEAR_LINE

           ;0123456789012345678901234567890123456789',
        db '  EVEN THE C64 HAS MORE USABLE MEMORY! '
        db TEXT_CMD_DELAY,TEXT_CMD_CLEAR_LINE
        db TEXT_CMD_CHANGE_PALETTE,0

        db TEXT_CMD_START_POS,2                         ;set start pos
           ;0123456789012345678901234567890123456789',
        db   'ON THE POSITIVE SIDE THE PCJR HAS%& '
        db TEXT_CMD_DELAY
        db TEXT_CMD_CLEAR_LINE

        db TEXT_CMD_START_POS,2                         ;set start pos
           ;0123456789012345678901234567890123456789',
        db   '%&A 320 X 200 @ 16-COLOR VIDEO MODE '
        db TEXT_CMD_DELAY
        db TEXT_CMD_CLEAR_LINE


           ;0123456789012345678901234567890123456789',
        db 2                                    ;turn off "flicker-free"
        db '$#$#$#$#$#$#$#$#$#$#$#$#$#$#$#$#$#$#$#$#',1         ;bat animation
        db 3                                    ;turn on "flicker-free" again

        db 1                                    ;clean line

        db TEXT_CMD_START_POS,8                         ;set start pos
        dw 0x0104                                       ;change palette
        db 'P'
        dw 0x0304                                       ;change palette
        db 'U'
        dw 0x0504                                       ;change palette
        db 'N'
        dw 0x0c04
        db 'G'
        dw 0x0204
        db 'A'
        dw 0x0404
        db 'S'
        dw 0x0004
        db ' '
        dw 0x0104                                       ;change palette
        db 'D'
        dw 0x0304                                       ;change palette
        db 'E'
        dw 0x0504                                       ;change palette
        db ' '
        dw 0x0c04
        db 'V'
        dw 0x0204
        db 'I'
        dw 0x0404
        db 'L'
        dw 0x0604
        db 'L'
        dw 0x0004
        db 'A'  
        dw 0x0504                                       ;change palette
        db ' '
        dw 0x0104                                       ;change palette
        db 'M'
        dw 0x0304                                       ;change palette
        db 'A'
        dw 0x0504                                       ;change palette
        db 'R'
        dw 0x0c04
        db 'T'
        dw 0x0204
        db 'E'
        dw 0x0404
        db 'L'
        dw 0x0404
        db 'L'
        dw 0x0604
        db 'I'
        dw 0x0004
        db ' '

        db TEXT_CMD_DELAY
        db TEXT_CMD_DELAY
        db TEXT_CMD_DELAY
        db 0
