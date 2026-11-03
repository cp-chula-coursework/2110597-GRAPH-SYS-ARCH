//------------------------------------------------------------------------------
// tb_music.v
//
// Checks the buzzer music against what the score says it should be:
//
//   1. every bar of song_rom.v adds up to sixteen sixteenth-notes, and its
//      roots walk down D, C, B, Bb with the second half an octave above the
//      first
//   2. the pitches that come out are the pitches that went in, measured off
//      the buzzer pin rather than read out of the ROM
//   3. the first note lands on D3 and the fifth bar on D4 - i.e. the octave
//      shift in the second half of the riff really is an octave
//   4. the two output pins are a true antiphase pair while a note sounds, and
//      both rest low when nothing does - a pin left high would sit DC across
//      the buzzer
//   5. `enable` low silences the pins and rewinds to the top of the score
//   6. the bring-up modes put out the flat tones and the DC they promise,
//      whether or not `enable` is asserted
//
// The player is instantiated at CLK_HZ = 251_750, a hundredth of the real
// pixel clock, so a whole 16-second loop of the song is a few million
// simulation clocks instead of a few hundred million. Every ratio in the
// design is preserved by that, so measuring a pitch and multiplying by 100
// gives the pitch the hardware will make.
//
//   iverilog -o /tmp/sim.vvp hdl/song_rom.v hdl/buzzer_music.v sim/tb_music.v
//   vvp /tmp/sim.vvp
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_music;

    localparam integer CLK_HZ = 251_750;    // 1/100 of the pixel clock
    localparam integer BPM    = 120;
    localparam integer TICK   = (CLK_HZ * 15) / BPM;   // clocks per sixteenth

    reg clk = 1'b0;
    reg enable = 1'b0;
    reg [1:0] test = 2'd0;
    wire buzzer, buzzer_n;

    always #1 clk = ~clk;      // one clock = 2 ns of simulation time

    buzzer_music #(.CLK_HZ (CLK_HZ), .BPM (BPM)) dut (
        .clk      (clk),
        .enable   (enable),
        .test     (test),
        .buzzer   (buzzer),
        .buzzer_n (buzzer_n)
    );

    // The pair is what makes the buzzer twice as loud as one pin against
    // ground, so it is worth watching continuously rather than sampling: the
    // two must never be high together (as far as the element is concerned
    // that is no drive at all), and once a note is under way they must be
    // exact opposites.
    //
    // Both low is the legitimate resting state - between notes, while muted,
    // and for the first half-period of every note, before the first flip has
    // happened. That last one is deliberate rather than a wart: the pins have
    // to rest somewhere between notes, and the only resting state that does
    // not sit a DC voltage across the buzzer is both of them low. So the
    // antiphase check only starts once the note has flipped at least once.
    integer both_high = 0;
    integer not_opposite = 0;
    reg     flipped = 1'b0;

    always @(posedge clk) begin
        if (buzzer === 1'b1 && buzzer_n === 1'b1)
            both_high = both_high + 1;
        if (dut.sound_eff && flipped && (buzzer === buzzer_n))
            not_opposite = not_opposite + 1;

        if (!dut.sound_eff)             flipped <= 1'b0;
        else if (buzzer | buzzer_n)     flipped <= 1'b1;
    end

    integer errors = 0;

    task check(input cond, input [8*48-1:0] what);
        begin
            if (!cond) begin
                $display("  FAIL: %0s", what);
                errors = errors + 1;
            end
        end
    endtask

    // ---- 1. the score itself -----------------------------------------------
    // Sweep the ROM's address and add the durations up bar by bar. A bar that
    // does not come to sixteen means the riff will drift out of time against
    // itself once it loops.
    reg  [6:0] rom_addr = 7'd0;
    wire [6:0] rom_note;
    wire [4:0] rom_dur;
    wire       rom_last;

    song_rom u_rom (
        .addr (rom_addr),
        .note (rom_note),
        .dur  (rom_dur),
        .last (rom_last)
    );

    integer i, bar_len, bars, total;

    task check_score;
        begin
            bar_len = 0;
            bars    = 0;
            total   = 0;
            for (i = 0; i < 128; i = i + 1) begin
                rom_addr = i[6:0];
                #1;
                bar_len = bar_len + rom_dur;
                total   = total + rom_dur;
                if ((i % 10) == 9) begin
                    check(bar_len == 16, "a bar is not 16 sixteenths long");
                    bars    = bars + 1;
                    bar_len = 0;
                end
                if (rom_last) i = 128;      // stop at the end of the score
            end
            $display("  score: %0d bars, %0d sixteenths total", bars, total);
            check(bars == 8, "expected 8 bars in the score");
            rom_addr = 7'd0;
            #1;
        end
    endtask

    // The four roots of a half of the riff walk *down* - D, C, B, Bb - and
    // the second half is the first half exactly one octave up. Both are easy
    // to get wrong by a whole octave when writing the score out, because
    // octave numbers roll over at C: below C3 comes B2, not B3. A root that
    // has gone the wrong way sounds nothing like the riff, so it is worth
    // checking rather than trusting. The {octave, semitone} code compares as
    // a pitch directly - a semitone never reaches 16, so a higher code is
    // always a higher note.
    reg [6:0] root [0:7];

    task check_roots;
        begin
            for (i = 0; i < 8; i = i + 1) begin
                rom_addr = i[6:0] * 7'd10;    // first note of each bar
                #1;
                root[i] = rom_note;
            end
            for (i = 1; i < 4; i = i + 1) begin
                check(root[i] < root[i-1], "the low roots do not walk down");
                check(root[i+4] < root[i+3], "the high roots do not walk down");
            end
            for (i = 0; i < 4; i = i + 1)
                check(root[i+4] == root[i] + 7'h10,
                      "bars 5-8 are not bars 1-4 one octave up");
            $display("  roots: %h %h %h %h / %h %h %h %h",
                     root[0], root[1], root[2], root[3],
                     root[4], root[5], root[6], root[7]);
            rom_addr = 7'd0;
            #1;
        end
    endtask

    // ---- 2/3. the pitches actually on the pin ------------------------------
    // A note is measured by timing one full cycle of the square wave in the
    // middle of it: two consecutive rising edges. Doing it mid-note rather
    // than at the start keeps the measurement clear of the staccato gap and
    // of the clock the sequencer spends loading the next entry.
    time t0, t_start, target;

    // half-period the design should be producing for octave `o`, semitone `s`
    function integer expect_half(input integer o, input integer s);
        integer f5;
        begin
            case (s)
            0: f5 = 523; 1: f5 = 554; 2:  f5 = 587; 3:  f5 = 622;
            4: f5 = 659; 5: f5 = 698; 6:  f5 = 740; 7:  f5 = 784;
            8: f5 = 831; 9: f5 = 880; 10: f5 = 932; default: f5 = 988;
            endcase
            expect_half = (CLK_HZ / (2 * f5)) * (1 << (5 - o));
        end
    endfunction

    // Wait until the song is `at_tick` sixteenth-notes plus half a
    // sixteenth old - i.e. the middle of the note that starts on that tick,
    // clear of the staccato gap at the end of the note before it - then time
    // one full cycle of the square wave. Everything is measured from
    // `t_start`, when the player was enabled, so a measurement never depends
    // on where the one before it happened to finish.
    task measure(input integer at_tick, output integer got);
        begin
            target = t_start + 2 * (at_tick * TICK + TICK / 2);
            if ($time < target) #(target - $time);
            @(posedge buzzer);
            t0 = $time;
            @(posedge buzzer);
            got = ($time - t0) / 4;    // one clock = 2 ns, and this is a full
        end                            // cycle = two half-periods
    endtask

    integer d3, d4_up, a3, t_lo, t_hi;

    initial begin
        $display("tb_music: the buzzer plays MEGALOVANIA's riff");

        // ---- the score -----------------------------------------------------
        check_score;
        check_roots;

        // ---- silence while disabled ----------------------------------------
        enable = 1'b0;
        #2000;
        check(buzzer === 1'b0, "buzzer is not silent while disabled");
        check(buzzer_n === 1'b0, "buzzer_n is not silent while disabled");
        check(dut.addr === 7'd0, "score did not rewind while disabled");

        // ---- start it ------------------------------------------------------
        @(posedge clk);
        enable  = 1'b1;
        t_start = $time;

        // note 0 is D3: one sixteenth long, so measure a quarter of the way in
        measure(0, d3);
        $display("  note 0  D3  half-period %0d clocks (expected %0d)",
                 d3, expect_half(3, 2));
        check(d3 == expect_half(3, 2), "note 0 is not D3");

        // note 3 is A3 and starts four sixteenths in (1+1+2)
        measure(4, a3);
        $display("  note 3  A3  half-period %0d clocks (expected %0d)",
                 a3, expect_half(3, 9));
        check(a3 == expect_half(3, 9), "note 3 is not A3");

        // Bar 5 starts 64 sixteenths in and is the riff an octave up, so its
        // first note is D4 - exactly half the period of the D3 that opened
        // the song.
        measure(64, d4_up);
        $display("  bar 5   D4  half-period %0d clocks (expected %0d)",
                 d4_up, expect_half(4, 2));
        check(d4_up == expect_half(4, 2), "bar 5 does not open on D4");
        check(d4_up * 2 == d3, "the second half of the riff is not an octave up");

        // ---- muting it -----------------------------------------------------
        enable = 1'b0;
        #4000;
        check(buzzer === 1'b0, "buzzer is not silent after being disabled");
        check(buzzer_n === 1'b0, "buzzer_n left DC across the buzzer");
        check(dut.addr === 7'd0, "score did not rewind after being disabled");

        // ---- the bring-up modes --------------------------------------------
        // These exist for a board that makes no sound at all, so what matters
        // is that they run regardless of `enable` - a muted or finished game
        // still has to be testable.
        test = 2'd1;
        t_start = $time;
        measure(0, t_lo);
        $display("  test 1      half-period %0d clocks (expected %0d)",
                 t_lo, CLK_HZ / (2 * 2400));
        check(t_lo == CLK_HZ / (2 * 2400),
              "test mode 1 is not a flat 2.4 kHz");

        test = 2'd2;
        t_start = $time;
        measure(0, t_hi);
        $display("  test 2      half-period %0d clocks (expected %0d)",
                 t_hi, CLK_HZ / (2 * 4000));
        check(t_hi == CLK_HZ / (2 * 4000), "test mode 2 is not a flat 4 kHz");

        // mode 3 is DC: the pins must split and stay split, so a meter across
        // them reads the whole supply rather than an average of a square wave
        test = 2'd3;
        #4000;
        check(buzzer === 1'b1 && buzzer_n === 1'b0,
              "test mode 3 does not hold the pins apart");
        #20000;
        check(buzzer === 1'b1 && buzzer_n === 1'b0,
              "test mode 3 did not stay put");

        // and leaving a test mode goes back to the tune, still muted
        test = 2'd0;
        #4000;
        check(buzzer === 1'b0 && buzzer_n === 1'b0,
              "leaving test mode did not fall silent again");

        // ---- the antiphase pair, over everything played above --------------
        $display("  pair: %0d clocks both high, %0d clocks not opposite",
                 both_high, not_opposite);
        check(both_high == 0, "the two pins were high together");
        check(not_opposite == 0, "the two pins are not an antiphase pair");

        if (errors == 0) $display("tb_music: PASS");
        else             $display("tb_music: FAIL (%0d)", errors);
        $finish;
    end

endmodule
