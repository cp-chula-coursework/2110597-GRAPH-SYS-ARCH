//------------------------------------------------------------------------------
// pong.v
//
// Pong game logic: ball/paddle physics, one human paddle (btn_up/btn_dn) vs.
// one AI paddle, score tracking, and a ball speedup-per-rally mechanic.
//
// This is a direct port of the base "PONG part I / part II" code taught in
// the course slides (05_PONG_History_and_Project.pdf), restructured to take
// pixel coordinates/VS from an external vga_timing module (this board drives
// HDMI, not a VGA DAC, so timing generation and final RGB blanking live in
// top.v instead of being embedded in this module) and extended with:
//   - score_l / score_r: point counters, saturating at 9, incremented on
//     each miss (coll_r -> left player scored, coll_l -> right/AI scored)
//   - a ball speedup every SPEEDUP paddle hits within a rally (the slides
//     declare the SPEEDUP parameter but never wire it up - this implements
//     the "new gameplay mechanics" extension the assignment asks for)
//   - digit rendering of the score via digit_font, and a center net line
//     (background effect) as a second requested extension
//------------------------------------------------------------------------------
module pong (
    input  wire        clk,        // pixel clock (25.175 MHz)
    input  wire        VS,
    input  wire        btn_reset,
    input  wire        btn_up,
    input  wire        btn_dn,
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    output reg  [3:0]  RED,
    output reg  [3:0]  GREEN,
    output reg  [3:0]  BLUE
);

    // ---- obj representation ----
    localparam BALL_SIZE = 8;   // ball size in pixels
    localparam BALL_ISPX = 5;   // initial horizontal ball speed
    localparam BALL_ISPY = 3;   // initial vertical ball speed
    localparam PAD_HEIGHT = 48; // paddle height in pixels
    localparam PAD_WIDTH  = 10; // paddle width in pixels
    localparam PAD_OFFS   = 32; // paddle distance from edge of screen in pixels
    localparam PAD_SPY    = 3;  // vertical paddle speed
    localparam SPEEDUP    = 5;  // speed up ball after this many paddle hits
    localparam MAX_SPX    = BALL_ISPX + 4; // speed cap, keeps collision math safe
    localparam MAX_SPY    = BALL_ISPY + 4;

    reg        ball, padl, padr, net, digit_px;
    reg [9:0]  ball_x, ball_y;      // position (origin at top left)
    reg [9:0]  ball_spx, ball_spy;
    reg        ball_dx = 1'b0, ball_dy = 1'b0; // direction: 0 is right/down
    reg        coll_l = 1'b0, coll_r = 1'b0;
    reg [9:0]  padl_y, padr_y;      // vertical position of left and right paddles
    reg [3:0]  hit_count = 4'd0;    // paddle hits this rally, drives speedup
    reg [3:0]  score_l = 4'd0, score_r = 4'd0; // 0-9, saturating; only cleared by btn_reset

    // ---- game state ----
    parameter NEW_GAME = 2'b00, PLAY = 2'b01;
    reg [1:0] state = NEW_GAME;

    // ---- game logic: ball motion, serve, wall/paddle collision ----
    always @(posedge VS) begin
        case (state)
            NEW_GAME: begin
                coll_l    <= 1'b0;   // reset screen collision flags
                coll_r    <= 1'b0;
                ball_spx  <= BALL_ISPX; // reset speed
                ball_spy  <= BALL_ISPY;
                hit_count <= 4'd0;
                ball_y    <= (480 - BALL_SIZE) / 2;
                if (coll_r) begin
                    ball_x  <= 640 - (PAD_OFFS + PAD_WIDTH + BALL_SIZE);
                    ball_dx <= 1'b1; // move left
                end else begin
                    ball_x  <= PAD_OFFS + PAD_WIDTH;
                    ball_dx <= 1'b0; // move right
                end

                state <= PLAY;
            end

            PLAY: begin
                // horizontal ball position
                if (ball_dx == 1'b0) begin // moving right
                    if (ball_x + BALL_SIZE + ball_spx >= 640 - 1) begin
                        ball_x <= 640 - BALL_SIZE; // move to edge of screen
                        coll_r <= 1'b1;
                    end else if ((ball_x + BALL_SIZE + ball_spx >= 640 - PAD_OFFS - PAD_WIDTH - 1) &&
                                 (ball_y + BALL_SIZE >= padr_y) &&
                                 (ball_y <= padr_y + PAD_HEIGHT)) begin
                        ball_dx <= 1'b1;
                        if (hit_count == SPEEDUP - 1) begin
                            hit_count <= 4'd0;
                            if (ball_spx < MAX_SPX) ball_spx <= ball_spx + 1'b1;
                            if (ball_spy < MAX_SPY) ball_spy <= ball_spy + 1'b1;
                        end else begin
                            hit_count <= hit_count + 1'b1;
                        end
                    end else ball_x <= ball_x + ball_spx;
                end else begin // moving left
                    if (ball_x < ball_spx) begin
                        ball_x <= 0; // move to edge of screen
                        coll_l <= 1'b1;
                    end else if ((ball_x - ball_spx <= PAD_OFFS + PAD_WIDTH) &&
                                 (ball_y + BALL_SIZE >= padl_y) &&
                                 (ball_y <= padl_y + PAD_HEIGHT)) begin
                        ball_dx <= 1'b0;
                        if (hit_count == SPEEDUP - 1) begin
                            hit_count <= 4'd0;
                            if (ball_spx < MAX_SPX) ball_spx <= ball_spx + 1'b1;
                            if (ball_spy < MAX_SPY) ball_spy <= ball_spy + 1'b1;
                        end else begin
                            hit_count <= hit_count + 1'b1;
                        end
                    end else ball_x <= ball_x - ball_spx;
                end

                // vertical ball position
                if (ball_dy == 1'b0) begin // moving down
                    if (ball_y + BALL_SIZE + ball_spy >= 480 - 1)
                        ball_dy <= 1'b1; // move up next frame
                    else ball_y <= ball_y + ball_spy;
                end else begin // moving up
                    if (ball_y < ball_spy)
                        ball_dy <= 1'b0; // move down next frame
                    else ball_y <= ball_y - ball_spy;
                end

                if (coll_l || coll_r) state <= NEW_GAME;
                else state <= PLAY;
            end
        endcase

        if (btn_reset) state <= NEW_GAME;
    end

    // ---- score tracking ----
    // coll_r fires when the right (AI) paddle missed -> left player scored.
    // coll_l fires when the left (human) paddle missed -> right/AI scored.
    // Read here in the same cycle state transitions out of NEW_GAME, so
    // these see the coll_l/coll_r values captured during the just-finished
    // rally (non-blocking assignment semantics - same pattern the serve
    // logic above relies on).
    always @(posedge VS) begin
        if (btn_reset) begin
            score_l <= 4'd0;
            score_r <= 4'd0;
        end else if (state == NEW_GAME) begin
            if (coll_r && score_l < 9) score_l <= score_l + 1'b1;
            if (coll_l && score_r < 9) score_r <= score_r + 1'b1;
        end
    end

    // ---- player paddle control ----
    always @(posedge VS) begin
        if (state == NEW_GAME) padl_y <= (480 - PAD_HEIGHT) / 2;
        else if (state == PLAY) begin
            if (btn_dn) begin
                if (padl_y + PAD_HEIGHT + PAD_SPY >= 480 - 1) begin // bottom of screen?
                    padl_y <= 480 - PAD_HEIGHT - 1; // move down as far as we can
                end else padl_y <= padl_y + PAD_SPY; // move down
            end else if (btn_up) begin
                if (padl_y < PAD_SPY) begin // top of screen
                    padl_y <= 0; // move up as far as we can
                end else padl_y <= padl_y - PAD_SPY; // move up
            end
        end
    end

    // ---- AI paddle control ----
    always @(posedge VS) begin
        if (state == NEW_GAME) padr_y <= (480 - PAD_HEIGHT) / 2;
        else if (state == PLAY) begin
            if (padr_y + PAD_HEIGHT / 2 < ball_y) begin
                if (padr_y + PAD_HEIGHT + PAD_SPY >= 480 - 1) begin
                    padr_y <= 480 - PAD_HEIGHT - 1;
                end else padr_y <= padr_y + PAD_SPY;
            end else if (padr_y + PAD_HEIGHT / 2 > ball_y + BALL_SIZE) begin
                if (padr_y < PAD_SPY) begin
                    padr_y <= 0;
                end else padr_y <= padr_y - PAD_SPY;
            end
        end
    end

    // ---- score digit layout (top-center, one glyph per player) ----
    localparam DIGIT_SCALE = 5;                    // on-screen pixels per font pixel
    localparam DIGIT_W     = 5 * DIGIT_SCALE;       // glyph width on screen
    localparam DIGIT_H     = 7 * DIGIT_SCALE;       // glyph height on screen
    localparam DIGIT_Y     = 16;                    // top margin
    localparam DIGIT_L_X   = 640 / 2 - 12 - DIGIT_W; // left digit, left of center
    localparam DIGIT_R_X   = 640 / 2 + 12;           // right digit, right of center

    wire in_digit_l = (x >= DIGIT_L_X) && (x < DIGIT_L_X + DIGIT_W) &&
                       (y >= DIGIT_Y)   && (y < DIGIT_Y + DIGIT_H);
    wire in_digit_r = (x >= DIGIT_R_X) && (x < DIGIT_R_X + DIGIT_W) &&
                       (y >= DIGIT_Y)   && (y < DIGIT_Y + DIGIT_H);

    wire [2:0] digit_row_l = (y - DIGIT_Y) / DIGIT_SCALE;
    wire [2:0] digit_col_l = (x - DIGIT_L_X) / DIGIT_SCALE;
    wire [2:0] digit_row_r = (y - DIGIT_Y) / DIGIT_SCALE;
    wire [2:0] digit_col_r = (x - DIGIT_R_X) / DIGIT_SCALE;

    wire [4:0] font_bits_l, font_bits_r;
    digit_font font_l (.digit(score_l), .row(digit_row_l), .row_bits(font_bits_l));
    digit_font font_r (.digit(score_r), .row(digit_row_r), .row_bits(font_bits_r));

    always @(*) begin
        digit_px = 1'b0;
        if (in_digit_l) digit_px = font_bits_l[4 - digit_col_l];
        else if (in_digit_r) digit_px = font_bits_r[4 - digit_col_r];
    end

    // ---- render obj bbox ----
    always @(*) begin
        ball = (x >= ball_x) && (x < ball_x + BALL_SIZE)
            && (y >= ball_y) && (y < ball_y + BALL_SIZE);
        padl = (x >= PAD_OFFS) && (x < PAD_OFFS + PAD_WIDTH)
            && (y >= padl_y) && (y < padl_y + PAD_HEIGHT);
        padr = (x >= 640 - PAD_OFFS - PAD_WIDTH) && (x < 640 - PAD_OFFS - 1)
            && (y >= padr_y) && (y < padr_y + PAD_HEIGHT);
        net  = (x >= 640/2 - 1) && (x < 640/2 + 1) && y[4]; // dashed center line
    end

    // ---- set obj color ----
    always @(*) begin
        if (ball) begin
            RED = 4'hF; GREEN = 4'h0; BLUE = 4'h0;
        end else if (padl || padr || digit_px) begin
            RED = 4'hF; GREEN = 4'hF; BLUE = 4'hF;
        end else if (net) begin
            RED = 4'h4; GREEN = 4'h4; BLUE = 4'h4;
        end else begin
            RED = 4'h0; GREEN = 4'h0; BLUE = 4'h0;
        end
    end

endmodule
