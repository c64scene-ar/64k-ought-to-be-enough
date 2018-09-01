.PHONY: res runme part2 part2a part1 part1a part3 part3a

TARGET_NAME_DETECT = detect.com
TARGET_DETECT = bin/${TARGET_NAME_DETECT}
ASM = nasm
ASMFLAGS = -fobj -Wall -Ox
LD = alink
LDFLAGS = -oCOM -m

detect: $(TARGET_DETECT)

all: res test_boot

SRCFILES_DETECT = detect/detect.asm common/pztimer.asm
OBJECTS_DETECT = $(patsubst %.asm, %.o, $(SRCFILES_DETECT))

%.o: %.asm
	$(ASM) $(ASMFLAGS) $< -o $@

.PRECIOUS: $(TARGET_P1) $(OBJECTS_P1) $(TARGET_DETECT) $(OBJECTS_DETECT)

$(TARGET_DETECT): $(OBJECTS_DETECT)
	echo "Linking..."
	$(LD) $(OBJECTS_DETECT) $(LDFLAGS) -o $@

clean:
	@echo "Cleaning..."
	-rm -f */*.o
	-rm -f bin/*.map

part1:
	@echo "Generating part1.com"
	nasm -Ox -Wall part1/part1.asm -fbin -o bin/part1.com

part1a: part1
	@echo "Appending GFX to .com..."
	@python3 tools/append_gfx_to_com.py part1/image_320_200.raw -c bin/part1.com -o bin/part1gfx.com -s 48
	@echo "Done."

test_part1: part1a
	@echo "Running..."
	dosbox-x -conf conf/dosbox-x_pcjr.conf -c "mount c bin/ && dir" -c "c:" -c part1gfx.com

part2:
	@echo "Generating part2.com"
	nasm -Ox -Wall part2/part2.asm -fbin -o bin/part2.com

part2a: part2
	@echo "Appending GFX to .com..."
	@python3 tools/append_gfx_to_com.py part2/alakran-cara.raw -c bin/part2.com -o bin/part2gfx.com -s 32
	@echo "Done."

test_part2: part2a
	@echo "Running..."
	dosbox-x -conf conf/dosbox-x_pcjr.conf -c "mount c bin/ && dir" -c "c:" -c part2gfx.com

part3:
	@echo "Generating part3.com"
	nasm -Ox -Wall part3/part3.asm -fbin -o bin/part3.com

part3a: part3
	@echo "Appending GFX to .com..."
	@python3 tools/append_gfx_to_com.py part3/image_pampa.raw -c bin/part3.com -o bin/part3gfx.com -s 32
	@echo "Done."

test_part3: part3a
	@echo "Running..."
	dosbox-x -conf conf/dosbox-x_pcjr.conf -c "mount c bin/ && dir" -c "c:" -c part3gfx.com

runme:
	@echo "Generating runme.com"
	nasm -Ox -Wall runme/runme.asm -fbin -o bin/runme.com

test_runme: runme
	@echo "Running..."
	dosbox-x -conf conf/dosbox-x_pcjr.conf -c "mount c bin/ && dir" -c "c:" -c runme.com

test_detect: detect
	dosbox-x -conf conf/dosbox-x_pcjr.conf -c "mount c bin/" -c "c:" -c dir

fat_image: runme detect part1a part2a
	@echo "Generating FAT image with needed files"
	-rm -f boot_loader/fat_image.360
	sudo mkfs.msdos -n PVM_BOOT -C boot_loader/fat_image.360 360
	-sudo mkdir /media/floppy
	sudo mount -o loop boot_loader/fat_image.360 /media/floppy
	sudo cp bin/runme.com /media/floppy/
	sudo cp bin/detect.com /media/floppy/
	sudo cp bin/part1gfx.com /media/floppy/part1.com
	sudo cp bin/part2gfx.com /media/floppy/part2.com
	sudo umount /media/floppy
	sudo rmdir /media/floppy
	dd if=boot_loader/fat_image.360 of=boot_loader/fat_without_boot.bin bs=512 skip=1 count=719

boot: fat_image
	nasm -Ox -Wall boot_loader/boot_loader.asm -fbin -o boot_loader/boot.bin
	cat boot_loader/boot.bin boot_loader/fat_without_boot.bin > bin/demo_pvm.360

test_boot: boot
	dosbox-x -conf conf/dosbox-x_pcjr.conf

dist: x
	@echo "Generating distribution .zip"
	-rm intro.zip
	-rm intro/intro.com
	cp bin/intro.com intro/
	zip intro.zip -r intro

res:
	@echo "Generating resources..."
	@echo "Compressing music..."
	python3 tools/convert_vgm_to_pvm.py res/cumparchiptune.vgm
	python3 tools/convert_vgm_to_pvm.py res/libertango.vgm
	mv res/cumparchiptune.pvm part1/uctumi-cumparsita.pvm
	mv res/libertango.pvm part2/uctumi-libertango.pvm
	@echo "Converting graphics..."
	python3 tools/parse_55_segment_data.py res/55-segment.png -o part1/segment55_data.asm
	python3 tools/parse_55_segment_font.py -o part1/segment55_table.asm
	python3 tools/parse_ibm_charset.py -m 4 res/tandy_1000_hx_charset-charset.bin -o part1/charset_0x20_0x60.bin
	@#python3 tools/parse_ibm_charset.py -m 9 res/arleka_font_caren_remix0C-charset.bin -o part2/charset_0x00_0x40.bin
	python3 tools/convert_gfx_to_bios_format.py -g 9 -o part2/alakran-cara.raw "res/alakran-cara.png"
	@#python3 tools/convert_gfx_to_bios_format.py -g 9 -o part2/image_320_200.raw res/part2_image.png
	python3 tools/convert_gfx_to_bios_format.py -g 9 -o part3/image_pampa.raw "res/part3_pampa.png"
	python3 tools/convert_gfx_to_bios_format.py -g 8 -o part1/image_320_200.raw res/part1_image.png
	python3 tools/parse_big_charset.py -o part2/charset_bigfont.bin res/part2_font_arleka-4colors.png
	@#python3 tools/convert_gfx_to_bios_format.py -g 10 -o src/flashparty.bin res/flashparty.data
	@#python3 tools/convert_gfx_to_bios_format.py -g 4 -o res/p.raw res/p.data
	@#python3 tools/convert_gfx_to_bios_format.py -g 4 -o res/v.raw res/v.data
	@#python3 tools/convert_gfx_to_bios_format.py -g 4 -o res/m.raw res/m.data
	@#python3 tools/convert_gfx_to_bios_format.py -g 4 -o res/invites.raw res/invites.data
	@#python3 tools/convert_gfx_to_bios_format.py -g 4 -o res/you.raw res/you.data
	@#python3 tools/convert_gfx_to_bios_format.py -g 4 -o res/to.raw res/to.data
	@#python3 tools/convert_gfx_to_bios_format.py -g 4 -o res/fp.raw res/fp.data
	@#python3 tools/convert_gfx_to_bios_format.py -g 4 -o res/2018.raw res/2018.data
	@#python3 tools/convert_gfx_to_bios_format.py -g 4 -o res/satelite.raw res/satelite.data
	@#python3 tools/convert_gfx_to_bios_format.py -g 4 -o res/tango_silueta.raw res/tango_silueta.data
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
	@#zx7 -f res/alakran-cara.raw part2/alakran-cara.raw.zx7
	@echo "Done"

dis:
	@echo "Dissassembling..."
	ndisasm -b 16 -o 100h bin/part1.com | gvim -


