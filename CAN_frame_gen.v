`timescale 1ns / 1ps
module CAN_frame_gen(
    input clk,
    input wire [3:0] id,
    input wire [3:0] dlc,
    input wire [7:0] data,
    input wire btn,
    output wire tx_out,
    output reg frame_done,
    
    input  wire rx_pin,
    output wire [10:0] id_out,
    output wire [3:0] dlc_out,
    output wire [7:0] D0_out,
    output wire [7:0] D1_out
);
reg shifted_out = 1'b1;
reg btn_prev = 1'b0; //stateholder for the previous state of the button, we will use the debounced btn signal
wire start_pulse = btn & ~btn_prev; //at the falling edge, start pulse

always @(posedge clk) begin  //after checking the previous and current states it assigns the current one as the previous one. ready for the next btn input
    btn_prev <= btn;
end

reg [7:0] counter=8'b0; //8 bit register to count up until 100
wire bit_tick=(counter==8'd99);//1Mbps bitrate, it creates a signal for every 100th (counting from 0-99)

always @(posedge clk) begin
    if (counter == 8'd99)//if the counter reaches the determined value, it resets
        counter <= 8'b0;
    else
        counter <= counter + 1; //if not the counter increments by one at every clockedge until it reaches the target value
end

wire SOF=1'b0;
wire [11:0] ID={7'b0,id,1'b0}; //id+RTR
wire [5:0] CONTROL={2'b0,dlc};//IDE+r_0+DLC

wire [7:0] D0={data};//1st byte of the data
wire [7:0] D1=8'b1010_0001;//2nd byte of the data
wire [7:0] D2=8'b0101_0010;//3rd byte of the data
wire [7:0] D3=8'b1010_0011;//4th byte of the data
wire [7:0] D4=8'b0101_0100;//5th byte of the data
wire [7:0] D5=8'b1010_0101;//6th byte of the data
wire [7:0] D6=8'b0101_0110;//7th byte of the data
wire [7:0] D7=8'b1010_0111;//8th byte of the data
wire [63:0] DATA={D0,D1,D2,D3,D4,D5,D6,D7};//DATA frame

wire [14:0] CRC=15'b0;
wire CRC_DEL=1'b1;
wire ACK=1'b1;
wire ACK_DEL=1'b1;
wire [6:0] EOF=7'b1111111;


wire [107:0] wire_frame={SOF,ID,CONTROL,DATA,CRC,CRC_DEL,ACK,ACK_DEL,EOF};

localparam S_IDLE= 1'd0;
localparam S_SHIFT= 1'd1; //when the btn is pressed data starts to shift

reg CS = S_IDLE;
reg NS;
reg [6:0] i=7'd107;
reg done = 1'b0;

wire [6:0] jump = 7'd89 - {dlc, 3'b0};

wire stuff_enable = (CS == S_SHIFT) && (i >= 7'd10) && !done;
wire stuffer_bit = output_bit;
wire stuffed_out;
wire is_stuffing;

bit_stuffer stuffer_inst (
    .clk(clk),
    .bit_tick(bit_tick),
    .in_bit(stuffer_bit),
    .stuff_enable(stuff_enable),
    .out_bit(stuffed_out),
    .stuffing(is_stuffing)
);

reg [14:0] crc_reg = 15'b0;
localparam CRC_POLY = 15'h4599;

wire crc_we = (CS == S_SHIFT) && (i >= 7'd25);
wire crc_xor_flag = wire_frame[i]^crc_reg[14];
wire [14:0] crc_new = crc_xor_flag ? {crc_reg[13:0], 1'b0}^CRC_POLY : {crc_reg[13:0], 1'b0};

always @(posedge clk) begin
    if (CS == S_IDLE)
        crc_reg <= 15'b0;
    else if (bit_tick && !is_stuffing && crc_we)
        crc_reg <= crc_new;
    else
        crc_reg <= crc_reg;
end

wire in_crc_field = (i >= 7'd10) && (i <= 7'd24);
wire output_bit = in_crc_field ? crc_reg[i - 7'd10] : wire_frame[i];

wire lost_arbitration = (CS == S_SHIFT) && (i >= 7'd95) && (i <= 7'd106)&& sample_tick && shifted_out && !rx_sync;

wire bit_error = (CS == S_SHIFT) && sample_tick&& (i <= 7'd94) && (i != 7'd8)&& (shifted_out != rx_sync);

always @(*) begin
    NS = CS;
    case (CS)
        S_IDLE:  NS = start_pulse ? S_SHIFT : S_IDLE;
        S_SHIFT: begin
            if (lost_arbitration)
                NS = S_IDLE;
            else if (bit_tick && done)
                NS = S_IDLE;
            else
                NS = S_SHIFT;
        end
        default: NS = S_IDLE;
    endcase
end

always @(posedge clk) begin
    CS <= NS;
        
    case (CS)
        S_IDLE: begin
            shifted_out<= 1'b1;
            i<= 7'd107;
            done<= 1'b0;
        end
        
        S_SHIFT: begin
            if (bit_tick) begin
                shifted_out <= stuffed_out;
                
                if (!is_stuffing) begin
                    if (i == 7'd0)
                        done <= 1'b1;
                    else if (i == jump)
                        i <= 7'd24;  
                    else
                        i<=i-1;
                end
             end
          end
     endcase
 end


//***********RECEIVER*************//
//input synchronizer (two flip-flops: metastability containment)
reg rx_ff0  = 1'b1;
reg rx_sync = 1'b1;

always @(posedge clk) begin
    rx_ff0  <= rx_pin;
    rx_sync <= rx_ff0;
end

//falling edge detector
reg rx_prev = 1'b1;
always @(posedge clk) rx_prev <= rx_sync;

wire falling_edge = rx_prev & ~rx_sync;


localparam S_IDLE_RX = 1'b0; //idle state
localparam S_RX   = 1'b1; //reading state

reg CS_RX = S_IDLE_RX;
reg NS_RX;

wire sof_edge = falling_edge & (CS_RX == S_IDLE_RX);   // hard sync only from idle

reg [6:0] bit_cnt = 7'd0;
wire sample_tick = (CS_RX == S_RX) && (bit_cnt == 7'd79);

reg synced_this_bit = 1'b0;
localparam SJW = 7'd6;
wire resync_edge = falling_edge && (CS_RX == S_RX)&& !synced_this_bit && (bit_cnt != 7'd0);

always @(posedge clk) begin
    if (sof_edge)
        bit_cnt <= 7'd0;
    else if (resync_edge) begin
        if (bit_cnt < 7'd79) 
            bit_cnt <= (bit_cnt > SJW) ? (bit_cnt - SJW) : 7'd0;
            
        else
            bit_cnt <= ((7'd100-bit_cnt) > SJW) ? (bit_cnt + SJW) : 7'd0;
        end       
    else if (bit_cnt == 7'd99)
        bit_cnt <= 7'd0;
    else
        bit_cnt <= bit_cnt + 1;
end

always @(posedge clk) begin
    if (sof_edge)
        synced_this_bit <= 1'b0;      // clear stale flag at start of each frame
    else if (resync_edge)
        synced_this_bit <= 1'b1;
    else if (sample_tick)   
        synced_this_bit <= 1'b0;
end

reg [6:0] j = 7'd0;  // bit position within frame
reg [107:0] rx_frame = 108'b0;   // full received frame, indexed to match wire_frame

wire [6:0] crc_end = 7'd33 + {dlc_reg, 3'b0}; // last CRC bit
wire [6:0] frame_end = 7'd43 + {dlc_reg, 3'b0}; // last EOF bit

// Field slices out of the reconstructed frame (fixed positions, DLC-independent)
wire [10:0] rx_id = rx_frame[106:96];
wire [3:0]  rx_dlc = rx_frame[92:89];
wire [7:0]  rx_byte0 = rx_frame[88:81];
wire [7:0]  rx_byte1 = rx_frame[80:73];

// dlc_reg tracks the DLC live during reception (needed for crc_end / frame_end)
reg [3:0] dlc_reg = 4'b0;

// Destuffing active from SOF through end of CRC
wire unstuff_enable = (CS_RX == S_RX) && (j <= crc_end);

wire bit_out;
wire bit_valid;

bit_unstuffer destuffer_inst (
    .clk(clk),
    .sample_tick(sample_tick),
    .in_bit(rx_sync),
    .unstuff_enable(unstuff_enable),
    .bit_out(bit_out),
    .bit_valid(bit_valid)
);

//rx crc calc
reg [14:0] crc_calc = 15'b0;   // CRC computed over received SOF..data
reg [14:0] crc_rx = 15'b0;   // CRC field as received off the wire
reg crc_ok = 1'b0;    // latched result of last completed frame

// CRC covers SOF through end of data: j <= 18 + 8*dlc
// (crc_end = 33 + 8*dlc, so the data field ends at crc_end - 15)
wire [6:0] crc_data_end  = crc_end - 7'd15;   // = 18 + 8*dlc
wire [6:0] crc_field_top = crc_end - 7'd14;   // = 19 + 8*dlc, first CRC bit

wire crc_we_rx = (CS_RX == S_RX) && (j <= crc_data_end);
wire in_crc_rx = (CS_RX == S_RX) && (j >= crc_field_top) && (j <= crc_end);

// Same LFSR form as the transmitter
wire crc_xor_flag_rx = bit_out ^ crc_calc[14];
wire [14:0] crc_new_rx = crc_xor_flag_rx ? {crc_calc[13:0], 1'b0} ^ CRC_POLY
                                         : {crc_calc[13:0], 1'b0};



always @(posedge clk) begin
    if (CS_RX == S_IDLE_RX) begin
        crc_calc <= 15'b0;
        crc_rx   <= 15'b0;
    end
    else if (sample_tick && bit_valid) begin
        if (crc_we_rx)
            crc_calc <= crc_new_rx;
        if (in_crc_rx)
            crc_rx <= {crc_rx[13:0], bit_out};
    end
end

//ACK
// Drive dominant for one bit when we received a correct frame that we did not transmit ourselves.
wire [6:0] ack_slot = crc_end + 7'd2;
reg ack_drive = 1'b0;

always @(posedge clk) begin
    if (CS_RX == S_IDLE_RX)
        ack_drive <= 1'b0;
    else if (bit_cnt == 7'd0 && j == ack_slot && crc_ok && (CS != S_SHIFT))
        ack_drive <= 1'b1; // start of ACK slot
    else if (bit_cnt == 7'd0 && j == ack_slot + 7'd1)
        ack_drive <= 1'b0; // start of ACK delimiter
end

reg ack_received = 1'b0;

always @(posedge clk) begin
    if (CS == S_IDLE && start_pulse)
        ack_received <= 1'b0;
    else if (CS == S_SHIFT && sample_tick && i == 7'd7) // ACK bit
        ack_received <= !rx_sync; //to check the error
end

assign tx_out = shifted_out & ~ack_drive; // both can pull the bus dominant


always @(*) begin
    case (CS_RX)
        S_IDLE_RX: NS_RX = sof_edge ? S_RX : S_IDLE_RX;
        S_RX: NS_RX = (sample_tick && bit_valid && (j == frame_end)) ? S_IDLE_RX : S_RX;
        default: NS_RX = S_IDLE_RX;
    endcase
end

always @(posedge clk) begin
    CS_RX <= NS_RX;
    frame_done <= 1'b0;
    
    case (CS_RX)
        S_IDLE_RX: begin
            j <= 7'd0;
            dlc_reg <= 4'b0;
        end
        
        S_RX: begin
    if (sample_tick && bit_valid) begin
        
        // store every received bit into the frame register
        rx_frame[7'd107 - j] <= bit_out;
        
        // track DLC live: needed by crc_end / frame_end before the frame ends
        if (j >= 7'd15 && j <= 7'd18)
            dlc_reg <= {dlc_reg[2:0], bit_out};
        
        // latch the CRC verdict as the last CRC bit arrives
        if (j == crc_end)
            crc_ok <= (crc_calc == {crc_rx[13:0], bit_out});
        
        // detect end of frame
        if (j == frame_end) begin
            frame_done <= 1'b1;
            j <= 7'd0;
        end
        else
            j <= j + 1;
    end
end
    endcase
end

// Latch display fields on frame completion so the display never shows
// a partially-received frame
reg [10:0] id_disp = 11'b0;
reg [3:0]  dlc_disp = 4'b0;
reg [7:0]  byte0_disp = 8'b0;
reg [7:0]  byte1_disp = 8'b0;

always @(posedge clk) begin
    if (frame_done) begin
        id_disp    <= rx_id;
        dlc_disp   <= (rx_dlc > 4'd8) ? 4'd8 : rx_dlc;
        byte0_disp <= (rx_dlc >= 4'd1) ? rx_byte0 : 8'h00;
        byte1_disp <= (rx_dlc >= 4'd2) ? rx_byte1 : 8'h00;
    end
end

assign id_out = id_disp;
assign dlc_out = dlc_disp;
assign D0_out = byte0_disp;
assign D1_out = byte1_disp;

endmodule