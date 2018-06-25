;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; Boot loader
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

bits    16
cpu     8086

;org     0x7c00
org     0x0000                          ;Org should be 0x7c00
                                        ; but since we copy everything to 60:00
                                        ; easier to say origin is 0x00


NEW_CS          equ 0x60                ;where the code will be placed
INTRO_CS        equ NEW_CS+0x20         ;where the intro should be placed (512 bytes off new_cs)

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
start:
        jmp     _start                  ;must start with a 'jmp' (3 bytes)
        nop
        db      'PVM_BOOT'              ;OEM name (8 bytes)

        ;BIOS parameter block
        dw      0x0200                  ;bytes per sector
        db      0x02                    ;sectors per cluster
        dw      0x0001                  ;number of reserved sectors
        db      2                       ;number of FATs
        dw      0x0070                  ;number of entries in root dir
        dw      0x02d0                  ;number of sectors in volume
        db      0xfd                    ;media descriptor
        dw      0x0002                  ;number of sectors per FAT
        dw      0x0009                  ;sectors per track
        dw      0x0002                  ;number of read/write heads
        dw      0x0000                  ;number of hidden sectors

        
times 0x36 - ($ - $$) db 0              ;some padding. start code at 0x36

_start:
        ;Don't use stack yet. SP not set correctly
        cli                             ;disable the interrupts
        cld
        sub     di,di
        mov     ax,NEW_CS               ;segment 0x10 will be the new address
        mov     es,ax                   ;dest: es:di
        mov     si,start+0x7c00         ;copy from byte 0 (since Org is 0, and not 0x7c00, add it)
        mov     ax,cs
        mov     ds,ax                   ;src = ds:si
        mov     cx,256                  ;copy 1 sector (512 bytes)
        rep movsw
        jmp     NEW_CS:new_start        ;jump to new colocation (minus current offset)

new_start:
        ;Set SP before continue using it
        sub     ax,ax
        mov     ss,ax
        mov     sp,NEW_CS*16            ;stack

        sti                             ;enable interrupts

        mov     ax,cs                   ;es=ds=cs
        mov     ds,ax
        mov     es,ax

        mov     si,boot_msg             ;offset to msg
        call    print_msg

        ; where does the intro.com file start
        mov     byte [f_drive],0        ;drive
        mov     byte [f_head],1         ;initial head
        mov     byte [f_track],0        ;initial track (cylinder)
        mov     byte [f_sector],6       ;initial sector
        mov     byte [f_total_sectors],96       ;how many sectors to read (96 = 48K / 512)
        call    read_sectors

        call    delay
        int 3
        jmp     INTRO_CS-0x10:0x100     ;512 (0x20 * 16) (sector size) + 0x100 (.com offset)


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
read_sectors:
        sub     ax,ax
        int     0x13                    ;reset drive

        mov     ax,INTRO_CS             ;512 bytes from here (1 sector size)
        mov     es,ax
        sub     bx,bx                   ;offset is 0, even though .com starts at 0x100
                                        ; a "jmp INTRO_CS-0x10:0x100" will be done

.loop:
        int 3
        call    read_sector             ;read one sector at the time
        jc      .error

        ; update offset
        sub     dx,dx
        mov     dl,al                   ;dx = sectors read
        mov     cl,9                    ;512 = 2 ^ 9
        shl     dx,cl                   ;dx contains the new offset
        add     bx,dx                   ;update offset

        sub     byte [f_total_sectors],al
        cmp     byte [f_total_sectors],0
        jz      .finish

        ; assumes it read at most 1 track (single head) per time

        mov     byte [f_sector],1       ;reset sector back to 1
        inc     byte [f_head]           ;from next head
        cmp     byte [f_head],2
        jb      .loop

        mov     byte [f_head],0         ;reset head back to 0
        inc     byte [f_track]
        cmp     byte [f_track],40
        jb      .loop

        int 3

.error:
        mov     si,error_msg            ;offset to msg
        call    print_msg
        int     0x19                    ;reboot

.finish:
        mov     si,ok_msg
        call    print_msg
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; IN:
;       es:bx: point to buffer where data will be stored
read_sector:
        mov     al,9+1                  ;max sectors + 1 since sectors start at 1, and not 0
        sub     al, byte [f_sector]     ;minus starting sector. cl contains the max
                                        ; possible sector for this track
        cmp     al,byte [f_total_sectors]
        jbe     .l0
        mov     al,byte [f_total_sectors];use f_total_sectors when it is less than
                                         ; the available sectors
.l0:
        mov     ah,0x02                 ;read sectors
        mov     ch,byte [f_track]       ;track to read from
        mov     cl,byte [f_sector]      ;sector to read from
        mov     dh,byte [f_head]
        mov     dl,byte [f_drive]
        int     0x13
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
print_msg:
        push    es
        les     di,[video_offset]
.l0:    lodsb                           ;loads SI into AL
        or      al,al                   ;checks whether the end of the string
        jz      .exit                   ;exit if so
        cmp     al,13                   ;new line?
        jz      .new_line
        stosb
        inc     di                      ;skip attrib value
        jmp     .l0                     ;and loop

.exit:
        pop     es
        mov     [video_offset],di       ;update char offset
        ret
.new_line:
        mov     di,[last_new_line]
        add     di,80
        mov     [last_new_line],di
        jmp     .l0

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
delay:
        sub     ax,ax
        int     0x13                    ;reset drive

        mov     cx,5                    ;delay for a while
.l1:    push    cx
        sub     cx,cx
.l0:    loop    .l0
        pop     cx
        loop    .l1
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

video_offset:
        dw      0x0000                  ;offset
        dw      0xb800                  ;segment
last_new_line:
        dw      0                       ;offset of last new line

boot_msg:
        db 'PVM BOOT LOADER v0.1',13    ;booting msg
        db 'Loading',0

error_msg:
        db 13,'Error loading. Trying again.',13,0
ok_msg:
        db 13,'Ok.',13,0                ;booting msg
f_drive:
        db 0                            ;initial drive to read
f_head:
        db 0                            ;initial header of the floppy
f_track:
        db 0                            ;initial track (cylinder)
f_sector:
        db 0                            ;initial sector
f_total_sectors:
        db 0                            ;how many sectors to read in totoal


;; Magic numbers
times 510 - ($ - $$) db 0               ;byte 509 should be 0
        dw 0xAA55                       ;510 = 0x55, 511 = 0xaa
