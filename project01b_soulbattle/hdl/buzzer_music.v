//------------------------------------------------------------------------------
// buzzer_music.v
//
// The board's music: a one-voice square-wave player for a passive buzzer,
// walking the score in song_rom.v. Same idea as the video side of this
// project - no CPU and no software, just a counter chain.
//
//   song_rom --> sequencer --> divider --> square wave --> buzzer pin
//   (what to    (how long     (how fast
//    play)       to hold it)   to toggle)
//
// Three counters, nested:
//
//   tick_cnt   counts one sixteenth-note      TICK clocks
//   left       counts the sixteenths left in the note being held
//   tone_cnt   counts one half-period of the pitch, then flips the output
//
// A *passive* buzzer has no oscillator of its own - it is a small speaker,
// and it makes the pitch it is fed. That is what makes a tune possible here:
// an active buzzer would only ever sound its own one note.
//
// Pitch table. Rather than store one divider per note, the octave-5
// frequencies are stored to the nearest whole hertz and everything else is
// derived by shifting: dropping an octave is exactly doubling the period, so
// a shift is not an approximation, and rounding 523.25 Hz to 523 is a 1.6
// cent error - about a hundredth of a semitone, which nobody can hear. One
// twelve-entry table covers the whole range.
//
// Notes are re-articulated by cutting the tone GAP clocks before the end of
// the note. Without it the riff's two repeated notes (`D D`, `C C`, ...) run
// together into one long note and the rhythm goes.
//
// `enable` low silences the buzzer and rewinds to the top of the score, so
// the riff starts from its first bar every time a battle begins.
//
// Volume. The buzzer comes out on *two* pins in antiphase rather than one
// pin against ground: while `buzzer` is high `buzzer_n` is low and the other
// way about, so the element sees the supply swing in both directions - 6.6 V
// peak-to-peak instead of 3.3 - which is about 6 dB for the cost of one wire
// moved off the ground pin. Wiring it the old way, one pin to ground, still
// works and is simply the quieter half of this.
//
// Both pins are driven low together when nothing is sounding. That matters:
// leaving one of them high would put a steady DC voltage across the element,
// which is silent but heats a magnetic buzzer's coil for no reason.
//
// `OCTAVE_UP` shifts the whole tune up by that many octaves. It exists for
// piezo elements, which are resonant: a disc that is feeble at 150 Hz can be
// twenty-odd decibels louder near its own resonance up around 2-4 kHz. It
// costs the bass of the riff, so it is 0 by default - turn it up only if a
// piezo is still too quiet with everything else done.
//
// Bring-up. A buzzer that makes no sound is either not being driven or not
// being driven hard enough, and a tune is a terrible signal to tell those
// apart with - it is quiet, it keeps changing pitch, and it stops for rests.
// `test` replaces it with something unambiguous:
//
//   0  play the score, normally
//   1  a flat 2.4 kHz square, forever - the resonance of the usual 12 mm
//      magnetic buzzer, i.e. the loudest noise this pin can make into one
//   2  a flat 4 kHz square, forever - the same idea for a piezo disc
//   3  `buzzer` held high and `buzzer_n` low, DC, no tone at all
//
// Modes 1 and 2 sound whether or not `enable` is asserted, so a muted or
// finished game still tests. Mode 3 is the one to put a multimeter on: it
// should read the full supply across the two pins, which proves the pins,
// the constraints and the wiring in one measurement without any timing in
// the way. It also identifies an *active* buzzer, which is the one part
// that can never play a tune - an active buzzer beeps on DC, a passive one
// clicks once and goes quiet. Do not leave mode 3 on: it is a steady current
// through a magnetic buzzer's coil, which only heats it.
//------------------------------------------------------------------------------
module buzzer_music #(
    parameter integer CLK_HZ    = 25_175_000, // pixel clock: the only clock here
    parameter integer BPM       = 120,        // MEGALOVANIA's tempo
    parameter integer OCTAVE_UP = 0           // transpose, for piezo resonance
)(
    input  wire clk,
    input  wire enable,      // 0 = silence + rewind
    input  wire [1:0] test,  // bring-up: 0 play, 1 2.4 kHz, 2 4 kHz, 3 DC
    output wire buzzer,      // drive the buzzer between these two pins;
    output wire buzzer_n     // one pin against ground also works, 6 dB quieter
);

    // clocks in one sixteenth-note: CLK_HZ * (60 / BPM) / 4, arranged so the
    // multiply happens first and nothing is lost to integer division
    localparam integer TICK   = (CLK_HZ * 15) / BPM;
    localparam integer TICK_W = $clog2(TICK);

    // 20 ms of silence at the end of every note, so two of the same pitch in
    // a row are heard as two notes
    localparam integer GAP = CLK_HZ / 50;

    // the two bring-up tones, at the resonances the two kinds of element are
    // built around - a buzzer that will make any noise at all makes its most
    // here, which is what a bring-up signal wants to be
    localparam integer TEST_MAGNETIC = CLK_HZ / (2 * 2400);
    localparam integer TEST_PIEZO    = CLK_HZ / (2 * 4000);

    // half-period, in clocks, of each semitone of octave 5
    function [21:0] half_period(input [6:0] n);
        integer base;
        begin
            case (n[3:0])
            4'd0:  base = CLK_HZ / (2 * 523);   // C5
            4'd1:  base = CLK_HZ / (2 * 554);   // C#5
            4'd2:  base = CLK_HZ / (2 * 587);   // D5
            4'd3:  base = CLK_HZ / (2 * 622);   // D#5
            4'd4:  base = CLK_HZ / (2 * 659);   // E5
            4'd5:  base = CLK_HZ / (2 * 698);   // F5
            4'd6:  base = CLK_HZ / (2 * 740);   // F#5
            4'd7:  base = CLK_HZ / (2 * 784);   // G5
            4'd8:  base = CLK_HZ / (2 * 831);   // G#5
            4'd9:  base = CLK_HZ / (2 * 880);   // A5
            4'd10: base = CLK_HZ / (2 * 932);   // A#5
            default: base = CLK_HZ / (2 * 988); // B5
            endcase
            // one octave down = twice the period; the score never goes above
            // octave 5, so the left shift is never negative, and OCTAVE_UP
            // takes the whole tune back up again afterwards
            half_period = (base << (3'd5 - n[6:4])) >> OCTAVE_UP;
        end
    endfunction

    // ---- the score ---------------------------------------------------------
    wire [6:0] note;
    wire [4:0] dur;
    wire       last;
    reg  [6:0] addr = 7'd0;

    song_rom u_score (
        .addr (addr),
        .note (note),
        .dur  (dur),
        .last (last)
    );

    // ---- sequencer: hold each note for its own number of sixteenths --------
    reg [TICK_W-1:0] tick_cnt = 0;
    reg [4:0]        left     = 5'd0;   // sixteenths still to hold
    reg [21:0]       div      = 22'd1;  // half-period of the note being held

    always @(posedge clk) begin
        div <= half_period(note);

        if (!enable) begin
            addr     <= 7'd0;
            left     <= 5'd0;
            tick_cnt <= 0;
        end else if (left == 5'd0) begin
            // one clock to pick up the entry `addr` is now pointing at
            left     <= dur;
            tick_cnt <= 0;
        end else if (tick_cnt == TICK - 1) begin
            tick_cnt <= 0;
            if (left == 5'd1) begin
                addr <= last ? 7'd0 : addr + 7'd1;
                left <= 5'd0;
            end else begin
                left <= left - 5'd1;
            end
        end else begin
            tick_cnt <= tick_cnt + 1'b1;
        end
    end

    // silence over the tail of the note, and over rests
    wire in_gap = (left == 5'd1) && (tick_cnt >= TICK - GAP);
    wire sound  = enable && (left != 5'd0) && (note != 7'h00) && !in_gap;

    // ---- bring-up override -------------------------------------------------
    // The sequencer carries on running underneath all of this; only what
    // reaches the pins changes, so leaving a test mode picks the tune back up
    // rather than restarting it.
    wire test_dc = (test == 2'd3);

    wire [21:0] div_eff = (test == 2'd1) ? TEST_MAGNETIC[21:0] :
                          (test == 2'd2) ? TEST_PIEZO[21:0]    : div;

    wire sound_eff = (test != 2'd0) ? ~test_dc : sound;

    // ---- tone: flip the two pins every half-period --------------------------
    // `tone_n` takes the value `tone_p` is leaving, which makes it the exact
    // inverse with no gap and no overlap - and both fall to 0 together when
    // the sound stops, so the element is never left with DC across it.
    reg [21:0] tone_cnt = 22'd0;
    reg        tone_p   = 1'b0;
    reg        tone_n   = 1'b0;

    always @(posedge clk) begin
        if (!sound_eff) begin
            tone_cnt <= 22'd0;
            tone_p   <= 1'b0;
            tone_n   <= 1'b0;
        end else if (tone_cnt >= div_eff - 22'd1) begin
            tone_cnt <= 22'd0;
            tone_p   <= ~tone_p;
            tone_n   <=  tone_p;
        end else begin
            tone_cnt <= tone_cnt + 1'b1;
        end
    end

    assign buzzer   = test_dc ? 1'b1 : tone_p;
    assign buzzer_n = test_dc ? 1'b0 : tone_n;

endmodule
