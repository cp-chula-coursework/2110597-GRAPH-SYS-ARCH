//------------------------------------------------------------------------------
// blaster_logic.v
//
// The blaster wave (wave 3 of the enemy turn): floating skulls that appear on
// the rim of the battle box, aim themselves at the soul, hold for a moment,
// then fire a thick beam down the line they are aiming along.
//
// One slot's life, all of it on the once-per-frame `frame_start` tick:
//
//   IDLE --spawner--> TRACK ------> CHARGE ------> FIRE --------> FADE --> IDLE
//                     18 frames     14..26 fr      20 frames      10 fr
//                     head fades    muzzle frozen, beam grows     head
//                     in, muzzle    a 3 px white   out of the     fades
//                     keeps re-     warning line   muzzle and     out
//                     solving from  is drawn       widens to
//                     the soul                     18 px
//
// AIMING - the part that makes this a geometry problem rather than a bullet:
//
//   The heading is picked at spawn from eight compass points, and then the
//   muzzle is *solved for*: given the soul's centre and a heading, there is
//   exactly one point on the rim of the box that a ray of that heading passes
//   through the soul from. For the four axis headings that point is just the
//   soul's own x or y carried out to the edge; for the four diagonals it is
//   the soul's centre walked back along the 45-degree line until it hits the
//   nearer of the two edges, i.e. t = min(dx, dy) - subtract and compare, no
//   multiplier and no divider anywhere.
//
//   Restricting the heading to eight points is what keeps every later stage
//   cheap: the beam is then a half-plane test on x, y, x+y or x-y (see
//   blaster_renderer), and the skull is one shape drawn in those same
//   coordinates, so it points eight ways for nothing. A free-angle beam would
//   need a normalized direction vector and a multiplier per pixel.
//
//   The side of the box a blaster comes from is random, except that a side
//   closer than MIN_LEAD to the soul is swapped for the opposite one - a beam
//   that appears 10 px away and fires down the same line is not a dodge, it
//   is a coin flip.
//
// The muzzle keeps tracking the soul for the whole TRACK phase - the skull
// visibly slides along the rim after you - and freezes when CHARGE starts, so
// the warning line always shows exactly where the beam will be.
//
// `ring` turns the same machinery into a second, faster wave: the heading
// walks one compass point round per blaster rather than being drawn at
// random, and every phase is shortened, so they come three times as often and
// sweep a full circle about the soul. Nothing else changes - each muzzle is
// still solved the same way, so every beam in the circle still passes exactly
// through the soul from wherever on the rim its heading reaches it.
//------------------------------------------------------------------------------
module blaster_logic #(
    parameter integer BOX_L  = 190,   // battle box, outer top-left
    parameter integer BOX_T  = 250,
    parameter integer BOX_W  = 260,
    parameter integer BOX_H  = 160,
    parameter integer NBLAST = 2      // blasters that can be on screen at once
)(
    input  wire       clk,            // pixel clock
    input  wire       frame_start,    // 1-clk pulse at the start of vblank
    input  wire       run,            // the blaster wave owns the enemy turn
    input  wire       spawn_en,       // ... and is still inside its spawn window
    input  wire       ring,           // sweep the headings round instead of
                                      // picking each one at random
    input  wire       red,            // the crimson one: one at a time, slow,
                                      // and a hit is fatal outright
    input  wire [9:0] soul_x,         // soul sprite top-left
    input  wire [9:0] soul_y,
    input  wire [2:0] round_cnt,      // difficulty ramp

    output wire [NBLAST*10-1:0] bl_mx,     // muzzle, on the rim of the box
    output wire [NBLAST*10-1:0] bl_my,
    output wire [NBLAST*3-1:0]  bl_dir,    // heading, 8 compass points
    output wire [NBLAST*5-1:0]  bl_hw,     // beam half-width, 0 = no beam
    output wire [NBLAST*10-1:0] bl_reach,  // how far the beam has grown
    output wire [NBLAST*3-1:0]  bl_kick,   // head recoil, px back along the beam
    output wire [NBLAST*2-1:0]  bl_dim,    // head fade: 0 full, 1 half, 2 quarter
    output wire [NBLAST-1:0]    bl_hot,    // 1 = firing, 0 = warning line
    output wire [NBLAST-1:0]    bl_head,   // head on screen
    output wire                 blast_hit, // a live beam is on the soul
    output wire                 blast_kill,// ... and it was a crimson one
    output wire                 blast_busy // something is still on screen
);

    // ---- headings ----------------------------------------------------------
    // Numbered clockwise from "straight down" so that bit 0 selects diagonal
    // vs. axis and bits [2:1] select which axis the beam advances along - the
    // renderer leans on both.
    localparam [2:0] D_S  = 3'd0,   // beam travels ( 0, +1)
                     D_SE = 3'd1,   //              (+1, +1)
                     D_E  = 3'd2,   //              (+1,  0)
                     D_NE = 3'd3,   //              (+1, -1)
                     D_N  = 3'd4,   //              ( 0, -1)
                     D_NW = 3'd5,   //              (-1, -1)
                     D_W  = 3'd6,   //              (-1,  0)
                     D_SW = 3'd7;   //              (-1, +1)

    // ---- phases ------------------------------------------------------------
    localparam [2:0] P_IDLE   = 3'd0,
                     P_TRACK  = 3'd1,
                     P_CHARGE = 3'd2,
                     P_FIRE   = 3'd3,
                     P_FADE   = 3'd4;

    localparam [7:0] TRACK_F = 8'd18;
    localparam [7:0] FIRE_F  = 8'd20;
    localparam [7:0] FADE_F  = 8'd10;

    // The ring wave puts one up every 18 frames instead of every 54, and each
    // lives 46 frames instead of 74, so three or four are on screen at once
    // sweeping round. Everything is shortened except the warning, which is
    // only cut to 16 frames: it is the one thing standing between the player
    // and an attack that cannot be dodged.
    localparam [7:0] RING_TRACK  = 8'd10;
    localparam [7:0] RING_CHARGE = 8'd16;
    localparam [7:0] RING_FIRE   = 8'd14;
    localparam [7:0] RING_FADE   = 8'd6;
    localparam [7:0] RING_GAP    = 8'd18;

    // The crimson wave goes the other way entirely. Its beam does not take
    // HP, it ends the battle, so everything about it is built to be seen
    // coming: one blaster on screen at a time, a second and a half of warning
    // line before it fires, and a long wait between them. An instant kill is
    // only fair while it is never a surprise.
    localparam [7:0] RED_TRACK  = 8'd40;
    localparam [7:0] RED_CHARGE = 8'd90;    // 1.5 s of warning
    localparam [7:0] RED_FIRE   = 8'd24;
    localparam [7:0] RED_FADE   = 8'd14;
    localparam [7:0] RED_GAP    = 8'd80;

    localparam [4:0] FULL_HW    = 5'd9;      // 19 px of beam at full width
    localparam [9:0] REACH_STEP = 10'd72;    // px/frame the beam reaches out
    localparam [9:0] REACH_MAX  = 10'd1023;

    // the muzzle is never allowed closer than this to the soul, measured on
    // the axis the beam advances along
    localparam [9:0] MIN_LEAD = 10'd40;

    // soul core half-size, matching battle_logic's forgiving 10x10 hitbox
    localparam [6:0] SOUL_HALF = 7'd5;

    // ---- box rim -----------------------------------------------------------
    localparam [9:0] EDGE_L = BOX_L;
    localparam [9:0] EDGE_R = BOX_L + BOX_W - 1;
    localparam [9:0] EDGE_T = BOX_T;
    localparam [9:0] EDGE_B = BOX_T + BOX_H - 1;

    // ---- difficulty --------------------------------------------------------
    // later turns give less warning and send blasters closer together
    wire [7:0] round_x2  = {4'd0, round_cnt, 1'b0};
    wire [7:0] round_x4  = {3'd0, round_cnt, 2'd0};
    wire [7:0] charge_f  = red  ? RED_CHARGE :
                           ring ? RING_CHARGE :
                           (round_x2 < 8'd12) ? (8'd26 - round_x2) : 8'd14;
    wire [7:0] gap_frames= red  ? RED_GAP :
                           ring ? RING_GAP :
                           (round_x4 < 8'd24) ? (8'd54 - round_x4) : 8'd30;
    wire [7:0] track_f   = red ? RED_TRACK : ring ? RING_TRACK : TRACK_F;
    wire [7:0] fire_f    = red ? RED_FIRE  : ring ? RING_FIRE  : FIRE_F;
    wire [7:0] fade_f    = red ? RED_FADE  : ring ? RING_FADE  : FADE_F;

    // ---- pseudo-random source ----------------------------------------------
    // Its own LFSR, seeded differently from battle_logic's, so the side a
    // blaster comes from is not correlated with the bullet waves.
    reg [15:0] lfsr = 16'h1D7B;
    always @(posedge clk)
        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[14] ^ lfsr[12] ^ lfsr[3]};

    // ---- where the soul is, and how much room is on each side --------------
    wire [9:0] cx = soul_x + 10'd8;
    wire [9:0] cy = soul_y + 10'd8;

    wire [9:0] room_l = cx - EDGE_L;
    wire [9:0] room_r = EDGE_R - cx;
    wire [9:0] room_t = cy - EDGE_T;
    wire [9:0] room_b = EDGE_B - cy;

    // Pick a side at random, but fall back to the opposite one when the
    // random side is too close to give the player a dodge. The box is 160 x
    // 260, so the far side always clears MIN_LEAD and the fallback is final.
    wire from_above = lfsr[3] ? (room_t >= MIN_LEAD) : ~(room_b >= MIN_LEAD);
    wire from_left  = lfsr[4] ? (room_l >= MIN_LEAD) : ~(room_r >= MIN_LEAD);

    // half diagonal, quarter vertical, quarter horizontal
    wire [1:0] family = lfsr[6:5];

    wire [2:0] dir_rand = (family == 2'd2) ? (from_above ? D_S : D_N) :
                          (family == 2'd3) ? (from_left  ? D_E : D_W) :
                          from_above ? (from_left ? D_SE : D_SW)
                                     : (from_left ? D_NE : D_NW);

    // The ring wave walks the heading round one compass point per blaster, so
    // the attack sweeps a circle about the soul instead of landing wherever a
    // random draw puts it. Where it starts and which way it goes are drawn
    // once per turn: the sweep should be readable, not memorisable.
    reg [2:0] ring_dir = 3'd0;
    reg       ring_cw  = 1'b0;

    wire [2:0] dir_new = ring ? ring_dir : dir_rand;

    // ---- solve the muzzle: the point on the rim this heading aims from ------
    function [19:0] muzzle(input [2:0] d, input [9:0] px, input [9:0] py);
        reg [9:0] rl, rr, rt, rb, t;
        begin
            rl = px - EDGE_L;  rr = EDGE_R - px;
            rt = py - EDGE_T;  rb = EDGE_B - py;
            case (d)
            D_S:  muzzle = {px, EDGE_T};
            D_N:  muzzle = {px, EDGE_B};
            D_E:  muzzle = {EDGE_L, py};
            D_W:  muzzle = {EDGE_R, py};
            D_SE: begin t = (rl < rt) ? rl : rt;  muzzle = {px - t, py - t}; end
            D_SW: begin t = (rr < rt) ? rr : rt;  muzzle = {px + t, py - t}; end
            D_NE: begin t = (rl < rb) ? rl : rb;  muzzle = {px - t, py + t}; end
            default: begin t = (rr < rb) ? rr : rb; muzzle = {px + t, py + t}; end
            endcase
        end
    endfunction

    // ---- beam width and head presentation, both pure functions of phase ----
    function [4:0] hw_of(input [2:0] s, input [7:0] t, input [7:0] ff);
        begin
            if (s == P_CHARGE)
                hw_of = 5'd1;                       // the 3 px warning line
            else if (s == P_FIRE) begin
                if      (t == 8'd0)       hw_of = 5'd3;       // snapping open
                else if (t == 8'd1)       hw_of = 5'd6;
                else if (t <  ff - 8'd4)  hw_of = FULL_HW;
                else if (t == ff - 8'd4)  hw_of = 5'd7;       // and closing
                else if (t == ff - 8'd3)  hw_of = 5'd5;
                else if (t == ff - 8'd2)  hw_of = 5'd3;
                else                      hw_of = 5'd1;
            end else
                hw_of = 5'd0;
        end
    endfunction

    function [2:0] kick_of(input [2:0] s, input [7:0] t);
        kick_of = (s != P_FIRE)  ? 3'd0 :
                  (t < 8'd2)     ? 3'd4 :
                  (t < 8'd5)     ? 3'd2 : 3'd0;
    endfunction

    function [1:0] dim_of(input [2:0] s, input [7:0] t);
        begin
            if (s == P_TRACK)
                dim_of = (t < 8'd5) ? 2'd2 : (t < 8'd11) ? 2'd1 : 2'd0;
            else if (s == P_FADE)
                dim_of = (t < 8'd3) ? 2'd0 : (t < 8'd7) ? 2'd1 : 2'd2;
            else
                dim_of = 2'd0;
        end
    endfunction

    // ---- slot register file ------------------------------------------------
    reg [2:0] st  [0:NBLAST-1];   // phase
    reg [7:0] pt  [0:NBLAST-1];   // frames spent in it
    reg [2:0] dr  [0:NBLAST-1];   // heading
    reg [9:0] mx  [0:NBLAST-1];   // muzzle
    reg [9:0] my  [0:NBLAST-1];
    reg [9:0] rch [0:NBLAST-1];   // beam reach
    reg [7:0] gap = 8'd10;        // frames until the next blaster

    integer k;
    initial begin
        for (k = 0; k < NBLAST; k = k + 1) begin
            st[k]  = P_IDLE;
            pt[k]  = 8'd0;
            dr[k]  = D_S;
            mx[k]  = EDGE_L;
            my[k]  = EDGE_T;
            rch[k] = 10'd0;
        end
    end

    // ---- flatten the slots for the renderer, and test the soul against ------
    // ---- every live beam ---------------------------------------------------
    wire [NBLAST-1:0]    hitv, busyv;
    wire [NBLAST*20-1:0] mzb;             // muzzle each slot is tracking to
    wire [19:0]          mz_new = muzzle(dir_new, cx, cy);

    genvar g;
    generate
        for (g = 0; g < NBLAST; g = g + 1) begin : g_slot
            wire [2:0] dg  = dr[g];
            wire [4:0] hwg = hw_of(st[g], pt[g], fire_f);

            assign bl_mx   [10*g +: 10] = mx[g];
            assign bl_my   [10*g +: 10] = my[g];
            assign bl_reach[10*g +: 10] = rch[g];
            assign bl_dir  [ 3*g +:  3] = dg;
            assign bl_hw   [ 5*g +:  5] = hwg;
            assign bl_kick [ 3*g +:  3] = kick_of(st[g], pt[g]);
            assign bl_dim  [ 2*g +:  2] = dim_of(st[g], pt[g]);
            assign bl_hot  [g]          = (st[g] == P_FIRE);
            assign bl_head [g]          = (st[g] != P_IDLE);
            assign busyv   [g]          = (st[g] != P_IDLE);

            // Same half-plane test the renderer draws with, evaluated once at
            // the soul's centre instead of once per pixel: `perp` is the
            // distance across the beam, `along` the distance down it.
            wire signed [12:0] sdx = $signed({3'b0, cx}) - $signed({3'b0, mx[g]});
            wire signed [12:0] sdy = $signed({3'b0, cy}) - $signed({3'b0, my[g]});

            wire signed [12:0] perp  = dg[0] ? (dg[1] ? sdx + sdy : sdx - sdy)
                                             : (dg[1] ? sdy : sdx);
            wire signed [12:0] along = (dg[2:1] == 2'd0) ?  sdy :
                                       (dg[2:1] == 2'd1) ?  sdx :
                                       (dg[2:1] == 2'd2) ? -sdy : -sdx;
            wire signed [12:0] pabs  = perp[12] ? -perp : perp;

            // On a diagonal, x-y measures sqrt(2) times the true distance
            // across the beam, so the threshold is scaled by ~1.375 (a pair
            // of shifts) instead of dividing by sqrt(2).
            wire [6:0] thr  = {2'd0, hwg} + SOUL_HALF;
            wire [6:0] thrd = thr + (thr >> 2) + (thr >> 3);
            wire [6:0] thre = dg[0] ? thrd : thr;

            // where this slot's heading would put the muzzle right now
            assign mzb[20*g +: 20] = muzzle(dg, cx, cy);

            assign hitv[g] = (st[g] == P_FIRE) &&
                             (pabs  <= $signed({6'd0, thre})) &&
                             (along >= 13'sd0) &&
                             (along <= $signed({3'd0, rch[g]}));
        end
    endgenerate

    assign blast_hit  = |hitv;
    assign blast_kill = red & (|hitv);
    assign blast_busy = |busyv;

    // ---- free slot (lowest index wins) -------------------------------------
    localparam integer IDXW = (NBLAST > 1) ? $clog2(NBLAST) : 1;
    reg [IDXW-1:0] free_idx;
    reg            free_ok;
    integer        f;
    always @(*) begin
        free_ok  = 1'b0;
        free_idx = {IDXW{1'b0}};
        for (f = NBLAST - 1; f >= 0; f = f - 1)
            if (st[f] == P_IDLE) begin
                free_ok  = 1'b1;
                free_idx = f[IDXW-1:0];
            end
        // the crimson one comes alone: two of a beam that kills outright
        // would leave nowhere to stand
        if (red && (busyv != {NBLAST{1'b0}})) free_ok = 1'b0;
    end

    // ---- per-frame update --------------------------------------------------
    integer i;

    always @(posedge clk) begin
        if (frame_start) begin
            if (!run) begin
                // the wave isn't running: clear the screen and pre-load a
                // short lead-in so the first blaster arrives promptly
                for (i = 0; i < NBLAST; i = i + 1) begin
                    st[i] <= P_IDLE;
                    pt[i] <= 8'd0;
                end
                gap      <= 8'd10;
                ring_dir <= lfsr[2:0];        // a fresh place to start
                ring_cw  <= lfsr[7];          // and a fresh way round
            end else begin
                for (i = 0; i < NBLAST; i = i + 1) begin
                    case (st[i])

                    // still turning onto the soul: re-solve the muzzle every
                    // frame, so the skull slides along the rim after it
                    P_TRACK: begin
                        mx[i] <= mzb[20*i + 10 +: 10];
                        my[i] <= mzb[20*i +: 10];
                        if (pt[i] + 8'd1 >= track_f) begin
                            st[i] <= P_CHARGE;
                            pt[i] <= 8'd0;
                        end else
                            pt[i] <= pt[i] + 8'd1;
                    end

                    // locked: the warning line is up, the muzzle no longer moves
                    P_CHARGE: begin
                        if (pt[i] + 8'd1 >= charge_f) begin
                            st[i]  <= P_FIRE;
                            pt[i]  <= 8'd0;
                            rch[i] <= REACH_STEP;
                        end else
                            pt[i] <= pt[i] + 8'd1;
                    end

                    // firing: the beam reaches further down its line each frame
                    P_FIRE: begin
                        rch[i] <= (rch[i] > REACH_MAX - REACH_STEP)
                                    ? REACH_MAX : rch[i] + REACH_STEP;
                        if (pt[i] + 8'd1 >= fire_f) begin
                            st[i] <= P_FADE;
                            pt[i] <= 8'd0;
                        end else
                            pt[i] <= pt[i] + 8'd1;
                    end

                    P_FADE: begin
                        if (pt[i] + 8'd1 >= fade_f) begin
                            st[i] <= P_IDLE;
                            pt[i] <= 8'd0;
                        end else
                            pt[i] <= pt[i] + 8'd1;
                    end

                    default: ;   // P_IDLE: the spawner below owns this slot
                    endcase
                end

                // ---- spawner ----------------------------------------------
                if (spawn_en) begin
                    if (gap != 8'd0)
                        gap <= gap - 8'd1;
                    else if (free_ok) begin
                        gap           <= gap_frames;
                        st [free_idx] <= P_TRACK;
                        pt [free_idx] <= 8'd0;
                        dr [free_idx] <= dir_new;
                        mx [free_idx] <= mz_new[19:10];
                        my [free_idx] <= mz_new[9:0];
                        rch[free_idx] <= REACH_MAX;   // the warning line spans
                        if (ring)                     // the whole box
                            ring_dir <= ring_cw ? ring_dir + 3'd1
                                                : ring_dir - 3'd1;
                    end
                end
            end
        end
    end

endmodule
