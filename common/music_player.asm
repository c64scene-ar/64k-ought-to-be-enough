; Music player (PVM format)
; Pungas de Villa Martelli - http://pungas.space
;
; code: riq (http://retro.moe)
bits    16
cpu     8086

PVM_HEADER_SIZE equ 0x10
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;in:
;       ax = offset to song
global music_init
music_init:
        mov     word [pvm_song_start],ax        ;update song start, including header
        add     ax,PVM_HEADER_SIZE              ;skip header
        mov     word [pvm_offset],ax            ;update song offset

        in      al,0x61                         ;PCJr only:
        or      al,0b0110_0000                  ; source for music is the SN76496
        out     0x61,al

        sub     al,al
        mov     byte [pvm_wait],al              ;don't wait at start
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
global music_cleanup
music_cleanup:
        mov     si,volume_0                     ;volume to 0 data
        mov     cx,VOLUME_0_MAX
.repeat:
        lodsb
        out     0xc0,al                         ;set volume to 0
        loop    .repeat

        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
global music_play
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
        mov     bx,[pvm_song_start]
        mov     ax,[bx + 0x0c]                  ;offset loop relative to start of data
        add     ax,bx                           ;add start offset
        add     ax,PVM_HEADER_SIZE              ;add header size
        mov     word [pvm_offset],ax            ;update new offset with loop data
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; DATA
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
pvm_wait:                                       ;cycles to read divided 0x2df
        db 0
pvm_offset:                                     ;pointer to next byte to read
        dw 0
pvm_song_start:                                 ;offset to where song start
        dw 0
volume_0:
        db      0b1001_1111                     ;vol 0 channel 0
        db      0b1011_1111                     ;vol 0 channel 1
        db      0b1101_1111                     ;vol 0 channel 2
        db      0b1111_1111                     ;vol 0 channel 3
VOLUME_0_MAX equ $ - volume_0
