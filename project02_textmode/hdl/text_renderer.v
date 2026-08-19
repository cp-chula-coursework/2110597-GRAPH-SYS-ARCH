//------------------------------------------------------------------------------
// text_renderer.v
//
// Text-mode pixel pipeline, per the course slides' text_screen_gen: for each
// pixel, look up the character code in the tile RAM (1 clk), feed it to the
// font ROM (1 clk), then select the pixel's bit out of the returned glyph
// row. Character cells are 8x16, so 640x480 shows 80x30 characters:
//
//   column     = x[9:3]     glyph column (bit) = x[2:0]
//   row        = y[8:4]     glyph row          = y[3:0]
//
// The tile RAM lives outside this module (there are two of them - editor
// text and screensaver - muxed by the mode logic), so this module outputs
// the fetch address and takes the fetched cell back in one clock later.
//
// Total latency is 2 clocks; instead of pre-fetching ahead of the beam, the
// sync/blank flags ride the same 2-stage pipeline so RGB and syncs leave the
// module aligned (the whole frame is just shifted 2 pixel clocks, which is
// invisible). The cursor overlay inverts its cell's pixels (a blinking block
// cursor) while cursor_blink is high, per the slides.
//------------------------------------------------------------------------------
module text_renderer (
    input  wire        clk,          // pixel clock

    // raw timing from vga_timing (counters include the blanking region)
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire        hs_in,
    input  wire        vs_in,
    input  wire        blank_in,

    // tile RAM fetch (data returns 1 clock after addr)
    output wire [11:0] tile_addr,
    input  wire [7:0]  tile_data,    // {bright, ascii[6:0]}

    // block cursor overlay
    input  wire        cursor_en,
    input  wire [6:0]  cursor_x,     // 0..79
    input  wire [4:0]  cursor_y,     // 0..29
    input  wire        cursor_blink, // 1 = cursor cell inverted this frame

    // video out, aligned with each other (2 clks behind x/y)
    output wire [7:0]  vid_r,
    output wire [7:0]  vid_g,
    output wire [7:0]  vid_b,
    output wire        vid_hs,
    output wire        vid_vs,
    output wire        vid_de
);

    // Green-phosphor palette; bright is used for matrix-rain stream heads.
    localparam [23:0] FG_NORMAL = 24'h00C830;
    localparam [23:0] FG_BRIGHT = 24'hC8FFC8;

    //--------------------------------------------------------------------------
    // Stage 0 (combinational): tile address from the raw beam position
    //--------------------------------------------------------------------------
    wire [6:0] col = x[9:3];
    wire [4:0] row = y[8:4];
    assign tile_addr = {7'd0, row} * 12'd80 + {5'd0, col};

    //--------------------------------------------------------------------------
    // Stage 1: tile RAM registers tile_addr on this edge; carry along the
    // in-glyph coordinates, syncs, and cursor-cell match
    //--------------------------------------------------------------------------
    reg [3:0] glyph_row_d1;
    reg [2:0] glyph_col_d1;
    reg       hs_d1, vs_d1, de_d1, cur_d1;

    always @(posedge clk) begin
        glyph_row_d1 <= y[3:0];
        glyph_col_d1 <= x[2:0];
        hs_d1        <= hs_in;
        vs_d1        <= vs_in;
        de_d1        <= ~blank_in;
        cur_d1       <= cursor_en && (col == cursor_x) && (row == cursor_y);
    end

    //--------------------------------------------------------------------------
    // Stage 2: font ROM registers its address on this edge (tile_data is the
    // RAM output, valid during stage 1); carry the rest along one more clock
    //--------------------------------------------------------------------------
    wire [7:0] font_word;

    font_rom u_font_rom (
        .clk  (clk),
        .addr ({tile_data[6:0], glyph_row_d1}),
        .data (font_word)
    );

    reg [2:0] glyph_col_d2;
    reg       hs_d2, vs_d2, de_d2, cur_d2, bright_d2;

    always @(posedge clk) begin
        glyph_col_d2 <= glyph_col_d1;
        hs_d2        <= hs_d1;
        vs_d2        <= vs_d1;
        de_d2        <= de_d1;
        cur_d2       <= cur_d1;
        bright_d2    <= tile_data[7];
    end

    //--------------------------------------------------------------------------
    // Output: pick the glyph bit (MSB = leftmost pixel), invert under the
    // blinking cursor, apply the palette
    //--------------------------------------------------------------------------
    wire font_bit = font_word[3'd7 - glyph_col_d2];
    wire pixel_on = font_bit ^ (cur_d2 & cursor_blink);

    wire [23:0] fg = bright_d2 ? FG_BRIGHT : FG_NORMAL;

    assign {vid_r, vid_g, vid_b} = (de_d2 && pixel_on) ? fg : 24'h000000;
    assign vid_hs = hs_d2;
    assign vid_vs = vs_d2;
    assign vid_de = de_d2;

endmodule
