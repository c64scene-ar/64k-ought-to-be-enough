;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; Part 2
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
%define EMULATOR 1                              ;1=run on emulator

GFX_SEG         equ     0x0800                  ;graphics segment (32k offset)

SCROLL_OFFSET   equ     23*2*160                ;start at line 22:160 bytes per line, lines are every 4 -> 8/4 =2
SCROLL_COLS_TO_SCROLL   equ 140                 ;how many cols to scroll. max 160 (width 320, but we scroll 2 pixels at the time)
SCROLL_COLS_MARGIN      equ ((160-SCROLL_COLS_TO_SCROLL)/2)
SCROLL_RIGHT_X  equ     (160-SCROLL_COLS_MARGIN-1)      ;col in which the scroll starts from the right
SCROLL_LEFT_X   equ     (SCROLL_COLS_MARGIN)    ;col in which the scroll ends from the left

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; render vertically 4 bits needed for the scroll. grabs the firts four bytes from the cache,
; use the MSB bit. If it is on, use white, else black color
;
; IN:   ds:si   -> bit to render (pointer to cache)
;       dx      -> pointer to pixel color table
;       bp      -> row index
;       cl      -> 0b1100_0000
; Args: %1: offset line.
%macro RENDER_BIT 1

        mov     di,SCROLL_OFFSET+160*%1+SCROLL_RIGHT_X  ;es:di points to video memory
        %rep    4
                lodsb                                   ;fetches byte from the cache
                mov     ah,al                           ;save value in ah for later use
                and     al,cl                           ;cl = 0b1100_0000
                rol     al,1
                rol     al,1
                mov     bx,dx
                xlatb                                   ;al = [scroll_pixel_color_tbl+ al]
                stosb

                add     di,8192-1                       ;draw in next bank. di was incremented by
                                                        ; one in stosb.

                shl     ah,1                            ;al << 2. bit 7,6 contains next bits to render
                shl     ah,1                            ;
                mov     bx,bp                           ;index by bp
                mov     [cache_charset+bx],ah           ;update cache for next iteration
                inc     bp                              ;inc row index
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

        sub     ax,ax
        int     0x16                            ;wait key

        mov     ax,cs
        mov     ds,ax                           ;ds=cs
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

%if EMULATOR
        sub     ax,ax
        int     0x16                            ;wait key
%else
.l0:    in      al,0x62                         ;on real hardware, test keystroke missed?
        and     al,1                            ; so that we can disable IRQ9
        jz      .l0
%endif


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
        %assign XX 0
        %rep 4
                %assign YY 0
                %rep 4
                        mov     cx,dx                           ;scroll 4 lines of 80 chars
                        mov     si,SCROLL_OFFSET+8192*XX+160*YY+SCROLL_LEFT_X+1  ;source: last char of screen
                        mov     di,SCROLL_OFFSET+8192*XX+160*YY+SCROLL_LEFT_X    ;dest: last char of screen - 1
                        rep movsw                               ;do the copy
                %assign YY YY+1
                %endrep
        %assign XX XX+1
        %endrep

        mov     ds,bp                           ;restore ds

        cmp     byte [scroll_bit_idx],0         ;if scroll_bit_idx == 0 ?
        jnz     .render_bits                    ; if not, render bits

.read_and_process_char:
        ;update the cache with the next 32 bytes (2x2 chars)
        mov     bx,[scroll_char_idx]            ;scroll text offset
        mov     bl,byte [scroll_text+bx]        ;char to print

        sub     bl,0x20                         ;offset to 0

        sub     bh,bh
        shl     bx,1                            ;bx * 8 since each char takes 8
        shl     bx,1                            ; bytes in the charset
        shl     bx,1
        lea     si,[charset+bx]                 ;ds:si: offset in charset for char

        mov     bp,es                           ;save es for later

        mov     ax,ds
        mov     es,ax                           ;es = ds
        mov     di,cache_charset                ;es:di: cache

        mov     cx,4                            ;copy upper part of char (4 words == 8 bytes)
        rep movsw

        mov     cl,4                            ;di updated to offset in cache_charset
        add     si,(64-1)*8                     ;point to bottom part of char. offset=64
        rep movsw                               ;copy bottom to cache (4 words == 8 bytes)

        mov     es,bp                           ;restore es

        ;fall-through

.render_bits:
        mov     si,cache_charset                ;ds:si points to cache_charset
        sub     bp,bp                           ;used for the cache row index in the macros
        mov     dx,scroll_pixel_color_tbl       ;table for colors used in the macros
        mov     cl,0b1100_0000                  ;mask used in macros

        RENDER_BIT 0                            ;render rows 0,4,8,12
        RENDER_BIT 1                            ;render rows 1,5,9,13
        RENDER_BIT 2                            ;render rows 2,6,10,14
        RENDER_BIT 3                            ;render rows 3,7,11,15

        add     byte [scroll_bit_idx],2         ;two incs, since it prints 2 bits at the time

        test    byte [scroll_bit_idx],8         ;should use 2nd chars?
        jz      .end                            ;if not, exit

.next_char:
        sub     ax,ax
        mov     byte [scroll_bit_idx],al        ;reset bit idx
        inc     word [scroll_char_idx]          ;scroll_char_idx++
        cmp     word [scroll_char_idx],SCROLL_TEXT_LEN  ;end of scroll?
        jnz     .end                            ; if so, reset index
        mov     word [scroll_char_idx],ax       ;reset to 0

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
        incbin 'part2/charset_0x00_0x40.bin'

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; scroll related
scroll_text:
        db 'HI AGAIN! REMEMBER THE DATES: SEPTEMBER 21,22,23 2018 '
        db 'IN BUENOS AIRES, ARGENTINA. '
        db 'DID YOU KNOW THE PCJR IS THE BEST COMPUTER EVER MADE? '
        db 'WELL, THAT WAS A LITTLE FAR-FETCHED, BUT YOU KNOW WHAT? '
        db 'THE PCJR IS SO UNDERRATED THAT WE THOUGHT THAT WE SHOULD GIVE IT '
        db 'SOME GOOD PRESS. '
        db 'IT HAS A SOUND CHIP WITH 3 VOICES + NOISE. '
        db 'IT HAS A NICE 320 X 200 @ 16 COLORS VIDEO MODE. '
        db '(USING RGBI OUTPUT). '
        db 'IT ALSO HAS COMPOSITE OUTPUT '
        db 'AND IT IS SUPER SLOW IF IT HAS LESS THAN 128KB RAM. '
        db 'AND JUST A BIT FASTER THAN A 1981 PC IF YOUR CODE IS PLACED ABOVE 128KB RAM. '
SCROLL_TEXT_LEN equ $-scroll_text

scroll_char_idx:                                ;pointer to the next char
        dw 0
scroll_bit_idx:                                 ;pointer to the next bit in the char
        db 0
scroll_pixel_color_tbl:                         ;the colors for the scroll letters
        db      0x00                            ;00 - black/black
        db      0x0f                            ;01 - black/white
        db      0xf0                            ;10 - white/black
        db      0xff                            ;11 - white/white

scroll_enabled:                                 ;boolean: enabled?
        db      0
scroll_effect_enabled:                          ;boolean. whether to enable plasma + raster bar
        db      0

cache_charset:
        resb    16                              ;the 16 bytes to print in the current frame
                                                ; char aligned like: top-left, bottom-left,
                                                ; top-right, bottom-right
