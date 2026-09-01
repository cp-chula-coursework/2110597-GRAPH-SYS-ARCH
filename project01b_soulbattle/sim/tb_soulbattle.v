//------------------------------------------------------------------------------
// tb_soulbattle.v
//
// Whole-core simulation at real 640x480@60 timing: the render pipeline, the
// button debouncer, and the game logic together. Where tb_battle_logic.v
// proves the rules, this one proves the picture - it plays far enough into a
// battle to capture one frame of each screen and writes them out as PPM
// images for eyeballing:
//
//   soulbattle_title.ppm  attract screen  (box, soul, blinking prompt, HUD)
//   soulbattle_aim.ppm    your turn       (sweeping cursor + target marks)
//   soulbattle_hit.ppm    the strike      (damage read-out, enemy flashing)
//   soulbattle_dodge.ppm  enemy turn      (bullets in flight in the box)
//
// It also checks the video timing the HDMI encoder depends on: exactly
// 640x480 active pixels per frame, and 525 lines between vsyncs.
//
// The blaster wave is four enemy turns in, which at real frame timing is a
// couple of thousand frames away - too far to be worth simulating here, so
// sim/tb_blaster_draw.v dumps that layer's picture on its own instead. What
// this bench does check is that the blasters stay completely out of the way
// during the bullet waves.
//
//   iverilog -o /tmp/tb_sb.vvp hdl/vga_timing.v hdl/pad_input.v \
//     hdl/soul_rom.v hdl/monster_rom.v hdl/blaster_rom.v hdl/font_rom.v \
//     hdl/soul_renderer.v hdl/monster_renderer.v hdl/bullet_renderer.v \
//     hdl/blaster_renderer.v hdl/hud_renderer.v hdl/battle_logic.v \
//     hdl/blaster_logic.v hdl/battle_core.v sim/tb_soulbattle.v
//   vvp /tmp/tb_sb.vvp
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_soulbattle;

    localparam S_TITLE = 3'd0, S_AIM = 3'd1, S_HIT = 3'd2,
               S_DODGE = 3'd3, S_WIN = 3'd4, S_LOSE = 3'd5;

    reg        clk = 1'b0;
    reg  [3:0] key = 4'b1111;    // active-low, all released
    wire [7:0] vid_r, vid_g, vid_b;
    wire       vid_hs, vid_vs, vid_de;

    battle_core dut (
        .clk    (clk),
        .key    (key),
        .vid_r  (vid_r),
        .vid_g  (vid_g),
        .vid_b  (vid_b),
        .vid_hs (vid_hs),
        .vid_vs (vid_vs),
        .vid_de (vid_de)
    );

    always #19.861 clk = ~clk;   // ~25.175 MHz

    // read-only peeks into the DUT
    wire       frame_start = dut.frame_start;
    wire [2:0] state       = dut.state;
    wire [5:0] player_hp   = dut.player_hp;
    wire [5:0] enemy_hp    = dut.enemy_hp;
    wire [4:0] last_damage = dut.last_damage;
    wire [1:0] wave        = dut.wave;
    wire       blast_busy  = dut.blast_busy;

    integer errors = 0;
    integer frame_no = 0;

    task check(input cond, input [8*64-1:0] msg);
        if (!cond) begin
            errors = errors + 1;
            $display("FAIL (frame %0d, state %0d): %0s", frame_no, state, msg);
        end
    endtask

    task step_frames(input integer n);
        integer i;
        for (i = 0; i < n; i = i + 1) begin
            @(posedge frame_start);
            frame_no = frame_no + 1;
        end
    endtask

    // key[0] held long enough to clear the 5 ms debounce, then released long
    // enough for the game's once-per-frame edge detector to re-arm
    task press;
        begin
            key[0] = 1'b0;
            step_frames(2);
            key[0] = 1'b1;
            step_frames(2);
        end
    endtask

    // ---- video timing checks ----------------------------------------------
    integer de_count = 0;
    integer line_count = 0;
    reg     vs_d = 1'b1;
    reg     hs_d = 1'b1;

    always @(posedge clk) begin
        if (vid_de) de_count = de_count + 1;
        vs_d <= vid_vs;
        if (vs_d && !vid_vs) begin          // falling edge = start of vsync
            if (frame_no > 2) begin
                check(de_count == 640 * 480, "wrong number of active pixels in a frame");
                check(line_count == 525, "wrong number of lines in a frame");
            end
            de_count   = 0;
            line_count = 0;
        end
        if (vid_hs === 1'b1 && hs_d === 1'b0) line_count = line_count + 1;
        hs_d <= vid_hs;
    end

    // ---- PPM frame dump ----------------------------------------------------
    task dump_frame(input [8*40-1:0] fname);
        integer f, n;
        begin
            f = $fopen(fname, "wb");
            $fwrite(f, "P6\n640 480\n255\n");
            @(posedge frame_start);
            frame_no = frame_no + 1;
            n = 0;
            while (n < 640 * 480) begin
                @(posedge clk);
                if (vid_de) begin
                    $fwrite(f, "%c%c%c", vid_r, vid_g, vid_b);
                    n = n + 1;
                end
            end
            $fclose(f);
            $display("wrote %0s", fname);
        end
    endtask

    // ---- watchdog ---------------------------------------------------------
    initial begin
        #12_000_000_000;   // 12 s sim time ~ 720 frames
        $display("FAIL: watchdog timeout (frame %0d, state %0d)", frame_no, state);
        $finish;
    end

    integer guard;

    initial begin
        // ---- attract screen ------------------------------------------------
        step_frames(4);
        check(state == S_TITLE, "did not power up on the title screen");
        check(player_hp == 6'd20 && enemy_hp == 6'd40, "HP not initialised");
        // the prompt blinks on anim[5]: dump a frame where it is lit
        guard = 0;
        while (!dut.anim[5] && guard < 64) begin step_frames(1); guard = guard + 1; end
        dump_frame("soulbattle_title.ppm");

        // ---- your turn: the attack cursor sweeps ---------------------------
        press;
        check(state == S_AIM, "a button press did not start the battle");
        step_frames(12);            // let the cursor get away from the wall
        dump_frame("soulbattle_aim.ppm");

        // ---- strike: damage read-out + enemy flash -------------------------
        press;
        check(state == S_HIT, "the strike did not land");
        check(last_damage != 5'd0, "the strike scored no damage");
        check(enemy_hp < 6'd40, "the enemy took no damage");
        step_frames(6);
        dump_frame("soulbattle_hit.ppm");

        // ---- enemy turn: wait for the box to fill with bullets -------------
        guard = 0;
        while (state != S_DODGE && guard < 200) begin
            step_frames(1); guard = guard + 1;
        end
        check(state == S_DODGE, "never reached the enemy's turn");
        step_frames(70);
        check(dut.bullet_active != 8'd0, "the enemy turn spawned no bullets");
        check(wave == 2'd0, "the first enemy turn is not the falling-pillar wave");
        check(!blast_busy, "a blaster turned up during a bullet wave");
        dump_frame("soulbattle_dodge.ppm");

        if (errors == 0)
            $display("ALL TESTS PASSED (%0d frames simulated)", frame_no);
        else
            $display("%0d TEST(S) FAILED", errors);
        $finish;
    end

endmodule
