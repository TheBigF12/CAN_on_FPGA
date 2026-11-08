`timescale 1ns / 1ps
module bit_stuffer(
    input  wire clk,
    input  wire bit_tick,
    input  wire in_bit,
    input  wire stuff_enable,
    output reg  out_bit,
    output reg  stuffing
);

localparam S_IDLE    = 2'd0;
localparam S_STUFF_0 = 2'd1;
localparam S_STUFF_1 = 2'd2;
 
reg [1:0] CS = S_IDLE;
reg [1:0] NS;
reg [2:0] count = 3'd0;

always @(*) begin
    NS = CS;
    out_bit  = in_bit; //stuffer input output relation
    stuffing = 1'b0; //indicator for stuffing
    
    case (CS)
    S_IDLE: begin
        out_bit=in_bit;
        stuffing = 1'b0;
            if (stuff_enable && bit_tick) begin
                NS= (in_bit == 1'b0) ? S_STUFF_1 : S_STUFF_0;
            end
        end

    S_STUFF_1: begin // Last bit was 1.
        if (bit_tick) begin
            if (!stuff_enable) begin
                out_bit = in_bit;
                stuffing = 1'b0;
                NS = S_IDLE;
            end
            else if (count == 3'd5) begin
                // Five 0s insert 1
                out_bit = 1'b1;
                stuffing = 1'b1;
                NS = S_STUFF_0;
                end
            else if (in_bit == 1'b0) begin
                out_bit = 1'b0;
                stuffing = 1'b0;
                NS = S_STUFF_1;
                end
            else begin
            // Input is 1
                out_bit = 1'b1;
                stuffing = 1'b0;
                NS = S_STUFF_0;
                end
            end
        end
        
    S_STUFF_0: begin
        // counting 1s
        if (bit_tick) begin
            if (!stuff_enable) begin
                out_bit = in_bit;
                stuffing = 1'b0;
                NS = S_IDLE;
                end
            else if (count == 3'd5) begin
                // five 1s reached insert 0
                out_bit  = 1'b0;
                stuffing = 1'b1;
                NS = S_STUFF_1;
                end
            else if (in_bit == 1'b1) begin
                out_bit = 1'b1;
                stuffing = 1'b0;
                NS = S_STUFF_0;
                end
            else begin
                out_bit = 1'b0;
                stuffing = 1'b0;
                NS = S_STUFF_1;
                end
            end
        end
            
    default: NS = S_IDLE;
    endcase
end

always @(posedge clk) begin
    CS <= NS;    
    if (bit_tick) begin
        case (NS)
            S_IDLE: begin
                count <= 3'd0;
                end
            S_STUFF_1: begin
                if (CS == S_STUFF_1)
                    count <= count + 1'b1;
                else
                    count <= 3'd1;
            end
                
            S_STUFF_0: begin
                if (CS == S_STUFF_0)
                    count <= count + 1'b1;
                else
                    count<= 3'd1;
            end
                
        default: count <= 3'd0;
        endcase
    end
end
endmodule