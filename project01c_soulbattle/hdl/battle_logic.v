//------------------------------------------------------------------------------
// battle_logic.v
//
// The whole battle, as hardwired logic: one always block that runs once per
// frame during vertical blanking (the slides' "newframe" tick). No CPU, no
// software - same shape as project01's pong.v, but with a turn-based state
// machine instead of a single rally.
//
// Turn loop (one stage of an Undertale-style encounter):
//
//   TITLE --press--> AIM --press--> HIT --> DODGE --+--> AIM ...
//                     ^                             |
//                     |            enemy HP = 0 --> WIN
//                     |            player HP = 0 --> LOSE --press--> TITLE
//
//   AIM   : a cursor sweeps across the battle box; pressing any button stops
//           it and deals damage by how close to the centre line it stopped
//           (the "timed hit" attack).
//   HIT   : damage read-out + enemy flash/shake for HIT_FRAMES frames.
//   DODGE : the enemy's turn - the soul (a 16x16 heart) is driven around
//           inside the box with the four buttons while bullets spawn from
//           the edges. Contact costs HP and grants IFRAMES frames of mercy
//           invincibility. The wave pattern cycles every turn:
//             wave 0 - falling pillars     (type 0, 16x48, straight down)
//             wave 1 - side-swiping pillars(type 1, 48x16, left/right)
//             wave 2 - bouncing orbs       (type 2, 12x12, diagonal, walls)
//             wave 3 - blasters            (blaster_logic; no bullets at all)
//             wave 4 - blasters sweeping a circle around the soul, three
//                      times as fast (blaster_logic again, in ring mode)
//             wave 5 - one crimson blaster at a time, slow, with a second
//                      and a half of warning - and its beam is fatal
//           Spawns get faster every turn (spawn_period).
//
//   The blaster wave is the one attack this module does not draw itself: it
//   hands the wave over to blaster_logic (which needs the soul's coordinates
//   to aim) and only takes `blast_hit` and `blast_busy` back, so the turn
//   still ends here and a beam costs HP through the same mercy-invincibility
//   path a bullet does.
//
// Bullets live in a small register file (NBULLET slots of x/y/vx/vy/type),
// updated in an unrolled per-frame loop - the classic fixed-object-list
// approach a hardwired console has to use, since there is no memory
// controller or display list to walk.
//
// All positions are whole pixels; velocities are signed pixels/frame.
//------------------------------------------------------------------------------
module battle_logic #(
    parameter integer BOX_L   = 190,   // battle box, outer top-left
    parameter integer BOX_T   = 250,
    parameter integer BOX_W   = 260,
    parameter integer BOX_H   = 160,
    parameter integer BORDER  = 4,     // white frame thickness
    parameter integer NBULLET = 8,
    parameter [9:0]   DODGE_FRAMES = 10'd330   // spawn window per enemy turn
)(
    input  wire        clk,           // pixel clock
    input  wire        frame_start,   // 1-clk pulse at the start of vblank
    input  wire        pad_up,
    input  wire        pad_dn,
    input  wire        pad_lf,
    input  wire        pad_rt,
    input  wire        pad_ok,       // confirm - a gamepad has a button for it
    input  wire        blast_hit,    // a blaster beam is on the soul
    input  wire        blast_kill,   // ... and it was a crimson one: fatal
    input  wire        blast_busy,   // a blaster is still on screen

    output reg  [2:0]  state      = 3'd0,
    output reg  [9:0]  timer      = 10'd0,  // frames spent in this state
    output reg  [7:0]  anim       = 8'd0,   // free-running, drives the idle bob
    output reg  [9:0]  soul_x     = 10'd0,
    output reg  [9:0]  soul_y     = 10'd0,
    output reg  [5:0]  player_hp  = 6'd40,
    output reg  [6:0]  enemy_hp   = 7'd120,
    output reg  [6:0]  iframes    = 7'd0,   // mercy invincibility, frames
    output reg  [9:0]  cursor_x   = 10'd0,  // attack cursor, left edge
    output reg  [4:0]  last_damage= 5'd0,
    output reg  [7:0]  hit_flash  = 8'd0,   // enemy flash/shake, frames
    output reg  [2:0]  round_cnt  = 3'd0,   // turns taken (difficulty ramp)
    output reg  [2:0]  wave       = 3'd0,   // which attack pattern this turn
    output wire [NBULLET*10-1:0] bullet_x,
    output wire [NBULLET*10-1:0] bullet_y,
    output wire [NBULLET*2-1:0]  bullet_type,
    output reg  [NBULLET-1:0]    bullet_active = {NBULLET{1'b0}}
);

    // ---- states -----------------------------------------------------------
    localparam [2:0] S_TITLE = 3'd0,
                     S_AIM   = 3'd1,
                     S_HIT   = 3'd2,
                     S_DODGE = 3'd3,
                     S_WIN   = 3'd4,
                     S_LOSE  = 3'd5;

    // ---- geometry (playfield inside the white frame) -----------------------
    localparam integer INNER_L = BOX_L + BORDER;                  // 194
    localparam integer INNER_T = BOX_T + BORDER;                  // 254
    localparam integer INNER_R = BOX_L + BOX_W - BORDER - 1;      // 445
    localparam integer INNER_B = BOX_T + BOX_H - BORDER - 1;      // 405
    localparam integer CENTER_X = BOX_L + BOX_W / 2;              // 320

    localparam integer SOUL_SZ = 16;
    localparam [9:0] SOUL_MIN_X  = INNER_L + 1;
    localparam [9:0] SOUL_MAX_X  = INNER_R - SOUL_SZ;
    localparam [9:0] SOUL_MIN_Y  = INNER_T + 1;
    localparam [9:0] SOUL_MAX_Y  = INNER_B - SOUL_SZ;
    localparam [9:0] SOUL_HOME_X = BOX_L + BOX_W / 2 - SOUL_SZ / 2;
    localparam [9:0] SOUL_HOME_Y = BOX_T + BOX_H / 2 - SOUL_SZ / 2;
    // during your turn the soul waits at the left of the box instead of the
    // middle, so it isn't sitting on top of the attack cursor's centre line
    localparam [9:0] SOUL_AIM_X  = INNER_L + 6;
    localparam [9:0] SOUL_SPD    = 10'd3;

    // bullets leaving this window are recycled
    localparam integer DESPAWN_L = BOX_L - 56;
    localparam integer DESPAWN_R = BOX_L + BOX_W + 56;
    localparam integer DESPAWN_T = BOX_T - 56;
    localparam integer DESPAWN_B = BOX_T + BOX_H + 56;

    // ---- tuning ------------------------------------------------------------
    localparam [5:0] PLAYER_HP_MAX = 6'd40;
    localparam [6:0] ENEMY_HP_MAX  = 7'd120;
    localparam [5:0] HIT_DMG       = 6'd2;    // HP lost per bullet contact
    localparam [5:0] BLAST_DMG     = 6'd3;    // ... and per blaster beam
    localparam [6:0] IFRAMES       = 7'd60;   // 1 s of mercy invincibility
    localparam [9:0] HIT_FRAMES    = 10'd75;  // damage read-out length
    localparam [9:0] DODGE_MAX     = 10'd480; // hard cap incl. bullet drain
    localparam [9:0] CURSOR_SPD    = 10'd7;
    localparam [9:0] CURSOR_W      = 10'd4;
    localparam [9:0] CURSOR_MAX    = INNER_R - CURSOR_W;
    localparam [2:0] WAVE_BLAST    = 3'd3;   // blasters, from random sides
    localparam [2:0] WAVE_RING     = 3'd4;   // blasters, sweeping a circle
    localparam [2:0] WAVE_RED      = 3'd5;   // one crimson blaster, fatal

    reg cursor_dir = 1'b0;   // attack cursor: 0 = sweeping right, 1 = left

    // ---- button edge (sampled once per frame) ------------------------------
    // Any direction still confirms, because the board's four buttons are all
    // there is without a controller plugged in; a controller adds a button
    // that only confirms.
    wire pad_any = pad_up | pad_dn | pad_lf | pad_rt | pad_ok;
    reg  pad_any_d = 1'b0;
    wire press = pad_any & ~pad_any_d;

    // ---- pseudo-random source: 16-bit maximal-length LFSR ------------------
    // Free-running at the pixel clock, so the value sampled at spawn time is
    // effectively unpredictable to the player.
    reg [15:0] lfsr = 16'hACE1;
    always @(posedge clk)
        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[14] ^ lfsr[12] ^ lfsr[3]};

    // Fold the random byte into a spawn range instead of clamping, so the
    // edge of the box isn't over-represented.
    wire [7:0] r8 = lfsr[7:0];
    wire [9:0] rnd_vx = {2'd0, (r8 > 8'd236) ? r8 - 8'd128 : r8};  // 0..236
    wire [9:0] rnd_hy = {2'd0, (r8 > 8'd136) ? r8 - 8'd128 : r8};  // 0..136
    wire [9:0] rnd_ox = {2'd0, (r8 > 8'd240) ? r8 - 8'd128 : r8};  // 0..240

    // ---- bullet register file ----------------------------------------------
    reg [9:0]        bx    [0:NBULLET-1];
    reg [9:0]        by    [0:NBULLET-1];
    reg signed [4:0] bvx   [0:NBULLET-1];
    reg signed [4:0] bvy   [0:NBULLET-1];
    reg [1:0]        btype [0:NBULLET-1];

    genvar g;
    generate
        for (g = 0; g < NBULLET; g = g + 1) begin : g_flat
            assign bullet_x[10*g +: 10]   = bx[g];
            assign bullet_y[10*g +: 10]   = by[g];
            assign bullet_type[2*g +: 2]  = btype[g];
        end
    endgenerate

    integer b;
    initial begin
        for (b = 0; b < NBULLET; b = b + 1) begin
            bx[b]    = 10'd0;
            by[b]    = 10'd0;
            bvx[b]   = 5'sd0;
            bvy[b]   = 5'sd0;
            btype[b] = 2'd0;
        end
        soul_x = SOUL_HOME_X;
        soul_y = SOUL_HOME_Y;
        cursor_x = INNER_L;
    end

    // ---- collision: soul core box vs. each bullet's body box ---------------
    // The heart's 16x16 cell is generous, so only its 10x10 core counts as a
    // hit - the same "forgiving hitbox" trick the original does.
    wire [9:0] soul_l = soul_x + 10'd3;
    wire [9:0] soul_r = soul_x + 10'd12;
    wire [9:0] soul_t = soul_y + 10'd3;
    wire [9:0] soul_b = soul_y + 10'd12;

    wire [NBULLET-1:0] hit;
    generate
        for (g = 0; g < NBULLET; g = g + 1) begin : g_hit
            wire [9:0] cl = bx[g] + ((btype[g] == 2'd0) ? 10'd2  :
                                     (btype[g] == 2'd1) ? 10'd0  : 10'd1);
            wire [9:0] cr = bx[g] + ((btype[g] == 2'd0) ? 10'd13 :
                                     (btype[g] == 2'd1) ? 10'd47 : 10'd10);
            wire [9:0] ct = by[g] + ((btype[g] == 2'd0) ? 10'd0  :
                                     (btype[g] == 2'd1) ? 10'd2  : 10'd1);
            wire [9:0] cb = by[g] + ((btype[g] == 2'd0) ? 10'd47 :
                                     (btype[g] == 2'd1) ? 10'd13 : 10'd10);
            assign hit[g] = bullet_active[g] &&
                            (cl <= soul_r) && (cr >= soul_l) &&
                            (ct <= soul_b) && (cb >= soul_t);
        end
    endgenerate

    wire any_hit  = |hit;
    // a beam hurts more than a bullet, but goes through the same mercy window
    wire       took_hit = any_hit | blast_hit;
    wire [5:0] took_dmg = blast_hit ? BLAST_DMG : HIT_DMG;

    // ---- free bullet slot (lowest index wins) ------------------------------
    localparam integer IDXW = (NBULLET > 1) ? $clog2(NBULLET) : 1;
    reg [IDXW-1:0] free_idx;
    reg            free_ok;
    integer        f;
    always @(*) begin
        free_ok  = 1'b0;
        free_idx = {IDXW{1'b0}};
        for (f = NBULLET - 1; f >= 0; f = f - 1)
            if (!bullet_active[f]) begin
                free_ok  = 1'b1;
                free_idx = f[IDXW-1:0];
            end
    end

    // ---- attack scoring: distance from the centre line ---------------------
    wire [9:0] cursor_mid = cursor_x + (CURSOR_W >> 1);
    wire [9:0] aim_err    = (cursor_mid > CENTER_X) ? cursor_mid - CENTER_X
                                                    : CENTER_X - cursor_mid;
    wire [4:0] aim_damage = (aim_err < 10'd6)  ? 5'd16 :
                            (aim_err < 10'd18) ? 5'd12 :
                            (aim_err < 10'd40) ? 5'd8  :
                            (aim_err < 10'd70) ? 5'd5  : 5'd3;

    // ---- spawn cadence: base rate per wave, faster every turn -------------
    reg [7:0] spawn_t = 8'd0;
    wire [7:0] base_period  = (wave == 3'd0) ? 8'd26 :
                              (wave == 3'd1) ? 8'd30 : 8'd22;
    // 2 frames faster per turn. The enemy has 120 HP, i.e. seven turns even
    // for a player hitting bullseyes, so the ramp has to be gentle enough to
    // still be survivable at the end of one - a steeper one fills the box
    // long before the enemy runs out of HP.
    wire [7:0] round_ramp   = {4'd0, round_cnt, 1'b0};
    wire [7:0] spawn_period = (base_period > round_ramp + 8'd8)
                                ? base_period - round_ramp : 8'd8;

    // ---- per-frame update --------------------------------------------------
    integer i;
    reg signed [4:0] vxn, vyn;
    reg [9:0]        nx, ny;

    always @(posedge clk) begin
        if (frame_start) begin
            anim      <= anim + 8'd1;
            // saturate rather than wrap: the win/lose screens gate their
            // "press to continue" on timer >= 90, and a wrap would take that
            // away again every 1023 frames
            timer     <= (timer == 10'd1023) ? timer : timer + 10'd1;
            pad_any_d <= pad_any;
            if (iframes   != 7'd0) iframes   <= iframes - 7'd1;
            if (hit_flash != 8'd0) hit_flash <= hit_flash - 8'd1;

            case (state)

            // ---- attract screen: wait for a button, then set up a battle --
            S_TITLE: if (press) begin
                state         <= S_AIM;
                timer         <= 10'd0;
                player_hp     <= PLAYER_HP_MAX;
                enemy_hp      <= ENEMY_HP_MAX;
                round_cnt     <= 3'd0;
                wave          <= 2'd0;
                iframes       <= 7'd0;
                hit_flash     <= 8'd0;
                soul_x        <= SOUL_AIM_X;
                soul_y        <= SOUL_HOME_Y;
                cursor_x      <= INNER_L;
                bullet_active <= {NBULLET{1'b0}};
            end

            // ---- your turn: stop the sweeping cursor on the centre line ---
            S_AIM: begin
                if (!cursor_dir) begin
                    if (cursor_x + CURSOR_SPD >= CURSOR_MAX) begin
                        cursor_x   <= CURSOR_MAX;
                        cursor_dir <= 1'b1;
                    end else
                        cursor_x <= cursor_x + CURSOR_SPD;
                end else begin
                    if (cursor_x <= INNER_L + CURSOR_SPD) begin
                        cursor_x   <= INNER_L;
                        cursor_dir <= 1'b0;
                    end else
                        cursor_x <= cursor_x - CURSOR_SPD;
                end

                if (press) begin
                    last_damage <= aim_damage;
                    enemy_hp    <= (enemy_hp > {2'b0, aim_damage})
                                     ? enemy_hp - {2'b0, aim_damage} : 7'd0;
                    hit_flash   <= 8'd45;
                    state       <= S_HIT;
                    timer       <= 10'd0;
                end
            end

            // ---- damage read-out, then hand the turn to the enemy ---------
            S_HIT: if (timer >= HIT_FRAMES) begin
                timer <= 10'd0;
                if (enemy_hp == 7'd0)
                    state <= S_WIN;
                else begin
                    state   <= S_DODGE;
                    soul_x  <= SOUL_HOME_X;
                    soul_y  <= SOUL_HOME_Y;
                    spawn_t <= 8'd12;
                end
            end

            // ---- enemy turn: drive the soul, run the bullet wave ----------
            S_DODGE: begin
                // 1. soul movement (both axes, so diagonals work)
                if (pad_rt && !pad_lf)
                    soul_x <= (soul_x + SOUL_SPD > SOUL_MAX_X) ? SOUL_MAX_X
                                                               : soul_x + SOUL_SPD;
                else if (pad_lf && !pad_rt)
                    soul_x <= (soul_x < SOUL_MIN_X + SOUL_SPD) ? SOUL_MIN_X
                                                               : soul_x - SOUL_SPD;
                if (pad_dn && !pad_up)
                    soul_y <= (soul_y + SOUL_SPD > SOUL_MAX_Y) ? SOUL_MAX_Y
                                                               : soul_y + SOUL_SPD;
                else if (pad_up && !pad_dn)
                    soul_y <= (soul_y < SOUL_MIN_Y + SOUL_SPD) ? SOUL_MIN_Y
                                                               : soul_y - SOUL_SPD;

                // 2. move every live bullet; orbs bounce off the side walls
                for (i = 0; i < NBULLET; i = i + 1) begin
                    if (bullet_active[i]) begin
                        vxn = bvx[i];
                        vyn = bvy[i];
                        if (btype[i] == 2'd2) begin
                            if (vxn[4] && (bx[i] <= INNER_L + 2))
                                vxn = -vxn;
                            else if (!vxn[4] && (bx[i] + 10'd12 >= INNER_R))
                                vxn = -vxn;
                        end
                        nx = bx[i] + {{5{vxn[4]}}, vxn};
                        ny = by[i] + {{5{vyn[4]}}, vyn};
                        bvx[i] <= vxn;
                        bx[i]  <= nx;
                        by[i]  <= ny;
                        if (nx < DESPAWN_L || nx > DESPAWN_R ||
                            ny < DESPAWN_T || ny > DESPAWN_B)
                            bullet_active[i] <= 1'b0;
                    end
                end

                // 3. spawn the next bullet of this wave (the blaster wave
                //    fires no bullets - blaster_logic owns the whole box)
                if (timer < DODGE_FRAMES && wave != WAVE_BLAST &&
                    wave != WAVE_RING && wave != WAVE_RED) begin
                    if (spawn_t != 8'd0)
                        spawn_t <= spawn_t - 8'd1;
                    else begin
                        spawn_t <= spawn_period;
                        if (free_ok) begin
                            bullet_active[free_idx] <= 1'b1;
                            case (wave)
                            3'd0: begin  // falling pillar
                                btype[free_idx] <= 2'd0;
                                bx[free_idx]    <= INNER_L + rnd_vx;
                                by[free_idx]    <= INNER_T - 10'd48;
                                bvx[free_idx]   <= 5'sd0;
                                bvy[free_idx]   <= lfsr[9] ? 5'sd4 : 5'sd3;
                            end
                            3'd1: begin  // side-swiping pillar
                                btype[free_idx] <= 2'd1;
                                bx[free_idx]    <= lfsr[10] ? INNER_R + 10'd1
                                                            : INNER_L - 10'd48;
                                by[free_idx]    <= INNER_T + rnd_hy;
                                bvx[free_idx]   <= lfsr[10] ? -5'sd4 : 5'sd4;
                                bvy[free_idx]   <= 5'sd0;
                            end
                            default: begin  // bouncing orb
                                btype[free_idx] <= 2'd2;
                                bx[free_idx]    <= INNER_L + rnd_ox;
                                by[free_idx]    <= INNER_T - 10'd12;
                                bvx[free_idx]   <= lfsr[11] ? -5'sd2 : 5'sd2;
                                bvy[free_idx]   <= lfsr[12] ? 5'sd3 : 5'sd2;
                            end
                            endcase
                        end
                    end
                end

                // 4. contact damage (mercy invincibility gates repeats)
                // The crimson beam ignores both the HP bar and the mercy
                // window: standing in it ends the battle there and then.
                // That is the whole point of the wave, and why it gives a
                // second and a half of warning before it fires.
                if (blast_kill) begin
                    player_hp     <= 6'd0;
                    state         <= S_LOSE;
                    timer         <= 10'd0;
                    bullet_active <= {NBULLET{1'b0}};
                end

                else if (took_hit && iframes == 7'd0) begin
                    if (player_hp <= took_dmg) begin
                        player_hp     <= 6'd0;
                        state         <= S_LOSE;
                        timer         <= 10'd0;
                        bullet_active <= {NBULLET{1'b0}};
                    end else begin
                        player_hp <= player_hp - took_dmg;
                        iframes   <= IFRAMES;
                    end
                end

                // 5. turn over once the wave has run and the box is clear
                else if ((timer >= DODGE_FRAMES &&
                          bullet_active == {NBULLET{1'b0}} && !blast_busy) ||
                         (timer >= DODGE_MAX)) begin
                    state         <= S_AIM;
                    timer         <= 10'd0;
                    bullet_active <= {NBULLET{1'b0}};
                    soul_x        <= SOUL_AIM_X;
                    soul_y        <= SOUL_HOME_Y;
                    wave          <= (wave == WAVE_RED) ? 3'd0 : wave + 3'd1;
                    if (round_cnt != 3'd7) round_cnt <= round_cnt + 3'd1;
                end
            end

            // ---- end of battle: any button returns to the attract screen --
            S_WIN, S_LOSE: if (timer >= 10'd90 && press) begin
                state <= S_TITLE;
                timer <= 10'd0;
            end

            default: state <= S_TITLE;
            endcase
        end
    end

endmodule
