;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; "Ought to be enough" - Part 2
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; Pungas de Villa Martelli - http://pungas.space
;
; code: riq (http://retro.moe)
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

bits    16
cpu     8086


extern irq_8_cleanup, irq_8_init
extern wait_vertical_retrace
extern dzx7_speed, dzx7_size
extern music_init, music_play, music_cleanup

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; MACROS
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
%define DEBUG 0                                 ;0=diabled, 1=enabled
%define EMULATOR 0                              ;1=run on emulator

GFX_SEG         equ     0x0800                  ;graphics segment (32k offset)

SCROLL_OFFSET   equ     21*2*160                ;start at line 21:160 bytes per line, lines are every 4 -> 8/4 =2
SCROLL_COLS_TO_SCROLL   equ 80                  ;how many cols to scroll. max 160 (width 320, but we scroll 2 pixels at the time)
SCROLL_COLS_MARGIN      equ ((160-SCROLL_COLS_TO_SCROLL)/2)
SCROLL_RIGHT_X  equ     (160-SCROLL_COLS_MARGIN-1)      ;col in which the scroll starts from the right
SCROLL_LEFT_X   equ     (SCROLL_COLS_MARGIN)    ;col in which the scroll ends from the left

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; render vertically 4 bits needed for the scroll. grabs the firts four bytes from the cache,
; use the MSB bit. If it is on, use white, else black color
;
; IN:   ds:si   -> bit to render (pointer to cache)
;       bx      -> pointer to pixel color table
;       bp      -> row index
; Args: %1: offset line.
%macro RENDER_BIT 1
        mov     di,SCROLL_OFFSET+160*%1+SCROLL_RIGHT_X  ;es:di points to video memory
        %rep    4
                lodsb                                   ;fetches byte from the cache
                mov     ah,al                           ;save value in ah for later use

                ;write first 2 pixels
                mov     cl,4
                shr     al,cl                           ;mov 4-MSB bits into LSB

                xlatb                                   ;al = [scroll_pixel_color_tbl+ al]
                stosb                                   ;write 2 pixels

                ;write 2nd 2 pixels
                mov     al,ah                           ;restore previous al value
                and     al,0b0000_1111                  ;filter out 4 MSB bits, and only use
                                                        ; 4 LSB bits
                xlatb                                   ;al = [scroll_pixel_color_tbl+ al]
                stosb                                   ;es:di already pointing to the correct
                                                        ; offset
                add     di,8192-2                       ;next bank minus 2 (from previous two stobs)
        %endrep
%endmacro

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; CODE
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
main:
        resb    0x100                           ;cannot use "org 0x100" when using multiple .o files

        sub     ax,ax
        mov     ds,ax                           ;ds = 0
        mov     word [0x0415],128               ;make BIOS set_video_modo believe that we
                                                ; have at least 128K RAM, otherwise it won't let
                                                ; us set video mode 9

        mov     ax,0x0089                       ;set video mode 9, don't clean screen
        int     0x10                            ;320x200 16 colors

        mov     ax,0x0583                       ;set CPU/CRT pages
        mov     bx,0x0202                       ;use page 2 for video memory/map 0xb800
        int     0x10                            ;page 2 means: starts at 0x0800 (32k offset)


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

        ;delay
        mov     cx,0xf000                       ;delay to display the graphics for a few ms
.l0:
        mul     ax
        mul     ax
        mul     ax
        mul     ax
        loop    .l0

        push    cs
        pop     ds                              ;ds=cs
        mov     si,image1                       ;ds:si source

        mov     ax,GFX_SEG
        mov     es,ax                           ;es=GFX seg
        sub     di,di                           ;es:di destination

        call    dzx7_speed                      ;uncompress image in GFX segment


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

        mov     ax,cs
        mov     ds,ax
        mov     ax,GFX_SEG
        mov     es,ax

%if DEBUG
        call    inc_d020
%endif

        call    music_play
        call    scroll_anim

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
scroll_anim:
        mov     bp,ds                           ;save ds for later
        mov     ax,es                           ;ds and es point to video memory
        mov     ds,ax

        mov     dx,SCROLL_COLS_TO_SCROLL/2      ;div 2 since we use movsw instead of movsb

        ;scroll 16 rows in total
        %assign XX 0                            ;represents the 4 banks
        %rep 4
                %assign YY 0                    ;represents how many rows to scroll times 4 (banks)
                %rep 8
                        mov     cx,dx                           ;scroll 8 rows
                        mov     si,SCROLL_OFFSET+8192*XX+160*YY+SCROLL_LEFT_X+1  ;source: last char of screen
                        mov     di,SCROLL_OFFSET+8192*XX+160*YY+SCROLL_LEFT_X-1  ;dest: last char of screen - 1
                        rep movsw                               ;do the copy
                %assign YY YY+1
                %endrep
        %assign XX XX+1
        %endrep

        mov     ds,bp                           ;restore ds

        cmp     byte [scroll_char_col],0        ;if scroll_char_col == 0 ?
        jnz     .render_bits                    ; if not, render bits


        ; Update the cache with the next 192 bytes (3x4 chars @ 2 bit resolution each)
        ; It could could be a regular 'space' or a char. 'space' is treated
        ; differently to save memory
        mov     bx,[scroll_char_idx]            ;scroll text offset
        mov     bl,byte [scroll_text+bx]        ;char to print

        cmp     bl,0x20                         ;special case for space
        jnz     .is_regular_char

        ; To save space (192 chars and more), the 'space' char is not
        ; in the charset. The charset only contains A-Z.
        ; So when a space is found, we generate it in runtime, which is
        ; basically 192 empty chars
        mov     bp,es                           ;save es for later

        mov     ax,ds
        mov     es,ax                           ;es = ds
        mov     di,cache_charset                ;es:di: cache

        sub     ax,ax                           ;ax=0 (emtpy bits)
        mov     cx,192/2                        ;copy 192 bytes (or 96 words)
        rep stosw

        mov     es,bp                           ;restore es
        jmp     .render_bits


.is_regular_char:
        sub     bl,0x41                         ;offset to 0. first char is 'A'
        sub     bh,bh

        push    bx                              ;save bx

        mov     cl,7                            ;multiplying by 192 is the same as
        shl     bx,cl                           ; doing: n << 7 + n << 6. Here we
                                                ; calculate the (bx << 7)

        pop     ax                              ;restore bx in ax
        dec     cl                              ; and shift by 6 the result
        shl     ax,cl
        add     bx,ax                           ;finally add bx and ax and the multiplication
                                                ; is done.

        lea     si,[charset+bx]                 ;ds:si: offset in charset for char

        mov     bp,es                           ;save es for later

        mov     ax,ds
        mov     es,ax                           ;es = ds
        mov     di,cache_charset                ;es:di: cache

        mov     cx,192/2                        ;copy 192 bytes (or 96 words)
        rep movsw                               ; the size of one char

        mov     es,bp                           ;restore es
        ;fall-through

.render_bits:
        mov     si,cache_charset                ;ds:si points to cache_charset
        add     si,[scroll_cache_offset]
        mov     bx,scroll_pixel_color_tbl       ;table for colors used in the macros
        RENDER_BIT 0
        RENDER_BIT 1

        RENDER_BIT 2
        RENDER_BIT 3

        RENDER_BIT 4
        RENDER_BIT 5

        RENDER_BIT 6
        RENDER_BIT 7

        inc     byte [scroll_char_col]           ;we render 4 bits at the time
        cmp     byte [scroll_char_col],6         ;end of char ? (6 * 4 = 24)
        jz      .next_char

        add     word [scroll_cache_offset],32   ;in each pass we render 32 bytes
                                                ; 32 height * 8 bits width (4 pixels) = 32 bytes
        jmp     .end                            ;and end

.next_char:
        cmp     byte [scroll_force_spacer],0    ;if 0, then next char is 'spacer'
        jnz     .next_is_char                   ;if not, do regualar char

        ;next is spacer
        inc     byte [scroll_force_spacer]      ;next should be regular char
        mov     byte [scroll_char_col],5        ;set bit idx to 5, so only one
                                                ; space column is rendered
        mov     word [scroll_cache_offset],0    ;reset cache offset

        ;clear cache with 'space' needed for the spacer
        mov     bp,es                           ;save es for later
        mov     ax,ds
        mov     es,ax                           ;es = ds
        mov     di,cache_charset                ;es:di: cache
        sub     ax,ax                           ;ax=0 (emtpy bits)
        mov     cx,192/2                        ;copy 192 bytes (or 96 words)
        rep stosw
        mov     es,bp                           ;restore es
        jmp     .end

.next_is_char:
        dec     byte [scroll_force_spacer]      ;next should be spacer
        sub     ax,ax
        mov     byte [scroll_char_col],al        ;reset bit idx
        mov     word [scroll_cache_offset],ax   ;reset cache offset
        inc     word [scroll_char_idx]          ;scroll_char_idx++
        cmp     word [scroll_char_idx],SCROLL_TEXT_LEN  ;end of scroll?
        jnz     .end                            ; if so, reset index

        ;mov     word [scroll_char_idx],ax       ;reset to 0
        mov     byte [end_condition],1          ;trigger end condition, end

.end:
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;DEBUG ONLY
%if DEBUG
inc_d020:
        mov     dx,0x03da                       ;show how many raster barts it consumes
        mov     al,2                            ;select border color
        out     dx,al                           ;(register)

        mov     al,0x0f
        out     dx,al                           ;change border to white (data)
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
dec_d020:
        mov     dx,0x03da                       ;show how many raster barts it consumes
        mov     al,2                            ;select border color
        out     dx,al                           ;(register)

        sub     al,al
        out     dx,al                           ;change border back to black (data)
        ret
%endif

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;DATA
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
pvm_song:
        incbin 'part2/uctumi-libertango.pvm'

image1:
        incbin 'part2/alakran-cara.raw.zx7'

charset:
        incbin 'part2/charset_bigfont.bin'

end_condition:
        db 0                                    ;1 if demo should end
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; scroll related
scroll_text:
        db 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        db '    '
        db 'THE PCJR WITH SIXTY FOUR KILOBYTES OF RAM DOES NOT SUPPORT '
        db 'SIXTEEN COLOR MODES, AT LEAST IN THEORY. IN PRACTICE IF YOU TELL '
        db 'THE COMPUTER THAT YOU HAVE ONE HUNDRED TWENTY EIGHT KILOBYTES OF '
        db 'RAM, EVEN YOU HAVE SIXTY FOUR, THEN YOU CAN USE THE SIXTEEN COLOR '
        db 'VIDEO MODES. AND THAT IS WHAT WE ARE DOING IN THIS SCROLL. '
        db 'THIS IS JUST THE 320 X 200 WITH SIXTEEN COLORS RUNNING. '
SCROLL_TEXT_LEN equ $-scroll_text

scroll_char_idx:                                ;pointer to the next char in text
        dw 0
scroll_char_col:                                ;pointer to the next column of the char is cache
        db 0
scroll_pixel_color_tbl:                         ;the colors for the scroll letters
        db      0x00                            ;0000 - black/black
        db      0x0c                            ;0001 - black/white
        db      0x09                            ;0010 - white/black
        db      0x0d                            ;0011 - white/white
        db      0xc0                            ;0100 - black/black
        db      0xcc                            ;0101 - black/white
        db      0xc9                            ;0110 - white/black
        db      0xcd                            ;0111 - white/white
        db      0x90                            ;1000 - black/black
        db      0x9c                            ;1001 - black/white
        db      0x99                            ;1010 - white/black
        db      0x9d                            ;1011 - white/white
        db      0xd0                            ;1100 - black/black
        db      0xdc                            ;1101 - black/white
        db      0xd9                            ;1110 - white/black
        db      0xdd                            ;1111 - white/white

scroll_enabled:                                 ;boolean: enabled?
        db      0
scroll_effect_enabled:                          ;boolean. whether to enable plasma + raster bar
        db      0

scroll_force_spacer:
        db      0                               ;when 1, a spacer of 4 pixels is rendered. occurs after
                                                ; rendering a char.
scroll_cache_offset:                            ;cache contains the data of the char to render
        dw 0                                    ; the cache_offset, is the offset within the cache
cache_charset:
        resb    192                             ;the 192 bytes that it takes to represent
                                                ; a big char: 3 * 4 * 2 bits per color
                                                ; column firts.
