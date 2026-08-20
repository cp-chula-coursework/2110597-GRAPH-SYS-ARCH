//------------------------------------------------------------------------------
// game_logic.v
//
// Hardwired platformer game logic - the slides' "6. Game logic": one
// multi-step state machine in a single always @(posedge clk) block, run
// once per frame during vertical blanking (36,000 pixel clocks available;
// this FSM uses a few dozen). No CPU, no software.
//
// Per-frame sequence (mirrors the slides' numbered list):
//   1. wait for the new frame (start of vblank)
//   2. sample buttons -> walk/run velocity, jump impulse
//   3. apply gravity (lighter while rising with jump held = variable-height
//      jump)
//   4. move X, then collide the hitbox with the map horizontally
//   5. move Y, then collide vertically (land on / bonk off solid tiles);
//      falling off the bottom of the map respawns at the start
//   6. camera: scrollOffset follows the player, clamped to the map
//   7. pick sprite frame + facing for the renderer
//
// Map collision uses its own map_rom instance (the slides' "coll_rom"), so
// the background renderer's ROM port is never contended. A tile is solid
// iff bit 4 of its index is set (tiles 16..31; see gen_assets.py).
//
// Vertical position is kept in 1/8-pixel fixed point (py8) so gravity can
// be tuned finely at 60 fps; X moves in whole pixels.
//------------------------------------------------------------------------------
module game_logic (
    input  wire        clk,          // pixel clock
    input  wire        frame_start,  // 1-clk pulse at the start of vblank
    input  wire        pad_left,
    input  wire        pad_right,
    input  wire        pad_jump,
    input  wire        pad_run,
    output reg  [9:0]  scroll = 10'd0,        // x scroll offset, 0..640
    output wire [10:0] player_x,              // sprite top-left, world px
    output wire [9:0]  player_y,
    output reg  [1:0]  player_frame = 2'd0,   // 0 idle, 1-2 walk, 3 jump
    output reg         player_flip  = 1'b0    // 1 = facing left
);

    // ---- tuning ------------------------------------------------------------
    localparam [10:0] WORLD_MAX_X = 11'd1248;  // 1280 - 32 (sprite width)
    localparam [10:0] SPAWN_X     = 11'd48;
    localparam [12:0] SPAWN_Y8    = 13'd3072;  // y=384: standing on the ground
    localparam signed [8:0] JUMP_V  = -9'sd48; // 6.000 px/frame up
    localparam signed [8:0] G_RISE  =  9'sd2;  // 0.250 px/f^2 (jump held, rising)
    localparam signed [8:0] G_FALL  =  9'sd5;  // 0.625 px/f^2
    localparam signed [8:0] VY_MAX  =  9'sd40; // 5 px/frame terminal fall
    // hitbox inside the 32x32 sprite: x +8..+23 (16 wide), y +4..+31 (28 tall)
    localparam [4:0] HB_L = 5'd8,  HB_R = 5'd23;
    localparam [4:0] HB_T = 5'd4,  HB_B = 5'd31;

    // ---- player state ------------------------------------------------------
    reg [10:0]       px  = SPAWN_X;   // world x of sprite left edge
    reg [12:0]       py8 = SPAWN_Y8;  // world y of sprite top, 1/8 px units
    reg signed [8:0] vy8 = 9'sd0;     // vertical velocity, 1/8 px per frame
    reg              grounded  = 1'b0;
    reg              jump_prev = 1'b0;
    reg              mov_l = 1'b0, mov_r = 1'b0;
    reg [3:0]        anim_cnt = 4'd0;

    wire [9:0] py = py8[12:3];
    assign player_x = px;
    assign player_y = py;

    // ---- collision ROM (the slides' coll_rom: a second map_rom port) -------
    reg  [6:0] probe_col = 7'd0;
    reg  [4:0] probe_row = 5'd0;
    reg        probe_valid = 1'b0;   // 0 = probe off the map: treat as empty
    wire [7:0] coll_tile;
    wire       probe_solid = probe_valid && coll_tile[4];

    map_rom u_coll (
        .clk  (clk),
        .addr ((probe_row * 12'd80) + {5'd0, probe_col}),
        .tile (coll_tile)
    );

    // ---- per-frame FSM -----------------------------------------------------
    localparam [3:0] S_WAIT    = 4'd0,
                     S_INPUT   = 4'd1,
                     S_GRAV    = 4'd2,
                     S_XMOVE   = 4'd3,
                     S_XP_SET  = 4'd4,
                     S_XP_WAIT = 4'd5,
                     S_XP_CHK  = 4'd6,
                     S_YMOVE   = 4'd7,
                     S_YP_SET  = 4'd8,
                     S_YP_WAIT = 4'd9,
                     S_YP_CHK  = 4'd10,
                     S_CAMERA  = 4'd11,
                     S_ANIM    = 4'd12;

    reg [3:0] state = S_WAIT;
    reg [1:0] k = 2'd0;              // probe loop index

    wire [2:0]  speed  = pad_run ? 3'd3 : 3'd2;
    wire        moving = mov_l ^ mov_r;
    wire        rising = vy8 < 0;

    // scratch expressions
    wire signed [8:0]  vy8_g   = vy8 + ((rising && pad_jump) ? G_RISE : G_FALL);
    wire signed [14:0] py8_nxt = $signed({2'b00, py8}) + {{6{vy8[8]}}, vy8};
    wire [10:0] hb_lx = px + {6'd0, HB_L};
    wire [10:0] hb_rx = px + {6'd0, HB_R};
    // X side probes at three heights so any of the <=3 spanned tile rows is hit
    wire [10:0] xp_y  = {1'b0, py} + (k == 2'd0 ? 11'd4 :
                                      k == 2'd1 ? 11'd17 : 11'd30);
    // Y probes: support 1 px below the feet when falling, head when rising
    wire [10:0] yp_y  = {1'b0, py} + (rising ? {6'd0, HB_T} : 11'd32);
    wire [10:0] yp_x  = (k == 2'd0) ? hb_lx : hb_rx;

    always @(posedge clk) begin
        case (state)

        S_WAIT: if (frame_start) state <= S_INPUT;

        S_INPUT: begin
            mov_l <= pad_left  && !pad_right;
            mov_r <= pad_right && !pad_left;
            jump_prev <= pad_jump;
            if (pad_jump && !jump_prev && grounded) begin
                vy8      <= JUMP_V;
                grounded <= 1'b0;
            end
            state <= S_GRAV;
        end

        S_GRAV: begin
            vy8   <= (vy8_g > VY_MAX) ? VY_MAX : vy8_g;
            state <= S_XMOVE;
        end

        S_XMOVE: begin
            if (mov_r)
                px <= (px + {8'd0, speed} > WORLD_MAX_X) ? WORLD_MAX_X
                                                         : px + {8'd0, speed};
            else if (mov_l)
                px <= (px < {8'd0, speed}) ? 11'd0 : px - {8'd0, speed};
            k     <= 2'd0;
            state <= moving ? S_XP_SET : S_YMOVE;
        end

        S_XP_SET: begin
            probe_col   <= mov_r ? hb_rx[10:4] : hb_lx[10:4];
            probe_row   <= xp_y[8:4];
            probe_valid <= (xp_y < 11'd480);
            state       <= S_XP_WAIT;
        end

        S_XP_WAIT: state <= S_XP_CHK;   // coll_rom read latency

        S_XP_CHK: begin
            if (probe_solid) begin
                // push the hitbox flush against the wall
                px <= mov_r ? ({probe_col, 4'd0} - {6'd0, HB_R} - 11'd1)
                            : ({probe_col, 4'd0} + 11'd16 - {6'd0, HB_L});
                state <= S_YMOVE;
            end else if (k == 2'd2)
                state <= S_YMOVE;
            else begin
                k     <= k + 2'd1;
                state <= S_XP_SET;
            end
        end

        S_YMOVE: begin
            k <= 2'd0;
            if (py8_nxt < 0) begin                       // clamp at world top
                py8 <= 13'd0;
                vy8 <= 9'sd0;
                state <= S_YP_SET;
            end else if (py8_nxt[13:3] >= 11'd480) begin // fell off: respawn
                px  <= SPAWN_X;
                py8 <= SPAWN_Y8;
                vy8 <= 9'sd0;
                grounded <= 1'b0;
                state <= S_CAMERA;
            end else begin
                py8 <= py8_nxt[12:0];
                state <= S_YP_SET;
            end
        end

        S_YP_SET: begin
            probe_col   <= yp_x[10:4];
            probe_row   <= yp_y[8:4];
            probe_valid <= (yp_y < 11'd480);
            state       <= S_YP_WAIT;
        end

        S_YP_WAIT: state <= S_YP_CHK;   // coll_rom read latency

        S_YP_CHK: begin
            if (probe_solid) begin
                if (rising) begin
                    // bonked a tile above: snap head flush under it
                    py8 <= {({probe_row, 4'd0} + 9'd16 - {4'd0, HB_T}), 3'd0};
                    vy8 <= 9'sd0;
                end else begin
                    // landed: snap feet flush on top of it
                    py8 <= {({probe_row, 4'd0} - 9'd32), 3'd0};
                    vy8 <= 9'sd0;
                    grounded <= 1'b1;
                end
                state <= S_CAMERA;
            end else if (k == 2'd0) begin
                k     <= 2'd1;
                state <= S_YP_SET;
            end else begin
                if (!rising)
                    grounded <= 1'b0;   // nothing under the feet: airborne
                state <= S_CAMERA;
            end
        end

        S_CAMERA: begin
            // keep the player centered, clamped to the 2-screen map
            if (px < 11'd304)
                scroll <= 10'd0;
            else if (px > 11'd944)
                scroll <= 10'd640;
            else
                scroll <= px[9:0] - 10'd304;
            state <= S_ANIM;
        end

        S_ANIM: begin
            if (moving)
                player_flip <= mov_l;
            if (!grounded)
                player_frame <= 2'd3;                       // jump
            else if (moving) begin
                anim_cnt     <= anim_cnt + 4'd1;
                player_frame <= anim_cnt[3] ? 2'd2 : 2'd1;  // walk cycle
            end else
                player_frame <= 2'd0;                       // idle
            state <= S_WAIT;
        end

        default: state <= S_WAIT;
        endcase
    end

endmodule
