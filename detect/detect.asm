;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; "Ought to be enough" - Detect computer
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; Pungas de Villa Martelli - http://pungas.space
;
; code: riq (http://retro.moe)
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; Reusing code and comments from Paku Paku game.
; http://www.deathshadow.com/pakuPaku
;

;       Detecting which video card is present is kinda tricky...
;       but thankfully they did something smart with int 0x10.
;       Calls to unknown subfunctions just RET leaving registers
;       intact, so if you call a VGA function that you know changes
;       a register, and the register doesn't change, it's not a VGA.
;       Call a EGA function ditto, ditto... finally check if we're in
;       a monochrome display mode, that's MDA.
;
;       Unfortunately there's no known reliable check for a CGA since
;       newer cards pretend to be one -- but if we eliminate
;       'everything else' from the list, it must be CGA.

bits    16
cpu     8086

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; CODE
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
extern ZTimerOn, ZTimerOff, ZTimerGetTime, ZTimerReport
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; Macros and defines
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
VIDEOCARD_MDA           equ 0
VIDEOCARD_CGA           equ 1
VIDEOCARD_PCJR          equ 2
VIDEOCARD_TANDY1000     equ 3
VIDEOCARD_TANDYSLTL     equ 4
VIDEOCARD_EGA           equ 5
VIDEOCARD_VGA           equ 6
VIDEOCARD_MCGA          equ 7

;
..start:
main:
        resb    0x100                           ;cannot use "org 0x100" when using multiple .o files

        mov     ax,cs                           ;setup segments that should be valid in this whole part
        mov     ds,ax                           ;data
        mov     ax,0xb800                       ;graphics
        mov     es,ax

        cld

        ; al =  0 -> MDA
        ;       1 -> CGA
        ;       2 -> PCjr
        ;       3 -> Tandy 1000
        ;       4 -> Tandy SL/TL
        ;       5 -> EGA
        ;       6 -> VGA
        ;       7 -> MCGA
        call    detect_card

        cmp     al,2                            ;is this a PCjr?
        jz      .is_pcjr                        ;yes!

        mov     ax,0x0003                       ;80x25 video mode
        int     0x10

        sub     ax,ax
        mov     ds,ax
        mov     bx,0xb800                       ;video seg for color
        mov     ax,[0x0463]                     ;BIOS CRT controller base address
        cmp     ax,0x3b4                        ;Hercules?
        jnz     .set_seg                        ; no, use previous value
        mov     bx,0xb000                       ;hercules video segment
.set_seg:
        mov     es,bx                           ;set new video segment

        push    cs
        pop     ds                              ;restore ds

        mov     cx,80*25                        ;copy 2000 bytes
        mov     si,ascii_art
        sub     di,di

.loop:
        lodsb                                   ;load ascii value
        stosb                                   ;copy ascii value
        inc     di                              ;skip attribute
        loop    .loop

        sub     ax,ax
        int     0x16                            ;wait key and...

        int     0x19                            ; ...reboot

;        mov     ah,0x4c                         ;ricarDOS: load next file
;        int     0x21                            ;DOS: exit


.is_pcjr:
        mov     dx,label_is_pcjr
        mov     ah,9
        int     0x21

        call    detect_mem_128kb
        jnc     .not_128k

        call    detect_8088
        jb      .not_8088

        call    detect_jr_a_or_b

        mov     ax,0x4c00                       ;ricarDOS: load next file. Don't clear screen
        int     0x21                            ;DOS: exit


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.not_128k:
        mov     dx,label_above_128k
        mov     ah,9
        int     0x21                            ;DOS print msg
        jmp     exit_with_warning

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.not_8088:
        mov     dx,label_not_8088
        mov     ah,9
        int     0x21                            ;DOS print msg

        ;
        ;fall-through
        ;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
exit_with_warning:
        mov     dx,label_warning
        mov     ah,9
        int     0x21                            ;DOS print msg

        sub     ax,ax
        int     0x16                            ;wait key

        mov     ax,0x4c00                       ;ricarDOS: load next file, don't clear screen
        int     0x21                            ;DOS: exit


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
detect_mem_128kb:
        mov     ax,cs
        cmp     ax,0x1000
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
detect_jr_a_or_b:
        cli                                     ;disable interrupts
        sub     al,al
        out     0xa0,al                         ;disable nmi

        in      al,0x21                         ;Read primary PIC Interrupt Mask Register
        mov     [old_pic_imr],al                ;Store it for later
        mov     al,0b1111_1110                  ;mask off everything except Timer interrupt
        out     0x21,al

        mov     cx,1000
        call    ZTimerOn

.l0:    loop    .l0

        call    ZTimerOff
        call    ZTimerGetTime                   ;returns in AX epased time in microseconds
                                                ; PCjr A ~= 3829
                                                ; PCjr B ~= 3907
        cmp     ax,3868                         ;Middle value between 3829 and 3907
        jb      .is_a
        mov     al,'B'
        jmp     .store_value
.is_a:
        mov     al,'A'
.store_value:
        mov     [label_model],al
        mov     al,[old_pic_imr]
        out     0x21,al                         ;restore interrupts
        mov     al,0b1000_0000
        out     0xa0,al                         ;enable nmi

        mov     ah,9
        mov     dx,label_pcjr_a_b
        int     0x21

        sti                                     ;re-enable interrupts
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
detect_8088:
        cli                                     ;disable interrupts
        sub     al,al
        out     0xa0,al                         ;disable nmi

        in      al,0x21                         ;Read primary PIC Interrupt Mask Register
        mov     [old_pic_imr],al                ;Store it for later
        mov     al,0b1111_1110                  ;mask off everything except Timer interrupt
        out     0x21,al

        mov     cx,1000
        call    ZTimerOn

        times 100 mul ax                        ;measure `mul` performance

        call    ZTimerOff
        call    ZTimerGetTime                   ;returns in AX epased time in microseconds
                                                ; intel 8088: ~1466
        cmp     ax,1450                         ;compare with 1450... a little faster than usual

        mov     al,[old_pic_imr]
        out     0x21,al                         ;restore interrupts
        mov     al,0b1000_0000
        out     0xa0,al                         ;enable nmi

        sti                                     ;re-enable interrupts
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; detect_card:
; output:
; al =  0 -> MDA
;       1 -> CGA
;       2 -> PCjr
;       3 -> Tandy 1000
;       4 -> Tandy SL/TL
;       5 -> EGA
;       6 -> VGA
;       7 -> MCGA
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
detect_card:
        mov     ax,0x1200
        mov     bl,0x32                 ;VGA only enable video
        int     0x10
        cmp     al,0x12                 ;VGA returns 0x12, all others leave it unmodified!
        jne     .notVGA                 ;not a vga, test for EGA
                                        ; VGA, or is it? test for MCGA
        xor     bl,bl                   ;null BL so it's set up for non-PS/2
        mov     ax,0x1a00
        int     0x10
        cmp     bl,0x0a                 ;MCGA returns 0x0a..0x0c
        jb      .isVGA
        cmp     bl,0x0c
        jg      .isVGA
        mov     al,VIDEOCARD_MCGA
        ret
.isVGA:
        mov     al,VIDEOCARD_VGA
        ret
.notVGA:                                ;We eliminated VGA, so an EGA/VGA true must be EGA
        mov     ah,0x12
        mov     bl,0x10                 ;EGA/VGA get configuration info
        int     0x10
        and     bl,0x03                 ;EGA/VGA returns a 0..3 value here
        jz      .notEGA                 ;not a VGA, test for MDA
        mov     al,VIDEOCARD_EGA
        ret
.notEGA:                                ;MDA all we need to detect is video mode 7
        mov     ah,0x0f                 ;get Video mode
        int     0x10
        cmp     al,0x07
        jne     .notMDA
        mov     al,VIDEOCARD_MDA
        ret
.notMDA:                                ;not MDA, check for Jr.
        mov     ax,0xffff
        mov     es,ax
        mov     di,0x000e               ;second to last byte PCjr/Tandy BIOS info area
        cmp     byte [es:di],0xfd       ;ends up 0xfd only on the Jr.
        jne     .notJr
        mov     al,VIDEOCARD_PCJR
        ret
.notJr:                                 ;not junior, test for tandy
        cmp     byte [es:di],0xff       ;all tandy's return 0xff here
        jne     .notTandy
        mov     ax,0xfc00
        mov     es,ax
        xor     di,di
        cmp     byte [es:di],0x21
        jne     .notTandy
        mov     ah,0xc0                 ;test for SL/TL
        int     0x15                    ;Get System Environment
        jnc     .tandySLTL              ;early Tandy's leave the carry bit set, TL/SL does not
        mov     al,VIDEOCARD_TANDY1000
        ret
.tandySLTL:
        mov     al,VIDEOCARD_TANDYSLTL
        ret
.notTandy:
        mov     al,VIDEOCARD_CGA        ;all other cards eliminated, must be CGA
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; DATA
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
label_is_pcjr:
        db 'IBM PCjr detected. Yay!'                 ,13,10
        db '$'

           ;          1         2         3
           ;0123456789012345678901234567890123456789
label_above_128k:
        db 'This code is running above 0x10000.'     ,13,10
        db "That means that you didn't boot from"    ,13,10
        db 'diskette, correct?'                      ,13,10
        db 'In any case, we let you continue running',13,10
        db 'this demo because we are nice people.'   ,13,10
        db '$'

label_not_8088:
        db 'But a real 8088 CPU was not detected.'   ,13,10
        db 'Are you using a NEC v20 CPU? or most'    ,13,10
        db 'probably inside an emulator?'            ,13,10
        db 'If so, we let you continue running this' ,13,10
        db 'demo, because we are nice people.'       ,13,10
        db "But this demo doesn't work Ok on DosBox.",13,10
        db 'And NEC v20 was not tested.'             ,13,10
        db 'Run it at your own risk.'                ,13,10
        db '$'

label_warning:
        db 13,10,'Press any key to continue               '
        db '$'

label_pcjr_a_b:
        db '(PCjr model '
label_model:
        db '?'
        db ' detected)',13,10,'$'

old_pic_imr:
        db 0

ascii_art:
        incbin          'detect/arl-64k2.asc'
