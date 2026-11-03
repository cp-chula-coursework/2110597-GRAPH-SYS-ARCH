//------------------------------------------------------------------------------
// uart_rx.v
//
// Plain 8N1 serial receiver. The PS2-to-serial adapter has a microcontroller
// on it that talks the PlayStation protocol to the pad itself and hands the
// result over as bytes, so all this design has to do is catch them - one wire
// instead of four, and none of the bit-level timing that ps2_pad.v carries.
//
//   idle  ‾‾‾‾‾‾|__start__| d0 | d1 | ... | d7 |‾‾stop‾‾|‾‾‾‾‾
//
// The line idles high; a falling edge starts a frame. Each bit is sampled in
// its middle rather than at its edge, which is what makes the receiver
// tolerant of the usual few percent of baud error on both sides.
//
// `clks_per_bit` is an input rather than a parameter so the rate can be
// changed on the board while hunting for whatever the adapter is actually
// set to, without rebuilding: at the 25.175 MHz pixel clock,
//
//   9600 -> 2622    19200 -> 1311    38400 -> 656    57600 -> 437
//   115200 -> 219
//
// A frame whose stop bit is not high is dropped and counted in `errors`,
// which is the quickest way to tell a wrong baud rate from a dead wire: a
// wrong rate gives a stream of errors, a dead wire gives nothing at all. The
// count saturates rather than wrapping, and `err_clear` restarts it - without
// that it sticks at ff after the first wrong guess and stops meaning anything.
//------------------------------------------------------------------------------
module uart_rx (
    input  wire        clk,
    input  wire        rx,             // async serial in, idles high
    input  wire [12:0] clks_per_bit,
    input  wire        err_clear,      // 1-clk pulse: restart the error count

    output reg  [7:0]  data   = 8'h00, // last good byte
    output reg         valid  = 1'b0,  // 1-clk strobe when `data` is new
    output reg  [7:0]  errors = 8'h00  // frames that ended without a stop bit
);

    localparam [1:0] S_IDLE = 2'd0, S_START = 2'd1,
                     S_DATA = 2'd2, S_STOP  = 2'd3;

    // the line comes off a cable with no relation to this clock
    reg [1:0] rx_sync = 2'b11;
    always @(posedge clk) rx_sync <= {rx_sync[0], rx};
    wire rx_s = rx_sync[1];

    reg [1:0]  st  = S_IDLE;
    reg [12:0] cnt = 13'd0;
    reg [2:0]  bit_i = 3'd0;
    reg [7:0]  sh = 8'h00;

    wire [12:0] half = {1'b0, clks_per_bit[12:1]};

    always @(posedge clk) begin
        valid <= 1'b0;
        if (err_clear) errors <= 8'h00;

        case (st)

        // wait for the line to fall out of idle
        S_IDLE: begin
            cnt <= 13'd0;
            if (!rx_s) st <= S_START;
        end

        // half a bit in, check it really is a start bit and not a glitch
        S_START: if (cnt >= half) begin
            cnt <= 13'd0;
            if (rx_s)
                st <= S_IDLE;          // it was noise
            else begin
                bit_i <= 3'd0;
                st    <= S_DATA;
            end
        end else
            cnt <= cnt + 13'd1;

        // from here every sample lands in the middle of its bit
        S_DATA: if (cnt >= clks_per_bit - 13'd1) begin
            cnt <= 13'd0;
            sh  <= {rx_s, sh[7:1]};    // LSB first
            if (bit_i == 3'd7)
                st <= S_STOP;
            else
                bit_i <= bit_i + 3'd1;
        end else
            cnt <= cnt + 13'd1;

        S_STOP: if (cnt >= clks_per_bit - 13'd1) begin
            cnt <= 13'd0;
            st  <= S_IDLE;
            if (rx_s) begin
                data  <= sh;
                valid <= 1'b1;
            end else if (errors != 8'hFF)
                errors <= errors + 8'd1;
        end else
            cnt <= cnt + 13'd1;

        endcase
    end

endmodule
