//------------------------------------------------------------------------------
// tb_blaster.v
//
// Blaster-wave simulation. blaster_logic is driven directly here - synthetic
// frame pulses, a soul position this bench moves by hand - so the aiming
// geometry can be checked exactly instead of being played into.
//
// What it proves:
//   - nothing spawns while the wave is not running, and everything on screen
//     is dropped the moment it stops
//   - every live blaster's muzzle sits on the rim of the battle box
//   - the muzzle is *solved*, not guessed: with the soul standing still, the
//     ray from the muzzle along the blaster's own heading passes exactly
//     through the soul's centre, for all eight headings
//   - the muzzle is never closer to the soul than MIN_LEAD, so every beam is
//     dodgeable
//   - the phases run IDLE -> TRACK -> CHARGE -> FIRE -> FADE -> IDLE with the
//     right widths: no beam while tracking, a 3 px warning line while
//     charging, a wide beam only while firing
//   - a soul that stands still is hit; a soul that steps aside after the
//     muzzle locks is not
//   - all eight headings actually come up
//
//   iverilog -o /tmp/tb_blaster.vvp hdl/blaster_logic.v sim/tb_blaster.v
//   vvp /tmp/tb_blaster.vvp
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_blaster;

    // geometry, mirroring the defaults battle_core instantiates with
    localparam EDGE_L = 190, EDGE_T = 250, EDGE_R = 449, EDGE_B = 409;
    localparam INNER_L = 194, INNER_T = 254, INNER_R = 445, INNER_B = 405;
    localparam MIN_LEAD = 40;

    localparam D_S = 0, D_SE = 1, D_E = 2, D_NE = 3,
               D_N = 4, D_NW = 5, D_W = 6, D_SW = 7;

    localparam P_IDLE = 0, P_TRACK = 1, P_CHARGE = 2, P_FIRE = 3, P_FADE = 4;

    reg clk = 1'b0;
    reg run = 1'b0, spawn_en = 1'b0;
    reg [9:0] soul_x = 10'd312, soul_y = 10'd322;   // centre of the box
    reg [2:0] round_cnt = 3'd3;

    // synthetic frame tick: one pulse every 20 clocks
    reg [7:0] fcnt = 8'd0;
    reg       fs   = 1'b0;
    always @(posedge clk) begin
        fcnt <= (fcnt == 8'd19) ? 8'd0 : fcnt + 8'd1;
        fs   <= (fcnt == 8'd18);
    end

    wire [19:0] bl_mx, bl_my, bl_reach;
    wire [5:0]  bl_dir, bl_kick;
    wire [9:0]  bl_hw;
    wire [3:0]  bl_dim;
    wire [1:0]  bl_hot, bl_head;
    wire        blast_hit, blast_busy;

    blaster_logic dut (
        .clk         (clk),
        .frame_start (fs),
        .run         (run),
        .spawn_en    (spawn_en),
        .soul_x      (soul_x),
        .soul_y      (soul_y),
        .round_cnt   (round_cnt),
        .bl_mx       (bl_mx),
        .bl_my       (bl_my),
        .bl_dir      (bl_dir),
        .bl_hw       (bl_hw),
        .bl_reach    (bl_reach),
        .bl_kick     (bl_kick),
        .bl_dim      (bl_dim),
        .bl_hot      (bl_hot),
        .bl_head     (bl_head),
        .blast_hit   (blast_hit),
        .blast_busy  (blast_busy)
    );

    always #19.861 clk = ~clk;   // ~25.175 MHz

    integer errors = 0;
    integer frame_no = 0;

    task check(input cond, input [8*72-1:0] msg);
        if (!cond) begin
            errors = errors + 1;
            $display("FAIL (frame %0d): %0s", frame_no, msg);
        end
    endtask

    task next_frame;
        begin
            @(posedge clk);
            while (fs !== 1'b1) @(posedge clk);
            #1;
            frame_no = frame_no + 1;
        end
    endtask

    task step_frames(input integer n);
        integer i;
        for (i = 0; i < n; i = i + 1) next_frame;
    endtask

    // ---- per-frame invariants ---------------------------------------------
    wire [9:0] cx = soul_x + 10'd8;
    wire [9:0] cy = soul_y + 10'd8;

    integer   s;
    reg [2:0] ph, dr;
    reg [9:0] mx, my;
    reg [4:0] hw;
    reg       on_rim, aimed;
    integer   lead, adx, ady;
    reg [7:0] seen_dir = 8'd0;      // which headings have come up
    reg       aim_stable = 1'b1;    // the soul has not moved lately

    always @(posedge clk) if (fs) begin
        #1;
        for (s = 0; s < 2; s = s + 1) begin
            ph = (s == 0) ? dut.st[0] : dut.st[1];
            dr = (s == 0) ? dut.dr[0] : dut.dr[1];
            mx = (s == 0) ? dut.mx[0] : dut.mx[1];
            my = (s == 0) ? dut.my[0] : dut.my[1];
            hw = bl_hw[5*s +: 5];

            if (ph != P_IDLE) begin
                seen_dir[dr] = 1'b1;

                // the muzzle is a point on the rim of the box
                on_rim = ((mx == EDGE_L) || (mx == EDGE_R) ||
                          (my == EDGE_T) || (my == EDGE_B)) &&
                         (mx >= EDGE_L) && (mx <= EDGE_R) &&
                         (my >= EDGE_T) && (my <= EDGE_B);
                check(on_rim, "a blaster muzzle is not on the rim of the box");

                // ... and the ray from it passes through the soul
                adx = (cx > mx) ? (cx - mx) : (mx - cx);
                ady = (cy > my) ? (cy - my) : (my - cy);
                case (dr)
                D_S:  aimed = (mx == cx) && (my == EDGE_T) && (cy > my);
                D_N:  aimed = (mx == cx) && (my == EDGE_B) && (cy < my);
                D_E:  aimed = (my == cy) && (mx == EDGE_L) && (cx > mx);
                D_W:  aimed = (my == cy) && (mx == EDGE_R) && (cx < mx);
                D_SE: aimed = (adx == ady) && (cx > mx) && (cy > my);
                D_SW: aimed = (adx == ady) && (cx < mx) && (cy > my);
                D_NE: aimed = (adx == ady) && (cx > mx) && (cy < my);
                default: aimed = (adx == ady) && (cx < mx) && (cy < my);
                endcase
                lead = (adx > ady) ? adx : ady;

                // only meaningful while the muzzle is still tracking a soul
                // that has not moved under it
                if (aim_stable && ph == P_TRACK) begin
                    check(aimed, "a tracking blaster is not aimed at the soul");
                    check(lead >= MIN_LEAD, "a blaster spawned inside MIN_LEAD");
                end

                // widths follow the phase
                if (ph == P_TRACK)  check(hw == 5'd0, "a tracking blaster is already drawing a beam");
                if (ph == P_CHARGE) check(hw == 5'd1, "the warning line is not 3 px wide");
                if (ph == P_FADE)   check(hw == 5'd0, "a faded blaster is still drawing a beam");
                if (ph == P_FIRE)   check(hw >= 5'd1, "a firing blaster has no beam");
            end else begin
                check(bl_head[s] == 1'b0, "an idle slot is still drawing a head");
                check(hw == 5'd0, "an idle slot is still drawing a beam");
            end
        end

        // the soul can only be hit by a beam that is actually firing
        if (blast_hit)
            check((dut.st[0] == P_FIRE) || (dut.st[1] == P_FIRE),
                  "blast_hit with no blaster firing");
        if (!run)
            check(!blast_busy && !blast_hit, "a blaster survived the wave ending");
    end

    // ---- watchdog ---------------------------------------------------------
    initial begin
        #2_000_000_000;
        $display("FAIL: watchdog timeout (frame %0d)", frame_no);
        $finish;
    end

    integer guard;
    integer hit_frames;
    reg [9:0] lock_x, lock_y;

    initial begin
        // ---- nothing runs while the wave is off ----------------------------
        step_frames(40);
        check(!blast_busy, "a blaster appeared with the wave switched off");
        check(bl_head == 2'b00, "a head is on screen with the wave switched off");

        // spawn_en alone must not be enough
        spawn_en = 1'b1;
        step_frames(40);
        check(!blast_busy, "spawn_en started a blaster without run");
        spawn_en = 1'b0;

        // ---- the wave runs: blasters appear, aim, warn, then fire ----------
        run = 1'b1; spawn_en = 1'b1;
        guard = 0;
        while (!blast_busy && guard < 60) begin next_frame; guard = guard + 1; end
        check(blast_busy, "the wave started but no blaster appeared");
        check(dut.st[0] == P_TRACK, "the first blaster did not start by tracking");

        // walk slot 0 through its phases and time the warning
        guard = 0;
        while (dut.st[0] != P_CHARGE && guard < 60) begin next_frame; guard = guard + 1; end
        check(dut.st[0] == P_CHARGE, "a blaster never locked on");
        lock_x = dut.mx[0];
        lock_y = dut.my[0];

        guard = 0;
        while (dut.st[0] == P_CHARGE && guard < 60) begin
            check(dut.mx[0] == lock_x && dut.my[0] == lock_y,
                  "the muzzle moved after locking on");
            next_frame; guard = guard + 1;
        end
        check(guard >= 12, "the warning line was shorter than 12 frames");
        check(dut.st[0] == P_FIRE, "a locked blaster did not fire");

        // the beam grows out of the muzzle rather than appearing whole
        check(dut.rch[0] < 10'd200, "the beam reached the far side on frame one");

        // ---- a soul that stands still gets hit -----------------------------
        hit_frames = 0;
        guard = 0;
        while (guard < 40) begin
            if (blast_hit) hit_frames = hit_frames + 1;
            next_frame; guard = guard + 1;
        end
        check(hit_frames > 0, "a stationary soul was never hit by a beam");

        // ---- ... and a soul that steps aside is not ------------------------
        // wait for the next lock, then walk out of the beam before it fires
        guard = 0;
        while (dut.st[0] != P_CHARGE && guard < 200) begin next_frame; guard = guard + 1; end
        check(dut.st[0] == P_CHARGE, "no second blaster locked on");

        aim_stable = 1'b0;                  // the soul is about to move
        if (dut.dr[0] == D_S || dut.dr[0] == D_N) begin
            soul_x = 10'd230;               // sidestep a vertical beam
        end else if (dut.dr[0] == D_E || dut.dr[0] == D_W) begin
            soul_y = 10'd270;               // sidestep a horizontal beam
        end else begin
            soul_x = 10'd230; soul_y = 10'd380;
        end

        guard = 0;
        while (dut.st[0] != P_FIRE && guard < 60) begin next_frame; guard = guard + 1; end
        hit_frames = 0;
        guard = 0;
        while (dut.st[0] == P_FIRE && guard < 40) begin
            // slot 1 may be firing at the soul's new position - only slot 0's
            // beam is the one that was dodged
            if (blast_hit && dut.st[1] != P_FIRE) hit_frames = hit_frames + 1;
            next_frame; guard = guard + 1;
        end
        check(hit_frames == 0, "a dodged beam still hit the soul");

        // ---- all eight headings turn up ------------------------------------
        soul_x = 10'd312; soul_y = 10'd322;
        aim_stable = 1'b1;
        round_cnt = 3'd7;                    // fastest cadence, shortest test
        step_frames(2500);
        check(seen_dir == 8'hFF, "some of the eight headings never came up");
        $display("  headings seen: %b", seen_dir);

        // ---- ending the wave clears the screen -----------------------------
        run = 1'b0; spawn_en = 1'b0;
        step_frames(4);
        check(!blast_busy, "a blaster outlived the wave");
        check(bl_head == 2'b00 && bl_hw == 10'd0, "something is still drawn");

        if (errors == 0)
            $display("ALL TESTS PASSED (%0d frames simulated)", frame_no);
        else
            $display("%0d TEST(S) FAILED", errors);
        $finish;
    end

endmodule
