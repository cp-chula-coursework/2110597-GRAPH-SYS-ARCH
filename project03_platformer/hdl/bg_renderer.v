//------------------------------------------------------------------------------
// bg_renderer.v
//
// Scrolling tile background, per the slides' "2. Background tile" +
// "3. Scrolling background tile" architecture:
//
//   x_scroll = vga x + scrollOffset (computed by the caller)
//   x_scroll[10:4], y[9:4]  -> Map ROM   -> tile index      (1 clk)
//   tile, x_scroll[3:0], y[3:0] -> BG tile ROM -> rgb       (1 clk)
//
// Total latency 2 clocks. The slides run logic at 4x the pixel rate on a
// Basys3 so the delay hides inside one pixel; here everything runs at the
// 25.175 MHz pixel clock (as in project02), so the caller pipelines its
// sync/blank flags 2 clocks to match and the whole frame just shifts 2
// pixels - invisible.
//
// During blanking (x >= 640 or y >= 480) the map address is forced to 0 so
// the ROM index can never run past the 80x30 map.
//------------------------------------------------------------------------------
module bg_renderer (
    input  wire        clk,
    input  wire [9:0]  x,         // raw vga x (active-area guard)
    input  wire [9:0]  y,
    input  wire [10:0] x_scroll,  // world x = x + scrollOffset, 0..1279 active
    output wire [11:0] color      // valid 2 clocks after x/y
);

    wire active = (x < 10'd640) && (y < 10'd480);

    // ---- stage 0 -> 1: map fetch --------------------------------------
    wire [11:0] map_addr = active ? (y[9:4] * 12'd80) + {5'd0, x_scroll[10:4]}
                                  : 12'd0;
    wire [7:0] tile;

    map_rom u_map (
        .clk  (clk),
        .addr (map_addr),
        .tile (tile)
    );

    // pixel-within-tile offsets ride along one stage
    reg [3:0] off_x_d1 = 4'd0, off_y_d1 = 4'd0;
    always @(posedge clk) begin
        off_x_d1 <= x_scroll[3:0];
        off_y_d1 <= y[3:0];
    end

    // ---- stage 1 -> 2: tile pixel fetch -------------------------------
    bg_tile_rom u_tiles (
        .clk   (clk),
        .addr  ({tile[4:0], off_y_d1, off_x_d1}),
        .color (color)
    );

endmodule
