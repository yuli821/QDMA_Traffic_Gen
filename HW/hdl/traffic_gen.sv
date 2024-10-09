`timescale 1ps / 1ps
module traffic_gen #(
    parameter MAX_ETH_FRAME = 16'h1000, //bytes
    parameter RX_LEN = 512, //data width
    parameter RX_BEN = RX_LEN/8,
    parameter TM_DSC_BITS = 16
)
(
    input logic axi_aclk,
    input logic axi_aresetn,
    input logic [31:0] control_reg,
    input logic [15:0] txr_size,
    input logic [31:0] num_pkt,
    input logic [TM_DSC_BITS-1:0] credit_in,
    input logic credit_updt,
    input logic [TM_DSC_BITS-1:0] credit_perpkt_in,
    input logic [31:0] credit_needed,
    input logic rx_ready,
    input logic [31:0] cycles_per_pkt,
    input logic [10:0] num_queue,
    input logic [10:0] qid, 
    output logic rx_valid,
    // output logic [RX_BEN-1:0] rx_ben,
    output logic [RX_LEN-1:0] rx_data, //1 byte
    output logic rx_last,
    output logic rx_end,
    output logic [10:0] rx_qid
);
localparam [31:0] cycles_per_second = 250000000;
localparam BYTES_PER_BEAT = RX_LEN/8;
// localparam DST_MAC = 48'h665544332211;
localparam SRC_MAC = 48'h665544332211;
localparam TCQ = 1;

logic [15:0] frame_size, tot_pkt_size, counter_trans, curr_pkt_size;
logic [31:0] cycles_pkt;
logic [47:0] DST_MAC [4];

logic is_header,updt_qid;
logic [31:0] crc;
logic [111:0] header_buf;
logic [RX_LEN-1:0] data_buf;
logic control_reg_1_d, start_c2h, start_c2h_d1, start_c2h_d2, ready;
logic [31:0] tcredit_used, credit_in_sync;
// logic lst_credit_pkt;
logic [31:0] pkt_count;
logic [31:0] cycles_needed;
int counter_wait, counter_rr;

assign DST_MAC = {48'h000000000001, 48'h000000000002, 48'h000000000003, 48'h000000000004};
assign header_buf = {DST_MAC[counter_rr], SRC_MAC, 16'h2121}; //omit the length
// assign rx_qid = qid + counter_rr[10:0]%n_queue;
assign crc = 32'h0a212121;
assign rx_end = (~rx_valid) & (num_pkt == pkt_count);
// assign lst_credit_pkt = (credit_perpkt_in - credit_used_perpkt) == 1;
assign cycles_needed = tot_pkt_size[15:6] +| tot_pkt_size[5:0]; //pkt size must > 64 bytes

enum logic [1:0] {IDLE, TRANSFER, WAIT} curr_state, next_state;

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

always_comb begin 
    data_buf = {BYTES_PER_BEAT{8'h41}};
    if (is_header) begin 
        data_buf[111:0] = header_buf;
    end
    if (counter_trans >= (frame_size - BYTES_PER_BEAT)) begin 
        data_buf[RX_LEN-1 : RX_LEN-32] = crc;
    end 
end
assign rx_data = data_buf;

//next_state logic
always_comb begin 
    next_state = IDLE;
    rx_valid = 1'b0;
    rx_last = 1'b0;
    case(curr_state) 
        IDLE: begin 
            if (rx_ready & start_c2h && (tcredit_used < credit_in_sync)) begin 
                next_state = TRANSFER;
            end else begin 
                next_state = IDLE;
            end
            rx_valid = 1'b0;
        end
        TRANSFER: begin 
            if (rx_ready && counter_trans >= (frame_size - BYTES_PER_BEAT)) begin
                if (pkt_count == num_pkt-1) next_state = IDLE;
                else if (counter_wait >= cycles_pkt - 1) next_state = TRANSFER;
                else  next_state = WAIT;
                rx_last = 1'b1;
            end else begin 
                next_state = TRANSFER;
            end
            rx_valid = 1'b1;
        end
        WAIT: begin 
            if (rx_ready & (pkt_count == num_pkt) && (counter_wait >= cycles_pkt-1) ) begin 
                next_state = IDLE;
            end else if (rx_ready & (credit_in_sync > tcredit_used) && (counter_wait >= cycles_pkt-1)) begin 
                next_state = TRANSFER;
            end else begin 
                next_state = WAIT;
            end
            rx_valid = 1'b0;
        end
        endcase
end

always_ff @(posedge axi_aclk) begin 
    if (~axi_aresetn) begin 
        curr_state <= IDLE;
        // next_state <= IDLE;
        // rx_valid <= 1'b0;
        // rx_last <= 1'b0;
        pkt_count <= 0;
        // credit_used_perpkt <= 0;
        tcredit_used <= 0;
        counter_wait <= 0;
        counter_trans <= 0;
        is_header <= 1'b1;
        frame_size <= 0;
        // curr_pkt_size <= 0;
        cycles_pkt <= cycles_needed;
        counter_rr <= 0;
        rx_qid <= qid;
        updt_qid <= 1'b0;
    end else begin 
        // if (rx_ready) begin
        curr_state <= next_state;
        case(curr_state)
            IDLE: begin 
                cycles_pkt <= (cycles_per_pkt > cycles_needed) ? cycles_per_pkt : cycles_needed;
                // if (start_c2h_d1 & ~start_c2h_d2 && (tcredit_used < credit_in_sync)) begin 
                //     // curr_state <= TRANSFER;
                //     // frame_size <= (tot_pkt_size > MAX_ETH_FRAME) ? MAX_ETH_FRAME : tot_pkt_size;
                frame_size <= tot_pkt_size;
                //     // frame_size <= tot_pkt_size;
                //     curr_pkt_size <= tot_pkt_size;
                // end
                // rx_valid <= 0;
                // rx_last <= 0;
                pkt_count <= 0;
                tcredit_used <= 0;
                // credit_used_perpkt <= 0;
                counter_wait <= 0;
                counter_trans <= 0;
                is_header <= 1'b1;
                counter_rr <= 0;
                rx_qid <= qid;
            end
            TRANSFER: begin
                if (rx_ready) begin 
                    counter_wait <= counter_wait + 1;
                    is_header <= 1'b0;
                    if (counter_trans >= (frame_size - BYTES_PER_BEAT)) begin
                        // rx_last <= 1'b1;
                        counter_trans <= 0;
                        tcredit_used <= tcredit_used + 1;
                        counter_rr <= (counter_rr == 3) ? 0 : counter_rr + 1;
                        // updt_qid <= 1'b1;
                        rx_qid <= (rx_qid == qid + num_queue - 1) ? qid : rx_qid + 1;
                        pkt_count <= pkt_count + 1;
                    end 
                    else begin 
                        counter_trans <= counter_trans + BYTES_PER_BEAT;
                    end
                end 
            end
            WAIT: begin 
                if (rx_ready) begin
                    // rx_last <= 1'b0;
                    is_header <= 1'b1;
                    counter_trans <= 16'h0;
                    // if (updt_qid) begin 
                    //     rx_qid <= (rx_qid == qid + num_queue - 1) ? qid : rx_qid + 1;
                    //     updt_qid <= 1'b0;
                    // end
                    if ((pkt_count == num_pkt) && (counter_wait >= cycles_pkt-1) ) begin 
                        // pkt_count <= pkt_count + 1;
                        counter_wait <= 0;
                    end else if ((credit_in_sync > tcredit_used) && (counter_wait >= cycles_pkt-1)) begin 
                        // pkt_count <= pkt_count + 1;
                        // curr_pkt_size <= tot_pkt_size;
                        counter_wait <= 0;
                    end else if (counter_wait >= cycles_pkt+3) begin 
                        updt_qid <= 1'b1;
                        counter_wait <= cycles_pkt-1;
                    end else begin 
                        counter_wait <= counter_wait + 1;
                    end
                end
            end
        endcase
        // end
    end
end

endmodule