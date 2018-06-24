; Invite intro for Flashparty 2018
; Pungas de Villa Martelli - http://pungas.space
;
; code: riq (http://retro.moe)

bits    16
cpu     8086

extern irq_8_cleanup, irq_8_init
extern wait_vertical_retrace

%include 'src/externs.inc'

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; MACROS
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
%define DEBUG 0                                 ;0=diabled, 1=enabled
%define EMULATOR 0                              ;1=run on emulator

GFX_SEG         equ     0xb800                  ;0x1800 for PCJr with 32k video ram
                                                ;0xb800 for 16k modes
CHAR_OFFSET     equ     (24*8/2)*80             ;start drawing at row 24

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; refreshes the palette. used as a macro, and not function, since it is being
; called from time-critical sections
;
; Args:
;       #1:     -> color to use
%macro SET_PALETTE 1
        call    wait_vertical_retrace
        sub     bx,bx                           ;bx=0 (to be used in xchg later)
        mov     cx,%1                           ;cx=new color (to be used in xchg later)
        ;mov     dx,0x03da                      ;address
        mov     al,0x11                         ;color index = 1
        out     dx,al                           ;dx=0x03da (register)

        xchg    ax,cx                           ;fast way to set al with new color
        out     dx,al                           ;set new color (data)

        xchg    ax,bx                           ;fast way to set al to zero
        out     dx,al                           ;update color (register)

        in      al,dx                           ;reset to register again
%endmacro
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; CODE
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
..start:
        resb    0x100                           ;cannot use "org 0x100" when using multiple .o files
        cld                                     ;forward direction

        cli                                     ;disable interrupt while changing the stack
        mov     ax,cs                           ;ds,sp = cs
        mov     ds,ax

        mov     ss,ax
        mov     ax,0x100
        mov     sp,ax                           ;stack starts at cs:0x100

        mov     ax,GFX_SEG                      ;through the whole intro.
        mov     es,ax                           ;push/pop otherwise

        call    banner_init
        call    banner_main_loop
        call    banner_cleanup

        int     0x20                            ;exit to DOS

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
banner_init:
        mov     ax,0x0004                       ;320x200 4 colors
        int     0x10

        mov     ax,banner_irq_8
        call    irq_8_init

        call    music_init

        mov     word [char_offset],CHAR_OFFSET  ;start drawing at row 24

        ret


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; draw a big char in the screen.
; only draws the segments that are needed: will turn on/off only the needed
; segments by doing a "diff" (simple xoring masks) of the previous char
;
; IN:
;       si = pointer to table of char to draw
draw_bigchar:

        SET_PALETTE 0

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

        SET_PALETTE 15

        ret


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
banner_cleanup:
        call    irq_8_cleanup
        call    music_cleanup
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
banner_main_loop:

.main_loop:
        cmp     byte [bigchar_to_render],0      ;is there any bigchar to render?
        jnz     .render_bigchar

        cmp     byte [end_condition],0          ;animation finished?
        jnz     .exit                           ; yes, end

        call    key_pressed                     ;key pressed?
        jz      .main_loop                      ; no, keep looping

.exit:
        ret                                     ;exit main loop.

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.render_bigchar:
        sub     ah,ah                           ;ah = 0. ax will be used
        mov     al,byte [bigchar_to_render]
        sub     al,0x20                         ;char table starts at 0x20 (ascii fo space)

        mov     bx,ax                           ;each entry takes 8 bytes
        shl     ax,1                            ; pow(ax,3) == ax * 8
        shl     ax,1
        shl     ax,1
        mov     si,table_space                  ;si contains the base for the table
        add     si,ax                           ;si contains the base + offset
        call    draw_bigchar
        mov     byte [bigchar_to_render],0
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
        push    bp
        pushf

        mov     ax,cs
        mov     ds,ax
        mov     ax,GFX_SEG
        mov     es,ax

        call    music_play
        call    text_writer_update

        inc     byte [vert_retrace]

        mov     al,0x20                         ;send the EOI signal
        out     0x20,al                         ; to the IRQ controller

        popf
        pop     bp
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
text_writer_update:
        dec     byte [text_writer_delay]
        jz      .l0
        ret
.l0:
        mov     byte [text_writer_delay],7      ;wait a few cycles
        mov     bx, word [text_writer_offset]
        inc     word [text_writer_offset]
        mov     al, [text_writer_msg + bx]
        or      al,al                           ;last char ?
        jz      .start_again
        cmp     al,1
        jz      .clean_line

.write:
        mov     [bigchar_to_render],al
        jmp     render_smallchar

.start_again:
        mov     word [text_writer_offset],0     ;reset offset

.clean_line:
        mov     di,CHAR_OFFSET
        mov     word [char_offset],di           ;reset destination for char
        mov     cx,40*4
        sub     ax,ax
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
        incbin 'src/uctumi-song.pvm'
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

vert_retrace:           db 0                    ;when 1, a vertical retrace have just ocurred

bigchar_to_render:      db 0                    ;when 0, render finished/not needed. else, contains the ASCII to be rendered


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
        incbin 'src/charset_0x20_0x60.bin'      ;the charset already expanded for mode 320x200 @ 4 colors

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
text_writer_delay:
        db 1                                    ;ticks to wait until next char it written
text_writer_offset:
        dw 0                                    ;offset in the text. next char to be written
text_writer_msg:
           ;0123456789012345678901234567890123456789
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
        db '       UNEXPANDED PCJR (128KB) ?        ',1
        db 0

