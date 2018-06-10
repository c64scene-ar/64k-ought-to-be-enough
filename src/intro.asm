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

%include 'src/externs.inc'

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; MACROS
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
%define DEBUG 0                                 ;0=diabled, 1=enabled
%define EMULATOR 1                              ;1=run on emulator

GFX_SEG         equ     0xb800                  ;0x1800 for PCJr with 32k video ram
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

        ;call    banner_main_loop
        ;call    banner_cleanup

        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
banner_init:
        mov     ax,0x0004                       ;320x200 4 colors
        int     0x10

.forever:
        mov     si,table_a
        call    draw_big_char

        mov     si,table_e
        call    draw_big_char

        mov     si,table_i
        call    draw_big_char

        mov     si,table_o
        call    draw_big_char

        mov     si,table_u
        call    draw_big_char

        jmp     .forever

        mov     ax,1
        int     0x16

        ret

        call    command_next                    ;initialize next command

        mov     ax,banner_irq_8
        call    irq_8_init
        call    music_init

        mov     ax,0x0004                       ;320x200 4 colors
        int     0x10

        mov     ax,1
        int     0x16

        ret


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; draw a big char in the screen.
; only draws the segments that are needed: will turn on/off only the needed
; segments by doing a "diff" (simple xoring masks) of the previous char
;
; IN:
;       si = pointer to table of char to draw
draw_big_char:

        int 3
        push    si                                      ;save si for later

        %assign XX 0
        %rep 4
                mov     ax,[old_segments + XX]          ;read mask of 16-bit
                xor     ax,[si + XX]                    ;xor-it with prev mask
                mov     [segments_to_draw + XX],ax      ;bits that are 'on' are the ones that need to be updated
        %assign XX XX+2
        %endrep


        sub     bx,bx                                   ;index for call table

        %assign XX 0
        %rep 4
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
        %rep 4
                mov     ax,[si + XX]                    ;update old_segments
                mov     [old_segments + XX],ax
        %assign XX XX+2
        %endrep

        ret


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
banner_cleanup:
        call    irq_8_cleanup
        call    music_cleanup
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
banner_main_loop:

.main_loop:
        cmp     byte [should_decompress],1      ;should decompress image?
        jz      .decompress_letter              ; yes, decompress it

        cmp     byte [end_condition],0          ;animation finished?
        jnz     .exit                           ; yes, end

        call    key_pressed                     ;key pressed?
        jz      .main_loop                      ; no, keep looping

.exit:
        ret                                     ;exit main loop.

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.decompress_letter:
        dec     byte [should_decompress]        ;flag that decompress finished
        jmp     .main_loop                      ;return to main loop

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
        pushf

        mov     ax,banner_data                  ;update segments
        mov     ds,ax
        mov     ax,0x1800
        mov     es,ax

        call    music_play
        call    update_state_machine

        mov     al,0x20                         ;send the EOI signal
        out     0x20,al                         ; to the IRQ controller

        popf
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
        int 3
        mov     ax,[pvm_song + 0xc]             ;offset loop relative to start of data
        add     ax,pvm_song + 0x10              ;add header size
        mov     word [pvm_offset],ax            ;update new offset with loop data
        ret


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
update_state_machine:
        cmp     byte [should_decompress],0      ;is decompressing?
        jnz     .exit                           ; if so, exit

        call    [command_current_fn]            ;call current command

.exit:
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
command_next:
        sub     ax,ax                           ;ax = 0
        mov     bx,[command_idx]
        mov     al,[commands + bx]              ;command to initialize
        shl     al,1                            ;each address takes 2 bytes
        xchg    bx,ax                           ;bx = ax

        inc     word [command_idx]

        mov     ax,[command_updates + bx]       ;cache current update function
        mov     [command_current_fn],ax         ; for future use

        jmp     [command_inits + bx]            ;call correct init function


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
command_init_display:
        mov     byte [should_decompress],1
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; do nothing. wait until decompress finishes (from main loop) and
; execute next command when that happens
command_update_display:
        cmp     byte [should_decompress],0
        jnz     .exit

        jmp     command_next

.exit:
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
command_init_flash:
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
command_update_flash:
        call    command_next
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
command_init_delay:
        mov     bx,[command_idx]
        mov     al,[commands + bx]
        mov     [delay_cnt],al
        inc     word [command_idx]
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
command_update_delay:
        dec     byte [delay_cnt]
        jz      .exit
        ret
.exit:
        jmp     command_next

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
command_init_black:
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
command_update_black:
        call    command_next
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
command_init_end:
        ;mov     byte [end_condition],1

        ;repeat forever
        mov     word [command_idx],0
        jmp     command_next

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
command_update_end:
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; DATA GFX
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
section .banner_data data

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
should_decompress:      db 0                    ;0 when no decompress is needed, nor in progress
                                                ; 1 when decompress is requested or in progress
command_idx:            dw 0                    ;index of current command. index in the
                                                ; 'command' variable. [command + command_idx] gives
                                                ; you the current command
command_current_fn:     dw 0                    ; current command function. address of the function to call

delay_cnt:              db 0                    ;when 0, delay is over. tick once per frame

end_condition:          db 0                    ;when 1, banner animation sequence finishes


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; available tokens
TOKEN_END       equ 4

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
command_inits:
        dw      command_init_display
        dw      command_init_flash
        dw      command_init_delay
        dw      command_init_black
        dw      command_init_end

command_updates:
        dw      command_update_display
        dw      command_update_flash
        dw      command_update_delay
        dw      command_update_black
        dw      command_update_end

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; available tokens
commands:
        db TOKEN_END

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



