//------------------------------------------------------------------------------
// soul_renderer.v
//
// The player's soul, drawn with comparators instead of a sprite ROM. There is
// no art in this project at all: every shape on screen is a set of arithmetic
// tests on the beam position, the same way the slides' Pong draws its ball and
// paddles, which is all a 1st-generation console could do.
//
// The 16x16 heart is three shapes unioned together, in half-pixel units so the
// centre falls between columns 7 and 8:
//
//   ax2 = |2*dx - 15|                     horizontal distance from the centre
//   lobe_l = |dx-4| + |dy-6| <= 6         upper-left lobe   (a diamond)
//   lobe_r = |dx-11| + |dy-6| <= 6        upper-right lobe
//   lower  = dy >= 8 && ax2 <= 15 - 2*(dy-8)     the point, a triangle
//
//   ....#......#....   the two diamonds meet at row 7, so the notch at the
//   ...###....###...   top and the full-width waist come out of the geometry
//   ..#####..#####..   rather than being drawn anywhere
//   .##############.
//   ################
//   .##############.
//   ....########....
//   .......##.......
//
// `frame` is the shattered heart for the losing screen: the same shape with a
// two-pixel crack knocked out of it, the crack zigzagging with dy[2:1] so it
// looks broken rather than cut.
//
// `show` is dropped for a few frames at a time while the player is in mercy
// invincibility, which makes the heart blink.
//
// Latency: 2 clocks, the same as every other layer, so the compositor sees all
// the layers sample-aligned.
//------------------------------------------------------------------------------
module soul_renderer (
    input  wire        clk,
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire [9:0]  pos_x,     // top-left of the 16x16 cell
    input  wire [9:0]  pos_y,
    input  wire        frame,     // 0 = whole heart, 1 = shattered heart
    input  wire        show,
    output reg  [11:0] color,     // valid 2 clocks after x/y
    output reg         visible
);

    localparam [11:0] C_SOUL   = 12'hF04;   // the red of the original
    localparam [11:0] C_HILITE = 12'hF89;   // a lighter facet on the left lobe

    // ---- stage 0: window test ----------------------------------------------
    wire in_x = (x >= pos_x) && (x < pos_x + 10'd16);
    wire in_y = (y >= pos_y) && (y < pos_y + 10'd16);

    // differences are mod-16 safe whenever in_x/in_y hold
    wire [3:0] dx = x[3:0] - pos_x[3:0];
    wire [3:0] dy = y[3:0] - pos_y[3:0];

    // ---- the heart, as three comparator shapes -----------------------------
    wire [4:0] ax2 = (dx >= 4'd8) ? ({dx, 1'b0} - 5'd15) : (5'd15 - {dx, 1'b0});
    // 5 bits wide, not 4: |dx-11| + |dy-6| reaches 17 at the corners of the
    // cell, and a 4-bit sum would wrap round into the middle of the heart
    wire [4:0] lx  = (dx >= 4'd4)  ? (dx - 4'd4)  : (4'd4  - dx);
    wire [4:0] rx  = (dx >= 4'd11) ? (dx - 4'd11) : (4'd11 - dx);
    wire [4:0] uy  = (dy >= 4'd6)  ? (dy - 4'd6)  : (4'd6  - dy);

    wire lobe_l = (dy <= 4'd7) && ((lx + uy) <= 5'd6);
    wire lobe_r = (dy <= 4'd7) && ((rx + uy) <= 5'd6);

    // dy >= 8 means dy - 8 is just dy[2:0], so the taper is 15 - 2*dy[2:0]
    // and the subtraction can never wrap
    wire [4:0] taper = 5'd15 - {1'b0, dy[2:0], 1'b0};
    wire lower  = (dy >= 4'd8) && (ax2 <= taper);

    wire heart = lobe_l | lobe_r | lower;

    // the crack, for the shattered frame: two columns wide, zigzagging down
    wire [3:0] crack_c = 4'd7 + {3'd0, dy[1]} - {3'd0, dy[2]};
    wire crack = frame && (dx >= crack_c) && (dx <= crack_c + 4'd1);

    // a facet on the upper-left lobe, so the heart reads as lit from one side
    wire hilite = ((lx + uy) <= 5'd2) && (dy <= 4'd6);

    // ---- stage 1 -> 2 ------------------------------------------------------
    reg vis_d1 = 1'b0;
    reg hil_d1 = 1'b0;
    always @(posedge clk) begin
        vis_d1  <= in_x && in_y && show && heart && !crack;
        hil_d1  <= hilite;
        color   <= hil_d1 ? C_HILITE : C_SOUL;
        visible <= vis_d1;
    end

endmodule
