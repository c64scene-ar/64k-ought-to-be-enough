;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; Boot loader
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

bits    16
cpu     8086

org     0x0000                          ;Org should be 0x7c00
                                        ; but since we copy everything to 60:00
                                        ; easier to say origin is 0x00


NEW_CS  equ 0x60                        ;where the code will be placed

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

        sub     ax,ax
        int     0x13                    ;reset floppy

        mov     si,boot_msg             ;offset to msg
        call    print_msg

.l1:
        mov     ax,0x0209               ;read 9 sectors
        mov     cx,0x0001               ;cylender = 0, sector = 1
        mov     dx,0x0000               ;head = 0, drive = 0
        mov     ax,NEW_CS
        mov     es,ax                   ;es:bx = dst
        mov     bx,0x200                ;load 512 bytes after this
        int     0x13
        jc      .error
        mov     si,ok_msg
        call    print_msg
        jmp     0x300                   ;512 (sector size) + 0x100 (.com offset)

.error:
        mov     si,error_msg            ;offset to msg
        call    print_msg
        jmp     .l1

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
        db 'PVM DOS v0.1',13,10,0       ;booting msg
error_msg:
        db 'Could not load intro. Trying again.',13,10,0
ok_msg:
        db 'Ok.',13,10,0                ;booting msg


;; Magic numbers
times 510 - ($ - $$) db 0               ;byte 509 should be 0
        dw 0xAA55                       ;510 = 0x55, 511 = 0xaa
