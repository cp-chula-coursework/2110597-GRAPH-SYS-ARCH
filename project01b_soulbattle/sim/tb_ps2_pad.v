//------------------------------------------------------------------------------
// tb_ps2_pad.v
//
// Talks to ps2_pad with a model of a real PlayStation controller on the other
// end of the wire: it shifts its answer out on each falling clock edge and
// latches the host's command on each rising one, exactly as the hardware
// does, and answers with whatever ID / button bytes the test sets.
//
// What it proves:
//   - the host sends 01, 42, then filler, LSB first
//   - it reads the ID and uses its low nibble to decide how long the rest of
//     the transaction is: 5 bytes from a digital pad, 9 from an analog one
//   - d-pad presses come out on the right output, and so do the face buttons
//     and START (as `ok`)
//   - the left stick works as a d-pad on an analog controller, with a
//     deadzone, and is ignored on a digital one
//   - with nothing plugged in (DAT held high by its pull-up) `present` stays
//     low and every button output stays at 0, which is what leaves the
//     board's own push buttons in charge
//
//   iverilog -o /tmp/tb_ps2.vvp hdl/ps2_pad.v sim/tb_ps2_pad.v
//   vvp /tmp/tb_ps2.vvp
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_ps2_pad;

    reg clk = 1'b0;
    always #19.861 clk = ~clk;      // ~25.175 MHz

    reg  poll = 1'b0;
    wire att, sck, cmd, dat;
    wire up, down, left, right, ok, present;

    ps2_pad dut (
        .clk (clk), .poll (poll),
        .ps2_att (att), .ps2_clk (sck), .ps2_cmd (cmd), .ps2_dat (dat),
        .pad_up (up), .pad_down (down), .pad_left (left), .pad_right (right),
        .pad_ok (ok), .present (present)
    );

    // ---- the controller on the other end -----------------------------------
    reg       plugged  = 1'b1;
    reg [7:0] pad_id   = 8'h41;     // 41 digital, 73 analog
    reg [7:0] btn_hi   = 8'hFF;     // SLCT L3 R3 STRT UP RIGHT DOWN LEFT
    reg [7:0] btn_lo   = 8'hFF;     // L2 R2 L1 R1  /\  ()  XX  []
    reg [7:0] stick_lx = 8'h80;
    reg [7:0] stick_ly = 8'h80;

    reg dat_bit = 1'b1;
    assign dat = plugged ? dat_bit : 1'b1;   // open drain: high when idle

    reg [7:0] tx_sr, rx_sr;
    integer   bitn = 0, byten = 0;
    reg [7:0] cmd_log [0:15];

    function [7:0] resp(input integer n);
        case (n)
            0: resp = 8'hFF;
            1: resp = pad_id;
            2: resp = 8'h5A;
            3: resp = btn_hi;
            4: resp = btn_lo;
            5: resp = 8'h80;        // right stick X
            6: resp = 8'h80;        // right stick Y
            7: resp = stick_lx;
            8: resp = stick_ly;
            default: resp = 8'hFF;
        endcase
    endfunction

    always @(negedge att) begin
        byten = 0;  bitn = 0;
        tx_sr = resp(0);
        rx_sr = 8'h00;
    end

    always @(posedge att) dat_bit = 1'b1;

    always @(negedge sck) if (!att && plugged) begin
        dat_bit = tx_sr[0];
        tx_sr   = {1'b1, tx_sr[7:1]};
    end

    always @(posedge sck) if (!att && plugged) begin
        rx_sr = {cmd, rx_sr[7:1]};          // LSB first
        bitn  = bitn + 1;
        if (bitn == 8) begin
            cmd_log[byten] = rx_sr;
            bitn  = 0;
            byten = byten + 1;
            tx_sr = resp(byten);
            rx_sr = 8'h00;
        end
    end

    // ---- harness -----------------------------------------------------------
    integer errors = 0;

    task check(input cond, input [8*72-1:0] msg);
        if (!cond) begin
            errors = errors + 1;
            $display("FAIL: %0s", msg);
        end
    endtask

    task run_poll;
        begin
            @(posedge clk);
            #1 poll = 1'b1;        // off the edge, so the DUT really sees it
            @(posedge clk);
            #1 poll = 1'b0;
            // level tests, not edges: ATT can go low on the same edge that
            // clears `poll`, which an @(negedge) here would miss
            while (att !== 1'b0) @(posedge clk);
            while (att !== 1'b1) @(posedge clk);
            repeat (4) @(posedge clk);
        end
    endtask

    task no_buttons;
        begin
            btn_hi = 8'hFF; btn_lo = 8'hFF;
            stick_lx = 8'h80; stick_ly = 8'h80;
        end
    endtask

    initial begin
        #2_000_000_000;
        $display("FAIL: watchdog timeout");
        $finish;
    end

    initial begin
        // ---- a digital pad, nothing pressed --------------------------------
        no_buttons;
        run_poll;
        check(present, "a digital controller was not detected");
        check(byten == 5, "a digital controller should be a 5-byte transaction");
        check(cmd_log[0] == 8'h01, "first command byte was not 01");
        check(cmd_log[1] == 8'h42, "second command byte was not 42");
        check(cmd_log[2] == 8'h00 && cmd_log[3] == 8'h00 && cmd_log[4] == 8'h00,
              "filler command bytes were not 00");
        check(!up && !down && !left && !right && !ok,
              "buttons reported with nothing pressed");

        // ---- the d-pad ------------------------------------------------------
        btn_hi = ~8'b0001_0000;  run_poll;   // UP
        check(up && !down && !left && !right, "UP did not come out as up");
        btn_hi = ~8'b0100_0000;  run_poll;   // DOWN
        check(down && !up, "DOWN did not come out as down");
        btn_hi = ~8'b1000_0000;  run_poll;   // LEFT
        check(left && !right, "LEFT did not come out as left");
        btn_hi = ~8'b0010_0000;  run_poll;   // RIGHT
        check(right && !left, "RIGHT did not come out as right");

        // two at once, for diagonals
        btn_hi = ~8'b0011_0000;  run_poll;
        check(up && right, "UP+RIGHT did not come out as a diagonal");
        no_buttons;

        // ---- face buttons and START all mean "confirm" ----------------------
        btn_lo = ~8'b0100_0000;  run_poll;   // cross
        check(ok, "cross did not come out as ok");
        btn_lo = ~8'b0001_0000;  run_poll;   // triangle
        check(ok, "triangle did not come out as ok");
        btn_lo = 8'hFF;
        btn_hi = ~8'b0000_1000;  run_poll;   // START
        check(ok, "START did not come out as ok");
        btn_lo = ~8'b0000_0100;  btn_hi = 8'hFF;  run_poll;   // L1
        check(!ok, "a shoulder button should not confirm");
        no_buttons;

        // a digital pad has no sticks - its stick bytes are never even sent
        stick_lx = 8'h00;  stick_ly = 8'h00;
        run_poll;
        check(!left && !up, "stick bytes were used on a digital controller");
        no_buttons;

        // ---- an analog pad --------------------------------------------------
        pad_id = 8'h73;
        run_poll;
        check(present, "an analog controller was not detected");
        check(byten == 9, "an analog controller should be a 9-byte transaction");
        check(!up && !down && !left && !right, "a centred stick moved the soul");

        stick_lx = 8'h10;  run_poll;
        check(left && !right, "the stick pushed left did not read as left");
        stick_lx = 8'hF0;  run_poll;
        check(right && !left, "the stick pushed right did not read as right");
        stick_lx = 8'h80;  stick_ly = 8'h05;  run_poll;
        check(up && !down, "the stick pushed up did not read as up");
        stick_ly = 8'hFA;  run_poll;
        check(down && !up, "the stick pushed down did not read as down");

        // just off centre is still centre
        stick_lx = 8'h70;  stick_ly = 8'h90;  run_poll;
        check(!left && !right && !up && !down, "the stick deadzone is too small");
        no_buttons;

        // the d-pad still works on an analog pad
        btn_hi = ~8'b1000_0000;  run_poll;
        check(left, "the d-pad stopped working in analog mode");
        no_buttons;

        // ---- nothing plugged in ---------------------------------------------
        plugged = 1'b0;
        run_poll;
        check(!present, "an empty socket was reported as a controller");
        check(!up && !down && !left && !right && !ok,
              "an empty socket reported buttons");

        // ---- and it recovers when one is plugged back in --------------------
        plugged = 1'b1;
        run_poll;
        check(present, "the controller was not picked up again after unplugging");

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", errors);
        $finish;
    end

endmodule
