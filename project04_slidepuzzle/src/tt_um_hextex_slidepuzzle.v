//------------------------------------------------------------------------------
// tt_um_hextex_slidepuzzle.v
//
// VGA Playground / Tiny Tapeout top for the image slide puzzle. It holds the
// same puzzle_core as the AX7010 build and changes only the two ends:
//
//   in   the playground's inputs. Gamepad mode (recommended) uses the arrow
//        keys plus t = start and s = peek. The ui_in switches work too:
//          ui_in[0] up      ui_in[1] down     ui_in[2] left
//          ui_in[3] right   ui_in[7] start / reshuffle
//        ui_in[6:4] are left alone because gamepad mode drives them.
//
//   out  Tiny VGA pinout, 2 bits per colour. The core's 24-bit colour is cut
//        to 2 bits with a 4x4 ordered (Bayer) dither, so the 64-colour output
//        still shows the picture's gradients rather than flat bands.
//
// The playground's ui_in buttons are toggles: a click flips the bit and it
// stays there. So every change of a switch, either way, counts as one press.
// Gamepad buttons are real buttons, so only the moment one goes down counts.
//------------------------------------------------------------------------------
`default_nettype none

module tt_um_hextex_slidepuzzle (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,      // 25.175 MHz
    input  wire       rst_n
);

    wire rst = ~rst_n;

    // ---- timing
    wire       t_hs, t_vs, t_blank;
    wire [9:0] t_x, t_y;

    vga_timing u_timing (
        .clk   (clk),
        .HS    (t_hs),
        .VS    (t_vs),
        .x     (t_x),
        .y     (t_y),
        .blank (t_blank)
    );

    // ---- gamepad
    wire [11:0] gp;          // { b, y, select, start, up, down, left, right, a, x, l, r }
    wire        gp_present;

    gamepad_pmod_rx u_gamepad (
        .clk        (clk),
        .rst        (rst),
        .pmod_data  (ui_in[6]),
        .pmod_clk   (ui_in[5]),
        .pmod_latch (ui_in[4]),
        .btn        (gp),
        .present    (gp_present)
    );

    reg  [11:0] gp_prev;
    wire [11:0] gp_down = gp & ~gp_prev;    // went down this clock

    // ---- ui_in switches: {start, right, left, down, up}
    wire [4:0] sw = {ui_in[7], ui_in[3:0]};
    reg  [4:0] sw_s1, sw_s2, sw_prev;
    wire [4:0] sw_flip = rst ? 5'd0 : (sw_s2 ^ sw_prev);

    always @(posedge clk) begin
        sw_s1   <= sw;
        sw_s2   <= sw_s1;
        // follows the synchronised switch through reset too, so a switch
        // already on when reset lets go is not taken as a press
        sw_prev <= sw_s2;
        gp_prev <= gp;          // reads all-released during reset
    end

    wire press_up    = gp_down[7] | sw_flip[0];
    wire press_down  = gp_down[6] | sw_flip[1];
    wire press_left  = gp_down[5] | sw_flip[2];
    wire press_right = gp_down[4] | sw_flip[3];
    wire press_start = gp_down[8] | gp_down[3] | sw_flip[4];   // start or a
    wire peek        = gp[9] | gp[11];                         // select or b

    // ---- the game
    wire [7:0] vr, vg, vb;
    wire       v_hs, v_vs, v_de;
    wire [2:0] game_state;

    puzzle_core u_core (
        .clk         (clk),
        .rst         (rst),
        .x           (t_x),
        .y           (t_y),
        .hs_in       (t_hs),
        .vs_in       (t_vs),
        .blank_in    (t_blank),
        .press_up    (press_up),
        .press_down  (press_down),
        .press_left  (press_left),
        .press_right (press_right),
        .press_start (press_start),
        .peek        (peek),
        .r           (vr),
        .g           (vg),
        .b           (vb),
        .hs          (v_hs),
        .vs          (v_vs),
        .de          (v_de),
        .game_state  (game_state)
    );

    // ---- 8 bits -> 2 bits per channel, ordered dither
    // Threshold from the 4x4 Bayer matrix, built from bits instead of a table:
    // rank = { x0^y0, y0, x1^y1, y1 }, spread over 0..255.
    wire [3:0] bayer = {t_x[0] ^ t_y[0], t_y[0], t_x[1] ^ t_y[1], t_y[1]};
    wire [7:0] thresh = {bayer, 4'b1000};

    // level = (3*c + threshold) / 256, which is 0..3
    function [1:0] dither2;
        input [7:0] c;
        input [7:0] t;
        reg   [9:0] v;
        begin
            v = {1'b0, c, 1'b0} + {2'b00, c} + {2'b00, t};
            dither2 = v[9:8];
        end
    endfunction

    wire [1:0] R = v_de ? dither2(vr, thresh) : 2'b00;
    wire [1:0] G = v_de ? dither2(vg, thresh) : 2'b00;
    wire [1:0] B = v_de ? dither2(vb, thresh) : 2'b00;

    // Tiny VGA Pmod pinout
    assign uo_out  = {v_hs, B[0], G[0], R[0], v_vs, B[1], G[1], R[1]};
    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;

    wire _unused = &{ena, uio_in, gp_present, gp[2:0], gp[10], game_state, 1'b0};

endmodule

`default_nettype wire
