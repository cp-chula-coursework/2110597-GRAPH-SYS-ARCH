//------------------------------------------------------------------------------
// player_renderer.v
//
// The slides' "4. a Sprite renderer" (mario_renderer): window-test the
// current beam position against the 32x32 sprite rectangle, fetch the pixel
// from the sprite ROM, and horizontally mirror when facing left:
//
//   offsetX = flip ? 31 - (x_scroll - posX) : (x_scroll - posX)
//   offsetY = y - posY
//
// The comparison is done in *world* coordinates (x_scroll vs posX), exactly
// as in the slides, so the sprite scrolls with the map for free.
//
// Latency: ROM read (1 clk) + output register (1 clk) = 2 clocks, matching
// bg_renderer so the two layers composite sample-aligned. `visible` rides
// the same 2-stage pipeline. Transparency (12'hFFF) is left to the
// compositor, per the slides' layer-priority mux.
//------------------------------------------------------------------------------
module player_renderer (
    input  wire        clk,
    input  wire [10:0] x_scroll,   // world x of the beam
    input  wire [9:0]  y,
    input  wire [10:0] pos_x,      // sprite top-left, world pixels
    input  wire [9:0]  pos_y,
    input  wire [1:0]  frame,      // 0 idle, 1-2 walk cycle, 3 jump
    input  wire        flip,       // 1 = facing left (mirror horizontally)
    output reg  [11:0] color,      // valid 2 clocks after x/y
    output reg         visible     // beam inside the sprite box, same latency
);

    // ---- stage 0: window test + ROM address ---------------------------
    wire in_x = (x_scroll >= pos_x) && (x_scroll < pos_x + 11'd32);
    wire in_y = ({1'b0, y} >= {1'b0, pos_y}) && ({1'b0, y} < {1'b0, pos_y} + 11'd32);

    // differences are mod-32 safe whenever in_x/in_y hold
    wire [4:0] dx    = x_scroll[4:0] - pos_x[4:0];
    wire [4:0] dy    = y[4:0] - pos_y[4:0];
    wire [4:0] off_x = flip ? (5'd31 - dx) : dx;

    wire [11:0] rom_color;

    player_rom u_rom (
        .clk   (clk),
        .addr  ({frame, dy, off_x}),
        .color (rom_color)
    );

    // ---- stage 1 -> 2: align with bg_renderer's 2-clock latency -------
    reg vis_d1 = 1'b0;
    always @(posedge clk) begin
        vis_d1  <= in_x && in_y;
        color   <= rom_color;
        visible <= vis_d1;
    end

endmodule
