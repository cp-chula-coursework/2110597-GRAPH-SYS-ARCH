//------------------------------------------------------------------------------
// top.v
//
// AX7010 test-pattern demo: generates a standard 8-bar HDMI colour-bar test
// pattern at 1280x720@60 and drives it out the board's HDMI connector.
//
// sys_clk    : 50 MHz onboard oscillator (pin U18)
// clk_wiz_video : 50 MHz -> 74.25 MHz pixel clock + 371.25 MHz (5x) serial clock
// color_bar  : timing generator + 8-colour bar pattern (hdl/color_bar.v)
// hdmi_tx    : RGB -> TMDS encode + OSERDES serialize (pure Verilog, hdl/hdmi_tx.v)
//------------------------------------------------------------------------------
module top(
    input  wire sys_clk,          // 50 MHz onboard oscillator
    output wire hdmi_oen,         // HDMI output enable
    output wire TMDS_clk_p,
    output wire TMDS_clk_n,
    output wire [2:0] TMDS_data_p,
    output wire [2:0] TMDS_data_n
);

wire pixel_clk;    // 74.25 MHz  - 1280x720 pixel clock
wire serial_clk;   // 371.25 MHz - 5x pixel clock, for TMDS serialization
wire clk_locked;

wire video_hs, video_vs, video_de;
wire [7:0] video_r, video_g, video_b;

clk_wiz_video u_clk_wiz (
    .clk_in1  (sys_clk),
    .clk_out1 (pixel_clk),
    .clk_out2 (serial_clk),
    .reset    (1'b0),
    .locked   (clk_locked)
);

color_bar u_color_bar (
    .clk   (pixel_clk),
    .rst   (~clk_locked),
    .hs    (video_hs),
    .vs    (video_vs),
    .de    (video_de),
    .rgb_r (video_r),
    .rgb_g (video_g),
    .rgb_b (video_b)
);

hdmi_tx u_hdmi_tx (
    .pixel_clk   (pixel_clk),
    .serial_clk  (serial_clk),
    .rst         (~clk_locked),

    .vid_r       (video_r),
    .vid_g       (video_g),
    .vid_b       (video_b),
    .vid_hsync   (video_hs),
    .vid_vsync   (video_vs),
    .vid_de      (video_de),

    .TMDS_clk_p  (TMDS_clk_p),
    .TMDS_clk_n  (TMDS_clk_n),
    .TMDS_data_p (TMDS_data_p),
    .TMDS_data_n (TMDS_data_n),
    .hdmi_oen    (hdmi_oen)
);

endmodule
