//------------------------------------------------------------------------------
// matrix_rain.v
//
// "Matrix" digital-rain screensaver generator. Owns the write port of its
// own tile RAM (separate from the editor's, so the user's text survives the
// screensaver untouched).
//
// Each of the 80 columns runs an independent falling stream: a bright head
// character steps down the column, the cell above it is rewritten as a
// normal-intensity random character (the streams visibly "mutate"), and the
// cell TAIL rows above the head is erased. When a stream falls off the
// bottom, its column restarts from the top after a random delay with a new
// random speed. Randomness comes from one free-running 17-bit maximal LFSR.
//
// Per-column state is updated by a sequential sweep triggered once per
// frame (frame_tick lands at the start of vertical blanking; a sweep is at
// most ~400 clocks, so it always finishes deep inside vblank). On `init`
// (entering screensaver mode) all columns are reseeded and the RAM is
// cleared first.
//------------------------------------------------------------------------------
module matrix_rain #(
    parameter integer TAIL = 12   // stream length in rows
)(
    input  wire        clk,          // pixel clock
    input  wire        frame_tick,
    input  wire        enable,       // screensaver mode active
    input  wire        init,         // 1-clock pulse: reseed + clear RAM

    // tile RAM write port
    output reg         we,
    output reg  [11:0] waddr,
    output reg  [7:0]  wdata
);

    localparam integer N_COLS  = 80;
    localparam integer N_ROWS  = 30;
    localparam integer RESTART = N_ROWS + TAIL - 1; // head value whose erase hits row 29

    //--------------------------------------------------------------------------
    // free-running randomness: x^17 + x^14 + 1 maximal LFSR
    //--------------------------------------------------------------------------
    reg [16:0] lfsr = 17'h1ACE5;
    always @(posedge clk)
        lfsr <= {lfsr[15:0], lfsr[16] ^ lfsr[13]};

    // map a raw 7-bit value onto visible ASCII 0x21..0x7E
    function [6:0] rnd_char(input [6:0] v);
        rnd_char = (v < 7'h21) ? (v + 7'h21) :
                   (v == 7'h7F) ? 7'h21 : v;
    endfunction

    //--------------------------------------------------------------------------
    // per-column stream state
    //--------------------------------------------------------------------------
    reg [5:0] head   [0:N_COLS-1];  // current head row (63 = wraps to 0 next step)
    reg [2:0] period [0:N_COLS-1];  // frames per step (2..5)
    reg [5:0] timer  [0:N_COLS-1];  // frames until next step / restart delay

    integer k;
    initial begin
        we    = 1'b0;
        waddr = 12'd0;
        wdata = 8'h20;
        for (k = 0; k < N_COLS; k = k + 1) begin
            head[k]   = 6'd63;
            period[k] = 3'd3;
            timer[k]  = k[5:0];
        end
    end

    //--------------------------------------------------------------------------
    // sweep FSM
    //--------------------------------------------------------------------------
    localparam [2:0] ST_IDLE   = 3'd0,
                     ST_SEED   = 3'd1,
                     ST_CLEAR  = 3'd2,
                     ST_COL    = 3'd3,
                     ST_WHEAD  = 3'd4,
                     ST_WDIM   = 3'd5,
                     ST_WERASE = 3'd6;

    reg [2:0]  state = ST_IDLE;
    reg [6:0]  c = 7'd0;            // column being processed
    reg [11:0] clr_addr = 12'd0;
    reg [5:0]  h = 6'd0;            // head row captured for the write slots
    reg [6:0]  wcol = 7'd0;

    wire [5:0] head_next = head[c] + 6'd1;

    always @(posedge clk) begin
        we <= 1'b0;

        if (init) begin
            // entering screensaver mode: reseed everything (overrides any
            // sweep in flight)
            c     <= 7'd0;
            state <= ST_SEED;
        end else
        case (state)
            ST_IDLE: begin
                c <= 7'd0;
                if (enable && frame_tick)
                    state <= ST_COL;
            end

            // reseed every column from the running LFSR (one per clock,
            // so each column samples a different LFSR state)
            ST_SEED: begin
                head[c]   <= 6'd63;
                period[c] <= 3'd2 + {1'b0, lfsr[1:0]};
                timer[c]  <= lfsr[11:6];
                if (c == N_COLS-1) begin
                    c        <= 7'd0;
                    clr_addr <= 12'd0;
                    state    <= ST_CLEAR;
                end else
                    c <= c + 7'd1;
            end

            ST_CLEAR: begin
                we    <= 1'b1;
                waddr <= clr_addr;
                wdata <= 8'h20;
                if (clr_addr == 12'd2399)
                    state <= ST_IDLE;
                else
                    clr_addr <= clr_addr + 12'd1;
            end

            ST_COL: begin
                if (timer[c] != 6'd0) begin
                    timer[c] <= timer[c] - 6'd1;
                    if (c == N_COLS-1)
                        state <= ST_IDLE;
                    else
                        c <= c + 7'd1;
                end else begin
                    h    <= head_next;
                    wcol <= c;
                    if (head_next == RESTART[5:0]) begin
                        // erase below will clear the last row; restart the
                        // stream from the top with fresh random parameters
                        head[c]   <= 6'd63;
                        period[c] <= 3'd2 + {1'b0, lfsr[1:0]};
                        timer[c]  <= lfsr[11:6];
                    end else begin
                        head[c]  <= head_next;
                        timer[c] <= {3'd0, period[c]};
                    end
                    state <= ST_WHEAD;
                end
            end

            // bright head character
            ST_WHEAD: begin
                if (h < N_ROWS[5:0]) begin
                    we    <= 1'b1;
                    waddr <= {6'd0, h} * 12'd80 + {5'd0, wcol};
                    wdata <= {1'b1, rnd_char(lfsr[6:0])};
                end
                state <= ST_WDIM;
            end

            // previous head drops to normal intensity (and mutates)
            ST_WDIM: begin
                if (h >= 6'd1 && (h - 6'd1) < N_ROWS[5:0]) begin
                    we    <= 1'b1;
                    waddr <= {6'd0, h - 6'd1} * 12'd80 + {5'd0, wcol};
                    wdata <= {1'b0, rnd_char(lfsr[6:0])};
                end
                state <= ST_WERASE;
            end

            // erase the tail end
            ST_WERASE: begin
                if (h >= TAIL[5:0] && (h - TAIL[5:0]) < N_ROWS[5:0]) begin
                    we    <= 1'b1;
                    waddr <= {6'd0, h - TAIL[5:0]} * 12'd80 + {5'd0, wcol};
                    wdata <= 8'h20;
                end
                if (c == N_COLS-1)
                    state <= ST_IDLE;
                else begin
                    c     <= c + 7'd1;
                    state <= ST_COL;
                end
            end

            default: state <= ST_IDLE;
        endcase
    end

endmodule
