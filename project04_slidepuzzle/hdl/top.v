//------------------------------------------------------------------------------
// top.v
//
// AX7010 top for the image slide puzzle (course 2110597, 4th project). It
// holds the same puzzle_core as the VGA Playground build (src/) and adds the
// board's ends: the clock, the buttons, and HDMI out at 640x480@60 with full
// 24-bit colour.
//
// sys_clk       : 50 MHz onboard oscillator (pin U18)
// clk_wiz_video : 50 MHz -> 25.175 MHz pixel clock + 125.875 MHz (5x) serial clock
// puzzle_core   : the game and the renderer (src/puzzle_core.v)
// hdmi_tx       : RGB -> TMDS encode + OSERDES serialize (pure Verilog)
//
// Controls. The board's four buttons are the four directions. A press moves
// the tile next to the gap that way, into the gap. On the title screen, any
// press starts a game.
//   key[0] up    key[1] down    key[2] left    key[3] right
//   up + down together     : reshuffle (a new game)
//   left + right, held     : peek at the finished picture
// The five optional buttons on J10 (the same wiring as project01b) work
// alongside the board's. ext_key[4] is a real start button there, so the
// chord is not needed.
//------------------------------------------------------------------------------
module top(
    input  wire       sys_clk,     // 50 MHz onboard oscillator
    input  wire [3:0] key,         // up, down, left, right - active-low
    input  wire [4:0] ext_key,     // J10: up, down, left, right, start - active-low, pulled up
    output wire       hdmi_oen,
    output wire       TMDS_clk_p,
    output wire       TMDS_clk_n,
    output wire [2:0] TMDS_data_p,
    output wire [2:0] TMDS_data_n
);

wire pixel_clk;    // 25.175 MHz - 640x480 pixel clock
wire serial_clk;   // 125.875 MHz - 5x pixel clock, for TMDS serialization
wire clk_locked;

clk_wiz_video u_clk_wiz (
    .clk_in1  (sys_clk),
    .clk_out1 (pixel_clk),
    .clk_out2 (serial_clk),
    .reset    (1'b0),
    .locked   (clk_locked)
);

// hold the game in reset for a few clocks after the clock settles
reg [3:0] por = 4'd0;
always @(posedge pixel_clk)
    if (!clk_locked)   por <= 4'd0;
    else if (!(&por))  por <= por + 4'd1;
wire rst = ~(&por);

// ---- buttons
wire [3:0] key_p;
wire [4:0] ext_p;

pad_input #(.WIDTH(4)) u_keys (.clk(pixel_clk), .key(key),     .pressed(key_p));
pad_input #(.WIDTH(5)) u_ext  (.clk(pixel_clk), .key(ext_key), .pressed(ext_p));

wire [3:0] dir   = key_p | ext_p[3:0];          // {right, left, down, up}
wire       chord = dir[0] & dir[1];             // up + down
wire       start = ext_p[4] | chord;

reg  [3:0] dir_prev   = 4'd0;
reg        start_prev = 1'b0;
always @(posedge pixel_clk) begin
    dir_prev   <= dir;
    start_prev <= start;
end
wire [3:0] dir_down   = dir & ~dir_prev;
wire       start_down = start & ~start_prev;

// ---- the game
wire [7:0] vid_r, vid_g, vid_b;
wire       vid_hs, vid_vs, vid_de;
wire       t_hs, t_vs, t_blank;
wire [9:0] t_x, t_y;
wire [2:0] game_state;

vga_timing u_timing (
    .clk   (pixel_clk),
    .HS    (t_hs),
    .VS    (t_vs),
    .x     (t_x),
    .y     (t_y),
    .blank (t_blank)
);

puzzle_core u_core (
    .clk         (pixel_clk),
    .rst         (rst),
    .x           (t_x),
    .y           (t_y),
    .hs_in       (t_hs),
    .vs_in       (t_vs),
    .blank_in    (t_blank),
    // the second button of a chord does not move a tile as well
    .press_up    (dir_down[0] & ~dir[1]),
    .press_down  (dir_down[1] & ~dir[0]),
    .press_left  (dir_down[2] & ~dir[3]),
    .press_right (dir_down[3] & ~dir[2]),
    .press_start (start_down),
    .peek        (dir[2] & dir[3]),
    .r           (vid_r),
    .g           (vid_g),
    .b           (vid_b),
    .hs          (vid_hs),
    .vs          (vid_vs),
    .de          (vid_de),
    .game_state  (game_state)
);

hdmi_tx u_hdmi_tx (
    .pixel_clk   (pixel_clk),
    .serial_clk  (serial_clk),
    .rst         (~clk_locked),

    .vid_r       (vid_r),
    .vid_g       (vid_g),
    .vid_b       (vid_b),
    .vid_hsync   (vid_hs),
    .vid_vsync   (vid_vs),
    .vid_de      (vid_de),

    .TMDS_clk_p  (TMDS_clk_p),
    .TMDS_clk_n  (TMDS_clk_n),
    .TMDS_data_p (TMDS_data_p),
    .TMDS_data_n (TMDS_data_n),
    .hdmi_oen    (hdmi_oen)
);

endmodule
