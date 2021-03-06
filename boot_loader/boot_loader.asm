;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; "Ought to be enough" - Boot loader
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; Pungas de Villa Martelli - http://pungas.space
;
; code: riq (http://retro.moe)
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

bits    16
cpu     8086

;org     0x7c00
org     0x0000                          ;Org should be 0x7c00
                                        ; but since we copy everything to 20:00
                                        ; easier to say origin is 0x00

BOOTSECTOR_CS   equ 0x20                ;where the boot-sector code will be placed
INTRO_CS        equ 0x60                ;where the intro should be placed
STACK_OFFSET    equ 0x600               ;goes down from 0x5ff

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; Memory map:
; 0      - 0x01ff: 512 bytes used for the vector table for the first 0x80 interrupts
; 0x0200 - 0x03ff: 512 bytes used to store the boot sector
; 0x0400 - 0x04ff: 256 bytes. BIOS variables
; 0x0500 - 0x05ff: 256 bytes. stack. used globally for all the intro parts and boot
; 0x0600 - 0xbfff: 46.5k free for the intro
; 0xc000 - 0xffff: 16k video memory
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
start:
        jmp     _start                  ;must start with a 'jmp' (3 bytes)
        nop
        db      'ricarDOS'              ;OEM name (8 bytes)

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
                                        ; but could use less padding if space is
                                        ; needed

_start:
        ;Don't use stack yet. SP not set correctly
        cli                             ;disable the interrupts
        cld
        sub     di,di
        mov     ax,BOOTSECTOR_CS        ;the new destination for the boot sector
        mov     es,ax                   ;dest: es:di
        mov     si,start+0x7c00         ;copy from byte 0 (since Org is 0, and not 0x7c00, add it)
        mov     ax,cs
        mov     ds,ax                   ;src = ds:si
        mov     cx,256                  ;copy 1 sector (512 bytes)
        rep movsw
        jmp     BOOTSECTOR_CS:new_start ;jump to new location

new_start:
        ;Set SP before continue using it
        sub     ax,ax
        mov     ss,ax
        mov     sp,STACK_OFFSET         ;stack

        mov     ds,ax                   ;ds=0
        mov     word [0x21*4],int_21_handler ;new 0x21 handler: offset
        mov     [0x21*4+2],cs           ;new 0x20 handler: segment

        mov     ax,cs                   ;es=ds=cs
        mov     ds,ax
        mov     es,ax

        sti                             ;enable interrupts

        mov     ax,0x0001               ;text 40x25 color
        int     0x10

        mov     dx,boot_msg             ;offset to msg
        mov     ah,9
        int     0x21                    ;print msg

        mov     ax,0x4c00               ;don't clear screen
        int     0x21                    ;load next file

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;dummy DOS "emulator". mimics some DOS functions so that stand alone
;.com works the same as with ricarDOS
;Easier for testing/debugging.
int_21_handler:
        cmp     ah,9                    ;print msg
        jz      ricardos_print_msg
        cmp     ah,0x4c
        jz      ricardos_load_file      ; if so, don't print / don't clean any message
                                        ; just load the next file
        int 3                           ;unsuppoted command

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;in:
;       ah = 0x4c
;       al = 0: don't clean screen / 1: clean screen
ricardos_load_file:
        mov     bx,cs                   ;ds = cs
        mov     ds,bx

        or      al,al                   ;al = 0?
        jz      .skip_clean             ;yes, skip clean

        dec     al                      ;al = 1 ?
        jz      .just_load              ;yes, skip clean and print

        mov     ax,0x0001               ;text 40x25 @ color
        int     0x10                    ;set video mode

        sub     ax,ax
        mov     [video_offset],ax       ;reset offset, so next msg starts from
        mov     [last_new_line],ax      ; the top

.skip_clean:
        mov     dx,loading_msg
        mov     ah,9
        int     0x21                    ;print msg

.just_load:
        mov     bx,[parts_idx]
        cmp     bx,PARTS_TOTAL
        jz      .reboot

        shl     bx,1                    ;each part takes 4 bytes.
        shl     bx,1                    ; so multiply bx by 4

        mov     ax,[parts_data + bx]

        mov     byte [f_drive],0        ;drive (should always be zero)
        mov     ax,[parts_data + bx]    ;fetch track/head
        mov     byte [f_track],al
        mov     byte [f_head],ah
        mov     ax,[parts_data + bx + 2];fetch sector/total sectors
        mov     byte [f_sector],al      ;initial sector
        mov     byte [f_total_sectors],ah       ;how many sectors to read (96 = 48K / 512)
        call    read_sectors

        inc     word [parts_idx]

        ;don't turn motor off. each part is reponsible for leaving the motor on/off

        mov     sp,STACK_OFFSET         ;reset stack
        jmp     INTRO_CS-0x10:0x100     ;jump to entry point:
                                        ; 512 (0x20 * 16) (sector size) + 0x100 (.com offset)

.reboot:
        ;jmp     0xf000:0x2022           ;no more parts to load, jump to PCjr-only keyboard test
        ;jmp     0xf000:0x2000           ;no more parts to load, jump to PCjr-only "mini welcome"
        jmp     0xf000:0xfff0           ;no more parts to load, reset computer
        ;int     0x19                    ;no more parts to load, reboot from floppy

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;in:
;       ah = 9
;       ds:dx: '$'-terminated string
ricardos_print_msg:
        mov     si,dx                   ;DS:SI source

        push    es
        les     di,[cs:video_offset]    ;ES:DI: destination

.l0:    lodsb                           ;loads SI into AL
        cmp     al,'$'                  ;checks whether the end of the string
        jz      .exit                   ;exit if so
        cmp     al,13                   ;new line?
        jz      .new_line
        cmp     al,10                   ;skip 10. it is a no-op in ricarDOS
        jz      .l0

        stosb
        inc     di                      ;skip attrib value
        jmp     .l0                     ;and loop

.exit:
        pop     es
        mov     [cs:video_offset],di    ;update char offset
        iret

.new_line:
        mov     di,[cs:last_new_line]
        add     di,80
        mov     [cs:last_new_line],di
        jmp     .l0


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
read_sectors:
        sub     ax,ax
        int     0x13                    ;reset drive

        mov     ax,INTRO_CS             ;512 bytes from here (1 sector size)
        mov     es,ax
        sub     bx,bx                   ;offset is 0, even though .com starts at 0x100
                                        ; a "jmp INTRO_CS-0x10:0x100" will be done

.loop:
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

        int 3                           ;should not happen

.error:
        mov     dx,error_msg            ;offset to msg
        mov     ah,9
        int     0x21                    ;print it using ricarDOS

        int     0x19                    ;reboot, try again

.finish:
        mov     dx,ok_msg               ;ok msg
        mov     ah,9
        int     0x21                    ;print it using ricarDOS

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

video_offset:
        dw      0x0000                  ;offset
        dw      0xb800                  ;segment
last_new_line:
        dw      0                       ;offset of last new line

boot_msg:
        db 'ricarDOS v0.1',13,'$'       ;booting msg
loading_msg:
        db 13,'Loading...$'          ;loading msg

error_msg:
        db 13,'Error. Trying again.',13,'$'
ok_msg:
        db 'Ok.',13,13,'$'              ;booting msg
f_drive:
        db 0                            ;initial drive to read. MUST be zero
f_head:
        db 0                            ;initial header of the floppy
f_track:
        db 0                            ;initial track (cylinder)
f_sector:
        db 0                            ;initial sector
f_total_sectors:
        db 0                            ;how many sectors to read in totoal

parts_idx:
        dw 0                            ;how many parts the demo contains
        ;(track * 18 + head*9 + sector-1) * 512 = offset
        ;formula:
        ; sectors = offset // 512
        ; track = sectors // 18
        ; head = (sectors // 9) % 2
        ; sector = (sectors % 9)+1
parts_data:                             ;track / head / sector / total sectors to read
        db 0,1,8,8                      ;detect.com: offset: 0x2000-0x3000. len: 8 sectors
        db 1,0,7,125                    ;part1.com: offset: 0x3000-0x12c00. len: 125 sectors max (64000 bytes)
                                        ; overwrites video memory
        db 8,0,7,125                    ;part2.com: offset: 0x12c00-0x22800. len: 125 sectors max (64000 bytes)
                                        ; overwrites video memory
        db 15,0,7,125               	;part3.com: offset: 0x22800-0x32140. len: 125 sectors max (64000 bytes)
                                        ; overwrites video memory
PARTS_TOTAL equ ($-parts_data)/4        ;how many parts are defined


;; Magic numbers
times 500 - ($ - $$) db 0               ;byte 509 should be 0
        dw 0xffff                       ;reserved
        dw 0xffff                       ;reserved
        dw 0xffff                       ;reserved
        dw 0xffff                       ;reserved
        dw 0xffff                       ;reserved
        dw 0xAA55                       ;510 = 0x55, 511 = 0xaa
