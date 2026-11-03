//------------------------------------------------------------------------------
// hud_renderer.v
//
// Everything on screen that isn't the soul, the enemy or a bullet: the battle
// box frame, both HP bars, the attack cursor with its target guides, the state
// badges, and the numbers.
//
// There is no character generator in this project. A 1st-generation console
// could put digits on the screen - Pong's score came out of a diode ROM - but
// not sentences, so nothing here is written in words: the state of the game is
// told with shapes, and only the numbers are drawn with a font, using
// project01's own 5x7 digit_font unchanged.
//
//   y=16   bring-up read-out: the baud digit, one lamp per decoded button,
//          and a red lamp if the serial line is framing badly
//   y=176  damage from the last strike, two digits at 4x (S_HIT only)
//   y=216  enemy HP bar (240 px = 120 HP) + the same number in digits
//   y=250  battle box frame, 260x160, 4 px white border
//   y=298  state badge inside the box: a tick for a win, a cross for a loss
//   y=416  phase band under the box, which is how the game says what it wants:
//            TITLE  a blinking white bar          - press something
//            AIM    a chevron pointing up at the centre line
//            DODGE  diagonal hazard stripes       - the enemy's turn
//            WIN    a solid green bar             LOSE  a solid red bar
//   y=448  player HP bar (100 px = 40 HP) + the number
//
// The four digit fields sit on disjoint scanlines and every digit cell is a
// power of two wide, so one digit_font serves all of them: the field picks the
// digit, the cell index is a shift of x, and the glyph row and column are the
// low bits - the same sharing trick the previous version used on its 8x16 text
// font, minus the font. digit_font is combinational, so one register stage
// puts this layer in step with the 2-clock latency of the others.
//------------------------------------------------------------------------------
module hud_renderer #(
    parameter integer BOX_L  = 190,
    parameter integer BOX_T  = 250,
    parameter integer BOX_W  = 260,
    parameter integer BOX_H  = 160,
    parameter integer BORDER = 4
)(
    input  wire        clk,
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire [2:0]  state,
    input  wire [9:0]  timer,
    input  wire        blink,       // free-running ~1 Hz, for the attract prompt
    input  wire [5:0]  player_hp,   // 0..40
    input  wire [6:0]  enemy_hp,    // 0..120
    input  wire [9:0]  cursor_x,
    input  wire [4:0]  last_damage,
    input  wire [2:0]  dbg_baud,    // which serial rate is selected
    input  wire [4:0]  dbg_btn,     // decoded: up down left right confirm
    input  wire [7:0]  dbg_err,     // frames that arrived without a stop bit
    output reg  [11:0] color,       // valid 2 clocks after x/y
    output reg         visible
);

    localparam [2:0] S_TITLE = 3'd0,
                     S_AIM   = 3'd1,
                     S_HIT   = 3'd2,
                     S_DODGE = 3'd3,
                     S_WIN   = 3'd4,
                     S_LOSE  = 3'd5;

    // ---- layout ------------------------------------------------------------
    localparam integer INNER_L  = BOX_L + BORDER;
    localparam integer INNER_T  = BOX_T + BORDER;
    localparam integer INNER_R  = BOX_L + BOX_W - BORDER - 1;
    localparam integer INNER_B  = BOX_T + BOX_H - BORDER - 1;
    localparam integer CENTER_X = BOX_L + BOX_W / 2;
    localparam integer CENTER_Y = BOX_T + BOX_H / 2;

    localparam integer DBG_X   = 16,  DBG_Y  = 16;    // baud digit, 2x
    localparam integer LAMP_X  = 40,  LAMP_Y = 18;    // button lamps
    localparam integer DMG_X   = 292, DMG_Y  = 176;   // damage, 2 digits at 4x
    localparam integer EBAR_X  = 200, EBAR_Y = 216, EBAR_W = 240, EBAR_H = 12;
    localparam integer ENUM_X  = 452, ENUM_Y = 215;   // enemy HP, 3 digits at 2x
    localparam integer BAND_X  = BOX_L, BAND_Y = 416, BAND_W = BOX_W, BAND_H = 14;
    localparam integer HPBAR_X = 248, HPBAR_Y = 450, HPBAR_W = 100, HPBAR_H = 12;
    localparam integer HPNUM_X = 360, HPNUM_Y = 448;  // player HP, 2 digits at 2x

    localparam [11:0] C_BORDER   = 12'hFFF;
    localparam [11:0] C_HP_FULL  = 12'hFF0;   // yellow, like the original
    localparam [11:0] C_HP_EMPTY = 12'h600;
    localparam [11:0] C_EN_FULL  = 12'h3D5;   // green enemy bar
    localparam [11:0] C_EN_EMPTY = 12'h333;
    localparam [11:0] C_GUIDE    = 12'h555;   // scoring-tier marks
    localparam [11:0] C_BULLSEYE = 12'hFF0;
    localparam [11:0] C_CURSOR   = 12'hEEF;
    localparam [11:0] C_DMG      = 12'hFF4;
    localparam [11:0] C_LAMP_ON  = 12'hEEF;
    localparam [11:0] C_LAMP_OFF = 12'h223;
    localparam [11:0] C_LAMP_ERR = 12'hF22;
    localparam [11:0] C_WIN      = 12'h3E6;
    localparam [11:0] C_LOSE     = 12'hE22;
    localparam [11:0] C_HAZARD   = 12'h922;
    localparam [11:0] C_HAZARD2  = 12'h300;

    // ---- binary to three decimal digits ------------------------------------
    // four conditional subtractions, which is what a hardwired scoreboard did
    // before anyone had a divider to spare
    function [11:0] bcd3(input [7:0] v);
        reg [7:0] r;
        reg [3:0] t;
        reg [3:0] h;
        begin
            h = 4'd0;
            r = v;
            if (r >= 8'd100) begin h = 4'd1; r = r - 8'd100; end
            t = 4'd0;
            if (r >= 8'd80)  begin t = t + 4'd8; r = r - 8'd80; end
            if (r >= 8'd40)  begin t = t + 4'd4; r = r - 8'd40; end
            if (r >= 8'd20)  begin t = t + 4'd2; r = r - 8'd20; end
            if (r >= 8'd10)  begin t = t + 4'd1; r = r - 8'd10; end
            bcd3 = {h, t, r[3:0]};
        end
    endfunction

    wire [11:0] hp_bcd  = bcd3({2'd0, player_hp});
    wire [11:0] en_bcd  = bcd3({1'd0, enemy_hp});
    wire [11:0] dmg_bcd = bcd3({3'd0, last_damage});

    // ---- digit fields ------------------------------------------------------
    // every cell is 16 px wide at 2x and 32 at 4x, so the cell index is a
    // shift and the glyph row/column are the low bits
    wire in_dbg = (x >= DBG_X) && (x < DBG_X + 16) &&
                  (y >= DBG_Y) && (y < DBG_Y + 16);
    wire in_dmg = (state == S_HIT) &&
                  (x >= DMG_X) && (x < DMG_X + 64) &&
                  (y >= DMG_Y) && (y < DMG_Y + 32);
    wire in_enum = (x >= ENUM_X) && (x < ENUM_X + 48) &&
                   (y >= ENUM_Y) && (y < ENUM_Y + 16);
    wire in_hpnum = (x >= HPNUM_X) && (x < HPNUM_X + 32) &&
                    (y >= HPNUM_Y) && (y < HPNUM_Y + 16);

    wire [5:0] dbg_dx   = x - DBG_X;
    wire [6:0] dmg_dx   = x - DMG_X;
    wire [5:0] enum_dx  = x - ENUM_X;
    wire [5:0] hpnum_dx = x - HPNUM_X;

    reg  [3:0] dig;        // the digit to draw (>9 blanks the cell)
    reg  [2:0] dig_row;
    reg  [2:0] dig_col;
    reg        dig_in;     // inside the 5x7 glyph rather than the cell margin
    reg [11:0] dig_color;

    always @(*) begin
        dig       = 4'hF;
        dig_row   = 3'd0;
        dig_col   = 3'd0;
        dig_in    = 1'b0;
        dig_color = C_BORDER;
        if (in_dbg) begin                                    // baud rate, 2x
            dig       = {1'b0, dbg_baud};
            dig_row   = (y - DBG_Y) >> 1;
            dig_col   = dbg_dx[3:1];
            dig_in    = (dbg_dx[3:0] < 4'd10);
        end else if (in_dmg) begin                           // damage, 4x
            dig       = dmg_dx[5] ? dmg_bcd[3:0]
                                  : (dmg_bcd[7:4] == 4'd0 ? 4'hF : dmg_bcd[7:4]);
            dig_row   = (y - DMG_Y) >> 2;
            dig_col   = dmg_dx[4:2];
            dig_in    = (dmg_dx[4:0] < 5'd20);
            dig_color = C_DMG;
        end else if (in_enum) begin                          // enemy HP, 2x
            case (enum_dx[5:4])
            2'd0:    dig = (en_bcd[11:8] == 4'd0) ? 4'hF : en_bcd[11:8];
            2'd1:    dig = (en_bcd[11:4] == 8'd0) ? 4'hF : en_bcd[7:4];
            default: dig = en_bcd[3:0];
            endcase
            dig_row   = (y - ENUM_Y) >> 1;
            dig_col   = enum_dx[3:1];
            dig_in    = (enum_dx[3:0] < 4'd10);
            dig_color = C_EN_FULL;
        end else if (in_hpnum) begin                         // player HP, 2x
            dig       = hpnum_dx[4] ? hp_bcd[3:0]
                                    : (hp_bcd[7:4] == 4'd0 ? 4'hF : hp_bcd[7:4]);
            dig_row   = (y - HPNUM_Y) >> 1;
            dig_col   = hpnum_dx[3:1];
            dig_in    = (hpnum_dx[3:0] < 4'd10);
            dig_color = C_HP_FULL;
        end
    end

    wire [4:0] glyph_row;

    digit_font u_font (
        .digit    (dig),
        .row      (dig_row),
        .row_bits (glyph_row)
    );

    wire dig_px = dig_in && glyph_row[3'd4 - dig_col];

    // ---- the battle box ----------------------------------------------------
    wire in_box_outer = (x >= BOX_L) && (x < BOX_L + BOX_W) &&
                        (y >= BOX_T) && (y < BOX_T + BOX_H);
    wire in_box_inner = (x >= INNER_L) && (x <= INNER_R) &&
                        (y >= INNER_T) && (y <= INNER_B);

    // ---- HP bars: 2.5 px of bar per player HP (100 px = 40), 2 px per enemy
    // HP (240 px = 120). The half pixel is a shift, and rounds invisibly.
    wire [9:0] hp_fill = {3'd0, player_hp, 1'b0} + {5'd0, player_hp[5:1]};
    wire [9:0] en_fill = {2'd0, enemy_hp,  1'b0};
    wire in_hpbar = (x >= HPBAR_X) && (x < HPBAR_X + HPBAR_W) &&
                    (y >= HPBAR_Y) && (y < HPBAR_Y + HPBAR_H);
    wire in_enbar = (x >= EBAR_X) && (x < EBAR_X + EBAR_W) &&
                    (y >= EBAR_Y) && (y < EBAR_Y + EBAR_H);

    // ---- the attack cursor + the tier marks it is aimed at ------------------
    wire aim_phase   = (state == S_AIM) || (state == S_HIT);
    wire cursor_show = (state == S_AIM) || timer[2];   // frozen cursor blinks
    wire in_strip    = in_box_inner;
    wire in_cursor   = in_strip && (x >= cursor_x) && (x < cursor_x + 10'd4);
    wire in_bulls    = in_strip && (x >= CENTER_X - 1) && (x <= CENTER_X);
    wire in_guide    = in_strip && ((x == CENTER_X - 18) || (x == CENTER_X + 18) ||
                                    (x == CENTER_X - 40) || (x == CENTER_X + 40));

    // ---- the phase band under the box --------------------------------------
    wire in_band = (x >= BAND_X) && (x < BAND_X + BAND_W) &&
                   (y >= BAND_Y) && (y < BAND_Y + BAND_H);

    // a chevron pointing up at the centre line, for your turn
    wire [9:0] band_ax = (x >= CENTER_X) ? (x - CENTER_X) : (CENTER_X - x);
    wire in_chevron = in_band && ((band_ax <= ((y - BAND_Y) << 1)) ||
                                  (y >= BAND_Y + BAND_H - 3));
    // diagonal hazard stripes, for the enemy's turn: one bit of x + y
    wire [10:0] hazard_sum = {1'b0, x} + {1'b0, y};
    wire        hazard_lit = hazard_sum[3];

    // ---- the state badge inside the box ------------------------------------
    // a tick for a win, a cross for a loss - two thick diagonal bars either
    // way, which is |ux - uy| and |ux + uy| against a constant
    wire signed [10:0] ux = $signed({1'b0, x}) - $signed(11'd0 + CENTER_X);
    wire signed [10:0] uy = $signed({1'b0, y}) - $signed(11'd0 + CENTER_Y);
    wire signed [10:0] dsum = ux + uy;
    wire signed [10:0] ddif = ux - uy;
    wire [10:0] asum = dsum[10] ? -dsum : dsum;
    wire [10:0] adif = ddif[10] ? -ddif : ddif;
    wire [10:0] aux  = ux[10] ? -ux : ux;
    wire [10:0] auy  = uy[10] ? -uy : uy;

    wire cross_arm = (asum <= 11'd5) || (adif <= 11'd5);
    wire badge_box = (aux <= 11'd28) && (auy <= 11'd28);
    // the short stroke runs down-right (ux - uy = -24), the long one up-right
    // (ux + uy = 8); each is a 11 px band about its own line
    wire tick_down = (ddif >= -11'sd29) && (ddif <= -11'sd19) &&
                     (ux   >= -11'sd28) && (ux   <= -11'sd6);
    wire tick_up   = (dsum >=  11'sd3)  && (dsum <=  11'sd13) &&
                     (ux   >= -11'sd10) && (ux   <=  11'sd28);

    wire badge_win  = (state == S_WIN)  && (tick_down || tick_up);
    wire badge_lose = (state == S_LOSE) && badge_box && cross_arm;

    // ---- the bring-up lamps -------------------------------------------------
    // one per decoded button, plus a red one that lights if the serial line is
    // framing badly - the whole of the old on-screen read-out that survives
    // without a text font, and all of it that was ever used after bring-up
    wire in_lamps = (y >= LAMP_Y) && (y < LAMP_Y + 10) &&
                    (x >= LAMP_X) && (x < LAMP_X + 6 * 16);
    wire [6:0] lamp_dx = x - LAMP_X;          // 16 px per lamp, 10 px lit
    wire [2:0] lamp_i  = lamp_dx[6:4];
    wire lamp_cell = in_lamps && (lamp_dx[3:0] < 4'd10);
    wire lamp_err  = (lamp_i == 3'd5);
    wire lamp_lit  = lamp_err ? (dbg_err != 8'd0) : dbg_btn[3'd4 - lamp_i];

    // ---- stage 0: everything that isn't a digit ----------------------------
    reg [11:0] ov_color;
    reg        ov_hit;
    always @(*) begin
        ov_color = 12'h000;
        ov_hit   = 1'b0;
        if (lamp_cell) begin
            ov_color = !lamp_lit ? C_LAMP_OFF :
                       lamp_err  ? C_LAMP_ERR : C_LAMP_ON;
            ov_hit   = 1'b1;
        end
        if (in_box_outer && !in_box_inner) begin
            ov_color = C_BORDER; ov_hit = 1'b1;
        end
        if (in_enbar) begin
            ov_color = ((x - EBAR_X) < en_fill) ? C_EN_FULL : C_EN_EMPTY;
            ov_hit   = 1'b1;
        end
        if (in_hpbar) begin
            ov_color = ((x - HPBAR_X) < hp_fill) ? C_HP_FULL : C_HP_EMPTY;
            ov_hit   = 1'b1;
        end
        if (aim_phase) begin
            if (in_guide) begin ov_color = C_GUIDE;    ov_hit = 1'b1; end
            if (in_bulls) begin ov_color = C_BULLSEYE; ov_hit = 1'b1; end
            if (in_cursor && cursor_show) begin
                ov_color = C_CURSOR; ov_hit = 1'b1;
            end
        end
        if (badge_win)  begin ov_color = C_WIN;  ov_hit = 1'b1; end
        if (badge_lose) begin ov_color = C_LOSE; ov_hit = 1'b1; end
        if (in_band) begin
            case (state)
            S_TITLE: if (blink && (y >= BAND_Y + 4) && (y < BAND_Y + 10)) begin
                         ov_color = C_BORDER; ov_hit = 1'b1;
                     end
            S_AIM,
            S_HIT:   if (in_chevron) begin
                         ov_color = C_BULLSEYE; ov_hit = 1'b1;
                     end
            S_DODGE: begin
                         ov_color = hazard_lit ? C_HAZARD : C_HAZARD2;
                         ov_hit   = 1'b1;
                     end
            S_WIN:   begin ov_color = C_WIN;  ov_hit = 1'b1; end
            S_LOSE:  begin ov_color = C_LOSE; ov_hit = 1'b1; end
            default: ;
            endcase
        end
    end

    // ---- stage 1 -----------------------------------------------------------
    reg [11:0] ov_color_d1 = 12'h000;
    reg        ov_hit_d1   = 1'b0;
    reg        dig_px_d1   = 1'b0;
    reg [11:0] dig_col_d1  = 12'h000;

    always @(posedge clk) begin
        ov_color_d1 <= ov_color;
        ov_hit_d1   <= ov_hit;
        dig_px_d1   <= dig_px;
        dig_col_d1  <= dig_color;
    end

    // ---- stage 2: digits win over the overlay ------------------------------
    always @(posedge clk) begin
        color   <= dig_px_d1 ? dig_col_d1 : ov_color_d1;
        visible <= dig_px_d1 | ov_hit_d1;
    end

endmodule
