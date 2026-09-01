//------------------------------------------------------------------------------
// tb_blaster_draw.v
//
// Picture check for blaster_renderer on its own. Playing the game far enough
// to reach the blaster wave at real 640x480 timing takes thousands of frames;
// this bench instead drives the renderer directly with eight hand-placed
// blasters - one per heading - and dumps a single frame.
//
// The eight muzzles are solved the same way blaster_logic solves them, from
// one soul position at the centre of the box, so all eight beams should meet
// exactly on the soul marker, each skull should point down its own beam, and
// nothing should spill outside the box:
//
//   soulbattle_blaster.ppm    4 beams firing (wide), 4 warning lines (thin),
//                             all eight skull orientations, the box frame and
//                             a red marker where the soul is
//   soulbattle_blaster_red.ppm       the crimson wave's blaster, firing
//   soulbattle_blaster_red_warn.ppm  and the warning it gives first
//   soulbattle_blaster_growing.ppm
//                             the same eight, one frame into firing (reach =
//                             72 px, one REACH_STEP): every beam is still
//                             short of the soul, which is what `reach` is
//                             for - the beam travels out of the muzzle
//                             instead of appearing all at once
//
//   iverilog -o /tmp/tb_bd.vvp hdl/vga_timing.v hdl/blaster_rom.v \
//     hdl/blaster_renderer.v sim/tb_blaster_draw.v
//   vvp /tmp/tb_bd.vvp
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_blaster_draw;

    localparam NB = 8;

    localparam EDGE_L = 190, EDGE_T = 250, EDGE_R = 449, EDGE_B = 409;
    localparam BOX_L  = 190, BOX_T  = 250, BOX_W  = 260, BOX_H  = 160;

    localparam D_S = 0, D_SE = 1, D_E = 2, D_NE = 3,
               D_N = 4, D_NW = 5, D_W = 6, D_SW = 7;

    // the soul, parked in the middle of the box
    localparam SOUL_X = 312, SOUL_Y = 322;
    localparam CX = SOUL_X + 8, CY = SOUL_Y + 8;

    reg clk = 1'b0;
    always #19.861 clk = ~clk;

    wire [9:0] x, y;
    wire       hs, vs, blank;

    vga_timing u_vga (.clk(clk), .HS(hs), .VS(vs), .x(x), .y(y), .blank(blank));

    reg [NB*10-1:0] bl_mx, bl_my, bl_reach;
    reg [NB*3-1:0]  bl_dir, bl_kick;
    reg [NB*5-1:0]  bl_hw;
    reg [NB*2-1:0]  bl_dim;
    reg [NB-1:0]    bl_hot, bl_head;

    wire [11:0] bcolor;
    wire        bvis;

    reg red = 1'b0;

    blaster_renderer #(.NBLAST (NB)) u_draw (
        .clk (clk), .x (x), .y (y), .red (red),
        .bl_mx (bl_mx), .bl_my (bl_my), .bl_dir (bl_dir), .bl_hw (bl_hw),
        .bl_reach (bl_reach), .bl_kick (bl_kick), .bl_dim (bl_dim),
        .bl_hot (bl_hot), .bl_head (bl_head),
        .color (bcolor), .visible (bvis)
    );

    // ---- place one blaster, muzzle solved exactly as blaster_logic does ----
    integer rl, rr, rt, rb, t;
    integer mxi, myi;

    // the same, but with the beam width given rather than implied, for
    // drawing a sweep caught part way round
    task place_hw(input integer slot, input integer d, input integer hw,
                  input integer hot, input integer reach);
        begin
            place(slot, d, 1'b0, reach);
            bl_hw [5*slot +: 5] = hw[4:0];
            bl_hot[slot]        = hot[0];
            bl_kick[3*slot +: 3]= hot[0] ? 3'd4 : 3'd0;
        end
    endtask

    task place(input integer slot, input integer d, input integer firing,
               input integer reach);
        begin
            rl = CX - EDGE_L;  rr = EDGE_R - CX;
            rt = CY - EDGE_T;  rb = EDGE_B - CY;
            case (d)
            D_S:  begin mxi = CX;     myi = EDGE_T; end
            D_N:  begin mxi = CX;     myi = EDGE_B; end
            D_E:  begin mxi = EDGE_L; myi = CY;     end
            D_W:  begin mxi = EDGE_R; myi = CY;     end
            D_SE: begin t = (rl < rt) ? rl : rt; mxi = CX - t; myi = CY - t; end
            D_SW: begin t = (rr < rt) ? rr : rt; mxi = CX + t; myi = CY - t; end
            D_NE: begin t = (rl < rb) ? rl : rb; mxi = CX - t; myi = CY + t; end
            default: begin t = (rr < rb) ? rr : rb; mxi = CX + t; myi = CY + t; end
            endcase
            bl_mx [10*slot +: 10] = mxi[9:0];
            bl_my [10*slot +: 10] = myi[9:0];
            bl_dir[ 3*slot +:  3] = d[2:0];
            bl_kick[3*slot +:  3] = firing ? 3'd4 : 3'd0;
            bl_dim [2*slot +:  2] = 2'd0;
            bl_hw  [5*slot +:  5] = firing ? 5'd9 : 5'd1;
            bl_reach[10*slot +: 10] = reach[9:0];
            bl_hot [slot]         = firing[0];
            bl_head[slot]         = 1'b1;
        end
    endtask

    // ---- background: the battle box frame, and where the soul is -----------
    reg [9:0] x1 = 0, y1 = 0, x2 = 0, y2 = 0;
    reg [2:0] blank_d = 3'b111;
    always @(posedge clk) begin
        x1 <= x;  x2 <= x1;
        y1 <= y;  y2 <= y1;
        blank_d <= {blank_d[1:0], blank};
    end

    wire box_out = (x2 >= BOX_L) && (x2 < BOX_L + BOX_W) &&
                   (y2 >= BOX_T) && (y2 < BOX_T + BOX_H);
    wire box_in  = (x2 >= BOX_L + 4) && (x2 < BOX_L + BOX_W - 4) &&
                   (y2 >= BOX_T + 4) && (y2 < BOX_T + BOX_H - 4);
    wire frame_px = box_out && !box_in;
    wire soul_px  = (x2 >= SOUL_X + 3) && (x2 <= SOUL_X + 12) &&
                    (y2 >= SOUL_Y + 3) && (y2 <= SOUL_Y + 12);

    wire [11:0] pix = bvis     ? bcolor :
                      soul_px  ? 12'hF00 :
                      frame_px ? 12'h888 : 12'h000;

    wire [7:0] pr = {pix[11:8], pix[11:8]};
    wire [7:0] pg = {pix[ 7:4], pix[ 7:4]};
    wire [7:0] pb = {pix[ 3:0], pix[ 3:0]};
    wire       de = ~blank_d[2];

    integer f, n;

    task dump(input [8*40-1:0] fname);
        begin
            @(negedge vs);
            f = $fopen(fname, "wb");
            $fwrite(f, "P6\n640 480\n255\n");
            n = 0;
            while (n < 640 * 480) begin
                @(posedge clk);
                if (de) begin
                    $fwrite(f, "%c%c%c", pr, pg, pb);
                    n = n + 1;
                end
            end
            $fclose(f);
            $display("wrote %0s", fname);
        end
    endtask

    initial begin
        bl_mx = 0; bl_my = 0; bl_dir = 0; bl_hw = 0;
        bl_reach = 0; bl_kick = 0; bl_dim = 0; bl_hot = 0; bl_head = 0;

        // four beams firing wide, four still showing their warning line
        place(0, D_S,  1, 1023);
        place(1, D_SE, 0, 1023);
        place(2, D_E,  1, 1023);
        place(3, D_NE, 0, 1023);
        place(4, D_N,  1, 1023);
        place(5, D_NW, 0, 1023);
        place(6, D_W,  1, 1023);
        place(7, D_SW, 0, 1023);

        @(negedge vs);                     // skip the first frame
        dump("soulbattle_blaster.ppm");

        // one frame into firing: reach is one 72 px step, so no beam has got
        // to the soul yet even though all eight are aimed straight at it
        place(0, D_S,  1, 72);
        place(1, D_SE, 1, 72);
        place(2, D_E,  1, 72);
        place(3, D_NE, 1, 72);
        place(4, D_N,  1, 72);
        place(5, D_NW, 1, 72);
        place(6, D_W,  1, 72);
        place(7, D_SW, 1, 72);

        dump("soulbattle_blaster_growing.ppm");

        // ---- the ring wave, caught part way round --------------------------
        // Successive headings at successive stages: the oldest beams thinning
        // out as they fade, the newest still only a warning line.
        bl_head = 8'h00;  bl_hw = 40'd0;  bl_hot = 8'h00;
        place_hw(0, D_S,  2, 1, 1023);    // firing, nearly done
        place_hw(1, D_SE, 5, 1, 1023);
        place_hw(2, D_E,  9, 1, 1023);    // full width
        place_hw(3, D_NE, 9, 1,  400);    // still growing
        place_hw(4, D_N,  6, 1,  180);
        place_hw(5, D_NW, 1, 0, 1023);    // warning line only
        place_hw(6, D_W,  1, 0, 1023);
        bl_head[7] = 1'b0;                // the eighth has not appeared yet

        dump("soulbattle_blaster_ring.ppm");

        // ---- the crimson one: alone, and about to fire ---------------------
        bl_head = 8'h00;  bl_hw = 40'd0;  bl_hot = 8'h00;
        red = 1'b1;
        place_hw(0, D_SE, 9, 1, 1023);        // firing
        dump("soulbattle_blaster_red.ppm");

        bl_head = 8'h00;  bl_hw = 40'd0;  bl_hot = 8'h00;
        place_hw(0, D_SE, 1, 0, 1023);        // its warning line
        dump("soulbattle_blaster_red_warn.ppm");
        $finish;
    end

endmodule
