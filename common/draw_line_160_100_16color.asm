;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; Name:     Line08
;
; Function: Draw a line in 120x100 16-color mode
;
; Caller must file:
;       Line08_x1
;       Line08_y1
;       Line08_x2
;       Line08_y2
;       Line08_color
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; From:
;       Programmers's Guide To PC & PS/2: Video Systems
;       by Richard Wilton
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; Adapted to nasm and, PCjr's 160x100 16-color: riq
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

ByteOffsetShift EQU 1                   ; used to convert pixels to byte offset
BytesPerLine    EQU 80

Line08_draw:
        push    si
        push    di
        push    ds

        cmp     ax,159
        ja      .error
        cmp     bx,99
        ja      .error
        cmp     cx,159
        ja      .error
        cmp     dx,99
        ja      .error
        jmp     .skip
.error:
        int 3
        jmp     .error

.skip:
; check for vertical line
        mov     si,BytesPerLine         ; initial y-increment

        sub     cx,ax                   ; CX := x2 - x1
        jz      VertLine04              ; jump if vertical line

; force x1 < x2

        jns     .l01                    ; jump if x2 > x1

        neg     cx                      ; CX := x1 - x2

        mov     bl,[Line08_x2]          ; exchange x1 and x2
        xchg    bl,[Line08_x1]
        mov     [Line08_x2],bl

        mov     bl,[Line08_y2]          ; exchange y1 and y2
        xchg    bl,[Line08_y1]
        mov     [Line08_y2],bl

; calculate dy = ABS(y2-y1)

.l01:   mov     bx,[Line08_y2]
        sub     bx,[Line08_y1]          ;BX := y2 - y1
        jnz     .l02

        jmp     HorizLine04             ; jump if horizontal line

.l02:   jns     .l03

        neg     bx                      ; BX := y1 - y2
        neg     si                      ; negate y-increment

; select appropriate routine for slope of line

.l03:   push    si                      ; preserve y-increment

        mov     word [VARroutine],LoSlopeLine04
        cmp     bx,cx
        jle     .l04                    ; jump if dy <= dx (slope <= 1)
        mov     word [VARroutine],HiSlopeLine04
        xchg    bx,cx                   ; exchange dy and dx

; calculate initial decision variable and increments

.l04:   shl     bx,1                    ; BX := 2 * dy
        mov     [VARincr1],bx           ; incr1 := 2 * dy
        sub     bx,cx
        mov     si,bx                   ; SI := d = 2 * dy - dx
        sub     bx,cx
        mov     [VARincr2],bx           ; incr2 := 2 * (dy - dx)

; calculate first pixel address

        push    cx                      ; preserve this register
        mov     al,[Line08_y1]          ; AX := y
        mov     bl,[Line08_x1]          ; BX := x
        call    PixelAddr08             ; AH := bit mask
                                        ; ES:BX -> buffer
                                        ; CL := # bits to shift left
        mov     al,[Line08_color]       ; AL := unshifted pixel value
        shl     ax,cl                   ; AH := bit mask in proper position
                                        ; AL := pixel value in proper position

        mov     dx,ax                   ; DH := bit mask
                                        ; DL := pixel value
        not     dh                      ; DH := inverse bit mask
        mov     di,bx                   ; ES:DI -> buffer

        pop     cx                      ; restore this register
        inc     cx                      ; CX := # of pixels to draw

        pop     bx                      ; BX := y-increment

.l05:    jmp     [VARroutine]            ; jump to appropriate routine for slope


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; routine for vertical lines

VertLine04:
        mov     al,[Line08_y1]          ; AX := y1
        mov     bl,[Line08_y2]          ; BX := y2
        mov     cl,bl
        sub     cl,al                   ; CX := dy
        jge     .l31                    ; jump if dy >= 0

        neg     cl                      ; force dy >= 0
        mov     al,bl                   ; AX := y2

.l31:   inc     cl                      ; CX := # of pixels to draw
        mov     bl,[Line08_x1]          ; BX := x
        push    cx                      ; preserve this register
        call    PixelAddr08             ; AH := bit mask
                                        ; ES:BX -> video buffer
                                        ; CL := # bits to shift left
        mov     al,[Line08_color]       ; AL := pixel value
        shl     ax,cl                   ; AH := bit mask in proper position
                                        ; AL := pixel value in proper position
        not     ah                      ; AH := inverse bit mask
        pop     cx                      ; restore this register

        mov     di,es
        mov     ds,di                   ;DS: vdieo buffer

.l32:   and     [bx],ah                 ; zero pixel in buffer
        or      [bx],al                 ; set pixel value in buffer

        add     bx,si                   ; increment to next portion of interleave

        loop    .l32

        jmp     Lexit


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; routine for horizontal lines (slope = 0)

HorizLine04:
        mov     al,[Line08_y1]
        mov     bl,[Line08_x1]
        call    PixelAddr08             ; AH := bit mask
                                        ; ES:BX -> video buffer
                                        ; CL := # bits to shift left
        mov     di,bx                   ; ES:DI -> buffer

        mov     dh,ah
        not     dh                      ; DH := unshifted bit mask for leftmost
                                        ;        byte
        mov     dl,0xff                 ; DL := unshifted bit mask for
                                        ;    rightmost byte

        shl     dh,cl                   ; DH := reverse bit mask for first byte
        not     dh                      ; DH := bit mask for first byte

        mov     cl,[Line08_x2]          ;cx = x2
        and     cl,1                    ;cl = x2 & 1
        xor     cl,1                    ;cl = !cl
        shl     cl,1                    ; CL := number of bits to shift left
        shl     cl,1                    ; CL := number of bits to shift left
        shl     cl,1                    ; CL := number of bits to shift left
        shl     dl,cl                   ; DL := bit mask for last byte

; determine byte offset of first and last pixel in the line

        mov     al,[Line08_x2]          ; AX := x2
        mov     ah,[Line08_x1]          ; BX := x1

        mov     cl,ByteOffsetShift      ; number of bits to shift to
                                        ;  convert pixels to bytes

        shr     al,cl                   ; AX := byte offset of x2
        shr     ah,cl                   ; BX := byte offset of x1
        mov     cl,al
        sub     cl,ah                   ; CX := (# bytes in line) - 1

; propagate pixel value throughout one byte

        mov     bx,PropagatedPixel
        mov     al,[Line08_color]       ; AL := pixel value
        xlatb                           ; AL := propagated pixel value

        mov     bp,es
        mov     ds,bp                   ;ds = video segment

; set pixels in leftmost byte of the line

        or      dh,dh
        js      .l43                    ; jump if byte-aligned (x1 is leftmost
                                        ;  pixel in byte)
        or      cx,cx
        jnz     .l42                     ; jump if more than one byte in the line

        and     dl,dh                   ; bit mask for the line
        jmp     .l44

.l42:   mov     ah,al
        and     ah,dh                   ; AH := masked pixel bits
        not     dh                      ; DH := reverse bit mask for 1st byte
        and     [di],dh                 ; zero masked pixels in buffer
        or      [di],ah                 ; update masked pixels in buffer
        inc     di
        dec     cx

; use a fast 8086 machine instruction to draw the remainder of the line

.l43:   rep stosb                       ; update all pixels in the line

; set pixels in the rightmost byte of the line

.l44:   and     al,dl                   ; AL := masked pixels for last byte
        not     dl
        and     [di],dl                 ; zero masked pixels in buffer
        or      [di],al                 ; update masked pixels in buffer

        jmp     Lexit

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; routine for dy <= dx (slope <= 1)
                    ; ES:DI -> video buffer
					; BX = y-increment
					; CX = # pixels to draw
					; SI = decision variable
                    ; DH = inverse bit mask
                    ; DL = pixel value in proper position
                    ; CH = pixel value in both MSB and LSB

LoSlopeLine04:
        mov     bp,[VARincr1]

        mov     ax,es
        mov     ds,ax                   ;ds = video segment

.l10:   mov     ah,[di]                 ; AH := byte from video buffer

.l11:   and     ah,dh                   ; zero pixel value at current bit offset
        or      ah,dl                   ; set pixel value in byte

        ror     dl,1
        ror     dl,1
        ror     dl,1
        ror     dl,1

        xor     dh,255                  ;swap mask. using 'xor' instead of 'not' since testing for sign bit
        jns     .l14                    ; jump if bit mask rotated to
                                        ;  leftmost pixel position

; bit mask not shifted out

        or      si,si                   ; test sign of d
        jns     .l12                    ; jump if d >= 0

        add     si,bp                   ; d := d + incr1
        loop    .l11

        mov     [di],ah                 ; store remaining pixels in buffer
        jmp     Lexit

.l12:   add     si,[cs:VARincr2]        ; d := d + incr2
        mov     [di],ah                 ; update buffer

        add     di,bx                   ; increment y

        loop    .l10
        jmp     Lexit

; bit mask shifted out

.l14:   mov     [di],ah                 ; update buffer
        inc     di                      ; di := offset of next byte

        or      si,si                   ; test sign of d
        jns     .l15                    ; jump if non-negative

        add     si,bp                   ; d := d + incr1
        loop    .l10
        jmp     Lexit


.l15:   add     si,[cs:VARincr2]        ; d := d + incr2

        add     di,bx                   ; increment y

        loop    .l10
        jmp     Lexit

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; routine for dy > dx (slope > 1)
;       ES:DI -> video buffer
;       BX = y-increment
;       CX = # pixels to draw
;       SI = decision variable
;       DH = inverse bit mask
;       DL = pixel value in proper position
HiSlopeLine04:
        mov     bp,[VARincr1]           ;bp := VARincr1
        mov     ax,es
        mov     ds,ax                   ;ds points to video seg
        mov     ax,[cs:VARincr2]        ;ax := VARincr2


.l21:   and     [di],dh                 ; zero pixel value in video buffer
        or      [di],dl                 ; set pixel value in byte

        add     di,bx                   ; increment y

.l22:   or      si,si                   ; test sign of d
        jns     .l23                     ; jump if d >= 0

        add     si,bp                   ; d := d + incr1
        loop    .l21

        jmp     Lexit


.l23:   add     si,ax                   ; d := d + incr2

        ror     dl,1                    ; rotate pixel value
        ror     dl,1                    ; rotate pixel value
        ror     dl,1                    ; rotate pixel value
        ror     dl,1                    ; rotate pixel value
        xor     dh,255                  ;swap bit mask
        js      .l24
        inc     di                      ; BX := offset of next byte
.l24:

        loop    .l21

        ; fall through

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
Lexit:
        pop     ds
        pop     di      ; restore registers and return
        pop     si
        ret

PropagatedPixel:
        db      0b0000_0000       ; 0
        db      0b0001_0001       ; 1
        db      0b0010_0010       ; 2
        db      0b0011_0011       ; 3
        db      0b0100_0100       ; 4
        db      0b0101_0101       ; 5
        db      0b0110_0110       ; 6
        db      0b0111_0111       ; 7
        db      0b1000_1000       ; 8
        db      0b1001_1001       ; 9
        db      0b1010_1010       ; 10
        db      0b1011_1011       ; 11
        db      0b1100_1100       ; 12
        db      0b1101_1101       ; 13
        db      0b1110_1110       ; 14
        db      0b1111_1111       ; 15

VARincr1:       dw      0
VARincr2:       dw      0
VARroutine:     dw      0

;public variables
Line08_x1:      dw      0               ;x1
Line08_x2:      dw      0               ;x2
Line08_y1:      dw      0               ;y1
Line08_y2:      dw      0               ;y2
Line08_color:   db      0               ;color


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; Includes
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
%include 'common/pixel_addr_160_100_16color.asm'
