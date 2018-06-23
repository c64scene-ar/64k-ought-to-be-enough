;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; Boot loader
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

bits    16
cpu     8086

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
        mov     sp,0x400                ;stack

        mov     ax,cs                   ;es=ds=cs
        mov     ds,ax
        mov     es,ax

        sti                             ;enable interrupts

        mov     ax,0x0001               ;video mode: 40x25 color
        int     0x10

        mov     si,boot_msg             ;offset to msg
        call    print_msg

        mov     ax,0x0001
        int     0x16                    ;wait key

        mov     byte [f_drive],0        ;drive
        mov     byte [f_head],0         ;initial head
        mov     byte [f_track],0        ;initial track (cylinder)
        mov     byte [f_sector],3       ;initial sector
        mov     byte [f_total_sectors],100       ;how many sectors to read
        call    read_sectors

        mov     cx,0
.delay:
        loop    .delay

        mov     ax,0x0001
        int     0x16                    ;wait key
        jmp     INTRO_CS:0x100          ;512 (0x20 * 16) (sector size) + 0x100 (.com offset)


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
read_sectors:
        sub     ax,ax
        int     0x13                    ;reset drive

        mov     ax,INTRO_CS             ;512 bytes from here (1 sector size)
        mov     es,ax
        mov     bx,0x100                ;.com offset

        mov     cx, [f_total_sectors]
.l1:
        push    cx

        call    read_sector             ;read one sector at the time
        inc     bh                      ;bx += 512
        inc     bh
        jc      .error

        push    bx
        mov     si,in_progress_msg
        call    print_msg
        pop     bx

        inc     byte [f_sector]         ;next sector
        cmp     byte [f_sector],9       ;end of max sectors?
        jbe     .cont                   ;no, continue

        mov     byte [f_sector],1       ;start again from sector 1
        inc     byte [f_head]           ;read using the other head
        cmp     byte [f_head],1         ;already used the two heads
        jbe     .cont                   ;no, continue

        mov     byte [f_head],0         ;start again from head 0
        inc     byte [f_track]          ;next track (cylinder)
        cmp     byte [f_track],39       ;already reached last track
        jbe     .cont                   ;no, continue

        mov     si,error_msg
        call    print_msg
        int 3                           ;should not happen

.cont:
        pop     cx
        loop    .l1

        mov     si,ok_msg
        call    print_msg
        ret

.error:
        pop     cx
        mov     si,error_msg            ;offset to msg
        call    print_msg
        jmp     .l1

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; IN:
;       es:bx: point to buffer where data will be stored
read_sector:
        mov     ch,byte [f_track]       ;track to read from
        mov     cl,byte [f_sector]      ;sector to read from
        mov     dh,byte [f_head]
        mov     dl,byte [f_drive]
        mov     ax,0x0201               ;read 1 one sector at the time
        int     0x13
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
print_msg:
        mov     ah,0x0e                 ;BIOS's print chars
.l0:	lodsb                           ;loads SI into AL
	    or      al,al                   ;checks whether the end of the string
	    jz      .exit                   ;exit if so
	    int     0x10                    ;otherwise, print char
	    jmp     .l0                     ;and loop
.exit:
        ret

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

boot_msg:
        db 'PVM BOOT LOADER v0.1',13,10         ;booting msg
        db 'Loading',0

in_progress_msg:
        db '.',0

error_msg:
        db 13,10,'Error. Could not load intro. Trying again.',13,10,0
ok_msg:
        db 13,10,'Ok.',13,10,0                ;booting msg
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

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; Faking a valid FAT entry to make DoxBox happy
sector_2:
        db 0xfd, 0xff, 0xff             ;some magic numbers

times 512 - ($ - sector_2) db 0         ;fill the rest of the sector with 0
