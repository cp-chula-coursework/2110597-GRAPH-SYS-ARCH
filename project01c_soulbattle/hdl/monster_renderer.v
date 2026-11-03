//------------------------------------------------------------------------------
// monster_renderer.v
//
// The enemy, ROOT SENTINEL, drawn straight out of comparators - no sprite ROM,
// no art, nothing stored anywhere. The whole creature is six shapes tested
// against the beam position inside its 128x128 cell, with ax = |dx - 64| doing
// the mirroring so only one half of it is ever described:
//
//   head    a hexagon: hw(dy) is 20..52 rising, flat at 52, then 1.5 px per
//           row of chin taper - a slope is an add and a shift
//   rim     the same hexagon 4 px in, which leaves a lighter rim
//   horns   |ax - hc(dy)| <= hwd(dy): a bar whose centre walks outward 3/8 px
//           per row while its width shrinks, so it comes to a point
//   core    a diamond on the forehead, |ax| + |dy-44| <= 9
//   eyes    |ax-26| <= 14 cut by two diagonal half-planes, which is what makes
//           them slant inward and look angry
//   mouth   a slot with teeth: the teeth are just dx[2], a stripe every 4 px -
//           the oldest trick in fixed-function graphics
//
//        /\        /\         Everything above is one expression per part; the
//       /  \  /\  /  \        priority mux at the bottom decides which colour
//      +----\/--\/----+       wins where they overlap, which is how the eyes
//      | (o)  ##  (o) |       sit in front of the head without either shape
//      |  ##########  |       needing to know about the other.
//      +--\ |#|#|#| /-+
//          \_______/
//
// `flash` replaces every visible pixel with white for the hit flash, and
// `show` blanks the creature once it is defeated. Latency is 2 clocks,
// matching the other layers.
//------------------------------------------------------------------------------
module monster_renderer (
    input  wire        clk,
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire [9:0]  pos_x,     // top-left of the 128x128 cell
    input  wire [9:0]  pos_y,
    input  wire        flash,
    input  wire        show,
    output reg  [11:0] color,     // valid 2 clocks after x/y
    output reg         visible
);

    localparam [11:0] FLASH_COLOR = 12'hEEE;

    localparam [11:0] C_HEAD  = 12'h335;   // slate body
    localparam [11:0] C_EDGE  = 12'h89B;   // lighter rim
    localparam [11:0] C_HORN  = 12'h9AB;
    localparam [11:0] C_CORE  = 12'h7FF;   // the forehead core
    localparam [11:0] C_HOT   = 12'hFFF;
    localparam [11:0] C_EYE   = 12'h3DC;
    localparam [11:0] C_PUPIL = 12'hFF7;
    localparam [11:0] C_TOOTH = 12'hDEF;
    localparam [11:0] C_MOUTH = 12'h111;

    // ---- stage 0: window test ----------------------------------------------
    wire in_x = (x >= pos_x) && (x < pos_x + 10'd128);
    wire in_y = (y >= pos_y) && (y < pos_y + 10'd128);

    wire [6:0] dx = x[6:0] - pos_x[6:0];   // mod-128 safe while in_x holds
    wire [6:0] dy = y[6:0] - pos_y[6:0];

    wire [6:0] ax = (dx >= 7'd64) ? (dx - 7'd64) : (7'd64 - dx);

    // ---- the head hexagon ---------------------------------------------------
    reg  [7:0] hw;
    reg        hw_ok;
    always @(*) begin
        hw_ok = 1'b1;
        if (dy < 7'd30 || dy > 7'd108) begin
            hw    = 8'd0;
            hw_ok = 1'b0;
        end else if (dy < 7'd46) begin
            hw = 8'd20 + {dy - 7'd30, 1'b0};                 // 20 -> 50
        end else if (dy <= 7'd84) begin
            hw = 8'd52;
        end else begin                                        // 1.5 px of chin
            hw = 8'd52 - ({1'b0, dy - 7'd84} + {2'b0, (dy - 7'd84) >> 1});
        end
    end

    wire head = hw_ok && (ax <= hw[6:0]);
    wire rim  = head && (ax + 7'd4 > hw[6:0]);

    // ---- the horns ----------------------------------------------------------
    wire [6:0] t   = (dy <= 7'd46) ? (7'd46 - dy) : 7'd0;   // rows above the base
    wire [7:0] hc  = 8'd46 + ((({1'b0, t, 1'b0} + {2'b0, t}) >> 3));
    wire [6:0] hwd = 7'd10 - (t >> 2);
    wire [7:0] hax = (ax >= hc[6:0]) ? (ax - hc[6:0]) : (hc[6:0] - ax);

    wire horn = (dy <= 7'd46) && (t < 7'd40) && (hax <= {1'b0, hwd});

    // ---- the forehead core --------------------------------------------------
    wire [6:0] cy   = (dy >= 7'd44) ? (dy - 7'd44) : (7'd44 - dy);
    wire [7:0] cdist = {1'b0, ax} + {1'b0, cy};
    wire core     = (cdist <= 8'd9);
    wire core_hot = (cdist <= 8'd4);

    // ---- the eyes -----------------------------------------------------------
    // two slanted slots: a window in x and y, then two diagonal half-planes
    // that cut the inner-bottom and outer-top corners off
    wire [6:0] ex = (ax >= 7'd26) ? (ax - 7'd26) : (7'd26 - ax);

    wire eye = (dy >= 7'd56) && (dy <= 7'd74) && (ex <= 7'd14) &&
               ((dy - 7'd56) >= ((ax - 7'd12) >> 2)) &&
               ((7'd74 - dy) >= ((7'd40 - ax) >> 2));
    wire pupil = eye && (ex <= 7'd6) && (dy >= 7'd60) && (dy <= 7'd70);

    // ---- the mouth ----------------------------------------------------------
    wire mouth = (dy >= 7'd88) && (dy <= 7'd100) && (ax <= 7'd30);
    wire tooth = mouth && !dx[2] && ((dy <= 7'd92) || (dy >= 7'd96));

    // ---- priority mux over the parts ---------------------------------------
    reg [11:0] part_color;
    reg        part_on;
    always @(*) begin
        part_on    = 1'b1;
        if      (horn)     part_color = C_HORN;
        else if (core_hot) part_color = C_HOT;
        else if (core)     part_color = C_CORE;
        else if (pupil)    part_color = C_PUPIL;
        else if (eye)      part_color = C_EYE;
        else if (tooth)    part_color = C_TOOTH;
        else if (mouth)    part_color = C_MOUTH;
        else if (rim)      part_color = C_EDGE;
        else if (head)     part_color = C_HEAD;
        else begin
            part_color = 12'h000;
            part_on    = 1'b0;
        end
    end

    // ---- stage 1 -> 2 -------------------------------------------------------
    reg [11:0] col_d1 = 12'h000;
    reg        vis_d1 = 1'b0;
    reg        flash_d1 = 1'b0;
    always @(posedge clk) begin
        col_d1   <= part_color;
        vis_d1   <= in_x && in_y && show && part_on;
        flash_d1 <= flash;
        color    <= flash_d1 ? FLASH_COLOR : col_d1;
        visible  <= vis_d1;
    end

endmodule
