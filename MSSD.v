`timescale 1ns / 1ps

module MSSD(
    input wire clk,
    input wire [31:0] val,
    output wire [6:0] display,
    output wire [7:0] AN
    );
    
    reg [2:0] i=0;
    reg [31:0] count=0;
    assign AN = ~(8'b00000001<<i);
    
    always@(posedge clk) begin
        if(count==100000) begin
            count<=0;
            i<=i+1;
        end else begin
            count <=count+1;
        end
    
    end
    SSD ssd_inst(
    .val({val[i*4+:4]}),
    .display(display)
    );
endmodule