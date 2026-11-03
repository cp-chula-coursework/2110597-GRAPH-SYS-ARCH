#!/usr/bin/env python3
"""
check_frames.py - compare the frames tb_puzzle.v dumped against an
independent model of what the screen must show.

    cd src && vvp /tmp/tb_puzzle.vvp && python3 ../sim/check_frames.py

Each frame's game state is in sim/out/info.txt: which tile is in each slot,
where the sliding tile is, and the iris radius. From that and nothing else
but src/image.mem + src/palette.mem, every one of the 640x480 pixels is
worked out here and compared exactly. Nothing about the picture is hard-coded,
so this keeps working when the picture is replaced.

Also writes sim/out/sheet.png, all the frames side by side, for a look.
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "src")
OUT = os.path.join(HERE, "out")

S_TITLE, S_SHUFFLE, S_PLAY, S_SLIDE, S_WIN = range(5)


def load_picture():
    with open(os.path.join(SRC, "image.mem")) as f:
        idx = np.array([int(t, 16) for t in f.read().split()], np.int64)
    with open(os.path.join(SRC, "palette.mem")) as f:
        pal = np.array([[int(t[0:2], 16), int(t[2:4], 16), int(t[4:6], 16)]
                        for t in f.read().split()], np.int64)
    assert idx.size == 320 * 240, idx.size
    return pal[idx.reshape(240, 320)]


def read_ppm(path):
    data = open(path, "rb").read()
    head = b"P6\n640 480\n255\n"
    assert data.startswith(head), path
    body = data[len(head):]
    assert len(body) == 640 * 480 * 3, f"{path}: {len(body)} bytes of pixels"
    return np.frombuffer(body, np.uint8).reshape(480, 640, 3).astype(np.int64)


PIC = load_picture()
YS, XS = np.mgrid[0:480, 0:640]
SLOT = (YS // 120) * 4 + XS // 160
LX, LY = XS % 160, YS % 120


def tile_pixels(tile, lx, ly):
    return PIC[(tile // 4) * 60 + ly // 2, (tile % 4) * 80 + lx // 2]


def bevel(c, lx, ly):
    c = c.copy()
    hi = (lx < 2) | (ly < 2)
    lo = ~hi & ((lx >= 158) | (ly >= 118))
    c[hi] = c[hi] + ((255 - c[hi]) >> 1)
    c[lo] = c[lo] >> 1
    return c


def full_picture():
    return tile_pixels(SLOT, LX, LY)


def board_view(board, extra_gap=None):
    tile = np.array(board)[SLOT]
    img = bevel(tile_pixels(tile, LX, LY), LX, LY)
    gap = tile == 15
    if extra_gap is not None:
        gap |= SLOT == extra_gap
    shadow = (LX < 5) | (LY < 5)
    gap_col = np.where(shadow[..., None], [6, 6, 12], [18, 18, 30])
    img[gap] = gap_col[gap]
    return img


def with_sprite(img, tile, mx, my):
    img = img.copy()
    m = (XS >= mx) & (XS < mx + 160) & (YS >= my) & (YS < my + 120)
    slx, sly = XS - mx, YS - my
    spr = bevel(tile_pixels(np.full_like(XS, tile), slx % 160, sly % 120),
                slx % 160, sly % 120)
    img[m] = spr[m]
    return img


def with_shine(img, pos):
    img = img.copy()
    d = np.abs((XS + YS) - pos)
    hi, lo = d < 8, (d >= 8) & (d < 26)
    img[hi] = img[hi] + ((255 - img[hi]) >> 1)
    img[lo] = img[lo] + ((255 - img[lo]) >> 2)
    return img


def expected(info):
    st = info["state"]
    board = info["board"]
    if st in (S_TITLE, S_SHUFFLE):
        img = full_picture()
        return with_shine(img, info["shine"]) if st == S_TITLE else img
    if st == S_PLAY:
        return full_picture() if info["peek"] else board_view(board)
    if st == S_SLIDE:
        img = board_view(board, extra_gap=info["mov_from"])
        return with_sprite(img, info["mov_tile"], info["mx"], info["my"])
    if st == S_WIN:
        r = info["iris_r"]
        inside = (XS - 320) ** 2 + (YS - 240) ** 2 < r * r
        img = board_view(board) >> 1
        img[inside] = full_picture()[inside]
        return img
    raise ValueError(st)


def parse_info():
    frames = []
    for line in open(os.path.join(OUT, "info.txt")):
        t = line.split()
        if not t or t[0] != "frame":
            continue
        d = {"name": t[1]}
        i = 2
        while i < len(t):
            if t[i] == "board":
                d["board"] = [int(v) for v in t[i + 1:i + 17]]
                i += 17
            else:
                d[t[i]] = int(t[i + 1])
                i += 2
        frames.append(d)
    return frames


def main():
    frames = parse_info()
    if not frames:
        print("no frames in info.txt")
        return 1
    bad = 0
    thumbs = []
    for info in frames:
        path = os.path.normpath(os.path.join(SRC, info["name"]))
        got = read_ppm(path)
        exp = expected(info)
        diff = np.any(got != exp, axis=2)
        n = int(diff.sum())
        name = os.path.basename(path)
        if n:
            ys, xs = np.nonzero(diff)
            y, x = ys[0], xs[0]
            print(f"FAIL {name}: {n} pixels differ, first at ({x},{y}) "
                  f"got {tuple(got[y, x])} expected {tuple(exp[y, x])}")
            bad += 1
        else:
            print(f"ok   {name}: state {info['state']}, all 307200 pixels match")
        thumbs.append(Image.fromarray(got.astype(np.uint8)).resize((320, 240)))

    sheet = Image.new("RGB", (320 * len(thumbs), 240))
    for i, t in enumerate(thumbs):
        sheet.paste(t, (320 * i, 0))
    sheet.save(os.path.join(OUT, "sheet.png"))

    print("PASS" if not bad else f"FAILED: {bad} frame(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
