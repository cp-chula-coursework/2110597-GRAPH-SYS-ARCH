//------------------------------------------------------------------------------
// monster_renderer.v
//
// Sprite renderer for the enemy. The ROM holds 64x64 pixels; the sprite is
// drawn at 2x (128x128 on screen) by dropping the low bit of the in-sprite
// offsets, which is how a fixed-function console gets a big sprite out of a
// small ROM:
//
//   rom_x = (x - pos_x) >> 1        rom_y = (y - pos_y) >> 1
//
// `flash` replaces every opaque pixel with white for the hit flash, and
// `show` blanks the sprite once the enemy is defeated. Latency is 2 clocks,
// matching the other layers.
//------------------------------------------------------------------------------
module monster_renderer (
    input  wire        clk,
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire [9:0]  pos_x,     // sprite top-left, 128x128 on screen
    input  wire [9:0]  pos_y,
    input  wire        flash,
    input  wire        show,
    output reg  [11:0] color,     // valid 2 clocks after x/y
    output reg         visible
);

    localparam [11:0] FLASH_COLOR = 12'hEEE;

    // ---- stage 0: window test + ROM address --------------------------------
    wire in_x = (x >= pos_x) && (x < pos_x + 10'd128);
    wire in_y = (y >= pos_y) && (y < pos_y + 10'd128);

    wire [6:0] dx = x[6:0] - pos_x[6:0];   // mod-128 safe while in_x holds
    wire [6:0] dy = y[6:0] - pos_y[6:0];

    wire [11:0] rom_color;

    monster_rom u_rom (
        .clk   (clk),
        .addr  ({dy[6:1], dx[6:1]}),
        .color (rom_color)
    );

    // ---- stage 1 -> 2 ------------------------------------------------------
    reg vis_d1   = 1'b0;
    reg flash_d1 = 1'b0;
    always @(posedge clk) begin
        vis_d1   <= in_x && in_y && show;
        flash_d1 <= flash;
        color    <= flash_d1 ? FLASH_COLOR : rom_color;
        visible  <= vis_d1 && (rom_color != 12'hFFF);
    end

endmodule
