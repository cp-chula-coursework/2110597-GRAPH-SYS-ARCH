//------------------------------------------------------------------------------
// text_editor.v
//
// Arcade-style text editor: a blinking block cursor moves over the 80x30
// grid and the character under it is cycled with two buttons (like entering
// initials on an arcade high-score screen) - the AX7010 has no keyboard
// connector, so the slides' PS/2 input stage becomes button input here.
//
//   ev[0] cursor right (wraps to next line, then back to top)
//   ev[1] cursor down  (wraps back to top)
//   ev[2] next character:      space -> 'A' -> 'B' ... '~' -> space
//   ev[3] previous character:  space -> '~' -> '}' ... '!' -> space
//   hold ev[2]+ev[3] buttons for CLEAR_HOLD_FRAMES -> clear screen
//
// Cycling needs to know what's under the cursor, but the tile RAM's read
// port belongs to the renderer. The renderer only needs it during active
// video, so this module gets it during blanking: the top level points the
// read port at the cursor cell whenever blank=1, and cur_char captures the
// returned value (every scanline's h-blank refreshes it, so it is always
// current long before the next button event).
//
// A clear sweep (write space to all 2400 cells) runs at power-up and on the
// clear combo; `busy` is high while sweeping.
//------------------------------------------------------------------------------
module text_editor #(
    parameter integer CLEAR_HOLD_FRAMES = 60   // ~1 s at 60 Hz
)(
    input  wire        clk,          // pixel clock
    input  wire        frame_tick,
    input  wire        active,       // editor mode (button events honored)
    input  wire [3:0]  ev,           // event pulses from button_input
    input  wire [3:0]  held,         // debounced button levels

    // cursor-cell read-back (tile RAM port B, granted during blanking)
    input  wire        blank,
    input  wire [7:0]  ram_dout,
    output wire [11:0] rb_addr,

    // tile RAM write port
    output reg         we,
    output reg  [11:0] waddr,
    output reg  [7:0]  wdata,

    output reg  [6:0]  cur_x,          // 0..79
    output reg  [4:0]  cur_y,          // 0..29
    output wire        busy
);

    initial begin
        we    = 1'b0;
        waddr = 12'd0;
        wdata = 8'h20;
        cur_x = 7'd0;
        cur_y = 5'd0;
    end

    localparam [6:0] CH_SPACE = 7'h20;
    localparam [6:0] CH_A     = 7'h41;
    localparam [6:0] CH_LAST  = 7'h7E;  // '~'

    wire [11:0] cur_addr = {7'd0, cur_y} * 12'd80 + {5'd0, cur_x};
    assign rb_addr = cur_addr;

    //--------------------------------------------------------------------------
    // Track the character under the cursor. ram_dout holds the cursor cell
    // one clock after a blanking cycle (registered read); a write from this
    // module updates the copy directly.
    //--------------------------------------------------------------------------
    reg blank_q = 1'b0;
    reg [6:0] cur_char = CH_SPACE;

    always @(posedge clk)
        blank_q <= blank;

    //--------------------------------------------------------------------------
    // Character cycling (suppressed while both cycle buttons are held, so
    // the clear combo doesn't type garbage on its way to triggering)
    //--------------------------------------------------------------------------
    wire ev_next = ev[2] && !held[3];
    wire ev_prev = ev[3] && !held[2];

    // space jumps straight to 'A' going forward so typing starts fast
    wire [6:0] next_char = (cur_char == CH_SPACE) ? CH_A :
                           (cur_char == CH_LAST)  ? CH_SPACE : cur_char + 7'd1;
    wire [6:0] prev_char = (cur_char == CH_SPACE) ? CH_LAST : cur_char - 7'd1;

    //--------------------------------------------------------------------------
    // Clear sweep FSM: runs once at power-up, and again when both cycle
    // buttons are held for CLEAR_HOLD_FRAMES
    //--------------------------------------------------------------------------
    localparam S_CLEAR = 1'b0, S_RUN = 1'b1;
    reg state = S_CLEAR;
    reg [11:0] clr_addr = 12'd0;
    reg [$clog2(CLEAR_HOLD_FRAMES+1)-1:0] hold_cnt = 0;

    assign busy = (state == S_CLEAR);

    always @(posedge clk) begin
        we <= 1'b0;

        case (state)
            S_CLEAR: begin
                we    <= 1'b1;
                waddr <= clr_addr;
                wdata <= {1'b0, CH_SPACE};
                if (clr_addr == 12'd2399) begin
                    state    <= S_RUN;
                    clr_addr <= 12'd0;
                    cur_x    <= 7'd0;
                    cur_y    <= 5'd0;
                    cur_char <= CH_SPACE;
                end else
                    clr_addr <= clr_addr + 12'd1;
            end

            S_RUN: begin
                // clear combo timer
                if (!(active && held[2] && held[3]))
                    hold_cnt <= 0;
                else if (frame_tick) begin
                    if (hold_cnt == CLEAR_HOLD_FRAMES - 1) begin
                        hold_cnt <= 0;
                        state    <= S_CLEAR;
                    end else
                        hold_cnt <= hold_cnt + 1;
                end

                if (active) begin
                    // movement takes priority over cycling in the (rare)
                    // same-cycle case, so a stale cur_char is never written
                    if (ev[0]) begin                       // right
                        if (cur_x == 7'd79) begin
                            cur_x <= 7'd0;
                            cur_y <= (cur_y == 5'd29) ? 5'd0 : cur_y + 5'd1;
                        end else
                            cur_x <= cur_x + 7'd1;
                    end else if (ev[1]) begin              // down
                        cur_y <= (cur_y == 5'd29) ? 5'd0 : cur_y + 5'd1;
                    end else if (ev_next || ev_prev) begin // cycle character
                        we       <= 1'b1;
                        waddr    <= cur_addr;
                        wdata    <= {1'b0, ev_next ? next_char : prev_char};
                        cur_char <= ev_next ? next_char : prev_char;
                    end else if (blank_q) begin
                        // refresh the cursor-cell copy from the RAM whenever
                        // nothing changed it this cycle
                        cur_char <= ram_dout[6:0];
                    end
                end else if (blank_q)
                    cur_char <= ram_dout[6:0];
            end
        endcase
    end

endmodule
