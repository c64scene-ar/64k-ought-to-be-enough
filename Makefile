.PHONY: res runme part2 part2a part1 part1a part3 part3a

TARGET_NAME_DETECT = detect.com
TARGET_DETECT = bin/${TARGET_NAME_DETECT}
ASM = nasm
ASMFLAGS = -fobj -Wall -Ox
LD = alink
LDFLAGS = -oCOM -m

all: res test_boot
detect: $(TARGET_DETECT)

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
	@python3 tools/append_gfx_to_com.py part1/image_320_200.raw -c bin/part1.com -o bin/part1gfx.com -s 48

test_part1: part1a
	@echo "Running..."
	dosbox-x -conf conf/dosbox-x_pcjr.conf -c "mount c bin/ && dir" -c "c:" -c part1gfx.com

part2:
	@echo "Generating part2.com"
	nasm -Ox -Wall part2/part2.asm -fbin -o bin/part2.com

part2a: part2
	@python3 tools/append_gfx_to_com.py part2/alakran-cara.raw -c bin/part2.com -o bin/part2gfx.com -s 32
	@echo "Done."

test_part2: part2a
	@echo "Running..."
	dosbox-x -conf conf/dosbox-x_pcjr.conf -c "mount c bin/ && dir" -c "c:" -c part2gfx.com

part3:
	@echo "Generating part3.com"
	nasm -Ox -Wall part3/part3.asm -fbin -o bin/part3.com

part3a: part3
	@python3 tools/append_gfx_to_com.py part3/image_zero.raw -c bin/part3.com -o bin/part3gfx.com -s 56

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

fat_image: runme detect part1a part2a part3a
	@echo "Generating FAT image with needed files"
	-rm -f boot_loader/fat_image.360
	sudo mkfs.msdos -n PVM_BOOT -C boot_loader/fat_image.360 360
	-sudo mkdir /media/floppy
	sudo mount -o loop boot_loader/fat_image.360 /media/floppy
	sudo cp bin/runme.com /media/floppy/
	sudo cp bin/detect.com /media/floppy/
	sudo cp bin/part1gfx.com /media/floppy/part1.com
	sudo cp bin/part2gfx.com /media/floppy/part2.com
	sudo cp bin/part3gfx.com /media/floppy/part3.com
	sudo umount /media/floppy
	sudo rmdir /media/floppy
	dd if=boot_loader/fat_image.360 of=boot_loader/fat_without_boot.bin bs=512 skip=1 count=719

boot: fat_image
	nasm -Ox -Wall boot_loader/boot_loader.asm -fbin -o boot_loader/boot.bin
	cat boot_loader/boot.bin boot_loader/fat_without_boot.bin > bin/demo_pvm.360

test_boot: boot
	dosbox-x -conf conf/dosbox-x_pcjr.conf

dist: boot
	@echo "Generating distribution .zip"
	-rm 64kought.zip
	-rm 64kought/64kought.360
	cp bin/demo_pvm.360 64kought/64kought.360
	zip 64kought.zip -r 64kought

res:
	@echo "Generating resources..."
	@echo "Compressing music..."
	python3 tools/convert_vgm_to_pvm.py res/cumparchiptune.vgm
	python3 tools/convert_vgm_to_pvm.py res/libertango.vgm
	python3 tools/convert_vgm_to_pvm.py res/zamba_de_mi_esperanza.vgm
	mv res/cumparchiptune.pvm part1/uctumi-cumparsita.pvm
	mv res/libertango.pvm part2/uctumi-libertango.pvm
	mv res/zamba_de_mi_esperanza.pvm part3/uctumi-zamba.pvm
	@echo "Converting graphics..."
	python3 tools/parse_55_segment_data.py res/55-segment.png -o part1/segment55_data.asm
	python3 tools/parse_55_segment_font.py -o part1/segment55_table.asm
	python3 tools/parse_ibm_charset.py -m 4 res/tandy_1000_hx_charset-charset.bin -o part1/charset_0x20_0x60.bin
	python3 tools/convert_gfx_to_bios_format.py -g 9 -o part2/alakran-cara.raw "res/alakran-cara.png"
	python3 tools/convert_gfx_to_bios_format.py -g 88 -o part3/image_pampa.raw "res/part3_pampa.png"
	python3 tools/convert_gfx_to_bios_format.py -g 10 -o res/image_moon.raw "res/part3_moon.png"
	python3 tools/convert_gfx_to_bios_format.py -g 6 -o res/image_still_there.raw "res/part3_still_there.png"
	python3 tools/convert_gfx_to_bios_format.py -g 8 -o part1/image_320_200.raw res/part1_image.png
	python3 tools/parse_big_charset.py -o part2/charset_bigfont.bin res/part2_font_arleka-4colors.png
	python3 tools/generate_elipse.py -o part3/elipse_table.asm -v 64
	python3 tools/vector_editor.py -o part3/svg_font.asm
	python3 tools/generate_fadeout_table.py -o common/fadeout16.asm
	@echo "Splitting graphic..."
	@dd if=res/image_moon.raw of=res/image_moon_half_a.raw count=1 bs=16384
	@dd if=res/image_moon.raw of=res/image_moon_half_b.raw count=1 skip=1 bs=16384
	@echo "Compressing graphics..."
	@lz4 -9 -f res/image_moon_half_a.raw part3/image_moon_half_a.raw.lz4
	@lz4 -9 -f res/image_moon_half_b.raw part3/image_moon_half_b.raw.lz4
	@lz4 -9 -f res/image_still_there.raw part3/image_still_there.raw.lz4
	@lz4 -9 -f part3/image_pampa.raw part3/image_pampa.raw.lz4
	@echo "Done"

dis:
	@echo "Dissassembling..."
	ndisasm -b 16 -o 100h bin/part1.com | gvim -


