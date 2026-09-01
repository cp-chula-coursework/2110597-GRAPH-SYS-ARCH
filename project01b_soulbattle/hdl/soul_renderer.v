//------------------------------------------------------------------------------
// soul_renderer.v
//
// Sprite renderer for the player's soul: window-test the beam against the
// 16x16 heart, fetch the pixel from soul_rom, and report it as visible only
// where the ROM pixel isn't the transparent key (12'hFFF).
//
// Latency: ROM read (1 clk) + output register (1 clk) = 2 clocks, the same
// as every other layer in this project, so the compositor sees all four
// layers sample-aligned.
//
// `show` is dropped for a few frames at a time while the player is in mercy
// invincibility, which makes the heart blink.
//------------------------------------------------------------------------------
module soul_renderer (
    input  wire        clk,
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire [9:0]  pos_x,     // sprite top-left
    input  wire [9:0]  pos_y,
    input  wire        frame,     // 0 = whole heart, 1 = shattered heart
    input  wire        show,
    output reg  [11:0] color,     // valid 2 clocks after x/y
    output reg         visible
);

    // ---- stage 0: window test + ROM address --------------------------------
    wire in_x = (x >= pos_x) && (x < pos_x + 10'd16);
    wire in_y = (y >= pos_y) && (y < pos_y + 10'd16);

    // differences are mod-16 safe whenever in_x/in_y hold
    wire [3:0] dx = x[3:0] - pos_x[3:0];
    wire [3:0] dy = y[3:0] - pos_y[3:0];

    wire [11:0] rom_color;

    soul_rom u_rom (
        .clk   (clk),
        .addr  ({frame, dy, dx}),
        .color (rom_color)
    );

    // ---- stage 1 -> 2 ------------------------------------------------------
    reg vis_d1 = 1'b0;
    always @(posedge clk) begin
        vis_d1  <= in_x && in_y && show;
        color   <= rom_color;
        visible <= vis_d1 && (rom_color != 12'hFFF);
    end

endmodule
