.PHONY: res

TARGET_NAME = invitro.exe
TARGET = bin/${TARGET_NAME}
ASM = nasm
ASMFLAGS = -fobj -Wall
LD = alink
LDFLAGS = -oEXE -m

default: $(TARGET)
all: res default

OBJECTS = main.o detect_card.o pztimer.o lz4_8088.o zx7_8086.o intro.o utils.o

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
	-rm invitro.zip
	-rm invitro/invitro.exe
	cp bin/invitro.exe invitro/
	zip invitro.zip -r invitro

res:
	echo "Generating resources..."
	echo "Compressing music..."
	python3 ~/progs/pc-8088-misc/pvmplay/convert_vgm_to_pvm.py res/cumparchiptune.vgm
	mv res/cumparchiptune.pvm src/
	echo "Converting graphics..."
	#python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 10 -o src/flashparty.bin res/flashparty.data
	python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/p.raw res/p.data
	python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/v.raw res/v.data
	python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/m.raw res/m.data
	python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/invites.raw res/invites.data
	python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/you.raw res/you.data
	python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/to.raw res/to.data
	python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/fp.raw res/fp.data
	python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/2018.raw res/2018.data
	python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/satelite.raw res/satelite.data
	python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 4 -o res/tango_silueta.raw res/tango_silueta.data
	echo "Compressing graphics..."
	lz4 -9 -f res/p.raw src/p.raw.lz4
	lz4 -9 -f res/v.raw src/v.raw.lz4
	lz4 -9 -f res/m.raw src/m.raw.lz4
	lz4 -9 -f res/invites.raw src/invites.raw.lz4
	lz4 -9 -f res/you.raw src/you.raw.lz4
	lz4 -9 -f res/to.raw src/to.raw.lz4
	lz4 -9 -f res/fp.raw src/fp.raw.lz4
	lz4 -9 -f res/2018.raw src/2018.raw.lz4
	lz4 -9 -f res/tango_silueta.raw src/tango_silueta.raw.lz4
	lz4 -9 -f res/satelite.raw src/satelite.raw.lz4
	echo "Done"
