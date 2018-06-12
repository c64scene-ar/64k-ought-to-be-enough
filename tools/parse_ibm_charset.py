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
            chars = buff[32:32+64]
            print(len(chars))

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
        with open(args.output_file, 'w+') as fd:
            Parser(args.filename, fd).run()
    else:
        Parser(args.filename, sys.stdout).run()

if __name__ == "__main__":
    main()
