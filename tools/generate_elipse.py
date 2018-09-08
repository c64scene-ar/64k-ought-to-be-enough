#!/usr/bin/env python3
# ----------------------------------------------------------------------------
# Generaters pre-calculated coordinates for elipses
# ----------------------------------------------------------------------------
"""
Tool to generate elipse paths.
"""
import math


__docformat__ = 'restructuredtext'


class Elipse:
    def __init__(self, rx, ry):
        self._rx = rx
        self._ry = ry

    def calc(self, x, y, a):
        new_x = x * math.cos(a) - y * math.sin(a)
        new_y = x * math.sin(a) + y * math.cos(a)
        return (new_x, new_y)

    def run(self):
        points = {}
        for px in range(0, 50):
            tmp_list = []
            for a in reversed(range(0, 90)):
                rad = math.radians(a)
                x, y = self.calc(px, 0, rad)
                tmp_list.append((int(x), int(y)))
            points[px] = tmp_list
        self.output(points)

    def output(self, points):
        print(';-------')
        for k in points:
            print('entry_%d_x:' % k)
            first = True
            count = 0
            for p in points[k]:
                if first:
                    print('        db %d' % p[0], end='')
                    first = False
                else:
                    print(', %d' % p[0], end='')
                count += 1
                if count >= 30:
                    first = True
                    count = 0
                    print('')
            print('')

def main():
    Elipse(0, 0).run()


if __name__ == "__main__":
    main()
