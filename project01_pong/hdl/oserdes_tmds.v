//------------------------------------------------------------------------------
// oserdes_tmds.v
//
// Serializes a 10-bit TMDS symbol (LSB first) to a single differential pair
// using a cascaded MASTER/SLAVE OSERDESE2 pair in DDR mode (7-series 10:1
// serialization) plus an OBUFDS output buffer, per Xilinx UG471.
//
// This is a direct Verilog port of Digilent's OutputSERDES.vhd (BSD
// 3-clause, (c) 2014 Digilent Incorporated) - same D-pin mapping, same
// bit-reversal, same cascade wiring.
//------------------------------------------------------------------------------
module oserdes_tmds (
    input  wire       pixel_clk,   // CLKDIV: 1x pixel clock
    input  wire       serial_clk,  // CLK: 5x pixel clock
    input  wire       rst,
    input  wire [9:0] data_in,     // TMDS-encoded symbol, bit 0 sent first
    output wire        tmds_p,
    output wire        tmds_n
);

    wire serial_out;
    wire cascade1, cascade2;

    OBUFDS #(
        .IOSTANDARD("TMDS_33")
    ) obufds_inst (
        .O  (tmds_p),
        .OB (tmds_n),
        .I  (serial_out)
    );

    // Re-order so DVI's LSB-first bit stream lines up with OSERDESE2's
    // D1-first shift order. data_q[3:0] are unused padding bits inherent to
    // the 10:1 DDR MASTER/SLAVE cascade (see UG471) and are tied low.
    wire [13:0] data_q;
    assign data_q[13] = data_in[0];
    assign data_q[12] = data_in[1];
    assign data_q[11] = data_in[2];
    assign data_q[10] = data_in[3];
    assign data_q[9]  = data_in[4];
    assign data_q[8]  = data_in[5];
    assign data_q[7]  = data_in[6];
    assign data_q[6]  = data_in[7];
    assign data_q[5]  = data_in[8];
    assign data_q[4]  = data_in[9];
    assign data_q[3]  = 1'b0;
    assign data_q[2]  = 1'b0;
    assign data_q[1]  = 1'b0;
    assign data_q[0]  = 1'b0;

    OSERDESE2 #(
        .DATA_RATE_OQ   ("DDR"),
        .DATA_RATE_TQ   ("SDR"),
        .DATA_WIDTH     (10),
        .TRISTATE_WIDTH (1),
        .TBYTE_CTL      ("FALSE"),
        .TBYTE_SRC      ("FALSE"),
        .SERDES_MODE    ("MASTER")
    ) oserdes_master (
        .OFB       (),
        .OQ        (serial_out),
        .SHIFTOUT1 (),
        .SHIFTOUT2 (),
        .TBYTEOUT  (),
        .TFB       (),
        .TQ        (),
        .CLK       (serial_clk),
        .CLKDIV    (pixel_clk),
        .D1        (data_q[13]),
        .D2        (data_q[12]),
        .D3        (data_q[11]),
        .D4        (data_q[10]),
        .D5        (data_q[9]),
        .D6        (data_q[8]),
        .D7        (data_q[7]),
        .D8        (data_q[6]),
        .OCE       (1'b1),
        .RST       (rst),
        .SHIFTIN1  (cascade1),
        .SHIFTIN2  (cascade2),
        .T1        (1'b0),
        .T2        (1'b0),
        .T3        (1'b0),
        .T4        (1'b0),
        .TBYTEIN   (1'b0),
        .TCE       (1'b0)
    );

    OSERDESE2 #(
        .DATA_RATE_OQ   ("DDR"),
        .DATA_RATE_TQ   ("SDR"),
        .DATA_WIDTH     (10),
        .TRISTATE_WIDTH (1),
        .TBYTE_CTL      ("FALSE"),
        .TBYTE_SRC      ("FALSE"),
        .SERDES_MODE    ("SLAVE")
    ) oserdes_slave (
        .OFB       (),
        .OQ        (),
        .SHIFTOUT1 (cascade1),
        .SHIFTOUT2 (cascade2),
        .TBYTEOUT  (),
        .TFB       (),
        .TQ        (),
        .CLK       (serial_clk),
        .CLKDIV    (pixel_clk),
        .D1        (1'b0),
        .D2        (1'b0),
        .D3        (data_q[5]),
        .D4        (data_q[4]),
        .D5        (data_q[3]),
        .D6        (data_q[2]),
        .D7        (data_q[1]),
        .D8        (data_q[0]),
        .OCE       (1'b1),
        .RST       (rst),
        .SHIFTIN1  (1'b0),
        .SHIFTIN2  (1'b0),
        .T1        (1'b0),
        .T2        (1'b0),
        .T3        (1'b0),
        .T4        (1'b0),
        .TBYTEIN   (1'b0),
        .TCE       (1'b0)
    );

endmodule
