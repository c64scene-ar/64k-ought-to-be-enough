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
        resb    0x100                           ;cannot use "org 0x100" when using multiple .o files

        mov     ax,cs
        mov     ds,ax
        mov     ax,0xb800
        mov     es,ax
        

        cld

        call    detect_card
        cmp     al,2
        jnz     not_pcjr

        call    detect_mem_128kb
        jc      not_128k

        call    detect_8088
        jb      not_8088

        call    detect_jr_a_or_b

        mov     ah,1                            ;exit and load next part
        int     0x20


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
not_pcjr:
        mov     si,label_not_pcjr
        call    print_dos_msg
        jmp     exit_with_error

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
not_128k:
        mov     si,label_not_128k
        call    print_dos_msg
        jmp     exit_with_error

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
not_8088:
        mov     si,label_not_8088
        call    print_dos_msg
        jmp     exit_with_error

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
exit_with_error:
        mov     si,label_fatal_error
        call    print_dos_msg
        int     0x19                            ;reboot


;        mov     ax,0xffff                       ;reboot machine
;        sub     bx,bx
;        push    ax
;        push    bx
;        retf

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
print_dos_msg:
        lodsb
        or      al,al
        jz      .exit

        stosb
        inc     di                              ;di =+ 2 to skip attribute

.exit:
        ret

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

        mov     cx,0xffff                       ;delay
.l1:
        mul     al
        loop    .l1

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
label_not_pcjr:
        db 'This demo only works on IBM PCjr computers.',13,10,0

label_not_128k:
        db 'PCjr with at least 256kb RAM needed. Code should run above 128kb RAM',13,10,0

label_not_8088:
        db 'An 8088 CPU is needed. No NEC v20, no emulators. Thanks.',13,10,0

label_fatal_error:
        db 'This is a fatal error.',0

label_pcjr_a_b:
        db 'PCjr '
label_model:
        db '?'
        db ' detected.',13,10,0

old_pic_imr:
        db 0
