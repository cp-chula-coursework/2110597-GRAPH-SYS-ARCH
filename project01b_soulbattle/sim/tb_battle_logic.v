//------------------------------------------------------------------------------
// tb_battle_logic.v
//
// Game-logic simulation. battle_logic only advances on frame_start, so this
// bench drives synthetic frame pulses every 20 clocks instead of real 640x480
// frames - thousands of game frames run in seconds, which is what makes a
// full "play the battle to a win, then play it to a death" test practical.
// (tb_soulbattle.v covers the real timing and the picture.)
//
// Plays the battle twice through the actual button interface:
//
//   win  run - strike on the bullseye every turn (16 damage), dodge the
//              enemy's turns with the simple avoidance policy below, and
//              check the battle ends in WIN. At 120 enemy HP that is eight
//              strikes and seven enemy turns, which no amount of standing
//              still survives - so this run is also the check that the
//              battle is winnable at all.
//   lose run - strike at the far edge every turn (3 damage) so the enemy
//              outlasts the player, and check the battle ends in LOSE with
//              the soul at 0 HP
//
// blaster_logic is wired up here exactly as battle_core wires it, so the
// blaster wave is tested where it actually matters - as part of the turn
// order. (tb_blaster.v covers its aiming geometry on its own.)
//
// Checked along the way, every frame:
//   - the soul never leaves the inside of the battle box
//   - HP never exceeds its maximum and never goes negative
//   - a bullet costs exactly 2 HP and a blaster beam exactly 3, and neither
//     can repeat within the 60-frame mercy window (i-frames)
//   - every live bullet stays inside the spawn/despawn window
//   - the attack cursor stays inside the box, and a bullseye press really
//     does score 16 while an edge press scores 3
//   - the four-way movement clamps against all four walls
//   - the blaster wave fires no bullets at all, hits a soul that stands
//     still, and does not hand the turn back while a blaster is on screen
//
//   iverilog -o /tmp/tb_logic.vvp hdl/battle_logic.v hdl/blaster_logic.v \
//     sim/tb_battle_logic.v
//   vvp /tmp/tb_logic.vvp
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_battle_logic;

    localparam S_TITLE = 3'd0, S_AIM = 3'd1, S_HIT = 3'd2,
               S_DODGE = 3'd3, S_WIN = 3'd4, S_LOSE = 3'd5;

    // box geometry, mirroring the defaults battle_core instantiates with
    localparam INNER_L = 194, INNER_T = 254, INNER_R = 445, INNER_B = 405;
    localparam SOUL_MIN_X = 195, SOUL_MAX_X = 429;
    localparam SOUL_MIN_Y = 255, SOUL_MAX_Y = 389;
    localparam CENTER_X = 320;

    reg clk = 1'b0;
    reg pad_up = 1'b0, pad_dn = 1'b0, pad_lf = 1'b0, pad_rt = 1'b0;

    // synthetic frame tick: one pulse every 20 clocks
    reg [7:0] fcnt = 8'd0;
    reg       fs   = 1'b0;
    always @(posedge clk) begin
        fcnt <= (fcnt == 8'd19) ? 8'd0 : fcnt + 8'd1;
        fs   <= (fcnt == 8'd18);
    end

    wire [2:0] state;
    wire [9:0] timer;
    wire [7:0] anim;
    wire [9:0] soul_x, soul_y;
    wire [5:0] player_hp;
    wire [6:0] enemy_hp;
    wire [6:0] iframes;
    wire [9:0] cursor_x;
    wire [4:0] last_damage;
    wire [7:0] hit_flash;
    wire [2:0] round_cnt;
    wire [1:0] wave;
    wire [79:0] bullet_x, bullet_y;
    wire [15:0] bullet_type;
    wire [7:0]  bullet_active;

    battle_logic dut (
        .clk           (clk),
        .frame_start   (fs),
        .pad_up        (pad_up),
        .pad_dn        (pad_dn),
        .pad_lf        (pad_lf),
        .pad_rt        (pad_rt),
        .blast_hit     (blast_hit),
        .blast_busy    (blast_busy),
        .state         (state),
        .timer         (timer),
        .anim          (anim),
        .soul_x        (soul_x),
        .soul_y        (soul_y),
        .player_hp     (player_hp),
        .enemy_hp      (enemy_hp),
        .iframes       (iframes),
        .cursor_x      (cursor_x),
        .last_damage   (last_damage),
        .hit_flash     (hit_flash),
        .round_cnt     (round_cnt),
        .wave          (wave),
        .bullet_x      (bullet_x),
        .bullet_y      (bullet_y),
        .bullet_type   (bullet_type),
        .bullet_active (bullet_active)
    );

    // the blaster wave, hooked up the way battle_core hooks it up
    wire [19:0] bl_mx, bl_my, bl_reach;
    wire [5:0]  bl_dir, bl_kick;
    wire [9:0]  bl_hw;
    wire [3:0]  bl_dim;
    wire [1:0]  bl_hot, bl_head;
    wire        blast_hit, blast_busy;

    wire blast_run   = (state == S_DODGE) && (wave == 2'd3);
    wire blast_spawn = blast_run && (timer < 10'd330);

    blaster_logic blast (
        .clk         (clk),
        .frame_start (fs),
        .run         (blast_run),
        .spawn_en    (blast_spawn),
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
            $display("FAIL (frame %0d, state %0d): %0s", frame_no, state, msg);
        end
    endtask

    // advance one game frame and settle
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

    // The press edge needs one fully-released frame first - exactly what a
    // player has to do to press twice in a row.
    task arm;
        begin
            pad_up = 1'b0; pad_dn = 1'b0; pad_lf = 1'b0; pad_rt = 1'b0;
            next_frame;
        end
    endtask

    // Press for exactly one frame. Because the bench arms first, the game
    // scores this press against the cursor position last sampled here - no
    // drift between "the cursor looks right" and the button going down.
    task strike;
        begin
            pad_up = 1'b1;
            next_frame;
            pad_up = 1'b0;
        end
    endtask

    task tap;
        begin
            arm;
            strike;
            next_frame;
        end
    endtask

    // ---- a player that actually dodges -------------------------------------
    // Reads the live bullet file the way a person reads the box: anything
    // falling towards the soul is stepped around sideways, anything sweeping
    // in from the side is stepped over or under. Crude, but it is the
    // difference between surviving seven enemy turns and dying in three.
    reg dodge_on = 1'b0;

    task release_pads;
        begin
            pad_up = 1'b0; pad_dn = 1'b0; pad_lf = 1'b0; pad_rt = 1'b0;
        end
    endtask

    task dodge_step;
        integer j, bcx, bcy, d, best_d, best_c;
        integer best_axis;          // 0 = dodge sideways, 1 = dodge vertically
        reg [1:0] ty;
        begin
            best_d    = 100000;
            best_axis = -1;
            best_c    = 0;
            // Commit to the single most urgent bullet rather than averaging
            // the whole box - two pillars either side would cancel out and
            // leave the soul standing between them.
            for (j = 0; j < 8; j = j + 1) begin
                if (bullet_active[j]) begin
                    ty  = bullet_type[2*j +: 2];
                    bcx = bullet_x[10*j +: 10] + ((ty == 2'd2) ? 6 : 8);
                    bcy = bullet_y[10*j +: 10] + ((ty == 2'd2) ? 6 : 8);
                    if (ty == 2'd1) begin
                        // sweeping in from a side: urgency is how far it still
                        // has to travel horizontally
                        if (bcy > soul_y - 20 && bcy < soul_y + 36) begin
                            d = (bcx > soul_x + 8) ? bcx - soul_x - 8
                                                   : soul_x + 8 - bcx;
                            if (d < best_d) begin
                                best_d = d;  best_axis = 1;  best_c = bcy;
                            end
                        end
                    end else begin
                        // falling: urgency is how far above the soul it is
                        if (bcx > soul_x - 20 && bcx < soul_x + 36 &&
                            bcy < soul_y + 16) begin
                            d = soul_y + 8 - bcy;
                            if (d < best_d) begin
                                best_d = d;  best_axis = 0;  best_c = bcx;
                            end
                        end
                    end
                end
            end

            release_pads;
            if (best_axis == 0) begin
                // step out of its column, towards whichever side has more room
                if (best_c == soul_x + 8)
                    pad_lf = (soul_x - SOUL_MIN_X > SOUL_MAX_X - soul_x);
                else
                    pad_lf = (best_c > soul_x + 8);
                pad_rt = ~pad_lf;
                if (soul_x <= SOUL_MIN_X + 6) begin pad_lf = 0; pad_rt = 1; end
                if (soul_x >= SOUL_MAX_X - 6) begin pad_rt = 0; pad_lf = 1; end
            end else if (best_axis == 1) begin
                if (best_c == soul_y + 8)
                    pad_up = (soul_y - SOUL_MIN_Y > SOUL_MAX_Y - soul_y);
                else
                    pad_up = (best_c > soul_y + 8);
                pad_dn = ~pad_up;
                if (soul_y <= SOUL_MIN_Y + 6) begin pad_up = 0; pad_dn = 1; end
                if (soul_y >= SOUL_MAX_Y - 6) begin pad_dn = 0; pad_up = 1; end
            end
        end
    endtask

    // one frame of whatever the current player is doing
    task play_frame;
        begin
            if (dodge_on && state == S_DODGE) dodge_step;
            else                              release_pads;
            next_frame;
        end
    endtask

    // ---- per-frame invariants ---------------------------------------------
    integer i;
    reg [5:0] hp_prev = 6'd40;
    reg [5:0] dmg_want;
    integer   last_hit_frame = -1000;
    reg [9:0] bxi, byi;

    always @(posedge clk) if (fs) begin
        #1;
        check(soul_x >= SOUL_MIN_X && soul_x <= SOUL_MAX_X, "soul_x outside the box");
        check(soul_y >= SOUL_MIN_Y && soul_y <= SOUL_MAX_Y, "soul_y outside the box");
        check(player_hp <= 6'd40, "player_hp above maximum");
        check(enemy_hp  <= 7'd120, "enemy_hp above maximum");
        check(iframes   <= 7'd60, "iframes above maximum");
        check(cursor_x >= INNER_L && cursor_x <= INNER_R - 4, "cursor left the box");

        if (player_hp != hp_prev) begin
            if (player_hp < hp_prev) begin
                // the blaster wave is the only one with no bullets in it,
                // so `wave` alone says which kind of hit this was
                dmg_want = (wave == 2'd3) ? 6'd3 : 6'd2;
                if (player_hp == 6'd0)
                    // the killing blow clamps at 0 rather than overshooting
                    check(hp_prev <= dmg_want, "a fatal hit skipped some HP");
                else
                    check(hp_prev - player_hp == dmg_want,
                          "a hit did not cost the right amount of HP");
                check(frame_no - last_hit_frame >= 60,
                      "took a second hit inside the mercy window");
                last_hit_frame = frame_no;
            end
            hp_prev = player_hp;
        end

        for (i = 0; i < 8; i = i + 1) begin
            bxi = bullet_x[10*i +: 10];
            byi = bullet_y[10*i +: 10];
            if (bullet_active[i])
                check(bxi >= 134 && bxi <= 506 && byi >= 194 && byi <= 466,
                      "a live bullet is outside the spawn window");
        end
    end

    // ---- play one turn: wait for AIM, strike, wait out the enemy's turn ----
    // `bullseye` picks the moment to press: on the centre line (16 damage) or
    // out at the edge (3 damage).
    task take_turn(input bullseye, input [4:0] want_damage);
        integer g;
        reg [9:0] mid, err;
        begin
            g = 0;
            while (state != S_AIM && state != S_WIN && state != S_LOSE &&
                   g < 4000) begin
                play_frame; g = g + 1;
            end
            check(g < 4000, "never reached the aim phase");

            if (state == S_AIM) begin
                // press on the frame whose cursor position scores what we want
                arm;
                g = 0;
                while (g < 2000) begin
                    mid = cursor_x + 10'd2;
                    err = (mid > CENTER_X) ? mid - CENTER_X : CENTER_X - mid;
                    if (bullseye ? (err < 10'd6) : (err >= 10'd70))
                        g = 2000;
                    else begin
                        next_frame; g = g + 1;
                    end
                end
                strike;
                check(state == S_HIT, "strike did not enter the hit phase");
                check(last_damage == want_damage, "strike scored the wrong damage");
            end
        end
    endtask

    integer guard;
    integer turns;
    integer sx0, sy0;
    integer bullets_seen, blast_seen;
    reg [5:0] hp0;

    // ---- watchdog ---------------------------------------------------------
    initial begin
        #4_000_000_000;   // 4 s sim time, ~ 10k game frames
        $display("FAIL: watchdog timeout (frame %0d, state %0d)", frame_no, state);
        $finish;
    end

    initial begin
        // ---- phase A: attract screen ---------------------------------------
        step_frames(5);
        check(state == S_TITLE, "did not power up on the title screen");
        check(player_hp == 6'd40 && enemy_hp == 7'd120, "HP not initialised");
        check(bullet_active == 8'd0, "bullets live on the title screen");

        tap;
        check(state == S_AIM, "a button press did not start the battle");

        // ---- phase B: win the battle on bullseye strikes -------------------
        // 120 enemy HP at 16 a strike is eight of them, so a won battle now
        // runs seven enemy turns - the wave cycle gets all the way round
        dodge_on = 1'b1;
        take_turn(1'b1, 5'd16);
        check(enemy_hp == 7'd104, "enemy HP wrong after the first strike");

        turns = 1;
        while (state != S_WIN && state != S_LOSE && turns < 16) begin
            take_turn(1'b1, 5'd16);
            if (state == S_HIT) turns = turns + 1;
        end
        dodge_on = 1'b0;
        check(state == S_WIN, "bullseye strikes did not win the battle");
        check(enemy_hp == 7'd0, "won with the enemy still holding HP");
        check(player_hp > 6'd0, "won at 0 HP");
        $display("  win run: %0d strikes, %0d HP left", turns, player_hp);

        // ---- phase C: restart ----------------------------------------------
        step_frames(95);          // the end screen ignores buttons for 90 frames
        tap;                      // win screen -> attract screen
        check(state == S_TITLE, "the win screen did not return to the title");
        tap;                      // attract screen -> a fresh battle
        check(state == S_AIM, "could not start a second battle");
        check(player_hp == 6'd40 && enemy_hp == 7'd120, "restart did not reset HP");

        // ---- phase D: four-way movement clamps -----------------------------
        // get into a dodge phase first (movement is only live on the enemy
        // turn); strike weakly so the enemy survives into phase E
        take_turn(1'b0, 5'd3);
        guard = 0;
        while (state != S_DODGE && guard < 500) begin next_frame; guard = guard + 1; end
        check(state == S_DODGE, "never reached the dodge phase");

        // diagonals first: both axes move 3 px/frame at once
        sx0 = soul_x; sy0 = soul_y;
        pad_lf = 1'b1; pad_up = 1'b1;
        step_frames(10);
        pad_lf = 1'b0; pad_up = 1'b0;
        check(soul_x == sx0 - 30 && soul_y == sy0 - 30,
              "diagonal movement did not move both axes 3 px/frame");

        // then walk into each wall in turn (the whole sweep fits in one
        // enemy turn: 300 frames of the 330-frame wave)
        pad_lf = 1'b1; step_frames(90); pad_lf = 1'b0;
        check(soul_x == SOUL_MIN_X, "left wall clamp failed");
        pad_up = 1'b1; step_frames(55); pad_up = 1'b0;
        check(soul_y == SOUL_MIN_Y, "top wall clamp failed");
        pad_rt = 1'b1; step_frames(90); pad_rt = 1'b0;
        check(soul_x == SOUL_MAX_X, "right wall clamp failed");
        pad_dn = 1'b1; step_frames(55); pad_dn = 1'b0;
        check(soul_y == SOUL_MAX_Y, "bottom wall clamp failed");
        check(state == S_DODGE, "the movement sweep outlasted the enemy turn");

        // ---- phase E: lose the battle with weak strikes ---------------------
        turns = 0;
        while (state != S_WIN && state != S_LOSE && turns < 20) begin
            take_turn(1'b0, 5'd3);
            if (state == S_HIT) turns = turns + 1;
        end
        check(state == S_LOSE, "weak strikes did not lose the battle");
        check(player_hp == 6'd0, "lost with HP left over");
        check(bullet_active == 8'd0, "bullets left live after the death");
        $display("  lose run: %0d strikes, enemy HP %0d left", turns, enemy_hp);

        // ---- phase F: back to the attract screen ----------------------------
        step_frames(95);
        tap;                      // game-over screen -> attract screen
        check(state == S_TITLE, "the game-over screen did not return to the title");
        tap;
        check(state == S_AIM, "could not start a battle after a game over");

        // ---- phase G: the blaster wave --------------------------------------
        // Ride the turn order round to wave 3 on weak strikes. Waves 0-2 get
        // dodged blind on the way, so the soul may not survive the trip; if it
        // doesn't, start a fresh battle and come round again.
        turns = 0;
        while (!(state == S_DODGE && wave == 2'd3) && turns < 24) begin
            if (state == S_WIN || state == S_LOSE) begin
                step_frames(95);
                tap;                       // end screen -> attract screen
                tap;                       // attract screen -> a fresh battle
            end
            take_turn(1'b0, 5'd3);
            guard = 0;                     // let the enemy's turn begin
            while (state != S_DODGE && state != S_WIN && state != S_LOSE &&
                   guard < 300) begin
                next_frame; guard = guard + 1;
            end
            if (state == S_DODGE && wave != 2'd3) begin
                guard = 0;                 // and run a bullet wave out
                while (state == S_DODGE && guard < 700) begin
                    next_frame; guard = guard + 1;
                end
            end
            turns = turns + 1;
        end
        check(state == S_DODGE && wave == 2'd3,
              "the turn order never reached the blaster wave");

        // stand still: a beam that has locked on cannot miss
        hp0          = player_hp;
        bullets_seen = 0;
        blast_seen   = 0;
        guard        = 0;
        while (state == S_DODGE && player_hp == hp0 && guard < 300) begin
            if (bullet_active != 8'd0) bullets_seen = bullets_seen + 1;
            if (blast_busy)            blast_seen   = blast_seen + 1;
            next_frame; guard = guard + 1;
        end
        check(blast_seen > 0, "the blaster wave put no blaster on screen");
        check(guard < 300, "a soul standing still was never hit by a beam");
        $display("  blaster wave: first beam landed after %0d frames", guard);

        // then keep moving, and watch the rest of the turn out
        guard = 0;
        while (state == S_DODGE && guard < 800) begin
            if (bullet_active != 8'd0) bullets_seen = bullets_seen + 1;
            // the turn may not be handed back while a blaster is still up
            if (timer >= 10'd330)
                check(!(blast_busy && state != S_DODGE),
                      "the turn ended with a blaster still on screen");
            pad_up = ((guard / 24) % 2) == 0;
            pad_dn = ~pad_up;
            next_frame; guard = guard + 1;
        end
        pad_up = 1'b0; pad_dn = 1'b0;
        check(bullets_seen == 0, "the blaster wave spawned bullets");
        check(state != S_DODGE, "the blaster wave never ended");

        if (errors == 0)
            $display("ALL TESTS PASSED (%0d game frames simulated)", frame_no);
        else
            $display("%0d TEST(S) FAILED", errors);
        $finish;
    end

endmodule
