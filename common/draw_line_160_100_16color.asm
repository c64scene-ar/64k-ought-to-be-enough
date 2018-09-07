;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; Name:     Line04
;
; Function: Draw a line in 320x200 16-color mode
;
; Caller:
;       ax =    x1
;       bl =    y1
;       cx =    x2
;       dx =    y2
;       bp =    color
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; From:
;       Programmers's Guide To PC & PS/2: Video Systems
;       by Richard Wilton
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; Adapted to nasm and, PCjr's 320x200 16-color: riq
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

ByteOffsetShift EQU 1       ; used to convert pixels to byte offset
BytesPerLine    EQU 80

Line08:
        push    si
        push    di

        mov     [ARGx1],ax              ;tmp for x1
        mov     [ARGy1],bx              ;tmp for y1
        mov     [ARGx2],cx              ;tmp for x2
        mov     [ARGy2],dx              ;tmp for y2
        mov     dx,bp
        mov     [ARGn],dl               ;tmp for color

; check for vertical line
        mov     si,BytesPerLine         ; initial y-increment

        sub     cx,ax                   ; CX := x2 - x1
        jz      VertLine04              ; jump if vertical line

; force x1 < x2

        jns     L01                     ; jump if x2 > x1

        neg     cx                      ; CX := x1 - x2

        mov     bx,[ARGx2]              ; exchange x1 and x2
        xchg    bx,[ARGx1]
        mov     [ARGx2],bx

        mov     bx,[ARGy2]               ; exchange y1 and y2
        xchg    bx,[ARGy1]
        mov     [ARGy2],bx

; calculate dy = ABS(y2-y1)

L01:    mov     bx,[ARGy2]
        sub     bx,[ARGy1]              ;BX := y2 - y1
        jnz     L02

        jmp     HorizLine04             ; jump if horizontal line

L02:    jns     L03

        neg     bx                      ; BX := y1 - y2
        neg     si                      ; negate y-increment

; select appropriate routine for slope of line

L03:    push    si                      ; preserve y-increment

        mov     word [VARroutine],LoSlopeLine04
        cmp     bx,cx
        jle     L04                     ; jump if dy <= dx (slope <= 1)
        mov     word [VARroutine],HiSlopeLine04
        xchg    bx,cx                   ; exchange dy and dx

; calculate initial decision variable and increments

L04:    shl     bx,1                    ; BX := 2 * dy
        mov     [VARincr1],bx           ; incr1 := 2 * dy
        sub     bx,cx
        mov     si,bx                   ; SI := d = 2 * dy - dx
        sub     bx,cx
        mov     [VARincr2],bx           ; incr2 := 2 * (dy - dx)

; calculate first pixel address

        push    cx                      ; preserve this register
        mov     ax,[ARGy1]              ; AX := y
        mov     bx,[ARGx1]              ; BX := x
        call    PixelAddr08             ; AH := bit mask
                                        ; ES:BX -> buffer
                                        ; CL := # bits to shift left

        mov     al,[ARGn]               ; AL := unshifted pixel value
        shl     ax,cl                   ; AH := bit mask in proper position
                                        ; AL := pixel value in proper position

        mov     dx,ax                   ; DH := bit mask
                                        ; DL := pixel value
        not     dh                      ; DH := inverse bit mask
        mov     di,bx                   ; ES:DI -> buffer

        pop     cx                      ; restore this register
        inc     cx                      ; CX := # of pixels to draw

        pop     bx                      ; BX := y-increment

L05:    jmp     [VARroutine]            ; jump to appropriate routine for slope


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; routine for vertical lines

VertLine04:
        mov     ax,[ARGy1]              ; AX := y1
        mov     bx,[ARGy2]              ; BX := y2
        mov     cx,bx
        sub     cx,ax                   ; CX := dy
        jge     L31                     ; jump if dy >= 0

        neg     cx                      ; force dy >= 0
        mov     ax,bx                   ; AX := y2

L31:    inc     cx                      ; CX := # of pixels to draw
        mov     bx,[ARGx1]              ; BX := x
        push    cx                      ; preserve this register
        call    PixelAddr08             ; AH := bit mask
                                        ; ES:BX -> video buffer
                                        ; CL := # bits to shift left
        mov     al,[ARGn]               ; AL := pixel value
        shl     ax,cl                   ; AH := bit mask in proper position
                                        ; AL := pixel value in proper position
        not     ah                      ; AH := inverse bit mask
        pop     cx                      ; restore this register


L32:    and     [es:bx],ah              ; zero pixel in buffer
        or      [es:bx],al              ; set pixel value in buffer

        add     bx,si                   ; increment to next portion of interleave

        loop    L32

        jmp     Lexit



;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; routine for horizontal lines (slope = 0)

HorizLine04:
        mov     ax,[ARGy1]
        mov     bx,[ARGx1]
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

        mov     cx,[ARGx2]              ;cx = x2
        and     cl,1                    ;cl = x2 & 1
        xor     cl,1                    ;cl = !cl
        shl     cl,1                    ; CL := number of bits to shift left
        shl     cl,1                    ; CL := number of bits to shift left
        shl     cl,1                    ; CL := number of bits to shift left
        shl     dl,cl                   ; DL := bit mask for last byte

; determine byte offset of first and last pixel in the line

        mov     ax,[ARGx2]              ; AX := x2
        mov     bx,[ARGx1]              ; BX := x1

        mov     cl,ByteOffsetShift      ; number of bits to shift to
                                        ;  convert pixels to bytes

        shr     ax,cl                   ; AX := byte offset of x2
        shr     bx,cl                   ; BX := byte offset of x1
        mov     cx,ax
        sub     cx,bx                   ; CX := (# bytes in line) - 1

; propagate pixel value throughout one byte

        mov     bx,PropagatedPixel
        mov     al,[ARGn]               ; AL := pixel value
        xlatb                           ; AL := propagated pixel value

; set pixels in leftmost byte of the line

        or      dh,dh
        js      L43                     ; jump if byte-aligned (x1 is leftmost
                                        ;  pixel in byte)
        or      cx,cx
        jnz     L42                     ; jump if more than one byte in the line

        and     dl,dh                   ; bit mask for the line
        jmp     short L44

L42:    mov     ah,al
        and     ah,dh                   ; AH := masked pixel bits
        not     dh                      ; DH := reverse bit mask for 1st byte
        and     [es:di],dh              ; zero masked pixels in buffer
        or      [es:di],ah              ; update masked pixels in buffer
        inc     di
        dec     cx

; use a fast 8086 machine instruction to draw the remainder of the line

L43:    rep stosb                       ; update all pixels in the line

; set pixels in the rightmost byte of the line

L44:    and     al,dl                   ; AL := masked pixels for last byte
        not     dl
        and     [es:di],dl              ; zero masked pixels in buffer
        or      [es:di],al              ; update masked pixels in buffer

        jmp     Lexit

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; routine for dy <= dx (slope <= 1)	; ES:DI -> video buffer
					; BX = y-increment
					; CX = # pixels to draw
					; SI = decision variable
                    ; DH = inverse bit mask
                    ; DL = pixel value in proper position

LoSlopeLine04:

L10:    mov     ah,[es:di]              ; AH := byte from video buffer

L11:    and     ah,dh                   ; zero pixel value at current bit offset
        or      ah,dl                   ; set pixel value in byte

        ror     dl,1                    ; rotate pixel value
        ror     dl,1                    ; rotate pixel value
        ror     dl,1                    ; rotate pixel value
        ror     dl,1                    ; rotate pixel value
        xor     dh,255                  ;swap mask. using 'xor' instead of 'not' since testing for sign bit
        jns     L14                     ; jump if bit mask rotated to
                                        ;  leftmost pixel position

; bit mask not shifted out

        or      si,si                   ; test sign of d
        jns     L12                     ; jump if d >= 0

        add     si,[VARincr1]           ; d := d + incr1
        loop    L11

        mov     [es:di],ah              ; store remaining pixels in buffer
        jmp     Lexit

L12:    add     si,[VARincr2]           ; d := d + incr2
        mov     [es:di],ah              ; update buffer

        add     di,bx                   ; increment y

        loop    L10
        jmp     Lexit

; bit mask shifted out

L14:    mov     [es:di],ah              ; update buffer
        inc     di                      ; di := offset of next byte

        or      si,si                   ; test sign of d
        jns     L15                     ; jump if non-negative

        add     si,[VARincr1]           ; d := d + incr1
        loop    L10
        jmp     Lexit


L15:    add     si,[VARincr2]           ; d := d + incr2

        add     di,bx                   ; increment y

        loop    L10
        jmp     Lexit

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; routine for dy > dx (slope > 1)   ; ES:DI -> video buffer
                    ; BX = y-increment
                    ; CX = # pixels to draw
                    ; SI = decision variable
                    ; DH = inverse bit mask
                    ; DL = pixel value in proper position
HiSlopeLine04:

L21:    and     [es:di],dh              ; zero pixel value in video buffer
        or      [es:di],dl              ; set pixel value in byte

        add     di,bx                   ; increment y

L22:    or      si,si                   ; test sign of d
        jns     L23                     ; jump if d >= 0

        add     si,[VARincr1]           ; d := d + incr1
        loop    L21

        jmp     Lexit


L23:    add     si,[VARincr2]           ; d := d + incr2

        ror     dl,1                    ; rotate pixel value
        ror     dl,1                    ; rotate pixel value
        ror     dl,1                    ; rotate pixel value
        ror     dl,1                    ; rotate pixel value
        xor     dh,255                  ;swap bit mask
        js      .l24
        inc     di                      ; BX := offset of next byte
.l24:

        loop    L21


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
Lexit:  pop     di      ; restore registers and return
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

ARGx1:          dw      0               ;x1
ARGx2:          dw      0               ;x2
ARGy1:          dw      0               ;y1
ARGy2:          dw      0               ;y2
ARGn:           db      0               ;color




;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; Includes
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
%include 'common/pixel_addr_160_100_16color.asm'
