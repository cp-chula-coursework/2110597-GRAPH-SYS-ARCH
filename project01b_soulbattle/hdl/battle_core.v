//------------------------------------------------------------------------------
// battle_core.v
//
// Everything except the clocking IP and the HDMI/TMDS output stage: video
// timing, the four render layers, the per-frame game logic, and the layer
// compositor. Runs entirely at the 25.175 MHz pixel clock.
//
//                                x,y
//   vga_timing --> +----------+----------+----------+----------+----------+
//                  |          |          |          |          |          |
//                  v          v          v          v          v          v
//              soul_    blaster_    bullet_      hud_      monster_
//            renderer   renderer   renderer   renderer   renderer
//            (soul_rom) (blaster_  (comparator (font_rom) (monster_rom,
//                        rom, 2x)   shapes)                2x scale)
//                  |          |          |          |          |
//                  +----------+----------+----------+----------+
//                                 |                        hs/vs/blank
//              compositor (soul > blasters > bullets >     2-stage delay
//               HUD > enemy > black)  - every layer 2 clks       |
//                                 +--------> vid_r/g/b, syncs <---+
//
//   battle_logic runs its whole turn machine in the vertical blanking
//   interval (frame_start), so nothing the renderers read ever changes
//   mid-frame. blaster_logic runs on the same tick, one wave in four, and
//   needs the soul's coordinates because its beams aim at them.
//
// Button map (all four are needed for four-way movement, so there is no
// spare reset key - the battle restarts from the attract screen instead):
//   key[0] = up   key[1] = down   key[2] = left   key[3] = right
//
// A PlayStation controller can be plugged into the expansion header as well.
// It is polled once per frame by ps2_pad and simply ORed in with the board's
// buttons, so either input plays the game and neither has to be there.
//------------------------------------------------------------------------------
module battle_core (
    input  wire       clk,          // 25.175 MHz pixel clock
    input  wire [3:0] key,          // active-low push buttons
    input  wire [4:0] ext_key,      // buttons on the expansion header, to GND
    input  wire       uart_rx_pin,   // PS2-to-serial adapter, its TXD to here
    input  wire       ps2_dat,      // PlayStation controller (optional)
    output wire       ps2_att,
    output wire       ps2_clk,
    output wire       ps2_cmd,
    output wire [3:0] led,        // active-low controller diagnostics
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
    localparam integer NBLAST  = 2;    // blasters on screen at once

    // spawn window of an enemy turn, shared by the bullet waves and the
    // blaster wave so both stop feeding the box at the same moment
    localparam [9:0]   DODGE_FRAMES = 10'd330;
    localparam [2:0]   WAVE_BLAST   = 3'd3;
    localparam [2:0]   WAVE_RING    = 3'd4;

    localparam [2:0] S_TITLE = 3'd0,
                     S_DODGE = 3'd3,
                     S_WIN   = 3'd4,
                     S_LOSE  = 3'd5;

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

    pad_input #(.N(4)) u_pad (
        .clk     (clk),
        .key     (key),
        .pressed (pad)
    );

    // Plain push buttons wired to the expansion header, each one shorting its
    // pin to ground. Nothing else is needed: the pins hold themselves high, so
    // there is no supply to get wrong and nothing that can be driven into an
    // input that would not survive it.
    //   ext[0] up   ext[1] down   ext[2] left   ext[3] right   ext[4] confirm
    wire [4:0] ext;

    pad_input #(.N(5)) u_ext (
        .clk     (clk),
        .key     (ext_key),
        .pressed (ext)
    );

    // one transaction per frame, in the same vertical blanking the game
    // logic runs in - the result is ready long before the next frame needs it
    wire ps2_up, ps2_dn, ps2_lf, ps2_rt, ps2_ok;

    // Up and down together is not a move the game can use, so the chord is
    // free to toggle the wiring check in ps2_pad.v. It latches rather than
    // being held, so a multimeter can be used with both hands free; led[2]
    // stays lit while it is on.
    ps2_pad u_ps2 (
        .clk       (clk),
        .poll      (frame_start),
        .find      (1'b0),   // bring-up mode, unused in the finished game
        .ps2_att   (ps2_att),
        .ps2_clk   (ps2_clk),
        .ps2_cmd   (ps2_cmd),
        .ps2_dat   (ps2_dat),
        .pad_up    (ps2_up),
        .pad_down  (ps2_dn),
        .pad_left  (ps2_lf),
        .pad_right (ps2_rt),
        .pad_ok    (ps2_ok),
        .present   (),      // the game plays the same either way
        .alive     (),
        .dat_hi    ()
    );

    // Controller diagnostics on the four board LEDs, which the game does not
    // otherwise use. Read them bottom-up as a ladder while bringing the
    // wiring up - each one only makes sense once the one before it is lit:
    //
    //   led[3]  heartbeat, ~1 Hz   this bitstream is the one running
    //   led[2]  the pad answered   ID and the 5a came back: the bus works
    //   led[1]  DATA has gone low  the controller is talking to us
    //   led[0]  DATA is high now   the wire, its pull-up and 3.3V are all fine
    //
    // So: no heartbeat means the board is running an older bitstream. A dark
    // led[0] is a wiring, power or pull-up fault and nothing else. led[0] lit
    // but led[1] dark means the controller has power but never replies. led[1]
    // lit but led[2] dark means the bus runs but the bytes are wrong, which is
    // usually COMMAND and DATA swapped.
    //
    // The LEDs are active low: VCCIO_35 -> 330R -> LED -> FPGA pin.
    // The four board LEDs mirror the player's HP a quarter at a time during a
    // battle, so the board shows how it is going without looking at the
    // screen. On the attract screen, where HP is always full and the number
    // would say nothing, they echo the four external direction buttons
    // instead - which is all the bring-up an external pad needs: press one,
    // watch its lamp.
    assign led = (state == S_TITLE) ? ~ext[3:0]
                                    : ~{player_hp > 6'd30,
                                        player_hp > 6'd20,
                                        player_hp > 6'd10,
                                        player_hp > 6'd0};

    // either input device drives the game; the d-pad and the buttons are the
    // same four signals as far as everything downstream is concerned
    wire in_up = pad[0] | ps2_up | ext[0] | ser_up;
    wire in_dn = pad[1] | ps2_dn | ext[1] | ser_dn;
    wire in_lf = pad[2] | ps2_lf | ext[2] | ser_lf;
    wire in_rt = pad[3] | ps2_rt | ext[3] | ser_rt;
    wire in_ok = ps2_ok | ext[4] | ser_ok;

    // ---- the PS2-to-serial adapter -----------------------------------------
    // The adapter has its own microcontroller: it talks the PlayStation
    // protocol to the pad and sends the result here as an 8-byte packet,
    // 0x73 .. 0x5A. What is not known from the outside is the rate it was
    // left set to, or exactly how it packs the buttons - so nothing is
    // decoded yet. The last eight bytes and the count of frames that arrived
    // without a stop bit are simply put on screen, and the rate can be
    // stepped through on the board until they make sense - which is how the
    // one this adapter is set to, 9600, was found in the first place.
    function [12:0] baud_div(input [2:0] sel);
        case (sel)
        3'd0: baud_div = 13'd2622;    //   9600
        3'd1: baud_div = 13'd1311;    //  19200
        3'd2: baud_div = 13'd656;     //  38400
        3'd3: baud_div = 13'd437;     //  57600
        default: baud_div = 13'd219;  // 115200
        endcase
    endfunction

    // left and right together, held, steps the rate - not a move the game can
    // use, and it has to be held so a scramble mid-dodge cannot trip it
    localparam [5:0] CHORD_HOLD = 6'd45;      // 0.75 s
    reg [2:0] baud_sel  = 3'd0;               // 9600 - what the adapter uses
    reg [5:0] baud_hold = 6'd0;
    wire chord_baud = pad[2] & pad[3];

    always @(posedge clk) if (frame_start) begin
        if (!chord_baud)              baud_hold <= 6'd0;
        else if (baud_hold != 6'd63)  baud_hold <= baud_hold + 6'd1;
        if (chord_baud && baud_hold == CHORD_HOLD)
            baud_sel <= (baud_sel == 3'd4) ? 3'd0 : baud_sel + 3'd1;
    end

    // stepping the rate restarts the error count, so what is on screen is
    // always about the rate being tried now and not a previous guess
    reg [2:0] baud_sel_d = 3'd0;
    reg       baud_changed = 1'b0;
    always @(posedge clk) begin
        baud_sel_d   <= baud_sel;
        baud_changed <= (baud_sel != baud_sel_d);
    end

    wire [7:0] uart_byte;
    wire       uart_valid;
    wire [7:0] uart_errors;

    uart_rx u_uart (
        .clk          (clk),
        .rx           (uart_rx_pin),
        .clks_per_bit (baud_div(baud_sel)),
        .err_clear    (baud_changed),
        .data         (uart_byte),
        .valid        (uart_valid),
        .errors       (uart_errors)
    );

    // The last eight bytes, oldest in the top byte. When those eight happen to
    // start with 0x73 and end with 0x5A the window is sitting exactly on one
    // of the adapter's packets, so it gets latched and shown instead - which
    // means the read-out stops sliding and starts showing the packet lined up,
    // and the marker on screen says the rate is right. If packets stop
    // arriving for half a second the marker goes out again.
    reg [63:0] uart_log = 64'd0;
    reg [63:0] uart_pkt = 64'd0;
    reg        pkt_ok   = 1'b0;
    reg [5:0]  pkt_age  = 6'd63;
    reg [63:0] uart_nxt;

    always @(posedge clk) begin
        if (uart_valid) begin
            uart_nxt = {uart_log[55:0], uart_byte};
            uart_log <= uart_nxt;
            if (uart_nxt[63:56] == 8'h73 && uart_nxt[7:0] == 8'h5A) begin
                uart_pkt <= uart_nxt;
                pkt_ok   <= 1'b1;
                pkt_age  <= 6'd0;
            end
        end
        if (frame_start) begin
            if (pkt_age == 6'd30) pkt_ok <= 1'b0;      // half a second
            if (pkt_age != 6'd63) pkt_age <= pkt_age + 6'd1;
        end
    end

    // ---- bytes to buttons ---------------------------------------------------
    wire ser_up, ser_dn, ser_lf, ser_rt, ser_ok;
    wire [7:0] ser_last;

    serial_pad u_serpad (
        .clk         (clk),
        .frame_start (frame_start),
        .data        (uart_byte),
        .valid       (uart_valid),
        .up          (ser_up),
        .down        (ser_dn),
        .left        (ser_lf),
        .right       (ser_rt),
        .ok          (ser_ok),
        .last        (ser_last)
    );

    // ---- game state (updated during vblank only) ---------------------------
    wire [2:0] state;
    wire [9:0] timer;
    wire [7:0] anim;
    wire [9:0] soul_x, soul_y;
    wire [5:0] player_hp;
    wire [6:0] enemy_hp;
    wire [6:0] iframes;
    wire [9:0] cursor_x;
    wire [4:0] last_damage;
    wire [7:0] hit_flash;
    wire [2:0] round_cnt;
    wire [2:0] wave;
    wire [NBULLET*10-1:0] bullet_x, bullet_y;
    wire [NBULLET*2-1:0]  bullet_type;
    wire [NBULLET-1:0]    bullet_active;

    battle_logic #(
        .BOX_L (BOX_L), .BOX_T (BOX_T), .BOX_W (BOX_W), .BOX_H (BOX_H),
        .BORDER (BORDER), .NBULLET (NBULLET), .DODGE_FRAMES (DODGE_FRAMES)
    ) u_logic (
        .clk           (clk),
        .frame_start   (frame_start),
        .pad_up        (in_up),
        .pad_dn        (in_dn),
        .pad_lf        (in_lf),
        .pad_rt        (in_rt),
        .pad_ok        (in_ok),
        .blast_hit     (blast_hit),
        .blast_busy    (blast_busy),
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
        .wave          (wave),
        .bullet_x      (bullet_x),
        .bullet_y      (bullet_y),
        .bullet_type   (bullet_type),
        .bullet_active (bullet_active)
    );

    // ---- the blaster wave --------------------------------------------------
    // One wave in four is handed over to blaster_logic, which aims at the
    // soul and reports back only "a beam is on you" and "still busy" - the
    // turn itself still ends in battle_logic.
    wire blast_hit, blast_busy;
    wire [NBLAST*10-1:0] bl_mx, bl_my, bl_reach;
    wire [NBLAST*3-1:0]  bl_dir, bl_kick;
    wire [NBLAST*5-1:0]  bl_hw;
    wire [NBLAST*2-1:0]  bl_dim;
    wire [NBLAST-1:0]    bl_hot, bl_head;

    wire blast_ring  = (wave == WAVE_RING);
    wire blast_run   = (state == S_DODGE) &&
                       ((wave == WAVE_BLAST) || blast_ring);
    wire blast_spawn = blast_run && (timer < DODGE_FRAMES);

    blaster_logic #(
        .BOX_L (BOX_L), .BOX_T (BOX_T), .BOX_W (BOX_W), .BOX_H (BOX_H),
        .NBLAST (NBLAST)
    ) u_blast (
        .clk         (clk),
        .frame_start (frame_start),
        .run         (blast_run),
        .spawn_en    (blast_spawn),
        .ring        (blast_ring),
        .soul_x      (soul_x),
        .soul_y      (soul_y),
        .round_cnt   (round_cnt),
        .bl_mx       (bl_mx),
        .bl_my       (bl_my),
        .bl_dir      (bl_dir),
        .bl_hw       (bl_hw),
        .bl_reach    (bl_reach),
        .bl_kick     (bl_kick),
        .bl_dim      (bl_dim),
        .bl_hot      (bl_hot),
        .bl_head     (bl_head),
        .blast_hit   (blast_hit),
        .blast_busy  (blast_busy)
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

    wire [11:0] blast_color;
    wire        blast_vis;

    blaster_renderer #(
        .BOX_L (BOX_L), .BOX_T (BOX_T), .BOX_W (BOX_W), .BOX_H (BOX_H),
        .BORDER (BORDER), .NBLAST (NBLAST)
    ) u_blast_draw (
        .clk      (clk),
        .x        (x),
        .y        (y),
        .bl_mx    (bl_mx),
        .bl_my    (bl_my),
        .bl_dir   (bl_dir),
        .bl_hw    (bl_hw),
        .bl_reach (bl_reach),
        .bl_kick  (bl_kick),
        .bl_dim   (bl_dim),
        .bl_hot   (bl_hot),
        .bl_head  (bl_head),
        .color    (blast_color),
        .visible  (blast_vis)
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
        .dbg_bytes   (uart_log),
        .dbg_baud    (baud_sel),
        .dbg_last    (ser_last),
        .dbg_btn     ({ser_up, ser_dn, ser_lf, ser_rt, ser_ok}),
        .dbg_err     (uart_errors),
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

    // ---- compositor: soul over blasters over bullets over HUD over enemy ---
    // The blasters sit above the HUD on purpose: a skull that comes in over
    // the top edge of the box passes in front of the enemy's name and HP bar
    // for the second or so it is on screen, which is what the attack is
    // supposed to look like.
    wire [11:0] pix = soul_vis   ? soul_color   :
                      blast_vis  ? blast_color  :
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
