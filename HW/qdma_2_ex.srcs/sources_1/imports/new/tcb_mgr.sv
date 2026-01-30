`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/05/2026 11:23:07 AM
// Design Name: 
// Module Name: tcb_mgr
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
module tcb_mgr(
    input logic         clk,
    input logic         rst,

    input logic         read_miss,
    input header_t      header_out,

    // RX DATAPATH
    input logic         tcb_valid_rx,
    input logic [5:0]   tcb_addr_rx,

    // RTO / TX READ PATH
    input logic         tcb_valid_tx,
    input logic [5:0]   tcb_addr_tx,
    input tcb_t         tcb_in_tx,

    output logic        cancel_rto,
    output logic        invalidate,
    output logic        tcp_ctrl_valid,

    output logic [5:0]  tcp_ctrl_addr,
    output logic        tcb_valid_tx_out,
    output tcb_t        tcb_out_tx
);

logic [63:0]    tcb_alloc;
logic [63:0]    lock;

logic [5:0]     tcp_ctrl_addr_d;
tcb_t           tcb_out_tx_d;

assign tcb_out_tx = tcb_out_tx_d;
assign tcp_ctrl_addr = tcp_ctrl_addr_d;

// always_ff @(posedge clk) begin
//     tcb_out_tx <= tcb_out_tx_d;
//     tcp_ctrl_addr <= tcp_ctrl_addr_d;
// end

header_t        header_out_d;
logic           debug_new_packet;

tcb_mgr_t       tcb_active_data;

logic           new_packet;
logic           new_packet_d;
logic           new_packet_d2;
tcb_t           new_packet_tcb;

// --------------------------------------------- WRITEBACK ports
// TCB PORTS
// Path to determine whether it was RX or TX
// Path:
//      0 - TX
//      1 - RX
logic           path;
logic           path_d;
logic           wb_valid;
logic           wb_valid_d;
logic [5:0]     wb_addr;
logic [5:0]     wb_addr_d;

// --------------------------------------------- TCB ports
logic           tcb_out_valid;
logic           tcb_a_ready;
tcb_t           tcb_a_out;
logic           tcb_a_valid;
tcb_t           tcb_b_out;

writeback wb_i (
    .clk            (clk),
    .rst            (rst),

    .tcb_alloc      (tcb_alloc),
    .tcb_ready      (tcb_a_ready),

    .tcb_valid_rx   (tcb_valid_rx),
    .tcb_addr_rx    (tcb_addr_rx),
    
    .tcb_valid_tx   (tcb_valid_tx),
    .tcb_addr_tx    (tcb_addr_tx),
    .tcb_in_tx      (tcb_in_tx),
    
    .path           (path),
    .valid          (wb_valid),
    .addr           (wb_addr)
);

tcp_ctrl tcp_ctrl_i (
    .clk        (clk),
    .rst        (rst),

    .path       (path_d),
    .valid_in   (wb_valid_d),
    .addr_in    (wb_addr_d),
    .tcb_in     (new_packet_d2 ? new_packet_tcb : tcb_b_out),

    .new_packet_d   (new_packet_d2),
    .rx_csr         (header_out_d.tcp_csr),
    .header_data    (header_out_d),

    .cancel_rto_temp    (cancel_rto),
    .invalidate_temp    (invalidate),
    .valid_out_temp     (tcp_ctrl_valid),
    .addr_out_temp      (tcp_ctrl_addr_d),
    .tcb_out_temp       (tcb_out_tx_d)
);

tcb tcb_i (
    .clk        (clk),
    .rst        (rst),

    .addra      (tcp_ctrl_addr_d),
    .wea        (tcp_ctrl_valid),
    .dina       (invalidate ? '0 : tcb_out_tx_d),
    .douta      (tcb_a_out),

    .addrb      (wb_addr),
    .doutb      (tcb_b_out)
);

// TODO: Change to after TCP_CTRL not before
assign tcb_valid_tx_out = tcp_ctrl_valid; // tcb_out_valid;

assign new_packet   = read_miss && (header_out.tcp_csr == CSR_SYN);

// --------------------------------- DELAYS / ALIGNMENT
always_ff @(posedge clk) begin
    tcb_out_valid   <= tcp_ctrl_valid;

    wb_valid_d      <= wb_valid;
    wb_addr_d       <= wb_addr;

    path_d          <= path;
    new_packet_d    <= new_packet;
    new_packet_d2   <= new_packet_d;

    header_out_d    <= header_out;
end

// always_comb begin
//     tcb_active_data = '0;

//     if (wb_valid_d) begin
//         tcb_active_data.path        = path_d;
//         tcb_active_data.tcb_addr    = tcb_addr_b_d;
//         tcb_active_data.tcb         = tcb_b_out;
//     end
// end

// TCB
always_ff @(posedge clk) begin
    if (rst) begin
        new_packet_tcb <= '0;
    end
    else if (new_packet_d) begin
        new_packet_tcb.dest_mac       <= header_out_d.l2_hdr.dest_mac;
        new_packet_tcb.src_mac        <= header_out_d.l2_hdr.src_mac;
        new_packet_tcb.dest_ip        <= header_out_d.ipv4_hdr.dest_ip;
        new_packet_tcb.src_ip         <= header_out_d.ipv4_hdr.src_ip;
        new_packet_tcb.dest_port      <= header_out_d.tcp_hdr.dest_port;
        new_packet_tcb.src_port       <= header_out_d.tcp_hdr.src_port;

        new_packet_tcb.seq_num        <= header_out_d.tcp_hdr.seq_num;
        new_packet_tcb.ack_num        <= header_out_d.tcp_hdr.ack_num;
        // TODO: Implement hashing for ISS generation
        new_packet_tcb.snd_una        <= 'd0;
        new_packet_tcb.snd_nxt        <= 'd1;
        new_packet_tcb.rcv_nxt        <= 'd0;

        new_packet_tcb.next_send_time <= '0;
        new_packet_tcb.backoff_exp    <= '0;
        new_packet_tcb.csr_curr       <= '0;
    end
end

// --------------------------------- TCB ALLOC LOGIC
always_ff @(posedge clk) begin
    if (rst) begin
        tcb_alloc <= '0;
    end
    else if (invalidate) begin
        tcb_alloc[tcp_ctrl_addr_d] <= 1'b0;
    end
    else if (tcb_valid_rx) begin
        tcb_alloc[tcb_addr_rx] <= 1'b1;
    end
end

// --------------------------------- LOCK LOGIC
always_ff @(posedge clk) begin
    if (rst) begin
        lock <= '0;
    end
    else begin
        // OBTAIN LOCK FOR READ
        if (wb_valid) begin
            lock[wb_addr] <= 1'b1;
        end

        // RELEASE LOCK FOR WRITE
        if (tcp_ctrl_valid) begin
            lock[tcp_ctrl_addr_d] <= 1'b0;
        end
    end
end

endmodule
