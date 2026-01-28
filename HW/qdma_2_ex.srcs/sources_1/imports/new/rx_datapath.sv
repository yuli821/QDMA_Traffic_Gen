`timescale 1ns / 1ps

import packages::*;

//////////////////////////////////////////////////////////////////////////////////
// 512-bit RX datapath: extracts Ethernet/IP/TCP headers from a single 512b beat.
// Assumes the first beat of the packet contains the full headers (no GMII slicing).
//////////////////////////////////////////////////////////////////////////////////
module rx_datapath (
    input  logic         clk,
    input  logic         rst,

    // H2C (QDMA -> TCP) stream
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

    output logic         fifo_we,
    output l2_hdr_t      l2_hdr,
    output ipv4_hdr_t    ipv4_hdr,
    output tcp_hdr_t     tcp_hdr,
    output tcp_csr_t     tcp_csr
);

assign m_axis_h2c_tready = 1'b1;

// Decode headers on the cycle a beat is accepted.
always_comb begin
    fifo_we  = 1'b0;
    l2_hdr   = '0;
    ipv4_hdr = '0;
    tcp_hdr  = '0;
    tcp_csr  = '0;

    if (!rst && m_axis_h2c_tvalid && m_axis_h2c_tready) begin
        fifo_we             = 1'b1;
        l2_hdr.dest_mac     = m_axis_h2c_tdata[511:464];
        l2_hdr.src_mac      = m_axis_h2c_tdata[463:416];
        l2_hdr.ethertype    = m_axis_h2c_tdata[415:400];

        case (m_axis_h2c_tdata[415:400])
            ETH_TYPE_IPV4 : begin
                ipv4_hdr.version        = m_axis_h2c_tdata[399:396];
                ipv4_hdr.ihl            = m_axis_h2c_tdata[395:392];
                ipv4_hdr.dscp           = m_axis_h2c_tdata[391:386];
                ipv4_hdr.ecn            = m_axis_h2c_tdata[385:384];
                ipv4_hdr.total_len      = m_axis_h2c_tdata[383:368];
                ipv4_hdr.id             = m_axis_h2c_tdata[367:352];
                ipv4_hdr.flags          = m_axis_h2c_tdata[351:349];
                ipv4_hdr.frag_off       = m_axis_h2c_tdata[348:336];
                ipv4_hdr.ttl            = m_axis_h2c_tdata[335:328];
                ipv4_hdr.protocol       = m_axis_h2c_tdata[327:320];
                ipv4_hdr.hdr_checksum   = m_axis_h2c_tdata[319:304];
                ipv4_hdr.src_ip         = m_axis_h2c_tdata[303:272];
                ipv4_hdr.dest_ip        = m_axis_h2c_tdata[271:240];

                case (m_axis_h2c_tdata[327:320])
                    IP_PROTO_TCP : begin
                        tcp_hdr.src_port    = m_axis_h2c_tdata[239:224];
                        tcp_hdr.dest_port   = m_axis_h2c_tdata[223:208];
                        tcp_hdr.seq_num     = m_axis_h2c_tdata[207:176];
                        tcp_hdr.ack_num     = m_axis_h2c_tdata[175:144];
                        tcp_hdr.data_off    = m_axis_h2c_tdata[143:140];
                        tcp_hdr.resv        = m_axis_h2c_tdata[139:136];
                        tcp_hdr.csr         = m_axis_h2c_tdata[135:128];
                        tcp_hdr.window      = m_axis_h2c_tdata[127:112];
                        tcp_hdr.checksum    = m_axis_h2c_tdata[111:96];
                        tcp_hdr.urgent      = m_axis_h2c_tdata[95:80];

                        tcp_csr.syn = m_axis_h2c_tdata[129];
                        tcp_csr.ack = m_axis_h2c_tdata[132];
                        tcp_csr.rst = m_axis_h2c_tdata[130];
                        tcp_csr.fin = m_axis_h2c_tdata[128];
                    end
                endcase
            end
            16'h86DD : begin
                // IPv6 not decoded in this datapath.
            end
        endcase
    end
end

endmodule
