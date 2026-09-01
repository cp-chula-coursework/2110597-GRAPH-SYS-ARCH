//------------------------------------------------------------------------------
// blaster_renderer.v
//
// Draws the blasters: the beam, and the skull it comes out of.
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
// Pong draws its paddles with. On a diagonal, dx-dy measures sqrt(2) times the
// true distance across, so the half-width is scaled by ~1.375 (two shifts and
// two adds) rather than dividing anything by sqrt(2).
//
// `reach` is what makes the beam travel: blaster_logic grows it by 72 px per
// frame from the moment the blaster fires, so the beam visibly punches out of
// the muzzle and across the box instead of appearing all at once. Everything
// is clipped to the inside of the battle box, exactly like the bullets.
//
// THE SKULL is a 32x32 ROM drawn at 2x. Only two frames are stored - one
// facing straight down, one facing down-right - and the other six headings
// come from the symmetries of the square, which cost nothing but address
// wiring: mirror the row address, mirror the column address, or swap the two.
//   S  = frame 0 as stored          SE = frame 1 as stored
//   N  = frame 0, rows mirrored     NE = frame 1, rows mirrored
//   E  = frame 0, address swapped   NW = frame 1, both mirrored
//   W  = frame 0, swapped + mirrored SW = frame 1, columns mirrored
// The skull is symmetric about its own axis, so the mirroring never shows.
//
// One ROM port serves both blasters, picked by a cell-priority mux the same
// way hud_renderer shares one font port between four text bands. Two skulls
// that overlap therefore occlude at cell granularity rather than pixel
// granularity - the classic fixed-sprite-hardware artifact, and rare in
// practice because blasters are placed on whichever side of the box is
// furthest from the soul.
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
    output reg  [11:0] color,        // valid 2 clocks after x/y
    output reg         visible
);

    localparam [2:0] D_S  = 3'd0, D_SE = 3'd1, D_E = 3'd2, D_NE = 3'd3,
                     D_N  = 3'd4, D_NW = 3'd5, D_W = 3'd6, D_SW = 3'd7;

    localparam [9:0] INNER_L = BOX_L + BORDER;
    localparam [9:0] INNER_T = BOX_T + BORDER;
    localparam [9:0] INNER_R = BOX_L + BOX_W - BORDER - 1;
    localparam [9:0] INNER_B = BOX_T + BOX_H - BORDER - 1;

    localparam [11:0] C_BEAM_CORE = 12'hFFF;   // white-hot centre
    localparam [11:0] C_BEAM_EDGE = 12'hBDF;   // cooler blue fringe
    localparam [11:0] C_WARN      = 12'hEEF;   // the thin warning line

    wire in_box = (x >= INNER_L) && (x <= INNER_R) &&
                  (y >= INNER_T) && (y <= INNER_B);

    wire [NBLAST-1:0]    beam_on, cell_on;
    wire [NBLAST*12-1:0] beam_col;
    wire [NBLAST*5-1:0]  cell_sx, cell_sy;

    genvar g;
    generate
        for (g = 0; g < NBLAST; g = g + 1) begin : g_blast
            wire [9:0] mxg   = bl_mx   [10*g +: 10];
            wire [9:0] myg   = bl_my   [10*g +: 10];
            wire [9:0] rchg  = bl_reach[10*g +: 10];
            wire [2:0] dg    = bl_dir  [ 3*g +:  3];
            wire [4:0] hwg   = bl_hw   [ 5*g +:  5];
            wire [2:0] kickg = bl_kick [ 3*g +:  3];

            // ---- the beam ---------------------------------------------------
            wire signed [12:0] sdx = $signed({3'b0, x}) - $signed({3'b0, mxg});
            wire signed [12:0] sdy = $signed({3'b0, y}) - $signed({3'b0, myg});

            wire signed [12:0] across = dg[0] ? (dg[1] ? sdx + sdy : sdx - sdy)
                                              : (dg[1] ? sdy : sdx);
            wire signed [12:0] down   = (dg[2:1] == 2'd0) ?  sdy :
                                        (dg[2:1] == 2'd1) ?  sdx :
                                        (dg[2:1] == 2'd2) ? -sdy : -sdx;
            wire signed [12:0] aabs   = across[12] ? -across : across;

            wire [6:0] hw   = {2'd0, hwg};
            wire [6:0] hwd  = hw + (hw >> 2) + (hw >> 3);   // ~sqrt(2) * hw
            wire [6:0] hwe  = dg[0] ? hwd : hw;
            wire [6:0] core = hwe >> 1;

            assign beam_on[g] = (hwg != 5'd0) && in_box &&
                                (aabs <= $signed({6'd0, hwe})) &&
                                (down >= 13'sd0) &&
                                (down <= $signed({3'd0, rchg}));

            assign beam_col[12*g +: 12] =
                ~bl_hot[g]                        ? C_WARN :
                (aabs <= $signed({6'd0, core}))   ? C_BEAM_CORE : C_BEAM_EDGE;

            // ---- the skull's 64x64 cell -------------------------------------
            // The muzzle sits at a different corner or edge of the cell for
            // each heading, and the recoil kick shoves the head back along its
            // own beam. Every result stays on screen (the box is inset far
            // enough on all four sides), so plain unsigned arithmetic is safe.
            reg [9:0] cl, ct;
            always @(*) begin
                case (dg)
                D_S:     begin cl = mxg - 10'd32;
                               ct = myg - 10'd64 - kickg; end
                D_SE:    begin cl = mxg - 10'd52 - kickg;
                               ct = myg - 10'd52 - kickg; end
                D_E:     begin cl = mxg - 10'd64 - kickg;
                               ct = myg - 10'd32;         end
                D_NE:    begin cl = mxg - 10'd52 - kickg;
                               ct = myg - 10'd12 + kickg; end
                D_N:     begin cl = mxg - 10'd32;
                               ct = myg          + kickg; end
                D_NW:    begin cl = mxg - 10'd12 + kickg;
                               ct = myg - 10'd12 + kickg; end
                D_W:     begin cl = mxg          + kickg;
                               ct = myg - 10'd32;         end
                default: begin cl = mxg - 10'd12 + kickg;   // D_SW
                               ct = myg - 10'd52 - kickg; end
                endcase
            end

            wire [9:0] cdx = x - cl;
            wire [9:0] cdy = y - ct;

            assign cell_on[g] = bl_head[g] && (x >= cl) && (cdx < 10'd64) &&
                                              (y >= ct) && (cdy < 10'd64);
            assign cell_sx[5*g +: 5] = cdx[5:1];   // 2x scale
            assign cell_sy[5*g +: 5] = cdy[5:1];
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

    // ---- pick which skull gets the single ROM port -------------------------
    reg [4:0] sel_sx, sel_sy;
    reg [2:0] sel_dir;
    reg [1:0] sel_dim;
    reg       sel_on;
    integer   h;
    always @(*) begin
        sel_sx  = 5'd0;
        sel_sy  = 5'd0;
        sel_dir = D_S;
        sel_dim = 2'd0;
        sel_on  = 1'b0;
        for (h = NBLAST - 1; h >= 0; h = h - 1)
            if (cell_on[h]) begin
                sel_on  = 1'b1;
                sel_sx  = cell_sx[5*h +: 5];
                sel_sy  = cell_sy[5*h +: 5];
                sel_dir = bl_dir [3*h +: 3];
                sel_dim = bl_dim [2*h +: 2];
            end
    end

    // ---- one of the eight symmetries of the two stored frames --------------
    reg [4:0] rom_x, rom_y;
    always @(*) begin
        case (sel_dir)
        D_S:     begin rom_x =  sel_sx; rom_y =  sel_sy; end
        D_N:     begin rom_x =  sel_sx; rom_y = ~sel_sy; end
        D_E:     begin rom_x =  sel_sy; rom_y =  sel_sx; end
        D_W:     begin rom_x =  sel_sy; rom_y = ~sel_sx; end
        D_SE:    begin rom_x =  sel_sx; rom_y =  sel_sy; end
        D_NE:    begin rom_x =  sel_sx; rom_y = ~sel_sy; end
        D_NW:    begin rom_x = ~sel_sx; rom_y = ~sel_sy; end
        default: begin rom_x = ~sel_sx; rom_y =  sel_sy; end   // D_SW
        endcase
    end

    wire [11:0] rom_color;

    blaster_rom u_rom (
        .clk   (clk),
        .addr  ({sel_dir[0], rom_y, rom_x}),   // bit 0 of the heading picks
        .color (rom_color)                     // the axis / diagonal frame
    );

    // ---- stage 1: ROM data is on its way back ------------------------------
    reg [11:0] beam_color_d1 = 12'h000;
    reg        beam_hit_d1   = 1'b0;
    reg        head_on_d1    = 1'b0;
    reg [1:0]  head_dim_d1   = 2'd0;

    always @(posedge clk) begin
        beam_color_d1 <= beam_color;
        beam_hit_d1   <= beam_hit;
        head_on_d1    <= sel_on;
        head_dim_d1   <= sel_dim;
    end

    // fade by halving each colour channel, which on 4-bit channels is a shift
    wire [11:0] head_color =
        (head_dim_d1 == 2'd0) ? rom_color :
        (head_dim_d1 == 2'd1) ? {1'b0, rom_color[11:9],
                                 1'b0, rom_color[ 7:5],
                                 1'b0, rom_color[ 3:1]}
                              : {2'b0, rom_color[11:10],
                                 2'b0, rom_color[ 7:6],
                                 2'b0, rom_color[ 3:2]};

    wire head_px = head_on_d1 && (rom_color != 12'hFFF);

    // ---- stage 2: the skull is in front of its own beam --------------------
    always @(posedge clk) begin
        color   <= head_px ? head_color : beam_color_d1;
        visible <= head_px | beam_hit_d1;
    end

endmodule
