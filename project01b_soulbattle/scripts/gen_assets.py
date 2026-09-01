#!/usr/bin/env python3
"""gen_assets.py - generate the two graphics ROMs for project01b_soulbattle.

All art here is original (drawn in Python, no ripped game assets) and baked
into plain Verilog `initial` blocks, so the ROMs behave identically in Vivado
synthesis and in Icarus Verilog simulation with no .mem path headaches - the
same approach as project02's font_rom.v and project03's sprite ROMs.

Generates (into hdl/, next to this script's parent):
  soul_rom.v     - the player's "soul": 2 frames of 16x16 px, 12-bit RGB
                   (0 = whole heart, 1 = shattered heart shown on game over),
                   addr = {frame, y[3:0], x[3:0]}
  monster_rom.v  - the enemy, ROOT SENTINEL: 64x64 px, 12-bit RGB, drawn on
                   screen at 2x (128x128), addr = {y[5:0], x[5:0]}

12'hFFF (pure white) = transparent in both ROMs, the same convention the
course slides use for sprites, so no pure white appears in the art itself
(highlights top out at 12'hEFF).

Usage:
  python3 scripts/gen_assets.py [--preview DIR]

--preview DIR additionally writes soul.png / monster.png previews (8x
nearest-neighbour blowups, requires Pillow) for eyeballing the art.
"""

import argparse
import os

HDL_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "hdl"))

TRANSPARENT = 0xFFF

# ---------------------------------------------------------------------------
# The soul: a 16x16 heart, authored as ASCII art.
#   'R' body red, 'h' highlight, 'd' shaded edge, '.' transparent
# ---------------------------------------------------------------------------
SOUL_PALETTE = {".": TRANSPARENT, "R": 0xF00, "h": 0xF66, "d": 0xA00}

SOUL_WHOLE = [
    "................",
    "..RRR......RRR..",
    ".RhhRR....RRRRR.",
    "RhhRRRR..RRRRRRR",
    "RhRRRRRRRRRRRRRR",
    "RRRRRRRRRRRRRRRd",
    "RRRRRRRRRRRRRRRd",
    ".RRRRRRRRRRRRRd.",
    ".RRRRRRRRRRRRRd.",
    "..RRRRRRRRRRRd..",
    "...RRRRRRRRRd...",
    "....RRRRRRRd....",
    ".....RRRRRd.....",
    "......RRRd......",
    ".......Rd.......",
    "................",
]

# Same heart, split by a jagged crack with the halves nudged apart - the
# classic "you died" shattered soul.
SOUL_BROKEN = [
    "................",
    "..RRR......RRR..",
    ".RhhR.......RRR.",
    "RhhRRR.....RRRRR",
    "RhRRRRd...RRRRRR",
    "RRRRRRd....RRRRd",
    "RRRRRRRd....RRRd",
    ".RRRRRRd....RRd.",
    ".RRRRRd......Rd.",
    "..RRRRd.....Rd..",
    "...RRRd....Rd...",
    "....RRd...Rd....",
    ".....Rd..Rd.....",
    "......d.Rd......",
    ".......ad.......",
    "..d..........d..",
]
SOUL_PALETTE["a"] = 0xA00


def from_ascii(rows, palette, w, h):
    assert len(rows) == h and all(len(r) == w for r in rows), "art size mismatch"
    return [[palette[c] for c in row] for row in rows]


# ---------------------------------------------------------------------------
# The enemy: ROOT SENTINEL, a floating carved stone mask, drawn procedurally
# on a 64x64 grid. Stone body + horns, one big glowing eye, a jagged mouth.
# ---------------------------------------------------------------------------
N = 64

STONE_LIGHT = 0x89A
STONE_MID = 0x678
STONE_DARK = 0x445
STONE_DEEP = 0x334
OUTLINE = 0x223
HORN = 0xBBA
HORN_DARK = 0x887
SOCKET = 0x112
GLOW = 0x6EE
GLOW_HOT = 0xCFF
GLOW_DIM = 0x277
TOOTH = 0xCDE


def blank():
    return [[TRANSPARENT] * N for _ in range(N)]


def in_poly(px, py, pts):
    """Even-odd point-in-polygon test at the pixel centre."""
    x, y = px + 0.5, py + 0.5
    inside = False
    n = len(pts)
    for i in range(n):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % n]
        if (y0 > y) != (y1 > y):
            xc = x0 + (y - y0) * (x1 - x0) / (y1 - y0)
            if x < xc:
                inside = not inside
    return inside


def poly_mask(pts):
    return [[in_poly(x, y, pts) for x in range(N)] for y in range(N)]


def ellipse_mask(cx, cy, rx, ry):
    m = [[False] * N for _ in range(N)]
    for y in range(N):
        for x in range(N):
            dx = (x + 0.5 - cx) / rx
            dy = (y + 0.5 - cy) / ry
            m[y][x] = dx * dx + dy * dy <= 1.0
    return m


def mask_or(*masks):
    return [[any(m[y][x] for m in masks) for x in range(N)] for y in range(N)]


def edge_of(mask):
    """1-pixel inner border of a mask (pixels with a non-mask 4-neighbour)."""
    out = [[False] * N for _ in range(N)]
    for y in range(N):
        for x in range(N):
            if not mask[y][x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx >= N or ny >= N or not mask[ny][nx]:
                    out[y][x] = True
                    break
    return out


def build_monster():
    img = blank()

    # --- silhouette: a heater-shield mask tapering to a chin, plus two horns
    body = poly_mask([(15, 12), (32, 7), (49, 12), (55, 22),
                      (53, 38), (32, 59), (11, 38), (9, 22)])
    horn_l = poly_mask([(16, 14), (3, 1), (13, 4), (22, 10)])
    horn_r = poly_mask([(48, 14), (61, 1), (51, 4), (42, 10)])
    horns = mask_or(horn_l, horn_r)
    solid = mask_or(body, horns)

    # --- stone shading: vertical gradient with a dithered transition band
    for y in range(N):
        for x in range(N):
            if not body[y][x]:
                continue
            if y < 16:
                c = STONE_LIGHT
            elif y < 20:
                c = STONE_LIGHT if (x + y) % 2 == 0 else STONE_MID
            elif y < 38:
                c = STONE_MID
            elif y < 42:
                c = STONE_MID if (x + y) % 2 == 0 else STONE_DARK
            else:
                c = STONE_DARK
            img[y][x] = c

    for y in range(N):
        for x in range(N):
            if horns[y][x]:
                img[y][x] = HORN if x + y < 60 else HORN_DARK

    # --- brow ridge across the top of the face
    for x in range(13, 51):
        y = 13 + abs(x - 32) // 5
        for dy in range(2):
            if body[y + dy][x]:
                img[y + dy][x] = STONE_DEEP

    # --- the eye: dark socket with a glowing rim, iris, slit pupil, specular
    socket = ellipse_mask(32, 26, 17, 10)
    socket_in = ellipse_mask(32, 26, 15.5, 8.6)
    iris = ellipse_mask(32, 26, 9, 7)
    pupil = ellipse_mask(32, 26, 3, 6)
    for y in range(N):
        for x in range(N):
            if not body[y][x] or not socket[y][x]:
                continue
            if pupil[y][x]:
                img[y][x] = SOCKET
            elif iris[y][x]:
                img[y][x] = GLOW_HOT if (x - 32) ** 2 + (y - 26) ** 2 < 22 else GLOW
            elif socket_in[y][x]:
                img[y][x] = SOCKET
            else:
                img[y][x] = GLOW_DIM
    img[23][28] = GLOW_HOT
    img[22][28] = GLOW_HOT

    # --- jagged mouth: dark slit, interlocking teeth, carved lip
    mouth_x, mouth_y = range(23, 42), range(41, 49)
    for x in mouth_x:
        for y in mouth_y:
            if body[y][x]:
                img[y][x] = SOCKET
    for i, tx in enumerate(range(23, 42, 5)):
        for x in range(tx, tx + 3):
            top = 41 if i % 2 == 0 else 45
            for y in range(top, top + 4):
                if x in mouth_x and body[y][x]:
                    img[y][x] = TOOTH
    for x in range(22, 43):
        for y in (40, 49):
            if body[y][x]:
                img[y][x] = STONE_DEEP
    for y in range(40, 50):
        for x in (22, 42):
            if body[y][x]:
                img[y][x] = STONE_DEEP

    # --- carved cracks running down the stone
    for (sx, sy, ex, ey) in ((18, 38, 21, 52), (47, 21, 44, 36), (40, 51, 36, 57)):
        steps = max(abs(ex - sx), abs(ey - sy))
        for i in range(steps + 1):
            x = round(sx + (ex - sx) * i / steps)
            y = round(sy + (ey - sy) * i / steps)
            if body[y][x] and img[y][x] not in (SOCKET, TOOTH, GLOW, GLOW_HOT):
                img[y][x] = OUTLINE

    # --- rune dots glowing on the cheeks
    for (rx, ry) in ((16, 33), (48, 33), (18, 39), (46, 39)):
        img[ry][rx] = GLOW
        img[ry][rx - 1] = GLOW_DIM
        img[ry][rx + 1] = GLOW_DIM

    # --- dark outline last, so nothing paints over it
    for y in range(N):
        for x in range(N):
            if edge_of(solid)[y][x]:
                img[y][x] = OUTLINE

    return img


# ---------------------------------------------------------------------------
# Verilog emission: block-ROM arrays initialized in an `initial` block,
# synchronous 1-clock read (the template Vivado infers RAMB blocks from).
# ---------------------------------------------------------------------------
HEADER = """//------------------------------------------------------------------------------
// {name}  (GENERATED - do not edit by hand)
//
{desc}// Regenerate with: python3 scripts/gen_assets.py
//------------------------------------------------------------------------------
"""


def emit_rom(path, name, desc, addr_w, data_w, out_name, words):
    lines = [HEADER.format(name=os.path.basename(path), desc=desc)]
    lines.append(f"module {name} (")
    lines.append("    input  wire        clk,")
    lines.append(f"    input  wire [{addr_w-1}:0] addr,")
    lines.append(f"    output reg  [{data_w-1}:0] {out_name}")
    lines.append(");")
    lines.append("")
    lines.append('    (* rom_style = "block" *)')
    lines.append(f"    reg [{data_w-1}:0] mem [0:{len(words)-1}];")
    lines.append("")
    lines.append("    initial begin")
    hexw = (data_w + 3) // 4
    for i, w in enumerate(words):
        lines.append(f"        mem[{i}] = {data_w}'h{w:0{hexw}X};")
    lines.append("    end")
    lines.append("")
    lines.append("    always @(posedge clk)")
    lines.append(f"        {out_name} <= mem[addr];")
    lines.append("")
    lines.append("endmodule")
    with open(path, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"wrote {path} ({len(words)} words x {data_w} bits)")


def write_previews(outdir, soul, monster):
    from PIL import Image

    os.makedirs(outdir, exist_ok=True)

    def to_img(grid, scale, bg=(0, 0, 0)):
        h, w = len(grid), len(grid[0])
        im = Image.new("RGB", (w, h))
        px = im.load()
        for y in range(h):
            for x in range(w):
                c = grid[y][x]
                if c == TRANSPARENT:
                    px[x, y] = bg
                else:
                    r, g, b = (c >> 8) & 0xF, (c >> 4) & 0xF, c & 0xF
                    px[x, y] = (r * 17, g * 17, b * 17)
        return im.resize((w * scale, h * scale), Image.NEAREST)

    for frame, name in enumerate(("soul_whole", "soul_broken")):
        to_img(soul[frame], 16).save(os.path.join(outdir, f"{name}.png"))
    to_img(monster, 8).save(os.path.join(outdir, "monster.png"))
    print(f"wrote previews to {outdir}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", metavar="DIR", help="also write PNG previews")
    args = ap.parse_args()

    soul = [from_ascii(SOUL_WHOLE, SOUL_PALETTE, 16, 16),
            from_ascii(SOUL_BROKEN, SOUL_PALETTE, 16, 16)]
    monster = build_monster()

    # soul_rom: addr = {frame, y[3:0], x[3:0]}
    words = []
    for f in range(2):
        for y in range(16):
            words.extend(soul[f][y])
    emit_rom(
        os.path.join(HDL_DIR, "soul_rom.v"), "soul_rom",
        "// The player's soul sprite: 2 frames of 16x16 px, 12-bit RGB\n"
        "// (0 = whole heart, 1 = shattered heart on game over).\n"
        "// 12'hFFF (pure white) = transparent, per the course slides.\n"
        "// addr = {frame, y[3:0], x[3:0]}.\n",
        9, 12, "color", words)

    # monster_rom: addr = {y[5:0], x[5:0]}
    words = []
    for y in range(N):
        words.extend(monster[y])
    emit_rom(
        os.path.join(HDL_DIR, "monster_rom.v"), "monster_rom",
        "// The enemy sprite (ROOT SENTINEL, original art): 64x64 px, 12-bit\n"
        "// RGB, scaled 2x to 128x128 on screen by monster_renderer.\n"
        "// 12'hFFF (pure white) = transparent, per the course slides.\n"
        "// addr = {y[5:0], x[5:0]}.\n",
        12, 12, "color", words)

    if args.preview:
        write_previews(args.preview, soul, monster)


if __name__ == "__main__":
    main()
