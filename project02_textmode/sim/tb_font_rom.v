//------------------------------------------------------------------------------
// tb_font_rom.v
//
// Dumps every printable glyph in font_rom as ASCII art to font_dump.txt for
// visual inspection (a check that gen_font_rom.py produced sane data).
//
//   iverilog -o /tmp/tb_font_rom.vvp hdl/font_rom.v sim/tb_font_rom.v
//   vvp /tmp/tb_font_rom.vvp
//------------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_font_rom;

    reg         clk = 1'b0;
    reg  [10:0] addr = 11'd0;
    wire [7:0]  data;

    font_rom dut (.clk(clk), .addr(addr), .data(data));

    always #10 clk = ~clk;

    integer fd, code, row, b;

    initial begin
        fd = $fopen("font_dump.txt", "w");
        for (code = 32; code < 127; code = code + 1) begin
            $fwrite(fd, "0x%02x '%c'\n", code, code);
            for (row = 0; row < 16; row = row + 1) begin
                addr = {code[6:0], row[3:0]};
                @(posedge clk); #1;   // addr is registered, data valid after edge
                for (b = 7; b >= 0; b = b - 1)
                    $fwrite(fd, "%s", data[b] ? "#" : ".");
                $fwrite(fd, "\n");
            end
            $fwrite(fd, "\n");
        end
        $fclose(fd);
        $display("wrote font_dump.txt");
        $finish;
    end

endmodule
