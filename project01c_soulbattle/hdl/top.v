//------------------------------------------------------------------------------
// top.v
//
// AX7010 SOUL BATTLE - PURE LOGIC (course 2110597, 1st Gen console project):
// the same hardwired, RPG-style bullet-hell battle as project01b, rebuilt
// without a single stored image. No CPU, no software, no frame buffer and now
// no ROM either: the soul, the enemy, the skulls and the HUD are all drawn by
// comparing the beam position against arithmetic, which is the only kind of
// graphics 1st generation hardware could do. The whole turn machine is a
// state machine that runs once per frame during vertical blanking.
//
// sys_clk       : 50 MHz onboard oscillator (pin U18)
// clk_wiz_video : 50 MHz -> 25.175 MHz pixel clock + 125.875 MHz (5x) serial clock
// battle_core   : timing + shape/bullet/HUD renderers + game logic + compositor
// hdmi_tx       : RGB -> TMDS encode + OSERDES serialize (pure Verilog)
//
// The board's 4 push buttons (key[0..3]) are active-low; battle_core
// synchronizes and debounces them internally. A PlayStation controller can
// also be wired to the expansion header - see the README for pins; with
// nothing plugged in those pins just idle and the buttons still play.
//------------------------------------------------------------------------------
module top(
    input  wire sys_clk,           // 50 MHz onboard oscillator
    input  wire [3:0] key,         // key[0]=up key[1]=down key[2]=left key[3]=right, active-low
    input  wire [4:0] ext_key,     // optional buttons on expansion header J10
    input  wire uart_rx_pin,       // PS2-to-serial adapter TXD, on J10 too
    input  wire ps2_dat,           // PlayStation controller on the expansion header
    output wire ps2_att,
    output wire ps2_clk,
    output wire ps2_cmd,
    output wire [3:0] led,         // active-low player HP meter, see battle_core
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

battle_core u_core (
    .clk     (pixel_clk),
    .key     (key),
    .ext_key (ext_key),
    .uart_rx_pin (uart_rx_pin),
    .ps2_dat (ps2_dat),
    .ps2_att (ps2_att),
    .ps2_clk (ps2_clk),
    .ps2_cmd (ps2_cmd),
    .led     (led),
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
