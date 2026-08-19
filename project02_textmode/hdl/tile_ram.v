//------------------------------------------------------------------------------
// tile_ram.v
//
// Simple dual-port character tile RAM, per the course slides
// (06_Text_Mode_Display.pdf): 80 cols x 30 rows = 2400 cells, one write port
// (port A) and one read port (port B) with 1 clock of read latency.
//
// Each 8-bit cell is {bright, ascii[6:0]}: bit 7 selects the bright
// foreground colour (used for the matrix-rain stream heads), bits 6:0 are
// the 7-bit ASCII code fed to the font ROM.
//------------------------------------------------------------------------------
module tile_ram (
    input  wire        clk,

    // port A: write
    input  wire        we,
    input  wire [11:0] waddr,
    input  wire [7:0]  din,

    // port B: read, dout valid 1 clock after raddr
    input  wire [11:0] raddr,
    output reg  [7:0]  dout
);

    localparam DEPTH = 2400;   // 80 cols x 30 rows

    (* ram_style = "block" *)
    reg [7:0] mem [0:DEPTH-1];

    // Power-up contents: all spaces. (The editor also runs a clear sweep at
    // power-up, so this mainly keeps simulation output clean.)
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 8'h20;
    end

    always @(posedge clk) begin
        if (we)
            mem[waddr] <= din;
        dout <= mem[raddr];
    end

endmodule
