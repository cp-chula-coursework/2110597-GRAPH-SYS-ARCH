//------------------------------------------------------------------------------
// tmds_encoder.v
//
// DVI 1.0 TMDS 8b/10b encoder for one colour channel: minimizes transitions
// (XOR/XNOR choice) then balances running DC disparity, per the DVI 1.0 spec
// algorithm (Figure 3-5). 3-cycle latency, pixel_clk domain throughout.
//
// This is a direct Verilog port of the same algorithm used by Digilent's
// open-source rgb2dvi core (TMDS_Encoder.vhd, BSD 3-clause,
// (c) 2014 Digilent Incorporated).
//------------------------------------------------------------------------------
module tmds_encoder (
    input  wire       pixel_clk,
    input  wire [7:0] data,    // unencoded 8-bit video data
    input  wire       c0,      // control bit 0 (e.g. hsync)
    input  wire       c1,      // control bit 1 (e.g. vsync)
    input  wire       de,      // video data enable (1 = active video)
    output reg  [9:0] q_out    // TMDS-encoded 10-bit symbol
);

    function [3:0] popcount8;
        input [7:0] v;
        integer k;
        begin
            popcount8 = 4'd0;
            for (k = 0; k < 8; k = k + 1)
                popcount8 = popcount8 + v[k];
        end
    endfunction

    // ---- Stage 1: register inputs, count set bits in raw data ----
    reg [7:0] data_1;
    reg       c0_1, c1_1, de_1;
    reg [3:0] n1d_1;

    always @(posedge pixel_clk) begin
        de_1   <= de;
        n1d_1  <= popcount8(data);
        data_1 <= data;
        c0_1   <= c0;
        c1_1   <= c1;
    end

    // Choose the XOR or XNOR minimal-transition encoding of data_1
    wire [8:0] q_m_xor;
    wire [8:0] q_m_xnor;
    assign q_m_xor[0]  = data_1[0];
    assign q_m_xnor[0] = data_1[0];
    genvar gi;
    generate
        for (gi = 1; gi < 8; gi = gi + 1) begin : gen_qm
            assign q_m_xor[gi]  = q_m_xor[gi-1]  ^  data_1[gi];
            assign q_m_xnor[gi] = q_m_xnor[gi-1] ~^ data_1[gi];
        end
    endgenerate
    assign q_m_xor[8]  = 1'b1;
    assign q_m_xnor[8] = 1'b0;

    wire [8:0] q_m_1 = (n1d_1 > 4'd4 || (n1d_1 == 4'd4 && data_1[0] == 1'b0)) ? q_m_xnor : q_m_xor;
    wire [3:0] n1q_m_1 = popcount8(q_m_1[7:0]);

    // ---- Stage 2: register q_m_1 / control / de, evaluate DC balance ----
    reg [8:0] q_m_2;
    reg [3:0] n1q_m_2, n0q_m_2;
    reg       c0_2, c1_2, de_2;

    always @(posedge pixel_clk) begin
        n1q_m_2 <= n1q_m_1;
        n0q_m_2 <= 4'd8 - n1q_m_1;
        q_m_2   <= q_m_1;
        c0_2    <= c0_1;
        c1_2    <= c1_1;
        de_2    <= de_1;
    end

    reg signed [4:0] cnt_t_3 = 5'sd0;  // running DC-bias counter

    wire cond_balanced_2     = (cnt_t_3 == 5'sd0) || (n1q_m_2 == 4'd4);
    wire cond_not_balanced_2 = ((cnt_t_3 > 5'sd0) && (n1q_m_2 > 4'd4)) ||
                                ((cnt_t_3 < 5'sd0) && (n1q_m_2 < 4'd4));

    localparam [9:0] CTL_TKN0 = 10'b1101010100;
    localparam [9:0] CTL_TKN1 = 10'b0010101011;
    localparam [9:0] CTL_TKN2 = 10'b0101010100;
    localparam [9:0] CTL_TKN3 = 10'b1010101011;

    wire [9:0] control_token_2 = (c1_2 == 1'b0 && c0_2 == 1'b0) ? CTL_TKN0 :
                                  (c1_2 == 1'b0 && c0_2 == 1'b1) ? CTL_TKN1 :
                                  (c1_2 == 1'b1 && c0_2 == 1'b0) ? CTL_TKN2 :
                                                                    CTL_TKN3;

    wire [9:0] q_out_2 =
        (de_2 == 1'b0)                          ? control_token_2 :
        (cond_balanced_2 && q_m_2[8] == 1'b0)   ? {~q_m_2[8], q_m_2[8], ~q_m_2[7:0]} :
        (cond_balanced_2 && q_m_2[8] == 1'b1)   ? {~q_m_2[8], q_m_2[8],  q_m_2[7:0]} :
        (cond_not_balanced_2)                   ? { 1'b1,     q_m_2[8], ~q_m_2[7:0]} :
                                                   { 1'b0,     q_m_2[8],  q_m_2[7:0]};

    wire signed [4:0] dc_bias_2 = $signed({1'b0, n0q_m_2}) - $signed({1'b0, n1q_m_2});
    wire signed [4:0] disparity_term  = q_m_2[8] ? 5'sd2 : 5'sd0; // "+2" when q_m_2(8)
    wire signed [4:0] disparity_term_n = q_m_2[8] ? 5'sd0 : 5'sd2; // "+2" when not q_m_2(8)

    wire signed [4:0] cnt_t_2 =
        (de_2 == 1'b0)                          ? 5'sd0 :
        (cond_balanced_2 && q_m_2[8] == 1'b0)   ? cnt_t_3 + dc_bias_2 :
        (cond_balanced_2 && q_m_2[8] == 1'b1)   ? cnt_t_3 - dc_bias_2 :
        (cond_not_balanced_2)                   ? cnt_t_3 + disparity_term + dc_bias_2 :
                                                   cnt_t_3 - disparity_term_n - dc_bias_2;

    // ---- Stage 3: registered output ----
    always @(posedge pixel_clk) begin
        cnt_t_3 <= cnt_t_2;
        q_out   <= q_out_2;
    end

endmodule
