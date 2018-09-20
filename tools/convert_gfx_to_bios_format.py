#!/usr/bin/env python3
# ----------------------------------------------------------------------------
# converts PNG images to PCjr / Tandy 1000 graphic modes - riq
# ----------------------------------------------------------------------------
"""
Tool to convert PNG images to CGA / PCJr / Tandy 1000 video modes
"""
import argparse
import math
import os
import sys

from PIL import Image
from collections import namedtuple


__docformat__ = 'restructuredtext'

BIOSFormat = namedtuple('BIOSFormat', 'width, height, colors, blocks')
formats = {}
formats[0] = BIOSFormat(-1, -1, -1, -1)        # Used for debug
formats[4] = BIOSFormat(320, 200, 4, 2)        # 320 x 200 4 colors
formats[6] = BIOSFormat(640, 200, 2, 2)        # 640 x 200 2 colors
formats[8] = BIOSFormat(160, 200, 16, 2)       # 160 x 200 16 colors
formats[88] = BIOSFormat(160, 100, 16, 1)       # 160 x 100 16 colors
formats[9] = BIOSFormat(320, 200, 16, 4)       # 320 x 200 16 colors
formats[10] = BIOSFormat(640, 200, 4, 4)       # 640 x 200 4 colors


def parse_line_2(bitmap):
    """converts 2 bytes into 1 byte. Used in 16-color modes"""
    ba = bytearray()
    for i in range(len(bitmap) // 2):
        hi = bitmap[i * 2 + 0] & 0xf
        lo = bitmap[i * 2 + 1] & 0xf
        byte = hi << 4 | lo
        ba.append(byte)
    return ba


def parse_line_4(bitmap):
    """converts 4 bytes into 1 byte. Used in 4-color modes"""
    ba = bytearray()
    for i in range(len(bitmap) // 4):
        b1 = bitmap[i * 4 + 0]
        b2 = bitmap[i * 4 + 1]
        b3 = bitmap[i * 4 + 2]
        b4 = bitmap[i * 4 + 3]
        if b1 > 3 or b2 > 3 or b3 > 3 or b4 > 3:
            raise Exception('Invalid pixel value: %d,%d,%d,%d > 3' %
                    (b1, b2, b3, b4))
        byte = (b1 << 6) | (b2 << 4) | (b3 << 2) | b4
        ba.append(byte)
    return ba

def parse_line_4_ext(bitmap):
    """converts 4 bytes into 1 byte. Used in 4-color modes"""
    ba = bytearray()
    for i in range(len(bitmap) // 8):
        even_byte = 0
        odd_byte = 0
        for p in range(8):
            b = bitmap[i * 8 + p]
            assert(b < 4)
            even_byte |= ((b & 0b01) << (7-p))
            odd_byte |= (((b & 0b10) >> 1) << (7-p))
        assert(even_byte < 256)
        assert(odd_byte < 256)
        ba.append(even_byte)
        ba.append(odd_byte)
    return ba

def parse_line_8(bitmap):
    """converts 8 bytes into 1 byte. Used in 2-color modes"""
    ba = bytearray()
    for i in range(len(bitmap) // 8):
        b1 = bitmap[i * 8 + 0] & 0x1
        b2 = bitmap[i * 8 + 1] & 0x1
        b3 = bitmap[i * 8 + 2] & 0x1
        b4 = bitmap[i * 8 + 3] & 0x1
        b5 = bitmap[i * 8 + 4] & 0x1
        b6 = bitmap[i * 8 + 5] & 0x1
        b7 = bitmap[i * 8 + 6] & 0x1
        b8 = bitmap[i * 8 + 7] & 0x1
        byte = (b1 << 7) | (b2 << 6) | (b3 << 5) | (b4 << 4) | (b5 << 3) | \
               (b6 << 2) | (b7 << 1) | b8
        ba.append(byte)
    return ba


def parse_line(array, gfx_format):
    colors = gfx_format.colors
    if colors == 16:
        return parse_line_2(array)
    if colors == 4 and gfx_format.width != 640:
        return parse_line_4(array)
    if colors == 4 and gfx_format.width == 640:
        # 640 x 200 @ 4 colors use different byte enconding
        return parse_line_4_ext(array)
    if colors == 2:
        return parse_line_8(array)
    return None


def write_to_file(lines, out_fd, gfx_format):
    """write files to output fd"""
    # reorder lines
    # raw format    ---> tandy 1000 format
    #   line 0            line 0
    #   line 1            line 4
    #   line 2            line 8
    #   line 3            line 12
    #   line 4            line 16
    #   line 5            line 20
    #   line 6            line 24
    #   line 7            line 28
    # ...

    bits_per_color = math.log2(gfx_format.colors)
    size = gfx_format.height * gfx_format.width * (bits_per_color / 8)
    lines_per_block = gfx_format.height // gfx_format.blocks
    ordered = []
    for i in range(gfx_format.blocks):
        for j in range(lines_per_block):
            ordered.append(lines[j * gfx_format.blocks + i])
        ordered.append(bytearray(192))

    for l in ordered:
        out_fd.buffer.write(l)


def run(image_file, gfx_format, output_fd):
    """execute the conversor"""
    lines = []
    with Image.open(image_file) as im:
        width = im.width
        height = im.height
        array = im.tobytes()

        if gfx_format.colors == -1:
            # Debug. Write what's inside PIL
            output_fd.buffer.write(array)
        else:
            for y in range(height):
                line = array[width * y : width * (y+1)]
                lines.append(parse_line(line, gfx_format))

            write_to_file(lines, output_fd, gfx_format)


def parse_args():
    """parse the arguments"""
    parser = argparse.ArgumentParser(
        description='Converts .png images to different formats supported by '
        'BIOS', epilog="""Example:

$ %(prog)s -g 9 -o image.tandy image.png
""")
    parser.add_argument('filename', metavar='<filename>',
            help='file to convert')
    parser.add_argument('-g', '--bios_gfx_mode', type=int, metavar='BIOS_graphics_mode',
            dest='format', help='output file. Default: 4. Valid options: 0, 4, 6, 8, 88, 9, 10',
            default=4, required=True)
    parser.add_argument('-o', '--output-file', metavar='<filename>',
            help='output file. Default: stdout', required=True)

    args = parser.parse_args()
    return args


def main():
    args = parse_args()
    with open(args.output_file, 'w+') as fd:
        run(args.filename, formats[args.format], fd)

if __name__ == "__main__":
    main()
