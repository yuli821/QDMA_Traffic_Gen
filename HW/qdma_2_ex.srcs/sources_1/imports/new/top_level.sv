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
    input  logic        clk,
    input  logic        rst,

    // H2C (QDMA -> TCP)
    input  logic [511:0] m_axis_h2c_tdata,
    input  logic [31:0]  m_axis_h2c_tcrc,
    input  logic [10:0]  m_axis_h2c_tuser_qid,
    input  logic [2:0]   m_axis_h2c_tuser_port_id,
    input  logic         m_axis_h2c_tuser_err,
    input  logic [31:0]  m_axis_h2c_tuser_mdata,
    input  logic [5:0]   m_axis_h2c_tuser_mty,
    input  logic         m_axis_h2c_tuser_zero_byte,
    input  logic         m_axis_h2c_tvalid,
    input  logic         m_axis_h2c_tlast,
    output logic         m_axis_h2c_tready,

    // C2H (TCP -> QDMA)
    output logic [511:0] s_axis_c2h_tdata,
    output logic [31:0]  s_axis_c2h_tcrc,
    output logic [15:0]  s_axis_c2h_ctrl_len,
    output logic [10:0]  s_axis_c2h_ctrl_qid,
    output logic         s_axis_c2h_ctrl_has_cmpt,
    output logic [2:0]   s_axis_c2h_ctrl_port_id,
    output logic         s_axis_c2h_ctrl_marker,
    output logic [6:0]   s_axis_c2h_ctrl_ecc,
    output logic [5:0]   s_axis_c2h_mty,
    output logic         s_axis_c2h_tvalid,
    output logic         s_axis_c2h_tlast,
    input  logic         s_axis_c2h_tready
);

localparam int HEADER_WIDTH = $bits(header_t);
localparam int HEADER_PAD   = 512 - HEADER_WIDTH;

l2_hdr_t    rx_l2_hdr;
ipv4_hdr_t  rx_ipv4_hdr;
tcp_hdr_t   rx_tcp_hdr;
tcp_csr_t   rx_tcp_csr;

logic           header_fifo_we;
header_t        header_in;
header_t        header_out;
logic [511:0]   header_fifo_in;
logic [511:0]   header_fifo_out;
logic           header_fifo_full;
logic           empty;

logic           tcb_valid;
logic [5:0]     tcb_addr_rx;

logic [127:0]   cache_input_tuple;
logic           read_miss;

logic           invalidate;
logic           tcb_b_valid_o;
tcb_t           tcb_b_out;

logic           tcp_ctrl_valid;
logic [5:0]     tcp_ctrl_addr;

logic           cancel_rto;

logic           tcb_rto_addr_out_valid;
logic [5:0]     tcb_rto_addr_out;
tcb_t           tcb_rto_out;

logic           busy;
logic           pop;

logic           m_axis_h2c_tready_i;

assign pop = !busy && !empty;

always_ff @(posedge clk) begin
    if (rst)            busy <= '0;
    else if (pop)       busy <= '1;
    else if (tcb_valid) busy <= '0;
end

rx_datapath rx_datapath_i (
    .clk                    (clk),
    .rst                    (rst),
    .m_axis_h2c_tdata       (m_axis_h2c_tdata),
    .m_axis_h2c_tcrc        (m_axis_h2c_tcrc),
    .m_axis_h2c_tuser_qid   (m_axis_h2c_tuser_qid),
    .m_axis_h2c_tuser_port_id(m_axis_h2c_tuser_port_id),
    .m_axis_h2c_tuser_err   (m_axis_h2c_tuser_err),
    .m_axis_h2c_tuser_mdata (m_axis_h2c_tuser_mdata),
    .m_axis_h2c_tuser_mty   (m_axis_h2c_tuser_mty),
    .m_axis_h2c_tuser_zero_byte(m_axis_h2c_tuser_zero_byte),
    .m_axis_h2c_tvalid      (m_axis_h2c_tvalid),
    .m_axis_h2c_tlast       (m_axis_h2c_tlast),
    .m_axis_h2c_tready      (m_axis_h2c_tready_i),
    .fifo_we                (header_fifo_we),
    .l2_hdr                 (rx_l2_hdr),
    .ipv4_hdr               (rx_ipv4_hdr),
    .tcp_hdr                (rx_tcp_hdr),
    .tcp_csr                (rx_tcp_csr)
);

tx_datapath tx_datapath_i (
    .clk                        (clk),
    .rst                        (rst),
    .sent                       (),
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

    .tcb_valid  (tcb_rto_addr_out_valid),
    .src_mac    (tcb_rto_out.dest_mac),
    .dest_mac   (tcb_rto_out.src_mac),
    .src_ip     (tcb_rto_out.dest_ip),
    .dest_ip    (tcb_rto_out.src_ip),
    .src_port   (tcb_rto_out.dest_port),
    .dest_port  (tcb_rto_out.src_port),

    .seq_num    (tcb_rto_out.snd_nxt),
    .ack_num    (tcb_rto_out.rcv_nxt),

    .tcp_csr    (tcb_rto_out.csr_curr)
);

fifo #(
    .WIDTH  (512),
    .DEPTH  (64),
    .FWFT   (1)
) header_queue_i (
    .clk        (clk),
    .srst       (rst),
    .din        (header_fifo_in),
    .wr_en      (header_fifo_we),
    .rd_en      (pop),
    .dout       (header_fifo_out),
    .full       (header_fifo_full),
    .empty      (empty),
    .valid      (),
    .overflow   (),
    .wr_rst_busy(),
    .rd_rst_busy()
);

cache cache_i (
    .clk            (clk),
    .rst            (rst),

    .read           (pop),

    .input_tuple    (cache_input_tuple),
    .rcv            (1'b1),

    .read_miss      (read_miss),
    .tcb_full       (),
    .input_addr     (),
    .tcb_addr_valid (tcb_valid),
    .tcb_addr       (tcb_addr_rx),

    .invalidate     (invalidate),
    .invalidate_addr(tcp_ctrl_addr)
);

tcb_mgr tcb_mgr_i (
    .clk                (clk),
    .rst                (rst),

    .read_miss          (read_miss),
    .header_out         (header_out),

    .tcb_valid_rx       (tcb_valid),
    .tcb_addr_rx        (tcb_addr_rx),

    .tcb_valid_tx       (tcb_rto_addr_out_valid),
    .tcb_addr_tx        (tcb_rto_addr_out),
    .tcb_in_tx          (tcb_rto_out),

    .cancel_rto         (cancel_rto),
    .invalidate         (invalidate),
    .tcp_ctrl_valid     (tcp_ctrl_valid),

    .tcp_ctrl_addr      (tcp_ctrl_addr),
    .tcb_valid_tx_out   (tcb_b_valid_o),
    .tcb_out_tx         (tcb_b_out)
);

rto rto_i (
    .clk    (clk),
    .rst    (rst),
    
    .write              (tcb_b_valid_o),
    .cancel_rto         (cancel_rto),

    .tcb_addr_in        (tcp_ctrl_addr),
    .tcb_data_in        (tcb_b_out),
    
    .tx_datapath_ready  (1'b1), // s_axis_c2h_tready),
    .tcb_addr_out_valid (tcb_rto_addr_out_valid),
    .tcb_addr_out       (tcb_rto_addr_out),
    .tcb_out            (tcb_rto_out)
);

assign cache_input_tuple = {header_out.ipv4_hdr.src_ip,
                            header_out.ipv4_hdr.dest_ip,
                            header_out.tcp_hdr.src_port,
                            header_out.tcp_hdr.dest_port};

assign header_fifo_in  = { {HEADER_PAD{1'b0}}, header_in };
assign header_out      = header_fifo_out[HEADER_WIDTH-1:0];
assign m_axis_h2c_tready = m_axis_h2c_tready_i;

always_comb begin
    header_in   = '0;

    if (header_fifo_we) begin
        header_in.l2_hdr    = rx_l2_hdr;
        header_in.ipv4_hdr  = rx_ipv4_hdr;
        header_in.tcp_hdr   = rx_tcp_hdr;
        header_in.tcp_csr   = rx_tcp_csr;
    end
end

endmodule
