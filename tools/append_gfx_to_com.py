#!/usr/bin/env python3
# ----------------------------------------------------------------------------
# Appends GFX to .com
# ----------------------------------------------------------------------------
"""
Tool that appends a 32k GFX to a .com so that the GFX is loaded in the right
place (0x0800:0000)
"""
import argparse
import json
import sys
import logging


__docformat__ = 'restructuredtext'


class Parser:
    def __init__(self, com_max_size, gfx_file, com_file, output_fd):
        self._com_max_size = com_max_size
        self._com_file = com_file
        self._gfx_file = gfx_file
        self._output_fd = output_fd

        logging.basicConfig(level=logging.INFO)

        self.run()

    def run(self):
        """Execute the conversor."""
        with open(self._com_file, 'rb') as com_fd, \
                open(self._gfx_file, 'rb') as gfx_fd:
            com_data = com_fd.read()
            gfx_data = gfx_fd.read()

            # Max possible size for .com. It will be loaded in 0x0000:0600
            # and should not go over 0x0000:8000
            com_max_size = self._com_max_size * 1024 - 512 * 3
            com_size = len(com_data)

            # if delta, is negative, then .com too big
            com_delta = com_max_size - com_size
            logging.info("Bytes still available in .com: %d" % com_delta)
            if com_delta < 0:
                raise Exception('File too big. Reduce size by %d bytes' % int(com_delta))

            # create new binary
            self._output_fd.write(com_data)
            self._output_fd.write(bytearray(com_delta))
            self._output_fd.write(gfx_data)


def parse_args():
    """Parse the arguments."""
    parser = argparse.ArgumentParser(
        description='Converts charset to optimzied charset', epilog="""Example:

$ %(prog)s charset.bin -o new_charset.bin
""")
    parser.add_argument('filename', metavar='<filename>',
            help='file with the gfx')
    parser.add_argument('-c', '--com-file', metavar='<filename>',
            help='.com file. Default: stdout')
    parser.add_argument('-o', '--output-file', metavar='<filename>',
            help='output file. Default: stdout')
    parser.add_argument('-s', '--max-size', metavar='N', type=int,
            help='max size for .com. Possible values: 32, 48, 56, etc.')

    args = parser.parse_args()
    return args


def main():
    args = parse_args()
    with open(args.output_file, 'wb') as fd:
        Parser(args.max_size, args.filename, args.com_file, fd)

if __name__ == "__main__":
    main()
