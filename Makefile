.PHONY: res

TARGET_NAME = intro.com
TARGET = bin/${TARGET_NAME}
ASM = nasm
ASMFLAGS = -fobj -Wall
LD = alink
LDFLAGS = -oCOM -m

default: $(TARGET)
all: res default

OBJECTS = intro.o utils.o segment55_table.o segment55_data.o

%.o: src/%.asm
	$(ASM) $(ASMFLAGS) $< -o $@

.PRECIOUS: $(TARGET) $(OBJECTS)

$(TARGET): $(OBJECTS)
	echo "Linking..."
	$(LD) $(OBJECTS) $(LDFLAGS) -o $@

clean:
	echo "Cleaning..."
	-rm -f *.o
	-rm -f bin/*.map

run: $(TARGET)
	echo "Running game..."
	dosbox-x -conf conf/dosbox-x_pcjr.conf -c "mount c bin/ && dir" -c "c:" -c ${TARGET_NAME}

x: $(TARGET)
	echo "Compressing game..."
	-upx -9 --8086 $(TARGET)

runx: x
	echo "Running game..."
	dosbox-x -conf conf/dosbox-x_pcjr.conf -c "mount c bin/ && dir" -c "c:" -c ${TARGET_NAME}

dist: x
	echo "Generating distribution .zip"
	-rm intro.zip
	-rm intro/intro.com
	cp bin/intro.com intro/
	zip intro.zip -r intro

boot: default fat_image
	nasm -Wall boot_loader/boot_loader.asm -fbin -o boot_loader/boot.bin
	cat boot_loader/boot.bin boot_loader/fat_without_boot.bin > bin/intro.360

test_boot: boot
	dosbox-x -conf conf/dosbox-x_pcjr.conf

res:
	echo "Generating resources..."
	echo "Compressing music..."
	python3 ~/progs/pc-8088-misc/pvmplay/convert_vgm_to_pvm.py res/cumparchiptune.vgm
	mv res/cumparchiptune.pvm src/uctumi-song.pvm
	echo "Converting graphics..."
	python3 tools/parse_55_segment_data.py res/55-segment.png -o src/segment55_data.asm
	python3 tools/parse_55_segment_font.py -o src/segment55_table.asm
	python3 tools/parse_ibm_charset.py res/tandy_1000_hx_charset-charset.bin -o src/charset_0x20_0x60.bin
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


fat_image: default
	echo "Generating FAT image with intro.com"
	-rm -f boot_loader/fat_image.360
	sudo mkfs.msdos -n PVM_BOOT -C boot_loader/fat_image.360 360
	-sudo mkdir /media/floppy
	sudo mount -o loop boot_loader/fat_image.360 /media/floppy
	sudo cp bin/intro.com /media/floppy
	sudo umount /media/floppy
	sudo rmdir /media/floppy
	dd if=boot_loader/fat_image.360 of=boot_loader/fat_without_boot.bin bs=512 skip=1 count=719
