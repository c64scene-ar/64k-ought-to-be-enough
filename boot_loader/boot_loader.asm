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
disk_params:                            ;taken from KingQuest PCjr boot sector
        db 0xdf, 0x02, 0x25, 0x02, 0x09, 0x2a, 0xff, 0x50, 0xf6, 0x00, 0x02

_start:
        int 3
        ;Don't use stack yet. SP not set correctly
        cli                             ;disable the interrupts
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

        mov     ds,ax                   ;ds = 0

        mov     ax,cs                   ;ax = cs
        mov     [0x7a],ax               ;set Disk param interrupt
        mov     word [0x78],disk_params
        sti                             ;enable interrupts

        mov     ds,ax                   ;restor ds

        mov     si,boot_msg             ;offset to msg
        call    print_msg

        mov     byte [f_drive],0        ;drive
        mov     byte [f_head],0         ;initial head
        mov     byte [f_track],0        ;initial track (cylinder)
        mov     byte [f_sector],3       ;initial sector
        mov     byte [f_total_sectors],92       ;how many sectors to read
        call    read_sectors
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
        mov     cl,9
        shl     bx,cl                   ;bx += 512
        jc      .error

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

        int 3                           ;should not happen

.cont:
        pop     cx
        loop    .l1
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
        db 'Could not load intro. Trying again.',13,10,0
ok_msg:
        db 'Ok.',13,10,0                ;booting msg
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
; Faking a valid FAT entry
sector_2:
        db 0xfd, 0xff, 0xff             ;some magic numbers

times 512 - ($ - sector_2) db 0         ;fill the rest of the sector with 0
