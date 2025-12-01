`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/23/2025 08:32:33 PM
// Design Name: 
// Module Name: top_level
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

import packages::*;
module top_level(
    input logic         clk,
    input logic         rst,

    // H2C (QDMA -> TCP)
    input logic [511:0] m_axis_h2c_tdata,
    input logic [31:0]  m_axis_h2c_tcrc,
    input logic [10:0]  m_axis_h2c_tuser_qid,
    input logic [2:0]   m_axis_h2c_tuser_port_id,
    input logic         m_axis_h2c_tuser_err,
    input logic [31:0]  m_axis_h2c_tuser_mdata,
    input logic [5:0]   m_axis_h2c_tuser_mty,
    input logic         m_axis_h2c_tuser_zero_byte,
    input logic         m_axis_h2c_tvalid,
    input logic         m_axis_h2c_tlast,
    output logic        m_axis_h2c_tready,

    // C2H (TCP -> QDMA)
    output logic [511:0]s_axis_c2h_tdata,

    output logic [31:0] s_axis_c2h_tcrc,

    output logic [15:0] s_axis_c2h_ctrl_len,
    output logic [10:0] s_axis_c2h_ctrl_qid,
    output logic        s_axis_c2h_ctrl_has_cmpt,
    output logic [2:0]  s_axis_c2h_ctrl_port_id,

    output logic        s_axis_c2h_ctrl_marker,
    output logic [6:0]  s_axis_c2h_ctrl_ecc,
    output logic [5:0]  s_axis_c2h_mty,

    output logic        s_axis_c2h_tvalid,
    output logic        s_axis_c2h_tlast,
    input logic         s_axis_c2h_tready
);

l2_hdr_t    rx_l2_hdr;
ipv4_hdr_t  rx_ipv4_hdr;
tcp_hdr_t   rx_tcp_hdr;
tcp_csr_t   rx_tcp_csr;
tcp_csr_t   tx_tcp_csr;

logic           tcb_valid;
logic [5:0]     tcb_addr_rx;
logic [5:0]     tcb_addr_b;

header_t        header_in;
logic [1023:0]  header_fifo_in;
header_t        header_out;
header_t        header_out_d;
logic           header_out_change;

logic           tcp_valid_i;
logic           tcp_valid_o;
tcp_state_t     tcp_curr_in_t;
tcp_state_t     tcp_next_out_t;
tcp_csr_t       tcp_curr_csr_t;

logic [127:0]   cache_input_tuple;
logic           read_miss;

logic [5:0]     next_send_time;
logic [4:0]     backoff_exp;

logic           invalidate;
logic [63:0]    tcb_alloc;
logic           tcb_a_valid;
tcb_t           tcb_a_in;
tcb_t           tcb_a_out;
logic           tcb_b_valid;
logic           tcb_b_valid_o;
tcb_t           tcb_b_in;
tcb_t           tcb_b_out;

logic           new_packet;

rx_datapath rx_datapath_i (
    .clk                        (clk),
    .rst                        (rst),
    .m_axis_h2c_tdata           (m_axis_h2c_tdata),
    .m_axis_h2c_tcrc            (m_axis_h2c_tcrc),
    .m_axis_h2c_tuser_qid       (m_axis_h2c_tuser_qid),
    .m_axis_h2c_tuser_port_id   (m_axis_h2c_tuser_port_id),
    .m_axis_h2c_tuser_err       (m_axis_h2c_tuser_err),
    .m_axis_h2c_tuser_mdata     (m_axis_h2c_tuser_mdata),
    .m_axis_h2c_tuser_mty       (m_axis_h2c_tuser_mty),
    .m_axis_h2c_tuser_zero_byte (m_axis_h2c_tuser_zero_byte),
    .m_axis_h2c_tvalid          (m_axis_h2c_tvalid),
    .m_axis_h2c_tlast           (m_axis_h2c_tlast),
    .m_axis_h2c_tready          (m_axis_h2c_tready),

    .l2_hdr     (rx_l2_hdr),
    .ipv4_hdr   (rx_ipv4_hdr),
    .tcp_hdr    (rx_tcp_hdr),
    .tcp_csr    (rx_tcp_csr)
);

tx_datapath tx_datapath_i (
    .clk                        (clk),
    .rst                        (rst),
    .s_axis_c2h_tready          (s_axis_c2h_tready),
    .s_axis_c2h_tdata           (s_axis_c2h_tdata),
    .s_axis_c2h_tcrc            (s_axis_c2h_tcrc),
    .s_axis_c2h_ctrl_len        (s_axis_c2h_ctrl_len),
    .s_axis_c2h_ctrl_qid        (s_axis_c2h_ctrl_qid),
    .s_axis_c2h_ctrl_has_cmpt   (s_axis_c2h_ctrl_has_cmpt),
    .s_axis_c2h_ctrl_marker     (s_axis_c2h_ctrl_marker),
    .s_axis_c2h_ctrl_port_id    (s_axis_c2h_ctrl_port_id),
    .s_axis_c2h_ctrl_ecc        (s_axis_c2h_ctrl_ecc),
    .s_axis_c2h_mty             (s_axis_c2h_mty),
    .s_axis_c2h_tvalid          (s_axis_c2h_tvalid),
    .s_axis_c2h_tlast           (s_axis_c2h_tlast),

    .tcb_valid  (tcb_b_valid_o),
    .src_mac    (tcb_b_out.dest_mac),
    .dest_mac   (tcb_b_out.src_mac),
    .src_ip     (tcb_b_out.src_ip),
    .dest_ip    (tcb_b_out.dest_ip),
    .src_port   (tcb_b_out.src_port),
    .dest_port  (tcb_b_out.dest_port),
    .tcp_csr    (tcb_b_out.csr_curr)
);

fifo_generator_1 header_queue_i (
    // DIRECTION | TUPLE
    .clk        (clk),
    .srst       (rst),

    .full       (), // SEND RST
    .din        (header_fifo_in),
    .wr_en      (m_axis_h2c_tvalid),

    .empty      (),
    .dout       (header_out),
    .rd_en      (tcb_valid),

    .wr_rst_busy(),
    .rd_rst_busy()
);

// TODO: implement if order not guaranteed
/* hdr_ring_buf hdr_ring_buf_i (
    .clk        (clk),
    .rst       (rst),

    .full       (), // SEND RST
    .din        (cache_request_in),
    .wr_en      (m_axis_h2c_tvalid),

    .empty      (),
    .dout       (cache_request_out),
    .rd_en      (cache_response),

    .overflow   (), // SEND RST
    // TODO: read or write?
    .wr_rst_busy(),
    .rd_rst_busy()
);
*/

cache cache_i (
    .clk            (clk),
    .rst            (rst),
    // FIXME: Implement logic for read/write
    /*
        read    -> lookup

        write   -> allocate
                -> new + SYN packet
                -> ignore if new + SYNACK or ACK and send RST
    */
    .read           (header_out_change),
    .write          ('0),

    .input_tuple    (cache_input_tuple),
    .rcv            (1'b1), // TODO: implement logic

    .read_miss      (read_miss),
    .tcb_full       (), // TODO: Send RST
    .input_addr     (),
    .tcb_addr_valid (tcb_valid),
    .tcb_addr       (tcb_addr_rx)
);

tcb tcb_i (
    .clk        (clk),
    .rst        (rst),

    .readya     (tcb_a_ready),
    .valida     (tcp_ctrl_valid),
    .addra      (tcp_ctrl_addr),
    .wea        (tcp_ctrl_we),
    .dina       (tcp_ctrl_tcb),
    .douta      (tcb_a_out),
    .douta_valid(tcb_a_valid),

    .validb     (tcb_b_valid),
    .addrb      (tcb_addr_b),
    .web        ('0),
    .dinb       (),
    .doutb      (tcb_b_out),
    .doutb_valid(tcb_b_valid_o)
);

rto rto_i (
    .clk    (clk),
    .rst    (rst),
    
    .write              (tcp_ctrl_valid), // tcb_a_valid),
    // .high_priority  (),
    // .tcb_addr_in_valid  (wb_valid),
    .tcb_addr_in        (tcp_ctrl_addr),
    .tcb_data_in        (tcp_ctrl_tcb),
    // .tcb_addr_in_valid  (wb_valid),
    // .tcb_addr_in        (wb_addr),
    // .tcb_data_in        (wb_tcb),
    
    .tx_datapath_ready  (),
    .tcb_addr_out_valid (tcb_b_valid),
    .tcb_addr_out       (tcb_addr_b),
    .tcb_data_out       ()
);

logic       tcb_a_ready;
logic       wb_valid;
logic [5:0] wb_addr;
logic       wb_wea;
tcb_t       wb_tcb;
logic       path;

logic       tcp_ctrl_valid;
logic [5:0] tcp_ctrl_addr;
logic       tcp_ctrl_we;
tcb_t       tcp_ctrl_tcb;

logic [5:0] tcb_addr_b_d;

always_ff @(posedge clk) begin
    tcb_addr_b_d <= tcb_addr_b;
end

writeback writeback_i (
    .clk            (clk),
    .rst            (rst),

    .tcb_alloc      (tcb_alloc),
    .tcb_ready      (tcb_a_ready),

    .tcb_valid_rx   (tcb_valid),
    .tcb_addr_rx    (tcb_addr_rx),
    .tcb_in_rx      (tcb_a_in),
    
    .tcb_valid_tx   (tcb_b_valid_o),
    .tcb_addr_tx    (tcb_addr_b_d),
    .tcb_in_tx      (tcb_b_out),
    
    .path           (path),
    .valida         (wb_valid),
    .addra          (wb_addr),
    .wea            (wb_wea),
    .tcb_out        (wb_tcb)
);

tcp_ctrl tcp_ctrl_i (
    .clk        (clk),
    .rst        (rst),

    .path       (path),
    .valid_in   (wb_valid),
    .addr_in    (wb_addr),
    .we_in      (wb_wea),
    .tcb_in     (wb_tcb),
    
    .new_packet (new_packet),
    .rx_csr     (header_out.tcp_csr),

    .invalidate (invalidate),
    .valid_out  (tcp_ctrl_valid),
    .addr_out   (tcp_ctrl_addr),
    .we_out     (tcp_ctrl_we),
    .tcb_out    (tcp_ctrl_tcb)
);

assign header_out_change    = (header_out != header_out_d);

assign cache_input_tuple    = {header_out.ipv4_hdr.src_ip,
                               header_out.ipv4_hdr.dest_ip,
                               header_out.tcp_hdr.src_port,
                               header_out.tcp_hdr.dest_port};

assign header_fifo_in       = {'0, header_in};

assign new_packet           = read_miss && (header_out.tcp_csr == CSR_SYN);

always_comb begin
    header_in   = '0;

    if (m_axis_h2c_tvalid) begin
        header_in.l2_hdr    = rx_l2_hdr;
        header_in.ipv4_hdr  = rx_ipv4_hdr;
        header_in.tcp_hdr   = rx_tcp_hdr;
        header_in.tcp_csr   = rx_tcp_csr;
    end
    else begin
        header_in = '0;
    end
end

always_comb begin
    tcb_a_in = '0;

    tcb_a_in.dest_mac      = header_out_d.l2_hdr.dest_mac;
    tcb_a_in.src_mac       = header_out_d.l2_hdr.src_mac;
    tcb_a_in.dest_ip       = header_out_d.ipv4_hdr.dest_ip;
    tcb_a_in.src_ip        = header_out_d.ipv4_hdr.src_ip;
    tcb_a_in.dest_port     = header_out_d.tcp_hdr.dest_port;
    tcb_a_in.src_port      = header_out_d.tcp_hdr.src_port;
    tcb_a_in.tcp_curr_t    = tcp_curr_in_t;
    tcb_a_in.tcp_next_t    = tcp_next_out_t;
    tcb_a_in.seq_num       = header_out_d.tcp_hdr.seq_num;
    tcb_a_in.ack_num       = header_out_d.tcp_hdr.ack_num;
    tcb_a_in.next_send_time= next_send_time;
    tcb_a_in.backoff_exp   = backoff_exp;
    tcb_a_in.csr_curr      = tcp_curr_csr_t;
end

always_ff @(posedge clk) begin
    header_out_d    <= header_out;
end

always_ff @(posedge clk) begin
    if (rst) begin
        tcb_alloc <= '0;
    end
    else if (invalidate) begin
        tcb_alloc[tcp_ctrl_addr] <= 1'b0;
    end
    else if (tcb_valid) begin
        tcb_alloc[tcb_addr_rx] <= 1'b1;
    end
end

// always_ff @(posedge clk) begin
//     if (rst) begin
//         tcp_curr_in_t   <= CLOSED;
//         tcp_curr_csr_t  <= '0;
//         tcp_valid_i     <= '0;
//     end
//     else if (read_miss) begin
//         // READ MISS + SYN means it is the first time seeing this packet
//         if (header_out.tcp_csr == CSR_SYN) begin
//             tcp_curr_in_t   <= LISTEN;
//             tcp_curr_csr_t  <= header_out.tcp_csr;
//             tcp_valid_i     <= '1;
//             next_send_time  <= '0;
//             backoff_exp     <= '0;
//         end
//     end
//     else if (tcb_valid) begin
//         tcp_curr_in_t   <= tcb_a_out.tcp_curr_t;
//         tcp_curr_csr_t  <= tcb_a_out.csr_curr;
//         tcp_valid_i     <= '1;
//         next_send_time  <= '0;
//         backoff_exp     <= '0;
//     end
// end


endmodule
