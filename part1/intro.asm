; Invite intro for Flashparty 2018
; Pungas de Villa Martelli - http://pungas.space
;
; code: riq (http://retro.moe)

bits    16
cpu     8086

extern irq_8_cleanup, irq_8_init
extern wait_vertical_retrace

%include 'part1/externs.inc'

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; MACROS
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
%define DEBUG 0                                 ;0=diabled, 1=enabled
%define EMULATOR 0                              ;1=run on emulator

GFX_SEG         equ     0xb800                  ;0x1800 for PCJr with 32k video ram
                                                ;0xb800 for 16k modes
CHAR_OFFSET     equ     (24*8/2)*80             ;start drawing at row 24

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; CODE
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
..start:
        resb    0x100                           ;cannot use "org 0x100" when using multiple .o files
        cld                                     ;forward direction

        mov     ax,cs
        mov     ds,ax                           ;ds = cs
        mov     ax,GFX_SEG
        mov     es,ax                           ;es = GFX segment.
                                                ; should be valid everywhere. if modified
                                                ; use push/pop
        call    intro_init
        call    intro_main_loop
        call    intro_cleanup

        sub     ax,ax                           ;don't clear screen in ricarDOS
        int     0x20                            ; and load next part

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
intro_init:
        
        mov     ax,0x0004                       ;320x200 4 colors
        int     0x10

%if EMULATOR
%else
        mov     al,0xa0
        out     0xf2,al                         ;turn off floppy motor
%endif

        call    music_init
        call    gfx_init

        ; should be the last one to get initialized
        mov     ax,intro_irq_8_handler
        jmp     irq_8_init


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; draw a big char in the screen.
; only draws the segments that are needed: will turn on/off only the needed
; segments by doing a "diff" (simple xoring masks) of the previous char
;
; IN:
;       si = pointer to table of char to draw
render_bigchar:

        ; begin: update background color
        call    wait_vertical_retrace

        cmp     byte [is_flicker_free],0        ;flicker free enabled?
        jz      .l0                             ; no, so skip

        sub     bx,bx                           ;bx=0 (to be used in xchg later)
        mov     cx,[back_fore_color]            ;cx=new color (to be used in xchg later)
        mov     al,0x11                         ;color index = 1
        out     dx,al                           ;dx=0x03da (register)

        xchg    ax,cx                           ;fast way to set al with new color
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
        jz      .l1                                     ; no, so skip it

        ; begin: update background / foreground color
        call    wait_vertical_retrace
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

.l1:
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
        sub     ah,ah                           ;ah = 0. ax will be used
        mov     al,byte [bigchar_to_render]
        sub     al,0x20                         ;char table starts at 0x20 (ascii fo space)

        mov     bx,ax                           ;each entry takes 8 bytes
        shl     ax,1                            ; pow(ax,3) == ax * 8
        shl     ax,1
        shl     ax,1
        mov     si,table_space                  ;si contains the base for the table
        add     si,ax                           ;si contains the base + offset
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
intro_irq_8_handler:
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
music_init:
        in      al,0x61                         ;PCJr only:
        or      al,0b0110_0000                  ; source for music is the SN76496
        out     0x61,al

        mov     word [pvm_offset],pvm_song + 0x10       ;update start offset
        sub     al,al
        mov     byte [pvm_wait],al              ;don't wait at start
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
music_cleanup:
        mov     si,volume_0                     ;volume to 0 data
        mov     cx,VOLUME_0_MAX
.repeat:
        lodsb
        out     0xc0,al                         ;set volume to 0
        loop    .repeat

        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
music_play:

MUSIC_DATA              equ 0b0000_0000
MUSIC_DATA_EXTRA        equ 0b0010_0000
MUSIC_DELAY             equ 0b0100_0000
MUSIC_DELAY_EXTRA       equ 0b0110_0000
MUSIC_END               equ 0b1000_0000

        sub     cx,cx                           ;cx=0... needed later
        mov     si,[pvm_offset]

        cmp     byte [pvm_wait],0
        je      .l0

        dec     byte [pvm_wait]
        ret

.l0:
        lodsb                                   ;fetch command byte
        mov     ah,al
        and     al,0b1110_0000                  ;al=command only
        and     ah,0b0001_1111                  ;ah=command args only

        cmp     al,MUSIC_DATA                   ;data?
        je      .is_data
        cmp     al,MUSIC_DATA_EXTRA             ;data extra?
        je      .is_data_extra
        cmp     al,MUSIC_DELAY                  ;delay?
        je      .is_delay
        cmp     al,MUSIC_DELAY_EXTRA            ;delay extra?
        je      .is_delay_extra
        cmp     al,MUSIC_END                    ;end?
        je      .is_end

.unsupported:
        int 3
        mov     [pvm_offset],si                 ;save offset
        ret


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.is_data:
        mov     cl,ah                           ;ch is already zero
        jmp     .repeat

.is_data_extra:
        lodsb                                   ;fetch lenght from next byte
        mov     cl,al
.repeat:
        lodsb
        out     0xc0,al                         ;play music

        loop    .repeat

        jmp     .l0                             ;repeat... fetch next command


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.is_delay:
        dec     ah                              ;minus one, since we are returning
        mov     [pvm_wait],ah                   ; from here now
        mov     [pvm_offset],si
        ret

.is_delay_extra:
        lodsb                                   ;fetch wait from next byte
        dec     al                              ;minus one, since we are returning
        mov     [pvm_wait],al                   ; from here now
        mov     [pvm_offset],si
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.is_end:
        mov     ax,[pvm_song + 0xc]             ;offset loop relative to start of data
        add     ax,pvm_song + 0x10              ;add header size
        mov     word [pvm_offset],ax            ;update new offset with loop data
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
gfx_init:
        ; default palette for the 4 CGA colors
        call    wait_vertical_retrace
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
        mov     byte [text_writer_delay],30     ;wait about .5 seconds
                                                ; before rendering next char

        ; draw big char
        mov     si,table_percent                ;prepare logo to draw
        call    render_bigchar                  ;draw it

        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
text_writer_update:
        dec     byte [text_writer_delay]
        jz      .l0
        ret
.l0:
        mov     byte [text_writer_delay],7      ;wait a few cycles
.read_char:
        mov     bx, word [text_writer_offset]
        inc     word [text_writer_offset]
        mov     al, [text_writer_msg + bx]
        mov     bl,al                           ;save al in bl, to be used if drawing char
        or      al,al                           ;al == 2? last char ?
        jz      .start_again
        dec     al                              ;al == 1?
        jz      text_writer_clean_bottom_line
        dec     al                              ;al == 2?
        jz      .disable_flicker_free
        dec     al                              ;al == 3?
        jz      .enable_flicker_free

        ;fall-through. draw char
.write:
        mov     [bigchar_to_render],bl
        ret

.enable_flicker_free:
        mov     byte [is_flicker_free],1        ;enable flicker free
        jmp     .read_char                      ;read next char

.disable_flicker_free:
        mov     byte [is_flicker_free],0        ;disable flicker free
        jmp     .read_char                      ;read next char

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
;
; DATA
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; song related
pvm_song:
        incbin 'part1/uctumi-song.pvm'
pvm_wait:                                       ;cycles to read divided 0x2df
        db 0
pvm_offset:                                     ;pointer to next byte to read
        dw 0
volume_0:
        db      0b1001_1111                     ;vol 0 channel 0
        db      0b1011_1111                     ;vol 0 channel 1
        db      0b1101_1111                     ;vol 0 channel 2
        db      0b1111_1111                     ;vol 0 channel 3
VOLUME_0_MAX equ $ - volume_0

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; vars
end_condition:          db 0                    ;when 1, banner animation sequence finishes

bigchar_to_render:      db 0                    ;when 0, render finished/not needed. else, contains the ASCII to be rendered

is_flicker_free:        db 1                    ;whether or not foreground color is the same as background
                                                ; while painting big char to prevent
                                                ; flicker-free drawing

palette_default:        db 0, 15, 0, 15         ;black/white, black/white
back_fore_color:        dw 0x000f               ;background / foreground colors
                                                ; used for the big letters

back_fore_idx:          db 0                    ;index to the back_fore_tbl
back_fore_tbl:          db 0, 15
                        db 1, 2
                        db 3, 4
                        db 5, 6
TOTAL_BACK_FORE         equ ($-back_fore_tbl)/2
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
           ;0123456789012345678901234567890123456789
        db 2                                            ;turn off "flicker-free"
        db '$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%',1
        db 3                                            ;re-enable "flicker-free"
        db '        PUNGAS DE VILLA MARTELLI        ',1
        db '                PRESENTS                ',1
        db 'AN INVITE INTRO FOR PCJR AND TANDY 1000.',1
        db '  WE INVITE YOU TO THE FLASHPARTY 2018  ',1
        db '            SEPTEMBER 21,22,23          ',1
        db 'TO BE HOSTED IN BUENOS AIRES, ARGENTINA.',1
        db '         (SOUTH OF SOUTH AMERICA)       ',1
        db '        REMOTE ENTRIES ARE WELCOME!     ',1
        db 'GREETINGS TO: XXX,YYY,ZZZ,AAA,BBB,CCC   ',1
        db 'DID WE MENTION THIS INVITE-INTRO RUNS IN',1
        db 'UNEXPANDED PCJR (ONLY 64KB RAM NEEDED!)?',1
        db 2                                            ;turn off "flicker-free"
        db '$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%',1
        db 0

