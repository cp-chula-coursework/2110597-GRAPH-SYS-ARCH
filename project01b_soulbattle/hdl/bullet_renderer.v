//------------------------------------------------------------------------------
// bullet_renderer.v
//
// Draws the enemy's projectiles straight from the bullet register file - no
// sprite ROM, the shapes are pure comparator logic on the in-bullet offset
// (dx,dy), the same way project01's pong.v draws its ball and paddles as
// bounding boxes:
//
//   type 0  falling pillar   16x48   shaft with a capped head and foot
//   type 1  swiping pillar   48x16   the same shape rotated
//   type 2  bouncing orb     12x12   diamond with a hot core
//
// Every bullet is clipped to the inside of the battle box, so a bullet is
// invisible until it has entered the arena and vanishes as it leaves - the
// box acts as a hardware window, which is also why bullets may be spawned
// off-box without showing.
//
// All NBULLET shape tests run in parallel; a priority mux (lowest slot wins)
// picks the pixel, then two register stages match the 2-clock latency of the
// ROM-based layers.
//------------------------------------------------------------------------------
module bullet_renderer #(
    parameter integer BOX_L   = 190,
    parameter integer BOX_T   = 250,
    parameter integer BOX_W   = 260,
    parameter integer BOX_H   = 160,
    parameter integer BORDER  = 4,
    parameter integer NBULLET = 8
)(
    input  wire        clk,
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire [NBULLET*10-1:0] bullet_x,
    input  wire [NBULLET*10-1:0] bullet_y,
    input  wire [NBULLET*2-1:0]  bullet_type,
    input  wire [NBULLET-1:0]    bullet_active,
    output reg  [11:0] color,      // valid 2 clocks after x/y
    output reg         visible
);

    localparam integer INNER_L = BOX_L + BORDER;
    localparam integer INNER_T = BOX_T + BORDER;
    localparam integer INNER_R = BOX_L + BOX_W - BORDER - 1;
    localparam integer INNER_B = BOX_T + BOX_H - BORDER - 1;

    localparam [11:0] C_PILLAR     = 12'hEEF;   // bone-white shaft
    localparam [11:0] C_PILLAR_CAP = 12'hCCD;   // slightly shaded cap
    localparam [11:0] C_ORB        = 12'h4CF;   // cyan orb
    localparam [11:0] C_ORB_HOT    = 12'hBEF;   // its glowing core

    wire in_box = (x >= INNER_L) && (x <= INNER_R) &&
                  (y >= INNER_T) && (y <= INNER_B);

    wire [NBULLET-1:0]    hit;
    wire [NBULLET*12-1:0] col;

    genvar g;
    generate
        for (g = 0; g < NBULLET; g = g + 1) begin : g_bullet
            wire [9:0] bxg = bullet_x[10*g +: 10];
            wire [9:0] byg = bullet_y[10*g +: 10];
            wire [1:0] tg  = bullet_type[2*g +: 2];

            wire [9:0] wg = (tg == 2'd1) ? 10'd48 : (tg == 2'd2) ? 10'd12 : 10'd16;
            wire [9:0] hg = (tg == 2'd0) ? 10'd48 : (tg == 2'd2) ? 10'd12 : 10'd16;

            wire in_w = (x >= bxg) && (x < bxg + wg) &&
                        (y >= byg) && (y < byg + hg);

            // offsets are mod-64 safe while in_w holds (largest bullet is 48)
            wire [5:0] dx = x[5:0] - bxg[5:0];
            wire [5:0] dy = y[5:0] - byg[5:0];

            // vertical pillar: 8-wide shaft, 14-wide cap, rounded tips
            wire v_cap = (dy < 6'd7) || (dy >= 6'd41);
            wire v_tip = (dy == 6'd0) || (dy == 6'd47);
            wire v_on  = v_cap ? (v_tip ? (dx >= 6'd3 && dx <= 6'd12)
                                        : (dx >= 6'd1 && dx <= 6'd14))
                               : (dx >= 6'd4 && dx <= 6'd11);

            // horizontal pillar: the same shape with the axes swapped
            wire h_cap = (dx < 6'd7) || (dx >= 6'd41);
            wire h_tip = (dx == 6'd0) || (dx == 6'd47);
            wire h_on  = h_cap ? (h_tip ? (dy >= 6'd3 && dy <= 6'd12)
                                        : (dy >= 6'd1 && dy <= 6'd14))
                               : (dy >= 6'd4 && dy <= 6'd11);

            // orb: |dx| + |dy| <= 5 about the centre of a 12x12 cell
            wire [5:0] odx  = (dx >= 6'd6) ? dx - 6'd6 : 6'd5 - dx;
            wire [5:0] ody  = (dy >= 6'd6) ? dy - 6'd6 : 6'd5 - dy;
            wire [6:0] osum = {1'b0, odx} + {1'b0, ody};

            wire shape = (tg == 2'd0) ? v_on :
                         (tg == 2'd1) ? h_on : (osum <= 7'd5);

            assign hit[g] = bullet_active[g] && in_w && in_box && shape;

            assign col[12*g +: 12] =
                (tg == 2'd2) ? ((osum <= 7'd2) ? C_ORB_HOT : C_ORB)
                             : (((tg == 2'd0) ? v_cap : h_cap) ? C_PILLAR_CAP
                                                               : C_PILLAR);
        end
    endgenerate

    // ---- priority mux: lowest active slot owns the pixel -------------------
    reg  [11:0] raw_color;
    reg         raw_hit;
    integer     i;
    always @(*) begin
        raw_color = 12'h000;
        raw_hit   = 1'b0;
        for (i = NBULLET - 1; i >= 0; i = i - 1)
            if (hit[i]) begin
                raw_hit   = 1'b1;
                raw_color = col[12*i +: 12];
            end
    end

    // ---- 2-clock pipeline to match the sprite layers -----------------------
    reg [11:0] col_d1 = 12'h000;
    reg        hit_d1 = 1'b0;
    always @(posedge clk) begin
        col_d1  <= raw_color;
        hit_d1  <= raw_hit;
        color   <= col_d1;
        visible <= hit_d1;
    end

endmodule
