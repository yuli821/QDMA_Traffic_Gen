`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/21/2025 05:25:39 AM
// Design Name: 
// Module Name: tx_datapath
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
module tx_datapath(
    input logic             clk,
    input logic             rst,
    input logic             c2h_dsc_available,

    output logic            sent,

    output logic [511:0]    s_axis_c2h_tdata,
    output logic [31:0]     s_axis_c2h_tcrc,
    output logic [15:0]     s_axis_c2h_ctrl_len,
    output logic [10:0]     s_axis_c2h_ctrl_qid,
    output logic            s_axis_c2h_ctrl_has_cmpt,
    output logic            s_axis_c2h_ctrl_marker,
    output logic [2:0]      s_axis_c2h_ctrl_port_id,
    output logic [6:0]      s_axis_c2h_ctrl_ecc,
    output logic [5:0]      s_axis_c2h_mty,
    output logic            s_axis_c2h_tvalid,
    output logic            s_axis_c2h_tlast,
    input logic             s_axis_c2h_tready,

    //Added
    input logic [31:0]      local_seq_num,
    input logic [31:0]      remote_ack_num,

    //input logic             tcb_valid,
    // input logic [47:0]      src_mac,
    // input logic [47:0]      dest_mac,
    // input logic [31:0]      src_ip,
    // input logic [31:0]      dest_ip,
    // input logic [15:0]      src_port,
    // input logic [15:0]      dest_port,

    input tcp_csr_t         tcp_csr,
    input l2_hdr_t     l2_hdr,
    input ipv4_hdr_t   ipv4_hdr,
    input tcp_hdr_t    tcp_hdr
);

/*
    CHECKSUM LOGIC

    Store constant value sum as local parameter, only
    add sections that could change, e.g. IP addr

    FIXME: For now assume 20B
*/
localparam  SYN_CHECKSUM    = 'd77;
// localparam  SYNACK_CHECKSUM = 
// localparam  ACK_CHECKSUM    = 
// localparam  FIN_CHECKSUM    = 
// localparam  FINACK_CHECKSUM = 
logic [47:0]      src_mac;
logic [47:0]      dest_mac;
logic [31:0]      src_ip;
logic [31:0]      dest_ip;
logic [15:0]      src_port;
logic [15:0]      dest_port;
assign src_mac = l2_hdr.src_mac;
assign dest_mac = l2_hdr.dest_mac;
assign src_ip = ipv4_hdr.src_ip;
assign dest_ip = ipv4_hdr.dest_ip;
assign src_port = tcp_hdr.src_port;
assign dest_port = tcp_hdr.dest_port;

//Added
logic [15:0]    syn_checksum;
// TCP checksum signals
logic [15:0] tcp_checksum_out;
logic [7:0]  current_flags;
logic [3:0]  current_data_offset;
logic [15:0] current_window;

// Determine current packet parameters for checksum
always_comb begin
    current_data_offset = 4'd5;          // 20 bytes = 5 * 4
    current_window      = 16'd512;     // 64KB receive window (typical)
    
    case ({tcp_csr.syn, tcp_csr.ack, tcp_csr.rst, tcp_csr.fin})
        4'b1000: current_flags = 8'b0000_0010;  // SYN
        4'b1100: current_flags = 8'b0001_0010;  // SYN+ACK
        4'b0100: current_flags = 8'b0001_0000;  // ACK
        4'b0001: current_flags = 8'b0000_0001;  // FIN
        4'b0101: current_flags = 8'b0001_0001;  // FIN+ACK
        4'b0010: current_flags = 8'b0000_0100;  // RST
        default: current_flags = 8'b0000_0000;
    endcase
end

// Instantiate TCP checksum calculator
tcp_checksum tcp_checksum_inst (
    .src_ip         (dest_ip),           // Swapped (we're replying)
    .dest_ip        (src_ip),            // Swapped (we're replying)
    .tcp_len        (16'd20),            // TCP header only (no payload)
    .src_port       (dest_port),         // Swapped (we're replying)
    .dest_port      (src_port),          // Swapped (we're replying)
    .seq_num        (local_seq_num),
    .ack_num        (remote_ack_num),
    .data_offset    (current_data_offset),
    .flags          (current_flags),
    .window         (current_window),
    .urgent_ptr     (16'd0),
    .checksum       (tcp_checksum_out)
);
//Added
//assign sent                 = |s_axis_c2h_tdata;
assign sent                 = s_axis_c2h_tvalid && s_axis_c2h_tready;
assign s_axis_c2h_tvalid    = |s_axis_c2h_tdata;
// assign syn_checksum         = ~(SYN_CHECKSUM + ipv4_hdr.version + ipv4_hdr.dest_ip + ipv4_hdr.src_ip);
//Added
//assign syn_checksum         = ~(SYN_CHECKSUM + dest_ip + src_ip);
always_comb begin
    // Sum all 16-bit words of the IP header (checksum field = 0)
    logic [16:0] ip_sum_temp;
    logic [16:0] ip_sum_folded;
    
    ip_sum_temp = 16'h4500 + 16'd40 + 16'd0 + 16'h4000 + 16'h4006 +
                  dest_ip[31:16] + dest_ip[15:0] + src_ip[31:16] + src_ip[15:0];
    
    ip_sum_folded = ip_sum_temp[15:0] + {16'd0, ip_sum_temp[16]};
    syn_checksum = ~ip_sum_folded[15:0];
end

// FIXME: Move IP Header here? IP
//Added
assign s_axis_c2h_ctrl_len = 16'd54; // 14B Eth + 20B IP + 20B TCP = 54B

always_ff @(posedge clk) begin
    if (rst || ~(|tcp_csr)) begin
        s_axis_c2h_tdata    <= '0;
        s_axis_c2h_tlast    <= 1'b0;
    end
    //else if (|tcp_csr && tcb_valid) begin
    else if (|tcp_csr && c2h_dsc_available) begin
        //Added
        s_axis_c2h_tlast    <= 1'b1;
        
        s_axis_c2h_tdata[511:400]   <= {src_mac, dest_mac, 16'h0800};

        //Added
        //s_axis_c2h_tdata[399:396]   <= '0; // ipv4_hdr.version;
        s_axis_c2h_tdata[399:396]   <= 4'd4; // ipv4_hdr.version;

        s_axis_c2h_tdata[395:392]   <= 'd5;      // IHL - Standard Length (5, 20B IP Header)
        s_axis_c2h_tdata[391:386]   <= '0;       // DSCP - Standard (0, No Priority)
        s_axis_c2h_tdata[385:384]   <= '0;       // ECN - Standard (Best Effort)

        //Added
        //s_axis_c2h_tdata[383:368]   <= '0; // TODO: Total Length
        s_axis_c2h_tdata[383:368]   <= 16'd40; // 20B IP + 20B TCP = 40B

        s_axis_c2h_tdata[367:352]   <= '0;       // ID - 0, No Fragment for Control Packet
        s_axis_c2h_tdata[351:349]   <= 3'b010;   // -> Don't Fragment
        s_axis_c2h_tdata[348:336]   <= '0;       // -> 0 Fragment Offset
        s_axis_c2h_tdata[335:328]   <= 'd64;     // TTL
        s_axis_c2h_tdata[327:320]   <= 'h06;    // Protocol - TCP
        s_axis_c2h_tdata[319:304]   <= syn_checksum; // Checksum
        s_axis_c2h_tdata[303:272]   <= dest_ip; // Invert Source and Dest
        s_axis_c2h_tdata[271:240]   <= src_ip;  // ->

        case ({tcp_csr.syn, tcp_csr.ack, tcp_csr.rst, tcp_csr.fin})
            4'b1000 : begin  // SYN
                // TODO: Implement TCP Header
                s_axis_c2h_tdata[239:224]   <= dest_port;
                s_axis_c2h_tdata[223:208]   <= src_port;
                //Added
                // s_axis_c2h_tdata[207:176]   <= '0;// TODO:  SEQ NUM
                // s_axis_c2h_tdata[175:144]   <= '0;// TODO:  ACK NUM
                s_axis_c2h_tdata[207:176]   <= local_seq_num;// TODO:  SEQ NUM
                s_axis_c2h_tdata[175:144]   <= remote_ack_num;// TODO:  ACK NUM

                //Added
                //s_axis_c2h_tdata[143:140]   <= '0;           // Data Offset
                s_axis_c2h_tdata[143:140]   <= 4'd5;           // Data Offset

                s_axis_c2h_tdata[139:136]   <= '0;           // RESV
                s_axis_c2h_tdata[135:128]   <= 8'b0000_0010; // SYN

                //Added
                //s_axis_c2h_tdata[127:112]   <= '0;           // Window
                //s_axis_c2h_tdata[111:96]    <= '0;// TODO: Checksum
                s_axis_c2h_tdata[127:112]   <= current_window;           // Window
                s_axis_c2h_tdata[111:96]    <= tcp_checksum_out; // Checksum

                s_axis_c2h_tdata[95:80]     <= '0;           // Urgent
            end
            4'b1100 : begin  // SYN+ACK
                s_axis_c2h_tdata[239:224]   <= dest_port;
                s_axis_c2h_tdata[223:208]   <= src_port;
                //Added
                // s_axis_c2h_tdata[207:176]   <= '0;// TODO:  SEQ NUM
                // s_axis_c2h_tdata[175:144]   <= '0;// TODO:  ACK NUM
                s_axis_c2h_tdata[207:176]   <= local_seq_num;// TODO:  SEQ NUM
                s_axis_c2h_tdata[175:144]   <= remote_ack_num;// TODO:  ACK NUM

                //Added
                //s_axis_c2h_tdata[143:140]   <= '0;           // Data Offset
                s_axis_c2h_tdata[143:140]   <= 4'd5;           // Data Offset

                s_axis_c2h_tdata[139:136]   <= '0;           // RESV
                s_axis_c2h_tdata[135:128]   <= 8'b0001_0010; // SYN+ACK

                //Added
                // s_axis_c2h_tdata[127:112]   <= '0;           // Window
                // s_axis_c2h_tdata[111:96]    <= '0;//TODO: Checksum
                s_axis_c2h_tdata[127:112]   <= current_window;           // Window
                s_axis_c2h_tdata[111:96]    <= tcp_checksum_out; // Checksum
                
                s_axis_c2h_tdata[95:80]     <= '0;           // Urgent
            end
            4'b0100 : begin  // ACK
                s_axis_c2h_tdata[239:224]   <= dest_port;
                s_axis_c2h_tdata[223:208]   <= src_port;
                //Added
                // s_axis_c2h_tdata[207:176]   <= '0;// TODO:  SEQ NUM
                // s_axis_c2h_tdata[175:144]   <= '0;// TODO:  ACK NUM
                s_axis_c2h_tdata[207:176]   <= local_seq_num;// TODO:  SEQ NUM
                s_axis_c2h_tdata[175:144]   <= remote_ack_num;// TODO:  ACK NUM

                //Added
                //s_axis_c2h_tdata[143:140]   <= '0;           // Data Offset
                s_axis_c2h_tdata[143:140]   <= 4'd5;           // Data Offset

                s_axis_c2h_tdata[139:136]   <= '0;           // RESV
                s_axis_c2h_tdata[135:128]   <= 8'b0001_0000; // ACK
                
                //Added
                // s_axis_c2h_tdata[127:112]   <= '0;           // Window
                // s_axis_c2h_tdata[111:96]    <= '0;//TODO: Checksum
                s_axis_c2h_tdata[127:112]   <= current_window;           // Window
                s_axis_c2h_tdata[111:96]    <= tcp_checksum_out; // Checksum

                s_axis_c2h_tdata[95:80]     <= '0;           // Urgent
            end
            4'b0001 : begin  // FIN
                s_axis_c2h_tdata[239:224]   <= dest_port;
                s_axis_c2h_tdata[223:208]   <= src_port;
                //Added
                // s_axis_c2h_tdata[207:176]   <= 'X;// TODO:  SEQ NUM
                // s_axis_c2h_tdata[175:144]   <= 'X;// TODO:  ACK NUM
                s_axis_c2h_tdata[207:176]   <= local_seq_num;// TODO:  SEQ NUM
                s_axis_c2h_tdata[175:144]   <= remote_ack_num;// TODO:  ACK NUM

                //Added
                //s_axis_c2h_tdata[143:140]   <= '0;           // Data Offset
                s_axis_c2h_tdata[143:140]   <= 4'd5;           // Data Offset

                s_axis_c2h_tdata[139:136]   <= '0;           // RESV
                s_axis_c2h_tdata[135:128]   <= 8'b0000_0001; // FIN
                
                //Added
                // s_axis_c2h_tdata[127:112]   <= '0;           // Window
                // s_axis_c2h_tdata[111:96]    <= '0;//TODO: Checksum
                s_axis_c2h_tdata[127:112]   <= current_window;           // Window
                s_axis_c2h_tdata[111:96]    <= tcp_checksum_out; // Checksum
                
                s_axis_c2h_tdata[95:80]     <= '0;           // Urgent
            end
            4'b0101 : begin  // FIN+ACK
                s_axis_c2h_tdata[239:224]   <= dest_port;
                s_axis_c2h_tdata[223:208]   <= src_port;
                //Added
                // s_axis_c2h_tdata[207:176]   <= '0;// TODO:  SEQ NUM
                // s_axis_c2h_tdata[175:144]   <= '0;// TODO:  ACK NUM
                s_axis_c2h_tdata[207:176]   <= local_seq_num;// TODO:  SEQ NUM
                s_axis_c2h_tdata[175:144]   <= remote_ack_num;// TODO:  ACK NUM

                //Added
                //s_axis_c2h_tdata[143:140]   <= '0;           // Data Offset
                s_axis_c2h_tdata[143:140]   <= 4'd5;           // Data Offset

                s_axis_c2h_tdata[139:136]   <= '0;           // RESV
                s_axis_c2h_tdata[135:128]   <= 8'b0001_0001; // FIN+ACK
                
                //Added
                // s_axis_c2h_tdata[127:112]   <= '0;           // Window
                // s_axis_c2h_tdata[111:96]    <= '0;//TODO: Checksum
                s_axis_c2h_tdata[127:112]   <= current_window;           // Window
                s_axis_c2h_tdata[111:96]    <= tcp_checksum_out; // Checksum

                s_axis_c2h_tdata[95:80]     <= '0;           // Urgent
            end
            4'b0010 : begin  // RST
                s_axis_c2h_tdata[239:224]   <= dest_port;
                s_axis_c2h_tdata[223:208]   <= src_port;
                //Added
                // s_axis_c2h_tdata[207:176]   <= '0;// TODO:  SEQ NUM
                // s_axis_c2h_tdata[175:144]   <= '0;// TODO:  ACK NUM
                s_axis_c2h_tdata[207:176]   <= local_seq_num;// TODO:  SEQ NUM
                s_axis_c2h_tdata[175:144]   <= remote_ack_num;// TODO:  ACK NUM

                //Added
                //s_axis_c2h_tdata[143:140]   <= '0;           // Data Offset
                s_axis_c2h_tdata[143:140]   <= 4'd5;           // Data Offset
                
                s_axis_c2h_tdata[139:136]   <= '0;           // RESV
                s_axis_c2h_tdata[135:128]   <= 8'b0000_0100; // RST
                
                //Added
                // s_axis_c2h_tdata[127:112]   <= '0;           // Window
                // s_axis_c2h_tdata[111:96]    <= '0;//TODO: Checksum
                s_axis_c2h_tdata[127:112]   <= current_window;           // Window
                s_axis_c2h_tdata[111:96]    <= tcp_checksum_out; // Checksum

                s_axis_c2h_tdata[95:80]     <= '0;           // Urgent
            end
            default : begin
                s_axis_c2h_tdata[239:80]    <= '0;
            end
        endcase
    end
    else begin
        s_axis_c2h_tdata    <= '0;
        //Added
        s_axis_c2h_tlast    <= 1'b0;
    end
end
endmodule

module tcp_checksum(
    input logic [31:0] src_ip,
    input logic [31:0] dest_ip,
    input logic [15:0] tcp_len,
    input logic [15:0] src_port,
    input logic [15:0] dest_port,
    input logic [31:0] seq_num,
    input logic [31:0] ack_num,
    input logic [3:0] data_offset,
    input logic [7:0] flags,
    input logic [15:0] window,
    input logic [15:0] urgent_ptr,
    output logic [15:0] checksum
);

// TCP pseudo-header fields
logic [31:0] pseudo_sum;
logic [31:0] tcp_hdr_sum;
logic [31:0] total_sum;
logic [31:0] temp_sum;

always_comb begin
    // Pseudo-header: src_ip (32) + dest_ip (32) + zero (8) + protocol (8) + tcp_len (16)
    pseudo_sum = {16'd0, src_ip[31:16]} + 
                 {16'd0, src_ip[15:0]} + 
                 {16'd0, dest_ip[31:16]} + 
                 {16'd0, dest_ip[15:0]} + 
                 {16'd0, 8'd0, 8'd6} +      // Protocol = 6 (TCP)
                 {16'd0, tcp_len};
    
    // TCP header fields (20 bytes minimum)
    tcp_hdr_sum = {16'd0, src_port} + 
                  {16'd0, dest_port} + 
                  {16'd0, seq_num[31:16]} + 
                  {16'd0, seq_num[15:0]} + 
                  {16'd0, ack_num[31:16]} + 
                  {16'd0, ack_num[15:0]} + 
                  {16'd0, data_offset, 4'd0, flags} +  // Data offset and flags
                  {16'd0, window} + 
                  // Checksum field itself is zero during calculation
                  16'd0 + 
                  {16'd0, urgent_ptr};
    
    // Add pseudo-header and TCP header
    total_sum = pseudo_sum + tcp_hdr_sum;
    
    // Fold 32-bit sum to 16 bits (handle carries)
    temp_sum = {16'd0, total_sum[15:0]} + {16'd0, total_sum[31:16]};
    
    // If there's still a carry, fold again
    temp_sum = {16'd0, temp_sum[15:0]} + {16'd0, temp_sum[31:16]};
    
    // One's complement
    checksum = ~temp_sum[15:0];
end

endmodule
