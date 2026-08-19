//------------------------------------------------------------------------------
// tb_text_system.v
//
// Full-system simulation of the text-mode core (everything except the
// clocking IP and the TMDS output stage): renders real 640x480 frames,
// drives scripted button presses through the debouncer, and checks tile-RAM
// contents / cursor position / mode transitions via hierarchical references.
// Two frames are dumped as PPM images (frame_editor.ppm, frame_rain.ppm)
// for visual inspection.
//
// Time-scaled parameters keep the run manageable: screensaver after 10
// frames idle (instead of 1200), 20-cycle debounce, 4-frame hold-to-clear.
//
//   iverilog -o /tmp/tb_text_system.vvp hdl/*.v sim/tb_text_system.v
//   vvp /tmp/tb_text_system.vvp        (run from the project root)
//------------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_text_system;

    // 40 idle frames before the screensaver: long enough that the scripted
    // waits between presses (worst case ~18 frames around the blink-phase
    // wait) never trip it early, short enough to test quickly
    localparam integer IDLE_FRAMES   = 40;
    localparam integer REPEAT_DELAY  = 3;
    localparam integer REPEAT_PERIOD = 2;
    localparam integer CLEAR_HOLD    = 4;

    reg        clk = 1'b0;
    reg  [3:0] key = 4'b1111;          // active-low, idle high
    wire [7:0] vid_r, vid_g, vid_b;
    wire       vid_hs, vid_vs, vid_de;

    always #20 clk = ~clk;

    text_system #(
        .IDLE_FRAMES       (IDLE_FRAMES),
        .DEBOUNCE_CYCLES   (20),
        .REPEAT_DELAY      (REPEAT_DELAY),
        .REPEAT_PERIOD     (REPEAT_PERIOD),
        .CLEAR_HOLD_FRAMES (CLEAR_HOLD)
    ) dut (
        .clk    (clk),
        .key    (key),
        .vid_r  (vid_r),
        .vid_g  (vid_g),
        .vid_b  (vid_b),
        .vid_hs (vid_hs),
        .vid_vs (vid_vs),
        .vid_de (vid_de)
    );

    //--------------------------------------------------------------------------
    // frame capture + on-request PPM dump
    //--------------------------------------------------------------------------
    reg [23:0] fb [0:640*480-1];
    integer pix = 0;
    integer frames = 0;
    reg dump_editor_req = 1'b0, dump_rain_req = 1'b0;

    task dump_ppm(input [8*24-1:0] fname);
        integer fd, i;
        begin
            fd = $fopen(fname, "wb");
            $fwrite(fd, "P6\n640 480\n255\n");
            for (i = 0; i < 640*480; i = i + 1)
                $fwrite(fd, "%c%c%c", fb[i][23:16], fb[i][15:8], fb[i][7:0]);
            $fclose(fd);
        end
    endtask

    always @(posedge clk) begin
        if (vid_de) begin
            fb[pix] = {vid_r, vid_g, vid_b};
            pix = pix + 1;
        end
    end

    // frame boundary = falling edge of VS (which sits inside vblank, well
    // after the last active pixel of the frame)
    always @(negedge vid_vs) begin
        if (pix == 640*480) begin
            if (dump_editor_req) begin
                dump_ppm("frame_editor.ppm");
                $display("dumped frame_editor.ppm (frame %0d)", frames);
                dump_editor_req = 1'b0;
            end
            if (dump_rain_req) begin
                dump_ppm("frame_rain.ppm");
                $display("dumped frame_rain.ppm (frame %0d)", frames);
                dump_rain_req = 1'b0;
            end
        end
        pix    = 0;
        frames = frames + 1;
    end

    //--------------------------------------------------------------------------
    // helpers
    //--------------------------------------------------------------------------
    integer errors = 0;

`define CHECK(cond, name) \
    if (cond) $display("PASS: %s", name); \
    else begin errors = errors + 1; $display("FAIL: %s", name); end

    task wait_frames(input integer n);
        integer target;
        begin
            target = frames + n;
            wait (frames == target);
            @(posedge clk);
        end
    endtask

    // one short press: through debounce (20 cycles) but far below one frame,
    // so it never autorepeats and never trips the idle timer noticeably
    task press(input integer idx);
        begin
            key[idx] = 1'b0;
            repeat (100) @(posedge clk);
            key[idx] = 1'b1;
            repeat (100) @(posedge clk);
        end
    endtask

    task press_n(input integer idx, input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                press(idx);
        end
    endtask

    // count used cells in the rain RAM
    function integer rain_cells;
        input integer dummy;
        integer i;
        begin
            rain_cells = 0;
            for (i = 0; i < 2400; i = i + 1)
                if (dut.u_rain_ram.mem[i][6:0] != 7'h20)
                    rain_cells = rain_cells + 1;
        end
    endfunction

    function integer rain_heads;   // bright cells
        input integer dummy;
        integer i;
        begin
            rain_heads = 0;
            for (i = 0; i < 2400; i = i + 1)
                if (dut.u_rain_ram.mem[i][7])
                    rain_heads = rain_heads + 1;
        end
    endfunction

    //--------------------------------------------------------------------------
    // test sequence
    //--------------------------------------------------------------------------
    integer x0;

    initial begin
        // 1. power-up clear sweep, editor mode
        wait (dut.u_editor.busy == 1'b0);
        wait_frames(2);
        `CHECK((dut.u_editor_ram.mem[0] == 8'h20) && (dut.u_editor_ram.mem[2399] == 8'h20),
               "power-up clear sweep fills RAM with spaces")
        `CHECK(dut.mode == 1'b0, "powers up in editor mode")

        // 2. character cycling at the cursor
        press(2);
        `CHECK(dut.u_editor_ram.mem[0] == 8'h41, "char+ on space types 'A'")
        press(2);
        `CHECK(dut.u_editor_ram.mem[0] == 8'h42, "char+ again cycles to 'B'")

        // 3. cursor movement + backward cycling
        press(0);
        `CHECK((dut.u_editor.cur_x == 7'd1) && (dut.u_editor.cur_y == 5'd0), "cursor right")
        wait_frames(1);   // let the cursor-cell read-back refresh
        press(3);
        `CHECK(dut.u_editor_ram.mem[1] == 8'h7E, "char- on space types '~'")
        press(1);
        `CHECK(dut.u_editor.cur_y == 5'd1, "cursor down")

        // 4. typematic autorepeat: hold right through delay + 2 periods
        x0 = dut.u_editor.cur_x;
        key[0] = 1'b0;
        wait_frames(REPEAT_DELAY + 2*REPEAT_PERIOD + 1);
        key[0] = 1'b1;
        wait_frames(1);
        `CHECK(dut.u_editor.cur_x >= x0 + 3, "holding a button autorepeats")

        // 5. hold-to-clear combo
        key[2] = 1'b0; key[3] = 1'b0;
        wait_frames(CLEAR_HOLD + 2);
        key[2] = 1'b1; key[3] = 1'b1;
        wait (dut.u_editor.busy == 1'b0);
        wait_frames(1);
        `CHECK((dut.u_editor_ram.mem[0] == 8'h20) && (dut.u_editor_ram.mem[1] == 8'h20),
               "hold char+/char- clears the screen")
        `CHECK((dut.u_editor.cur_x == 7'd0) && (dut.u_editor.cur_y == 5'd0), "clear homes the cursor")

        // 6. type "HI" (space->A is 1 press, so 'H'=8 presses, 'I'=9)
        press_n(2, 8);
        `CHECK(dut.u_editor_ram.mem[0] == 8'h48, "typed 'H'")
        press(0);
        wait_frames(1);
        press_n(2, 9);
        `CHECK(dut.u_editor_ram.mem[1] == 8'h49, "typed 'I'")
        press(0);
        wait_frames(1);

        // 7. dump an editor frame with the cursor visible
        wait (dut.blink_cnt[4] == 1'b1);
        dump_editor_req = 1'b1;
        wait (dump_editor_req == 1'b0);

        // 8. go idle -> screensaver
        wait (dut.mode == 1'b1);
        `CHECK(1'b1, "idle timeout enters screensaver mode")
        // let the streams fall for a second - columns start with random
        // delays of up to 63 frames, so counting too early reads sparse
        wait_frames(60);
        `CHECK(rain_cells(0) > 50, "rain streams are drawing characters")
        `CHECK(rain_heads(0) > 0, "rain streams have bright heads")
        `CHECK((dut.u_editor_ram.mem[0] == 8'h48) && (dut.u_editor_ram.mem[1] == 8'h49),
               "editor text untouched by screensaver")
        dump_rain_req = 1'b1;
        wait (dump_rain_req == 1'b0);

        // 9. wake up: the waking press is consumed, text and cursor intact
        x0 = dut.u_editor.cur_x;
        press(0);
        `CHECK(dut.mode == 1'b0, "button press wakes from screensaver")
        `CHECK(dut.u_editor.cur_x == x0, "wake press is consumed (cursor did not move)")
        `CHECK((dut.u_editor_ram.mem[0] == 8'h48) && (dut.u_editor_ram.mem[1] == 8'h49),
               "text still intact after wake")
        press(0);
        `CHECK(dut.u_editor.cur_x == x0 + 1, "buttons work again after wake")

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", errors);
        $finish;
    end

    // safety net: expected end is ~2 s of simulated video (~140 frames)
    initial begin
        #4_000_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
