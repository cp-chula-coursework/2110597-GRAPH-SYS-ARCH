//------------------------------------------------------------------------------
// blaster_renderer.v
//
// Draws the blasters: the beam, and the skull it comes out of. Neither one is
// stored anywhere - this project has no sprite ROM, so the skull is a set of
// comparisons exactly like the beam is.
//
// THE BEAM is a rotated rectangle, but because blaster_logic only ever aims
// along eight compass points it never needs a rotation. Take the offset from
// the muzzle, (dx, dy):
//
//   heading        across the beam      down the beam
//   S  / N         dx                   +dy / -dy
//   E  / W         dy                   +dx / -dx
//   SE / NW        dx - dy              +dy / -dy
//   NE / SW        dx + dy              +dx / -dx
//
// so "inside the beam" is |across| <= half-width AND 0 <= down <= reach - four
// adders and four comparators per blaster, the same class of logic the slides'
// Pong draws its paddles with.
//
// `reach` is what makes the beam travel: blaster_logic grows it by 72 px per
// frame from the moment the blaster fires, so the beam visibly punches out of
// the muzzle and across the box instead of appearing all at once. Everything
// is clipped to the inside of the battle box, exactly like the bullets.
//
// THE SKULL is drawn in that same rotated frame, which is what makes eight
// orientations free: let aa = |across| and uu = how far behind the muzzle the
// pixel is, and describe the skull once, facing along its own beam.
//
//        uu=60  .-'''-.        dome    aa <= 24, rounded off past uu = 44
//               |     |        jaw     aa <= 11 + uu/2, widening backwards
//        uu=34  | O O |        sockets |aa-13| <= 8, cut by a diagonal
//        uu=24  |  ^  |        nose    a small diamond
//        uu=0   '|#|#|'        teeth   stripes, one bit of aa
//                  V  the muzzle: where the beam comes out
//
// A sprite ROM would have needed either eight bitmaps or the mirror-and-swap
// address tricks the previous version of this project used; a shape function
// in beam coordinates needs neither, and there is no cell-granularity
// occlusion between overlapping skulls any more because each blaster tests its
// own shape in parallel.
//
// On the diagonal headings both beam axes are sums of the pixel offsets, so
// both come out sqrt(2) times the true distance; the skull scales each of them
// by 0.6875 (three shifts and two adds, 2.8% off 1/sqrt(2)) and so comes out
// the same size and shape whichever of the eight ways it points. The beam
// needs the correction the other way round, widening its half-width by ~1.375
// instead of narrowing what it measures.
//
// Latency is 2 clocks, matching every other layer.
//------------------------------------------------------------------------------
module blaster_renderer #(
    parameter integer BOX_L  = 190,
    parameter integer BOX_T  = 250,
    parameter integer BOX_W  = 260,
    parameter integer BOX_H  = 160,
    parameter integer BORDER = 4,
    parameter integer NBLAST = 2
)(
    input  wire        clk,
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire [NBLAST*10-1:0] bl_mx,
    input  wire [NBLAST*10-1:0] bl_my,
    input  wire [NBLAST*3-1:0]  bl_dir,
    input  wire [NBLAST*5-1:0]  bl_hw,
    input  wire [NBLAST*10-1:0] bl_reach,
    input  wire [NBLAST*3-1:0]  bl_kick,
    input  wire [NBLAST*2-1:0]  bl_dim,
    input  wire [NBLAST-1:0]    bl_hot,
    input  wire [NBLAST-1:0]    bl_head,
    input  wire                 red,     // draw the crimson one instead
    output reg  [11:0] color,        // valid 2 clocks after x/y
    output reg         visible
);

    localparam [9:0] INNER_L = BOX_L + BORDER;
    localparam [9:0] INNER_T = BOX_T + BORDER;
    localparam [9:0] INNER_R = BOX_L + BOX_W - BORDER - 1;
    localparam [9:0] INNER_B = BOX_T + BOX_H - BORDER - 1;

    localparam [11:0] C_BEAM_CORE = 12'hFFF;   // white-hot centre
    localparam [11:0] C_BEAM_EDGE = 12'hBDF;   // cooler blue fringe
    localparam [11:0] C_WARN      = 12'hEEF;   // the thin warning line

    // the crimson wave's beam, in the same three parts
    localparam [11:0] C_RED_CORE  = 12'hF99;
    localparam [11:0] C_RED_EDGE  = 12'hC00;
    localparam [11:0] C_RED_WARN  = 12'hF44;

    // the skull
    localparam [11:0] C_BONE      = 12'hDDE;
    localparam [11:0] C_TOOTH     = 12'hFFF;
    localparam [11:0] C_GLOW      = 12'hFFB;
    localparam [11:0] C_DARK      = 12'h112;
    localparam [11:0] C_BONE_RED  = 12'hE55;
    localparam [11:0] C_TOOTH_RED = 12'hF99;
    localparam [11:0] C_GLOW_RED  = 12'hFDD;

    wire [11:0] beam_core = red ? C_RED_CORE : C_BEAM_CORE;
    wire [11:0] beam_edge = red ? C_RED_EDGE : C_BEAM_EDGE;
    wire [11:0] beam_warn = red ? C_RED_WARN : C_WARN;
    wire [11:0] bone_col  = red ? C_BONE_RED  : C_BONE;
    wire [11:0] tooth_col = red ? C_TOOTH_RED : C_TOOTH;
    wire [11:0] glow_col  = red ? C_GLOW_RED  : C_GLOW;

    wire in_box = (x >= INNER_L) && (x <= INNER_R) &&
                  (y >= INNER_T) && (y <= INNER_B);

    wire [NBLAST-1:0]    beam_on, head_on;
    wire [NBLAST*12-1:0] beam_col, head_col;

    genvar g;
    generate
        for (g = 0; g < NBLAST; g = g + 1) begin : g_blast
            wire [9:0] mxg   = bl_mx   [10*g +: 10];
            wire [9:0] myg   = bl_my   [10*g +: 10];
            wire [9:0] rchg  = bl_reach[10*g +: 10];
            wire [2:0] dg    = bl_dir  [ 3*g +:  3];
            wire [4:0] hwg   = bl_hw   [ 5*g +:  5];
            wire [2:0] kickg = bl_kick [ 3*g +:  3];

            // ---- beam frame -------------------------------------------------
            wire signed [12:0] sdx = $signed({3'b0, x}) - $signed({3'b0, mxg});
            wire signed [12:0] sdy = $signed({3'b0, y}) - $signed({3'b0, myg});

            wire signed [12:0] dsum = sdx + sdy;
            wire signed [12:0] ddif = sdx - sdy;

            wire signed [12:0] across = dg[0] ? (dg[1] ? dsum : ddif)
                                              : (dg[1] ? sdy : sdx);
            wire signed [12:0] down   = (dg[2:1] == 2'd0) ?  sdy :
                                        (dg[2:1] == 2'd1) ?  sdx :
                                        (dg[2:1] == 2'd2) ? -sdy : -sdx;
            wire signed [12:0] aabs   = across[12] ? -across : across;

            // The beam only needs `down` to know where to stop, so a diagonal
            // one measures along its own axis with whichever of dx, dy it
            // likes. The skull cannot: a shape cut into slices by horizontal
            // lines while its sides run at 45 degrees comes out sheared, not
            // rotated. So it gets a real along-beam axis, which on a diagonal
            // is the other of the two sums - free, both are already computed.
            wire signed [12:0] diag_along = dg[1] ? ddif : dsum;
            wire signed [12:0] along = dg[0] ? (dg[2] ? -diag_along : diag_along)
                                             : down;

            // ---- the beam ---------------------------------------------------
            wire [6:0] hw   = {2'd0, hwg};
            wire [6:0] hwd  = hw + (hw >> 2) + (hw >> 3);   // ~sqrt(2) * hw
            wire [6:0] hwe  = dg[0] ? hwd : hw;
            wire [6:0] core = hwe >> 1;

            assign beam_on[g] = (hwg != 5'd0) && in_box &&
                                (aabs <= $signed({6'd0, hwe})) &&
                                (down >= 13'sd0) &&
                                (down <= $signed({3'd0, rchg}));

            assign beam_col[12*g +: 12] =
                ~bl_hot[g]                        ? beam_warn :
                (aabs <= $signed({6'd0, core}))   ? beam_core : beam_edge;

            // ---- the skull, in the beam's own coordinates -------------------
            // uu counts backwards from the muzzle, so the whole shape is
            // described once and every heading gets it for free. The recoil
            // kick simply shoves the near edge further back.
            wire [12:0] umag = along[12] ? -along : 13'd0;  // 0 in front of it
            wire [12:0] amag = aabs;

            // both diagonal axes are sums of the offsets, so both come out
            // sqrt(2) too big and both shrink by the same 0.6875
            wire [12:0] a_n = dg[0] ? ((amag >> 1) + (amag >> 3) + (amag >> 4))
                                    : amag;
            wire [12:0] u_n = dg[0] ? ((umag >> 1) + (umag >> 3) + (umag >> 4))
                                    : umag;

            wire behind = (along < 13'sd0) && (u_n >= {10'd0, kickg});
            wire [12:0] uu = u_n - {10'd0, kickg};
            wire [12:0] aa = a_n;

            wire in_cell = bl_head[g] && behind &&
                           (uu <= 13'd60) && (aa <= 13'd26);

            // jaw: widens going back from the muzzle; dome: the cranium,
            // rounded off over its last 16 rows
            wire jaw = (uu <= 13'd20) && (aa <= (13'd11 + (uu >> 1)));

            wire [12:0] back = (uu > 13'd44) ? (uu - 13'd44) : 13'd0;
            wire [12:0] cw   = (uu > 13'd60) ? 13'd0
                                             : (13'd24 - (back + (back >> 1)));
            wire dome = (uu >= 13'd20) && (uu <= 13'd60) && (aa <= cw);

            wire bone = jaw || dome;

            // eye sockets: a window, cut across by a diagonal so they slant
            wire [12:0] ex = (aa >= 13'd13) ? (aa - 13'd13) : (13'd13 - aa);
            wire socket = (uu >= 13'd26) && (uu <= 13'd42) && (ex <= 13'd8) &&
                          ((uu - 13'd26) >= ((aa - 13'd5) >> 2));
            wire glow   = socket && (ex <= 13'd4) &&
                          (uu >= 13'd29) && (uu <= 13'd39);

            // nose: a small diamond where the jaw meets the dome
            wire [12:0] ny = (uu >= 13'd27) ? (uu - 13'd27) : (13'd27 - uu);
            wire nose = (uu >= 13'd20) && (uu <= 13'd27) && ((aa + ny) <= 13'd6);

            // teeth: one bit of aa, a stripe every 4 px across the muzzle end
            wire tooth = bone && (uu <= 13'd8) && !aa[2];

            assign head_on[g] = in_cell && bone;
            assign head_col[12*g +: 12] = glow            ? glow_col  :
                                          (socket | nose) ? C_DARK    :
                                          tooth           ? tooth_col : bone_col;
        end
    endgenerate

    // ---- pick the beam pixel (lowest live slot wins) -----------------------
    reg [11:0] beam_color;
    reg        beam_hit;
    integer    b;
    always @(*) begin
        beam_color = 12'h000;
        beam_hit   = 1'b0;
        for (b = NBLAST - 1; b >= 0; b = b - 1)
            if (beam_on[b]) begin
                beam_hit   = 1'b1;
                beam_color = beam_col[12*b +: 12];
            end
    end

    // ---- and the skull pixel, the same way ---------------------------------
    reg [11:0] skull_color;
    reg        skull_hit;
    reg [1:0]  skull_dim;
    integer    h;
    always @(*) begin
        skull_color = 12'h000;
        skull_hit   = 1'b0;
        skull_dim   = 2'd0;
        for (h = NBLAST - 1; h >= 0; h = h - 1)
            if (head_on[h]) begin
                skull_hit   = 1'b1;
                skull_color = head_col[12*h +: 12];
                skull_dim   = bl_dim [ 2*h +: 2];
            end
    end

    // ---- stage 1 -----------------------------------------------------------
    reg [11:0] beam_color_d1 = 12'h000;
    reg        beam_hit_d1   = 1'b0;
    reg [11:0] head_color_d1 = 12'h000;
    reg        head_hit_d1   = 1'b0;
    reg [1:0]  head_dim_d1   = 2'd0;

    always @(posedge clk) begin
        beam_color_d1 <= beam_color;
        beam_hit_d1   <= beam_hit;
        head_color_d1 <= skull_color;
        head_hit_d1   <= skull_hit;
        head_dim_d1   <= skull_dim;
    end

    // fade by halving each colour channel, which on 4-bit channels is a shift
    wire [11:0] head_shown =
        (head_dim_d1 == 2'd0) ? head_color_d1 :
        (head_dim_d1 == 2'd1) ? {1'b0, head_color_d1[11:9],
                                 1'b0, head_color_d1[ 7:5],
                                 1'b0, head_color_d1[ 3:1]}
                              : {2'b0, head_color_d1[11:10],
                                 2'b0, head_color_d1[ 7:6],
                                 2'b0, head_color_d1[ 3:2]};

    // ---- stage 2: the skull is in front of its own beam --------------------
    always @(posedge clk) begin
        color   <= head_hit_d1 ? head_shown : beam_color_d1;
        visible <= head_hit_d1 | beam_hit_d1;
    end

endmodule
