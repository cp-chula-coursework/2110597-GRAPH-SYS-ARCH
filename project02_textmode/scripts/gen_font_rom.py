#!/usr/bin/env python3
"""gen_font_rom.py

Generates hdl/font_rom.v (8x16 glyphs for 7-bit ASCII) from a Linux console
font in PSF1 format. Default source is the classic IBM VGA 8x16 font shipped
with Debian/Ubuntu's console-setup package:

    /usr/share/consolefonts/Lat15-VGA16.psf.gz

ROM layout follows the course slides (06_Text_Mode_Display.pdf, "ascii_rom"):
  - address: 11 bits = {char[6:0], row[3:0]}  (7-bit ASCII, 16 rows per char)
  - data:    8 bits  = one glyph row, MSB = leftmost pixel

Codes 0x00-0x1F and 0x7F (non-printable) render blank. Run from the project
root:  python3 scripts/gen_font_rom.py
"""

import gzip
import sys
from pathlib import Path

FONT_PATH = "/usr/share/consolefonts/Lat15-VGA16.psf.gz"

PSF1_MAGIC = b"\x36\x04"
PSF1_MODE512 = 0x01
PSF1_MODEHASTAB = 0x02
PSF1_SEPARATOR = 0xFFFF


def load_psf1(path):
    """Returns (glyphs, unicode_map). glyphs: list of 16-byte rows per glyph.
    unicode_map: {codepoint: glyph_index} (empty if font has no table)."""
    raw = gzip.open(path, "rb").read()
    if raw[:2] != PSF1_MAGIC:
        sys.exit(f"{path}: not a PSF1 font")
    mode, charsize = raw[2], raw[3]
    nglyph = 512 if (mode & PSF1_MODE512) else 256
    if charsize != 16:
        sys.exit(f"{path}: charsize {charsize}, want 16 (8x16 font)")
    glyphs = []
    off = 4
    for _ in range(nglyph):
        glyphs.append(raw[off:off + charsize])
        off += charsize
    unicode_map = {}
    if mode & PSF1_MODEHASTAB:
        # Table: per glyph, little-endian u16 codepoints, 0xFFFF-terminated
        idx = 0
        while off + 1 < len(raw) and idx < nglyph:
            cp = int.from_bytes(raw[off:off + 2], "little")
            off += 2
            if cp == PSF1_SEPARATOR:
                idx += 1
            elif cp not in unicode_map:
                unicode_map[cp] = idx
    return glyphs, unicode_map


def main():
    proj = Path(__file__).resolve().parent.parent
    out_path = proj / "hdl" / "font_rom.v"
    glyphs, unicode_map = load_psf1(FONT_PATH)

    lines = []
    lines.append("//" + "-" * 78)
    lines.append("// font_rom.v  (GENERATED - do not edit by hand)")
    lines.append("//")
    lines.append("// 8x16 character-generator ROM for 7-bit ASCII, glyph data extracted from")
    lines.append("// the classic IBM VGA 8x16 console font (Lat15-VGA16, Debian console-setup)")
    lines.append("// by scripts/gen_font_rom.py.")
    lines.append("//")
    lines.append("// Layout per the course slides (06_Text_Mode_Display.pdf, ascii_rom):")
    lines.append("//   addr[10:0] = {char[6:0], row[3:0]}   (7-bit ASCII code, 16 rows/char)")
    lines.append("//   data[7:0]  = one glyph row, data[7] = leftmost pixel")
    lines.append("//")
    lines.append("// Registered address + full case -> Vivado infers one RAMB18 block ROM;")
    lines.append("// read data is valid 1 clock after addr (same latency as the tile RAM).")
    lines.append("//" + "-" * 78)
    lines.append("module font_rom (")
    lines.append("    input  wire        clk,")
    lines.append("    input  wire [10:0] addr,")
    lines.append("    output reg  [7:0]  data")
    lines.append(");")
    lines.append("")
    lines.append('    (* rom_style = "block" *)')
    lines.append("")
    lines.append("    reg [10:0] addr_reg;")
    lines.append("")
    lines.append("    always @(posedge clk)")
    lines.append("        addr_reg <= addr;")
    lines.append("")
    lines.append("    always @* begin")
    lines.append("        case (addr_reg)")

    n_glyphs = 0
    for code in range(0x20, 0x7F):  # printable ASCII only; the rest stay blank
        gi = unicode_map.get(code, code if not unicode_map else None)
        if gi is None or gi >= len(glyphs):
            sys.exit(f"font has no glyph for U+{code:04X}")
        rows = glyphs[gi]
        ch = chr(code)
        label = f"'{ch}'" if ch != "'" else '"\'"'
        lines.append(f"            // 0x{code:02X} {label}")
        for row in range(16):
            b = rows[row]
            if b == 0:
                continue  # zero rows fall through to the default arm
            lines.append(
                f"            11'h{(code << 4) | row:03x}: data = 8'b{b:08b};"
            )
        n_glyphs += 1
    lines.append("            // control codes (0x00-0x1F), DEL (0x7F), and all")
    lines.append("            // blank glyph rows render as empty scanlines")
    lines.append("            default: data = 8'b00000000;")
    lines.append("        endcase")
    lines.append("    end")
    lines.append("")
    lines.append("endmodule")
    lines.append("")

    out_path.write_text("\n".join(lines))
    print(f"wrote {out_path} ({n_glyphs} glyphs)")


if __name__ == "__main__":
    main()
