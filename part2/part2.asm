;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; "64K RAM Ought to be enough" - Part 2
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

GFX_SEG         equ     0x0800                  ;graphics segment (32k offset)

SCROLL_OFFSET   equ     21*2*160                ;start at line 21:160 bytes per line, lines are every 4 -> 8/4 =2
SCROLL_COLS_TO_SCROLL   equ 84                  ;how many cols to scroll. max 160 (width 320, but we scroll using words)
SCROLL_COLS_MARGIN      equ ((160-SCROLL_COLS_TO_SCROLL)/2)
SCROLL_RIGHT_X  equ     (160-SCROLL_COLS_MARGIN-1)      ;col in which the scroll starts from the right
SCROLL_LEFT_X   equ     (SCROLL_COLS_MARGIN)    ;col in which the scroll ends from the left

CHARSET_CHAR_WIDTH      equ 24
CHARSET_CHAR_HEIGHT     equ 32
CHARSET_COLS_PER_CHAR   equ 6                   ;each char has 6 columns

CHARSET_SPACE           equ charset + (192 * 3) ;space is defined in position 3
                                                ; and each char takes 192 bytes

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
section .text
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
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
start:
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

        push    cs
        pop     ds

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


        call    scroll_anim
        call    music_play


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
        mov     ax,GFX_SEG
        mov     es,ax
        mov     ds,ax                           ;ds = es = video segment

        mov     dx,SCROLL_COLS_TO_SCROLL/2      ;div 2 since we use movsw instead of movsb

        ;scroll 32 rows in total
        %assign XX 0                            ;represents the 4 banks
        %rep 4
                %assign YY 0                    ;represents how many rows to scroll times 4 (banks)
                %rep 8
                        mov     cx,dx           ;scroll 8 rows
                        mov     si,SCROLL_OFFSET+8192*XX+160*YY+SCROLL_LEFT_X+1  ;source: last char of screen
                        mov     di,SCROLL_OFFSET+8192*XX+160*YY+SCROLL_LEFT_X-1  ;dest: last char of screen - 1
                        rep movsw               ;do the copy
                %assign YY YY+1
                %endrep
        %assign XX XX+1
        %endrep

        mov     ax,cs
        mov     ds,ax                           ;ds = cs

        cmp     byte [scroll_char_col],CHARSET_COLS_PER_CHAR    ;if scroll_char_col == 6 ? (initial state)
        jnz     .render_bits                    ; if not, render bits


        ; Update the pointer to the chardef
        mov     bx,[scroll_char_idx]            ;scroll text offset
        mov     bl,byte [scroll_text+bx]        ;char to print

        cmp     bl,0x20                         ;special case for space
        jnz     .is_alphanumeric

        ; Is space
        mov     word [scroll_char_offset],CHARSET_SPACE
        jmp     .render_bits


.is_alphanumeric:
        cmp     bl,0x40                         ;is char [A-Z] ?
        jb      .is_digit

.is_char:
        sub     bl,0x32                         ;offset to 15. first char is 'A'
                                                ; positions 0-14 reserved to digits, dot and space et al.
                                                ; so use 0x41 - 15 = 0x32
        jmp     .process_alphanumeric

.is_digit:                                      ;is number [0-9], dot or space
        sub     bl,0x2c                         ; ',' is 0x2c and is the first char
        ; fall-through                          ; and 'space' is placed in '/' position

.process_alphanumeric:
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
        mov     [scroll_char_offset],si         ; and save it in the offset variable
        ;fall-through

.render_bits:
        mov     si,[scroll_char_offset]
        mov     bx,scroll_pixel_color_tbl       ;table for colors used in the macros
        RENDER_BIT 0
        RENDER_BIT 1

        RENDER_BIT 2
        RENDER_BIT 3

        RENDER_BIT 4
        RENDER_BIT 5

        RENDER_BIT 6
        RENDER_BIT 7

        dec     byte [scroll_char_col]          ;we render 4 bits at the time
        jz      .next_char                      ;after rendering all its columsn,
                                                ; end of char ? (6 * 4 = 24)

        add     word [scroll_char_offset],32    ;in each pass we render 32 bytes
                                                ; 32 height * 8 bits width (4 pixels) = 32 bytes
        ret                                     ;end.

.next_char:
        cmp     byte [scroll_force_spacer],0    ;if 1, then next char is 'spacer'
        jz      .next_is_char                   ;if not, do regualar char

        ;next is spacer
        dec     byte [scroll_force_spacer]      ;next should be regular char
        inc     byte [scroll_char_col]          ;set bit idx to 1, so only one
                                                ; space column is rendered
        mov     word [scroll_char_offset],CHARSET_SPACE         ;reset cache offset
                                                ; so that it points to an empty char
        ret                                     ;end.

.next_is_char:
        inc     byte [scroll_force_spacer]      ;after real char, next should be spacer
        mov     byte [scroll_char_col],CHARSET_COLS_PER_CHAR    ;total columns to render per char
        inc     word [scroll_char_idx]          ;scroll_char_idx++
        cmp     word [scroll_char_idx],SCROLL_TEXT_LEN  ;end of scroll?
        jz      .end_scroll                     ; if so, end scroll
        ret                                     ;end

.end_scroll:
        ;mov     word [scroll_char_idx],ax       ;reset to 0
        mov     byte [end_condition],1          ;trigger end condition, end
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;DATA
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
pvm_song:
        incbin 'part2/uctumi-libertango.pvm'

charset:
        incbin 'part2/charset_bigfont.bin'              ;letters A-Z
charset_numbers:
;        incbin 'part2/charset_bigfont_numbers.bin'      ;numbers 0-9

end_condition:
        db 0                                    ;1 if demo should end
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; scroll related
scroll_text:
        db '... WE SAID THAT THE GOOD THING OF THE PCJR WAS THAT IT '
        db 'HAS A 320 X 200 WITH 16 COLORS VIDEO MODE.     '
        db 'WELL... WE LIED. THAT VIDEO MODE IS DISABLED IN THE 64K-RAM PCJR. '
        db 'AND WHEN YOU THINK ABOUT IT, IT MAKES SENSE. '
        db 'THE VIDEO RAM AND THE CPU RAM ARE SHARED IN THE PCJR. '
        db 'THAT CAUSES TWO VERY BAD THINGS:   '
        db 'FIRST: THERE IS NO VIDEO-RAM IN THE PCJR. '
        db 'THE CPU RAM IS USED FOR THE VIDEO AS WELL. SO, IF YOU USE 16K-RAM VIDEO MODE, '
        db 'YOU ONLY HAVE 48K-RAM LEFT FOR THE REST.'
        db '  '
        db 'AND THE SECOND THING IS: EVERYTIME THE VIDEO CARD ACCESSES THE RAM, '
        db 'IT ADDS SOME WAIT-STATES, MAKING THE MACHINE UP TO 2.5 TIMES SLOWER. '

        db '    '
        db 'THERE IS NO PC AS RAM-CONSTRAINED, AND SLOW AS THE 64K-RAM PCJR. '
        db 'AND THAT IS WHY WE LIKE IT. '
        db '    '

        db 'GOING BACK THE VIDEO MODES... '
        db 'THE 320 X 200 WITH 16 COLORS VIDEO MODE TAKES 32K-RAM. SO ONLY 32K-RAM '
        db 'IS LEFT FOR THE REST: INTERRUPT VECTOR TABLE, BIOS VARIABLES, '
        db ' AND DOS. '
        db 'AFTER THAT, YOU WILL ONLY HAVE ABOUT 10K RAM LEFT FOR YOUR PROGRAM.'
        db '... AND THAT IS PRETTY MUCH WHY THE VIDEO MODE IS DISABLED. '

        db '     '

        db 'BUT AS YOU CAN SEE IN THIS PART, YOU CAN STILL USE THE 320 X 200 WITH 16 COLORS '
        db 'VIDEO MODE... YOU JUST NEED TO BYPASS SOME BIOS CHECKS.'

        db '      '
        db 'ONE WONDERS WHAT WAS THE MARKET FOR THE 64K-RAM PCJR.   '
        db '              '
SCROLL_TEXT_LEN equ $-scroll_text

scroll_char_idx:                                ;pointer to the next char in text
        dw 0
scroll_char_col:                                ;total columns to render per char
        db CHARSET_COLS_PER_CHAR
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
        db      1                               ;when 1, a spacer of 4 pixels is rendered. occurs after
                                                ; rendering a char.
scroll_char_offset:                             ;Pointer to the char definition. Will get
        dw      0                               ; updated after each pass.
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; includes
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
%include 'common/utils.asm'
%include 'common/music_player.asm'
;%include 'common/zx7_8086.asm'

