#!/usr/bin/env python3
# ----------------------------------------------------------------------------
# Parses a .PNG of certain dimensions and generates a font file to be used in
# the PCjr.
# ----------------------------------------------------------------------------
"""
Parses a .PNG of certain dimensions and generates a font file to be used in the
PCjr.
"""
import argparse
import math
import os
import sys

from PIL import Image
from collections import namedtuple


__docformat__ = 'restructuredtext'


def write_to_file(lines, out_fd, gfx_format):
    """write files to output fd"""
    out_fd.buffer.write(l)


class ParseBigCharset:
    # pixels between chars
    CHAR_WIDTH = 24         # char width in pixels in .png
    CHAR_HEIGHT = 32        # char height in pixels in .png
    SPACING = 2             # pixels between chars in the .png
    BITS_PER_COLOR = 2      # 4 colors max per pixel

    # how many pixels fits in one byte
    # eg: if using 4 colors (2 bits per color), then 4 pixels fits in one
    # byte
    PIXELS_PER_BYTE = 8 // BITS_PER_COLOR

    # how many bytes are needed to represent one row
    # eg: 6 bytes are needed for one row if the char is 24 pixels width
    # and each pixels needs 2 bits.
    BYTES_PER_ROW = CHAR_WIDTH // PIXELS_PER_BYTE


    def __init__(self, image_file, output_fd):
        output = bytearray()
        with Image.open(image_file) as im:
            self._im_width = im.width
            self._im_height = im.height
            self._array = im.tobytes()

            total_chars = self._im_width / (self.CHAR_WIDTH + self.SPACING)

            # Make sure the division was without decimal. Otherwise the
            # values might be incorrect
            assert(total_chars == int(total_chars))
            total_chars = int(total_chars)

            print('total chars: %d' % total_chars)
            for chr_idx in range(total_chars):
                output += self.parse_char(chr_idx)

            output_fd.buffer.write(output)

    def parse_char(self, chr_idx):
        output = bytearray()

        # parse each column first. columns are packed together.
        for col in range(self.BYTES_PER_ROW):
            output += self.parse_char_column(chr_idx, col)
        return output

    def parse_char_column(self, char_idx, col):
        output = bytearray()

        # offset to char and the wanted column
        offset = char_idx * (self.CHAR_WIDTH + self.SPACING) + col * self.PIXELS_PER_BYTE
        for i in range(self.CHAR_HEIGHT):
            b = self.parse_for_4_colors(offset)
            # point to next row
            offset += self._im_width
            output.append(b)
        return output

    def parse_for_4_colors(self, offset):
        """converts 4 bytes into 1 byte. Expects that each pixels has a value
        between 0 and 3. Otherwise the conversion won't work as expected
        """
        b0 = self._array[offset + 0] & 0x03
        b1 = self._array[offset + 1] & 0x03
        b2 = self._array[offset + 2] & 0x03
        b3 = self._array[offset + 3] & 0x03
        return (b0 << 6) | (b1 << 4) | (b2 << 2) | b3


def parse_args():
    """parse the arguments"""
    parser = argparse.ArgumentParser(
        description='Converts .raw images to different formats supported by '
        'BIOS', epilog="""Example:

$ %(prog)s -g 9 -o image.tandy image.raw
""")
    parser.add_argument('filename', metavar='<filename>',
            help='file to convert')
    parser.add_argument('-o', '--output-file', metavar='<filename>',
            help='output file. Default: stdout', required=True)

    args = parser.parse_args()
    return args


def main():
    args = parse_args()
    with open(args.output_file, 'w+') as fd:
        ParseBigCharset(args.filename, fd)

if __name__ == "__main__":
    main()
