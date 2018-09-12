#!/usr/bin/env python3
# ----------------------------------------------------------------------------
# Appends GFX to .com
# ----------------------------------------------------------------------------

"""
Tool to generate and view vector letters
"""
import PIL.ImageDraw as ImageDraw
import PIL.Image as Image

class Vector:
    SIZE_X = 100
    SIZE_Y = 100
    def __init__(self):
        self._image = Image.new("RGB", (self.SIZE_X, self.SIZE_Y))
        self._draw = ImageDraw.Draw(self._image)

        self._chars = {}

        self._chars['A'] = [
                ((12,80), (49,2), (83,76)),
                ((25,46), (77,54)),
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
                ((72,20), (31,20), (31,80), (73,80)),
                ((31,50), (57,50))
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
        self._chars['P'] = [
                ((25,80), (34,6), (69,8), (76,21), (72,38), (59,41), (32,40)),
                ]
        self._chars['R'] = [
                ((25,80), (34,6), (69,8), (76,21), (72,38), (59,41), (32,40)),
                ((54,42), (60,77))
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


def main():
    v = Vector()
    #to_show = ['A', 'B', 'C', 'P', 'R']
    to_show = ['I']
    for l in to_show:
        v.draw(l)

if __name__ == "__main__":
    main()
