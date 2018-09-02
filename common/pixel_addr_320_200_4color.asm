;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; Name:     PixelAddr04
;
; Function: Determine buffer address of pixel in 320x200 4-color mode
;
; Caller:   AX = y-coordinate (0-199)
;       BX = x-coordinate (0-319)
;
; Returns:  AH = bit mask
;       BX = byte offset in buffer
;       CL = number of bits to shift left
;       ES = video buffer segment
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


OriginOffset    equ 0       ; byte offset of (0,0)
VideoBufferSeg  equ 0xb800

PixelAddr04:
        mov     cl,bl       ; CL := low-order byte of x

        xchg    ah,al       ; AX := 0x100 * y
        shr     ax,1        ; AL := 80 * (y&1)
        add     bh,al       ; BX := x + 0x8000*(y&1)
        xor     al,al       ; AX := 0x100*(y/2)
        add     bx,ax       ; BX := x + 0x8000*(y&1) + 0x100*(y/2)
        shr     ax,1
        shr     ax,1        ; AX := 0x40*(y/2)
        add     bx,ax       ; BX := x + 0x8000*(y&1) + 0x140*(y/2)
        shr     bx,1
        shr     bx,1        ; BX := x/4 + 0x2000*(y&1) + 0x50*(y/2)
        add     bx,OriginOffset ; BX := byte offset in video buffer

        mov     ax,VideoBufferSeg
        mov     es,ax       ; ES:BX := byte address of pixel

        mov     ah,3        ; AH := unshifted bit mask
        and     cl,ah       ; CL := x & 3
        xor     cl,ah       ; CL := 3 - (x & 3)
        shl     cl,1        ; CL := # bits to shift left

        ret
