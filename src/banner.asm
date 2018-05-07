; Invite intro for Flashparty 2018
; Pungas de Villa Martelli - http://pungas.space
;
; code: riq (http://retro.moe)

bits    16
cpu     8086

extern label_model
extern lz4_decompress, lz4_decompress_small
extern dzx7_speed, dzx7_size, dzx7_original
extern irq_8_cleanup, irq_8_init

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
;
; CODE
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
section .text

global banner_start
banner_start:
        cld

        mov     ax,banner_data                  ;init segments
        mov     ds,ax                           ;these values must always be true
        mov     ax,GFX_SEG                      ; through the whole intro.
        mov     es,ax                           ; push/pop otherwise

        call    banner_init

        call    banner_main_loop

        call    banner_cleanup

        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
banner_init:
        push    ds
        push    es

        mov     ax,banner_irq_8
        call    irq_8_init

        mov     ax,0x0004                       ;320x200 4 colors
        int     0x10

        mov     cx,20
.loop:
        push    cx

        ;--- P ---
        mov     ax,banner_data                  ;ds:si (source)
        mov     ds,ax
        mov     si,letter_p_lz4

        mov     ax,0x1800                       ;es:di (destination)
        mov     es,ax
        mov     di,0x4000

        call    lz4_decompress


        ;--- V ---
        mov     ax,banner_data                  ;ds:si (source)
        mov     ds,ax
        mov     ax,0x1800                       ;es:di (destination)
        mov     es,ax

        mov     si,letter_v_lz4
        mov     di,0x4000
        call    lz4_decompress


        ;--- M ---
        mov     ax,banner_data                  ;ds:si (source)
        mov     ds,ax
        mov     ax,0x1800                       ;es:di (destination)
        mov     es,ax

        mov     si,letter_m_lz4
        mov     di,0x4000
        call    lz4_decompress

        pop     cx
        loop    .loop

        pop     es
        pop     ds
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
banner_cleanup:
        call    irq_8_cleanup
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
banner_main_loop:

.loop:
%if EMULATOR
        cli                                     ;on emulator, test for keyboard buffer

        push    ds
        push    ax

        sub     ax,ax
        mov     ds,ax                           ;ds = zero page
        mov     ax, [0x41a]                     ;keyboard buffer head
        cmp     ax, [0x41c]                     ;keyboard buffer tail

        pop     ax
        pop     ds
        sti
%else
        in      al,0x62                         ;on real hardware, test keystroke missed?
        and     al,1                            ; so that we can disable IRQ9
%endif
        jz      .loop

        int 3

        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
banner_irq_8:
        mov     al,0x20                         ;send the EOI signal
        out     0x20,al                         ; to the IRQ controller

        iret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; DATA GFX
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
section .banner_data data
letter_p_lz4:
        incbin 'src/p.raw.lz4'
letter_v_lz4:
        incbin 'src/v.raw.lz4'
letter_m_lz4:
        incbin 'src/m.raw.lz4'

