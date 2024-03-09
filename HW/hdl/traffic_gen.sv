`timescale 1ps / 1ps
module traffic_gen #(
    parameter FLOW_SPEED = 10000000, //10Mbps
    parameter MAX_ETH_FRAME = 1518, //bytes
    parameter RX_LEN = 128, //data width
    parameter RX_BEN = RX_LEN/8,
    parameter DST_MAC = 48'h800000000000,
    parameter SRC_MAC = 48'h800000000001
)
(
    input logic user_clk,
    input logic user_resetn,
    input logic [31:0] control_reg,
    output logic error,
    output logic rx_valid,
    output logic [RX_BEN-1:0]  rx_ben,
    output logic [RX_LEN-1:0] rx_data, //1 byte
    output logic rx_last
);
localparam CYCLES_PER_SEC = 250000000; //clock speed (250Mhz), 4ns per cycle
localparam BYTES_PER_BEAT = RX_LEN/8;

int cycles_per_frame, cycles_needed;
logic is_header;
logic [31:0] crc;
logic [111:0] header_buf;
logic [RX_LEN-1:0] data_buf;
logic start_c2h;

logic [31:0] counter_trans;
logic [31:0] counter_wait;

assign header_buf = {DST_MAC, SRC_MAC, 16'hff}; //omit the length
assign crc = 32'b0;

assign cycles_per_frame = (8 * MAX_ETH_FRAME * CYCLES_PER_SEC) / FLOW_SPEED; //based on flow speed, how many cycles are required for a frame
assign cycles_needed = (8 * MAX_ETH_FRAME) / RX_LEN; //Actual number of cycles needed to transfer a frame
assign error = (cycles_needed > cycles_per_frame) ? 1'b1 : 1'b0; //too slow

enum logic [2:0] {IDLE, TRANSFER, WAIT} curr_state, next_state;

// assign c2h_dpar = ~dpar_val;
always_comb begin
    for (integer i=0; i < BYTES_PER_BEAT; i += 1) begin
	    rx_ben[i] = ^rx_data[i*8 +: 8];
    end
end
//output signal
always_ff @(posedge user_clk) begin 
    if(~user_resetn | ~start_c2h) begin 
        for (integer j=0; j<BYTES_PER_BEAT; j++)
            data_buf[j*8 +: 8] <= j[7:0];
    end
    else if (rx_valid & (~is_header)) begin 
        for (integer j=0; j<BYTES_PER_BEAT; j++)
            data_buf[j*8 +: 8] <= data_buf[j*8 +: 8] + j[7:0];
    end
end

always_comb begin 
    rx_valid = 1'b0;
    rx_data = RX_LEN'(0);
    case (curr_state)
        IDLE: begin 
            rx_valid = 1'b0;
            rx_data = RX_LEN'(0);
        end
        TRANSFER: begin 
            rx_valid = 1'b1;
            if (is_header) begin 
                rx_data[111:0] = header_buf;
                for (integer j = 14 ; j < BYTES_PER_BEAT; j++)
                    rx_data[j*8 +: 8] = data_buf[j];
            end
            else begin 
                for (integer j = 0; j < BYTES_PER_BEAT; j++) begin
                    if ((counter_trans + j) >= MAX_ETH_FRAME) begin
                        rx_data[j*8 +: 8] = 8'b0;
                    end else begin 
                        rx_data[j*8 +: 8] = data_buf;
                    end
                end
            end
        end
        WAIT: begin 
            rx_valid = 1'b0;
            rx_data = RX_LEN'(0);
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
            if ((counter_trans + BYTES_PER_BEAT) >= MAX_ETH_FRAME) next_state = WAIT;
            else                                       next_state = TRANSFER;
        end
        WAIT: begin 
            if (~start_c2h) begin 
                next_state = IDLE;
            end
            else if (counter_wait < cycles_per_frame - 1) begin 
                next_state = WAIT;
            end
            else begin 
                next_state = TRANSFER;
            end
        end
        default: begin 
            next_state = IDLE;
        end
    endcase
end

always_ff @(posedge user_clk) begin 
    if (~user_resetn) begin 
        curr_state <= IDLE;
        start_c2h <= 1'b0;
        counter_trans <= 32'b0;
        counter_wait <= 32'b0;
        rx_last <= 1'b0;
        is_header <= 1'b1;
    end else begin 
        curr_state <= next_state;
        start_c2h <= control_reg[1];
        case(curr_state)
            IDLE: begin 
                counter_trans <= 32'b0;
                counter_wait <= 32'b0;
                rx_last <= 1'b0;
                is_header <= 1'b1;
            end
            TRANSFER: begin
                is_header <= 1'b0;
                counter_trans <= counter_trans + BYTES_PER_BEAT; //bytes
                counter_wait <= counter_wait + 32'b1;
                rx_last <= 1'b0;
                if ((counter_trans + BYTES_PER_BEAT) >= MAX_ETH_FRAME) begin
                    rx_last <= 1'b1;
                end
            end
            WAIT: begin 
                is_header <= 1'b1;
                rx_last <= 1'b0;
                counter_trans <= 16'b0;
                counter_wait <= counter_wait + 32'b1;
            end
        endcase
    end
end

endmodule
