//------------------------------------------------------------------------------
// tb_uart_rx.v
//
// Shifts bytes into uart_rx the way a real transmitter does - one start bit,
// eight data bits LSB first, one stop bit, all at a bit period the bench sets
// itself - and checks that what comes out the other side is what went in.
//
// What it proves:
//   - bytes are received correctly, LSB first, back to back
//   - the whole 8-byte packet the PS2-to-serial adapter sends arrives intact
//     and in order (73 .. 5a)
//   - a bit period a few percent away from the receiver's still works, which
//     is what sampling in the middle of each bit buys
//   - a frame with no stop bit is dropped and counted rather than passed on,
//     so a wrong baud rate shows up as errors instead of as garbage data
//   - a glitch on an idle line does not start a frame
//
//   iverilog -o /tmp/tb_uart.vvp hdl/uart_rx.v sim/tb_uart_rx.v
//   vvp /tmp/tb_uart.vvp
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_uart_rx;

    localparam CLKS_PER_BIT = 219;          // 115200 at 25.175 MHz
    localparam real TCLK    = 39.722;       // ns

    reg clk = 1'b0;
    always #(TCLK/2.0) clk = ~clk;

    reg  rx = 1'b1;
    reg  [12:0] clks_per_bit = CLKS_PER_BIT;
    reg  err_clear = 1'b0;
    wire [7:0]  data;
    wire        valid;
    wire [7:0]  errors;

    uart_rx dut (
        .clk (clk), .rx (rx), .clks_per_bit (clks_per_bit),
        .err_clear (err_clear),
        .data (data), .valid (valid), .errors (errors)
    );

    integer errs = 0;

    task check(input cond, input [8*64-1:0] msg);
        if (!cond) begin
            errs = errs + 1;
            $display("FAIL: %0s", msg);
        end
    endtask

    // send one byte at `bit_clks` clocks per bit, with or without a stop bit
    task send(input [7:0] b, input integer bit_clks, input stop_ok);
        integer i;
        begin
            rx = 1'b0;                                   // start
            repeat (bit_clks) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin          // LSB first
                rx = b[i];
                repeat (bit_clks) @(posedge clk);
            end
            rx = stop_ok ? 1'b1 : 1'b0;                  // stop
            repeat (bit_clks) @(posedge clk);
            rx = 1'b1;
            repeat (4) @(posedge clk);
        end
    endtask

    reg [7:0] got [0:15];
    integer   n_got = 0;

    always @(posedge clk) if (valid) begin
        got[n_got] = data;
        n_got = n_got + 1;
    end

    integer i;

    initial begin
        #200_000_000;
        $display("FAIL: watchdog timeout");
        $finish;
    end

    initial begin
        repeat (20) @(posedge clk);

        // ---- one byte --------------------------------------------------
        send(8'h73, CLKS_PER_BIT, 1'b1);
        check(n_got == 1, "a single byte did not arrive");
        check(got[0] == 8'h73, "a single byte arrived wrong");

        // ---- the adapter's whole packet, back to back ------------------
        n_got = 0;
        send(8'h73, CLKS_PER_BIT, 1'b1);   // start marker
        send(8'hFF, CLKS_PER_BIT, 1'b1);   // buttons 1
        send(8'hEF, CLKS_PER_BIT, 1'b1);   // buttons 2
        send(8'h80, CLKS_PER_BIT, 1'b1);   // right stick x
        send(8'h7F, CLKS_PER_BIT, 1'b1);   // right stick y
        send(8'h00, CLKS_PER_BIT, 1'b1);   // left stick x
        send(8'hFF, CLKS_PER_BIT, 1'b1);   // left stick y
        send(8'h5A, CLKS_PER_BIT, 1'b1);   // end marker
        check(n_got == 8, "the 8-byte packet did not all arrive");
        check(got[0] == 8'h73 && got[7] == 8'h5A,
              "the packet's start and end markers are wrong");
        check(got[1] == 8'hFF && got[2] == 8'hEF && got[3] == 8'h80 &&
              got[4] == 8'h7F && got[5] == 8'h00 && got[6] == 8'hFF,
              "the packet's payload came out in the wrong order");

        // ---- a transmitter 3% fast, and one 3% slow --------------------
        n_got = 0;
        send(8'hA5, (CLKS_PER_BIT * 97) / 100, 1'b1);
        send(8'h5A, (CLKS_PER_BIT * 103) / 100, 1'b1);
        check(n_got == 2 && got[0] == 8'hA5 && got[1] == 8'h5A,
              "a few percent of baud error broke reception");

        // ---- a frame with no stop bit is dropped, not passed on --------
        n_got = 0;
        i = errors;
        send(8'h3C, CLKS_PER_BIT, 1'b0);
        check(n_got == 0, "a frame with no stop bit was passed on anyway");
        check(errors == i + 1, "a bad frame was not counted");

        // ---- the error count can be restarted --------------------------
        // Without this it sticks at whatever the last wrong baud rate ran it
        // up to, and stops saying anything about the rate being tried now.
        check(errors != 8'h00, "no errors to clear");
        @(posedge clk); #1 err_clear = 1'b1;
        @(posedge clk); #1 err_clear = 1'b0;
        repeat (4) @(posedge clk);
        check(errors == 8'h00, "err_clear did not restart the count");

        // ---- a glitch on an idle line starts nothing -------------------
        n_got = 0;
        i = errors;
        rx = 1'b1;  repeat (CLKS_PER_BIT * 2) @(posedge clk);
        rx = 1'b0;  repeat (CLKS_PER_BIT / 8) @(posedge clk);
        rx = 1'b1;  repeat (CLKS_PER_BIT * 12) @(posedge clk);
        check(n_got == 0 && errors == i, "a glitch was taken for a start bit");

        // ---- and it still works afterwards ------------------------------
        n_got = 0;
        send(8'h73, CLKS_PER_BIT, 1'b1);
        check(n_got == 1 && got[0] == 8'h73, "the receiver did not recover");

        if (errs == 0) $display("ALL TESTS PASSED");
        else           $display("%0d TEST(S) FAILED", errs);
        $finish;
    end

endmodule
