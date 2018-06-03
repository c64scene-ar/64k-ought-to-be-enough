#!/usr/bin/env python3
# ----------------------------------------------------------------------------
# converts a "font" image to to .asm code
# ----------------------------------------------------------------------------
"""
Tool to convert a font-file to .asm code
"""
import argparse
import sys
import queue
from PIL import Image


__docformat__ = 'restructuredtext'


class Parser:
    def __init__(self, image_file, output_fd):
        self._visited = {}
        self._image_file = image_file
        self._output_fd = output_fd
        self._width = 0
        self._height = 0
        self._array = []
        self._segments = {}

    def run(self):
        """Execute the conversor."""
        im = Image.open(self._image_file)
        self._array = im.tobytes()
        self._width = im.width
        self._height = im.height

        segment = 0
        for x in range(self._width):
            for y in range(self._height):
                if not self.is_visited(x, y):
                    color = self.get_color(x, y)
                    self.start_segment(segment, x, y, color, 0)
                    #print(self._segments[segment])
                    segment += 1

        print('Total segments: %d' % segment)
        self.process_segments()

    def is_visited(self, x, y):
        key = '%d,%d' % (x, y)
        return key in self._visited

    def is_valid(self, segment, x, y, color):
        # safety check
        if x < 0 or x >= self._width:
            return False
        if y < 0 or y >= self._height:
            return False

        # ignore if already visited
        if self.is_visited(x, y):
            return False

        # ignore if not the same color
        if self.get_color(x, y) != color:
            return False

        return True

    def start_segment(self, segment, x, y, color, depth):
        # non recursive "visit" algorithm since to avoid recursion exception

        print('Starting segment: %d - color: %d (%d,%d)' % (segment, color, x, y))
        q = queue.Queue()
        q.put((x, y))
        while not q.empty():
            x, y = q.get()

            if not self.is_valid(segment, x, y, color):
                # skip already processed nodes
                continue

            # tagged as visited
            key = '%d,%d' % (x, y)
            self._visited[key] = True

            if segment not in self._segments:
                self._segments[segment] = {}

            if y not in self._segments[segment]:
                self._segments[segment][y] = []

            # update dictionary with values for segment
            self._segments[segment][y].append(x)

            # visit the rest of the nodes
            if self.is_valid(segment, x-1, y, color):
                q.put((x-1, y))
            if self.is_valid(segment, x+1, y, color):
                q.put((x+1, y))
            if self.is_valid(segment, x, y-1, color):
                q.put((x, y-1))
            if self.is_valid(segment, x, y+1, color):
                q.put((x, y+1))

    def get_color(self, x, y):
        return self._array[self._width * y + x]

    def process_segments(self):
        for segment_k, segment_v in self._segments.items():
            for col, values in segment_v.items():
                values.sort()
                # non contiguos regions not supported yet (not needed for 55-segment)
                assert(len(values)-1 == values[-1] - values[0])
                # replace strings with range
                self._segments[segment_k][col] = (values[0], values[-1])

        print(self._segments[1])


def parse_args():
    """Parse the arguments."""
    parser = argparse.ArgumentParser(
        description='Converts font-file to asm', epilog="""Example:

$ %(prog)s 55-segment.png -o font.asm
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
