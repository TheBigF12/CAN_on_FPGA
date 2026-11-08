`timescale 1ns / 1ps

module bit_unstuffer(
    input  wire clk,
    input  wire sample_tick, // mid-bit sample strobe from bit timing unit
    input  wire in_bit, // synchronized rx line (rx_sync)
    input  wire unstuff_enable, // high from SOF through end of CRC
    output reg  bit_out, // the sampled bit value
    output reg  bit_valid // 1 = real frame bit, 0 = stuff bit (discard)
);

localparam S_IDLE = 2'd0;
localparam S_UNSTUFF_1 = 2'd1;
localparam S_UNSTUFF_0 = 2'd2;

reg [1:0] CS = S_IDLE;
reg [1:0] NS;
reg [2:0] count = 3'd0;

always @(*) begin
    NS = CS;
    bit_out = in_bit; // the bit value is always just the sample
    bit_valid = 1'b1; // default
    
    case (CS)
        S_IDLE: begin
            if (unstuff_enable && sample_tick)
                NS = (in_bit == 1'b0) ? S_UNSTUFF_1 : S_UNSTUFF_0;
        end
        
        S_UNSTUFF_1: begin   // last bit was 0 counting 0s
            if (sample_tick) begin
                if (!unstuff_enable)
                    NS = S_IDLE;
                else if (count == 3'd5) begin
                    // Five 0s just went by: THIS bit is the stuff bit.
                    // The stuffer guaranteed it is a 1. Discard it.
                    bit_valid = 1'b0;
                    NS = S_UNSTUFF_0;    // the stuff bit (1) starts a new run
                end
                else if (in_bit == 1'b0)
                    NS = S_UNSTUFF_1;    // run of 0s continues
                else
                    NS = S_UNSTUFF_0;    // real polarity change
            end
        end
        
        S_UNSTUFF_0: begin     // last bit was 1, counting 1s
            if (sample_tick) begin
                if (!unstuff_enable)
                    NS = S_IDLE;
                else if (count == 3'd5) begin
                    // Five 1s just went by: this bit is the stuff bit (a 0).
                    bit_valid = 1'b0;
                    NS = S_UNSTUFF_1;
                end
                else if (in_bit == 1'b1)
                    NS = S_UNSTUFF_0;
                else
                    NS = S_UNSTUFF_1;
            end
        end
        
        default: NS = S_IDLE;
    endcase
end

always @(posedge clk) begin
    CS <= NS;
    
    if (sample_tick) begin
        case (NS)
            S_IDLE:    count <= 3'd0;
            
            S_UNSTUFF_1: begin
                if (CS == S_UNSTUFF_1)
                    count <= count + 1'b1;
                else
                    count <= 3'd1; // entered via transition or stuff discard
            end
            
            S_UNSTUFF_0: begin
                if (CS == S_UNSTUFF_0)
                    count <= count + 1'b1;
                else
                    count <= 3'd1;
            end
            
            default: count <= 3'd0;
        endcase
    end
end

endmodule
