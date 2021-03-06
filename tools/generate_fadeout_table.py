#!/usr/bin/env python3
# ----------------------------------------------------------------------------
# Generates fadeout table
# ----------------------------------------------------------------------------
"""
Tool to generate fadeout table
"""
import argparse
import math
import sys

__docformat__ = 'restructuredtext'

class Fadeout:
    def __init__(self, fd):
        self._fd = fd
        # white (15) -> light green (10) -> yellow (14) -> cyan (11) ->
        # light grey (7) -> green (2) -> light red (12) -> light blue (9) ->
        # grey 2 (8) -> orange/cyan (13) -> violet/magent (5) -> red (4) ->
        # dark grey/cyan (3) -> brown (6) -> blue (1) -> black (0)
        self._colors = [0, 1, 6, 3, 4, 5, 13, 8, 9, 12, 2, 7, 11, 14, 10, 15]
        self._total_colors = len(self._colors)

    def generate(self):
        # parse each color in order
        self._fd.write(';=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;\n')
        self._fd.write('; Autogenerated with generate_fadeout_table.py\n')
        self._fd.write('; DO NOT MODIFY\n')
        self._fd.write(';=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;\n')
        self._fd.write('fadeout_palette_tbl:\n')
        for c in range(self._total_colors):
            self.gen_table_for_color(c)

    def gen_table_for_color(self, color):
        index = self._colors.index(color)
        inc_var = (index+1) / self._total_colors
        accum = 0
        self._fd.write(';table for color %d\n' % color)
        self._fd.write('\tdb ')
        for c in range(self._total_colors):
            self._fd.write('%d,' % self._colors[int(accum)])
            accum += inc_var
        self._fd.write('\n')


def parse_args():
    """parse the arguments"""
    parser = argparse.ArgumentParser(
        description='Generates a fadeout table'
        'BIOS', epilog="""Example:

$ %(prog)s -o fadeout.asm
""")
    parser.add_argument('-o', '--output-file', metavar='<filename>',
            help='output file.', required=True)

    args = parser.parse_args()
    return args


def main():
    args = parse_args()
    with open(args.output_file, 'w+') as fd:
        Fadeout(fd).generate()

if __name__ == "__main__":
    main()
