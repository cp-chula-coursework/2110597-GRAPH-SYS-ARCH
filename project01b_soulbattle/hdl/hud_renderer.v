//------------------------------------------------------------------------------
// hud_renderer.v
//
// Everything on screen that isn't a sprite or a bullet: the battle box frame,
// both HP bars, the attack cursor with its target guides, and four lines of
// text.
//
//   y=176  serial adapter read-out: baud, framing errors, last byte in,
//          the decoded directions, and the last four bytes raw
//   y=192  enemy name / damage read-out       (14 chars)
//   y=216  enemy HP bar (240 px = 120 HP)
//   y=250  battle box frame, 260x160, 4 px white border
//   y=288  centre message  (title / win / lose, 16 chars)
//   y=416  phase hint      (aim / dodge, 16 chars)
//   y=448  "HP" + player HP bar (100 px = 40 HP) + "nn / 40"
//
// Text reuses project02's 8x16 ASCII font_rom unchanged: the four text bands
// sit on disjoint scanlines, so a single font ROM port serves all of them -
// pick the band from y, the character index from x, then index the glyph row
// with y[3:0] and the glyph column with x[2:0]. That last shortcut is why
// every band starts on a multiple of 16 in y and of 8 in x, exactly like the
// character grid in project02's text_renderer. Font data comes back 1 clock
// after the address, so one more register stage puts this layer's 2-clock
// latency in step with the sprite layers.
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
    input  wire [63:0] dbg_bytes,   // last 8 bytes off the serial adapter
    input  wire [2:0]  dbg_baud,    // which rate is selected
    input  wire [7:0]  dbg_last,    // last byte the adapter sent
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

    localparam integer DBG_X = 232, DBG_Y = 176, DBG_N = 23;
    localparam integer NAME_X = 264, NAME_Y = 192, NAME_N = 14;
    localparam integer EBAR_X = 200, EBAR_Y = 216, EBAR_W = 240, EBAR_H = 12;
    localparam integer MSG_X  = 256, MSG_Y  = 288;
    localparam integer HINT_X = 256, HINT_Y = 416;
    localparam integer HUD_Y  = 448;
    localparam integer HPLBL_X = 224;
    localparam integer HPBAR_X = 248, HPBAR_Y = 450, HPBAR_W = 100, HPBAR_H = 12;
    localparam integer HPNUM_X = 360;

    localparam [11:0] C_TEXT     = 12'hFFF;
    localparam [11:0] C_BORDER   = 12'hFFF;
    localparam [11:0] C_HP_FULL  = 12'hFF0;   // yellow, like the original
    localparam [11:0] C_HP_EMPTY = 12'h600;
    localparam [11:0] C_EN_FULL  = 12'h3D5;   // green enemy bar
    localparam [11:0] C_EN_EMPTY = 12'h333;
    localparam [11:0] C_GUIDE    = 12'h555;   // scoring-tier marks
    localparam [11:0] C_BULLSEYE = 12'hFF0;
    localparam [11:0] C_CURSOR   = 12'hEEF;

    // ---- HP values as decimal digits ---------------------------------------
    wire [3:0] hp_tens = (player_hp >= 6'd40) ? 4'd4 :
                         (player_hp >= 6'd30) ? 4'd3 :
                         (player_hp >= 6'd20) ? 4'd2 :
                         (player_hp >= 6'd10) ? 4'd1 : 4'd0;
    wire [3:0] hp_ones = player_hp - {hp_tens, 3'd0} - {1'b0, hp_tens, 1'b0};
    wire [3:0] dm_tens = (last_damage >= 5'd10) ? 4'd1 : 4'd0;
    wire [3:0] dm_ones = last_damage - {dm_tens, 3'd0} - {1'b0, dm_tens, 1'b0};

    // ---- text bands --------------------------------------------------------
    wire in_dbg  = (y >= DBG_Y)  && (y < DBG_Y + 16) &&
                   (x >= DBG_X)  && (x < DBG_X + DBG_N * 8);
    wire in_name = (y >= NAME_Y) && (y < NAME_Y + 16) &&
                   (x >= NAME_X) && (x < NAME_X + NAME_N * 8);
    wire in_msg  = (y >= MSG_Y)  && (y < MSG_Y + 16) &&
                   (x >= MSG_X)  && (x < MSG_X + 16 * 8);
    wire in_hint = (y >= HINT_Y) && (y < HINT_Y + 16) &&
                   (x >= HINT_X) && (x < HINT_X + 16 * 8);
    wire in_lbl  = (y >= HUD_Y)  && (y < HUD_Y + 16) &&
                   (x >= HPLBL_X) && (x < HPLBL_X + 2 * 8);
    wire in_num  = (y >= HUD_Y)  && (y < HUD_Y + 16) &&
                   (x >= HPNUM_X) && (x < HPNUM_X + 7 * 8);

    wire [4:0] idx_dbg  = (x - DBG_X)  >> 3;
    wire [3:0] idx_name = (x - NAME_X) >> 3;
    wire [3:0] idx_msg  = (x - MSG_X)  >> 3;
    wire [3:0] idx_hint = (x - HINT_X) >> 3;
    wire [3:0] idx_lbl  = (x - HPLBL_X) >> 3;
    wire [3:0] idx_num  = (x - HPNUM_X) >> 3;

    // Serial read-out: "Bn Exx " then the last eight bytes as hex, oldest
    // first. Two characters per byte and none in between, so the character
    // index picks the byte with a shift instead of a divide.
    function [6:0] hex_char(input [3:0] v);
        hex_char = (v < 4'd10) ? ("0" + {3'd0, v}) : ("A" + {3'd0, v} - 7'd10);
    endfunction

    function [6:0] dbg_char(input [4:0] i, input [63:0] b, input [2:0] sel,
                            input [7:0] last, input [4:0] btn,
                            input [7:0] err);
        reg [7:0] byt;
        begin
            byt = 8'h00;
            case (i)
            5'd0:  dbg_char = "B";
            5'd1:  dbg_char = "0" + {4'd0, sel};
            5'd2:  dbg_char = " ";
            5'd3:  dbg_char = hex_char(err[7:4]);      // framing errors
            5'd4:  dbg_char = hex_char(err[3:0]);
            5'd5:  dbg_char = " ";
            5'd6:  dbg_char = hex_char(last[7:4]);     // last byte in
            5'd7:  dbg_char = hex_char(last[3:0]);
            5'd8:  dbg_char = " ";
            // what the game is actually being told, letter per direction
            5'd9:  dbg_char = btn[4] ? "U" : "-";
            5'd10: dbg_char = btn[3] ? "D" : "-";
            5'd11: dbg_char = btn[2] ? "L" : "-";
            5'd12: dbg_char = btn[1] ? "R" : "-";
            5'd13: dbg_char = btn[0] ? "K" : "-";
            5'd14: dbg_char = " ";
            default: begin                              // last 4 bytes, raw
                byt = b >> (8 * (3 - ((i - 5'd15) >> 1)));
                dbg_char = i[0] ? hex_char(byt[7:4]) : hex_char(byt[3:0]);
            end
            endcase
        end
    endfunction

    // " ROOT SENTINEL"
    function [6:0] name_char(input [3:0] i);
        case (i)
            4'd1: name_char = "R";   4'd2: name_char = "O";
            4'd3: name_char = "O";   4'd4: name_char = "T";
            4'd6: name_char = "S";   4'd7: name_char = "E";
            4'd8: name_char = "N";   4'd9: name_char = "T";
            4'd10: name_char = "I";  4'd11: name_char = "N";
            4'd12: name_char = "E";  4'd13: name_char = "L";
            default: name_char = " ";
        endcase
    endfunction

    // "  DAMAGE  nn "
    function [6:0] dmg_char(input [3:0] i, input [3:0] tens, input [3:0] ones);
        case (i)
            4'd2: dmg_char = "D";   4'd3: dmg_char = "A";
            4'd4: dmg_char = "M";   4'd5: dmg_char = "A";
            4'd6: dmg_char = "G";   4'd7: dmg_char = "E";
            4'd10: dmg_char = (tens == 4'd0) ? " " : ("0" + tens);
            4'd11: dmg_char = "0" + ones;
            default: dmg_char = " ";
        endcase
    endfunction

    // centre message: "PRESS ANY BUTTON" / "  YOU  SURVIVED " / "   GAME  OVER   "
    function [6:0] msg_char(input [3:0] i, input [2:0] st);
        case (st)
        S_WIN: case (i)
            4'd2: msg_char = "Y";   4'd3: msg_char = "O";
            4'd4: msg_char = "U";   4'd7: msg_char = "S";
            4'd8: msg_char = "U";   4'd9: msg_char = "R";
            4'd10: msg_char = "V";  4'd11: msg_char = "I";
            4'd12: msg_char = "V";  4'd13: msg_char = "E";
            4'd14: msg_char = "D";
            default: msg_char = " ";
        endcase
        S_LOSE: case (i)
            4'd3: msg_char = "G";   4'd4: msg_char = "A";
            4'd5: msg_char = "M";   4'd6: msg_char = "E";
            4'd9: msg_char = "O";   4'd10: msg_char = "V";
            4'd11: msg_char = "E";  4'd12: msg_char = "R";
            default: msg_char = " ";
        endcase
        default: case (i)   // S_TITLE
            4'd0: msg_char = "P";   4'd1: msg_char = "R";
            4'd2: msg_char = "E";   4'd3: msg_char = "S";
            4'd4: msg_char = "S";   4'd6: msg_char = "A";
            4'd7: msg_char = "N";   4'd8: msg_char = "Y";
            4'd10: msg_char = "B";  4'd11: msg_char = "U";
            4'd12: msg_char = "T";  4'd13: msg_char = "T";
            4'd14: msg_char = "O";  4'd15: msg_char = "N";
            default: msg_char = " ";
        endcase
        endcase
    endfunction

    // phase hint: "PRESS TO STRIKE!" / "     DODGE!     "
    function [6:0] hint_char(input [3:0] i, input [2:0] st);
        case (st)
        S_AIM: case (i)
            4'd0: hint_char = "P";   4'd1: hint_char = "R";
            4'd2: hint_char = "E";   4'd3: hint_char = "S";
            4'd4: hint_char = "S";   4'd6: hint_char = "T";
            4'd7: hint_char = "O";   4'd9: hint_char = "S";
            4'd10: hint_char = "T";  4'd11: hint_char = "R";
            4'd12: hint_char = "I";  4'd13: hint_char = "K";
            4'd14: hint_char = "E";  4'd15: hint_char = "!";
            default: hint_char = " ";
        endcase
        default: case (i)   // S_DODGE
            4'd5: hint_char = "D";   4'd6: hint_char = "O";
            4'd7: hint_char = "D";   4'd8: hint_char = "G";
            4'd9: hint_char = "E";   4'd10: hint_char = "!";
            default: hint_char = " ";
        endcase
        endcase
    endfunction

    // "nn / 20"
    function [6:0] num_char(input [3:0] i, input [3:0] tens, input [3:0] ones);
        case (i)
            4'd0: num_char = (tens == 4'd0) ? " " : ("0" + tens);
            4'd1: num_char = "0" + ones;
            4'd3: num_char = "/";
            4'd5: num_char = "4";
            4'd6: num_char = "0";
            default: num_char = " ";
        endcase
    endfunction

    // ---- stage 0: pick the character, and draw everything non-text ---------
    reg [6:0]  ch;
    reg        text_band;
    always @(*) begin
        ch        = " ";
        text_band = 1'b0;
        if (in_dbg) begin
            // shown in every state during bring-up: the band sits between the
            // enemy sprite and its name and is empty in all of them
            text_band = 1'b1;
            ch = dbg_char(idx_dbg, dbg_bytes, dbg_baud, dbg_last, dbg_btn,
                          dbg_err);
        end else if (in_name) begin
            text_band = (state != S_WIN);
            ch = (state == S_HIT) ? dmg_char(idx_name, dm_tens, dm_ones)
                                  : name_char(idx_name);
        end else if (in_msg) begin
            // the attract-screen prompt blinks, the end-of-battle ones don't
            text_band = (state == S_WIN) || (state == S_LOSE) ||
                        ((state == S_TITLE) && blink);
            ch = msg_char(idx_msg, state);
        end else if (in_hint) begin
            text_band = (state == S_AIM) || (state == S_DODGE);
            ch = hint_char(idx_hint, state);
        end else if (in_lbl) begin
            text_band = 1'b1;
            ch = (idx_lbl == 4'd0) ? "H" : "P";
        end else if (in_num) begin
            text_band = 1'b1;
            ch = num_char(idx_num, hp_tens, hp_ones);
        end
    end

    wire [7:0] font_word;

    font_rom u_font (
        .clk  (clk),
        .addr ({ch, y[3:0]}),
        .data (font_word)
    );

    // battle box frame
    wire in_box_outer = (x >= BOX_L) && (x < BOX_L + BOX_W) &&
                        (y >= BOX_T) && (y < BOX_T + BOX_H);
    wire in_box_inner = (x >= INNER_L) && (x <= INNER_R) &&
                        (y >= INNER_T) && (y <= INNER_B);

    // HP bars: 2.5 px of bar per player HP (100 px = 40), 2 px per enemy HP
    // (240 px = 120). The half pixel is a shift, and rounds invisibly.
    wire [9:0] hp_fill = {3'd0, player_hp, 1'b0} + {5'd0, player_hp[5:1]};
    wire [9:0] en_fill = {2'd0, enemy_hp,  1'b0};   // 2 px per HP, 240 px full
    wire in_hpbar = (x >= HPBAR_X) && (x < HPBAR_X + HPBAR_W) &&
                    (y >= HPBAR_Y) && (y < HPBAR_Y + HPBAR_H);
    wire in_enbar = (x >= EBAR_X) && (x < EBAR_X + EBAR_W) &&
                    (y >= EBAR_Y) && (y < EBAR_Y + EBAR_H);

    // attack cursor + the tier marks it is aimed at
    wire aim_phase   = (state == S_AIM) || (state == S_HIT);
    wire cursor_show = (state == S_AIM) || timer[2];   // frozen cursor blinks
    wire in_strip    = in_box_inner;
    wire in_cursor   = in_strip && (x >= cursor_x) && (x < cursor_x + 10'd4);
    wire in_bulls    = in_strip && (x >= CENTER_X - 1) && (x <= CENTER_X);
    wire in_guide    = in_strip && ((x == CENTER_X - 18) || (x == CENTER_X + 18) ||
                                    (x == CENTER_X - 40) || (x == CENTER_X + 40));

    reg [11:0] ov_color;
    reg        ov_hit;
    always @(*) begin
        ov_color = 12'h000;
        ov_hit   = 1'b0;
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
    end

    // ---- stage 1: font data is back; combine with the overlay --------------
    reg [11:0] ov_color_d1 = 12'h000;
    reg        ov_hit_d1   = 1'b0;
    reg        text_d1     = 1'b0;
    reg [2:0]  col_d1      = 3'd0;

    always @(posedge clk) begin
        ov_color_d1 <= ov_color;
        ov_hit_d1   <= ov_hit;
        text_d1     <= text_band;
        col_d1      <= x[2:0];
    end

    wire text_px = text_d1 && font_word[3'd7 - col_d1];

    // ---- stage 2: text wins over the overlay -------------------------------
    always @(posedge clk) begin
        color   <= text_px ? C_TEXT : ov_color_d1;
        visible <= text_px | ov_hit_d1;
    end

endmodule
