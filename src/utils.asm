; Invite intro for Flashparty 2018
; Pungas de Villa Martelli - http://pungas.space
;
; code: riq (http://retro.moe)

bits    16
cpu     8086

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; CODE
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

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
;waits until the beam is about to return to the top-left
;should be the one to call for the effects
global wait_vertical_retrace
wait_vertical_retrace:
        mov     dx,0x03da
        WAIT_VERTICAL_RETRACE
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
global wait_horiz_retrace
wait_horiz_retrace:
        mov     dx,0x03da
        WAIT_HORIZONTAL_RETRACE
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; installs a timer IRQ that triggers at the correct horizontal scan line
; for the scroll
; input:
; ax = offset for the new irq 8 handler
; assumes segment is cs
global irq_8_init
irq_8_init:

PIT_DIVIDER equ (262*76)                        ;262 lines * 76 PIT cycles each
                                                ; make it sync with vertical retrace

        cli                                     ;disable interrupts

        push    es
        push    ds

        mov     bp,es                           ;save es
        sub     bx,bx
        mov     es,bx                           ;es = page 0

        ;PIC
        mov     dx,cs
        xchg    ax,[es:8*4]                     ;new/old IRQ 8: offset
        xchg    dx,[es:8*4+2]                   ;new/old IRQ 8: segment
        mov     [cs:old_i08],ax
        mov     [cs:old_i08+2],dx

        mov     es,bp                           ;restore es

        mov     dx,0x03da
        WAIT_VERTICAL_RETRACE

        mov     cx,194                          ;and wait for scanlines
.repeat:
        WAIT_HORIZONTAL_RETRACE                 ;inlining, so timing in real machine
        loop    .repeat                         ; is closer to emulators

        mov     bx,PIT_DIVIDER                  ;Configure the PIT to
        call    setup_pit                       ;setup PIT

        in      al,0x21                         ;Read primary PIC Interrupt Mask Register
        mov     [cs:old_pic_imr],al             ;Store it for later
        mov     al,0b1111_1110                  ;Mask off everything except IRQ0 (timer)
        out     0x21,al

        in      al,0xa0                         ;clear nmi latch
        sub     al,al
        out     0xa0,al
        sti                                     ;enable interrupts

        pop     ds
        pop     es
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
global irq_8_cleanup
irq_8_cleanup:
        cli                                     ;disable interrupts

        in      al,0xa0                         ;clear nmi latch
        mov     al,0b1000_0000                  ;enable nmi
        out     0xa0,al

        mov     al,[cs:old_pic_imr]             ;Get old PIC settings
        out     0x21,al                         ;Set primary PIC Interrupt Mask Register

        mov     bx,0                            ;Reset PIT to defaults (~18.2 Hz)
        call    setup_pit                       ; actually means 0x10000

        push    ds
        push    es

        xor     ax,ax
        mov     ds,ax                           ;ds = page 0

        les     si,[cs:old_i08]
        mov     [8*4],si
        mov     [8*4+2],es                      ;Restore the old INT 08 vector (timer)

        pop     es
        pop     ds

        sti                                     ;enable interrupts
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
setup_pit:
        ; IN    bx = PIT clock period
        ;          (Divider to 1193180 Hz)
        mov     al,0b0011_0100                  ;0x34: channel 0, access mode lo/hi, rate generator, 16-bit binary
        out     0x43,al                         ;command port
        mov     ax,bx
        out     0x40,al                         ;data port for IRQ0: freq LSB
        mov     al,ah
        nop                                     ;some pause
        nop
        out     0x40,al                         ;data port for IRQ0: freq MSB

        ret

old_i08:                                        ;segment + offset to old int 8 (timer)
        dd      0
old_pic_imr:                                    ;PIC IMR original value
        db      0

