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
    def __init__(self, input_file, output_fd):
        self._output_fd = output_fd
        self._input_file = input_file

    def run(self):
        """Execute the conversor."""
        with open(self._input_file,'rb') as fd:
            buff = fd.read()
            # only care about the chars 0x20 - 0x60
            chars = buff[32*8:32*8+64*8]
            out = bytearray()
            for byte in chars:
                b = self.parse_half_byte(byte>>4)
                out.append(b)
                b = self.parse_half_byte(byte)
                out.append(b)

        self._output_fd.write(out)

    def parse_half_byte(self, byte):
        masks = [0b0001, 0b0010, 0b0100, 0b1000]
        out = 0
        for bit in range(4):
            mask = byte & masks[bit]
            if mask != 0:
                # 0b11 is the color used for the charset
                out |= 0b11 << (bit * 2)
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

    args = parser.parse_args()
    return args


def main():
    args = parse_args()
    if args.output_file is not None:
        with open(args.output_file, 'wb') as fd:
            Parser(args.filename, fd).run()
    else:
        Parser(args.filename, sys.stdout).run()

if __name__ == "__main__":
    main()
