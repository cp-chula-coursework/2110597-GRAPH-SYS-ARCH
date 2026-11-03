//------------------------------------------------------------------------------
// song_rom.v  (GENERATED - do not edit by hand)
//
// MEGALOVANIA's opening riff (Toby Fox, UNDERTALE), as a list of notes for
// buzzer_music.v to walk: four bars of the bass figure, then the same four
// an octave up, where the lead comes in in the original. `last` marks the
// final entry so the player knows where to loop back to.
//
// Each entry is a pitch and a length in sixteenth-notes. A pitch is
// {octave[2:0], semitone[3:0]} with semitone 0 = C, 1 = C#, ... 11 = B;
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
    output wire [6:0]  note,    // {octave, semitone}, 7'h00 = rest
    output wire [4:0]  dur,     // length in sixteenth-notes
    output wire        last     // 1 on the final entry: loop after this one
);

    localparam integer LAST_ADDR = 79;

    // 80 notes is small enough that Vivado will leave this in LUTs rather
    // than spend a block RAM on it - which is what we want, the block RAMs
    // are all carrying sprites.
    reg [11:0] mem [0:LAST_ADDR];

    initial begin
        mem[  0] = {7'h32, 5'd1};   // D3
        mem[  1] = {7'h32, 5'd1};   // D3
        mem[  2] = {7'h42, 5'd2};   // D4
        mem[  3] = {7'h39, 5'd3};   // A3
        mem[  4] = {7'h38, 5'd2};   // G#3
        mem[  5] = {7'h37, 5'd2};   // G3
        mem[  6] = {7'h35, 5'd2};   // F3
        mem[  7] = {7'h32, 5'd1};   // D3
        mem[  8] = {7'h35, 5'd1};   // F3
        mem[  9] = {7'h37, 5'd1};   // G3

        mem[ 10] = {7'h30, 5'd1};   // C3
        mem[ 11] = {7'h30, 5'd1};   // C3
        mem[ 12] = {7'h42, 5'd2};   // D4
        mem[ 13] = {7'h39, 5'd3};   // A3
        mem[ 14] = {7'h38, 5'd2};   // G#3
        mem[ 15] = {7'h37, 5'd2};   // G3
        mem[ 16] = {7'h35, 5'd2};   // F3
        mem[ 17] = {7'h32, 5'd1};   // D3
        mem[ 18] = {7'h35, 5'd1};   // F3
        mem[ 19] = {7'h37, 5'd1};   // G3

        mem[ 20] = {7'h2B, 5'd1};   // B2
        mem[ 21] = {7'h2B, 5'd1};   // B2
        mem[ 22] = {7'h42, 5'd2};   // D4
        mem[ 23] = {7'h39, 5'd3};   // A3
        mem[ 24] = {7'h38, 5'd2};   // G#3
        mem[ 25] = {7'h37, 5'd2};   // G3
        mem[ 26] = {7'h35, 5'd2};   // F3
        mem[ 27] = {7'h32, 5'd1};   // D3
        mem[ 28] = {7'h35, 5'd1};   // F3
        mem[ 29] = {7'h37, 5'd1};   // G3

        mem[ 30] = {7'h2A, 5'd1};   // A#2
        mem[ 31] = {7'h2A, 5'd1};   // A#2
        mem[ 32] = {7'h42, 5'd2};   // D4
        mem[ 33] = {7'h39, 5'd3};   // A3
        mem[ 34] = {7'h38, 5'd2};   // G#3
        mem[ 35] = {7'h37, 5'd2};   // G3
        mem[ 36] = {7'h35, 5'd2};   // F3
        mem[ 37] = {7'h32, 5'd1};   // D3
        mem[ 38] = {7'h35, 5'd1};   // F3
        mem[ 39] = {7'h37, 5'd1};   // G3

        mem[ 40] = {7'h42, 5'd1};   // D4
        mem[ 41] = {7'h42, 5'd1};   // D4
        mem[ 42] = {7'h52, 5'd2};   // D5
        mem[ 43] = {7'h49, 5'd3};   // A4
        mem[ 44] = {7'h48, 5'd2};   // G#4
        mem[ 45] = {7'h47, 5'd2};   // G4
        mem[ 46] = {7'h45, 5'd2};   // F4
        mem[ 47] = {7'h42, 5'd1};   // D4
        mem[ 48] = {7'h45, 5'd1};   // F4
        mem[ 49] = {7'h47, 5'd1};   // G4

        mem[ 50] = {7'h40, 5'd1};   // C4
        mem[ 51] = {7'h40, 5'd1};   // C4
        mem[ 52] = {7'h52, 5'd2};   // D5
        mem[ 53] = {7'h49, 5'd3};   // A4
        mem[ 54] = {7'h48, 5'd2};   // G#4
        mem[ 55] = {7'h47, 5'd2};   // G4
        mem[ 56] = {7'h45, 5'd2};   // F4
        mem[ 57] = {7'h42, 5'd1};   // D4
        mem[ 58] = {7'h45, 5'd1};   // F4
        mem[ 59] = {7'h47, 5'd1};   // G4

        mem[ 60] = {7'h3B, 5'd1};   // B3
        mem[ 61] = {7'h3B, 5'd1};   // B3
        mem[ 62] = {7'h52, 5'd2};   // D5
        mem[ 63] = {7'h49, 5'd3};   // A4
        mem[ 64] = {7'h48, 5'd2};   // G#4
        mem[ 65] = {7'h47, 5'd2};   // G4
        mem[ 66] = {7'h45, 5'd2};   // F4
        mem[ 67] = {7'h42, 5'd1};   // D4
        mem[ 68] = {7'h45, 5'd1};   // F4
        mem[ 69] = {7'h47, 5'd1};   // G4

        mem[ 70] = {7'h3A, 5'd1};   // A#3
        mem[ 71] = {7'h3A, 5'd1};   // A#3
        mem[ 72] = {7'h52, 5'd2};   // D5
        mem[ 73] = {7'h49, 5'd3};   // A4
        mem[ 74] = {7'h48, 5'd2};   // G#4
        mem[ 75] = {7'h47, 5'd2};   // G4
        mem[ 76] = {7'h45, 5'd2};   // F4
        mem[ 77] = {7'h42, 5'd1};   // D4
        mem[ 78] = {7'h45, 5'd1};   // F4
        mem[ 79] = {7'h47, 5'd1};   // G4
    end

    wire [11:0] entry = mem[addr];

    assign note = entry[11:5];
    assign dur  = entry[4:0];
    assign last = (addr == LAST_ADDR);

endmodule
