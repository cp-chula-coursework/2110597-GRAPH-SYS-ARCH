//------------------------------------------------------------------------------
// puzzle_core.v
//
// Image slide puzzle: the whole game and the whole picture, shared unchanged by
// both targets (AX7010 over HDMI, and the VGA Playground / Tiny Tapeout top).
//
// A 320x240 picture, shown doubled at 640x480, is cut into a 4x4 grid of
// 80x60-pixel tiles (160x120 on screen). Tile 15, the bottom-right one, is
// missing; the player slides the others through the gap until the picture is
// whole again.
//
// Nothing is ever copied. The picture stays where it is in its ROM. The only
// thing a move changes is `board`, sixteen 4-bit entries saying which tile
// sits in each slot. For every pixel the beam visits, the renderer works out:
//
//     slot     which of the 16 slots the beam is in          (comparators)
//     tile     board[slot], which tile is in that slot        (a 16:1 mux)
//     address  where that tile's pixel is in the picture      (shift + add)
//
// and reads the colour from there. A move that rewrites two board entries
// therefore rearranges the picture on the very next frame.
//
// Game flow (one move = one slide; every state change happens in vblank):
//
//   TITLE  --press-->  SHUFFLE  --done-->  PLAY  <--slide-->  SLIDE
//     ^                                     |
//     +--------  WIN (iris)  <---solved-----+
//
//   - SHUFFLE starts from the solved board and makes SHUFFLE_MOVES random but
//     legal moves of the gap, one per clock. Because every step is a real
//     move, the result can always be solved. Choosing a random arrangement
//     directly would make half of the boards impossible.
//   - SLIDE draws the moving tile as a sprite stepping STEP_X / STEP_Y pixels
//     a frame, and only writes the board when it arrives. No input is taken
//     while a tile is moving.
//   - WIN opens the finished picture from the centre of the screen as a
//     growing circle (dx^2 + dy^2 < r^2) over the dimmed board, then falls
//     back to TITLE.
//
// Pixel pipeline (latency 4; hs/vs/de are delayed to match):
//   0: slot / tile / address / effect flags from (x, y)   -> registered
//   1: picture ROM read: palette index                    -> registered
//   2: palette read: 24-bit colour                        -> registered
//   3: bevels, gap, dimming, shine                        -> outputs
//
// Every signal is 32 bits wide or less, and nothing is signed, so the VGA
// Playground's simulator can run the design.
//------------------------------------------------------------------------------
`default_nettype none

module puzzle_core #(
    parameter [7:0] SHUFFLE_MOVES = 8'd200, // gap moves per shuffle
    parameter [7:0] STEP_X        = 8'd16,  // slide speed, px/frame (divides 160)
    parameter [7:0] STEP_Y        = 8'd12,  // slide speed, px/frame (divides 120)
    parameter [7:0] IRIS_STEP     = 8'd6    // iris growth, px/frame
)(
    input  wire       clk,          // 25.175 MHz pixel clock
    input  wire       rst,          // synchronous, active-high

    // video timing in (from vga_timing)
    input  wire [9:0] x,
    input  wire [9:0] y,
    input  wire       hs_in,
    input  wire       vs_in,
    input  wire       blank_in,

    // controls: one-clock pulses, except peek which is a level
    input  wire       press_up,     // the tile below the gap moves up
    input  wire       press_down,   // the tile above the gap moves down
    input  wire       press_left,   // the tile right of the gap moves left
    input  wire       press_right,  // the tile left of the gap moves right
    input  wire       press_start,  // new game / reshuffle
    input  wire       peek,         // held: show the finished picture

    // video out, 4 clocks behind (x, y)
    output reg  [7:0] r,
    output reg  [7:0] g,
    output reg  [7:0] b,
    output reg        hs,
    output reg        vs,
    output reg        de,

    output wire [2:0] game_state
);

    // ---------------------------------------------------------------- states
    localparam [2:0] S_TITLE   = 3'd0,
                     S_SHUFFLE = 3'd1,
                     S_PLAY    = 3'd2,
                     S_SLIDE   = 3'd3,
                     S_WIN     = 3'd4;

    // directions; d ^ 1 is the opposite direction
    localparam [1:0] D_UP = 2'd0, D_DOWN = 2'd1, D_LEFT = 2'd2, D_RIGHT = 2'd3;

    localparam [3:0]  GAP_TILE   = 4'd15;     // the missing piece
    localparam [10:0] SHINE_REST = 11'd1300;  // shine starts off-screen
    localparam [8:0]  IRIS_END   = 9'd404;    // past the corners (400 px away)

    reg  [2:0] state;
    assign game_state = state;

    // one pulse per frame, on the first line of vertical blanking
    wire tick = (x == 10'd0) && (y == 10'd480);

    // ----------------------------------------------------------- game state
    reg  [3:0]  board [0:15];    // board[slot] = tile in that slot
    reg  [3:0]  gap;             // slot holding the gap
    reg  [15:0] lfsr;            // free-running random source
    reg  [7:0]  shuf_cnt;
    reg  [1:0]  last_dir;        // gap's previous shuffle move
    reg         last_valid;
    reg         start_req;       // a press waiting for the next vblank

    reg  [3:0]  mov_tile;        // the sliding tile
    reg  [3:0]  mov_from;        // the slot it left
    reg  [1:0]  mov_dir;         // which way it is going
    reg  [9:0]  mx, my;          // its top-left corner on screen
    reg  [9:0]  tx, ty;          // where it stops (the gap's corner)

    reg  [8:0]  iris_r;
    reg  [17:0] iris_r2;
    reg  [10:0] shine_pos;

    // the board is solved when every slot holds its own tile
    wire solved = (board[0]  == 4'd0)  && (board[1]  == 4'd1)  &&
                  (board[2]  == 4'd2)  && (board[3]  == 4'd3)  &&
                  (board[4]  == 4'd4)  && (board[5]  == 4'd5)  &&
                  (board[6]  == 4'd6)  && (board[7]  == 4'd7)  &&
                  (board[8]  == 4'd8)  && (board[9]  == 4'd9)  &&
                  (board[10] == 4'd10) && (board[11] == 4'd11) &&
                  (board[12] == 4'd12) && (board[13] == 4'd13) &&
                  (board[14] == 4'd14) && (board[15] == 4'd15);

    // ---- where the gap can go
    // The gap moving in direction d swaps it with its neighbour that way.
    // A player's press moves a tile the other way into the gap, so a press in
    // direction p is the gap moving in p ^ 1.
    wire [1:0] gap_row = gap[3:2];
    wire [1:0] gap_col = gap[1:0];

    function legal;            // can the gap move in direction d?
        input [1:0] d;
        input [1:0] row, col;
        case (d)
            D_UP:    legal = (row != 2'd0);
            D_DOWN:  legal = (row != 2'd3);
            D_LEFT:  legal = (col != 2'd0);
            default: legal = (col != 2'd3);
        endcase
    endfunction

    function [3:0] neighbour;  // the slot next to s in direction d
        input [3:0] s;
        input [1:0] d;
        case (d)
            D_UP:    neighbour = s - 4'd4;
            D_DOWN:  neighbour = s + 4'd4;
            D_LEFT:  neighbour = s - 4'd1;
            default: neighbour = s + 4'd1;
        endcase
    endfunction

    // a slot's top-left corner on screen: col*160, row*120, as shifts
    function [9:0] slot_x;
        input [3:0] s;
        slot_x = {1'b0, s[1:0], 7'd0} + {3'd0, s[1:0], 5'd0};
    endfunction
    function [9:0] slot_y;
        input [3:0] s;
        slot_y = {1'b0, s[3:2], 7'd0} - {5'd0, s[3:2], 3'd0};
    endfunction

    // ---- shuffle step: a random gap move, never undoing the previous one
    wire [1:0] shuf_dir  = {lfsr[11], lfsr[4]};
    wire       shuf_ok   = legal(shuf_dir, gap_row, gap_col) &&
                           !(last_valid && (shuf_dir == (last_dir ^ 2'd1)));
    wire [3:0] shuf_nb   = neighbour(gap, shuf_dir);
    wire       shuf_step = (state == S_SHUFFLE) && shuf_ok &&
                           (shuf_cnt != SHUFFLE_MOVES);

    // ---- player move: the pressed direction, first one wins
    wire       any_press = press_up | press_down | press_left | press_right;
    wire [1:0] press_dir = press_up   ? D_UP   :
                           press_down ? D_DOWN :
                           press_left ? D_LEFT : D_RIGHT;
    wire [1:0] gap_dir   = press_dir ^ 2'd1;
    wire       move_ok   = legal(gap_dir, gap_row, gap_col);
    wire [3:0] move_nb   = neighbour(gap, gap_dir);

    wire slide_horiz = mov_dir[1];   // LEFT / RIGHT
    wire slide_done  = slide_horiz ? (mx == tx) : (my == ty);

    // a new game starts at the next vblank after a press was taken
    wire begin_shuffle = tick && start_req &&
                         ((state == S_TITLE) || (state == S_PLAY) || (state == S_WIN));
    wire slide_commit  = (state == S_SLIDE) && tick && slide_done;
    wire load_solved   = rst || begin_shuffle;

    // ---- the board, and its only three writers
    // Kept in its own block, written out entry by entry: the VGA Playground's
    // Verilator rejects non-blocking writes to an array inside a for loop.
    always @(posedge clk) begin
        if (load_solved) begin
            board[0]  <= 4'd0;   board[1]  <= 4'd1;
            board[2]  <= 4'd2;   board[3]  <= 4'd3;
            board[4]  <= 4'd4;   board[5]  <= 4'd5;
            board[6]  <= 4'd6;   board[7]  <= 4'd7;
            board[8]  <= 4'd8;   board[9]  <= 4'd9;
            board[10] <= 4'd10;  board[11] <= 4'd11;
            board[12] <= 4'd12;  board[13] <= 4'd13;
            board[14] <= 4'd14;  board[15] <= 4'd15;
        end else if (shuf_step) begin           // the gap swaps with a neighbour
            board[gap]     <= board[shuf_nb];
            board[shuf_nb] <= GAP_TILE;
        end else if (slide_commit) begin        // the sliding tile lands
            board[gap]      <= mov_tile;
            board[mov_from] <= GAP_TILE;
        end
    end

    // ---- everything else
    always @(posedge clk) begin
        // the random source steps on every clock, whatever the game is doing,
        // so how long the player waits before pressing start decides the board
        lfsr <= {1'b0, lfsr[15:1]} ^ (lfsr[0] ? 16'hB400 : 16'h0000);
        iris_r2 <= iris_r * iris_r;

        if (rst) begin
            state      <= S_TITLE;
            gap        <= 4'd15;
            lfsr       <= 16'hACE1;
            shuf_cnt   <= 8'd0;
            last_dir   <= 2'd0;
            last_valid <= 1'b0;
            start_req  <= 1'b0;
            mov_tile   <= 4'd0;
            mov_from   <= 4'd0;
            mov_dir    <= 2'd0;
            mx         <= 10'd0;
            my         <= 10'd0;
            tx         <= 10'd0;
            ty         <= 10'd0;
            iris_r     <= 9'd0;
            shine_pos  <= SHINE_REST;
        end else if (begin_shuffle) begin
            // the board block loads the solved board on this same clock
            start_req  <= 1'b0;
            state      <= S_SHUFFLE;
            gap        <= 4'd15;
            shuf_cnt   <= 8'd0;
            last_valid <= 1'b0;
        end else begin
            case (state)
                // ------------------------------------------------------------
                S_TITLE: begin
                    if (any_press | press_start)
                        start_req <= 1'b1;
                    if (tick)
                        shine_pos <= shine_pos + 11'd12;
                end

                // ------------------------------------------------------------
                S_SHUFFLE: begin
                    if (shuf_step) begin
                        gap        <= shuf_nb;
                        last_dir   <= shuf_dir;
                        last_valid <= 1'b1;
                        shuf_cnt   <= shuf_cnt + 8'd1;
                    end else if (shuf_cnt == SHUFFLE_MOVES) begin
                        // the walk can come back to the start; go round again
                        if (solved)
                            shuf_cnt <= 8'd0;
                        else
                            state <= S_PLAY;
                    end
                end

                // ------------------------------------------------------------
                S_PLAY: begin
                    if (press_start)
                        start_req <= 1'b1;
                    if (tick && solved) begin
                        state  <= S_WIN;
                        iris_r <= 9'd0;
                    end else if (any_press && !peek && move_ok && !start_req) begin
                        // the tile next to the gap becomes a sprite sitting
                        // exactly where it was drawn, so this can happen
                        // mid-frame without a seam
                        mov_tile <= board[move_nb];
                        mov_from <= move_nb;
                        mov_dir  <= press_dir;
                        mx       <= slot_x(move_nb);
                        my       <= slot_y(move_nb);
                        tx       <= slot_x(gap);
                        ty       <= slot_y(gap);
                        state    <= S_SLIDE;
                    end
                end

                // ------------------------------------------------------------
                S_SLIDE: begin
                    // a start during a slide (the AX7010's up+down chord
                    // begins with a move) waits for it to land
                    if (press_start)
                        start_req <= 1'b1;
                    if (slide_commit) begin
                        gap   <= mov_from;
                        state <= S_PLAY;
                    end else if (tick) begin
                        case (mov_dir)
                            D_UP:    my <= my - {2'd0, STEP_Y};
                            D_DOWN:  my <= my + {2'd0, STEP_Y};
                            D_LEFT:  mx <= mx - {2'd0, STEP_X};
                            default: mx <= mx + {2'd0, STEP_X};
                        endcase
                    end
                end

                // ------------------------------------------------------------
                S_WIN: begin
                    if (any_press | press_start)
                        start_req <= 1'b1;
                    if (tick) begin
                        if (iris_r >= IRIS_END) begin
                            state     <= S_TITLE;
                            shine_pos <= SHINE_REST;
                        end else begin
                            iris_r <= iris_r + {1'b0, IRIS_STEP};
                        end
                    end
                end

                default: state <= S_TITLE;
            endcase
        end
    end

    // =================================================================
    // Stage 0: which tile, which pixel of it, which effects
    // =================================================================

    // slot under the beam: three comparators per axis, no divider
    wire [1:0] col = (x >= 10'd480) ? 2'd3 : (x >= 10'd320) ? 2'd2 :
                     (x >= 10'd160) ? 2'd1 : 2'd0;
    wire [1:0] row = (y >= 10'd360) ? 2'd3 : (y >= 10'd240) ? 2'd2 :
                     (y >= 10'd120) ? 2'd1 : 2'd0;
    wire [3:0] slot = {row, col};

    wire [9:0] slot_dx = x - slot_x(slot);
    wire [9:0] slot_dy = y - slot_y(slot);

    // the sliding tile, drawn as a 160x120 sprite at (mx, my)
    wire [9:0] spr_dx = x - mx;
    wire [9:0] spr_dy = y - my;
    wire in_sprite = (state == S_SLIDE) &&
                     (x >= mx) && (spr_dx < 10'd160) &&
                     (y >= my) && (spr_dy < 10'd120);

    // iris: squared distance from the centre, from unsigned |dx| and |dy|
    wire [9:0]  adx = (x >= 10'd320) ? (x - 10'd320) : (10'd320 - x);
    wire [9:0]  ady = (y >= 10'd240) ? (y - 10'd240) : (10'd240 - y);
    wire [19:0] dist2 = adx * adx + ady * ady;
    wire in_iris = (dist2 < {2'd0, iris_r2});

    // the finished picture (no gaps, no bevels) is what TITLE shows, what WIN
    // reveals inside the circle, and what a held peek shows during play
    wire full_view = (state == S_TITLE) || (state == S_SHUFFLE) ||
                     ((state == S_WIN) && in_iris) ||
                     ((state == S_PLAY) && peek);

    wire [3:0] slot_tile = board[slot];
    wire [3:0] tile = in_sprite ? mov_tile :
                      full_view ? slot     : slot_tile;
    wire [7:0] lx   = in_sprite ? spr_dx[7:0] : slot_dx[7:0];  // 0..159
    wire [6:0] ly   = in_sprite ? spr_dy[6:0] : slot_dy[6:0];  // 0..119

    // the gap: the missing tile, plus the slot a sliding tile has left
    wire is_gap = !in_sprite && !full_view &&
                  ((slot_tile == GAP_TILE) ||
                   ((state == S_SLIDE) && (slot == mov_from)));

    // source pixel: tile column*80 + lx/2, tile row*60 + ly/2
    wire [8:0]  src_x = {1'b0, tile[1:0], 6'd0} + {3'd0, tile[1:0], 4'd0}
                        + {2'd0, lx[7:1]};
    wire [7:0]  src_y = {tile[3:2], 6'd0} - {4'd0, tile[3:2], 2'd0}
                        + {2'd0, ly[6:1]};
    wire [16:0] addr  = {1'b0, src_y, 8'd0} + {3'd0, src_y, 6'd0}
                        + {8'd0, src_x};                    // src_y*320 + src_x

    // raised-tile bevel: light top/left edge, dark bottom/right edge
    wire bevel_hi = !full_view && ((lx < 8'd2)   || (ly < 7'd2));
    wire bevel_lo = !full_view && ((lx >= 8'd158) || (ly >= 7'd118));
    // the gap looks sunk in: a shadow along its top and left
    wire gap_shadow = (slot_dx < 10'd5) || (slot_dy < 10'd5);

    wire dim = (state == S_WIN) && !in_iris;

    // title shine: a diagonal band of light that sweeps across now and then
    wire [10:0] diag = {1'b0, x} + {1'b0, y};
    wire [10:0] shine_d = (diag >= shine_pos) ? (diag - shine_pos)
                                              : (shine_pos - diag);
    wire shine_hi = (state == S_TITLE) && (shine_d < 11'd8);
    wire shine_lo = (state == S_TITLE) && (shine_d < 11'd26);

    // =================================================================
    // Stages 1-3
    // =================================================================

    reg [7:0]  image_rom [0:76799];   // palette index per picture pixel
    reg [23:0] palette   [0:255];     // RRGGBB per index

    initial begin
        $readmemh("image.mem", image_rom);
        $readmemh("palette.mem", palette);
    end

    // flags carried down the pipeline: {de, hs, vs, gap, gap_shadow,
    //                                   bevel_hi, bevel_lo, dim, shine_hi, shine_lo}
    localparam FW = 10;
    wire [FW-1:0] flags0 = {~blank_in, hs_in, vs_in, is_gap, gap_shadow,
                            bevel_hi, bevel_lo, dim, shine_hi, shine_lo};

    reg [16:0]   addr1;
    reg [FW-1:0] flags1, flags2, flags3;
    reg [7:0]    idx2;
    reg [23:0]   rgb3;

    always @(posedge clk) begin
        addr1  <= addr;                 // stage 1
        flags1 <= flags0;

        idx2   <= image_rom[addr1];     // stage 2
        flags2 <= flags1;

        rgb3   <= palette[idx2];        // stage 3
        flags3 <= flags2;
    end

    wire f_de       = flags3[9];
    wire f_hs       = flags3[8];
    wire f_vs       = flags3[7];
    wire f_gap      = flags3[6];
    wire f_gapsh    = flags3[5];
    wire f_hi       = flags3[4];
    wire f_lo       = flags3[3];
    wire f_dim      = flags3[2];
    wire f_shine_hi = flags3[1];
    wire f_shine_lo = flags3[0];

    // one colour channel through the effects
    function [7:0] shade;
        input [7:0] c;
        input       hi, lo, dimmed, sh_hi, sh_lo;
        reg   [7:0] t;
        begin
            t = c;
            if (hi)          t = t + ((~t) >> 1);        // halfway to white
            else if (lo)     t = t >> 1;                 // half as bright
            if (sh_hi)       t = t + ((~t) >> 1);
            else if (sh_lo)  t = t + ((~t) >> 2);
            if (dimmed)      t = t >> 1;
            shade = t;
        end
    endfunction

    // the gap: a dark slate well, darker still in its shadow
    wire [7:0] gap_r = f_gapsh ? 8'd6  : 8'd18;
    wire [7:0] gap_g = f_gapsh ? 8'd6  : 8'd18;
    wire [7:0] gap_b = f_gapsh ? 8'd12 : 8'd30;

    always @(posedge clk) begin             // stage 4: outputs
        hs <= f_hs;
        vs <= f_vs;
        de <= f_de;
        if (!f_de) begin
            r <= 8'd0; g <= 8'd0; b <= 8'd0;
        end else if (f_gap) begin
            r <= f_dim ? (gap_r >> 1) : gap_r;
            g <= f_dim ? (gap_g >> 1) : gap_g;
            b <= f_dim ? (gap_b >> 1) : gap_b;
        end else begin
            r <= shade(rgb3[23:16], f_hi, f_lo, f_dim, f_shine_hi, f_shine_lo);
            g <= shade(rgb3[15:8],  f_hi, f_lo, f_dim, f_shine_hi, f_shine_lo);
            b <= shade(rgb3[7:0],   f_hi, f_lo, f_dim, f_shine_hi, f_shine_lo);
        end
    end

endmodule

`default_nettype wire
