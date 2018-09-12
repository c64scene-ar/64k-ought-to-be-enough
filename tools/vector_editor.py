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

    def draw_base(self):
        r = self.SIZE_X // 2
        center_x = self.SIZE_X // 2
        center_y = self.SIZE_Y // 2
        self._draw.ellipse((center_x - r, center_y - r, center_x + r, center_y + r),
            fill=(164,164,164,255))
        self._draw.line((0, center_y, self.SIZE_X, center_y),
                fill=(92,92,92,255))
        self._draw.line((center_x, 0, center_x, self.SIZE_Y),
                fill=(92,92,92,255))

    def draw(self, key):
        segments = self._chars[key]
        print('Drawing %s - segments: %d' % (key, len(segments)))

        self.draw_base()

        for segment in segments:
            self._draw.line(segment)

        self._image.show()
        self._image.save('letter_%s.png' % key)


def main():
    v = Vector()
    v.draw('A')

if __name__ == "__main__":
    main()
