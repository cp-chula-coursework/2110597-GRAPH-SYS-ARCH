//------------------------------------------------------------------------------
// tb_top.v - the AX7010 top's button handling, at the real debounce time
//
//   cd src
//   iverilog -o /tmp/tb_top.vvp ../sim/tb_top.v ../hdl/top.v ../hdl/pad_input.v \
//            puzzle_core.v vga_timing.v
//   vvp /tmp/tb_top.vvp
//
// The Clocking Wizard and hdmi_tx are stubbed below. The wizard's IP and the
// OSERDES primitives do not exist outside Vivado, and the picture path behind
// them is already checked by tb_puzzle.v. What is tested here is everything
// top.v adds between the buttons and puzzle_core:
//   - power-on reset
//   - the debounce (5 ms, so a 2 ms blip must not register)
//   - one press per push
//   - the up+down chord as start
//   - left+right as peek
//   - the second button of a chord moving nothing
//   - the J10 buttons ORed in
// Presses are counted where they reach puzzle_core, not inferred from the
// board, because a press with no tile to move is still a press.
//------------------------------------------------------------------------------

// ---- stubs for the two blocks that only exist in Vivado
module clk_wiz_video (
    input  wire clk_in1,
    output wire clk_out1,
    output wire clk_out2,
    input  wire reset,
    output wire locked
);
    assign clk_out1 = clk_in1;
    assign clk_out2 = clk_in1;
    assign locked   = 1'b1;
endmodule

module hdmi_tx (
    input  wire       pixel_clk,
    input  wire       serial_clk,
    input  wire       rst,
    input  wire [7:0] vid_r,
    input  wire [7:0] vid_g,
    input  wire [7:0] vid_b,
    input  wire       vid_hsync,
    input  wire       vid_vsync,
    input  wire       vid_de,
    output wire       TMDS_clk_p,
    output wire       TMDS_clk_n,
    output wire [2:0] TMDS_data_p,
    output wire [2:0] TMDS_data_n,
    output wire       hdmi_oen
);
    assign TMDS_clk_p = 1'b0;  assign TMDS_clk_n = 1'b1;
    assign TMDS_data_p = 3'b000;  assign TMDS_data_n = 3'b111;
    assign hdmi_oen = 1'b1;
endmodule

module tb_top;

    localparam S_TITLE = 0, S_SHUFFLE = 1, S_PLAY = 2, S_SLIDE = 3, S_WIN = 4;
    localparam HOLD = 160000;      // > 125000-cycle debounce
    localparam BLIP = 50000;       // ~2 ms, must be filtered out

    reg clk = 1'b0;
    always #20 clk = ~clk;         // stands in for the 25.175 MHz pixel clock

    reg  [3:0] key     = 4'hf;     // active-low, released
    reg  [4:0] ext_key = 5'h1f;
    wire       hdmi_oen, TMDS_clk_p, TMDS_clk_n;
    wire [2:0] TMDS_data_p, TMDS_data_n;

    top dut (
        .sys_clk(clk), .key(key), .ext_key(ext_key), .hdmi_oen(hdmi_oen),
        .TMDS_clk_p(TMDS_clk_p), .TMDS_clk_n(TMDS_clk_n),
        .TMDS_data_p(TMDS_data_p), .TMDS_data_n(TMDS_data_n)
    );

    wire [2:0] state = dut.u_core.state;
    integer errors = 0;

    integer n_up = 0, n_down = 0, n_left = 0, n_right = 0, n_start = 0;
    reg     saw_shuffle = 0, saw_peek = 0;
    always @(posedge clk) begin
        if (dut.u_core.press_up)    n_up    = n_up + 1;
        if (dut.u_core.press_down)  n_down  = n_down + 1;
        if (dut.u_core.press_left)  n_left  = n_left + 1;
        if (dut.u_core.press_right) n_right = n_right + 1;
        if (dut.u_core.press_start) n_start = n_start + 1;
        if (state == S_SHUFFLE)     saw_shuffle = 1;
        if (dut.u_core.peek)        saw_peek = 1;
    end

    task cycles(input integer n);
        repeat (n) @(posedge clk);
    endtask

    task frames(input integer n);
        integer f;
        for (f = 0; f < n; f = f + 1) @(posedge dut.u_core.tick);
    endtask

    task clear;
        begin
            n_up = 0; n_down = 0; n_left = 0; n_right = 0; n_start = 0;
            saw_shuffle = 0; saw_peek = 0;
        end
    endtask

    task check(input [8*40:1] what, input integer got, input integer want);
        if (got != want) begin
            $display("FAIL %0s: %0d, expected %0d", what, got, want);
            errors = errors + 1;
        end else
            $display("ok   %0s: %0d", what, got);
    endtask

    task wait_play(input integer max_frames);
        integer f;
        begin
            f = 0;
            while (state != S_PLAY && f < max_frames) begin frames(1); f = f + 1; end
            if (state != S_PLAY) begin
                $display("FAIL: never reached PLAY (state %0d)", state); errors = errors + 1;
            end
        end
    endtask

    initial begin
        // power-on reset holds for 15 clocks after lock
        cycles(5);
        if (dut.rst !== 1'b1) begin $display("FAIL: not in reset at start"); errors = errors + 1; end
        cycles(30);
        if (dut.rst !== 1'b0) begin $display("FAIL: reset never released"); errors = errors + 1; end
        frames(1);
        check("state after reset is TITLE", state, S_TITLE);

        // ---- a 2 ms blip is not a press
        clear;
        key[0] = 0; cycles(BLIP); key[0] = 1; cycles(HOLD);
        check("presses from a 2 ms blip", n_up + n_start, 0);

        // ---- any key on the title starts a game
        clear;
        key[2] = 0; cycles(HOLD); key[2] = 1; cycles(HOLD);
        check("left on title: left presses", n_left, 1);
        wait_play(4);
        check("left on title: shuffled", saw_shuffle, 1);

        // ---- up, then down while up is held: one up, no down, one start
        frames(12);               // let any slide finish
        wait_play(12);
        clear;
        key[0] = 0; cycles(HOLD);
        key[1] = 0; cycles(HOLD);
        key[0] = 1; key[1] = 1; cycles(HOLD);
        check("chord: up presses", n_up, 1);
        check("chord: down presses", n_down, 0);
        check("chord: start presses", n_start, 1);
        frames(14);               // the up's slide, if any, then the shuffle
        wait_play(4);
        check("chord: reshuffled", saw_shuffle, 1);

        // ---- left, then right while left is held: peek, one left, no right
        frames(12);
        wait_play(12);
        clear;
        key[2] = 0; cycles(HOLD);
        key[3] = 0; cycles(HOLD);
        check("peek held: peek on", dut.u_core.peek, 1);
        key[2] = 1; key[3] = 1; cycles(HOLD);
        check("peek: left presses", n_left, 1);
        check("peek: right presses", n_right, 0);
        check("peek released: peek off", dut.u_core.peek, 0);

        // ---- J10: a direction and the start button
        frames(12);
        wait_play(12);
        clear;
        ext_key[1] = 0; cycles(HOLD); ext_key[1] = 1; cycles(HOLD);
        check("J10 down: down presses", n_down, 1);
        frames(12);
        wait_play(12);
        clear;
        ext_key[4] = 0; cycles(HOLD); ext_key[4] = 1; cycles(HOLD);
        check("J10 start: start presses", n_start, 1);
        frames(2);
        wait_play(4);
        check("J10 start: reshuffled", saw_shuffle, 1);

        // ---- each board key, once, one press each
        frames(12);
        wait_play(12);
        clear;
        key[3] = 0; cycles(HOLD); key[3] = 1; cycles(HOLD);
        check("right: right presses", n_right, 1);
        check("right: no other presses", n_up + n_down + n_left + n_start, 0);

        if (errors == 0) $display("PASS");
        else             $display("FAILED with %0d errors", errors);
        $finish;
    end

endmodule
