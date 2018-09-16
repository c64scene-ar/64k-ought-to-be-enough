#!/usr/bin/env python3
# ----------------------------------------------------------------------------
# Generates vector fonts
# ----------------------------------------------------------------------------
"""
Tool to generate and view vector letters
"""
import PIL.Image as Image
import PIL.ImageDraw as ImageDraw
import argparse
import math
import sys

__docformat__ = 'restructuredtext'

class Vector:
    SIZE_X = 100
    SIZE_Y = 100
    SCALE_TO_X = 40
    SCALE_TO_Y = 40
    def __init__(self, fd):
        self._fd = fd
        self._image = Image.new("RGB", (self.SIZE_X, self.SIZE_Y))
        self._draw = ImageDraw.Draw(self._image)

        self._chars = {}

        self._chars['A'] = [
                ((25,80), (50,20), (80,80)),
                ((33,53), (68,49))
                ]
        self._chars['B'] = [
                ((56,41), (65,48), (67,63), (65,77), (58,82),
                    (25,80), (34,6), (69,8), (76,21), (72,38), (59,41), (32,40)),
                ]
        self._chars['C'] = [
                ((74,30), (67,21), (49,18), (42,20), (34,24), (29,43), (33,72),
                    (48,80), (64,80), (69,75))
                ]
        self._chars['D'] = [
                ((32,80), (64,80), (72,75), (77,65), (78,33), (73,24), (62,18), (31,18)),
                ((39,18), (38,80))
                ]
        self._chars['E'] = [
                ((74,20), (29,20), (28,80), (76,80)),
                ((29,50), (63,50))
                ]
        self._chars['F'] = [
                ((72,20), (31,20), (31,80)),
                ((31,50), (57,50))
                ]
        self._chars['G'] = [
                ((74,30), (67,21), (49,18), (42,20), (34,24), (29,43), (33,72),
                    (48,80), (64,80), (69,75), (70,53), (48,51))
                ]
        self._chars['H'] = [
                ((30,20), (32,81)),
                ((30,50), (67,49)),
                ((68,20), (65,80))
                ]
        self._chars['I'] = [
                ((49,80), (50,30)),
                ((50,24), (50,20))
                ]
        self._chars['J'] = [
                ((20,77), (27,85), (39,88), (49,85), (53,79), (49,29)),
                ((50,24), (50,20))
                ]
        self._chars['K'] = [
                ((28,80), (27,20)),
                ((73,20), (29,51), (70,80))
                ]
        self._chars['L'] = [
                ((34,20), (36,80), (70,79))
                ]
        self._chars['M'] = [
                ((22,80), (30,20), (50,50), (71,21), (75,80))
                ]
        self._chars['N'] = [
                ((32,80), (31,20), (57,80), (62,20))
                ]
        self._chars['O'] = [
                ((50,80), (40,80), (33,75), (25,63), (24,30), (43,20), (59,21),
                    (66,28), (70,53), (63,72), (59,79), (50,80))
                ]
        self._chars['P'] = [
                ((34,80), (35,20), (61,20), (67,25), (69,33), (68,45), (59,53),
                    (34,53))
                ]
        self._chars['Q'] = [
                ((42,81), (32,76), (26,66), (24,55), (24,35), (38,20), (57,21),
                    (65,28), (70,40), (71,62), (66,75), (56,80), (42,81)),
                ((54,72), (57,77), (63,86))
                ]
        self._chars['R'] = [
                ((33,80), (32,20), (50,20), (61,23), (66,27), (68,36), (65,48),
                    (57,51), (33,52)),
                ((52,51), (63,79))
                ]
        self._chars['S'] = [
                ((75,25), (72,21), (52,17), (36,20), (32,25), (30,34), (36,43),
                    (39,48), (60,49), (73,55), (77,67), (73,78), (62,83), (44,84),
                    (35,79))
                ]
        self._chars['T'] = [
                ((28,23), (76,20)),
                ((50,18), (50,80))
                ]
        self._chars['U'] = [
                ((33,20), (33,74), (36,78), (43,81), (58,82), (65,79), (69,73),
                    (70,20))
                ]
        self._chars['V'] = [
                ((27,21), (50,80), (76,20))
                ]
        self._chars['W'] = [
                ((22,20), (34,80), (50,50), (65,81), (75,20))
                ]
        self._chars['X'] = [
                ((25,20), (75,80)),
                ((72,20), (28,80))
                ]
        self._chars['Y'] = [
                ((28,20), (35,45), (50,56), (50,80)),
                ((70,20), (60,49), (50,56))
                ]
        self._chars['Z'] = [
                ((27,20), (73,20), (27,80), (71,80))
                ]

        # prefix them so that they are in the correct order when sorted
        # should conform to ASCII order
        # ASCII from 0x20 to 0x2f
        self._chars['00space'] = [
                ]
        self._chars['01exclamation'] = [
                ]
        self._chars['02quote'] = [
                ]
        self._chars['03hash'] = [
                ]
        self._chars['04dollar'] = [
                ]
        self._chars['05percent'] = [
                ]
        self._chars['06amp'] = [
                ]
        self._chars['07singlequote'] = [
                ((50,10), (50,21), (44,28))
                ]
        self._chars['08braketopen'] = [
                ]
        self._chars['09braketclosed'] = [
                ]
        self._chars['0Astar'] = [
                ]
        self._chars['0Bplus'] = [
                ]
        self._chars['0Ccomma'] = [
                ]
        self._chars['0Dminus'] = [
                ]
        self._chars['0Edot'] = [
                ]
        self._chars['0Fslash'] = [
                ]
        # ASCII from 0x30 to 0x39
        # this is the real zero
        self._chars['0Z'] = [
                ]
        self._chars['1'] = [
                ]
        self._chars['2'] = [
                ]
        self._chars['3'] = [
                ]
        self._chars['4'] = [
                ]
        self._chars['5'] = [
                ]
        self._chars['6'] = [
                ]
        self._chars['7'] = [
                ]
        self._chars['8'] = [
                ]
        self._chars['9'] = [
                ]

        # ASCII from 0x3a to 0x40
        # prefix them so that they are in the correct order when sorted
        # should conform to ASCII order
        self._chars['9Acolon'] = [
                ((49,38), (52,38), (52,41), (49,41), (49,38)),
                ((48,58), (52,58), (52,61), (49,61), (48,58)),
                ]
        self._chars['9Bsemicolon'] = [
                ]
        self._chars['9Cgreater'] = [
                ]
        self._chars['9Dequal'] = [
                ]
        self._chars['9Elesser'] = [
                ]
        self._chars['9Fquestion'] = [
                ]
        self._chars['9Gat'] = [
                ]

    def draw_base(self):
        x = self.SIZE_X
        y = self.SIZE_Y
        r = x // 2
        x2 = x // 2
        y2 = y // 2
        self._draw.ellipse((x2 - r, y2 - r, x2 + r, y2 + r),
            fill=(164,164,164,255))
        self._draw.line((0, y2, x, y2),
                fill=(92,92,92,255))
        self._draw.line((0, y * 0.8, x, y * 0.8),
                fill=(92,92,92,255))
        self._draw.line((0, y * 0.2, x, y * 0.2),
                fill=(92,92,92,255))
        self._draw.line((x2, 0, x2, y),
                fill=(92,92,92,255))

    def draw(self, key):
        segments = self._chars[key]
        print('Drawing %s - segments: %d' % (key, len(segments)))

        self.draw_base()

        for segment in segments:
            self._draw.line(segment)

        self._image.show()
        #self._image.save('letter.png')

    def generate(self):
        # we assume we are scaling a cirlce / square.
        scale = self.SCALE_TO_X / self.SIZE_X
        center = self.SCALE_TO_X / 2

        new_chars = {}
        #for k in self._chars:
        for k in self._chars:
            char = self._chars[k]
            # a char contain one or more segments
            new_segments = []
            for segment in char:
                # a segment contains one or more points
                new_segment = []
                for point in segment:
                    x = point[0] * scale
                    y = point[1] * scale
                    # invert x, since X should be positive
                    new_x = -(x - center)
                    new_y = y - center
                    angle = math.degrees(math.atan2(new_x, new_y))
                    # angle is clockwise for us, and angle 0 is the (x=0,y=1)
                    # so, adjust angle to correct one
                    angle = (angle + 180) % 360
                    # the 360 degrees are calculated between 0 and 255
                    angle = round(angle * 256 / 360)
                    radius = round(math.sqrt(new_x*new_x + new_y*new_y))
                    assert(angle < 256)
                    assert(radius < self.SCALE_TO_X)
                    new_segment.append((angle, radius))
                new_segments.append(new_segment)
            new_chars[k] = new_segments

        self.dump_asm(new_chars)

    def dump_asm(self, new_chars):
        self._fd.write(';=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;\n')
        self._fd.write('; Autogenerated with vector_editor.py\n')
        self._fd.write('; DO NOT MODIFY\n')
        self._fd.write(';=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;\n')
        self._fd.write('; Using polar coordiantes. Angle is between 0-255, of course.\n')
        self._fd.write(';=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;\n')
        # contains the entries... needed to generate the entry table
        entries = []
        for k in new_chars:
            segments = new_chars[k]
            entry_name = 'svg_letter_data_%s' % k
            entries.append((k, entry_name))
            self._fd.write('%s:\n' % entry_name)
            for i,segment in enumerate(segments):
                first = True
                for x, y in segment:
                    if first:
                        self._fd.write('\tdb 0x%02x, 0x%02x' % (x, y))
                        first = False
                    else:
                        self._fd.write(', 0x%02x, 0x%02x' % (x, y))

                if i != len(segments) - 1:
                    # don't print "end of segment" if this is the last segment
                    self._fd.write(', 0xff, 0xfe\t\t\t; end segment\n')
                else:
                    self._fd.write('\n')
            self._fd.write('\tdb 0xff, 0xff\t\t\t; end svg letter\n')
        self._fd.write('\n\n')
        self._fd.write(';=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;\n')
        self._fd.write('svg_letter_table:\n')

        # sort entries by label name
        sorted_entries = sorted(entries, key=lambda x:x[1])
        for key, data in sorted(entries):
            self._fd.write('svg_letter_entry_%s:\t\tdw %s\n' % (key, data))


def parse_args():
    """parse the arguments"""
    parser = argparse.ArgumentParser(
        description='Converts .raw images to different formats supported by '
        'BIOS', epilog="""Example:

$ %(prog)s -o svg_letters.asm
""")
    parser.add_argument('-o', '--output-file', metavar='<filename>',
            help='output file.', required=True)

    args = parser.parse_args()
    return args


def main():

    args = parse_args()
    with open(args.output_file, 'w+') as fd:

        to_show = []
        if sys.argv[1] != None:
            to_show = [sys.argv[1]]
        else:
            #to_show = ['A', 'B', 'C', 'P', 'R']
            to_show = ['J']

        v = Vector(fd)
        v.generate()
        #for l in to_show:
        #    v.draw(l)

if __name__ == "__main__":
    main()
