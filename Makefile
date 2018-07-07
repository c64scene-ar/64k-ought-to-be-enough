.PHONY: res runme part2a

TARGET_NAME_P1 = part1.com
TARGET_NAME_P2 = part2.com
TARGET_NAME_DETECT = detect.com
TARGET_P1 = bin/${TARGET_NAME_P1}
TARGET_P2 = bin/${TARGET_NAME_P2}
TARGET_DETECT = bin/${TARGET_NAME_DETECT}
ASM = nasm
ASMFLAGS = -fobj -Wall
LD = alink
LDFLAGS = -oCOM -m

part1: $(TARGET_P1)
part2: $(TARGET_P2)
detect: $(TARGET_DETECT)

all: res test_boot

SRCFILES_P1 = part1/intro.asm common/music_player.asm common/utils.asm part1/segment55_table.asm part1/segment55_data.asm
OBJECTS_P1 = $(patsubst %.asm, %.o, $(SRCFILES_P1))
SRCFILES_P2 = part2/part2.asm common/zx7_8086.asm common/utils.asm common/music_player.asm
OBJECTS_P2 = $(patsubst %.asm, %.o, $(SRCFILES_P2))
SRCFILES_DETECT = detect/detect.asm common/pztimer.asm
OBJECTS_DETECT = $(patsubst %.asm, %.o, $(SRCFILES_DETECT))

%.o: %.asm
	$(ASM) $(ASMFLAGS) $< -o $@

.PRECIOUS: $(TARGET_P1) $(OBJECTS_P1) $(TARGET_P2) $(OBJECTS_P2) $(TARGET_DETECT) $(OBJECTS_DETECT)

$(TARGET_P1): $(OBJECTS_P1)
	@echo "Linking..."
	$(LD) $(OBJECTS_P1) $(LDFLAGS) -o $@

$(TARGET_P2): $(OBJECTS_P2)
	@echo "Linking..."
	$(LD) $(OBJECTS_P2) $(LDFLAGS) -o $@

$(TARGET_DETECT): $(OBJECTS_DETECT)
	echo "Linking..."
	$(LD) $(OBJECTS_DETECT) $(LDFLAGS) -o $@

clean:
	@echo "Cleaning..."
	-rm -f */*.o
	-rm -f bin/*.map

test_part1: $(TARGET_P1)
	@echo "Running..."
	dosbox-x -conf conf/dosbox-x_pcjr.conf -c "mount c bin/ && dir" -c "c:" -c ${TARGET_NAME_P1}

part1x: $(TARGET_P1)
	@echo "Compressing game..."
	-upx -9 --8086 $(TARGET_P1)

test_part1x: part1x
	@echo "Running..."
	dosbox-x -conf conf/dosbox-x_pcjr.conf -c "mount c bin/ && dir" -c "c:" -c ${TARGET_NAME_P1}

part2a: part2
	@echo "Appending GFX to .com..."
	@python3 tools/append_gfx_to_com.py part2/image_320_200.raw -c bin/part2.com -o bin/part2gfx.com
	@echo "Done."

test_part2: part2a
	@echo "Running..."
	dosbox-x -conf conf/dosbox-x_pcjr.conf -c "mount c bin/ && dir" -c "c:" -c part2gfx.com

dist: x
	@echo "Generating distribution .zip"
	-rm intro.zip
	-rm intro/intro.com
	cp bin/intro.com intro/
	zip intro.zip -r intro

boot: fat_image
	nasm -Wall boot_loader/boot_loader.asm -fbin -o boot_loader/boot.bin
	cat boot_loader/boot.bin boot_loader/fat_without_boot.bin > bin/demo_pvm.360

runme:
	@echo "Generating runme.com"
	nasm -Wall runme/runme.asm -fbin -o bin/runme.com

test_runme: runme
	@echo "Running..."
	dosbox-x -conf conf/dosbox-x_pcjr.conf -c "mount c bin/ && dir" -c "c:" -c runme.com

test_detect: detect
	dosbox-x -conf conf/dosbox-x_pcjr.conf -c "mount c bin/" -c "c:" -c dir

test_boot: boot
	dosbox-x -conf conf/dosbox-x_pcjr.conf

res:
	@echo "Generating resources..."
	@echo "Compressing music..."
	python3 ~/progs/pc-8088-misc/pvmplay/convert_vgm_to_pvm.py res/cumparchiptune.vgm
	python3 ~/progs/pc-8088-misc/pvmplay/convert_vgm_to_pvm.py res/libertango.vgm
	mv res/cumparchiptune.pvm part1/uctumi-cumparsita.pvm
	mv res/libertango.pvm part2/uctumi-libertango.pvm
	@echo "Converting graphics..."
	python3 tools/parse_55_segment_data.py res/55-segment.png -o part1/segment55_data.asm
	python3 tools/parse_55_segment_font.py -o part1/segment55_table.asm
	python3 tools/parse_ibm_charset.py -m 4 res/tandy_1000_hx_charset-charset.bin -o part1/charset_0x20_0x60.bin
	python3 tools/parse_ibm_charset.py -m 9 res/arleka_font_caren_remix0C-charset.bin -o part2/charset_0x00_0x40.bin
	python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 9 -o res/alakran-cara.raw "res/alakran-cara.data"
	python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 9 -o part2/image_320_200.raw res/image_320_200.data
	@#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 10 -o src/flashparty.bin res/flashparty.data
	@#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/p.raw res/p.data
	@#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/v.raw res/v.data
	@#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/m.raw res/m.data
	@#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/invites.raw res/invites.data
	@#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/you.raw res/you.data
	@#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/to.raw res/to.data
	@#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/fp.raw res/fp.data
	@#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/2018.raw res/2018.data
	@#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/satelite.raw res/satelite.data
	@#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/tango_silueta.raw res/tango_silueta.data
	@echo "Compressing graphics..."
	@#lz4 -9 -f res/p.raw src/p.raw.lz4
	@#lz4 -9 -f res/v.raw src/v.raw.lz4
	@#lz4 -9 -f res/m.raw src/m.raw.lz4
	@#lz4 -9 -f res/invites.raw src/invites.raw.lz4
	@#lz4 -9 -f res/you.raw src/you.raw.lz4
	@#lz4 -9 -f res/to.raw src/to.raw.lz4
	@#lz4 -9 -f res/fp.raw src/fp.raw.lz4
	@#lz4 -9 -f res/2018.raw src/2018.raw.lz4
	@#lz4 -9 -f res/tango_silueta.raw src/tango_silueta.raw.lz4
	@#lz4 -9 -f res/satelite.raw src/satelite.raw.lz4
	zx7 -f res/alakran-cara.raw part2/alakran-cara.raw.zx7
	@echo "Done"

dis:
	@echo "Dissassembling..."
	ndisasm -b 16 -o 100h bin/${TARGET_NAME} | gvim -


fat_image: runme detect part1 part2a
	@echo "Generating FAT image with needed files"
	-rm -f boot_loader/fat_image.360
	sudo mkfs.msdos -n PVM_BOOT -C boot_loader/fat_image.360 360
	-sudo mkdir /media/floppy
	sudo mount -o loop boot_loader/fat_image.360 /media/floppy
	sudo cp bin/runme.com /media/floppy/
	sudo cp bin/detect.com /media/floppy/
	sudo cp bin/part1.com /media/floppy/
	sudo cp bin/part2gfx.com /media/floppy/part2.com
	sudo umount /media/floppy
	sudo rmdir /media/floppy
	dd if=boot_loader/fat_image.360 of=boot_loader/fat_without_boot.bin bs=512 skip=1 count=719
