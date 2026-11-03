//------------------------------------------------------------------------------
// tb_puzzle.v - puzzle_core at real 640x480@60 timing
//
// Run from src/, so that $readmemh("image.mem") finds the picture:
//
//   cd src
//   iverilog -o /tmp/tb_puzzle.vvp ../sim/tb_puzzle.v puzzle_core.v vga_timing.v
//   vvp /tmp/tb_puzzle.vvp                      # play a game to the win
//   python3 ../sim/check_frames.py              # compare the frames it dumped
//
//   iverilog -P tb_puzzle.SHUF=200 -P tb_puzzle.REPLAY=0 ...   # shuffle soak
//
// REPLAY=1 (default) plays a whole game:
//   1. title screen                                       -> title.ppm
//   2. start: the shuffle is watched move by move         -> shuffled.ppm
//   3. peek held shows the finished picture, and blocks moves -> peek.ppm
//      tile numbers (on by default) are hidden and shown again -> nonumbers.ppm
//   4. a press with no tile to move does nothing (tested the first time
//      the gap is against an edge during step 5)
//   5. the shuffle is undone by pressing the same directions in reverse order
//      (the gap stepped d, so the tile now beside it must step d back). That
//      proves every shuffle is solvable and every press moves the right tile.
//      The first slide is caught halfway                  -> slide.ppm
//   6. the last move solves it: WIN and the iris          -> iris.ppm
//   7. back to the title                                  -> final.ppm
// The board, gap and sprite state behind each frame go to info.txt, so the
// Python check can work out every expected pixel from image.mem alone.
//
// REPLAY=0 reshuffles over and over, checking each board is a permutation of
// 0..15 and has the parity of a solvable position.
//
// Slides and the iris run faster than on the board (STEP_X/Y, IRIS_STEP) so
// that a whole game fits in a few dozen frames.
//------------------------------------------------------------------------------
module tb_puzzle;

    parameter SHUF   = 12;
    parameter REPLAY = 1;

    localparam S_TITLE = 0, S_SHUFFLE = 1, S_PLAY = 2, S_SLIDE = 3, S_WIN = 4;

    reg clk = 1'b0;
    always #20 clk = ~clk;

    reg rst = 1'b1;
    reg p_up = 0, p_down = 0, p_left = 0, p_right = 0, p_start = 0, peek = 0, p_nums = 0;

    wire       t_hs, t_vs, t_blank;
    wire [9:0] t_x, t_y;
    vga_timing u_timing (.clk(clk), .HS(t_hs), .VS(t_vs), .x(t_x), .y(t_y), .blank(t_blank));

    wire [7:0] r, g, b;
    wire       o_hs, o_vs, o_de;
    wire [2:0] st;

    puzzle_core #(
        .SHUFFLE_MOVES (SHUF),
        .STEP_X        (8'd80),
        .STEP_Y        (8'd60),
        .IRIS_STEP     (8'd40)
    ) dut (
        .clk(clk), .rst(rst),
        .x(t_x), .y(t_y), .hs_in(t_hs), .vs_in(t_vs), .blank_in(t_blank),
        .press_up(p_up), .press_down(p_down), .press_left(p_left),
        .press_right(p_right), .press_start(p_start), .peek(peek),
        .press_numbers(p_nums),
        .r(r), .g(g), .b(b), .hs(o_hs), .vs(o_vs), .de(o_de),
        .game_state(st)
    );

    integer errors = 0;
    integer info_fd;
    integer k;

    // ------------------------------------------------------------ frame dump
    // A dump starts at the next vsync of the core's *output* and takes the
    // 640x480 active pixels that follow, as a binary PPM.
    reg          dump_req = 0, dumping = 0;
    reg [8*48:1] dump_name;
    integer      dump_fd, npix;
    reg          o_vs_d = 1'b1;

    always @(posedge clk) begin
        o_vs_d <= o_vs;
        if (dump_req && o_vs_d && !o_vs) begin
            dump_fd  = $fopen(dump_name, "wb");
            $fwrite(dump_fd, "P6\n640 480\n255\n");
            npix     = 0;
            dumping  = 1;
            dump_req = 0;
            // what the renderer is working from for this frame
            $fwrite(info_fd, "frame %0s state %0d gap %0d mov_tile %0d mov_from %0d mx %0d my %0d iris_r %0d shine %0d board",
                    dump_name, dut.state, dut.gap, dut.mov_tile, dut.mov_from,
                    dut.mx, dut.my, dut.iris_r, dut.shine_pos);
            for (k = 0; k < 16; k = k + 1)
                $fwrite(info_fd, " %0d", dut.board[k]);
            $fwrite(info_fd, " peek %0d numbers %0d\n", peek, dut.show_numbers);
        end else if (dumping && o_de) begin
            $fwrite(dump_fd, "%c%c%c", r, g, b);
            npix = npix + 1;
            if (npix == 640 * 480) begin
                $fclose(dump_fd);
                dumping = 0;
            end
        end
    end

    task dump(input [8*48:1] name);
        begin
            dump_name = name;
            dump_req  = 1;
            wait (!dump_req);
            wait (!dumping);
        end
    endtask

    // ------------------------------------------------------------ helpers

    task frames(input integer n);
        integer f;
        for (f = 0; f < n; f = f + 1) @(posedge dut.tick);
    endtask

    task press(input integer which);   // 0 up 1 down 2 left 3 right 4 start 5 numbers
        begin
            @(negedge clk);
            case (which)
                0: p_up = 1;  1: p_down = 1;  2: p_left = 1;  3: p_right = 1;
                5: p_nums = 1;
                default: p_start = 1;
            endcase
            @(negedge clk);
            p_up = 0; p_down = 0; p_left = 0; p_right = 0; p_start = 0; p_nums = 0;
        end
    endtask

    task wait_state(input integer s, input integer max_frames);
        integer f;
        begin
            f = 0;
            while (dut.state != s && f < max_frames * 420000) begin
                @(posedge clk);
                f = f + 1;
            end
            if (dut.state != s) begin
                $display("FAIL: waited for state %0d, still in %0d", s, dut.state);
                errors = errors + 1;
            end
        end
    endtask

    // every board must be a permutation of 0..15 with the gap's tile on the
    // gap, and have even (inversions + gap's distance from home): that sum
    // keeps its parity through every legal move and is even when solved
    task check_board(input [8*24:1] when);
        integer i, j, inv, dist;
        reg [15:0] seen;
        begin
            seen = 0;
            inv  = 0;
            for (i = 0; i < 16; i = i + 1) begin
                seen = seen | (16'd1 << dut.board[i]);
                for (j = i + 1; j < 16; j = j + 1)
                    if (dut.board[i] > dut.board[j]) inv = inv + 1;
            end
            dist = (3 - dut.gap[3:2]) + (3 - dut.gap[1:0]);
            if (seen != 16'hffff) begin
                $display("FAIL %0s: board is not a permutation (%h)", when, seen);
                errors = errors + 1;
            end
            if (dut.board[dut.gap] != 4'd15) begin
                $display("FAIL %0s: gap slot %0d holds tile %0d", when, dut.gap, dut.board[dut.gap]);
                errors = errors + 1;
            end
            if ((inv + dist) % 2 != 0) begin
                $display("FAIL %0s: unsolvable parity (inv %0d, dist %0d)", when, inv, dist);
                errors = errors + 1;
            end
        end
    endtask

    // ------------------------------------------------------------ shuffle log
    reg [1:0] mv [0:1023];
    integer   nmv = 0;
    reg [2:0] st_prev = 0;

    always @(posedge clk) begin
        st_prev <= dut.state;
        if (dut.state == S_SHUFFLE && st_prev != S_SHUFFLE)
            nmv = 0;
        if (dut.shuf_step) begin
            mv[nmv] = dut.shuf_dir;
            nmv = nmv + 1;
        end
    end

    // can the gap move in direction d? (mirrors the rule the game must follow)
    function gap_can;
        input [1:0] d;
        input [3:0] gp;
        case (d)
            0: gap_can = gp[3:2] != 0;
            1: gap_can = gp[3:2] != 3;
            2: gap_can = gp[1:0] != 0;
            default: gap_can = gp[1:0] != 3;
        endcase
    endfunction

    // a press p moves the gap p ^ 1
    function has_illegal;
        input [3:0] gp;
        has_illegal = !gap_can(2'd0, gp) || !gap_can(2'd1, gp) ||
                      !gap_can(2'd2, gp) || !gap_can(2'd3, gp);
    endfunction

    function [1:0] illegal_press;   // a press with no tile to move
        input [3:0] gp;
        integer d;
        begin
            illegal_press = 0;
            for (d = 0; d < 4; d = d + 1)
                if (!gap_can(d[1:0] ^ 2'd1, gp)) illegal_press = d[1:0];
        end
    endfunction

    function [1:0] legal_press;     // a press that would move a tile
        input [3:0] gp;
        integer d;
        begin
            legal_press = 0;
            for (d = 0; d < 4; d = d + 1)
                if (gap_can(d[1:0] ^ 2'd1, gp)) legal_press = d[1:0];
        end
    endfunction

    // ------------------------------------------------------------ the game
    reg [3:0] saved [0:15];
    reg [3:0] saved_gap;
    integer   i, j, n, shuffles, same, illegal_done;
    reg [1:0] bad;

    initial begin
        info_fd = $fopen("../sim/out/info.txt", "w");
        repeat (10) @(posedge clk);
        rst = 0;

        frames(2);
        if (dut.state != S_TITLE) begin
            $display("FAIL: not on the title screen after reset"); errors = errors + 1;
        end
        dump("../sim/out/title.ppm");

        if (REPLAY) begin
            // ---- 2. shuffle
            press(4);
            wait_state(S_PLAY, 4);
            $display("shuffle made %0d gap moves", nmv);
            if (nmv < SHUF || nmv % SHUF != 0) begin
                $display("FAIL: shuffle made %0d moves, expected a multiple of %0d", nmv, SHUF);
                errors = errors + 1;
            end
            check_board("after shuffle");
            if (dut.solved) begin
                $display("FAIL: shuffle left the board solved"); errors = errors + 1;
            end
            dump("../sim/out/shuffled.ppm");

            // ---- 3. peek: the finished picture while held, and no moves
            @(negedge clk) peek = 1;
            press(legal_press(dut.gap));     // peek must block even a legal press
            frames(1);
            if (dut.state != S_PLAY) begin
                $display("FAIL: a press moved a tile while peeking"); errors = errors + 1;
            end
            dump("../sim/out/peek.ppm");
            @(negedge clk) peek = 0;

            // ---- numbers: on after reset, a press hides them, another shows them
            if (dut.show_numbers !== 1'b1) begin
                $display("FAIL: tile numbers not on after reset"); errors = errors + 1;
            end
            press(5);
            if (dut.show_numbers !== 1'b0) begin
                $display("FAIL: numbers press did not hide them"); errors = errors + 1;
            end
            dump("../sim/out/nonumbers.ppm");
            press(5);
            if (dut.show_numbers !== 1'b1) begin
                $display("FAIL: numbers press did not show them again"); errors = errors + 1;
            end

            // ---- 4 + 5. undo the shuffle; on the way, the first time the gap
            // is against an edge, a press with nothing to move must do nothing
            n = nmv;
            illegal_done = 0;
            for (i = n - 1; i >= 0; i = i - 1) begin
                if (!illegal_done && has_illegal(dut.gap)) begin
                    for (j = 0; j < 16; j = j + 1) saved[j] = dut.board[j];
                    saved_gap = dut.gap;
                    bad = illegal_press(dut.gap);
                    press(bad);
                    frames(2);
                    same = (dut.gap == saved_gap) && (dut.state == S_PLAY);
                    for (j = 0; j < 16; j = j + 1) if (dut.board[j] != saved[j]) same = 0;
                    if (!same) begin
                        $display("FAIL: press %0d with nothing to move changed the board", bad);
                        errors = errors + 1;
                    end else
                        $display("press %0d with gap at slot %0d (nothing to move) ignored", bad, saved_gap);
                    illegal_done = 1;
                end
                press(mv[i]);
                if (dut.state != S_SLIDE) begin
                    $display("FAIL: replay move %0d (press %0d) did not start a slide", i, mv[i]);
                    errors = errors + 1;
                end
                if (i == n - 1)
                    dump("../sim/out/slide.ppm");   // the frame after one step
                // pressing again mid-slide must be ignored
                press(mv[i]);
                wait_state(S_PLAY, 6);
                check_board("during replay");
            end
            if (!dut.solved) begin
                $display("FAIL: undoing the shuffle did not solve the board"); errors = errors + 1;
            end
            if (!illegal_done) begin
                $display("FAIL: the gap never reached an edge to test an illegal press");
                errors = errors + 1;
            end

            // ---- 6. win
            wait_state(S_WIN, 3);
            frames(3);
            dump("../sim/out/iris.ppm");

            // ---- 7. back to the title, and the picture whole
            wait_state(S_TITLE, 20);
            frames(1);
            dump("../sim/out/final.ppm");
        end else begin
            // ---- shuffle soak: many boards, each must be solvable
            for (shuffles = 0; shuffles < 6; shuffles = shuffles + 1) begin
                for (i = 0; i < 16; i = i + 1) saved[i] = dut.board[i];
                press(4);
                frames(2);
                wait_state(S_PLAY, 4);
                check_board("soak");
                same = 1;
                for (i = 0; i < 16; i = i + 1) if (dut.board[i] != saved[i]) same = 0;
                if (same) begin
                    $display("FAIL: reshuffle %0d produced the same board", shuffles);
                    errors = errors + 1;
                end
                $write("board %0d (%0d moves):", shuffles, nmv);
                for (i = 0; i < 16; i = i + 1) $write(" %0d", dut.board[i]);
                $write("\n");
            end
            dump("../sim/out/soak.ppm");
        end

        $fclose(info_fd);
        if (errors == 0) $display("PASS");
        else             $display("FAILED with %0d errors", errors);
        $finish;
    end

endmodule
