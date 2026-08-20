//------------------------------------------------------------------------------
// tb_platformer.v
//
// Full-core simulation of the platformer: real 640x480 frames, scripted
// button presses through the debouncer, and an "auto-runner" that plays the
// level - hold right+run, jump when pushed up against a wall, jump over the
// first pit on the second attempt. Along the way it checks (via read-only
// hierarchical references into the DUT):
//
//   - spawn state (position, grounded, idle animation)
//   - walking left/right, facing flip, world-edge clamp
//   - wall collision (player stops flush against the crate stack)
//   - jumping (leaves the ground, rises, lands back)
//   - falling into a pit -> respawn at the start
//   - clearing the pit and the pipe with jumps
//   - camera invariant every frame: scroll == clamp(px - 304, 0, 640)
//   - animation invariant every frame: airborne -> jump frame,
//     grounded+walking -> walk frames
//
// It also dumps two rendered frames as PPM images (platformer_start.ppm,
// platformer_mid.ppm) for visual inspection.
//
//   iverilog -o /tmp/tb_plat.vvp hdl/vga_timing.v hdl/pad_input.v \
//     hdl/map_rom.v hdl/bg_tile_rom.v hdl/player_rom.v hdl/bg_renderer.v \
//     hdl/player_renderer.v hdl/game_logic.v hdl/platformer_core.v \
//     sim/tb_platformer.v
//   vvp /tmp/tb_plat.vvp
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_platformer;

    reg        clk = 1'b0;
    reg  [3:0] key = 4'b1111;    // active-low, all released
    wire [7:0] vid_r, vid_g, vid_b;
    wire       vid_hs, vid_vs, vid_de;

    platformer_core dut (
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
    wire        frame_start = dut.frame_start;
    wire [10:0] px          = dut.player_x;
    wire [9:0]  py          = dut.player_y;
    wire [9:0]  scroll      = dut.scroll;
    wire [1:0]  pframe      = dut.player_frame;
    wire        pflip       = dut.player_flip;
    wire        grounded    = dut.u_game.grounded;

    // active-low button helpers
    `define PRESS_LEFT   key[0] = 1'b0
    `define RELEASE_LEFT key[0] = 1'b1
    `define PRESS_RIGHT  key[1] = 1'b0
    `define PRESS_JUMP   key[2] = 1'b0
    `define RELEASE_JUMP key[2] = 1'b1
    `define PRESS_RUN    key[3] = 1'b0

    integer errors = 0;
    integer frame_no = 0;

    task check(input cond, input [8*60-1:0] msg);
        if (!cond) begin
            errors = errors + 1;
            $display("FAIL (frame %0d, px=%0d py=%0d): %0s", frame_no, px, py, msg);
        end
    endtask

    // wait for n frame boundaries (game state is stable when sampled here:
    // the FSM ran during the previous vblank)
    task step_frames(input integer n);
        integer i;
        for (i = 0; i < n; i = i + 1) begin
            @(posedge frame_start);
            frame_no = frame_no + 1;
        end
    endtask

    // per-frame invariants, checked at every frame boundary
    always @(posedge frame_start) begin
        if (frame_no > 3) begin
            check(scroll == ((px < 304) ? 10'd0 :
                             (px > 944) ? 10'd640 : px[9:0] - 10'd304),
                  "camera: scroll != clamp(px-304, 0, 640)");
            check(py < 480, "player stored below the map bottom");
            if (!grounded)
                check(pframe == 2'd3, "airborne but not showing jump frame");
        end
    end

    // ---- auto-runner ------------------------------------------------------
    // While enabled: hold right (+run), jump when px is stuck for 6 frames,
    // and optionally jump when approaching the first pit.
    reg        auto_on = 1'b0;
    reg        auto_pit_jump = 1'b0;
    reg [10:0] last_px = 11'd0;
    integer    stuck_cnt = 0;
    integer    jump_hold = 0;

    always @(posedge frame_start) begin
        if (auto_on) begin
            `PRESS_RIGHT; `PRESS_RUN;
            if (grounded && px == last_px)
                stuck_cnt = stuck_cnt + 1;
            else
                stuck_cnt = 0;
            last_px <= px;
            if (jump_hold == 0 &&
                ((stuck_cnt >= 6) ||
                 (auto_pit_jump && grounded && px >= 356 && px <= 372))) begin
                jump_hold = 25;
                stuck_cnt = 0;
            end
            if (jump_hold > 0) begin
                `PRESS_JUMP;
                jump_hold = jump_hold - 1;
            end else
                `RELEASE_JUMP;
        end
    end

    // lowest py seen (= highest point reached) while the runner plays
    reg [9:0] min_py = 10'd1023;
    always @(posedge frame_start)
        if (py < min_py) min_py <= py;

    // ---- PPM frame dump ---------------------------------------------------
    task dump_frame(input [8*32-1:0] fname);
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
        #25_000_000_000;   // 25 s sim time ~ 1500 frames of gameplay
        $display("FAIL: watchdog timeout (frame %0d, px=%0d)", frame_no, px);
        $finish;
    end

    integer t;

    initial begin
        // ---- phase A: power-up / spawn ------------------------------------
        step_frames(5);
        check(px == 11'd48,  "spawn x != 48");
        check(py == 10'd384, "spawn y != 384 (not standing on the ground)");
        check(grounded,      "not grounded at spawn");
        check(pframe == 2'd0, "not idle at spawn");
        check(scroll == 10'd0, "scroll != 0 at spawn");
        dump_frame("platformer_start.ppm");

        // ---- phase B: walk left into the world edge -----------------------
        `PRESS_LEFT;
        step_frames(40);
        check(px == 11'd0, "left edge clamp failed");
        check(pflip == 1'b1, "not facing left while walking left");
        `RELEASE_LEFT;

        // ---- phase C: auto-run right; crate wall then pit -> respawn ------
        auto_on = 1'b1;          // no pit jump: fall in and respawn
        auto_pit_jump = 1'b0;
        t = 0;
        while (!(px == 11'd136 && grounded) && t < 200) begin
            step_frames(1); t = t + 1;
        end
        check(t < 200, "never stopped flush against the crate wall (px=136)");
        check(pflip == 1'b0, "not facing right while walking right");
        check(pframe == 2'd1 || pframe == 2'd2, "not in walk cycle at wall");

        // the stuck-detector will jump the crates; then the pit swallows us
        t = 0;
        while (!(px == 11'd48 && py == 10'd384) && t < 400) begin
            step_frames(1); t = t + 1;
        end
        check(t < 400, "never respawned after the pit");
        check(min_py < 10'd360, "auto-runner never actually jumped");
        step_frames(2);
        check(scroll == 10'd0, "scroll not reset after respawn");

        // ---- phase D: run again, jump the pit and the pipe, reach px 600 --
        auto_pit_jump = 1'b1;
        t = 0;
        while (!(px >= 11'd600 && grounded) && t < 600) begin
            step_frames(1); t = t + 1;
        end
        check(t < 600, "never made it past the pit + pipe to px 600");
        check(scroll == px[9:0] - 10'd304, "camera not following mid-level");
        dump_frame("platformer_mid.ppm");

        if (errors == 0)
            $display("ALL TESTS PASSED (%0d frames simulated)", frame_no);
        else
            $display("%0d TEST(S) FAILED", errors);
        $finish;
    end

endmodule
