//------------------------------------------------------------------------------
// tb_tt.v - the VGA Playground top, driven the way the playground drives it
//
//   cd src
//   iverilog -o /tmp/tb_tt.vvp ../sim/tb_tt.v tt_um_hextex_slidepuzzle.v \
//            puzzle_core.v vga_timing.v gamepad_pmod_rx.v digit_font.v
//   vvp /tmp/tb_tt.vvp && python3 ../sim/check_tt.py
//
// The gamepad here is a copy of the playground's InputController.ts
// updateGamepadPmod(). It steps once per scanline (the playground calls it at
// the start of every line it draws) through a 400-step cycle:
//   - CLK = cycle % 2 for cycles 0..47
//   - DATA = bit (cycle >> 1) of (buttons << 12)
//   - LATCH high on cycle 49
// Button bits: b0 y1 select2 start3 up4 down5 left6 right7 a8 x9 l10 r11.
//
// Checks:
//   - sync comes out on the Tiny VGA pins with the right pulse lengths
//   - gamepad start leaves the title; an arrow moves a tile; select peeks;
//     each press is exactly one press
//   - the ui_in switches act on every flip, both ways; ui_in[7] reshuffles
//   - a frame decoded from uo_out with the playground's bit mapping, for
//     check_tt.py to compare against the core's colours through the dither
//------------------------------------------------------------------------------
module tb_tt;

    localparam S_TITLE = 0, S_SHUFFLE = 1, S_PLAY = 2, S_SLIDE = 3, S_WIN = 4;

    reg        clk = 1'b0;
    always #20 clk = ~clk;

    reg        rst_n = 1'b0;
    reg  [7:0] ui_in = 8'h00;
    wire [7:0] uo_out, uio_out, uio_oe;

    tt_um_hextex_slidepuzzle dut (
        .ui_in(ui_in), .uo_out(uo_out), .uio_in(8'h00), .uio_out(uio_out),
        .uio_oe(uio_oe), .ena(1'b1), .clk(clk), .rst_n(rst_n)
    );

    wire [2:0] state = dut.u_core.state;
    integer errors = 0;

    // ------------------------------------------------------ gamepad model
    reg        gp_en = 0;
    reg [11:0] gp_value = 0;
    integer    gp_counter = 0, cycle, data_index;
    reg [23:0] data_reg;

    always @(posedge uo_out[7]) begin        // hsync going inactive: a line starts
        if (gp_en) begin
            cycle      = gp_counter % 400;
            gp_counter = gp_counter + 1;
            data_reg   = {gp_value, 12'h000};
            data_index = (cycle < 49) ? (cycle >> 1) : 0;
            ui_in[5]   = (cycle < 48) ? (cycle % 2) : 0;          // clock
            ui_in[6]   = data_reg[data_index];                    // data
            ui_in[4]   = (cycle == 49);                           // latch
        end
    end

    // hold buttons v for at least `packets` whole packets: the packet in
    // flight when v changes may carry either value, so wait one latch more,
    // then give the receiver's synchronizer a few clocks
    task gamepad_hold(input [11:0] v, input integer packets);
        begin
            gp_value = v;
            repeat (packets + 1) @(posedge ui_in[4]);
            repeat (8) @(posedge clk);
        end
    endtask

    // ------------------------------------------------------ press counters
    integer n_up = 0, n_down = 0, n_left = 0, n_right = 0, n_start = 0;
    always @(posedge clk) begin
        if (dut.press_up)    n_up    = n_up + 1;
        if (dut.press_down)  n_down  = n_down + 1;
        if (dut.press_left)  n_left  = n_left + 1;
        if (dut.press_right) n_right = n_right + 1;
        if (dut.press_start) n_start = n_start + 1;
    end

    function integer presses;
        input integer dir;
        case (dir)
            0: presses = n_up;  1: presses = n_down;
            2: presses = n_left; default: presses = n_right;
        endcase
    endfunction

    function gap_can;              // can the gap move in direction d?
        input [1:0] d;
        input [3:0] gp;
        case (d)
            0: gap_can = gp[3:2] != 0;
            1: gap_can = gp[3:2] != 3;
            2: gap_can = gp[1:0] != 0;
            default: gap_can = gp[1:0] != 3;
        endcase
    endfunction

    function [1:0] legal_press;    // a press that moves a tile right now
        input [3:0] gp;
        integer d;
        begin
            legal_press = 0;
            for (d = 3; d >= 0; d = d - 1)
                if (gap_can(d[1:0] ^ 2'd1, gp)) legal_press = d[1:0];
        end
    endfunction

    task wait_state(input integer s, input integer max_frames);
        integer c;
        begin
            c = 0;
            while (state != s && c < max_frames * 420000) begin
                @(posedge clk); c = c + 1;
            end
            if (state != s) begin
                $display("FAIL: waited for state %0d, still %0d", s, state);
                errors = errors + 1;
            end
        end
    endtask

    task expect_count(input [8*24:1] what, input integer got, input integer want);
        if (got != want) begin
            $display("FAIL: %0s: %0d presses, expected %0d", what, got, want);
            errors = errors + 1;
        end else
            $display("ok   %0s: %0d press(es)", what, got);
    endtask

    // ------------------------------------------------------ sync pulse widths
    integer hs_low = 0, vs_low = 0, hs_bad = 0, vs_bad = 0, hs_seen = 0, vs_seen = 0;
    always @(posedge clk) if (rst_n) begin
        if (!uo_out[7]) hs_low = hs_low + 1;
        else if (hs_low) begin
            if (hs_low != 96) hs_bad = hs_bad + 1;
            hs_seen = hs_seen + 1; hs_low = 0;
        end
        if (!uo_out[3]) vs_low = vs_low + 1;
        else if (vs_low) begin
            if (vs_low != 2 * 800) vs_bad = vs_bad + 1;
            vs_seen = vs_seen + 1; vs_low = 0;
        end
    end

    // ------------------------------------------------------ frame from the pins
    reg          dump_req = 0, dumping = 0;
    reg [8*48:1] dump_name;
    integer      fd, npix;
    reg          vs_d = 1'b1;
    reg  [1:0]   pr, pg, pb;

    always @(posedge clk) begin
        vs_d <= uo_out[3];
        if (dump_req && vs_d && !uo_out[3]) begin
            fd = $fopen(dump_name, "wb");
            $fwrite(fd, "P6\n640 480\n255\n");
            npix = 0; dumping = 1; dump_req = 0;
        end else if (dumping && dut.v_de) begin
            // the playground's decodeVGAOutput()
            pr = {uo_out[0], uo_out[4]};
            pg = {uo_out[1], uo_out[5]};
            pb = {uo_out[2], uo_out[6]};
            $fwrite(fd, "%c%c%c", pr * 8'd85, pg * 8'd85, pb * 8'd85);
            npix = npix + 1;
            if (npix == 640 * 480) begin $fclose(fd); dumping = 0; end
        end
    end

    task dump(input [8*48:1] name);
        begin dump_name = name; dump_req = 1; wait (!dump_req); wait (!dumping); end
    endtask

    // ------------------------------------------------------ the test
    integer   before, d;
    reg [3:0] gap0;

    initial begin
        // a switch already on before reset ends must not count as a press
        ui_in[2] = 1;
        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge dut.u_core.tick);
        expect_count("switch on through reset", n_left, 0);
        if (state != S_TITLE) begin $display("FAIL: not on title"); errors = errors + 1; end

        dump("../sim/out/tt_title.ppm");

        // ---- gamepad: start
        gp_en = 1;
        gamepad_hold(12'h000, 1);
        if (!dut.gp_present) begin $display("FAIL: gamepad not seen"); errors = errors + 1; end
        gamepad_hold(12'h008, 2);                 // start, held two packets
        gamepad_hold(12'h000, 1);
        expect_count("gamepad start", n_start, 1);
        wait_state(S_PLAY, 4);

        // ---- gamepad: an arrow
        d = legal_press(dut.u_core.gap);
        gap0 = dut.u_core.gap;
        before = presses(d);
        gamepad_hold(12'h010 << d, 1);             // up=bit4 .. right=bit7
        if (state != S_SLIDE && state != S_PLAY) begin
            $display("FAIL: arrow did not slide"); errors = errors + 1;
        end
        gamepad_hold(12'h000, 1);
        wait_state(S_PLAY, 20);
        expect_count("gamepad arrow", presses(d) - before, 1);
        if (dut.u_core.gap == gap0) begin
            $display("FAIL: gamepad arrow %0d did not move a tile", d); errors = errors + 1;
        end

        // ---- gamepad: select peeks while held
        gamepad_hold(12'h004, 1);
        if (!dut.peek) begin $display("FAIL: select did not peek"); errors = errors + 1; end
        else            $display("ok   select peeks");
        gamepad_hold(12'h000, 1);
        if (dut.peek) begin $display("FAIL: peek stuck on"); errors = errors + 1; end

        // ---- gamepad: x flips the tile numbers, once per press
        if (dut.u_core.show_numbers !== 1'b1) begin
            $display("FAIL: numbers not on after reset"); errors = errors + 1;
        end
        gamepad_hold(12'h200, 2);                  // x, held two packets
        gamepad_hold(12'h000, 1);
        if (dut.u_core.show_numbers !== 1'b0) begin
            $display("FAIL: x did not hide the numbers"); errors = errors + 1;
        end else $display("ok   x hides the numbers");
        gamepad_hold(12'h200, 1);
        gamepad_hold(12'h000, 1);
        if (dut.u_core.show_numbers !== 1'b1) begin
            $display("FAIL: x did not show the numbers again"); errors = errors + 1;
        end else $display("ok   x shows them again");

        // ---- ui_in switches: every flip is a press, either way
        d = legal_press(dut.u_core.gap);
        gap0 = dut.u_core.gap;
        before = presses(d);
        @(negedge clk) ui_in[d] = ~ui_in[d];
        repeat (5) @(posedge clk);
        if (state != S_SLIDE) begin $display("FAIL: switch %0d did not slide", d); errors = errors + 1; end
        wait_state(S_PLAY, 20);
        @(negedge clk) ui_in[d] = ~ui_in[d];
        repeat (5) @(posedge clk);
        wait_state(S_PLAY, 20);
        expect_count("switch flipped twice", presses(d) - before, 2);

        dump("../sim/out/tt_play.ppm");

        // ---- ui_in[7] reshuffles
        before = n_start;
        @(negedge clk) ui_in[7] = ~ui_in[7];
        wait_state(S_SHUFFLE, 2);
        wait_state(S_PLAY, 2);
        expect_count("switch 7 start", n_start - before, 1);

        $display("hsync pulses seen %0d (bad widths %0d), vsync pulses %0d (bad %0d)",
                 hs_seen, hs_bad, vs_seen, vs_bad);
        if (hs_bad || vs_bad || hs_seen < 1000 || vs_seen < 3) begin
            $display("FAIL: sync pulses on uo_out[7]/uo_out[3] are wrong"); errors = errors + 1;
        end

        if (errors == 0) $display("PASS");
        else             $display("FAILED with %0d errors", errors);
        $finish;
    end

endmodule
