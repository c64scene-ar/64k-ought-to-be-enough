;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; Name:     PixelAddr16
;
; Function: Determine buffer address of pixel in 160x200 16-color mode
;
; Caller:       al = y-coordinate (0-99)
;               bl = x-coordinate (0-159)
;
; Returns:      AH = bit mask
;               BX = byte offset in buffer
;               CL = number of bits to shift left
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; From:
;       Programmers's Guide To PC & PS/2: Video Systems
;       by Richard Wilton
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; Adapted to nasm and, PCjr's 160x200 16-color: riq
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

; 2 pixels per byte
; 160 / 2 = 80 bytes per horizontal line. (80 = 64 + 16)
; offset = y * 80 + x / 2
; cl = (x & 1) ? 0 : 1

PixelAddr08:
        mov     cl,bl           ;save for later

        sub     ah,ah
        sub     bh,bh

        xchg    ah,al           ; AX := 256*y
        shr     ax,1            ; AX := 128*Y
        add     bx,ax           ; BX := 128*y + x
        shr     ax,1            ; AX := 64*Y
        shr     ax,1            ; AX := 32*Y
        add     bx,ax           ; BX := 128*Y + 32*Y + X == 160*Y + X
        shr     bx,1            ; BX : = 80*y + x /2

        mov     ah,0b0000_1111  ;mask
        and     cl,1            ;x & 1
        xor     cl,1            ;invert bit
        shl     cl,1            ;
        shl     cl,1            ;cl = (x&1) * 4
;        shl     ah,cl           ;mask = 0xf0 if x&1, else 0x0f

        cmp     bx,4096
        ja      .error

        ret

.error:
        int 3
        jmp     .error
