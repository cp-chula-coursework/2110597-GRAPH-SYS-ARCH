//------------------------------------------------------------------------------
// ps2_pad.v
//
// PlayStation (PSX/PS2) controller host, in plain Verilog. The controller is
// an SPI slave with an unusual habit: it talks back on the same clock it is
// being talked to on, so one transaction both sends a command and reads the
// buttons.
//
//   ATT  ___                                             ____   (active low)
//           \___________________________________________/
//   CLK  ‾‾‾‾‾|_|‾|_|‾|_| ... 8 clocks per byte ... |_|‾‾‾‾‾    (idle high)
//   CMD  ----< b0 X b1 X b2 ... >---- host -> pad, LSB first
//   DAT  ----< b0 X b1 X b2 ... >---- pad -> host, LSB first, open drain
//
// Both sides put their bit out on the falling edge and latch the other's on
// the rising edge, so this is SPI mode 3, LSB first, at ~200 kHz with a gap
// of about 16 us between bytes for the controller to keep up.
//
// One transaction, run once per video frame:
//
//   host  01  42  00  00  00  00  00  00  00
//   pad   ff  ID  5a  b0  b1  RX  RY  LX  LY
//
//   ID = 41 digital (2 data bytes), 73 analog (6). The low nibble is the
//        number of 16-bit words that follow, which is how the length of the
//        rest of the transaction is decided rather than hardwired.
//   5a = "data follows"; anything else means nothing sane is plugged in.
//   b0 = SLCT L3 R3 STRT UP RIGHT DOWN LEFT   (0 = pressed)
//   b1 = L2 R2 L1 R1 /\ () XX []              (0 = pressed)
//   LX/LY = left stick, 00..ff, centred at 80
//
// With nothing plugged in, DAT idles high through its pull-up, the 5a never
// arrives, `present` stays low and every output stays at 0 - so the board's
// own push buttons keep working exactly as before.
//
// The ACK line the controller pulses after each byte is not used: the byte
// gap here is longer than the controller's worst-case response, which is
// what ACK would otherwise be waited on for. It can be left unconnected.
//------------------------------------------------------------------------------
module ps2_pad #(
    parameter integer CLK_HZ = 25_175_000,   // pixel clock
    parameter integer SCK_HZ = 125_000,      // PSX bus clock (spec: 100k..500k)
    parameter integer GAP_NS = 40_000        // quiet time between bytes
)(
    input  wire clk,
    input  wire poll,            // 1-clk pulse: run one transaction
    input  wire find,            // wiring check: park the pins at known levels

    output reg  ps2_att = 1'b1,  // to the pad (active low)
    output reg  ps2_clk = 1'b1,
    output reg  ps2_cmd = 1'b1,
    input  wire ps2_dat,         // from the pad (open drain, needs a pull-up)

    output reg  pad_up    = 1'b0,
    output reg  pad_down  = 1'b0,
    output reg  pad_left  = 1'b0,
    output reg  pad_right = 1'b0,
    output reg  pad_ok    = 1'b0,   // any face button or START
    output reg  present   = 1'b0,   // a controller answered this poll
    output reg  alive     = 1'b0,   // DATA was pulled low at least once - i.e.
                                    // something is wired up and powered
    output wire dat_hi              // DATA as it sits right now: high means the
);                                  // wire and its pull-up are doing their job

    localparam integer HALF = CLK_HZ / (2 * SCK_HZ);          // half a bit
    localparam integer GAP  = (CLK_HZ / 1000) * GAP_NS / 1000_000 + 1;

    localparam [2:0] S_IDLE = 3'd0,
                     S_LEAD = 3'd1,   // ATT low, before the first clock
                     S_HI   = 3'd2,   // clock high half of a bit
                     S_LO   = 3'd3,   // clock low half of a bit
                     S_GAP  = 3'd4,   // between bytes
                     S_END  = 3'd5;

    reg [2:0]  st  = S_IDLE;
    reg [11:0] cnt = 12'd0;
    reg [2:0]  bit_i  = 3'd0;
    reg [3:0]  byte_i = 4'd0;
    reg [7:0]  txb = 8'h00;
    reg [7:0]  rxb = 8'h00;

    reg [7:0] id    = 8'hFF;
    reg [7:0] hdr   = 8'h00;    // the byte that should be 5a
    reg [7:0] b0    = 8'hFF;
    reg [7:0] b1    = 8'hFF;
    reg [7:0] lx    = 8'h80;
    reg [7:0] ly    = 8'h80;
    reg [3:0] ndata = 4'd2;     // data bytes this controller sends
    reg       dat_any = 1'b0;   // saw DATA low at any point this transaction

    // 01 opens the transaction, 42 asks for the buttons, the rest are filler
    function [7:0] tx_of(input [3:0] n);
        tx_of = (n == 4'd0) ? 8'h01 : (n == 4'd1) ? 8'h42 : 8'h00;
    endfunction

    // stick deadzone: a quarter of full travel either side of centre
    localparam [7:0] STICK_LO = 8'h50;
    localparam [7:0] STICK_HI = 8'hB0;

    wire has_stick = (id == 8'h73) || (id == 8'h79);

    // "something sane answered": it sent the 5a and an ID with a length in it
    wire present_now = (hdr == 8'h5A) && (id != 8'hFF) && (id[3:0] != 4'd0);

    // DAT comes off a metre of cable with no relation to this clock, so it
    // gets the usual two flip-flops before anything looks at it. 2 clocks is
    // 79 ns against a 2.5 us half-bit - invisible.
    reg [1:0] dat_sync = 2'b11;
    always @(posedge clk) dat_sync <= {dat_sync[0], ps2_dat};

    assign dat_hi = dat_sync[1];

    // ---- wiring check ------------------------------------------------------
    // Holding it puts each output at a level a cheap multimeter can tell
    // apart, so the three FPGA outputs can be found on the header without a
    // scope and without having to trust the schematic:
    //
    //   ATTENTION  steady 0 V        CLOCK  steady 3.3 V
    //   COMMAND    swinging 0 <-> 3.3 V about once a second
    //
    // Whatever is measured on DATA is the controller's business, not ours.
    reg [23:0] beacon = 24'd0;
    always @(posedge clk) beacon <= beacon + 24'd1;

    always @(posedge clk) begin
        if (find) begin
            st      <= S_IDLE;
            ps2_att <= 1'b0;
            ps2_clk <= 1'b1;
            ps2_cmd <= beacon[23];
            present <= 1'b0;
            alive   <= 1'b0;
        end else
        case (st)

        // ---- waiting for the frame tick ------------------------------------
        S_IDLE: begin
            ps2_att <= 1'b1;
            ps2_clk <= 1'b1;
            ps2_cmd <= 1'b1;
            if (poll) begin
                ps2_att <= 1'b0;
                byte_i  <= 4'd0;
                txb     <= tx_of(4'd0);
                rxb     <= 8'h00;
                lx      <= 8'h80;      // so a digital pad reads as centred
                ly      <= 8'h80;
                dat_any <= 1'b0;
                cnt     <= 12'd0;
                st      <= S_LEAD;
            end
        end

        // ---- ATT has to settle before the first clock edge ------------------
        S_LEAD: if (cnt == GAP[11:0]) begin
            cnt   <= 12'd0;
            bit_i <= 3'd0;
            st    <= S_HI;
        end else
            cnt <= cnt + 12'd1;

        // ---- clock high, then put this bit out on the falling edge ---------
        S_HI: if (cnt == HALF[11:0] - 12'd1) begin
            cnt     <= 12'd0;
            ps2_clk <= 1'b0;
            ps2_cmd <= txb[0];
            txb     <= {1'b1, txb[7:1]};
            st      <= S_LO;
        end else
            cnt <= cnt + 12'd1;

        // ---- clock low, then latch the pad's bit on the rising edge --------
        S_LO: if (cnt == HALF[11:0] - 12'd1) begin
            cnt     <= 12'd0;
            ps2_clk <= 1'b1;
            rxb     <= {dat_sync[1], rxb[7:1]};  // LSB first
            if (!dat_sync[1]) dat_any <= 1'b1;
            if (bit_i == 3'd7)
                st <= S_GAP;
            else begin
                bit_i <= bit_i + 3'd1;
                st    <= S_HI;
            end
        end else
            cnt <= cnt + 12'd1;

        // ---- byte done: file it away, then start the next one --------------
        S_GAP: begin
            ps2_cmd <= 1'b1;
            if (cnt == GAP[11:0]) begin
                cnt <= 12'd0;
                case (byte_i)
                4'd1: begin
                    id <= rxb;
                    // the low nibble counts 16-bit words; cap at the six
                    // bytes this design has any use for
                    ndata <= (rxb[3:0] >= 4'd3) ? 4'd6 : {rxb[2:0], 1'b0};
                end
                4'd2: hdr <= rxb;
                4'd3: b0  <= rxb;
                4'd4: b1  <= rxb;
                4'd7: lx  <= rxb;
                4'd8: ly  <= rxb;
                default: ;
                endcase

                if (byte_i >= 4'd2 + ndata)
                    st <= S_END;
                else begin
                    byte_i <= byte_i + 4'd1;
                    txb    <= tx_of(byte_i + 4'd1);
                    bit_i  <= 3'd0;
                    rxb    <= 8'h00;
                    st     <= S_HI;
                end
            end else
                cnt <= cnt + 12'd1;
        end

        // ---- release the bus and publish this frame's buttons --------------
        S_END: begin
            ps2_att <= 1'b1;
            ps2_cmd <= 1'b1;
            present <= present_now;
            alive   <= dat_any;
            st      <= S_IDLE;
        end

        default: st <= S_IDLE;
        endcase

        // buttons are active low on the wire; the stick doubles for the d-pad
        if (st == S_END) begin
            pad_up    <= present_now && (~b0[4] || (has_stick && ly < STICK_LO));
            pad_down  <= present_now && (~b0[6] || (has_stick && ly > STICK_HI));
            pad_left  <= present_now && (~b0[7] || (has_stick && lx < STICK_LO));
            pad_right <= present_now && (~b0[5] || (has_stick && lx > STICK_HI));
            pad_ok    <= present_now && (~b1[4] | ~b1[5] | ~b1[6] | ~b1[7] |
                                         ~b0[3]);
        end
    end

endmodule
