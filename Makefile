.PHONY: res runme detect

TARGET_NAME_1 = part1.com
TARGET_1 = bin/${TARGET_NAME_1}
ASM = nasm
ASMFLAGS = -fobj -Wall
LD = alink
LDFLAGS = -oCOM -m

part1: $(TARGET_1)

all: res test_boot

OBJECTS_1 = intro.o utils.o segment55_table.o segment55_data.o

%.o: part1/%.asm
	$(ASM) $(ASMFLAGS) $< -o $@

.PRECIOUS: $(TARGET_1) $(OBJECTS_1)

$(TARGET_1): $(OBJECTS_1)
	echo "Linking..."
	$(LD) $(OBJECTS_1) $(LDFLAGS) -o $@

clean:
	echo "Cleaning..."
	-rm -f obj/*.o *.o
	-rm -f bin/*.map

test_part1: $(TARGET_1)
	echo "Running game..."
	dosbox-x -conf conf/dosbox-x_pcjr.conf -c "mount c bin/ && dir" -c "c:" -c ${TARGET_NAME_1}

part1x: $(TARGET_1)
	echo "Compressing game..."
	-upx -9 --8086 $(TARGET_1)

test_part1x: part1x
	echo "Running game..."
	dosbox-x -conf conf/dosbox-x_pcjr.conf -c "mount c bin/ && dir" -c "c:" -c ${TARGET_NAME_1}

dist: x
	echo "Generating distribution .zip"
	-rm intro.zip
	-rm intro/intro.com
	cp bin/intro.com intro/
	zip intro.zip -r intro

boot: fat_image
	nasm -Wall boot_loader/boot_loader.asm -fbin -o boot_loader/boot.bin
	cat boot_loader/boot.bin boot_loader/fat_without_boot.bin > bin/demo_pvm.360

runme:
	echo "Generating runme.com"
	nasm -Wall runme/runme.asm -fbin -o bin/runme.com

test_runme: runme
	echo "Running runme"
	dosbox-x -conf conf/dosbox-x_pcjr.conf -c "mount c bin/ && dir" -c "c:" -c runme.com

detect:
	echo "Generating detect.com"
	nasm -Wall detect/detect.asm  -fobj -o obj/detect.o
	nasm -Wall detect/pztimer.asm -fobj -o obj/pztimer.o
	alink -oCOM -m obj/detect.o obj/pztimer.o -o bin/detect.com

test_detect: detect
	dosbox-x -conf conf/dosbox-x_pcjr.conf -c "mount c bin/" -c "c:" -c dir

test_boot: boot
	dosbox-x -conf conf/dosbox-x_pcjr.conf

res:
	echo "Generating resources..."
	echo "Compressing music..."
	python3 ~/progs/pc-8088-misc/pvmplay/convert_vgm_to_pvm.py res/cumparchiptune.vgm
	mv res/cumparchiptune.pvm part1/uctumi-song.pvm
	echo "Converting graphics..."
	python3 tools/parse_55_segment_data.py res/55-segment.png -o part1/segment55_data.asm
	python3 tools/parse_55_segment_font.py -o part1/segment55_table.asm
	python3 tools/parse_ibm_charset.py res/tandy_1000_hx_charset-charset.bin -o part1/charset_0x20_0x60.bin
	#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 10 -o src/flashparty.bin res/flashparty.data
	#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/p.raw res/p.data
	#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/v.raw res/v.data
	#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/m.raw res/m.data
	#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/invites.raw res/invites.data
	#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/you.raw res/you.data
	#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/to.raw res/to.data
	#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/fp.raw res/fp.data
	#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/2018.raw res/2018.data
	#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/satelite.raw res/satelite.data
	#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/tango_silueta.raw res/tango_silueta.data
	#echo "Compressing graphics..."
	#lz4 -9 -f res/p.raw src/p.raw.lz4
	#lz4 -9 -f res/v.raw src/v.raw.lz4
	#lz4 -9 -f res/m.raw src/m.raw.lz4
	#lz4 -9 -f res/invites.raw src/invites.raw.lz4
	#lz4 -9 -f res/you.raw src/you.raw.lz4
	#lz4 -9 -f res/to.raw src/to.raw.lz4
	#lz4 -9 -f res/fp.raw src/fp.raw.lz4
	#lz4 -9 -f res/2018.raw src/2018.raw.lz4
	#lz4 -9 -f res/tango_silueta.raw src/tango_silueta.raw.lz4
	#lz4 -9 -f res/satelite.raw src/satelite.raw.lz4
	echo "Done"

dis:
	echo "Dissassembling..."
	ndisasm -b 16 -o 100h bin/${TARGET_NAME} | gvim -


fat_image: part1 runme detect
	echo "Generating FAT image with needed files"
	-rm -f boot_loader/fat_image.360
	sudo mkfs.msdos -n PVM_BOOT -C boot_loader/fat_image.360 360
	-sudo mkdir /media/floppy
	sudo mount -o loop boot_loader/fat_image.360 /media/floppy
	sudo cp bin/runme.com /media/floppy/
	sudo cp bin/detect.com /media/floppy/
	sudo cp bin/part1.com /media/floppy/
	sudo umount /media/floppy
	sudo rmdir /media/floppy
	dd if=boot_loader/fat_image.360 of=boot_loader/fat_without_boot.bin bs=512 skip=1 count=719
