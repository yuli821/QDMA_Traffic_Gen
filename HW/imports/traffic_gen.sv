`timescale 1ps / 1ps
module traffic_gen #(
    parameter FLOW_SPEED = 10000000, //10Mbps
    parameter MAX_ETH_FRAME = 1500, //bytes
    parameter RX_LEN = 8, //data width
    parameter RX_BEN = RX_LEN/8,
    parameter DST_MAC = 48'h800000000000,
    parameter SRC_MAC = 48'h800000000001
)
(
    input user_clk,
    input user_resetn,
    input [31:0] control_reg,
    input [15:0] pkt_size,
    output error,
    output rx_valid,
    output [RX_BEN-1:0]  rx_ben,
    output [RX_LEN-1:0] rx_data //1 byte
);
localparam CYCLES_PER_SEC = 250000000;

int cycles_per_pkt, cycles_needed;
logic [31:0] crc;
logic [111:0] header_buf;
logic [RX_LEN-1:0] data_buf;
logic start_c2h;

logic [15:0] frame_size, num_frame, last_frame_size;
logic [31:0] counter_frame;
logic [31:0] counter_trans;
logic [31:0] counter_wait;

// assign frame_size = (pkt_size > MAX_ETH_FRAME) ? MAX_ETH_FRAME + 16'h12 : pkt_size + 16'h12; //18 bytes: header + crc
assign last_frame_size = pkt_size % MAX_ETH_FRAME;
assign num_frame = pkt_size / MAX_ETH_FRAME;

assign header_buf = {DST_MAC, SRC_MAC, length}; 
assign crc = 32'b0;

assign cycles_per_pkt = (8 * (frame_size * num_frame + last_frame_size) * CYCLES_PER_SEC) / FLOW_SPEED; //based on flow speed, how many cycles are required for a pkt
assign cycles_needed = (8 * (frame_size * num_frame + last_frame_size)) / RX_LEN; //Actual number of cycles needed to transfer a packet
assign error = (cycles_needed > cycles_per_pkt) ? 1'b1 : 1'b0;

enum [2:0] {IDLE, TRANSFER, WAIT} curr_state, next_state;
//output signal
always_comb begin 
    case (curr_state)
        IDLE: begin 
            rx_valid = 1'b0;
            rx_ben = RX_BEM'(0);
            rx_data = RX_LEN'(0);
        end
        TRANSFER: begin 
            
        end
        WAIT: begin 
        end
    endcase
end
//next_state logic
always_comb begin 
    case (curr_state)
        IDLE: begin 
            if (start_c2h)
                next_state = TRANSFER;
            else 
                next_state = IDLE;
        end
        TRANSFER: begin 
            if (counter_trans >= (frame_size - 16'b1)) next_state = WAIT;
            else                                       next_state = TRANSFER;
        end
        WAIT: begin 
        end
    endcase
end

always_ff @(posedge user_clk) begin 
    if (~user_resetn) begin 
        curr_state <= IDLE;
        start_c2h <= 1'b0;
        frame_size <= 16'b0;
        counter_frame <= 32'b0;
        counter_trans <= 32'b0;
        counter_wait <= 32'b0;
    end else begin 
        curr_state <= next_state;
        start_c2h <= control_reg[1];
        case(curr_state)
            IDLE: begin 
                frame_size <= (num_frame > 16'b0) ? MAX_ETH_FRAME+16'h12 : last_frame_size + 16'h12;
                counter_frame <= 32'b0;
                counter_trans <= 32'b0;
            end
            TRANSFER: begin
                counter_wait <= 32'b0;
                counter_trans <= counter_trans + RX_LEN/8;
                if (counter >= (frame_size - 16'b1)) counter_frame <= counter_frame + 1'b1;
            end
            WAIT: begin 
                counter_trans <= 16'b0;
                counter_wait <= counter_wait + 32'b1;
                if (counter_frame < num_frame) frame_size <= MAX_ETH_FRAME+16'h12;
                else if 
            end
        endcase
    end
end

endmodule
