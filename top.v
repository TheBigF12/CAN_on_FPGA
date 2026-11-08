`timescale 1ns / 1ps

module top (
    input  wire CLK100MHZ,
    input  wire [15:0] SW,
    input  wire BTNC,
    output wire [15:0] LED,
    output wire JA1,
    input  wire JA2,
    output wire [7:0]  AN,
    output wire CA, CB, CC, CD, CE, CF, CG,
    output wire DP
);

    assign LED = SW;
    assign DP  = 1'b1;             // decimal points off (active-low)

    wire btnc_db;
    button_debouncer db_btnc (
        .clk(CLK100MHZ),
        .btn(BTNC),
        .btn_db(btnc_db)
    );

    wire [3:0] dlc;
    assign dlc = (SW[3:0] <= 4'd8) ? SW[3:0] : 4'd8;

    wire tx;
    wire [10:0] id_rx;
    wire [3:0]  dlc_rx;
    wire [7:0]  byte0_rx;
    wire [7:0]  byte1_rx;
    wire frame_done;

    CAN_frame_gen can_inst (
        .clk(CLK100MHZ),
        .id(SW[7:4]),
        .dlc(dlc),
        .data(SW[15:8]),
        .btn(btnc_db),
        .rx_pin(JA2),
        .tx_out(tx),
        .id_out(id_rx),
        .dlc_out(dlc_rx),
        .D0_out(byte0_rx),
        .D1_out(byte1_rx),
        .frame_done(frame_done)
    );

    assign JA1 = tx;

    wire [31:0] display_val = {1'b0, id_rx, dlc_rx, byte0_rx, byte1_rx};

    MSSD mssd_inst (
        .clk(CLK100MHZ),
        .val(display_val),
        .display({CG, CF, CE, CD, CC, CB, CA}),
        .AN(AN)
    );

endmodule