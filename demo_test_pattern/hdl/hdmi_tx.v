//------------------------------------------------------------------------------
// hdmi_tx.v
//
// Drives a DVI/HDMI TMDS link (clock + 3 data channels) from RGB video
// timing signals: one tmds_encoder + oserdes_tmds pair per data channel,
// plus a fixed-pattern clock-channel serializer.
//
// Channel mapping matches the DVI 1.0 spec convention used by Digilent's
// rgb2dvi core: channel 0 = blue (also carries hsync/vsync during
// blanking), channel 1 = green, channel 2 = red.
//------------------------------------------------------------------------------
module hdmi_tx (
    input  wire       pixel_clk,   // 1x pixel clock
    input  wire       serial_clk,  // 5x pixel clock
    input  wire       rst,         // async reset, active-high

    input  wire [7:0] vid_r,
    input  wire [7:0] vid_g,
    input  wire [7:0] vid_b,
    input  wire       vid_hsync,
    input  wire       vid_vsync,
    input  wire       vid_de,

    output wire        TMDS_clk_p,
    output wire        TMDS_clk_n,
    output wire [2:0]  TMDS_data_p,
    output wire [2:0]  TMDS_data_n,
    output wire        hdmi_oen
);

    assign hdmi_oen = 1'b1;

    // TMDS clock channel: fixed pattern -> one clean square wave per pixel period
    oserdes_tmds u_clk_serdes (
        .pixel_clk  (pixel_clk),
        .serial_clk (serial_clk),
        .rst        (rst),
        .data_in    (10'b1111100000),
        .tmds_p     (TMDS_clk_p),
        .tmds_n     (TMDS_clk_n)
    );

    // Channel 0: blue, carries hsync/vsync during blanking
    wire [9:0] tmds_data0;
    tmds_encoder u_enc0 (
        .pixel_clk (pixel_clk),
        .data      (vid_b),
        .c0        (vid_hsync),
        .c1        (vid_vsync),
        .de        (vid_de),
        .q_out     (tmds_data0)
    );
    oserdes_tmds u_serdes0 (
        .pixel_clk  (pixel_clk),
        .serial_clk (serial_clk),
        .rst        (rst),
        .data_in    (tmds_data0),
        .tmds_p     (TMDS_data_p[0]),
        .tmds_n     (TMDS_data_n[0])
    );

    // Channel 1: green
    wire [9:0] tmds_data1;
    tmds_encoder u_enc1 (
        .pixel_clk (pixel_clk),
        .data      (vid_g),
        .c0        (1'b0),
        .c1        (1'b0),
        .de        (vid_de),
        .q_out     (tmds_data1)
    );
    oserdes_tmds u_serdes1 (
        .pixel_clk  (pixel_clk),
        .serial_clk (serial_clk),
        .rst        (rst),
        .data_in    (tmds_data1),
        .tmds_p     (TMDS_data_p[1]),
        .tmds_n     (TMDS_data_n[1])
    );

    // Channel 2: red
    wire [9:0] tmds_data2;
    tmds_encoder u_enc2 (
        .pixel_clk (pixel_clk),
        .data      (vid_r),
        .c0        (1'b0),
        .c1        (1'b0),
        .de        (vid_de),
        .q_out     (tmds_data2)
    );
    oserdes_tmds u_serdes2 (
        .pixel_clk  (pixel_clk),
        .serial_clk (serial_clk),
        .rst        (rst),
        .data_in    (tmds_data2),
        .tmds_p     (TMDS_data_p[2]),
        .tmds_n     (TMDS_data_n[2])
    );

endmodule
