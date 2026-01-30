//-----------------------------------------------------------------------------
//
// (c) Copyright 2012-2012 Xilinx, Inc. All rights reserved.
//
// This file contains confidential and proprietary information
// of Xilinx, Inc. and is protected under U.S. and
// international copyright and other intellectual property
// laws.
//
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// Xilinx, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) Xilinx shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or Xilinx had been advised of the
// possibility of the same.
//
// CRITICAL APPLICATIONS
// Xilinx products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of Xilinx products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
//
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.
//
//-----------------------------------------------------------------------------
//
// Project    : The Xilinx PCI Express DMA 
// File       : user_control.sv
// Version    : 5.0
//-----------------------------------------------------------------------------
`timescale 1ps / 1ps
`include "types.svh"

module user_control 
  #(
    parameter C_DATA_WIDTH = 64,
    parameter QID_MAX = 64,
    parameter TM_DSC_BITS = 16,
    parameter NUM_FLOWS = 16,
    parameter GLOBAL_DST_IP = 32'hC0A8640A,
    parameter GLOBAL_DST_PORT = 16'h1234,
    parameter GLOBAL_PROTOCOL = 8'h6,
    parameter GLOBAL_DST_MAC = 48'h001112345678,
    parameter PF0_M_AXILITE_ADDR_MSK    =  32'h000FFFFF,
    parameter PF1_M_AXILITE_ADDR_MSK    =  32'h000FFFFF,
    parameter PF2_M_AXILITE_ADDR_MSK    =  32'h000FFFFF,
    parameter PF3_M_AXILITE_ADDR_MSK    =  32'h000FFFFF,
    parameter PF0_VF_M_AXILITE_ADDR_MSK =  32'h00000FFF,
    parameter PF1_VF_M_AXILITE_ADDR_MSK =  32'h00000FFF,
    parameter PF2_VF_M_AXILITE_ADDR_MSK =  32'h00000FFF,
    parameter PF3_VF_M_AXILITE_ADDR_MSK =  32'h00000FFF,
    parameter PF0_PCIEBAR2AXIBAR        =  32'h00000000,
    parameter PF1_PCIEBAR2AXIBAR        =  32'h10000000,
    parameter PF2_PCIEBAR2AXIBAR        =  32'h20000000,
    parameter PF3_PCIEBAR2AXIBAR        =  32'h30000000,
    parameter PF0_VF_PCIEBAR2AXIBAR     =  32'h40000000,
    parameter PF1_VF_PCIEBAR2AXIBAR     =  32'h50000000,
    parameter PF2_VF_PCIEBAR2AXIBAR     =  32'h60000000,
    parameter PF3_VF_PCIEBAR2AXIBAR     =  32'h70000000

    )
   (
    input axi_aclk,
    input axi_aresetn,
    input m_axil_wvalid,
    input m_axil_wready,
    input m_axil_rvalid,
    input m_axil_rready,
    input [31:0] m_axil_awaddr,
    input [31:0] m_axil_wdata,
    output logic [31:0] m_axil_rdata,
    input [31:0] m_axil_rdata_bram,
    input [31:0] m_axil_araddr,
    input        m_axil_arvalid,
    output  soft_reset_n,
    output  st_loopback,
    input axi_mm_h2c_valid,
    input axi_mm_h2c_ready,
    input axi_mm_c2h_valid,
    input axi_mm_c2h_ready,
    input axi_st_h2c_valid,
    input axi_st_h2c_ready,
    input axi_st_c2h_valid,
    input axi_st_c2h_ready,
   //  input [10:0] c2h_qid,
    output reg [31:0] c2h_control,
    output reg [10:0] c2h_st_qid,
    output clr_h2c_match,
    output reg [15:0] c2h_st_len,
    input h2c_match,
    input h2c_crc_match,
    input [10:0] h2c_qid,
    input [31:0] h2c_count,
    input h2c_zero_byte,
    input c2h_st_marker_rsp,
    output reg [31:0] cmpt_size,
    output reg [255:0] wb_dat,
    output wire [15:0] buf_count,
    output wire h2c_dsc_bypass,
    output wire [1:0] c2h_dsc_bypass,
    input usr_irq_out_fail,
    input usr_irq_out_ack,
    output [10:0] usr_irq_in_vec,
    output [7:0] usr_irq_in_fnc,
    output reg usr_irq_in_vld,
    output st_rx_msg_rdy,
    input st_rx_msg_valid,
    input st_rx_msg_last,
    input [31:0] st_rx_msg_data,
    input         axis_c2h_drop,
    input         axis_c2h_drop_valid,
    input   [7:0] usr_flr_fnc,
    input         usr_flr_set,
    input         usr_flr_clr,
    output  reg [7:0] usr_flr_done_fnc,
    output        usr_flr_done_vld,
    output        c2h_mm_marker_req,
    input         c2h_mm_marker_rsp,
    output        h2c_mm_marker_req,
    input         h2c_mm_marker_rsp,
    output        h2c_st_marker_req,
    input         h2c_st_marker_rsp,
    output [1:0]  h2c_mm_at,
    output [1:0]  h2c_st_at,
    output [1:0]  c2h_mm_at,
    output [1:0]  c2h_st_at,
    output [6:0]  pfch_byp_tag,
    output [10:0] pfch_byp_tag_qid,
    output reg [31:0]  single_bit_err_inject_reg,
    output reg [31:0]  double_bit_err_inject_reg,

   //  output reg [31:0] cycles_per_pkt,
    output reg [31:0] traffic_pattern,
    output reg [31:0] src_ip,
    output reg [31:0] dst_ip,
    output reg [15:0] src_port,
    output reg [15:0] dst_port,
    output reg [7:0] protocol,

    output [10:0] c2h_qid,
    input [31:0] hash_val,
    output reg c2h_perform,
    output [31:0] read_addr,
    input [31:0] rd_output,
    output reg [10:0] c2h_num_queue,
    output flow_config_t flow_config [0:NUM_FLOWS-1],
    output logic [NUM_FLOWS-1:0] flow_running
    );

   reg [31:0] 	       control_reg_h2c;
   reg [31:0] 	       control_reg_c2h;
   reg [31:0] 	       scratch_reg1, scratch_reg2;
   reg [4:0] 	       perf_ctl;
   reg 		       control_h2c_clr;
   reg 		       start_c2h_d1;
   reg 		       start_imm_d1;
   wire 	       start_imm;
   wire 	       perf_stop;
   wire 	       perf_clear;

   reg 		       start_counter;
   wire 	       start_c2h_pls;
   wire 	       start_c2h;
   wire         end_c2h;
   reg          end_c2h_d1;
   wire         end_c2h_pls;
   reg [63:0] 	       data_count;
   reg [63:0] 	       valid_count;
   reg [15:0] 	       c2h_st_buffsz;

   reg 	     tm_vld_out;
   reg 	     tm_vld_out_d1;
   reg 	     tm_vld_out_d2;
   reg [31:0] axis_pkt_drop;
   reg [31:0] axis_pkt_accept;
   reg [5:0] dsc_bypass;
   reg [19:0] usr_irq;
   reg        usr_irq_d;
   reg [31:0] usr_irq_msk;
   reg [31:0] usr_irq_num;
   wire usr_irq_tmp;
   reg [2:0] usr_irq_clr;
   reg gen_qdma_reset;
   //wire soft_reset_n;
   reg [15:0] qdma_reset_count;
   localparam [15:0] QDMA_RESET_CYCLE_COUNT = 16'h0064;

   reg       invalid_axilm_addr;
   reg 	     clr_reset;
   reg [31:0] vdm_msg_rd_dout;
   reg h2c_zero_byte_reg;
   wire reg_x10_read;
   reg [31:0] pfch_byp_tag_reg;
   wire [3:0] hash_idx;
   assign hash_idx = hash_val[3:0];
   // reg [31:0] c2h_num_queue;
   reg [31:0] rss_indir_table [0:15];
   wire [31:0] qdma_net_mac_hi;
   wire [31:0] qdma_net_mac_lo;
   wire [31:0] link_status_reg;
   reg [NUM_FLOWS-1:0] flow_running_reg;
   flow_config_t flow_config_reg [0:NUM_FLOWS-1];
   assign c2h_qid = rss_indir_table[hash_idx];
   assign qdma_net_mac_lo[31:0] = 32'h12345678; //8E8
   assign qdma_net_mac_hi[31:0] = 32'h00000011; //8EC
   assign link_status_reg = 32'h00000001; //8F0
   assign flow_running = flow_running_reg;
   assign flow_config = flow_config_reg;
   // Interpreting request on the axilite master interface
   wire [31:0] wr_addr;
   wire [31:0] rd_addr;
   assign read_addr = rd_addr;
   assign wr_addr = ((m_axil_awaddr >= PF0_PCIEBAR2AXIBAR) && (m_axil_awaddr < PF1_PCIEBAR2AXIBAR)) ? (m_axil_awaddr & PF0_M_AXILITE_ADDR_MSK) :
                    ((m_axil_awaddr >= PF1_PCIEBAR2AXIBAR) && (m_axil_awaddr < PF2_PCIEBAR2AXIBAR)) ? (m_axil_awaddr & PF1_M_AXILITE_ADDR_MSK) :
                    ((m_axil_awaddr >= PF2_PCIEBAR2AXIBAR) && (m_axil_awaddr < PF3_PCIEBAR2AXIBAR)) ? (m_axil_awaddr & PF2_M_AXILITE_ADDR_MSK) :
                    ((m_axil_awaddr >= PF3_PCIEBAR2AXIBAR) && (m_axil_awaddr < PF0_VF_PCIEBAR2AXIBAR)) ? (m_axil_awaddr & PF3_M_AXILITE_ADDR_MSK) :
                    ((m_axil_awaddr >= PF0_VF_PCIEBAR2AXIBAR) && (m_axil_awaddr < PF1_VF_PCIEBAR2AXIBAR)) ? (m_axil_awaddr & PF0_VF_M_AXILITE_ADDR_MSK) :
                    ((m_axil_awaddr >= PF1_VF_PCIEBAR2AXIBAR) && (m_axil_awaddr < PF2_VF_PCIEBAR2AXIBAR)) ? (m_axil_awaddr & PF1_VF_M_AXILITE_ADDR_MSK) :
                    ((m_axil_awaddr >= PF2_VF_PCIEBAR2AXIBAR) && (m_axil_awaddr < PF3_VF_PCIEBAR2AXIBAR)) ? (m_axil_awaddr & PF2_VF_M_AXILITE_ADDR_MSK) :
                     (m_axil_awaddr >= PF3_VF_PCIEBAR2AXIBAR)                                             ? (m_axil_awaddr & PF3_VF_M_AXILITE_ADDR_MSK) : 32'hFFFFFFFF;

   assign rd_addr = ((m_axil_araddr >= PF0_PCIEBAR2AXIBAR) && (m_axil_araddr < PF1_PCIEBAR2AXIBAR)) ? (m_axil_araddr & PF0_M_AXILITE_ADDR_MSK) :
                    ((m_axil_araddr >= PF1_PCIEBAR2AXIBAR) && (m_axil_araddr < PF2_PCIEBAR2AXIBAR)) ? (m_axil_araddr & PF1_M_AXILITE_ADDR_MSK) :
                    ((m_axil_araddr >= PF2_PCIEBAR2AXIBAR) && (m_axil_araddr < PF3_PCIEBAR2AXIBAR)) ? (m_axil_araddr & PF2_M_AXILITE_ADDR_MSK) :
                    ((m_axil_araddr >= PF3_PCIEBAR2AXIBAR) && (m_axil_araddr < PF0_VF_PCIEBAR2AXIBAR)) ? (m_axil_araddr & PF3_M_AXILITE_ADDR_MSK) :
                    ((m_axil_araddr >= PF0_VF_PCIEBAR2AXIBAR) && (m_axil_araddr < PF1_VF_PCIEBAR2AXIBAR)) ? (m_axil_araddr & PF0_VF_M_AXILITE_ADDR_MSK) :
                    ((m_axil_araddr >= PF1_VF_PCIEBAR2AXIBAR) && (m_axil_araddr < PF2_VF_PCIEBAR2AXIBAR)) ? (m_axil_araddr & PF1_VF_M_AXILITE_ADDR_MSK) :
                    ((m_axil_araddr >= PF2_VF_PCIEBAR2AXIBAR) && (m_axil_araddr < PF3_VF_PCIEBAR2AXIBAR)) ? (m_axil_araddr & PF2_VF_M_AXILITE_ADDR_MSK) :
                     (m_axil_araddr >= PF3_VF_PCIEBAR2AXIBAR)                                             ? (m_axil_araddr & PF3_VF_M_AXILITE_ADDR_MSK) : 32'hFFFFFFFF;
   
   logic [31:0] computed_hash [0:NUM_FLOWS-1];
   always_comb begin 
      for (int i = 0 ; i < NUM_FLOWS ; i = i+1) begin 
         computed_hash[i] = computeRSShash(
            flow_config_reg[i].src_ip,
            GLOBAL_DST_IP,
            flow_config_reg[i].src_port,
            GLOBAL_DST_PORT,
            GLOBAL_PROTOCOL
         );
      end
   end
   // Register Write
   //
   // To Control AXI-Stream pattern generator and checker
   //
   // address 0x0000 : Qid 
   // address 0x0004 : C2H transfer length
   // address 0x0008 : C2H Control
   //                  [0] Streaming loop back  // not supported now
   //                  [1] start C2H
   //                  [2] Immediate data
   //                  [3] Disable C2H completion transfer to Host
   //                  [4] Reserved 
   //                  [5] Marker 
   // address 0x00C0 : H2C Control
   //                  [0] clear match for H2C transfer
   //                  [5:4]   : H2C mm at 
   //                  [7:6]   : H2C st at 
   //                  [9:8]   : C2H mm at 
   //                  [11:10] : C2H st at 
   // address 0x0010 : H2C Qid, 3'b0, h2c transfer match // Read only
   // address 0x0014 : H2C tranfer count // Read only
   // address 0x0020 : C2H number of packets to transfer
   // address 0x0024 : C2H Simple bypass prefetch tag and QID for which it got the tag
   // address 0x0030 : C2H Write back data [31:0]
   // address 0x0034 : C2H Write back data [63:32]
   // address 0x0038 : C2H Write back data [95:64]
   // address 0x003C : C2H Write back data [127:96]
   // address 0x0040 : C2H Write back data [159:128]
   // address 0x0044 : C2H Write back data [191:160]
   // address 0x0048 : C2H Write back data [223:192]
   // address 0x004C : C2H Write back data [255:224]
   // address 0x0050 : C2H Write back type [31:0]
   //                  [1:0]  Completion size
   //		       [2]    completion marker
   //		       [3]    Completion User trigger
   // 		       [6:4]  Color bit indx
   // 		       [10:8] Error bit indx
   //		       [13:12] Completion type
   // address 0x0054 : C2H Completion packet count [31:0]
   // address 0x0060 : Scratch pad reg0 
   // address 0x0064 : Scratch pad reg1
   // address 0x0068 : single bit error inject register
   // address 0x006C : double bit error inject register
   // address 0x0070 : Performance control
   //                  [0] start
   //                  [1] end
   //                  [2] clear
   //                  [4:3] : 00 AXI-MM H2C, 01 AXI-MM C2H
   //                        : 10 AXI-ST H2C, 11 AXI-ST C2H
   // address 0x0074 : Performance data count [31:0]
   // address 0x0078 : Performance data count [63:30]
   // address 0x007C : Performance valid count [31:0]
   // address 0x0080 : Performance valid count [63:30]
   // address 0x0084 : C2H Streaming Buffer size, default 4K
   // address 0x0088 : C2H Streaming packet drop count
   // address 0x008C : C2H Streaming packet accepted 
   // address 0x0090 : DSC bypass loopback [0] H2C dsc loopback [1] C2H dsc loopback 
   // address 0x0094 : user interrupt reg 
   // address 0x0098 : Multiple user interrupt Mask reg 
   // address 0x009C : Multiple user interrupt reg 
   // address 0x00A0 : DMA Control
   // address 0x00A4 : VMD messge read
   // reg c2h_perform;
   
   always @(posedge axi_aclk) begin
      if (!axi_aresetn) begin
         c2h_st_qid <= 1;
         c2h_st_len <= 16'h80;  // default transfer size set to 128Bytes
         control_reg_h2c <= 32'h0;
         control_reg_c2h <= 32'h0;
         // cycles_per_pkt <= 32'h0;
         wb_dat[255:0] <= 0;
         cmpt_size[31:0] <= 0;
         // perf_ctl <= 0;
         scratch_reg1 <=0;
         scratch_reg2 <=0;
         pfch_byp_tag_reg <= 0;
         c2h_st_buffsz<=16'h1000;  // default buff size 4K
         dsc_bypass <= 6'h0;
         usr_irq <= 'h0;
         usr_irq_msk <= 'h0;
         usr_irq_num <= 'h0;
         invalid_axilm_addr <= 'h0;
         gen_qdma_reset <= 1'b0;
         single_bit_err_inject_reg <= 32'h0;
         double_bit_err_inject_reg <= 32'h0;
         c2h_num_queue <= 32'b1;
         traffic_pattern <= '0;
         for (int i = 0 ; i < 16 ; i= i+1) 
            rss_indir_table[i] <= 0;
         for (int i = 0 ; i < NUM_FLOWS ; i = i+1) begin 
            flow_config_reg[i].pkt_size <= 16'd128;
            flow_config_reg[i].cycles_per_pkt <= 32'd100;
            flow_config_reg[i].traffic_pattern <= 32'd0;
            flow_config_reg[i].src_ip <= 32'd0;
            flow_config_reg[i].src_port <= 16'd0;
            flow_config_reg[i].src_mac <= 48'd0;
            flow_config_reg[i].hash_val <= 32'd0;
         end
      end
      else if (m_axil_wvalid && m_axil_wready ) begin
         if (wr_addr >= 32'hA8 && wr_addr <= 32'hE4) begin
            rss_indir_table[(wr_addr - 32'hA8) >> 2] <= m_axil_wdata; //(wr_addr - A4)/4 is the index, program the indirection table
         end else if (wr_addr >= 32'h210 && wr_addr < 32'h210 + NUM_FLOWS * 32'h20) begin
            automatic int flow_idx = (wr_addr - 32'h210) >> 5; 
            automatic int reg_offset = (wr_addr - 32'h210) & 5'h1F;

            case (reg_offset) 
               5'h00: flow_config_reg[flow_idx].pkt_size[15:0] <= m_axil_wdata[15:0];
               5'h04: flow_config_reg[flow_idx].cycles_per_pkt[31:0] <= m_axil_wdata[31:0] - 1;
               5'h08: flow_config_reg[flow_idx].traffic_pattern[31:0] <= m_axil_wdata[31:0];
               5'h0C: flow_config_reg[flow_idx].src_ip[31:0] <= m_axil_wdata[31:0];
               5'h10: flow_config_reg[flow_idx].src_port[15:0] <= m_axil_wdata[15:0];
               5'h14: flow_config_reg[flow_idx].src_mac[31:0] <= m_axil_wdata;
               5'h18: flow_config_reg[flow_idx].src_mac[47:32] <= m_axil_wdata[15:0];
            endcase 
            // flow_config_reg[flow_idx].hash_val <= computed_hash[flow_idx];
         end 
         else begin
            for (int i = 0 ; i < NUM_FLOWS ; i = i+1) begin 
               flow_config_reg[i].hash_val <= computed_hash[i];
            end
            case (wr_addr)
               32'h00 : c2h_st_qid     <= m_axil_wdata[10:0]; //user-defined, base qid
               32'h04 : c2h_st_len     <= m_axil_wdata[15:0]; //user-defined
               32'h08 : control_reg_c2h<= m_axil_wdata[31:0]; //user-defined
               32'h0C : control_reg_h2c<= m_axil_wdata[31:0];
               // 32'h1C : cycles_per_pkt<= m_axil_wdata[31:0]; //user-defined
               32'h20 : traffic_pattern  <= m_axil_wdata[31:0];
               32'h24 : pfch_byp_tag_reg   <= m_axil_wdata[31:0];
               32'h28 : c2h_num_queue <= m_axil_wdata[10:0]; //user-defined, number of queues
               32'h30 : wb_dat[31:0]   <= m_axil_wdata[31:0];
               32'h34 : wb_dat[63:32]  <= m_axil_wdata[31:0];
               32'h38 : wb_dat[95:64]  <= m_axil_wdata[31:0];
               32'h3C : wb_dat[127:96] <= m_axil_wdata[31:0];
               32'h40 : wb_dat[159:128]<= m_axil_wdata[31:0];
               32'h44 : wb_dat[191:160]<= m_axil_wdata[31:0];
               32'h48 : wb_dat[223:192]<= m_axil_wdata[31:0];
               32'h4C : wb_dat[255:224]<= m_axil_wdata[31:0];
               32'h50 : cmpt_size[31:0]  <= m_axil_wdata[31:0];
               32'h60 : scratch_reg1[31:0]  <= m_axil_wdata[31:0];
               32'h64 : scratch_reg2[31:0]  <= m_axil_wdata[31:0];
               32'h68 : single_bit_err_inject_reg[31:0] <= m_axil_wdata[31:0];
               32'h6C : double_bit_err_inject_reg[31:0] <= m_axil_wdata[31:0];
               //32'h70 : perf_ctl[4:0]  <= m_axil_wdata[4:0];
               32'h84 : c2h_st_buffsz  <= m_axil_wdata[15:0];
               32'h90 : dsc_bypass[5:0]    <= m_axil_wdata[5:0];
               32'h94 : usr_irq[19:0] <= m_axil_wdata[19:0];
               32'h98 : usr_irq_msk[31:0] <= m_axil_wdata[31:0];
               32'h9C : usr_irq_num[31:0] <= m_axil_wdata[31:0];
               32'hA0 : gen_qdma_reset <= m_axil_wdata[0]; //Write 1 to reset, self clearing register
               32'h200: flow_running_reg <= m_axil_wdata[NUM_FLOWS-1:0];
               // 32'h8E8: qdma_net_mac_lo[31:0] <= 32'h12345678;
               // 32'h8EC: qdma_net_mac_hi[31:0] <= 32'h00000011;
               // 32'h8F0: link_status_reg <= 32'h00000001;
               // 32'h8F4:;
               // 32'h8F8:;
               // 32'h900:;

               // 32'h00 : c2h_st_qid     <= m_axil_wdata[10:0]; //base qid
               // 32'h04 : c2h_num_queue <= m_axil_wdata[10:0]; //number of queues
               // 32'h08 : control_reg_c2h<= m_axil_wdata[31:0];
               // 32'h0C : control_reg_h2c<= m_axil_wdata[31:0];
               // 32'h10 : pfch_byp_tag_reg   <= m_axil_wdata[31:0];
               // 32'h14 : pfch_byp_tag_reg   <= m_axil_wdata[31:0];
               // 32'h18 : pfch_byp_tag_reg   <= m_axil_wdata[31:0];
               // 32'h1C : wb_dat[31:0]   <= m_axil_wdata[31:0];
               // 32'h20 : wb_dat[63:32]  <= m_axil_wdata[31:0];
               // 32'h24 : wb_dat[95:64]  <= m_axil_wdata[31:0];
               // 32'h28 : wb_dat[127:96] <= m_axil_wdata[31:0];
               // 32'h2C : wb_dat[159:128]<= m_axil_wdata[31:0];
               // 32'h30 : wb_dat[191:160]<= m_axil_wdata[31:0];
               // 32'h34 : wb_dat[223:192]<= m_axil_wdata[31:0];
               // 32'h38 : wb_dat[255:224]<= m_axil_wdata[31:0];
               // 32'h3C : cmpt_size[31:0]  <= m_axil_wdata[31:0];
               // 32'h40 : c2h_st_len     <= m_axil_wdata[15:0]; //flow0
               // 32'h44 : cycles_per_pkt<= m_axil_wdata[31:0];
               // 32'h48 : traffic_pattern  <= m_axil_wdata[31:0];
               // 32'h4C : src_ip <= m_axil_wdata[31:0];
               // 32'h50 : dst_ip <= m_axil_wdata[31:0];
               // 32'h54 : src_port <= m_axil_wdata[15:0];
               // 32'h58 : dst_port <= m_axil_wdata[15:0];
               // 32'h5C : protocol <= m_axil_wdata[7:0];
               32'hFFFFFFFF: invalid_axilm_addr <= 1'b1;
            endcase // case (m_axil_awaddr[15:0])
         end
      end // if (m_axil_wvalid && m_axil_wready )
      else begin
         control_reg_c2h <= {control_reg_c2h[31:7], end_c2h_pls, control_reg_c2h[5:3], start_imm,start_c2h_pls,control_reg_c2h[0]};
         control_reg_h2c <= {control_reg_h2c[31:1],clr_h2c_match};
         // perf_ctl[4:0] <= {perf_ctl[4:3],perf_clear,perf_stop, (perf_ctl[0]& ~perf_stop)};
         usr_irq[16:0] <= {usr_irq[16:1],usr_irq_in_vld};
         gen_qdma_reset <= ~clr_reset & gen_qdma_reset;
         usr_irq_num <= usr_irq_clr[2] ? 32'h0 : usr_irq_num;
      end
   end // always @ (posedge axi_aclk)
 
   //  Descriptor bypass / Marker request
   assign h2c_mm_marker_req = dsc_bypass[3];
   assign c2h_mm_marker_req = dsc_bypass[4];
   assign h2c_st_marker_req = dsc_bypass[5];
   assign h2c_mm_at[1:0]  = control_reg_h2c[5:4];
   assign h2c_st_at[1:0]  = control_reg_h2c[7:6];
   assign c2h_mm_at[1:0]  = control_reg_h2c[9:8];
   assign c2h_st_at[1:0]  = control_reg_h2c[11:10];
   assign pfch_byp_tag[6:0]      = pfch_byp_tag_reg[6:0];
   assign pfch_byp_tag_qid[10:0] = pfch_byp_tag_reg[26:16];
   
   // Soft reset
   always @(posedge axi_aclk) begin
      if (~axi_aresetn) begin
	 qdma_reset_count <= 16'h0;
	 clr_reset <= 1'b0;
      end 
      else if (gen_qdma_reset & ~clr_reset)
	if (qdma_reset_count != QDMA_RESET_CYCLE_COUNT)
	    qdma_reset_count <= qdma_reset_count + 1;
	else begin
	   qdma_reset_count <= 'h0;
	   clr_reset <= 1'b1;
	end
      else
	clr_reset <= 1'b0;
   end
   assign soft_reset_n = ~gen_qdma_reset;
  
   // User interrupt
   logic usr_irq_gen;
   assign usr_irq_gen = usr_irq[0] ? usr_irq[0] : usr_irq_tmp;
   
   always @(posedge axi_aclk) begin
     if (~axi_aresetn) begin
          usr_irq_d <= 1'b0;
          usr_irq_in_vld <= 1'b0;
	  usr_irq_clr[2:0] <= 1'b0;
     end	      
     else begin
          usr_irq_in_vld <= (usr_irq_gen & ~usr_irq_d) ? 1'b1 : usr_irq_out_ack ? 1'b0 : usr_irq_in_vld;
	  usr_irq_d <= usr_irq_gen;
	  usr_irq_clr[2:0] <= {usr_irq_clr[1:0],(m_axil_rvalid & m_axil_rready & (rd_addr == 32'h9C))};
     end 
   end // always @ (posedge axi_aclk)
   
   assign usr_irq_tmp = |(usr_irq_msk & usr_irq_num);
   
   assign usr_irq_in_vec = {6'h0,usr_irq[8:4]};   // vector
   assign usr_irq_in_fnc = usr_irq[19:12]; // function number

   // Register Read
   assign reg_x10_read = (m_axil_rvalid & m_axil_rready & (rd_addr == 32'h10));

   //Marker response

   logic c2h_status;
   always @(posedge axi_aclk) begin
	c2h_status <= control_reg_c2h[5] & c2h_st_marker_rsp ? 1'b1 : control_reg_c2h[1] ? 1'b0 : c2h_status;
   end
   always_comb begin
   case (rd_addr)
      32'h00 : m_axil_rdata  = (32'h0 | c2h_st_qid[10:0]);
      32'h04 : m_axil_rdata  = (32'h0 | c2h_st_len);
      32'h08 : m_axil_rdata  = (32'h0 | control_reg_c2h[31:0]);
      32'h0C : m_axil_rdata  = (32'h0 | control_reg_h2c[31:0]);
      32'h10 : m_axil_rdata  = (32'h0 | {h2c_qid[10:0], h2c_crc_match, 1'b0, h2c_zero_byte_reg, h2c_match});
      32'h14 : m_axil_rdata  = h2c_count;
      32'h18 : m_axil_rdata  = {32'h0 | c2h_status};
      // 32'h1C : m_axil_rdata  = cycles_per_pkt[31:0];
      32'h20 : m_axil_rdata  = traffic_pattern;
      32'h28 : m_axil_rdata = {32'h0 | c2h_num_queue};
      32'h30 : m_axil_rdata  = wb_dat[31:0];
      32'h34 : m_axil_rdata  = wb_dat[63:32];
      32'h38 : m_axil_rdata  = wb_dat[95:64];
      32'h3C : m_axil_rdata  = wb_dat[127:96];
      32'h40 : m_axil_rdata  = wb_dat[159:128];
      32'h44 : m_axil_rdata  = wb_dat[191:160];
      32'h48 : m_axil_rdata  = wb_dat[223:192];
      32'h4C : m_axil_rdata  = wb_dat[255:224];
      32'h50 : m_axil_rdata  = cmpt_size[31:0];
      32'h60 : m_axil_rdata  = scratch_reg1[31:0];
      32'h64 : m_axil_rdata  = scratch_reg2[31:0];
      32'h68 : m_axil_rdata  = single_bit_err_inject_reg[31:0];
      32'h6C : m_axil_rdata  = double_bit_err_inject_reg[31:0];
      //32'h70 : m_axil_rdata  = {32'h0 | perf_ctl[4:0]};
      // 32'h74 : m_axil_rdata  = data_count[31:0];
      // 32'h78 : m_axil_rdata  = data_count[63:32];
      // 32'h7C : m_axil_rdata  = valid_count[31:0];
      // 32'h80 : m_axil_rdata  = valid_count[63:32];
      32'h84 : m_axil_rdata  = c2h_st_buffsz[15:0];
      32'h88 : m_axil_rdata  = {32'h0 | axis_pkt_drop[31:0]};
      32'h8C : m_axil_rdata  = {32'h0 | axis_pkt_accept[31:0]};
      32'h90 : m_axil_rdata  = {32'h0 | dsc_bypass[5:0]};
      32'h94 : m_axil_rdata  = {32'h0 | usr_irq[16:0]};
      32'h98 : m_axil_rdata  = {32'h0 | usr_irq_msk[31:0]};
      32'h9C : m_axil_rdata  = {32'h0 | usr_irq_num[31:0]};
      32'hA0 : m_axil_rdata  = {32'h0 | gen_qdma_reset};
      32'hA4 : m_axil_rdata  = {32'h0 | vdm_msg_rd_dout};
      32'h8E8: m_axil_rdata  = {32'h0 | qdma_net_mac_lo};
      32'h8EC: m_axil_rdata  = {32'h0 | qdma_net_mac_hi};
      32'h8F0: m_axil_rdata  = {32'h0 | link_status_reg};
      // 32'h8F4:;
      // 32'h8F8:;
      // 32'h900:;
      32'hFFFFFFFF: m_axil_rdata = {32'h0 | invalid_axilm_addr};
      default : begin 
         if (rd_addr >= 32'hE8 && rd_addr <= 32'h8E4) m_axil_rdata = rd_output;
         else m_axil_rdata  = m_axil_rdata_bram;
      end
      endcase // case (m_axil_araddr[31:0]...
    end // always_comb begin
   // reg perf_ctl_stp;
   // reg perf_ctl_clr;

   assign h2c_dsc_bypass = dsc_bypass[0];  // 1 : h2c dsc bypass out looped back to dsc bypass in. 0 no loopback 

   // C2h Dsc bypass options
   // 2'b00 : Normal mode
   // 2'b01 : C2H Cash bypass mode loopback
   // 2'b10 : C2H simple bypass mode loopback
   // 2'b11 : C2H bypass out to Completion loopback
   assign c2h_dsc_bypass = dsc_bypass[2:1];
   logic [31:0] c2h_control_temp;
   assign c2h_control_temp = { 25'h0, end_c2h, control_reg_c2h[5:3],start_imm,start_c2h,control_reg_c2h[0]};
   always @(posedge axi_aclk) begin
      if (!axi_aresetn) begin
	      control_h2c_clr <= 0;
	      start_c2h_d1 <= 0;
         end_c2h_d1 <= 0;
	      // perf_ctl_stp <= 0;
	      // perf_ctl_clr <= 0;
	      start_imm_d1 <= 0;
         c2h_perform <= 0;
         c2h_control <= 0;
      end
      else begin
         if (start_c2h_pls) begin 
            c2h_perform <= 1'b1;
         end
         else if (end_c2h_pls) begin 
            c2h_perform <= 1'b0;
         end
   	   control_h2c_clr <= control_reg_h2c[0];
	      start_c2h_d1 <= start_c2h;
         end_c2h_d1 <= end_c2h;
	      // perf_ctl_stp <=  perf_ctl[1];
	      // perf_ctl_clr <=  perf_ctl[2];
	      start_imm_d1 <= control_reg_c2h[2] & ~ control_reg_c2h[1];
         c2h_control <= c2h_control_temp;
      end
   end
   // assign c2h_perform = 1'b0;
   // assign start_c2h = control_reg_c2h[1] | (c2h_perform & c2h_end);
   assign start_c2h = control_reg_c2h[1];
   assign end_c2h = control_reg_c2h[6];

   assign start_imm = control_reg_c2h[2] & ~start_imm_d1;

//   assign clr_h2c_match = control_reg_h2c[0] & ~control_h2c_clr;
   assign clr_h2c_match = reg_x10_read | (control_reg_h2c[0] & ~control_h2c_clr);
   assign start_c2h_pls = (start_c2h & ~start_c2h_d1) & ~control_reg_c2h[2] & ~control_reg_c2h[5] ;  // for immediate data and Marker no credits will be used 
   assign end_c2h_pls = end_c2h & ~end_c2h_d1;
   // assign perf_stop = perf_ctl[1] & ~perf_ctl_stp;
   // assign perf_clear = perf_ctl[2] & ~perf_ctl_clr;
	 
   assign st_loopback = control_reg_c2h[0];       // Streaming loopback mode
   
   // wire perf_start = perf_ctl[0];
   // // Performance 
   // wire 	 valids;
   // wire 	 readys;
   // assign valids = axi_mm_h2c_valid | axi_mm_c2h_valid;
   // assign readys = axi_mm_h2c_ready | axi_mm_c2h_ready;

   // reg 		 valids_d1;
   // wire 	 valids_pls;
   // wire 	 vld_rdys_pls;
   
   // always @(posedge axi_aclk)
   //    if (!axi_aresetn | perf_stop) begin
	//       valids_d1 <= 1'b0;
   //    end
   //    else if (~valids_d1) begin
	//       valids_d1 <= valids;
   //    end
   
   // assign valids_pls = valids & ~valids_d1;
   // assign vld_rdys_pls = (valids & ~valids_d1) & readys;
   
   // always @(posedge axi_aclk) begin
   //    if (!axi_aresetn | perf_stop) begin
	//       start_counter <= 0;      end
   //    else if (perf_start & valids & readys)
	//       start_counter <= 1'b1;
   // end
   
   // always @(posedge axi_aclk) begin
   //    if (!axi_aresetn | perf_clear) begin
   //       data_count <= 0;
   //       valid_count <= 0;
   //    end
   //    else begin
	//    case (perf_ctl[4:3])
	//       2'b00 : begin
	//          data_count <= ((vld_rdys_pls | start_counter) && axi_mm_h2c_valid && axi_mm_h2c_ready) ? data_count+1 :data_count;
	//          valid_count <= (valids_pls | start_counter) ? valid_count + 1 : valid_count;
	//       end
	//       2'b01 : begin
   //          data_count <= ((vld_rdys_pls | start_counter) && axi_mm_c2h_valid && axi_mm_c2h_ready) ? data_count+1 :data_count;
   //          valid_count <= (valids_pls | start_counter) ? valid_count + 1 : valid_count;
	//       end
	//    endcase // case (perf_sel[1:0])
   //    end
   // end // always @ (posedge axi_aclk)

   // H2C zero byte    
   always@(posedge axi_aclk) begin
      if (!axi_aresetn) begin
         h2c_zero_byte_reg <= 'b0;
      end else begin
         h2c_zero_byte_reg <= axi_st_h2c_valid & h2c_zero_byte ? 1'b1 : reg_x10_read ? 1'b0 : h2c_zero_byte_reg;
      end
   end


   // Axi Streaming Paket drop
   always @(posedge axi_aclk) begin
      if (!axi_aresetn) begin
         axis_pkt_drop <=0;
         axis_pkt_accept <=0;
      end
      else begin
         if (start_c2h_pls) begin
            axis_pkt_drop <= 0;
            axis_pkt_accept <=0;
         end
         else if (axis_c2h_drop_valid) begin
            axis_pkt_drop   <= axis_c2h_drop ? axis_pkt_drop + 1 : axis_pkt_drop;
            axis_pkt_accept <= ~axis_c2h_drop ? axis_pkt_accept+1 : axis_pkt_accept;
         end
      end
   end

   // Checking FLR request and provide ack
   reg       usr_flr_done_vld_reg;
   reg       usr_flr_done_vld_reg_reg;
   
   always @ (posedge axi_aclk) begin
      if (!axi_aresetn) begin
         usr_flr_done_fnc <= 'h0;
         usr_flr_done_vld_reg <= 'h0;
         usr_flr_done_vld_reg_reg <= 'h0;
      end
      else begin
         usr_flr_done_vld_reg_reg <= usr_flr_done_vld_reg;
         if (usr_flr_set && ~usr_flr_clr) begin
           usr_flr_done_fnc <= usr_flr_fnc;
           usr_flr_done_vld_reg <= 1'b1;
         end
         else if (usr_flr_clr) begin
           usr_flr_done_fnc <= 'h0;
           usr_flr_done_vld_reg <= 1'b0;
         end
         else begin
           usr_flr_done_fnc <= usr_flr_done_fnc;
           usr_flr_done_vld_reg <= usr_flr_done_vld_reg;
         end
         
      end
   end

   assign usr_flr_done_vld = usr_flr_done_vld_reg && ~usr_flr_done_vld_reg_reg; // generate one-cycle pulse

  // VMD messge storage

   wire fifo_full;
   wire fifo_rd_en;
   wire [31:0] rd_dout;
   wire vdm_empty;
   assign st_rx_msg_rdy = ~fifo_full;

   assign fifo_rd_en =  m_axil_arvalid & (rd_addr == 32'hA4);

   always @(posedge axi_aclk)
   	  vdm_msg_rd_dout <= fifo_rd_en ? rd_dout : 32'b0;

   xpm_fifo_sync # 
     (
      .FIFO_MEMORY_TYPE     ("block"), //string; "auto", "block", "distributed", or "ultra";
      .ECC_MODE             ("no_ecc"), //string; "no_ecc" or "en_ecc";
      .FIFO_WRITE_DEPTH     (128), //positive integer
      .WRITE_DATA_WIDTH     (32), //positive integer
      .WR_DATA_COUNT_WIDTH  (7), //positive integer
      .PROG_FULL_THRESH     (10), //positive integer
      .FULL_RESET_VALUE     (0), //positive integer; 0 or 1
      .READ_MODE            ("fwft"), //string; "std" or "fwft";
      .FIFO_READ_LATENCY    (1), //positive integer;
      .READ_DATA_WIDTH      (32), //positive integer
      .RD_DATA_COUNT_WIDTH  (7), //positive integer
      .PROG_EMPTY_THRESH    (10), //positive integer
      .DOUT_RESET_VALUE     ("0"), //string
      .WAKEUP_TIME          (0) //positive integer; 0 or 2;
      ) xpm_fifo_vdm_msg_i 
       (
	.sleep           (1'b0),
	.rst             (~axi_aresetn),
	.wr_clk          (axi_aclk),
	.wr_en           (st_rx_msg_valid & st_rx_msg_rdy),
	.din             (st_rx_msg_data),
	.full            (fifo_full),
	.prog_full       (prog_full),
	.wr_data_count   (),
	.overflow        (overflow),
	.wr_rst_busy     (wr_rst_busy),
	.rd_en           (fifo_rd_en),
	.dout            (rd_dout),
	.empty           (vdm_empty),
	.prog_empty      (prog_empty),
	.rd_data_count   (),
	.underflow       (underflow),
	.rd_rst_busy     (rd_rst_busy),
	.injectsbiterr   (1'b0),
	.injectdbiterr   (1'b0),
	.sbiterr         (),
	.dbiterr         ()
	);
   // End of xpm_fifo_sync instance declaration


endmodule // user_control


