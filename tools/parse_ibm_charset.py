#!/usr/bin/env python3
# ----------------------------------------------------------------------------
# Converts charset into optimized version
# ----------------------------------------------------------------------------
"""
Tool to convert a charset (256 chars * 8 bytes) into one suitable for fast
rendering in graphics mode 4 (320x200 @ 4 colors).
Only parses first chars from 0x20 to 0x60
"""
import argparse
import json
import sys


__docformat__ = 'restructuredtext'


class Parser:
    def __init__(self, input_file, mode, output_fd):
        self._output_fd = output_fd
        self._input_file = input_file
        if mode == 4:
            self.run4()
        elif mode == 9:
            self.run9()
        else:
            raise Exception('Invalid argument')

    def run4(self):
        """Execute the conversor."""
        with open(self._input_file,'rb') as fd:
            buff = fd.read()
            # only care about the chars 0x20 - 0x60
            chars = buff[32*8:32*8+64*8]
            out = bytearray()
            for byte in chars:
                b = self.parse_4_bits(byte>>4)
                out.append(b)
                b = self.parse_4_bits(byte)
                out.append(b)

        self._output_fd.write(out)

    def run9(self):
        """Execute the conversor."""
        with open(self._input_file,'rb') as fd:
            buff = fd.read()
            # only care about the chars 0x00 - 0x7f
            chars = buff[0:128*8]
            out = bytearray()
            for byte in chars:
                b = self.parse_2_bits(byte>>6)
                out.append(b)
                b = self.parse_2_bits(byte>>4)
                out.append(b)
                b = self.parse_2_bits(byte>>2)
                out.append(b)
                b = self.parse_2_bits(byte)
                out.append(b)

        self._output_fd.write(out)

    def parse_4_bits(self, byte):
        """Parses half a byte (4 bits) and returns one byte.
        Useful when using a 4 color video mode. """
        masks = [0b0001, 0b0010, 0b0100, 0b1000]
        # empty is color 2 (0b10)
        out = 0b10101010
        for bit in range(len(masks)):
            mask = byte & masks[bit]
            if mask != 0:
                # 0b11 is the color used for the charset
                out |= 0b11 << (bit * 2)
        return out

    def parse_2_bits(self, byte):
        """Parses a quarter of a byte (2 bits) and returns one byte.
        Useful when using a 16 color video mode.
        """
        masks = [0b01, 0b10]
        # empty is color 0 (0b00)
        out = 0b00000000
        for bit in range(len(masks)):
            mask = byte & masks[bit]
            if mask != 0:
                # 0b11 is the color used for the charset
                out |= 0b1111 << (bit * 4)
        return out


def parse_args():
    """Parse the arguments."""
    parser = argparse.ArgumentParser(
        description='Converts charset to optimzied charset', epilog="""Example:

$ %(prog)s charset.bin -o new_charset.bin
""")
    parser.add_argument('filename', metavar='<filename>',
            help='file to convert')
    parser.add_argument('-o', '--output-file', metavar='<filename>',
            help='output file. Default: stdout')
    parser.add_argument('-m', '--mode', metavar='N', type=int, default=9,
            help='BIOS graphics mode. Either 4 or 9. Default: 9')

    args = parser.parse_args()
    return args


def main():
    args = parse_args()
    if args.output_file is not None:
        with open(args.output_file, 'wb') as fd:
            Parser(args.filename, args.mode, fd)
    else:
        Parser(args.filename, args.mode, sys.stdout)

if __name__ == "__main__":
    main()
