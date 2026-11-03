//------------------------------------------------------------------------------
// digit_font.v
//
// Combinational 5x7 dot-matrix font ROM for digits 0-9, used to render the
// scoreboard. row_bits[4] is the leftmost pixel of the glyph row.
//------------------------------------------------------------------------------
module digit_font (
    input  wire [3:0] digit,    // 0-9 (other values render blank)
    input  wire [2:0] row,      // 0-6
    output reg  [4:0] row_bits
);
    always @(*) begin
        case (digit)
            4'd0: case (row)
                3'd0: row_bits = 5'b01110;
                3'd1: row_bits = 5'b10001;
                3'd2: row_bits = 5'b10011;
                3'd3: row_bits = 5'b10101;
                3'd4: row_bits = 5'b11001;
                3'd5: row_bits = 5'b10001;
                3'd6: row_bits = 5'b01110;
                default: row_bits = 5'b00000;
            endcase
            4'd1: case (row)
                3'd0: row_bits = 5'b00100;
                3'd1: row_bits = 5'b01100;
                3'd2: row_bits = 5'b00100;
                3'd3: row_bits = 5'b00100;
                3'd4: row_bits = 5'b00100;
                3'd5: row_bits = 5'b00100;
                3'd6: row_bits = 5'b01110;
                default: row_bits = 5'b00000;
            endcase
            4'd2: case (row)
                3'd0: row_bits = 5'b01110;
                3'd1: row_bits = 5'b10001;
                3'd2: row_bits = 5'b00001;
                3'd3: row_bits = 5'b00010;
                3'd4: row_bits = 5'b00100;
                3'd5: row_bits = 5'b01000;
                3'd6: row_bits = 5'b11111;
                default: row_bits = 5'b00000;
            endcase
            4'd3: case (row)
                3'd0: row_bits = 5'b11111;
                3'd1: row_bits = 5'b00010;
                3'd2: row_bits = 5'b00100;
                3'd3: row_bits = 5'b00010;
                3'd4: row_bits = 5'b00001;
                3'd5: row_bits = 5'b10001;
                3'd6: row_bits = 5'b01110;
                default: row_bits = 5'b00000;
            endcase
            4'd4: case (row)
                3'd0: row_bits = 5'b00010;
                3'd1: row_bits = 5'b00110;
                3'd2: row_bits = 5'b01010;
                3'd3: row_bits = 5'b10010;
                3'd4: row_bits = 5'b11111;
                3'd5: row_bits = 5'b00010;
                3'd6: row_bits = 5'b00010;
                default: row_bits = 5'b00000;
            endcase
            4'd5: case (row)
                3'd0: row_bits = 5'b11111;
                3'd1: row_bits = 5'b10000;
                3'd2: row_bits = 5'b11110;
                3'd3: row_bits = 5'b00001;
                3'd4: row_bits = 5'b00001;
                3'd5: row_bits = 5'b10001;
                3'd6: row_bits = 5'b01110;
                default: row_bits = 5'b00000;
            endcase
            4'd6: case (row)
                3'd0: row_bits = 5'b00110;
                3'd1: row_bits = 5'b01000;
                3'd2: row_bits = 5'b10000;
                3'd3: row_bits = 5'b11110;
                3'd4: row_bits = 5'b10001;
                3'd5: row_bits = 5'b10001;
                3'd6: row_bits = 5'b01110;
                default: row_bits = 5'b00000;
            endcase
            4'd7: case (row)
                3'd0: row_bits = 5'b11111;
                3'd1: row_bits = 5'b00001;
                3'd2: row_bits = 5'b00010;
                3'd3: row_bits = 5'b00100;
                3'd4: row_bits = 5'b01000;
                3'd5: row_bits = 5'b01000;
                3'd6: row_bits = 5'b01000;
                default: row_bits = 5'b00000;
            endcase
            4'd8: case (row)
                3'd0: row_bits = 5'b01110;
                3'd1: row_bits = 5'b10001;
                3'd2: row_bits = 5'b10001;
                3'd3: row_bits = 5'b01110;
                3'd4: row_bits = 5'b10001;
                3'd5: row_bits = 5'b10001;
                3'd6: row_bits = 5'b01110;
                default: row_bits = 5'b00000;
            endcase
            4'd9: case (row)
                3'd0: row_bits = 5'b01110;
                3'd1: row_bits = 5'b10001;
                3'd2: row_bits = 5'b10001;
                3'd3: row_bits = 5'b01111;
                3'd4: row_bits = 5'b00001;
                3'd5: row_bits = 5'b00010;
                3'd6: row_bits = 5'b01100;
                default: row_bits = 5'b00000;
            endcase
            default: row_bits = 5'b00000;
        endcase
    end
endmodule
