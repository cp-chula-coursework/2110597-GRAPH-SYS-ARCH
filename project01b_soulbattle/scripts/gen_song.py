#!/usr/bin/env python3
"""Generate hdl/song_rom.v - the score the buzzer plays.

The score is MEGALOVANIA's opening riff (Toby Fox, UNDERTALE): four bars of
the bass figure, then the same four bars an octave up, which is where the
lead comes in in the original. It loops from there.

Each bar is sixteen sixteenth-notes long:

    root root  D   A    G#   G    F    D  F  G       <- pitches
     1    1    2   3    2    2    2    1  1  1       <- sixteenths (= 16)

Only the first two notes change from bar to bar - the root walks down
D, C, B, Bb - which is what makes the riff sound like it is descending while
the top of it stays put.

A note is stored as {octave[2:0], semitone[3:0]}; 0 means a rest (nothing in
the score reaches octave 0, so the code is free). Durations are in
sixteenth-notes, which is what buzzer_music.v counts.

Usage:
    python3 scripts/gen_song.py                  writes hdl/song_rom.v
    python3 scripts/gen_song.py --wav out.wav    + a square-wave preview of
                                                 exactly what the buzzer will
                                                 play, to hear before spending
                                                 a synthesis run on it
"""

import math
import os
import struct
import sys
import wave

# semitone numbers within an octave, the usual chromatic order
SEMI = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6,
        "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def note(name):
    """'G#3' -> the 7-bit {octave, semitone} code. 'r' -> rest."""
    if name == "r":
        return 0, "rest"
    pitch, octave = name[:-1], int(name[-1])
    assert 2 <= octave <= 5, f"{name}: only octaves 2..5 are in the table"

    return (octave << 4) | SEMI[pitch], name


def bar(root, octave):
    """One bar of the riff, rooted on `root`, with the upper line in `octave`.

    The roots walk down D, C, B, Bb. Octave numbers roll over at C rather
    than at A, so once the walk passes below C it is in the octave below the
    rest of the bar: under D3 and C3 come B2 and Bb2, not B3 and Bb3. Getting
    that wrong sends bars 3 and 4 up a seventh instead of down a tone, which
    is audibly not the riff.
    """
    o = octave
    ro = o - 1 if root in ("B", "A#") else o
    return [
        (f"{root}{ro}",  1),
        (f"{root}{ro}",  1),
        (f"D{o + 1}",    2),
        (f"A{o}",        3),
        (f"G#{o}",       2),
        (f"G{o}",        2),
        (f"F{o}",        2),
        (f"D{o}",        1),
        (f"F{o}",        1),
        (f"G{o}",        1),
    ]


# The riff walks D -> C -> B -> Bb under a fixed upper line. Bars 1-4 sit in
# the bass (D3 C3 B2 Bb2); bars 5-8 are the same thing an octave up.
SCORE = []
for octave in (3, 4):
    for root in ("D", "C", "B", "A#"):
        SCORE += bar(root, octave)

for i in range(0, len(SCORE), 10):
    assert sum(d for _, d in SCORE[i:i + 10]) == 16, "a bar is not 16/16 long"


# What the hardware runs at, so the preview is the same tune and not a
# prettier one: buzzer_music.v counts the pixel clock at MEGALOVANIA's tempo,
# cuts each note 20 ms early so repeated notes re-articulate, and rounds every
# octave-5 frequency to a whole hertz before shifting down to the real octave.
CLK_HZ = 25_175_000
BPM = 120
SIXTEENTH = 15.0 / BPM          # seconds
GAP = 0.020                     # seconds of silence at the end of a note
F5 = [523, 554, 587, 622, 659, 698, 740, 784, 831, 880, 932, 988]


def write_wav(path, rate=44100):
    """Render the score the way the hardware will make it: a square wave at
    the frequency the divider actually produces, not at the ideal pitch."""
    frames = bytearray()
    for name, dur in SCORE:
        code, _ = note(name)
        octave, semi = code >> 4, code & 15
        length = dur * SIXTEENTH
        half = (CLK_HZ // (2 * F5[semi])) << (5 - octave)   # clocks, as in RTL
        freq = CLK_HZ / (2.0 * half)
        for i in range(int(length * rate)):
            t = i / float(rate)
            on = t < length - GAP and math.sin(2 * math.pi * freq * t) >= 0
            frames += struct.pack("<h", 12000 if on else -12000 if
                                  t < length - GAP else 0)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(frames))
    secs = len(frames) / 2.0 / rate
    print(f"wrote {path}: {secs:.1f} s, one loop of the riff")


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "..", "hdl", "song_rom.v")

    lines = []
    for i, (name, dur) in enumerate(SCORE):
        code, label = note(name)
        lines.append(f"        mem[{i:3d}] = {{7'h{code:02X}, 5'd{dur}}};"
                     f"   // {label}")
        if i % 10 == 9:
            lines.append("")
    body = "\n".join(lines).rstrip()

    with open(out, "w") as f:
        f.write(HEADER.format(last=len(SCORE) - 1, n=len(SCORE), body=body))
    print(f"wrote {out}: {len(SCORE)} notes, {len(SCORE) // 10} bars")

    if "--wav" in sys.argv:
        write_wav(sys.argv[sys.argv.index("--wav") + 1])


HEADER = '''//------------------------------------------------------------------------------
// song_rom.v  (GENERATED - do not edit by hand)
//
// MEGALOVANIA's opening riff (Toby Fox, UNDERTALE), as a list of notes for
// buzzer_music.v to walk: four bars of the bass figure, then the same four
// an octave up, where the lead comes in in the original. `last` marks the
// final entry so the player knows where to loop back to.
//
// Each entry is a pitch and a length in sixteenth-notes. A pitch is
// {{octave[2:0], semitone[3:0]}} with semitone 0 = C, 1 = C#, ... 11 = B;
// 7'h00 is a rest. Every bar adds up to sixteen sixteenths:
//
//     root root  D   A    G#   G    F    D  F  G
//      1    1    2   3    2    2    2    1  1  1
//
// Only the first two notes move from bar to bar - the root walks down
// D, C, B, Bb while the top of the figure stays put.
//
// Regenerate with: python3 scripts/gen_song.py
//------------------------------------------------------------------------------

module song_rom (
    input  wire [6:0]  addr,
    output wire [6:0]  note,    // {{octave, semitone}}, 7'h00 = rest
    output wire [4:0]  dur,     // length in sixteenth-notes
    output wire        last     // 1 on the final entry: loop after this one
);

    localparam integer LAST_ADDR = {last};

    // {n} notes is small enough that Vivado will leave this in LUTs rather
    // than spend a block RAM on it - which is what we want, the block RAMs
    // are all carrying sprites.
    reg [11:0] mem [0:LAST_ADDR];

    initial begin
{body}
    end

    wire [11:0] entry = mem[addr];

    assign note = entry[11:5];
    assign dur  = entry[4:0];
    assign last = (addr == LAST_ADDR);

endmodule
'''


if __name__ == "__main__":
    main()
