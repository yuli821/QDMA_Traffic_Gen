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
    // TODO: tready
    input logic             s_axis_c2h_tready,

    input logic             tcb_valid,
    input logic [47:0]      src_mac,
    input logic [47:0]      dest_mac,
    input logic [31:0]      src_ip,
    input logic [31:0]      dest_ip,
    input logic [15:0]      src_port,
    input logic [15:0]      dest_port,

    input logic [31:0]      seq_num,
    input logic [31:0]      ack_num,

    input tcp_csr_t         tcp_csr
);

// Version(4), IHL(5), TOS(0), Len(40), ID(0), Flags(DF), TTL(64), Proto(TCP)
localparam IP_CONST_SUM  = 20'h4500 + 20'd40 + 20'h0000 + 20'h4000 + 20'h4006;
// Pseudo Header Static: Proto(TCP) + TCP_Len(20)
localparam TCP_CONST_SUM = 20'h0006 + 20'd20;

logic [19:0]    ip_sum;
logic [19:0]    tcp_sum;
logic [15:0]    ip_checksum;
logic [15:0]    tcp_checksum;

assign sent                 = |s_axis_c2h_tdata;
assign s_axis_c2h_tvalid    = |s_axis_c2h_tdata;
assign s_axis_c2h_ctrl_len  = 16'd54; // 14B Eth + 20B IP + 20B TCP = 54B

// -------------------------------------------------------------------------- IP CHECKSUM
always_comb begin
    ip_sum = IP_CONST_SUM + src_ip[31:16] + src_ip[15:0] + dest_ip[31:16] + dest_ip[15:0];
    ip_sum = ip_sum[15:0] + ip_sum[19:16];
    ip_sum = ip_sum[15:0] + ip_sum[19:16];

    ip_checksum = ~ip_sum[15:0];
end

// -------------------------------------------------------------------------- TCP_CHECKSUM
always_comb begin
    tcp_sum = TCP_CONST_SUM + 
              src_ip[31:16] + src_ip[15:0] + dest_ip[31:16] + dest_ip[15:0] +
              src_port + dest_port + 
              seq_num[31:16] + seq_num[15:0] + 
              ack_num[31:16] + ack_num[15:0] + 
              {4'd5, 4'd0, 3'b0, tcp_csr.ack, 1'b0, tcp_csr.rst, tcp_csr.syn, tcp_csr.fin};
    tcp_sum = tcp_sum[15:0] + tcp_sum[19:16];
    tcp_sum = tcp_sum[15:0] + tcp_sum[19:16];

    tcp_checksum = ~tcp_sum[15:0];
end

always_ff @(posedge clk) begin
    if (rst || ~(|tcp_csr)) begin
        s_axis_c2h_tdata    <= '0;
    end
    else if (|tcp_csr && tcb_valid) begin
        s_axis_c2h_tdata[511:400]   <= {dest_mac, src_mac, 16'h0800};

        // ------------------------------------------------------------------ IP HEADER
        s_axis_c2h_tdata[399:396]   <= 'd4;     // ipv4_hdr.version;
        s_axis_c2h_tdata[395:392]   <= 'd5;     // IHL - Standard Length (5, 20B IP Header)
        s_axis_c2h_tdata[391:386]   <= '0;      // DSCP - Standard (0, No Priority)
        s_axis_c2h_tdata[385:384]   <= '0;      // ECN - Standard (Best Effort)
        s_axis_c2h_tdata[383:368]   <= 'd40;    // IP(20B) + TCP(20B)
        s_axis_c2h_tdata[367:352]   <= '0;      // ID - 0, No Fragment for Control Packet
        s_axis_c2h_tdata[351:349]   <= 3'b010;  // -> Don't Fragment
        s_axis_c2h_tdata[348:336]   <= '0;      // -> 0 Fragment Offset
        s_axis_c2h_tdata[335:328]   <= 'd64;    // TTL
        s_axis_c2h_tdata[327:320]   <= 'h06;    // Protocol - TCP
        s_axis_c2h_tdata[319:304]   <= ip_checksum;
        s_axis_c2h_tdata[303:272]   <= src_ip;
        s_axis_c2h_tdata[271:240]   <= dest_ip;

        // ------------------------------------------------------------------ TCP HEADER
        s_axis_c2h_tdata[239:224]   <= src_port;
        s_axis_c2h_tdata[223:208]   <= dest_port;
        s_axis_c2h_tdata[207:176]   <= seq_num;
        s_axis_c2h_tdata[175:144]   <= ack_num;
        s_axis_c2h_tdata[143:140]   <= 'd5;             // Data Offset
        s_axis_c2h_tdata[139:136]   <= '0;              // RESV
        s_axis_c2h_tdata[135:128]   <= {3'b0, tcp_csr.ack, 1'b0, tcp_csr.rst, tcp_csr.syn, tcp_csr.fin};
        s_axis_c2h_tdata[127:112]   <= 16'hFFFF;              // Window
        s_axis_c2h_tdata[111:96]    <= tcp_checksum;
        s_axis_c2h_tdata[95:80]     <= '0;              // Urgent
    end
    else begin
        s_axis_c2h_tdata    <= '0;
    end
end
endmodule
