`timescale 1ns / 1ps
module button_debouncer(
    input wire clk,
    input wire btn,
    output wire btn_db
    );
reg d_ff0=1'b0;
reg d_ff1=1'b0;
reg [20:0] counter=21'b0;
reg btn_db_reg = 1'b0;
always@(posedge clk) begin
    d_ff0<=btn;
    d_ff1<=d_ff0;
    if (d_ff1==btn_db_reg)
        counter<=21'b0;
    else if (counter==21'd2000000) begin
        btn_db_reg<=d_ff1;
        counter<=21'b0;
    end
    else  begin
        counter<=counter+1;
    end
end
assign btn_db=btn_db_reg;
endmodule