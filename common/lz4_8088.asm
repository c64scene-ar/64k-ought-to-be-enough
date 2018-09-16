; Surprise!  I don't know what assembler you are using (masm, tasm,
; nasm, jasm, a86, etc.) so you get to wrap either of these routines for your
; specific situation.  Be sure to read the TRASHES comment below.
;
; The speed-optimized routine is lz4_decompress and the size-optimized
; routine is lz4_decompress_small.

bits    16
cpu     8086
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; CODE
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

;COMMENT #
;function lz4_decompress(inb,outb:pointer):word
;
;Decompresses an LZ4 stream file with a compressed chunk 64K or less in size.
;Input:
;  DS:SI Location of source data.  DWORD magic header and DWORD chunk size
;        must be intact; it is best to load the entire LZ4 file into this
;        location before calling this code.
;
;Output:
;  ES:DI Decompressed data.  If using an entire 64K segment, decompression
;        is "safe" because overruns will wrap around the segment.
;  AX    Size of decompressed data.
;
;Trashes AX, BX, CX, DX, SI, DI
;        ...so preserve what you need before calling this code.
;#
;
;asm
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
global lz4_decompress
lz4_decompress:
        jmp     .decompinit
.SHR4table:
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01
        db 0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02
        db 0x03,0x03,0x03,0x03,0x03,0x03,0x03,0x03,0x03,0x03,0x03,0x03,0x03,0x03,0x03,0x03
        db 0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04
        db 0x05,0x05,0x05,0x05,0x05,0x05,0x05,0x05,0x05,0x05,0x05,0x05,0x05,0x05,0x05,0x05
        db 0x06,0x06,0x06,0x06,0x06,0x06,0x06,0x06,0x06,0x06,0x06,0x06,0x06,0x06,0x06,0x06
        db 0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07
        db 0x08,0x08,0x08,0x08,0x08,0x08,0x08,0x08,0x08,0x08,0x08,0x08,0x08,0x08,0x08,0x08
        db 0x09,0x09,0x09,0x09,0x09,0x09,0x09,0x09,0x09,0x09,0x09,0x09,0x09,0x09,0x09,0x09
        db 0x0A,0x0A,0x0A,0x0A,0x0A,0x0A,0x0A,0x0A,0x0A,0x0A,0x0A,0x0A,0x0A,0x0A,0x0A,0x0A
        db 0x0B,0x0B,0x0B,0x0B,0x0B,0x0B,0x0B,0x0B,0x0B,0x0B,0x0B,0x0B,0x0B,0x0B,0x0B,0x0B
        db 0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C
        db 0x0D,0x0D,0x0D,0x0D,0x0D,0x0D,0x0D,0x0D,0x0D,0x0D,0x0D,0x0D,0x0D,0x0D,0x0D,0x0D
        db 0x0E,0x0E,0x0E,0x0E,0x0E,0x0E,0x0E,0x0E,0x0E,0x0E,0x0E,0x0E,0x0E,0x0E,0x0E,0x0E
        db 0x0F,0x0F,0x0F,0x0F,0x0F,0x0F,0x0F,0x0F,0x0F,0x0F,0x0F,0x0F,0x0F,0x0F,0x0F,0x0F

.decompinit:
        push    ds              ;preserve compiler assumptions
        push    bp              ;preserve compiler assumptions
        ;les     di,outb         ;load target buffer
        push    di              ;save original starting offset (in case != 0)
        ;lds     si,inb          ;load source buffer
        add     si,7            ;skip magic number
        cld                     ;make strings copy forward
        mov     bx,.SHR4table   ;prepare BX for XLAT later on
        lodsw                   ;load chunk size low 16-bit word
        mov     bp,ax           ;BP = size of compressed chunk
        lodsw                   ;load chunk size high 16-bit word
        add     bp,si           ;BP = threshold to stop decompression
        or      ax,ax           ;is high word non-zero?
        jnz     .done           ;If so, chunk too big or malformed, abort

.starttoken:
        lodsb                   ;grab token to AL
        mov     dx,ax           ;preserve packed token in DX
        cs xlatb                ;unpack upper 4 bits, faster than SHR reg,cl
        mov     cx,ax           ;CX = unpacked literal length token
        jcxz    .copymatches    ;if CX = 0, no literals; try matches
        cmp     al,0x0F          ;is it 15?
        jne     .doliteralcopy1 ;if so, build full length, else start copying
.build1stcount:                 ;this first count build is not the same
        lodsb                   ;fall-through jump as the one in the main loop
        add     cx,ax           ;because it is more likely that the very first
        cmp     al,0xFF          ;length is 15 or more
        je      .build1stcount
.doliteralcopy1:
        rep movsb               ;src and dst might overlap so do this by bytes

;At this point, we might be done; all LZ4 data ends with five literals and the
;offset token is ignored.  If we're at the end of our compressed chunk, stop.

        cmp     si,bp           ;are we at the end of our compressed chunk?
        jae     .done           ;if so, jump to exit; otherwise, process match

.copymatches:
        lodsw                   ;AX = match offset
        xchg    dx,ax           ;AX = packed token, DX = match offset
        and     al,0x0F          ;unpack match length token
        cmp     al,0x0F          ;is it 15?
        xchg    cx,ax           ;(doesn't affect flags); don't need ax any more
        je      .buildmcount    ;if not, start copying, otherwise build count

.domatchcopy:
        cmp     dx,2            ;if match offset=1 or 2, we're repeating a value
        jbe     .domatchfill    ;if so, perform RLE expansion optimally
        push    ds
        xchg    si,ax           ;ds:si saved
        mov     si,di
        sub     si,dx
        mov     dx,es
        mov     ds,dx           ;ds:si points at match; es:di points at dest
        movsw
        movsw                   ;minimum match is 4 bytes; move them ourselves
        shr     cx,1
        rep movsw               ;cx contains count-4 so copy the rest
        adc     cx,cx
        rep movsb
        xchg    si,ax
        pop     ds              ;ds:si restored

.parsetoken:                    ;CX always 0 here because of REP
        xchg    cx,ax           ;zero ah here to benefit other reg loads
        lodsb                   ;grab token to AL
        mov     dx,ax           ;preserve packed token in DX
.copyliterals:                  ;next 5 lines are 8088-optimal, do not rearrange
        cs xlatb                ;unpack upper 4 bits, faster than SHR reg,cl
        mov     cx,ax           ;CX = unpacked literal length token
        jcxz    .copymatches    ;if CX = 0, no literals; try matches
        cmp     al,0x0F          ;is it 15?
        je      .buildlcount    ;if so, build full length, else start copying
.doliteralcopy:                 ;src and dst might overlap so do this by bytes
        rep movsb               ;if cx=0 nothing happens

;At this point, we might be done; all LZ4 data ends with five literals and the
;offset token is ignored.  If we're at the end of our compressed chunk, stop.

.testformore:
        cmp     si,bp           ;are we at the end of our compressed chunk?
        jb      .copymatches    ;if not, keep going
        jmp     .done           ;if so, end

.domatchfill:
        je      .domatchfill2   ;if DX=2, RLE by word, else by byte
.domatchfill1:
        mov     al,[es:di-1]    ;load byte we are filling with
        mov     ah,al           ;copy to ah so we can do 16-bit fills
        stosw                   ;minimum match is 4 bytes, so we fill four
        stosw
        inc     cx              ;round up for the shift
        shr     cx,1            ;CX = remaining (count+1)/2
        rep stosw               ;includes odd byte - ok because LZ4 never ends with matches
        adc     di,-1           ;Adjust dest unless original count was even
        jmp     .parsetoken     ;continue decompressing

.domatchfill2:
        mov     ax,[es:di-2]    ;load word we are filling with
        stosw                   ;minimum match is 4 bytes, so we fill four
        stosw
        inc     cx              ;round up for the shift
        shr     cx,1            ;CX = remaining (count+1)/2
        rep stosw               ;includes odd byte - ok because LZ4 never ends with matches
        adc     di,-1           ;Adjust dest unless original count was even
        jmp     .parsetoken     ;continue decompressing

.buildlcount:                   ;build full literal length count
        lodsb                   ;get next literal count byte
        add     cx,ax           ;increase count
        cmp     al,0xFF         ;more count bytes to read?
        je      .buildlcount
        jmp     .doliteralcopy

.buildmcount:                   ;build full match length count - AX is 0
        lodsb                   ;get next literal count byte
        add     cx,ax           ;increase count
        cmp     al,0xFF         ;more count bytes to read?
        je      .buildmcount
        jmp     .domatchcopy

.done:
        pop     ax              ;retrieve previous starting offset
        sub     di,ax           ;subtract prev offset from where we are now
        xchg    ax,di           ;AX = decompressed size
        pop     bp              ;restore compiler assumptions
        pop     ds              ;restore compiler assumptions

        ret
;
;COMMENT #
;
;function lz4_decompress_small(inb,outb:pointer):word
;
;Same as LZ4_Decompress but optimized for size, not speed.  Still pretty fast,
;although roughly 30% slower than lz4_decompress and RLE sequences are not
;optimally handled.  Same Input, Output, and Trashes as lz4_decompress.
;Assembles to 79 bytes. Thanks to Peter Ferrie for suggestions!
;
;#
;
;asm
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
global lz4_decompress_small
lz4_decompress_small:
        push    ds              ;preserve compiler assumptions
        ;les     di,outb         ;load target buffer
        push    di              ;save original starting offset (in case != 0)
        ;lds     si,inb          ;load source buffer
        cld                     ;make strings copy forward
        lodsw
        lodsw                   ;skip magic number, smaller than "add si,4"
        lodsw                   ;load chunk size low 16-bit word
        xchg    bx,ax           ;BX = size of compressed chunk
        add     bx,si           ;BX = threshold to stop decompression
        lodsw                   ;load chunk size high 16-bit word
        xchg    cx,ax           ;set CX=0 so that AX=0 later
        inc     cx              ;is high word non-zero?
        loop    .done           ;If so, chunk too big or malformed, abort

.parsetoken:                    ;CX=0 here because of REP at end of loop
        xchg    cx,ax           ;zero ah here to benefit other reg loads
        lodsb                   ;grab token to AL
        mov     dx,ax           ;preserve packed token in DX
.copyliterals:
        mov     cl,4
        shr     al,cl           ;unpack upper 4 bits
        call    .buildfullcount ;build full literal count if necessary
.doliteralcopy:                 ;src and dst might overlap so do this by bytes
        rep movsb               ;if cx=0 nothing happens

;At this point, we might be done; all LZ4 data ends with five literals and the
;offset token is ignored.  If we're at the end of our compressed chunk, stop.

        cmp     si,bx           ;are we at the end of our compressed chunk?
        jae     .done           ;if so, jump to exit; otherwise, process match

.copymatches:
        lodsw                   ;AX = match offset
        xchg    dx,ax           ;AX = packed token, DX = match offset
        and     al,0x0F         ;unpack match length token
        call    .buildfullcount ;build full match count if necessary
.domatchcopy:
        push    ds
        xchg    si,ax           ;ds:si saved
        mov     si,di
        sub     si,dx
        push    es
        pop     ds              ;ds:si points at match; es:di points at dest
        add     cx,4            ;minimum match is 4
        rep movsb               ;copy match run; movsb handles si=di-1 condition
        xchg    si,ax
        pop     ds              ;ds:si restored
        jmp     .parsetoken

.buildfullcount:
        mov     cx,ax           ;CX = unpacked literal length token
        cmp     al,0x0F         ;is it 15?
        jne     .builddone      ;if not, we have nothing to build
.buildloop:
        lodsb                   ;load a byte
        add     cx,ax           ;add it to the full count
        cmp     al,0xFF         ;was it FFh?
        je      .buildloop      ;if so, keep going
.builddone:
        ret

.done:
        pop     ax              ;retrieve previous starting offset
        sub     di,ax           ;subtract prev offset from where we are now
        xchg    ax,di           ;AX = decompressed size
        pop     ds              ;restore compiler assumptions

        ret
