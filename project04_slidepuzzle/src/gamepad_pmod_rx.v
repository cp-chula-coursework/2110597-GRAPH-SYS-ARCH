//------------------------------------------------------------------------------
// gamepad_pmod_rx.v
//
// Receiver for the Tiny Tapeout Gamepad Pmod, which is also what the VGA
// Playground's "Gamepad" mode drives: arrow keys, plus a/b/x/y, s (select),
// t (start), l and r.
//
// The Pmod is a shift register on three wires. Every pulse on CLK carries one
// bit on DATA, and a pulse on LATCH ends the packet. Each packet is 24 bits:
// two 12-bit controllers, with the first controller sent last. Keeping only
// the last 12 bits shifted in therefore leaves the first controller, in the
// order
//
//     btn[11..0] = { b, y, select, start, up, down, left, right, a, x, l, r }
//
// When no controller is connected, every bit reads 1. All twelve set at once
// therefore means "no pad", and the buttons are reported as released.
//
// This is a fresh implementation of that protocol, written to the behaviour of
// the playground's InputController.ts:
//   - one step per scanline
//   - CLK high on odd steps 1..47, so 24 rising edges
//   - DATA changes on the even steps
//   - LATCH high on step 49
// The inputs are asynchronous to clk and go through two flip-flops each.
//------------------------------------------------------------------------------
`default_nettype none

module gamepad_pmod_rx (
    input  wire        clk,
    input  wire        rst,          // synchronous, active-high
    input  wire        pmod_data,
    input  wire        pmod_clk,
    input  wire        pmod_latch,
    output wire [11:0] btn,          // active-high, see order above
    output wire        present
);

    reg [1:0]  data_s, clk_s, latch_s;
    reg        clk_prev, latch_prev;
    reg [11:0] shift;
    reg [11:0] packet;

    always @(posedge clk) begin
        data_s  <= {data_s[0],  pmod_data};
        clk_s   <= {clk_s[0],   pmod_clk};
        latch_s <= {latch_s[0], pmod_latch};
        clk_prev   <= clk_s[1];
        latch_prev <= latch_s[1];

        if (rst) begin
            shift  <= 12'hfff;
            packet <= 12'hfff;
        end else begin
            if (clk_s[1] && !clk_prev)
                shift <= {shift[10:0], data_s[1]};
            if (latch_s[1] && !latch_prev)
                packet <= shift;
        end
    end

    assign present = (packet != 12'hfff);
    assign btn     = present ? packet : 12'h000;

endmodule

`default_nettype wire
