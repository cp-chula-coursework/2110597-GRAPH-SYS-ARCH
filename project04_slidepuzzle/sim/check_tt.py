#!/usr/bin/env python3
"""
check_tt.py - check the frame tb_tt.v decoded from the Tiny VGA pins.

The frame was read off uo_out with the VGA Playground's own bit mapping
(R = {uo[0], uo[4]}, G = {uo[1], uo[5]}, B = {uo[2], uo[6]}, each 0..3 shown
as 0/85/170/255). Here the title screen is rebuilt from image.mem and
palette.mem, passed through the same 4x4 Bayer dither the top applies, and
compared exactly. A swapped or misplaced colour pin cannot get through that.

Also saves tt_title / tt_play as PNGs in sim/out/ for a look.
"""
import os
import sys

import numpy as np
from PIL import Image

import check_frames as cf


def bayer_threshold(xs, ys):
    rank = (((xs ^ ys) & 1) << 3) | ((ys & 1) << 2) | \
           ((((xs >> 1) ^ (ys >> 1)) & 1) << 1) | ((ys >> 1) & 1)
    return rank * 16 + 8


def dither(img):
    t = bayer_threshold(cf.XS, cf.YS)[..., None]
    return ((3 * img + t) >> 8) * 85


def main():
    got = cf.read_ppm(os.path.join(cf.OUT, "tt_title.ppm"))
    exp = dither(cf.full_picture())
    diff = np.any(got != exp, axis=2)
    n = int(diff.sum())
    for name in ("tt_title", "tt_play"):
        p = os.path.join(cf.OUT, name + ".ppm")
        if os.path.exists(p):
            Image.fromarray(cf.read_ppm(p).astype(np.uint8)).save(
                os.path.join(cf.OUT, name + ".png"))
    if n:
        ys, xs = np.nonzero(diff)
        print(f"FAIL tt_title: {n} pixels differ, first at ({xs[0]},{ys[0]}) "
              f"got {tuple(got[ys[0], xs[0]])} expected {tuple(exp[ys[0], xs[0]])}")
        return 1
    print("ok   tt_title: every pixel matches the dithered picture")
    print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
