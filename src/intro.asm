; Invite intro for Flashparty 2018
; Pungas de Villa Martelli - http://pungas.space
;
; code: riq (http://retro.moe)

bits    16
cpu     8086

extern label_model
extern lz4_decompress, lz4_decompress_small
extern dzx7_speed, dzx7_size, dzx7_original
extern irq_8_init, irq_8_cleanup

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
; inline vertical retrace
; IN:
;       dx      -> VGA_ADDRESS
%macro WAIT_VERTICAL_RETRACE 0
%%wait:
        in      al,dx                           ;wait for vertical retrace
        test    al,8                            ; to finish
        jnz     %%wait

%%retrace:
        in      al,dx                           ;wait for vertical retrace
        test    al,8                            ; to start
        jz      %%retrace
%endmacro

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; inline horizontal retrace
; IN:
;       dx      -> VGA_ADDRESS
%macro WAIT_HORIZONTAL_RETRACE 0
%%wait:
        in      al,dx                           ;wait for horizontal retrace
        ror     al,1
        jc      %%wait

%%retrace:
        in      al,dx                           ;wait for horizontal retrace
        ror     al,1
        jnc     %%retrace
%endmacro

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; refreshes the palette. used as a macro, and not function, since it is being
; called from time-critical sections
;
; IN:
;       ds:si   -> table with the palette to update
;       bl      -> starting color + 0x10. example: use 0x1f for white: 0x10 + 0xf
;       cx      -> jump address for delay
;       dx      -> VGA_ADDRESS
;
; Args:
;       #1:     -> number of colors to update times 2, since it does 2 colors per h-line
;       #2:  0  -> don't wait for horizontal retrace
;            1  -> wait fro horizontal retrace
%macro REFRESH_PALETTE 2

        WAIT_HORIZONTAL_RETRACE                 ;reset to register again
        call    cx                              ;sync: jr A = 45 nop
                                                ;      jr B = 41 nop + 1 aaa
  %rep %1
        sub     di,di                           ;zero it. needed for later
        mov     al,bl                           ;color to update
        out     dx,al                           ;dx=0x03da (register)

        lodsb                                   ;load one color value in al
        out     dx,al                           ;update color (data)

        xchg    ax,di                           ;fatest way to set al to 0
        out     dx,al                           ;(register)

        in      al,dx                           ;reset to register again
        inc     bl                              ;next color

    %if %2
        call    cx                              ;sync: jr A = 55 nops
                                                ;      jr B = 53 nops
    %endif
  %endrep
%endmacro



;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; CODE
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
section .text

global intro_start
intro_start:
        cld

        mov     ax,data                         ;init segments
        mov     ds,ax                           ;these values must always be true
        mov     ax,GFX_SEG                      ; through the whole intro.
        mov     es,ax                           ; push/pop otherwise

        call    intro_init

        mov     ax,intro_irq_8
        call    irq_8_init

        call    main_loop

        call    music_cleanup
        call    irq_8_cleanup

        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
intro_init:

        call    gfx_init
        call    music_init
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
main_loop:
        sub     al,al
.loop:
        cmp     byte [tick],al                  ;in theory, the tick is not needed
        je      .loop                           ; since i'm not doing anything, but
                                                ; in practice, if not used, the interrupt could be triggered
                                                ; in the middle of the BIOS call, some intructions are longer than others,
                                                ; and it could generate some flicker in the raster bar routine

        mov     byte [tick],al                  ;mov ,0, instead of dec. since two inc could happen together
                                                ; if running on a slow machine. not a big issue, but ctrl+alt+del won't work
                                                ; and a switch on/off will be required (arggh.)

%if EMULATOR
        cli                                     ;on emulator, test for keyboard buffer
        mov     cx,ds

        sub     ax,ax
        mov     ds,ax                           ;ds = zero page
        mov     ax, [0x41a]                     ;keyboard buffer head
        cmp     ax, [0x41c]                     ;keyboard buffer tail

        mov     ds,cx
        sti
%else
        in      al,0x62                         ;on real hardware, test keystroke missed?
        and     al,1                            ; so that we can disable IRQ9
%endif
        jz      .loop

        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; IRQ
intro_irq_8:
        ;not saving any variable, since the code at main loop
        ;happens after the tick

        mov     ax,data
        mov     ds,ax

%if DEBUG
        call    inc_d020
%endif

        call    music_anim                      ;play music

%if DEBUG
        call    dec_d020
%endif

        inc     byte [tick]                     ;tell main_loop that it could process
                                                ; whatever he wants

        mov     al,0x20                         ;send the EOI signal
        out     0x20,al                         ; to the IRQ controller

        iret                                    ;exit interrupt

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
music_init:
        in      al,0x61                         ;PCJr only:
        or      al,0b0110_0000                  ; source for music is the SN76496
        out     0x61,al

        mov     word [pvm_offset],pvm_song + 0x10       ;update start offset
        sub     al,al
        mov     byte [pvm_wait],al              ;don't wait at start
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
music_anim:

DATA    equ     0b0000_0000
DATA_EXTRA equ  0b0010_0000
DELAY   equ     0b0100_0000
DELAY_EXTRA equ 0b0110_0000
END     equ     0b1000_0000

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

        cmp     al,DATA                         ;data?
        je      .is_data
        cmp     al,DATA_EXTRA                   ;data extra?
        je      .is_data_extra
        cmp     al,DELAY                        ;delay?
        je      .is_delay
        cmp     al,DELAY_EXTRA                  ;delay extra?
        je      .is_delay_extra
        cmp     al,END                          ;end?
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
gfx_init:
        push    ds
        push    es

        mov     ax,0x0009
        int     0x10                            ;320x200x16

        mov     ax,gfx                          ;ds:si (source)
        mov     ds,ax
;        mov     si,logo
;        mov     si,logo_lz4
        mov     si,logo_zx7

        mov     ax,GFX_SEG                      ;es:di (destination)
        mov     es,ax
        sub     di,di

;        mov     cx,16 * 1024                    ;32k
;        rep movsw                               ;copy 32k
;        call    lz4_decompress
        call    dzx7_speed

        pop     es
        pop     ds
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
inc_d020:
        mov     dx,VGA_ADDRESS                  ;show how many raster barts it consumes
        mov     al,2                            ;select border color
        out     dx,al                           ;(register)

        mov     al,0x0f
        out     dx,al                           ;change border to white (data)
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
dec_d020:
        mov     dx,VGA_ADDRESS                  ;show how many raster barts it consumes
        mov     al,2                            ;select border color
        out     dx,al                           ;(register)

        sub     al,al
        out     dx,al                           ;change border back to black (data)
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; IBM PCjr B delays used in REFRESH_PALETTE
jr_b_delay_0a:                                  ;sync
        times 30 nop
        mov     cx,jr_b_delay_0b                ;delay function to be used after this one
        ret

jr_b_delay_0b:                                  ;h-retrace
        times 41 nop
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; IBM PCjr B delays used in REFRESH_PALETTE
; delays used in new_i08_bottom_full_color
jr_b_delay_1a:                                  ;sync function
        times 30 nop
        mov     cx,jr_b_delay_1b                ;delay function to be used after this one
        ret

jr_b_delay_1b:                                  ;h-retrace
        times 43 nop
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; IBM PCjr A delays used in REFRESH_PALETTE
jr_a_delay_0a:                                  ;sync
        times 31 nop
        mov     cx,jr_a_delay_0b                ;delay function to be used after this one
        ret

jr_a_delay_0b:                                  ;h-retrace
        times 43 nop
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; IBM PCjr A delays used in REFRESH_PALETTE
; delays used in new_i08_bottom_full_color
jr_a_delay_1a:                                  ;sync
        times 31 nop
        mov     cx,jr_a_delay_1b                ;delay function to be used after this one
        ret

jr_a_delay_1b:                                  ;h-retrace
        times 45 nop
        ret


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; DATA GFX
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
section .gfx data
logo_lz4:
        incbin 'src/logo.raw.lz4'

logo_zx7:
        incbin 'src/logo.raw.zx7'

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; DATA MUSIC + CHARSET + MISC
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
section .data data

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

tick:                                           ;to trigger once the irq was called
        db      0
old_i08:                                        ;segment + offset to old int 8 (timer)
        dd      0
old_i09:                                        ;segment + offset to old int 9 (keyboard)
        dd      0
old_pic_imr:                                    ;PIC IMR original value
        db      0
