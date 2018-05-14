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

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; MACROS
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
%define DEBUG 0                                 ;0=diabled, 1=enabled
%define EMULATOR 1                              ;1=run on emulator

GFX_SEG         equ     0x1800                  ;0x1800 for PCJr with 32k video ram
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

        call    banner_main_loop

        call    banner_cleanup

        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
banner_init:

        call    command_next                    ;initialize next command

        mov     ax,banner_irq_8
        call    irq_8_init
        call    music_init

        mov     ax,0x0004                       ;320x200 4 colors
        int     0x10

        ret


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
banner_cleanup:
        call    irq_8_cleanup
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
        sub     ax,ax
        mov     al,[letter_to_decompress]
        shl     ax,1                            ;each address takes 2 bytes
        mov     bx,ax                           ;uses bx for index
        mov     si,[letter_idx + bx]            ;ds:si: compressed data

        mov     ax,0x1800                       ;es:di (destination)
        mov     es,ax
        mov     di,0x4000

        call    lz4_decompress

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
        mov     bx,[command_idx]
        mov     al,[commands + bx]

        inc     word [command_idx]

        mov     [letter_to_decompress],al
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
        mov     byte [end_condition],1
        ret

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
; compress data
letter_p_lz4:
        incbin 'src/p.raw.lz4'
letter_v_lz4:
        incbin 'src/v.raw.lz4'
letter_m_lz4:
        incbin 'src/m.raw.lz4'
letter_invites_lz4:
        incbin 'src/invites.raw.lz4'
letter_you_lz4:
        incbin 'src/you.raw.lz4'
letter_to_lz4:
        incbin 'src/to.raw.lz4'
letter_flashparty_lz4:
        incbin 'src/fp.raw.lz4'
letter_2018_lz4:
        incbin 'src/2018.raw.lz4'

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
letter_to_decompress:   db 0                    ;idx of the image to decompress

command_idx:            dw 0                    ;index of current command. index in the
                                                ; 'command' variable. [command + command_idx] gives
                                                ; you the current command
command_current_fn:     dw 0                    ; current command function. address of the function to call

delay_cnt:              db 0                    ;when 0, delay is over. tick once per frame

end_condition:          db 0                    ;when 1, banner animation sequence finishes

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; pointers to the data. each one has its own index
letter_idx:
        dw letter_p_lz4                         ;0
        dw letter_v_lz4                         ;1
        dw letter_m_lz4                         ;2
        dw letter_invites_lz4                   ;3
        dw letter_you_lz4                       ;4
        dw letter_to_lz4                        ;5
        dw letter_flashparty_lz4                ;6
        dw letter_2018_lz4                      ;7


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; available tokens
DISPLAY         equ 0                             ;letter to display
FLASH           equ 1
DELAY           equ 2
BLACK           equ 3
END             equ 4

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
        db DISPLAY,0                            ;p
        db DELAY,75
        db DISPLAY,1                            ;v
        db DELAY,75
        db DISPLAY,2                            ;m
        db DELAY,75
        db BLACK
        db DELAY,100

        db DISPLAY,0                            ;p
        db DELAY,75
        db DISPLAY,1                            ;v
        db DELAY,75
        db DISPLAY,2                            ;m
        db BLACK
        db DELAY,75

        db DISPLAY,0                            ;p
        db DELAY,50
        db DISPLAY,1                            ;v
        db DELAY,50
        db DISPLAY,2                            ;m
        db BLACK
        db DELAY,50

        db DISPLAY,0                            ;p
        db DELAY,25
        db DISPLAY,1                            ;v
        db DELAY,25
        db DISPLAY,2                            ;m
        db BLACK
        db DELAY,25

        db DISPLAY,0                            ;p
        db DELAY,5
        db DISPLAY,1                            ;v
        db DELAY,5
        db DISPLAY,2                            ;m
        db BLACK
        db DELAY,5

        db DISPLAY,0                            ;p
        db DELAY,5
        db DISPLAY,1                            ;v
        db DELAY,5
        db DISPLAY,2                            ;m
        db BLACK
        db DELAY,5

        db DISPLAY,3                            ;invites
        db DELAY,30
        db DISPLAY,4                            ;you
        db DELAY,30
        db DISPLAY,5                            ;to
        db DELAY,30

        db DISPLAY,6                            ;flash party
        db DELAY,30
        db FLASH
        db DELAY,5
        db FLASH
        db DELAY,5
        db FLASH
        db DELAY,5
        db FLASH
        db DELAY,5
        db FLASH
        db DELAY,5
        db FLASH
        db DELAY,30

        db DISPLAY,7                            ;2018
        db DELAY,150

        db END
