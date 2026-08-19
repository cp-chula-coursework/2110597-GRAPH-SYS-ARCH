//------------------------------------------------------------------------------
// text_system.v
//
// The complete text-mode display core: video timing, button conditioning,
// the two tile RAMs (editor text + matrix-rain screensaver), their writers,
// the mode logic between them, and the text renderer. Everything here runs
// in the single 25.175 MHz pixel-clock domain and is plain simulable
// Verilog - top.v wraps this with the clocking IP and the HDMI/TMDS output
// stage, which is all the AX7010-specific hardware there is.
//
// Mode logic:
//   EDITOR (power-up): blinking block cursor, buttons edit the text RAM.
//   After IDLE_FRAMES frames with no button activity -> RAIN: the renderer
//   is switched to the rain RAM (reseeded + cleared on entry) and the
//   matrix_rain generator animates it. Any button press switches straight
//   back to EDITOR - the press is consumed by the wake-up, and the user's
//   text is exactly as they left it, since the rain never touched that RAM.
//------------------------------------------------------------------------------
module text_system #(
    parameter integer IDLE_FRAMES       = 1200,   // ~20 s at 60 Hz
    parameter integer DEBOUNCE_CYCLES   = 125000, // ~5 ms at 25.175 MHz
    parameter integer REPEAT_DELAY      = 30,     // frames before autorepeat
    parameter integer REPEAT_PERIOD     = 4,      // frames between repeats
    parameter integer CLEAR_HOLD_FRAMES = 60      // hold-to-clear time
)(
    input  wire       clk,     // 25.175 MHz pixel clock
    input  wire [3:0] key,     // push buttons, active-low

    output wire [7:0] vid_r,
    output wire [7:0] vid_g,
    output wire [7:0] vid_b,
    output wire       vid_hs,
    output wire       vid_vs,
    output wire       vid_de
);

    //--------------------------------------------------------------------------
    // video timing + frame tick (start of vertical sync, inside vblank)
    //--------------------------------------------------------------------------
    wire       hs, vs, blank;
    wire [9:0] x, y;

    vga_timing u_vga_timing (
        .clk   (clk),
        .HS    (hs),
        .VS    (vs),
        .x     (x),
        .y     (y),
        .blank (blank)
    );

    reg vs_q = 1'b1;
    always @(posedge clk)
        vs_q <= vs;
    wire frame_tick = vs_q & ~vs;   // VS is active-low: falling edge

    //--------------------------------------------------------------------------
    // buttons
    //--------------------------------------------------------------------------
    wire [3:0] pressed, ev;

    button_input #(
        .DEBOUNCE_CYCLES (DEBOUNCE_CYCLES),
        .REPEAT_DELAY    (REPEAT_DELAY),
        .REPEAT_PERIOD   (REPEAT_PERIOD)
    ) u_buttons (
        .clk        (clk),
        .frame_tick (frame_tick),
        .key        (key),
        .pressed    (pressed),
        .ev         (ev)
    );

    //--------------------------------------------------------------------------
    // mode logic: editor vs screensaver
    //--------------------------------------------------------------------------
    localparam MODE_EDITOR = 1'b0, MODE_RAIN = 1'b1;

    reg mode = MODE_EDITOR;
    reg rain_init = 1'b0;
    reg [$clog2(IDLE_FRAMES+1)-1:0] idle_cnt = 0;

    always @(posedge clk) begin
        rain_init <= 1'b0;
        if (mode == MODE_EDITOR) begin
            if (|pressed || |ev)
                idle_cnt <= 0;
            else if (frame_tick) begin
                if (idle_cnt == IDLE_FRAMES - 1) begin
                    mode      <= MODE_RAIN;
                    rain_init <= 1'b1;
                    idle_cnt  <= 0;
                end else
                    idle_cnt <= idle_cnt + 1;
            end
        end else begin
            // any press wakes the editor; the editor ignores this event
            // because it is not active yet, so the wake press types nothing
            if (|ev) begin
                mode     <= MODE_EDITOR;
                idle_cnt <= 0;
            end
        end
    end

    // ~2 Hz cursor blink
    reg [5:0] blink_cnt = 6'd0;
    always @(posedge clk)
        if (frame_tick)
            blink_cnt <= blink_cnt + 6'd1;

    //--------------------------------------------------------------------------
    // editor + its tile RAM
    //--------------------------------------------------------------------------
    wire        ed_we;
    wire [11:0] ed_waddr, ed_rb_addr;
    wire [7:0]  ed_wdata, ed_dout;
    wire [6:0]  cur_x;
    wire [4:0]  cur_y;
    wire        ed_busy;
    wire [11:0] rend_addr;

    text_editor #(
        .CLEAR_HOLD_FRAMES (CLEAR_HOLD_FRAMES)
    ) u_editor (
        .clk        (clk),
        .frame_tick (frame_tick),
        .active     (mode == MODE_EDITOR),
        .ev         (ev),
        .held       (pressed),
        .blank      (blank),
        .ram_dout   (ed_dout),
        .rb_addr    (ed_rb_addr),
        .we         (ed_we),
        .waddr      (ed_waddr),
        .wdata      (ed_wdata),
        .cur_x      (cur_x),
        .cur_y      (cur_y),
        .busy       (ed_busy)
    );

    // The renderer only needs the read port during active video, so the
    // editor gets it during blanking to read the cell under the cursor.
    tile_ram u_editor_ram (
        .clk   (clk),
        .we    (ed_we),
        .waddr (ed_waddr),
        .din   (ed_wdata),
        .raddr (blank ? ed_rb_addr : rend_addr),
        .dout  (ed_dout)
    );

    //--------------------------------------------------------------------------
    // matrix rain + its tile RAM
    //--------------------------------------------------------------------------
    wire        rain_we;
    wire [11:0] rain_waddr;
    wire [7:0]  rain_wdata, rain_dout;

    matrix_rain u_rain (
        .clk        (clk),
        .frame_tick (frame_tick),
        .enable     (mode == MODE_RAIN),
        .init       (rain_init),
        .we         (rain_we),
        .waddr      (rain_waddr),
        .wdata      (rain_wdata)
    );

    tile_ram u_rain_ram (
        .clk   (clk),
        .we    (rain_we),
        .waddr (rain_waddr),
        .din   (rain_wdata),
        .raddr (rend_addr),
        .dout  (rain_dout)
    );

    //--------------------------------------------------------------------------
    // renderer, fed from whichever RAM the current mode displays
    //--------------------------------------------------------------------------
    text_renderer u_renderer (
        .clk          (clk),
        .x            (x),
        .y            (y),
        .hs_in        (hs),
        .vs_in        (vs),
        .blank_in     (blank),
        .tile_addr    (rend_addr),
        .tile_data    (mode == MODE_RAIN ? rain_dout : ed_dout),
        .cursor_en    (mode == MODE_EDITOR && !ed_busy),
        .cursor_x     (cur_x),
        .cursor_y     (cur_y),
        .cursor_blink (blink_cnt[4]),
        .vid_r        (vid_r),
        .vid_g        (vid_g),
        .vid_b        (vid_b),
        .vid_hs       (vid_hs),
        .vid_vs       (vid_vs),
        .vid_de       (vid_de)
    );

endmodule
