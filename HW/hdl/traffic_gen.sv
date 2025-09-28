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
    input logic [31:0] timestamp,
    input logic rx_ready,
    input logic [31:0] cycles_per_pkt,
    input logic [10:0] num_queue,
    input logic [10:0] qid, 
    output logic rx_valid,
    output logic [RX_LEN-1:0] rx_data, //1 byte
    output logic rx_last,
    input logic [10:0] rx_qid,
    output logic [31:0] hash_val,
    input logic c2h_perform,

    output logic rx_begin,

    input logic   tm_dsc_sts_vld,
    input logic   tm_dsc_sts_byp,
    input logic   tm_dsc_sts_qen,
    input logic   tm_dsc_sts_dir,
    input logic   tm_dsc_sts_mm,
    input logic   tm_dsc_sts_error,
    input logic [10:0]  tm_dsc_sts_qid,
    input logic [15:0]  tm_dsc_sts_avl,
    input logic   tm_dsc_sts_qinv,
    input logic	  tm_dsc_sts_irq_arm,
    output logic   tm_dsc_sts_rdy,
    input logic qid_fifo_full,
    
    input logic [31:0] cycles_per_pkt_2,
    input logic [31:0] traffic_pattern
);
localparam BYTES_PER_BEAT = RX_LEN/8;
localparam DST_MAC = 48'h665544332211;
localparam SRC_MAC = 48'h665544332200;
localparam TEMP = BYTES_PER_BEAT * 2;
localparam TCQ = 1;

logic [15:0] tot_pkt_size, counter_trans;
logic [31:0] cycles_pkt;
// logic [47:0] DST_MAC [4];

logic is_header,updt_crdt,crdt_valid, rx_valid_d1;
logic [31:0] crc;
logic [111:0] header_eth_buf;  //14 bytes, ethernet layer header
logic [159:0] header_ip_buf;  //20 bytes, ip layer header
logic [159:0] header_trans_buf; //20 bytes, transport layer header
logic [31:0] src_ip_addr, dst_ip_addr;
logic [15:0] src_port, dst_port;
logic [7:0] prot;
logic [RX_LEN-1:0] data_buf;
logic control_reg_1_d, start_c2h, ready;
logic [31:0] cycles_needed;
int counter_wait;

//credit logic and bram
logic [10:0] rd_credit_qid, rd_credit_qid_d1;
logic [10:0] wr_credit_qid, wr_credit_qid_d1;
logic [10:0] rx_qid_d1, rx_qid_d2, rx_qid_d3, rx_qid_d4;
logic [31:0] wr_credit_in;
logic signed [31:0] rd_credit_out;
logic  wr_credit_en, wr_conflict, wr_conflict_d1;
logic [31:0] cycles_count;

assign cycles_count = (traffic_pattern == '0) ? cycles_per_pkt : cycles_per_pkt_2;

logic [TM_DSC_BITS-1:0] tm_dsc_sts_avl_d1;
logic [10:0] 		  tm_dsc_sts_qid_d1;
logic tm_update, tm_update_d1, tm_dsc_sts_qinv_d1, wr_credit_en_d1, tm_ready, qid_valid;
assign tm_ready = 1'b1;

logic [31:0] credit_reg [0:15]; // credit registers
always_ff @(posedge axi_aclk) begin 
    if (~axi_aresetn) begin 
        for (int i = 0 ; i < 16 ; i++) credit_reg[i] <= 0;
    end else begin
        if (wr_conflict) begin 
            if (tm_dsc_sts_qid_d1 == rx_qid) credit_reg[tm_dsc_sts_qid_d1] <= tm_dsc_sts_qinv_d1 ? 'h0 : credit_reg[tm_dsc_sts_qid_d1] + tm_dsc_sts_avl_d1 - 1;
            else begin 
                credit_reg[tm_dsc_sts_qid_d1] <= tm_dsc_sts_qinv_d1 ? 'h0 : credit_reg[tm_dsc_sts_qid_d1] + tm_dsc_sts_avl_d1;
                credit_reg[rx_qid] <= credit_reg[rx_qid] - 1;
            end
        end
        else if (tm_update_d1) begin 
            credit_reg[tm_dsc_sts_qid_d1] <= tm_dsc_sts_qinv_d1 ? 'h0 : credit_reg[tm_dsc_sts_qid_d1] + tm_dsc_sts_avl_d1;
        end
        else if (updt_crdt) begin 
            credit_reg[rx_qid] <= credit_reg[rx_qid] - 1;
        end
    end
end
always_ff @(posedge axi_aclk) begin 
    rx_qid_d1 <= rx_qid;
    rx_qid_d2 <= rx_qid_d1;
    rx_qid_d3 <= rx_qid_d2;
    rx_qid_d4 <= rx_qid_d3;
    rd_credit_qid_d1 <= rd_credit_qid;
    tm_dsc_sts_qinv_d1 <= tm_dsc_sts_qinv;
    tm_dsc_sts_qid_d1 <= tm_dsc_sts_qid;
    tm_dsc_sts_avl_d1 <= tm_dsc_sts_avl;
    wr_conflict_d1 <= wr_conflict;
    wr_credit_qid_d1 <= wr_credit_qid;
    wr_credit_en_d1 <= wr_credit_en;
    rx_valid_d1 <= rx_valid;
    tm_update_d1 <= tm_update;
end

assign tm_dsc_sts_rdy = 1'b1;
assign tm_update = tm_dsc_sts_vld & (tm_dsc_sts_qen | tm_dsc_sts_qinv ) & ~tm_dsc_sts_mm & tm_dsc_sts_dir;
assign wr_conflict = tm_update_d1 & updt_crdt;
assign rx_begin = rx_valid & ~rx_valid_d1;

xorshift_32bits dst_ip(.seed(32'h01234567), .clk(axi_aclk), .aresetn(axi_aresetn), .update(updt_crdt), .rand_out(dst_ip_addr));
xorshift_32bits src_ip(.seed(32'h89abcdef), .clk(axi_aclk), .aresetn(axi_aresetn), .update(updt_crdt), .rand_out(src_ip_addr));
xorshift_16bits src_p(.seed(16'h4e5f), .clk(axi_aclk), .aresetn(axi_aresetn), .update(updt_crdt), .rand_out(src_port));
assign dst_port = 0;
assign prot = 8'h6;
assign header_eth_buf = {DST_MAC, SRC_MAC, 16'h2121}; //omit the length, ethernet layer header
assign header_ip_buf = {72'b0, prot, 16'b0, src_ip_addr, dst_ip_addr}; //ip/link layer header
assign header_trans_buf = {src_port, dst_port, 128'b0};//transport layer header
// assign rx_qid = qid + counter_rr[10:0]%n_queue;
assign crc = 32'h0a212121;
// assign lst_credit_pkt = (credit_perpkt_in - credit_used_perpkt) == 1;
assign cycles_needed = tot_pkt_size[15:6] +| tot_pkt_size[5:0] + 1; //pkt size must > 64 bytes
// assign hash_val = header_eth_buf[69:64] ^ SRC_MAC[5:0];  //dst xor src mac
computeRSShash hash_value(.clk(axi_aclk), .src_ip(src_ip_addr), .dst_ip(dst_ip_addr), .src_port(src_port), .dst_port(dst_port), .protocol(prot), .hash(hash_val));

enum logic [2:0] {IDLE, TRANSFER, WAIT} curr_state, next_state;

//output signal
always_ff @(posedge axi_aclk) begin 
    if (~axi_aresetn) begin 
        tot_pkt_size <= 0;
    end else begin
        tot_pkt_size <= txr_size;
    end
end

//data generation logic
always_comb begin 
    data_buf = {BYTES_PER_BEAT{8'h41}};
    if (is_header) begin 
        data_buf[RX_LEN-1 : RX_LEN-112] = header_eth_buf;
        data_buf[RX_LEN-113 : RX_LEN-272] = header_ip_buf;
        data_buf[RX_LEN-273 : RX_LEN-432] = header_trans_buf;//total byte of header: 54
        data_buf[RX_LEN-433:0] = {timestamp, 16'h1234, 32'h0}; //79:0
    end
    if (signed'(counter_trans) >= signed'(tot_pkt_size - BYTES_PER_BEAT)) begin 
        data_buf[31:0] = crc;
    end 
end
assign rx_data = data_buf;
assign crdt_valid = credit_reg[rx_qid] > 0;

//next_state logic
always_comb begin 
    next_state = IDLE;
    rx_valid = 1'b0;
    rx_last = 1'b0;
    updt_crdt = 1'b0;
    case(curr_state) 
        IDLE: begin 
            if (rx_ready && (c2h_perform == 1'b1) && ~qid_fifo_full && crdt_valid) begin 
                next_state = TRANSFER;
            end else begin 
                next_state = IDLE;
            end
            rx_valid = 1'b0;
        end
        TRANSFER: begin 
            if (rx_ready && counter_trans >= (tot_pkt_size - BYTES_PER_BEAT)) begin
                next_state = WAIT;
                updt_crdt = 1'b1;
                rx_last = 1'b1;
            end else begin 
                next_state = TRANSFER;
            end
            rx_valid = 1'b1;
        end
        WAIT: begin 
            if (c2h_perform == 1'b1) begin 
                if (crdt_valid && rx_ready && ~qid_fifo_full && (counter_wait >= cycles_pkt-1)) begin //check credit
                    next_state = TRANSFER;
                end else begin 
                    next_state = WAIT;
                end
            end else begin 
                next_state = IDLE;
            end
            rx_valid = 1'b0;
        end
        endcase
end

always_ff @(posedge axi_aclk) begin 
    if (~axi_aresetn) begin 
        curr_state <= IDLE;
        counter_wait <= 0;
        counter_trans <= 0;
        is_header <= 1'b1;
        cycles_pkt <= cycles_needed;
    end else begin 
        curr_state <= next_state;
        case(curr_state)
            IDLE: begin 
                cycles_pkt <= (cycles_count > cycles_needed) ? cycles_count : cycles_needed;
                counter_wait <= 0;
                counter_trans <= 0;
                is_header <= 1'b1;
            end
            TRANSFER: begin
                if (rx_ready) begin 
                    counter_wait <= counter_wait + 1;
                    is_header <= 1'b0;
                    if (counter_trans >= (tot_pkt_size - BYTES_PER_BEAT)) begin
                        counter_trans <= 0;
                    end 
                    else begin 
                        counter_trans <= counter_trans + BYTES_PER_BEAT;
                    end
                end  
            end
            WAIT: begin 
                is_header <= 1'b1;
                counter_trans <= 16'h0;
                if (rx_ready && crdt_valid && ~qid_fifo_full && (counter_wait >= cycles_pkt-1)) begin //check credit
                    counter_wait <= 0;
                    cycles_pkt <= (cycles_count > cycles_needed) ? cycles_count : cycles_needed;
                end else begin 
                    counter_wait <= counter_wait + 1;
                end
            end
        endcase
    end
end

endmodule

module xorshift_32bits(
    input logic [31:0] seed,
    input logic clk,
    input logic aresetn,
    input logic update,
    output logic [31:0] rand_out
);  
logic [31:0] input_sd, temp, temp2, temp3;
always_ff @ (posedge clk) begin 
    if (~aresetn) rand_out <= seed;
    else if (update) rand_out <= temp3;
end
always_comb begin 
    temp = rand_out ^ (rand_out >> 7);
    temp2 = temp ^ (temp << 9);
    temp3 = temp2 ^ (temp2 >> 13);
end
endmodule

module xorshift_16bits(
    input logic [15:0] seed,
    input logic clk,
    input logic aresetn,
    input logic update,
    output logic [15:0] rand_out
);
logic [15:0] input_sd, temp, temp2, temp3;
always_ff @ (posedge clk) begin 
    if (~aresetn) rand_out <= seed;
    else if (update) rand_out <= temp3;
end
always_comb begin 
    temp = rand_out ^ (rand_out >> 7);
    temp2 = temp ^ (temp << 9);
    temp3 = temp2 ^ (temp2 >> 8);
end
endmodule

module computeRSShash (
    input logic [31:0] src_ip,
    input logic [31:0] dst_ip,
    input logic [15:0] src_port,
    input logic [15:0] dst_port,
    input logic [7:0] protocol,
    input logic clk,
    output logic [31:0] hash
);
localparam [319:0] key = 320'h6d5a56da255b0ec24167253d43a38fb0d0ca2bcbae7b30b477cb2da38030f20c6a42b73bbeac01fa; //40 bytes
logic [103:0] input_hs;
logic [31:0] temp;
always_ff @ (posedge clk) begin 
    hash <= temp;
end
assign input_hs = {src_ip, dst_ip, src_port, dst_port, protocol};
always_comb begin
    temp = 0;
    for (int i = 0 ; i < 104 ; i = i+1) begin 
        if (input_hs[i] == 1'b1) temp ^= key[288 - i+:32]; //leftmost 32 bits
    end
end
endmodule