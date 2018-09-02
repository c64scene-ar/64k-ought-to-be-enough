;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; Name:     PixelAddr16
;
; Function: Determine buffer address of pixel in 160x100 16-color mode
;
; Caller:       AX = y-coordinate (0-99)
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
	mov 	cx,0xb800
	mov 	es,cx

	; y * 80
	mov 	dx,ax 		;save Y for later
	mov 	cl,4 		;multiply by 16
	shl 	ax,cl		; ax = y * 16
	mov 	cl,6 		;multiply by 64
	shl 	dx,cl 	 	; dx = y * 64
	add 	ax,dx 		;ax = ax + dx  (ax = y * 80)

	; calculate x
	shr 	bx,1 		;x = x / 2, and useful to carry set to calc. mask
	jc 	is_odd

is_even:
	add 	bx,ax 		; offset = y * 80 + x / 2
	mov 	ah,0b1111_0000	;mask
	mov 	cl,4 		;bits to shift
	ret

is_odd:
	add 	bx,ax 		; offset = y * 80 + x / 2
	mov 	ah,0b0000_1111 	;mask
	sub	cl,cl		;bits to shift
	ret
	

PixelAddr04_old:
        mov     cl,bl       ; CL := low-order byte of x

        xchg    ah,al       ; AX := 0x100 * y
        shr     ax,1        ; AL := 0x80 * (y&1)
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
