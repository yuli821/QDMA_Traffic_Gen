`timescale 1ps / 1ps
module traffic_gen #(
    parameter MAX_ETH_FRAME = 4096, //bytes
    parameter RX_LEN = 512, //data width
    parameter RX_BEN = RX_LEN/8,
    parameter TM_DSC_BITS = 16,
    parameter FLOW_SPEED = 1000000000//1Gbps
)
(
    input logic axi_aclk,
    input logic axi_aresetn,
    input logic [31:0] control_reg,
    input logic [15:0] txr_size,
    input logic [15:0] num_pkt,
    input logic [TM_DSC_BITS-1:0] credit_in,
    input logic credit_updt,
    input logic [TM_DSC_BITS-1:0] credit_perpkt_in,
    input logic [TM_DSC_BITS-1:0] credit_needed,
    input logic rx_ready,
    input logic [31:0] cycles_per_pkt,
    output logic rx_valid,
    output logic [RX_BEN-1:0] rx_ben,
    output logic [RX_LEN-1:0] rx_data, //1 byte
    output logic rx_last,
    output logic rx_end
);
localparam [31:0] cycles_per_second = 250000000;
localparam BYTES_PER_BEAT = RX_LEN/8;
localparam DST_MAC = 48'h665544332211;
localparam SRC_MAC = 48'h665544332211;
localparam TCQ = 1;

logic [15:0] frame_size, tot_pkt_size, counter_trans, curr_pkt_size;
logic [31:0] cycles_pkt;

logic is_header;
logic [31:0] crc;
logic [111:0] header_buf;
logic [RX_LEN-1:0] data_buf;
logic control_reg_1_d, start_c2h, start_c2h_d1, start_c2h_d2, ready;
logic [TM_DSC_BITS-1:0] credit_used_perpkt, tcredit_used, credit_in_sync;
logic lst_credit_pkt;
logic [15:0] pkt_count;
logic [31:0] cycles_needed;

int counter_wait;
assign header_buf = {DST_MAC, SRC_MAC, 16'h2121}; //omit the length
assign crc = 32'h0a212121;
assign rx_end = (~rx_valid) & (num_pkt == pkt_count);
assign lst_credit_pkt = (credit_perpkt_in - credit_used_perpkt) == 1;
assign cycles_needed = tot_pkt_size[15:6] +| tot_pkt_size[5:0]; //pkt size must > 64 bytes
// assign cycles_pkt = (cycles_per_pkt > cycles_needed) ? cycles_per_pkt : cycles_needed; //when cycles_pkt = 150, rx_ready behaves weiredly.

enum logic [1:0] {IDLE, TRANSFER, WAIT_FRAME, WAIT} curr_state;

//output signal
always_ff @(posedge axi_aclk) begin 
    control_reg_1_d <= control_reg[1];
    tot_pkt_size <= txr_size;
end

always_ff @(posedge axi_aclk) begin 
    start_c2h_d1 <= start_c2h;
    start_c2h_d2 <= start_c2h_d1;
end

always_ff @(posedge axi_aclk) begin 
    if (~axi_aresetn) begin 
        start_c2h <= 0;
    end
    else if (control_reg_1_d) begin 
        start_c2h <= 1;
    end
    else if (pkt_count >= num_pkt) begin
        start_c2h <= 0;
    end
end

always @(posedge axi_aclk)
    if (~axi_aresetn )
        credit_in_sync <= 0;
    else if (~start_c2h )
        credit_in_sync <= 0;
    else if (start_c2h & credit_updt)
        credit_in_sync <= credit_in_sync + credit_in;

always_ff @(posedge axi_aclk) begin 
    if (~axi_aresetn | ~start_c2h | rx_last | is_header) begin 
        for (integer j = 0 ; j < BYTES_PER_BEAT ; j++) begin
            if (j < 14) 
                data_buf[8*j +: 8] <= #TCQ header_buf[8*j +: 8];
            else 
                data_buf[8*j +: 8] <= #TCQ 8'h41;
            
        end
    end else if (rx_ready & rx_valid) begin 
        for (integer j = 0 ; j < BYTES_PER_BEAT ; j++) begin 
            if(((counter_trans + j) >= (frame_size - 4)) && ((counter_trans + j) < frame_size))
                data_buf[8*j +: 8] <= #TCQ crc[(counter_trans + j - frame_size + 4) * 8 +: 8];
            else 
                data_buf[8*j +: 8] <= #TCQ 8'h41;
        end
    end
end
assign rx_data = data_buf;

always_ff @(posedge axi_aclk) begin 
    if (~axi_aresetn) begin 
        curr_state <= IDLE;
        rx_valid <= 1'b0;
        rx_last <= 1'b0;
        pkt_count <= 0;
        credit_used_perpkt <= 0;
        tcredit_used <= 0;
        counter_wait <= 0;
        counter_trans <= 0;
        is_header <= 1'b1;
        frame_size <= 0;
        curr_pkt_size <= 0;
        cycles_pkt <= cycles_needed;
    end else begin 
        case(curr_state)
            IDLE: begin 
                if (start_c2h_d1 & ~start_c2h_d2 && (tcredit_used < credit_in_sync)) begin 
                    curr_state <= TRANSFER;
                    frame_size <= (tot_pkt_size > MAX_ETH_FRAME) ? MAX_ETH_FRAME : tot_pkt_size;
                    curr_pkt_size <= tot_pkt_size;
                end
                cycles_pkt <= (cycles_per_pkt > cycles_needed) ? cycles_per_pkt : cycles_needed;
                rx_valid <= 0;
                rx_last <= 0;
                pkt_count <= 0;
                tcredit_used <= 0;
                credit_used_perpkt <= 0;
                counter_wait <= 0;
                counter_trans <= 0;
                is_header <= 1'b1;
            end
            TRANSFER: begin
                if (rx_ready) begin 
                    counter_wait <= counter_wait + 1;
                    is_header <= 1'b0;
                    rx_valid <= 1'b1;
                    if (counter_trans >= (frame_size - BYTES_PER_BEAT) && lst_credit_pkt) begin 
                        rx_last <= 1'b1;
                        tcredit_used <= tcredit_used + 1;
                        curr_state <= WAIT;
                    end else if (counter_trans >= (frame_size - BYTES_PER_BEAT)) begin 
                        curr_state <= WAIT_FRAME;
                        counter_trans <= 0;
                        curr_pkt_size <= curr_pkt_size - frame_size;
                        tcredit_used <= tcredit_used + 1;
                        credit_used_perpkt <= credit_used_perpkt + 1;
                    end else begin 
                        counter_trans <= counter_trans + BYTES_PER_BEAT;
                    end
                end
            end
            WAIT_FRAME: begin 
                frame_size <= (curr_pkt_size > MAX_ETH_FRAME) ? MAX_ETH_FRAME : curr_pkt_size;
                counter_wait <= counter_wait + 1;
                if (rx_ready & (tcredit_used < credit_in_sync)) begin 
                    is_header <= 1'b1;
                    rx_valid <= 1'b0;
                    curr_state <= TRANSFER;
                end
                else if (tcredit_used == credit_needed) begin 
                    curr_state <= IDLE;
                    rx_valid <= 1'b0;
                    rx_last <= 1'b0;
                end else begin 
                    rx_valid <= 1'b0;
                end
            end
            WAIT: begin 
                if (rx_ready) begin
                    credit_used_perpkt <= 0;
                    rx_valid <= 1'b0;
                    rx_last <= 1'b0;
                    is_header <= 1'b1;
                    counter_trans <= 16'h0;
                    if ((pkt_count == num_pkt-1) && (counter_wait == cycles_pkt-1) ) begin 
                        curr_state <= IDLE;
                        pkt_count <= pkt_count + 1;
                        counter_wait <= 0;
                    end else if ((credit_in_sync > tcredit_used) && (counter_wait == cycles_pkt-1)) begin 
                        pkt_count <= pkt_count + 1;
                        curr_state <= TRANSFER;
                        frame_size <= (tot_pkt_size > MAX_ETH_FRAME) ? MAX_ETH_FRAME : tot_pkt_size;
                        curr_pkt_size <= tot_pkt_size;
                        counter_wait <= 0;
                    end else begin 
                        counter_wait <= counter_wait + 1;
                    end
                end
            end
        endcase
    end
end

endmodule