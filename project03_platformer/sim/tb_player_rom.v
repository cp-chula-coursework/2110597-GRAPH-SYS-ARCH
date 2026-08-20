//------------------------------------------------------------------------------
// tb_player_rom.v
//
// Dumps the 4 player sprite frames (32x32) as ASCII art to player_dump.txt
// for eyeballing: '.' = transparent (12'hFFF), '#' = opaque pixel.
//
//   iverilog -o /tmp/tb_prom.vvp hdl/player_rom.v sim/tb_player_rom.v
//   vvp /tmp/tb_prom.vvp
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_player_rom;

    reg         clk = 1'b0;
    reg  [11:0] addr = 12'd0;
    wire [11:0] color;

    player_rom dut (.clk(clk), .addr(addr), .color(color));

    always #10 clk = ~clk;

    integer f, fr, yy, xx;
    reg [8*32-1:0] line;

    initial begin
        f = $fopen("player_dump.txt", "w");
        for (fr = 0; fr < 4; fr = fr + 1) begin
            $fdisplay(f, "--- frame %0d ---", fr);
            for (yy = 0; yy < 32; yy = yy + 1) begin
                for (xx = 0; xx < 32; xx = xx + 1) begin
                    addr = {fr[1:0], yy[4:0], xx[4:0]};
                    @(posedge clk);
                    @(posedge clk);   // sync ROM: data valid 1 clk after addr
                    line[(31-xx)*8 +: 8] = (color == 12'hFFF) ? "." : "#";
                end
                $fdisplay(f, "%s", line);
            end
        end
        $fclose(f);
        $display("player_dump.txt written");
        $finish;
    end

endmodule
