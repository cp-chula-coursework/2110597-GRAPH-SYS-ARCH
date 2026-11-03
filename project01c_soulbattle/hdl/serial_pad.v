//------------------------------------------------------------------------------
// serial_pad.v
//
// Turns the bytes coming off the PS2-to-serial adapter into held button
// levels, which is what the game wants.
//
// The adapter sends one byte per button rather than the packet its
// documentation describes:
//
//   41 up        42 down     43 left     44 right      ('A'..'D')
//   49 triangle  4a cross    4b square   4c circle     ('I'..'L')
//
// Read off the hardware one button at a time - the adapter's own
// documentation describes a different scheme entirely.
//
// A byte says a button is down; nothing says it has come back up. So each
// button gets a timer instead: a byte reloads it, the frame tick counts it
// down, and the button reads as held while the timer is running. As long as
// the adapter repeats faster than HOLD_FRAMES the button stays down for as
// long as it is really held, and lets go about a fifth of a second after.
// That last part is why the timer is not longer than it is - it is the lag
// between letting go and the soul stopping.
//
// Some of these adapters send a release code as well - the same letter in
// lower case - so those clear the timer outright and make letting go instant.
// If this one does not send them, nothing is lost; the timeout still works.
//
// The four face buttons all mean "confirm", as do the other codes in the
// same run of letters - whichever of them the shoulder buttons and START
// turn out to be.
//------------------------------------------------------------------------------
module serial_pad #(
    parameter [7:0]   CODE_UP     = 8'h41,
    parameter [7:0]   CODE_DOWN   = 8'h42,
    parameter [7:0]   CODE_LEFT   = 8'h43,
    parameter [7:0]   CODE_RIGHT  = 8'h44,
    parameter [7:0]   CODE_TRI    = 8'h49,   // triangle
    parameter [7:0]   CODE_CROSS  = 8'h4A,   // cross
    parameter [7:0]   CODE_SQUARE = 8'h4B,   // square
    parameter [7:0]   CODE_CIRCLE = 8'h4C,   // circle
    parameter integer HOLD_FRAMES = 12      // ~200 ms at 60 Hz
)(
    input  wire       clk,
    input  wire       frame_start,
    input  wire [7:0] data,
    input  wire       valid,

    output wire       up,
    output wire       down,
    output wire       left,
    output wire       right,
    output wire       ok,
    output reg  [7:0] last = 8'h00     // last byte seen, for the read-out
);

    localparam integer TW = 5;         // enough for HOLD_FRAMES

    reg [TW-1:0] t_up = 0, t_dn = 0, t_lf = 0, t_rt = 0, t_ok = 0;

    // lower case of each direction code, if the adapter sends release codes
    localparam [7:0] REL_UP    = CODE_UP    | 8'h20,
                     REL_DOWN  = CODE_DOWN  | 8'h20,
                     REL_LEFT  = CODE_LEFT  | 8'h20,
                     REL_RIGHT = CODE_RIGHT | 8'h20;

    always @(posedge clk) begin
        // the frame tick ages every timer...
        if (frame_start) begin
            if (t_up != 0) t_up <= t_up - 1'b1;
            if (t_dn != 0) t_dn <= t_dn - 1'b1;
            if (t_lf != 0) t_lf <= t_lf - 1'b1;
            if (t_rt != 0) t_rt <= t_rt - 1'b1;
            if (t_ok != 0) t_ok <= t_ok - 1'b1;
        end

        // ... and an arriving byte overrules it, so a button that is being
        // held never ages out between repeats
        if (valid) begin
            last <= data;
            case (data)
            CODE_UP:    t_up <= HOLD_FRAMES[TW-1:0];
            CODE_DOWN:  t_dn <= HOLD_FRAMES[TW-1:0];
            CODE_LEFT:  t_lf <= HOLD_FRAMES[TW-1:0];
            CODE_RIGHT: t_rt <= HOLD_FRAMES[TW-1:0];
            REL_UP:     t_up <= 0;
            REL_DOWN:   t_dn <= 0;
            REL_LEFT:   t_lf <= 0;
            REL_RIGHT:  t_rt <= 0;
            CODE_TRI, CODE_CROSS, CODE_SQUARE, CODE_CIRCLE:
                t_ok <= HOLD_FRAMES[TW-1:0];
            default:
                // The four face buttons above are the ones actually read off
                // the pad. The shoulder buttons, START and SELECT sit in the
                // same run of letters somewhere and are taken as confirm too,
                // without needing to know which is which; the range stops
                // short of the directions and of their lower-case releases.
                if (data >= 8'h45 && data <= 8'h58)
                    t_ok <= HOLD_FRAMES[TW-1:0];
            endcase
        end
    end

    assign up    = (t_up != 0);
    assign down  = (t_dn != 0);
    assign left  = (t_lf != 0);
    assign right = (t_rt != 0);
    assign ok    = (t_ok != 0);

endmodule
