//------------------------------------------------------------------------------
// top.v
//
// AX7010 Text Mode Display (course 2110597 second project): an 80x30
// character text mode over the board's HDMI connector, with an arcade-style
// text editor on the 4 push buttons and a "Matrix" digital-rain screensaver
// that takes over when idle. No CPU, no software - hardwired logic only.
//
// sys_clk       : 50 MHz onboard oscillator (pin U18)
// clk_wiz_video : 50 MHz -> 25.175 MHz pixel clock + 125.875 MHz (5x) serial clock
// text_system   : timing + tile RAMs + font ROM + editor/screensaver + renderer
// hdmi_tx       : RGB -> TMDS encode + OSERDES serialize (pure Verilog)
//
// The board's 4 push buttons (key[0..3]) are active-low; text_system
// synchronizes and debounces them internally.
//------------------------------------------------------------------------------
module top(
    input  wire sys_clk,           // 50 MHz onboard oscillator
    input  wire [3:0] key,         // key[0]=right key[1]=down key[2]=char+ key[3]=char-, active-low
    output wire hdmi_oen,
    output wire TMDS_clk_p,
    output wire TMDS_clk_n,
    output wire [2:0] TMDS_data_p,
    output wire [2:0] TMDS_data_n
);

wire pixel_clk;    // 25.175 MHz - 640x480 pixel clock
wire serial_clk;   // 125.875 MHz - 5x pixel clock, for TMDS serialization
wire clk_locked;

wire [7:0] vid_r, vid_g, vid_b;
wire vid_hs, vid_vs, vid_de;

clk_wiz_video u_clk_wiz (
    .clk_in1  (sys_clk),
    .clk_out1 (pixel_clk),
    .clk_out2 (serial_clk),
    .reset    (1'b0),
    .locked   (clk_locked)
);

text_system u_text_system (
    .clk    (pixel_clk),
    .key    (key),
    .vid_r  (vid_r),
    .vid_g  (vid_g),
    .vid_b  (vid_b),
    .vid_hs (vid_hs),
    .vid_vs (vid_vs),
    .vid_de (vid_de)
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
