; Invite intro for Flashparty 2018
; Pungas de Villa Martelli - http://pungas.space
;
; code: riq (http://retro.moe)

bits    16
cpu     8086


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; MACROS
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; CODE
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
org     0x100                                   ;it is a .com
main:
        mov     ax,0x0001                       ;40x25 color
        int     0x10

        call    show_msg

        sub     ax,ax
        int     0x16                            ;wait key
        int     0x20
        int     0x19                            ;reboot

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
show_msg:
        mov     ax,0xb800
        mov     es,ax
        mov     ax,cs
        mov     ds,ax
        mov     si,msg
        sub     di,di

.l0:    lodsb                           ;loads SI into AL
        or      al,al                   ;checks whether the end of the string
        jz      .exit                   ;exit if so
        stosb
        inc     di                      ;skip attrib value
        jmp     .l0                     ;and loop

.exit:
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
msg:
           ;          1         2         3
           ;0123456789012345678901234567890123456789
        db 'This demo is intended to run in a PCjr  '
        db 'with 64k RAM (or more).                 '
        db 'Since the PCjr with 64K does not have   '
        db 'enough RAM both for the DOS and this    '
        db 'demo, booting from this disk is required'
        db '                                        '
        db '                                        '
        db '       PRESS ANY KEY TO REBOOT          '
        db 0
