#!/usr/bin/env python3
"""
gen_image.py - turn a picture into the puzzle's image ROM.

    python3 scripts/gen_image.py                 # built-in test scene
    python3 scripts/gen_image.py photo.jpg       # your own picture
    python3 scripts/gen_image.py photo.jpg --preview /tmp/p.png

Writes, next to the RTL that loads them:

    src/image.mem    76800 lines, one 8-bit palette index per pixel, 320x240
                     row-major (address = y*320 + x)
    src/palette.mem  256 lines, one 24-bit RRGGBB colour per index

The picture is centre-cropped to 4:3, scaled to 320x240 and reduced to the 256
colours that suit it best (median cut, Floyd-Steinberg dithered), the way an
indexed-colour console stores a background: a byte per pixel, and the real
colour looked up in a small palette on the way out.

Both files are plain $readmemh hex, read unchanged by Icarus Verilog, Vivado
and the VGA Playground.

The built-in scene is original procedural art (a lake at dusk), drawn so that
each of the sixteen 80x60 tiles looks different from the others, which a
sliding puzzle needs.
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

W, H = 320, 240
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, "..", "src"))


def test_scene() -> Image.Image:
    rng = np.random.default_rng(2110597)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    img = np.zeros((H, W, 3), np.float32)

    horizon = 150.0

    # sky: night blue at the top, through violet, to orange at the horizon
    t = np.clip(yy / horizon, 0, 1)[..., None]
    top = np.array([12, 18, 58], np.float32)
    mid = np.array([112, 52, 120], np.float32)
    low = np.array([255, 150, 70], np.float32)
    sky = np.where(t < 0.6, top + (mid - top) * (t / 0.6),
                   mid + (low - mid) * ((t - 0.6) / 0.4))
    img[:] = sky

    # stars, only in the dark part of the sky
    for _ in range(140):
        sx, sy = rng.integers(0, W), rng.integers(0, 80)
        b = rng.integers(150, 256)
        img[sy, sx] = [b, b, min(255, b + 20)]
        if rng.random() < 0.15 and 0 < sx < W - 1:
            img[sy, sx - 1] = img[sy, sx + 1] = [b * 0.6, b * 0.6, b * 0.7]

    # crescent moon, upper left
    d1 = (xx - 52) ** 2 + (yy - 38) ** 2
    d2 = (xx - 60) ** 2 + (yy - 33) ** 2
    moon = (d1 < 17 ** 2) & (d2 > 15 ** 2)
    img[moon] = [250, 245, 215]

    # setting sun with a glow, right of centre, half under the horizon
    ds = np.sqrt((xx - 222) ** 2 + (yy - 142) ** 2)
    glow = np.clip(1 - ds / 70, 0, 1)[..., None] ** 2
    img = img + glow * np.array([120, 70, 10], np.float32)
    img[(ds < 22) & (yy < horizon)] = [255, 225, 120]

    # two ranges of mountains
    def ridge(base, amp, freqs, phase):
        r = np.full(W, base, np.float32)
        x = np.arange(W, dtype=np.float32)
        for f, a in zip(freqs, amp):
            r += a * np.sin(x * f + phase)
        return r

    far = ridge(118, [14, 7, 3], [0.021, 0.057, 0.13], 1.3)
    near = ridge(136, [12, 6, 2.5], [0.034, 0.081, 0.19], 4.1)
    for x in range(W):
        img[int(far[x]):int(horizon), x] = [84, 58, 110]
        img[int(near[x]):int(horizon), x] = [48, 34, 72]

    # snow caps on the far range's highest peaks
    for x in range(W):
        if far[x] < 108:
            img[int(far[x]):int(far[x]) + 4, x] = [200, 190, 220]

    # lake: the sky above, mirrored and darkened, broken by ripples
    for y in range(int(horizon), H):
        src_y = int(2 * horizon - y)
        src_y = max(0, min(int(horizon) - 1, src_y))
        shift = int(3 * np.sin(y * 0.9))
        row = np.roll(img[src_y], shift, axis=0) * 0.62
        row += np.array([4, 10, 26], np.float32)
        img[y] = row

    # the sun's path of light across the water
    for y in range(int(horizon), H):
        w = 4 + (y - horizon) * 0.35
        for x in range(int(222 - w), int(222 + w)):
            if 0 <= x < W and ((x + y * 3) % 7) < 4:
                img[y, x] = img[y, x] * 0.5 + np.array([255, 200, 110]) * 0.5

    # left shore with pine trees and a cabin
    shore = 176 + 10 * np.sin(np.arange(W) * 0.05)
    for x in range(0, 128):
        top_y = int(shore[x] - (128 - x) * 0.35)
        img[top_y:H, x] = [22, 40, 30]

    def pine(cx, base, h):
        for dy in range(h):
            half = int((dy / h) * h * 0.32) + 1
            y = base - h + dy
            img[y, max(0, cx - half):min(W, cx + half + 1)] = [16, 56, 36]
        img[base:base + 5, cx - 1:cx + 2] = [60, 40, 24]

    for cx, h in [(12, 46), (30, 38), (46, 52), (70, 34), (92, 30)]:
        base = int(shore[cx] - (128 - cx) * 0.35) + 4
        pine(cx, base, h)

    # cabin with a lit window, right next to the water
    img[166:186, 100:124] = [96, 58, 40]
    for i in range(12):                      # roof
        img[154 + i, 112 - i - 1:112 + i + 1] = [140, 50, 44]
    img[171:178, 105:111] = [255, 210, 110]  # window
    img[178:186, 115:120] = [40, 24, 16]     # door

    # right shore: a grassy bank with rocks
    for x in range(240, W):
        top_y = int(204 - (x - 240) * 0.45 + 3 * np.sin(x * 0.3))
        img[top_y:H, x] = [30, 58, 34]
    for cx, cy, r in [(262, 214, 7), (284, 208, 9), (306, 200, 6)]:
        rock = (xx - cx) ** 2 + ((yy - cy) * 1.6) ** 2 < r * r
        img[rock] = [92, 92, 104]

    # fireflies over the left shore, so the bottom-left tiles differ too
    for _ in range(30):
        fx, fy = rng.integers(4, 120), rng.integers(186, 236)
        img[fy, fx] = [230, 255, 120]

    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")


def load_picture(path: str) -> Image.Image:
    im = Image.open(path).convert("RGB")
    w, h = im.size
    # centre-crop to 4:3 before scaling, so nothing is stretched
    if w * 3 > h * 4:
        nw = h * 4 // 3
        im = im.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
    else:
        nh = w * 3 // 4
        im = im.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
    return im.resize((W, H), Image.LANCZOS)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("picture", nargs="?", help="input picture (default: built-in test scene)")
    ap.add_argument("--preview", help="also save the 256-colour result as a PNG")
    ap.add_argument("--out", default=SRC, help="output directory (default: src/)")
    args = ap.parse_args()

    im = load_picture(args.picture) if args.picture else test_scene()
    q = im.quantize(colors=256, method=Image.Quantize.MEDIANCUT,
                    dither=Image.Dither.FLOYDSTEINBERG)

    idx = np.asarray(q, dtype=np.uint8)
    pal = q.getpalette()[: 256 * 3]
    pal += [0] * (256 * 3 - len(pal))

    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "image.mem"), "w") as f:
        f.write("\n".join(f"{v:02x}" for v in idx.reshape(-1)))
        f.write("\n")
    with open(os.path.join(args.out, "palette.mem"), "w") as f:
        for i in range(256):
            r, g, b = pal[3 * i: 3 * i + 3]
            f.write(f"{r:02x}{g:02x}{b:02x}\n")

    if args.preview:
        q.convert("RGB").save(args.preview)

    used = len(np.unique(idx))
    print(f"wrote {args.out}/image.mem ({W}x{H}) and palette.mem ({used} colours used)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
