#!/usr/bin/env python3
"""gen_assets.py - generate the three graphics ROMs for project03_platformer.

The course slides (10_2D_Platformer_FPGA_Project.pdf) build their BG/sprite
ROMs from Super Mario sprite rips loaded with $readmemh. This project instead
ships original, hand-drawn-in-Python pixel art (no copyrighted game assets)
and bakes it into plain Verilog `initial` blocks, so the ROMs work identically
in Vivado synthesis and Icarus Verilog simulation with no .mem file path
headaches (same approach as project02's generated font_rom.v).

Generates (into hdl/, next to this script's parent):
  bg_tile_rom.v  - 32 tiles x 16x16 px x 12-bit RGB  (8192 x 12)
                   addr = {tile[4:0], y[3:0], x[3:0]}
                   tile index bit 4 doubles as the "solid" attribute:
                   0..15 decorative (sky, clouds, bushes...), 16..31 solid
  map_rom.v      - level map, 80 cols x 30 rows x 8-bit tile index
                   (2 screens wide for x scrolling), addr = row*80 + col
  player_rom.v   - player sprite, 4 frames x 32x32 px x 12-bit RGB
                   (idle, walk A, walk B, jump), 12'hFFF = transparent,
                   addr = {frame[1:0], y[4:0], x[4:0]}
                   Art is authored 16x16 and pixel-doubled to 32x32.

Usage:
  python3 scripts/gen_assets.py [--preview DIR]

--preview DIR additionally writes tileset.png / level.png / player.png
previews (requires Pillow) for eyeballing the art.
"""

import argparse
import os

HDL_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "hdl"))

SKY = 0x9CF          # flat sky color, also the entire tile 0
TRANSPARENT = 0xFFF  # per the slides: pure white = sprite transparency

# ---------------------------------------------------------------------------
# Tileset: 16x16 tiles, drawn as ASCII art or procedurally.
# Index bit 4 = solid, so decorative tiles are 0..15 and solid tiles 16..31.
# ---------------------------------------------------------------------------
T_SKY, T_CLOUD_L, T_CLOUD_M, T_CLOUD_R = 0, 1, 2, 3
T_BUSH_L, T_BUSH_M, T_BUSH_R, T_FLOWER, T_FENCE = 4, 5, 6, 7, 8
T_GRASS, T_DIRT, T_BRICK, T_CRATE, T_STONE = 16, 17, 18, 19, 20
T_METAL, T_PIPE_TL, T_PIPE_TR, T_PIPE_BL, T_PIPE_BR = 21, 22, 23, 24, 25

N_TILES = 32


def from_ascii(rows, palette):
    """16 strings of 16 chars -> 16x16 list of 12-bit colors."""
    assert len(rows) == 16 and all(len(r) == 16 for r in rows), rows
    return [[palette[c] for c in row] for row in rows]


def flat(color):
    return [[color] * 16 for _ in range(16)]


def hflip(tile):
    return [list(reversed(row)) for row in tile]


def cloud_tiles():
    # One 48x16 cloud drawn across three tiles.
    pal = {".": SKY, "w": 0xFFE, "s": 0xCDE}
    art = [
        "................................................",
        "................................................",
        "..................wwwww.........................",
        "...............wwwwwwwwww.......................",
        ".............wwwwwwwwwwwwww.....................",
        "........wwwwwwwwwwwwwwwwwwwww...................",
        "......wwwwwwwwwwwwwwwwwwwwwwwwwwww.............",
        ".....wwwwwwwwwwwwwwwwwwwwwwwwwwwwwww...........",
        "....wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww........",
        "...wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww.....",
        "..swwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwws....",
        "..sswwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwsss...",
        "...ssswwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwssss....",
        "....sssssssssssssssssssssssssssssssssssssss.....",
        "......ssssssssssssssssssssssssssssssssss........",
        "................................................",
    ]
    art = [r.ljust(48, ".")[:48] for r in art]
    tiles = []
    for t in range(3):
        tiles.append([[pal[art[y][t * 16 + x]] for x in range(16)] for y in range(16)])
    return tiles


def bush_tiles():
    # One 48x16 bush drawn across three tiles; sits on top of the ground row.
    pal = {".": SKY, "d": 0x274, "m": 0x3A5, "l": 0x5C6}
    art = [
        "................................................",
        "................................................",
        "................................................",
        "......................mmm.......................",
        ".....................mllmm......................",
        "............mmm.....mllmmmm.....mmm.............",
        "...........mllmm...mllmmmmmm...mllmm............",
        "..........mllmmmm.mllmmmmmmmm.mllmmmm...........",
        ".........mllmmmmmmllmmmmmmmmmmllmmmmmm..........",
        "........mllmmmmmmmlmmmmmmmmmmmmmmmmmmmm.........",
        ".......mllmmmmmmmmmmmmmmdmmmmmmmmmdmmmmm........",
        "......mllmmmmmdmmmmmmmmdmmmmmmmmmmmmdmmmm.......",
        ".....mlmmmmmmmmdmmmmmmmmmmmmdmmmmmmmmmmmmm......",
        "....mmmmmmdmmmmmmmmmdmmmmmmmmmmmdmmmmmmmmmm.....",
        "...mmmmmmmmmmmmmmmmmmmmmmdmmmmmmmmmmmdmmmmmm....",
        "..dddddddddddddddddddddddddddddddddddddddddddd..",
    ]
    art = [r.ljust(48, ".")[:48] for r in art]
    tiles = []
    for t in range(3):
        tiles.append([[pal[art[y][t * 16 + x]] for x in range(16)] for y in range(16)])
    return tiles


def flower_tile():
    pal = {".": SKY, "s": 0x3A5, "d": 0x274, "p": 0xF68, "c": 0xFD4}
    return from_ascii([
        "................",
        "......pp.pp.....",
        ".....pppppp.....",
        ".....ppccpp.....",
        ".....ppccpp.....",
        ".....pppppp.....",
        "......pp.pp.....",
        ".......ss.......",
        ".......ss.......",
        "...s...ss.......",
        "...ss..ss..s....",
        "....ss.ss.ss....",
        ".....ssssss.....",
        ".......ss.......",
        ".......ss.......",
        ".......ss.......",
    ], pal)


def fence_tile():
    pal = {".": SKY, "w": 0xA74, "d": 0x742}
    rows = []
    for y in range(16):
        row = []
        for x in range(16):
            plank = x % 5 in (1, 2)                    # vertical planks
            rail = y in (3, 4, 10, 11)                 # two horizontal rails
            if plank and y >= 1:
                row.append(0x742 if (y == 1 or x % 5 == 2) else 0xA74)
            elif rail:
                row.append(0x742 if y in (4, 11) else 0xA74)
            else:
                row.append(SKY)
        rows.append(row)
    return rows


def grass_tile():
    # Grass cap on dirt (the walkable ground surface).
    pal = {"l": 0x7D5, "g": 0x4B3, "G": 0x395, "d": 0x965, "k": 0x743}
    return from_ascii([
        "lglgglgllgglglgl",
        "gglgglgglgglggll",
        "gggggggggggggggg",
        "GgGggGgGggGgGggG",
        "GGGGGGGGGGGGGGGG",
        "dGdddGddGdddGddd",
        "dddddddddddddddd",
        "ddddkddddddkdddd",
        "dddddddddddddddd",
        "dkddddddkddddddk",
        "dddddddddddddddd",
        "dddddkddddddkddd",
        "ddkddddddddddddd",
        "dddddddddkdddddd",
        "dddddddddddddddd",
        "ddddkddddddddkdd",
    ], pal)


def dirt_tile():
    pal = {"d": 0x965, "k": 0x743, "l": 0xA76}
    return from_ascii([
        "dddddddddddddddd",
        "ddkddddddlddddkd",
        "dddddddddddddddd",
        "ddddddkddddddddd",
        "dlddddddddddkddd",
        "dddddddddddddddd",
        "ddddkddddlddddddd"[:16],
        "dddddddddddddddd",
        "dkddddddkddddddl",
        "dddddddddddddddd",
        "dddddlddddddkddd",
        "dddddddddddddddd",
        "ddkddddddddlddddd"[:16],
        "dddddddkdddddddd",
        "dlddddddddddddkd",
        "dddddddddddddddd",
    ], pal)


def brick_tile():
    base, dark, mortar = 0xB53, 0x831, 0xDA8
    rows = []
    for y in range(16):
        row = []
        course = y // 4                                # 4-px brick courses
        for x in range(16):
            if y % 4 == 3:
                row.append(mortar)                     # horizontal mortar line
            else:
                joint = (x + (4 if course % 2 else 0)) % 8 == 7
                row.append(mortar if joint else (dark if y % 4 == 0 else base))
        rows.append(row)
    return rows


def crate_tile():
    wood, dark, light = 0xB84, 0x852, 0xDA6
    rows = []
    for y in range(16):
        row = []
        for x in range(16):
            if x in (0, 15) or y in (0, 15):
                row.append(dark)                       # frame
            elif x in (1, 14) or y in (1, 14):
                row.append(light if (x == 1 or y == 1) else dark)
            elif x == y or x == 15 - y:
                row.append(dark)                       # diagonal braces
            else:
                row.append(wood if (y % 3) else light)
        rows.append(row)
    return rows


def stone_tile():
    base, dark, light = 0x99A, 0x667, 0xBBC
    rows = []
    for y in range(16):
        row = []
        for x in range(16):
            if x == 0 or y == 0:
                row.append(light)                      # top/left highlight
            elif x == 15 or y == 15:
                row.append(dark)                       # bottom/right shadow
            elif (x * 7 + y * 13) % 23 == 0:
                row.append(dark)                       # speckle
            else:
                row.append(base)
        rows.append(row)
    return rows


def metal_tile():
    base, dark, light = 0xAAB, 0x778, 0xDDE
    rows = []
    for y in range(16):
        row = []
        for x in range(16):
            if x == 0 or y == 0:
                row.append(light)
            elif x == 15 or y == 15:
                row.append(dark)
            elif (x in (3, 12) and y in (3, 12)):
                row.append(dark)                       # corner rivets
            elif (x in (2, 11) and y in (2, 11)):
                row.append(light)
            else:
                row.append(base)
        rows.append(row)
    return rows


def pipe_tiles():
    # 32px-wide pipe: [top-left, top-right] with a lip, [body-left, body-right].
    g, dk, hi = 0x2A4, 0x172, 0x8E9
    def col_shade(x):                                  # cylinder shading, x 0..31
        if x in (0, 31):
            return dk
        if 3 <= x <= 7:
            return hi
        if x >= 26:
            return dk
        return g
    top, body = [], []
    for y in range(16):
        trow, brow = [], []
        for x in range(32):
            # top tile: 10-px tall lip over the body, lip is 32px wide
            if y < 2 or y == 9:
                trow.append(dk)
            elif y < 9:
                trow.append(hi if 2 <= x <= 6 else (dk if x in (0, 1, 30, 31) else g))
            else:
                trow.append(SKY if (x < 2 or x > 29) else col_shade_body(x))
            brow.append(SKY if (x < 2 or x > 29) else col_shade_body(x))
        top.append(trow)
        body.append(brow)
    def split(t32):
        return ([r[:16] for r in t32], [r[16:] for r in t32])
    return split(top) + split(body)


def col_shade_body(x):
    g, dk, hi = 0x2A4, 0x172, 0x8E9
    if x in (2, 29):
        return dk
    if 5 <= x <= 9:
        return hi
    if x >= 25:
        return dk
    return g


def build_tileset():
    tiles = {i: flat(0x000) for i in range(N_TILES)}   # undefined -> black
    tiles[T_SKY] = flat(SKY)
    tiles[T_CLOUD_L], tiles[T_CLOUD_M], tiles[T_CLOUD_R] = cloud_tiles()
    tiles[T_BUSH_L], tiles[T_BUSH_M], tiles[T_BUSH_R] = bush_tiles()
    tiles[T_FLOWER] = flower_tile()
    tiles[T_FENCE] = fence_tile()
    tiles[T_GRASS] = grass_tile()
    tiles[T_DIRT] = dirt_tile()
    tiles[T_BRICK] = brick_tile()
    tiles[T_CRATE] = crate_tile()
    tiles[T_STONE] = stone_tile()
    tiles[T_METAL] = metal_tile()
    (tiles[T_PIPE_TL], tiles[T_PIPE_TR],
     tiles[T_PIPE_BL], tiles[T_PIPE_BR]) = pipe_tiles()
    return tiles


# ---------------------------------------------------------------------------
# Level map: 80x30 tiles (2 screens wide), ground surface at row 26.
# ---------------------------------------------------------------------------
def build_map():
    W, H, GROUND = 80, 30, 26
    m = [[T_SKY] * W for _ in range(H)]

    def put(col, row, tile):
        m[row][col] = tile

    def ground(c0, c1):
        for c in range(c0, c1 + 1):
            m[GROUND][c] = T_GRASS
            for r in range(GROUND + 1, H):
                m[r][c] = T_DIRT

    # ground with two 3-tile pits
    ground(0, 23)
    ground(27, 54)
    ground(58, 79)

    # clouds (3 tiles wide each)
    for c, r in ((6, 4), (18, 6), (31, 3), (45, 5), (58, 4), (70, 6)):
        put(c, r, T_CLOUD_L); put(c + 1, r, T_CLOUD_M); put(c + 2, r, T_CLOUD_R)

    # bushes + flowers + fence on the ground surface
    for c in (4, 40, 66):
        put(c, GROUND - 1, T_BUSH_L)
        put(c + 1, GROUND - 1, T_BUSH_M)
        put(c + 2, GROUND - 1, T_BUSH_R)
    for c in (13, 44, 59):
        put(c, GROUND - 1, T_FLOWER)
    for c in (35, 36, 37):
        put(c, GROUND - 1, T_FENCE)

    # crate cluster near the start
    put(10, GROUND - 1, T_CRATE); put(11, GROUND - 1, T_CRATE)
    put(10, GROUND - 2, T_CRATE)

    # floating platforms (3 tiles above ground = jumpable)
    for c in range(17, 22):
        put(c, 23, T_BRICK)
    for c in range(21, 25):
        put(c, 19, T_BRICK)                            # reachable from the first
    put(22, 19, T_METAL)                               # accent block
    for c in range(34, 39):
        put(c, 22, T_BRICK)
    put(36, 22, T_METAL)

    # pipes (2 and 3 tiles tall)
    put(30, 24, T_PIPE_TL); put(31, 24, T_PIPE_TR)
    put(30, 25, T_PIPE_BL); put(31, 25, T_PIPE_BR)
    put(50, 23, T_PIPE_TL); put(51, 23, T_PIPE_TR)
    for r in (24, 25):
        put(50, r, T_PIPE_BL); put(51, r, T_PIPE_BR)

    # stone staircase
    for i, c in enumerate((60, 61, 62, 63)):
        for r in range(GROUND - 1 - i, GROUND):
            put(c, r, T_STONE)

    # goal: metal pillar at the far right
    for r in range(19, GROUND):
        put(76, r, T_METAL)

    return m


# ---------------------------------------------------------------------------
# Player sprite: 4 frames authored 16x16 (facing right), doubled to 32x32.
# '.' = transparent (12'hFFF). An original little "scout robot" - no
# copyrighted game character art.
# ---------------------------------------------------------------------------
PLAYER_PAL = {
    ".": TRANSPARENT,
    "o": 0x178,   # dark teal outline
    "b": 0x2AC,   # teal body
    "l": 0x6DE,   # light teal highlight
    "v": 0x134,   # visor
    "s": 0x8EF,   # visor shine
    "a": 0xF83,   # orange accents / backpack
    "k": 0x345,   # dark gray boots/joints
    "r": 0xF44,   # antenna bulb
}

PLAYER_FRAMES = {
    # frame 0: idle
    0: [
        ".......r........",
        ".......o........",
        "....ooooooo.....",
        "...obbblbbbo....",
        "...obvvvvvbo....",
        "...obvsvvvbo....",
        "...obbbbbbbo....",
        "....ooooooo.....",
        "..aobbbbbbboa...",
        "..aobbaaabboa...",
        "...obbbbbbbo....",
        "....obbbbbo.....",
        "....okokoko.....",
        "....okk.okk.....",
        "....okk.okk.....",
        "....kkk.kkk.....",
    ],
    # frame 1: walk A (legs apart)
    1: [
        ".......r........",
        ".......o........",
        "....ooooooo.....",
        "...obbblbbbo....",
        "...obvvvvvbo....",
        "...obvsvvvbo....",
        "...obbbbbbbo....",
        "....ooooooo.....",
        "..aobbbbbbboa...",
        "..aobbaaabboa...",
        "...obbbbbbbo....",
        "....obbbbbo.....",
        "....okokoko.....",
        "...okk...okk....",
        "..okk.....okk...",
        "..kkk.....kkk...",
    ],
    # frame 2: walk B (legs crossed under)
    2: [
        ".......r........",
        ".......o........",
        "....ooooooo.....",
        "...obbblbbbo....",
        "...obvvvvvbo....",
        "...obvsvvvbo....",
        "...obbbbbbbo....",
        "....ooooooo.....",
        "..aobbbbbbboa...",
        "..aobbaaabboa...",
        "...obbbbbbbo....",
        "....obbbbbo.....",
        "....okokoko.....",
        ".....okok.......",
        ".....okok.......",
        ".....kkkk.......",
    ],
    # frame 3: jump (legs tucked, arms up)
    3: [
        ".......r........",
        ".......o........",
        "....ooooooo.....",
        "...obbblbbbo....",
        "...obvvvvvbo....",
        "...obvsvvvbo....",
        "..aobbbbbbboa...",
        "..aoooooooooa...",
        "...obbbbbbbo....",
        "...obbaaabbo....",
        "...obbbbbbbo....",
        "....obbbbbo.....",
        "....okokoko.....",
        "....okk.okk.....",
        "....kk...kk.....",
        "................",
    ],
}


def build_player():
    frames = []
    for f in range(4):
        art = from_ascii(PLAYER_FRAMES[f], PLAYER_PAL)
        big = [[art[y // 2][x // 2] for x in range(32)] for y in range(32)]
        frames.append(big)
    return frames


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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", metavar="DIR", help="also write PNG previews")
    args = ap.parse_args()

    tiles = build_tileset()
    level = build_map()
    player = build_player()

    # bg_tile_rom: addr = {tile[4:0], y[3:0], x[3:0]}
    words = []
    for t in range(N_TILES):
        for y in range(16):
            words.extend(tiles[t][y])
    emit_rom(
        os.path.join(HDL_DIR, "bg_tile_rom.v"), "bg_tile_rom",
        "// 32 background tiles, 16x16 px, 12-bit RGB (the slides' \"BG ROM\").\n"
        "// addr = {tile[4:0], y[3:0], x[3:0]}. Tile index bit 4 = solid\n"
        "// attribute (0..15 decorative, 16..31 solid), used by the collision\n"
        "// logic. Tile 0 is the flat sky color.\n",
        13, 12, "color", words)

    # map_rom: addr = row*80 + col
    words = [level[r][c] for r in range(30) for c in range(80)]
    emit_rom(
        os.path.join(HDL_DIR, "map_rom.v"), "map_rom",
        "// Level map (the slides' \"Map ROM\"): 80 cols x 30 rows of 8-bit\n"
        "// tile indices - 2 screens wide for x-axis scrolling.\n"
        "// addr = row*80 + col. Instantiated twice: once by the background\n"
        "// renderer, once by the game logic as its collision ROM.\n",
        12, 8, "tile", words)

    # player_rom: addr = {frame[1:0], y[4:0], x[4:0]}
    words = []
    for f in range(4):
        for y in range(32):
            words.extend(player[f][y])
    emit_rom(
        os.path.join(HDL_DIR, "player_rom.v"), "player_rom",
        "// Player sprite (the slides' \"Mario ROM\", original art): 4 frames\n"
        "// of 32x32 px, 12-bit RGB. Frames: 0 idle, 1-2 walk cycle, 3 jump.\n"
        "// 12'hFFF (pure white) = transparent, per the slides.\n"
        "// addr = {frame[1:0], y[4:0], x[4:0]}.\n",
        12, 12, "color", words)

    if args.preview:
        write_previews(args.preview, tiles, level, player)


def write_previews(outdir, tiles, level, player):
    from PIL import Image

    os.makedirs(outdir, exist_ok=True)

    def px(c):
        return ((c >> 8) * 17, ((c >> 4) & 0xF) * 17, (c & 0xF) * 17)

    sheet = Image.new("RGB", (8 * 16, 4 * 16))
    for t in range(N_TILES):
        ox, oy = (t % 8) * 16, (t // 8) * 16
        for y in range(16):
            for x in range(16):
                sheet.putpixel((ox + x, oy + y), px(tiles[t][y][x]))
    sheet.resize((sheet.width * 4, sheet.height * 4), Image.NEAREST).save(
        os.path.join(outdir, "tileset.png"))

    lvl = Image.new("RGB", (80 * 16, 30 * 16))
    for r in range(30):
        for c in range(80):
            t = tiles[level[r][c]]
            for y in range(16):
                for x in range(16):
                    lvl.putpixel((c * 16 + x, r * 16 + y), px(t[y][x]))
    lvl.save(os.path.join(outdir, "level.png"))

    pl = Image.new("RGB", (4 * 32, 32))
    for f in range(4):
        for y in range(32):
            for x in range(32):
                c = player[f][y][x]
                pl.putpixel((f * 32 + x, y),
                            px(SKY) if c == TRANSPARENT else px(c))
    pl.resize((pl.width * 4, pl.height * 4), Image.NEAREST).save(
        os.path.join(outdir, "player.png"))
    print(f"previews written to {outdir}")


if __name__ == "__main__":
    main()
