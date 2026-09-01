//------------------------------------------------------------------------------
// battle_core.v
//
// Everything except the clocking IP and the HDMI/TMDS output stage: video
// timing, the four render layers, the per-frame game logic, and the layer
// compositor. Runs entirely at the 25.175 MHz pixel clock.
//
//                                x,y
//   vga_timing ---> +-------------+-------------+--------------+
//                   |             |             |              |
//                   v             v             v              v
//             soul_renderer  bullet_renderer  hud_renderer  monster_renderer
//              (soul_rom)     (comparator      (font_rom,    (monster_rom,
//               2 clks)         shapes,         2 clks)       2x scale,
//                   |           2 clks)            |           2 clks)
//                   +-------------+-------------+--+
//                                 |                        hs/vs/blank
//                    compositor (soul > bullets >           2-stage delay
//                     HUD > enemy > black)                        |
//                                 +--------> vid_r/g/b, syncs <---+
//
//   battle_logic runs its whole turn machine in the vertical blanking
//   interval (frame_start), so nothing the renderers read ever changes
//   mid-frame.
//
// Button map (all four are needed for four-way movement, so there is no
// spare reset key - the battle restarts from the attract screen instead):
//   key[0] = up   key[1] = down   key[2] = left   key[3] = right
//------------------------------------------------------------------------------
module battle_core (
    input  wire       clk,          // 25.175 MHz pixel clock
    input  wire [3:0] key,          // active-low push buttons
    output wire [7:0] vid_r,
    output wire [7:0] vid_g,
    output wire [7:0] vid_b,
    output wire       vid_hs,
    output wire       vid_vs,
    output wire       vid_de
);

    // ---- battle-box geometry, shared with every submodule ------------------
    localparam integer BOX_L   = 190;
    localparam integer BOX_T   = 250;
    localparam integer BOX_W   = 260;
    localparam integer BOX_H   = 160;
    localparam integer BORDER  = 4;
    localparam integer NBULLET = 8;

    localparam [2:0] S_WIN  = 3'd4,
                     S_LOSE = 3'd5;

    // enemy sprite: 64x64 ROM drawn at 2x, centred on the screen
    localparam [9:0] MON_X = 10'd253;   // + a 0..6 px shake
    localparam [9:0] MON_Y = 10'd40;

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
    wire [2:0] state;
    wire [9:0] timer;
    wire [7:0] anim;
    wire [9:0] soul_x, soul_y;
    wire [5:0] player_hp, enemy_hp;
    wire [6:0] iframes;
    wire [9:0] cursor_x;
    wire [4:0] last_damage;
    wire [7:0] hit_flash;
    wire [2:0] round_cnt;
    wire [NBULLET*10-1:0] bullet_x, bullet_y;
    wire [NBULLET*2-1:0]  bullet_type;
    wire [NBULLET-1:0]    bullet_active;

    battle_logic #(
        .BOX_L (BOX_L), .BOX_T (BOX_T), .BOX_W (BOX_W), .BOX_H (BOX_H),
        .BORDER (BORDER), .NBULLET (NBULLET)
    ) u_logic (
        .clk           (clk),
        .frame_start   (frame_start),
        .pad_up        (pad[0]),
        .pad_dn        (pad[1]),
        .pad_lf        (pad[2]),
        .pad_rt        (pad[3]),
        .state         (state),
        .timer         (timer),
        .anim          (anim),
        .soul_x        (soul_x),
        .soul_y        (soul_y),
        .player_hp     (player_hp),
        .enemy_hp      (enemy_hp),
        .iframes       (iframes),
        .cursor_x      (cursor_x),
        .last_damage   (last_damage),
        .hit_flash     (hit_flash),
        .round_cnt     (round_cnt),
        .bullet_x      (bullet_x),
        .bullet_y      (bullet_y),
        .bullet_type   (bullet_type),
        .bullet_active (bullet_active)
    );

    // ---- enemy presentation: idle bob, hit shake/flash, death fade ---------
    wire [9:0] bob = (anim[7:6] == 2'd0) ? 10'd0 :
                     (anim[7:6] == 2'd2) ? 10'd6 : 10'd3;
    wire [9:0] shake = (hit_flash != 8'd0) ? (hit_flash[1] ? 10'd6 : 10'd0)
                                           : 10'd3;
    wire mon_flash = (hit_flash != 8'd0) && hit_flash[2];
    wire mon_show  = (state != S_WIN) || (timer < 10'd90 && timer[2]);

    // ---- render layers (2-clock latency each) ------------------------------
    wire [11:0] soul_color;
    wire        soul_vis;

    soul_renderer u_soul (
        .clk     (clk),
        .x       (x),
        .y       (y),
        .pos_x   (soul_x),
        .pos_y   (soul_y),
        .frame   (state == S_LOSE),
        .show    (~(iframes != 7'd0 && iframes[2])),   // blink while merciful
        .color   (soul_color),
        .visible (soul_vis)
    );

    wire [11:0] bullet_color;
    wire        bullet_vis;

    bullet_renderer #(
        .BOX_L (BOX_L), .BOX_T (BOX_T), .BOX_W (BOX_W), .BOX_H (BOX_H),
        .BORDER (BORDER), .NBULLET (NBULLET)
    ) u_bullets (
        .clk           (clk),
        .x             (x),
        .y             (y),
        .bullet_x      (bullet_x),
        .bullet_y      (bullet_y),
        .bullet_type   (bullet_type),
        .bullet_active (bullet_active),
        .color         (bullet_color),
        .visible       (bullet_vis)
    );

    wire [11:0] hud_color;
    wire        hud_vis;

    hud_renderer #(
        .BOX_L (BOX_L), .BOX_T (BOX_T), .BOX_W (BOX_W), .BOX_H (BOX_H),
        .BORDER (BORDER)
    ) u_hud (
        .clk         (clk),
        .x           (x),
        .y           (y),
        .state       (state),
        .timer       (timer),
        .blink       (anim[5]),
        .player_hp   (player_hp),
        .enemy_hp    (enemy_hp),
        .cursor_x    (cursor_x),
        .last_damage (last_damage),
        .color       (hud_color),
        .visible     (hud_vis)
    );

    wire [11:0] mon_color;
    wire        mon_vis;

    monster_renderer u_monster (
        .clk     (clk),
        .x       (x),
        .y       (y),
        .pos_x   (MON_X + shake),
        .pos_y   (MON_Y + bob),
        .flash   (mon_flash),
        .show    (mon_show),
        .color   (mon_color),
        .visible (mon_vis)
    );

    // sync/blank ride a matching 2-stage pipeline (the frame shifts 2 px,
    // which is invisible)
    reg [1:0] hs_d = 2'b11, vs_d = 2'b11, blank_d = 2'b11;
    always @(posedge clk) begin
        hs_d    <= {hs_d[0], hs};
        vs_d    <= {vs_d[0], vs};
        blank_d <= {blank_d[0], blank};
    end

    // ---- compositor: soul over bullets over HUD over enemy over black ------
    wire [11:0] pix = soul_vis   ? soul_color   :
                      bullet_vis ? bullet_color :
                      hud_vis    ? hud_color    :
                      mon_vis    ? mon_color    : 12'h000;

    // 12-bit 4:4:4 -> 8-bit channels by nibble duplication
    assign vid_r = blank_d[1] ? 8'h00 : {pix[11:8], pix[11:8]};
    assign vid_g = blank_d[1] ? 8'h00 : {pix[7:4],  pix[7:4]};
    assign vid_b = blank_d[1] ? 8'h00 : {pix[3:0],  pix[3:0]};

    assign vid_hs = hs_d[1];
    assign vid_vs = vs_d[1];
    assign vid_de = ~blank_d[1];

endmodule
