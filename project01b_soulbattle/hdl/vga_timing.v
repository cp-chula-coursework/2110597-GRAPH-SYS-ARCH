//------------------------------------------------------------------------------
// vga_timing.v
//
// Standard VESA 640x480@60 video timing generator (25.175 MHz pixel clock).
// Produces free-running pixel coordinates (x,y), sync pulses, and a blanking
// flag. x/y count through the full line/frame including blanking (0..799,
// 0..524) - game/graphics logic only needs to compare against the active
// 0..639 / 0..479 range, so this never needs to be clipped.
//------------------------------------------------------------------------------
module vga_timing (
    input  wire       clk,     // 25.175 MHz pixel clock
    output wire        HS,
    output wire        VS,
    output wire [9:0]  x,
    output wire [9:0]  y,
    output wire        blank
);

    localparam H_ACTIVE = 640;
    localparam H_FP     = 16;
    localparam H_SYNC   = 96;
    localparam H_BP     = 48;
    localparam H_TOTAL  = H_ACTIVE + H_FP + H_SYNC + H_BP; // 800

    localparam V_ACTIVE = 480;
    localparam V_FP     = 10;
    localparam V_SYNC   = 2;
    localparam V_BP     = 33;
    localparam V_TOTAL  = V_ACTIVE + V_FP + V_SYNC + V_BP; // 525

    reg [9:0] h_cnt = 10'd0;
    reg [9:0] v_cnt = 10'd0;

    always @(posedge clk) begin
        if (h_cnt == H_TOTAL - 1) begin
            h_cnt <= 10'd0;
            if (v_cnt == V_TOTAL - 1)
                v_cnt <= 10'd0;
            else
                v_cnt <= v_cnt + 10'd1;
        end else begin
            h_cnt <= h_cnt + 10'd1;
        end
    end

    assign x = h_cnt;
    assign y = v_cnt;

    // VESA 640x480@60 uses negative sync polarity
    assign HS = ~((h_cnt >= H_ACTIVE + H_FP) && (h_cnt < H_ACTIVE + H_FP + H_SYNC));
    assign VS = ~((v_cnt >= V_ACTIVE + V_FP) && (v_cnt < V_ACTIVE + V_FP + V_SYNC));

    assign blank = (h_cnt >= H_ACTIVE) || (v_cnt >= V_ACTIVE);

endmodule
