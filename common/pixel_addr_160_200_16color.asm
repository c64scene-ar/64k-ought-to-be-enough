;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; Name:     PixelAddr16
;
; Function: Determine buffer address of pixel in 160x200 16-color mode
;
; Caller:       AX = y-coordinate (0-199)
;               BX = x-coordinate (0-159)
;
; Returns:      AH = bit mask
;               BX = byte offset in buffer
;               CL = number of bits to shift left
;               ES = video buffer segment
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

OriginOffset    equ 0       ; byte offset of (0,0)
VideoBufferSeg  equ 0xb800

PixelAddr04:
        int 3
        mov     cl,bl       ; CL := low-order byte of x

        xchg    ah,al       ; AX := 0x100 * y
        shl     bx,1            ; x = x * 2
        shr     ax,1        ; AL := 0x80 * (y&1)
        add     bh,al       ; BX := x*2 + 0x8000*(y&1)
        xor     al,al       ; AX := 0x100*(y/2)
        add     bx,ax       ; BX := x*2 + 0x8000*(y&1) + 0x100*(y/2)
        shr     ax,1
        shr     ax,1        ; AX := 0x40*(y/2)
        add     bx,ax       ; BX := x*2 + 0x8000*(y&1) + 0x140*(y/2)
        shr     bx,1            ; BX = x + 0x4000*(y&1) + 0xa0(y/2)
        shr     bx,1        ; BX := x/2 + 0x2000*(y&1) + 0x50*(y/2)
;        add     bx,OriginOffset ; BX := byte offset in video buffer

        mov     ax,VideoBufferSeg
        mov     es,ax       ; ES:BX := byte address of pixel

        mov     ah,0b0000_1111  ;mask
        and     cl,1            ;x & 1
        xor     cl,1            ;invert bit
        shl     cl,1            ;
        shl     cl,1            ;cl = (x&1) * 4
;        shl     ah,cl           ;mask = 0xf0 if x&1, else 0x0f

        ret
