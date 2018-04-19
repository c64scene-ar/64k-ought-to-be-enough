.PHONY: res

TARGET_NAME = invitro.exe
TARGET = bin/${TARGET_NAME}
ASM = nasm
ASMFLAGS = -fobj -Wall
LD = alink
LDFLAGS = -oEXE -m

default: $(TARGET)
all: res default

OBJECTS = main.o intro.o detect_card.o pztimer.o

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
	python3 ~/progs/pc-8088-misc/pvmplay/convert_vgm_to_pvm.py res/cumparchiptune.vgm
	mv res/cumparchiptune.pvm src/
	python3 ~/progs/pc-8088-misc/tools/convert_gfx_to_bios_format.py -g 10 -o src/flashparty.bin res/flashparty.data
