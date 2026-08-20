//------------------------------------------------------------------------------
// platformer_core.v
//
// Everything except the clocking IP and the HDMI/TMDS output stage: video
// timing, the scrolling tile background, the player sprite, the per-frame
// game-logic FSM, and the layer compositor. Runs entirely at the 25.175 MHz
// pixel clock.
//
//                       x,y ------------+------------------+
//   vga_timing ---> (+ scrollOffset) x_scroll               |
//                        |              |                   |
//                        v              v                   |
//                  bg_renderer    player_renderer           |
//                 (map_rom +       (player_rom,             |
//                  bg_tile_rom,     32x32, flip,            |
//                  2-clk latency)   2-clk latency)          |
//                        \              /                   |
//                         \            /              hs/vs/blank
//                       compositor (sprite over bg,   2-stage delay
//                        12'hFFF = transparent)          |
//                                \                      /
//                                 +---> vid_r/g/b, syncs
//
//   game_logic (own map_rom instance as coll_rom) updates the player and
//   scrollOffset once per frame during vertical blanking, so the render
//   pipeline never sees them change mid-frame.
//------------------------------------------------------------------------------
module platformer_core (
    input  wire       clk,          // 25.175 MHz pixel clock
    input  wire [3:0] key,          // active-low buttons:
                                    // key[0]=left key[1]=right key[2]=jump key[3]=run
    output wire [7:0] vid_r,
    output wire [7:0] vid_g,
    output wire [7:0] vid_b,
    output wire       vid_hs,
    output wire       vid_vs,
    output wire       vid_de
);

    // ---- video timing ------------------------------------------------------
    wire [9:0] x, y;
    wire       hs, vs, blank;

    vga_timing u_vga (
        .clk   (clk),
        .HS    (hs),
        .VS    (vs),
        .x     (x),
        .y     (y),
        .blank (blank)
    );

    // one pulse at the start of vertical blanking = the slides' "newframe"
    wire frame_start = (y == 10'd480) && (x == 10'd0);

    // ---- input -------------------------------------------------------------
    wire [3:0] pad;

    pad_input u_pad (
        .clk     (clk),
        .key     (key),
        .pressed (pad)
    );

    // ---- game state (updated during vblank only) ---------------------------
    wire [9:0]  scroll;
    wire [10:0] player_x;
    wire [9:0]  player_y;
    wire [1:0]  player_frame;
    wire        player_flip;

    game_logic u_game (
        .clk          (clk),
        .frame_start  (frame_start),
        .pad_left     (pad[0]),
        .pad_right    (pad[1]),
        .pad_jump     (pad[2]),
        .pad_run      (pad[3]),
        .scroll       (scroll),
        .player_x     (player_x),
        .player_y     (player_y),
        .player_frame (player_frame),
        .player_flip  (player_flip)
    );

    // ---- render pipeline (2-clock latency in both layers) ------------------
    wire [10:0] x_scroll = {1'b0, x} + {1'b0, scroll};

    wire [11:0] bg_color;
    bg_renderer u_bg (
        .clk      (clk),
        .x        (x),
        .y        (y),
        .x_scroll (x_scroll),
        .color    (bg_color)
    );

    wire [11:0] pl_color;
    wire        pl_visible;
    player_renderer u_player (
        .clk      (clk),
        .x_scroll (x_scroll),
        .y        (y),
        .pos_x    (player_x),
        .pos_y    (player_y),
        .frame    (player_frame),
        .flip     (player_flip),
        .color    (pl_color),
        .visible  (pl_visible)
    );

    // sync/blank ride a matching 2-stage pipeline (frame shifts 2 px - invisible)
    reg [1:0] hs_d = 2'b11, vs_d = 2'b11, blank_d = 2'b11;
    always @(posedge clk) begin
        hs_d    <= {hs_d[0], hs};
        vs_d    <= {vs_d[0], vs};
        blank_d <= {blank_d[0], blank};
    end

    // ---- compositor: sprite over background, white = transparent -----------
    wire [11:0] pix = (pl_visible && pl_color != 12'hFFF) ? pl_color : bg_color;

    // 12-bit 4:4:4 -> 8-bit channels by nibble duplication
    assign vid_r = blank_d[1] ? 8'h00 : {pix[11:8], pix[11:8]};
    assign vid_g = blank_d[1] ? 8'h00 : {pix[7:4],  pix[7:4]};
    assign vid_b = blank_d[1] ? 8'h00 : {pix[3:0],  pix[3:0]};

    assign vid_hs = hs_d[1];
    assign vid_vs = vs_d[1];
    assign vid_de = ~blank_d[1];

endmodule
