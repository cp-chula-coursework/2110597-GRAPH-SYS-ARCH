//------------------------------------------------------------------------------
// top.v
//
// AX7010 Pong: 640x480@60 Pong game (course DT181/2110597 first project) over
// the board's HDMI connector.
//
// sys_clk       : 50 MHz onboard oscillator (pin U18)
// clk_wiz_video : 50 MHz -> 25.175 MHz pixel clock + 125.875 MHz (5x) serial clock
// vga_timing    : 640x480@60 sync/blanking/pixel-coordinate generator
// pong          : game logic + score + rendering (4-bit/channel RGB)
// hdmi_tx       : RGB -> TMDS encode + OSERDES serialize (pure Verilog)
//
// The board's 4 push buttons (key[0..3]) are active-low (idle=1, pressed=0);
// they are synchronized into the pixel-clock domain and inverted here so the
// game logic (ported from course slides, which assume active-high buttons)
// sees btn_reset/btn_up/btn_dn = 1 while pressed.
//------------------------------------------------------------------------------
module top(
    input  wire sys_clk,           // 50 MHz onboard oscillator
    input  wire [3:0] key,         // key[0]=reset key[1]=up key[2]=down key[3]=spare, active-low
    output wire hdmi_oen,
    output wire TMDS_clk_p,
    output wire TMDS_clk_n,
    output wire [2:0] TMDS_data_p,
    output wire [2:0] TMDS_data_n
);

wire pixel_clk;    // 25.175 MHz - 640x480 pixel clock
wire serial_clk;   // 125.875 MHz - 5x pixel clock, for TMDS serialization
wire clk_locked;

wire video_hs, video_vs, video_blank;
wire [9:0] video_x, video_y;
wire [3:0] pong_r, pong_g, pong_b;

clk_wiz_video u_clk_wiz (
    .clk_in1  (sys_clk),
    .clk_out1 (pixel_clk),
    .clk_out2 (serial_clk),
    .reset    (1'b0),
    .locked   (clk_locked)
);

vga_timing u_vga_timing (
    .clk   (pixel_clk),
    .HS    (video_hs),
    .VS    (video_vs),
    .x     (video_x),
    .y     (video_y),
    .blank (video_blank)
);

// Synchronize the async, active-low buttons into pixel_clk and invert to
// active-high for the game logic.
reg [3:0] key_sync0, key_sync1;
always @(posedge pixel_clk) begin
    key_sync0 <= key;
    key_sync1 <= key_sync0;
end
wire btn_reset = ~key_sync1[0];
wire btn_up    = ~key_sync1[1];
wire btn_dn    = ~key_sync1[2];

pong u_pong (
    .clk       (pixel_clk),
    .VS        (video_vs),
    .btn_reset (btn_reset),
    .btn_up    (btn_up),
    .btn_dn    (btn_dn),
    .x         (video_x),
    .y         (video_y),
    .RED       (pong_r),
    .GREEN     (pong_g),
    .BLUE      (pong_b)
);

// 4-bit-per-channel game colour -> 8-bit-per-channel HDMI, via bit
// replication (so max intensity 4'hF maps to 8'hFF, not 8'hF0), zeroed
// during blanking.
wire [7:0] hdmi_r = video_blank ? 8'h00 : {pong_r, pong_r};
wire [7:0] hdmi_g = video_blank ? 8'h00 : {pong_g, pong_g};
wire [7:0] hdmi_b = video_blank ? 8'h00 : {pong_b, pong_b};

hdmi_tx u_hdmi_tx (
    .pixel_clk   (pixel_clk),
    .serial_clk  (serial_clk),
    .rst         (~clk_locked),

    .vid_r       (hdmi_r),
    .vid_g       (hdmi_g),
    .vid_b       (hdmi_b),
    .vid_hsync   (video_hs),
    .vid_vsync   (video_vs),
    .vid_de      (~video_blank),

    .TMDS_clk_p  (TMDS_clk_p),
    .TMDS_clk_n  (TMDS_clk_n),
    .TMDS_data_p (TMDS_data_p),
    .TMDS_data_n (TMDS_data_n),
    .hdmi_oen    (hdmi_oen)
);

endmodule
