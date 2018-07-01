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

        mov     ax,cs
        mov     ds,ax
        mov     ax,0xb800
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
        call    print_msg

        cmp     al,2                            ;is this a PCjr?
        jz      .is_pcjr                        ;yes!

        mov     dx,label_remove_diskette        ;not a PCjr
        mov     ah,9                            ;print msg using DOS
        int     0x21

        sub     ax,ax
        int     0x16                            ;wait key and...
;        int     0x19                            ; ...reboot
        int     0x20


.is_pcjr:
        call    detect_mem_128kb
        jnc     .not_128k

        call    detect_8088
        jb      .not_8088

        call    detect_jr_a_or_b

        mov     ah,1                            ;exit and load next part
        int     0x20


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

        sub     ah,ah                           ;don't clean screen
        int     0x20                            ; and load next file

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; in:
;       al = msg index to print
print_msg:
        push    ax                              ;save it

        sub     ah,ah
        shl     ax,1                            ;multiply by 2 (each address takes 2 bytes)
        mov     bx,ax
        mov     dx,[labels + bx]                ;get address from table
        mov     ah,9
        int     0x21                            ;DOS print msg

        pop     ax                              ;restore ax
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
labels:
        dw      label_is_mda
        dw      label_is_cga
        dw      label_is_pcjr
        dw      label_is_tandy_1000
        dw      label_is_tandy_sltl
        dw      label_is_ega
        dw      label_is_vga
        dw      label_is_mcga

           ;          1         2         3
           ;0123456789012345678901234567890123456789
label_is_mda:
        db 'Hercules detected. If this is true, then'
        db 'you cannot possible see this message    '
        db 'since this message uses segment 0xb800  '
        db '(instead of 0xb000)                     '
        db 'Cheater!!!                              '
        db '$'
label_is_cga:
        db "My friend, this demo doesn't run in a   "
        db 'CGA machine.                            '
        db '$'
label_is_pcjr:
        db 'IBM PCjr detected. Yay!                 '
        db '$'
label_is_tandy_1000:
        db 'Tandy 1000 detected. Do you know what   '
        db 'does it mean? That this demo is not     '
        db 'compatible with this machine.        :-('
        db '                                        '
        db 'So sad, since the Tandy 1000 and the    '
        db 'PCjr are almost the same, and making    '
        db 'this demo compatible with the Tandy 1000'
        db "is easy. But unfortunately we didn't    "
        db 'have time to do it. But if you write us '
        db 'demanding support for the Tandy 1000 we '
        db 'might port it to it. Mention the secret '
        db 'code: "Tandy 1000 & PCjr are the best". '
        db '$'
label_is_tandy_sltl:
        db "Tandy 1000 SL/TL detected. We don't     "
        db 'support modern Tandys. Sorry.           '
        db '$'
label_is_ega:
        db 'EGA detected. WTF is an EGA?.           '
        db 'Not supported                           '
        db '$'
label_is_vga:
        db 'Modern computer detected. Abort. Abort. '
        db '$'
label_is_mcga:
        db 'Are you really running this demo in an  '
        db 'IBM PS/2 model 25?                      '
        db 'I used to hate that computer ~25 years  '
        db 'ago. But now I am looking for one. If   '
        db 'want to donate one, I happily accept it.'
        db 'Thanks! :-)                             '
        db '$'

           ;          1         2         3
           ;0123456789012345678901234567890123456789
label_remove_diskette:
        db 'Remove the diskette and insert it in an '
        db 'IBM PCjr, the best computer ever!       '
        db '$'


           ;          1         2         3
           ;0123456789012345678901234567890123456789
label_above_128k:
        db 'This code is running above 0x10000.     '
        db "That means that you didn't boot from    "
        db 'diskette, correct?                      '
        db 'In any case, we let you continue running'
        db 'this demo because we are nice people.   '
        db '$'

label_not_8088:
        db 'But a real 8088 CPU was not detected.   '
        db 'Are you using a NEC v20 CPU? or most    '
        db 'probably inside an emulator?            '
        db 'If so, we let you continue running this '
        db 'demo, because we are nice peopel.       '
        db "But this demo doesn't work Ok on DosBox."
        db 'And NEC v20 was not tested.             '
        db 'Run it at your own risk.                '
        db '$'

label_warning:
        db 'Press any key to continue               '
        db '$'

label_pcjr_a_b:
        db 'PCjr '
label_model:
        db '?'
        db ' detected.',13,10,'$'

old_pic_imr:
        db 0
