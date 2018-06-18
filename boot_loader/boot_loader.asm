;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; Boot loader
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

bits    16
cpu     8086
org     0x7c00                          ;BIOS loads our programm at this address


NEW_CS  equ 0x10                        ;where the code will be placed
                                        ;ints 0x00-0x1f (0000-007f)remain unmodified
                                        ;ints 0x20-0x3f (0080-00ff) for future use, temp stack
                                        ;ints >= 0x40: (0100) should not be used

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
start:
        ;Don't use stack yet. SP not set correctly
        cli                             ;disable the interrupts
        sub     di,di
        mov     ax,NEW_CS               ;segment 0x10 will be the new address
        mov     es,ax                   ;dest: es:di
        mov     si,new_start
        mov     ax,cs
        mov     ds,ax                   ;src = ds:si
        mov     cx,256                  ;copy 1 sector (512 bytes)
        rep movsw
        jmp     NEW_CS:new_start        ;jump to new colocation

new_start:
        ;Set SP before continue using it
        sub     ax,ax
        mov     ss,ax
        mov     sp,NEW_CS*16            ;stack: 0000:0x100

        mov     ax,cs
        mov     ds,ax
        mov     es,ax
        mov     [0x7a],ax               ;set Disk param interrupt
        mov     word [0x78],disk_params
        sti                             ;enable interrupts
        sub     ax,ax
        int     0x13                    ;reset floppy

        mov     si,boot_msg             ;offset to msg
        call    print_msg

.l1:
        mov     ax,0x0210               ;read 16 sectors
        mov     cx,0x0001               ;cylender = 0, sector = 1
        mov     dx,0x0000               ;head = 0, drive = 0
        mov     ax,0
        mov     es,ax                   ;es:bx = dst
        mov     bx,0x200                ;0000:0200 -> code starts here (can't use ints 0x80 or above)
        int     0x13
        jc      .error
        jmp     0x0000:0x0200

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

disk_params:                            ;taken from KingQuest PCjr boot sector
        db 0xdf, 0x02, 0x25, 0x02, 0x09, 0x2a, 0xff, 0x50, 0xf6, 0x00, 0x02

;; Magic numbers
times 510 - ($ - $$) db 0
dw 0xAA55
