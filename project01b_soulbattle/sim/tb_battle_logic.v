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
//   win  run - strike on the bullseye every turn (16 damage), survive the
//              enemy's turns, and check the battle ends in WIN
//   lose run - strike at the far edge every turn (3 damage) so the enemy
//              outlasts the player, and check the battle ends in LOSE with
//              the soul at 0 HP
//
// Checked along the way, every frame:
//   - the soul never leaves the inside of the battle box
//   - HP never exceeds its maximum and never goes negative
//   - a hit costs exactly 2 HP and cannot repeat within the 60-frame mercy
//     window (i-frames)
//   - every live bullet stays inside the spawn/despawn window
//   - the attack cursor stays inside the box, and a bullseye press really
//     does score 16 while an edge press scores 3
//   - the four-way movement clamps against all four walls
//
//   iverilog -o /tmp/tb_logic.vvp hdl/battle_logic.v sim/tb_battle_logic.v
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
    wire [5:0] player_hp, enemy_hp;
    wire [6:0] iframes;
    wire [9:0] cursor_x;
    wire [4:0] last_damage;
    wire [7:0] hit_flash;
    wire [2:0] round_cnt;
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
        .bullet_x      (bullet_x),
        .bullet_y      (bullet_y),
        .bullet_type   (bullet_type),
        .bullet_active (bullet_active)
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

    // ---- per-frame invariants ---------------------------------------------
    integer i;
    reg [5:0] hp_prev = 6'd20;
    integer   last_hit_frame = -1000;
    reg [9:0] bxi, byi;

    always @(posedge clk) if (fs) begin
        #1;
        check(soul_x >= SOUL_MIN_X && soul_x <= SOUL_MAX_X, "soul_x outside the box");
        check(soul_y >= SOUL_MIN_Y && soul_y <= SOUL_MAX_Y, "soul_y outside the box");
        check(player_hp <= 6'd20, "player_hp above maximum");
        check(enemy_hp  <= 6'd40, "enemy_hp above maximum");
        check(iframes   <= 7'd60, "iframes above maximum");
        check(cursor_x >= INNER_L && cursor_x <= INNER_R - 4, "cursor left the box");

        if (player_hp != hp_prev) begin
            if (player_hp < hp_prev) begin
                check(hp_prev - player_hp == 6'd2, "a hit did not cost exactly 2 HP");
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
                   g < 2000) begin
                next_frame; g = g + 1;
            end
            check(g < 2000, "never reached the aim phase");

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
        check(player_hp == 6'd20 && enemy_hp == 6'd40, "HP not initialised");
        check(bullet_active == 8'd0, "bullets live on the title screen");

        tap;
        check(state == S_AIM, "a button press did not start the battle");

        // ---- phase B: win the battle with three bullseye strikes -----------
        take_turn(1'b1, 5'd16);
        check(enemy_hp == 6'd24, "enemy HP wrong after the first strike");

        turns = 1;
        while (state != S_WIN && state != S_LOSE && turns < 8) begin
            take_turn(1'b1, 5'd16);
            if (state == S_HIT) turns = turns + 1;
        end
        check(state == S_WIN, "three bullseye strikes did not win the battle");
        check(enemy_hp == 6'd0, "won with the enemy still holding HP");
        check(player_hp > 6'd0, "won at 0 HP");
        $display("  win run: %0d strikes, %0d HP left", turns, player_hp);

        // ---- phase C: restart ----------------------------------------------
        step_frames(95);          // the end screen ignores buttons for 90 frames
        tap;                      // win screen -> attract screen
        check(state == S_TITLE, "the win screen did not return to the title");
        tap;                      // attract screen -> a fresh battle
        check(state == S_AIM, "could not start a second battle");
        check(player_hp == 6'd20 && enemy_hp == 6'd40, "restart did not reset HP");

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

        if (errors == 0)
            $display("ALL TESTS PASSED (%0d game frames simulated)", frame_no);
        else
            $display("%0d TEST(S) FAILED", errors);
        $finish;
    end

endmodule
