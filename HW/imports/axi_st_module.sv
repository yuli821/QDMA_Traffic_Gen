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
// File       : axi_st_module.sv
// Version    : 5.0
//-----------------------------------------------------------------------------
`timescale 1ps / 1ps
`include "types.svh"

// From pciecoredefines.h
`define XSRREG_SYNC(clk, reset_n, q,d,rstval)        \
    always @(posedge clk)                        \
    begin                                        \
     if (reset_n == 1'b0)                        \
         q <= #(TCQ) rstval;                                \
     else                                        \
         `ifdef FOURVALCLKPROP                        \
            q <= #(TCQ) clk ? d : q;                        \
          `else                                        \
            q <= #(TCQ)  d;                                \
          `endif                                \
     end

// From dma5_axi4mm_axi_bridge.vh
`define XSRREG_XDMA(clk, reset_n, q,d,rstval)        \
`XSRREG_SYNC (clk, reset_n, q,d,rstval) \

module axi_st_module
  #( 
    parameter MAX_ETH_FRAME = 16'h1000,
    parameter C_DATA_WIDTH = 256,
    parameter CRC_WIDTH    = 32,
    parameter C_H2C_TUSER_WIDTH = 128,
    parameter TM_DSC_BITS = 16,
    parameter NUM_FLOWS = 16
  )
   (
    input axi_aresetn ,
    input axi_aclk,
    
    input [10:0] c2h_st_qid,
    input [31:0] c2h_control,
    input clr_h2c_match,
    input [15:0] c2h_st_len,
    input [31:0] cmpt_size,
    input [255:0] wb_dat,
    input   [C_DATA_WIDTH-1 :0]    m_axis_h2c_tdata /* synthesis syn_keep = 1 */,
    input   [CRC_WIDTH-1 :0]       m_axis_h2c_tcrc /* synthesis syn_keep = 1 */,
    input   [10:0]                 m_axis_h2c_tuser_qid /* synthesis syn_keep = 1 */,
    input   [2:0]                  m_axis_h2c_tuser_port_id, 
    input                          m_axis_h2c_tuser_err, 
    input   [31:0]                 m_axis_h2c_tuser_mdata, 
    input   [5:0]                  m_axis_h2c_tuser_mty, 
    input                          m_axis_h2c_tuser_zero_byte, 
    input                          m_axis_h2c_tvalid /* synthesis syn_keep = 1 */,
    output                         m_axis_h2c_tready /* synthesis syn_keep = 1 */,
    input                          m_axis_h2c_tlast /* synthesis syn_keep = 1 */,

    // input [31:0]    cycles_per_pkt,
    input [10:0]    c2h_num_queue,

    input         tm_dsc_sts_vld,
    input         tm_dsc_sts_byp,
    input         tm_dsc_sts_qen,
    input         tm_dsc_sts_dir,
    input         tm_dsc_sts_mm,
    input         tm_dsc_sts_error,
    input [10:0]  tm_dsc_sts_qid,
    input [15:0]  tm_dsc_sts_avl,
    input         tm_dsc_sts_qinv,
    input 	  tm_dsc_sts_irq_arm,
    output        tm_dsc_sts_rdy,
    
    output [C_DATA_WIDTH-1 :0]     s_axis_c2h_tdata /* synthesis syn_keep = 1 */,  
    // output [C_DATA_WIDTH/8-1:0]       s_axis_c2h_dpar  /* synthesis syn_keep = 1 */, 
    output [CRC_WIDTH-1 :0]        s_axis_c2h_tcrc /* synthesis syn_keep = 1 */,  
    output                         s_axis_c2h_ctrl_marker /* synthesis syn_keep = 1 */,
    output [15:0]                  s_axis_c2h_ctrl_len /* synthesis syn_keep = 1 */,
    output [10:0]                  s_axis_c2h_ctrl_qid /* synthesis syn_keep = 1 */,
    output                         s_axis_c2h_ctrl_has_cmpt /* synthesis syn_keep = 1 */,
    output                         s_axis_c2h_tvalid /* synthesis syn_keep = 1 */,
    input                          s_axis_c2h_tready /* synthesis syn_keep = 1 */,
    output                         s_axis_c2h_tlast /* synthesis syn_keep = 1 */,
    output [5:0]                   s_axis_c2h_mty /* synthesis syn_keep = 1 */ ,
    output [511:0]                 s_axis_c2h_cmpt_tdata,
    output [1:0]                   s_axis_c2h_cmpt_size,
    output [15:0]                  s_axis_c2h_cmpt_dpar,
    output                         s_axis_c2h_cmpt_tvalid,
    output  [10:0]		   s_axis_c2h_cmpt_ctrl_qid,
    output  [1:0]		   s_axis_c2h_cmpt_ctrl_cmpt_type,
    output  [15:0]		   s_axis_c2h_cmpt_ctrl_wait_pld_pkt_id,
    output   		   	   s_axis_c2h_cmpt_ctrl_marker,
    output   		   	   s_axis_c2h_cmpt_ctrl_user_trig,
    output [2:0]                   s_axis_c2h_cmpt_ctrl_col_idx,
    output [2:0]                   s_axis_c2h_cmpt_ctrl_err_idx,
    input                          s_axis_c2h_cmpt_tready,
    input [15:0]                   buf_count,
    input 			   byp_to_cmp,
    input [511 : 0] 		   byp_data_to_cmp,
    input [1 : 0]                  c2h_dsc_bypass,
    input [10 : 0] 		   pfch_byp_tag_qid,
    output [31:0]                  h2c_count,
    output                         h2c_match,
    output logic                   h2c_crc_match,
    output reg [10:0]              h2c_qid,
    input [10:0] c2h_qid,
    output [31:0] hash_val,
    input c2h_perform,
    input [31:0] read_addr,
    output [31:0] rd_output,
    input [31:0] cycles_per_pkt_2,
    input [31:0] traffic_pattern,
    input flow_config_t flow_config [0:NUM_FLOWS-1],
    input logic [NUM_FLOWS-1:0] flow_running
    );

  logic [CRC_WIDTH-1 : 0]     gen_h2c_tcrc;
  logic 		       s_axis_c2h_tlast_nn1;
  logic 		       wb_sm;
  logic [31:0] 		       cmpt_count;
  logic 		       c2h_st_d1;
  logic 		       start_c2h;
  logic 		       start_imm;
  logic [31:0] 	       cmpt_pkt_cnt;
  logic 		       cmpt_tvalid;
  logic 		       start_cmpt;
  logic rx_begin, qid_fifo_full;
  logic s_axis_c2h_tvalid_d1;
  logic [15:0] curr_pkt_size;

  always_ff @(posedge axi_aclk) begin
    if (~axi_aresetn) begin
      s_axis_c2h_tvalid_d1 <= 1'b0;
    end
    else begin
      s_axis_c2h_tvalid_d1 <= s_axis_c2h_tvalid;
    end
  end
  assign rx_begin = s_axis_c2h_tvalid & ~s_axis_c2h_tvalid_d1;
  //  logic [10:0]   c2h_qid;

//   logic  m_axis_h2c_tready;
//   logic [C_DATA_WIDTH-1 :0] s_axis_c2h_tdata;

logic [31:0] timestamp_counter;
logic perform_begin, perform_d1;
assign perform_begin = c2h_perform & ~perform_d1;

always_ff @(posedge axi_aclk) begin
  if (~axi_aresetn || perform_begin) timestamp_counter <= 0;
  else timestamp_counter += 1;
end
   
always @(posedge axi_aclk) begin
  if (~axi_aresetn) begin
    h2c_qid <= 0;
    perform_d1 <= 0;
  end
  else begin
    h2c_qid <= (m_axis_h2c_tvalid & m_axis_h2c_tlast) ? m_axis_h2c_tuser_qid[10:0] : h2c_qid;
    perform_d1 <= c2h_perform;
  end
end

reg [$clog2(C_DATA_WIDTH/8)-1:0]  s_axis_c2h_mty_comb;
reg [15:0] s_axis_c2h_ctrl_len_comb;

// always @(posedge axi_aclk) begin
assign s_axis_c2h_mty_comb = (start_imm | c2h_control[5]) ? 6'h0 :
                        (curr_pkt_size%(C_DATA_WIDTH/8) > 0) ? C_DATA_WIDTH/8 - (curr_pkt_size%(C_DATA_WIDTH/8)) :
                        6'b0;  //calculate empty bytes for c2h Streaming interface.

assign s_axis_c2h_ctrl_len_comb = (start_imm | c2h_control[5]) ?  (16'h0 | C_DATA_WIDTH/8) : curr_pkt_size; // in case of Immediate data, length = C_DATA_WIDTH/8
// end

assign s_axis_c2h_ctrl_marker = c2h_control[5];   // C2H Marker Enabled

assign s_axis_c2h_ctrl_has_cmpt =  ~c2h_control[3];  // Disable completions

//Integrate change:
assign s_axis_c2h_mty = s_axis_c2h_tlast ? s_axis_c2h_mty_comb : 6'h0;
assign s_axis_c2h_ctrl_len = s_axis_c2h_ctrl_len_comb;
assign s_axis_c2h_ctrl_qid = c2h_dsc_bypass[1:0] == 2'b10 ? pfch_byp_tag_qid : c2h_qid;

// C2H Stream data CRC Generator
crc32_gen #(
  .MAX_DATA_WIDTH   ( C_DATA_WIDTH      ),
  .CRC_WIDTH        ( CRC_WIDTH         )
) crc32_gen_c2h_i (
  // Clock and Resetd
  .clk              ( axi_aclk          ),
  .rst_n            ( axi_aresetn       ),
  .in_par_err       ( 1'b0              ),
  .in_misc_err      ( 1'b0              ),
  .in_crc_dis       ( 1'b0              ),

  .in_data          ( s_axis_c2h_tdata  ),
  .in_vld           ( (s_axis_c2h_tvalid & s_axis_c2h_tready) ),
  .in_tlast         ( s_axis_c2h_tlast  ),
  .in_mty           ( s_axis_c2h_mty_comb    ),
  .out_crc          ( s_axis_c2h_tcrc   )
);

localparam NUM_QUEUES = 16;  // Support up to 16 queues (can be adjusted)



// Credit registers per queue
logic signed [31:0] credit_reg [0:NUM_QUEUES-1];

// Control signals
logic        tm_update, tm_update_d1;
logic [15:0] tm_dsc_sts_avl_d1;
logic [10:0] tm_dsc_sts_qid_d1;
logic        tm_dsc_sts_qinv_d1;

// Packet consumption tracking
logic        pkt_consume;         // Packet sent (consumes 1 descriptor)
logic        pkt_consume_d1;
logic [10:0] consume_qid;         // Queue ID for consumed packet
logic [10:0] consume_qid_d1;

// Conflict detection
logic        wr_conflict;

//------------------------------------------------------------------------------
// Packet consumption signals from C2H interface
//------------------------------------------------------------------------------
// Extract queue ID from C2H control interface
// For now, use s_axis_c2h_ctrl_qid output from TCP module
// When packet completes (tlast), consume 1 credit for that queue
assign consume_qid = s_axis_c2h_ctrl_qid;  // Queue ID from RSS
assign pkt_consume = s_axis_c2h_tvalid && s_axis_c2h_tready && s_axis_c2h_tlast;

//------------------------------------------------------------------------------
// Delayed signals for timing (match traffic_gen.sv)
//------------------------------------------------------------------------------
always_ff @(posedge axi_aclk) begin
    tm_update_d1        <= tm_update;
    tm_dsc_sts_avl_d1   <= tm_dsc_sts_avl;
    tm_dsc_sts_qid_d1   <= tm_dsc_sts_qid;
    tm_dsc_sts_qinv_d1  <= tm_dsc_sts_qinv;
    pkt_consume_d1      <= pkt_consume;
    consume_qid_d1      <= consume_qid;
end

//------------------------------------------------------------------------------
// QDMA Traffic Manager update condition
// Only for C2H streaming mode (same as traffic_gen line 119)
//------------------------------------------------------------------------------
assign tm_update = tm_dsc_sts_vld & 
                   (tm_dsc_sts_qen | tm_dsc_sts_qinv) & 
                   ~tm_dsc_sts_mm &      // Streaming (not memory-mapped)
                   tm_dsc_sts_dir;       // C2H (not H2C)

//------------------------------------------------------------------------------
// Conflict detection: simultaneous QDMA update and packet consumption
// on the SAME queue (same as traffic_gen line 120)
//------------------------------------------------------------------------------
assign wr_conflict = tm_update_d1 & pkt_consume_d1 & 
                     (tm_dsc_sts_qid_d1 == consume_qid_d1);

//------------------------------------------------------------------------------
// Multi-Queue Credit Calculation
// Exactly follows traffic_gen.sv logic (lines 82-101)
//------------------------------------------------------------------------------
always_ff @(posedge axi_aclk) begin
    if (~axi_aresetn) begin
        // Initialize all queue credits to 0
        for (int i = 0; i < NUM_QUEUES; i++) begin
            credit_reg[i] <= 32'sd0;
        end
    end
    else begin
        // CASE 1: Conflict - same queue update and consume (traffic_gen line 87-92)
        if (wr_conflict) begin
            // Same queue: add new credits and subtract consumed packet in one step
            credit_reg[tm_dsc_sts_qid_d1] <= tm_dsc_sts_qinv_d1 ? 32'sd0 : 
                credit_reg[tm_dsc_sts_qid_d1] + $signed({16'd0, tm_dsc_sts_avl_d1}) - 32'sd1;
        end
        // CASE 2 & 3: No conflict - handle updates independently
        else begin
            // QDMA descriptor status update (traffic_gen line 94-96)
            if (tm_update_d1) begin
                credit_reg[tm_dsc_sts_qid_d1] <= tm_dsc_sts_qinv_d1 ? 32'sd0 : 
                    credit_reg[tm_dsc_sts_qid_d1] + $signed({16'd0, tm_dsc_sts_avl_d1});
            end
            
            // Packet consumption (traffic_gen line 97-99)
            // Note: This can happen simultaneously with update on DIFFERENT queue
            if (pkt_consume_d1) begin
                credit_reg[consume_qid_d1] <= credit_reg[consume_qid_d1] - 32'sd1;
            end
        end
    end
end

//------------------------------------------------------------------------------
// Credit availability check for TCP module's queue
// TCP module provides its current queue ID via s_axis_c2h_ctrl_qid
//------------------------------------------------------------------------------
logic c2h_dsc_available;
assign c2h_dsc_available = (credit_reg[consume_qid[3:0]] > 32'sd0);

//------------------------------------------------------------------------------
// Always ready to accept descriptor status from QDMA (traffic_gen line 118)
//------------------------------------------------------------------------------
assign tm_dsc_sts_rdy = 1'b1;

assign hash_val = 0;
top_level tcp_stack(
    .clk(axi_aclk),
    .rst(axi_aresetn),

    // H2C (QDMA -> TCP)
    .m_axis_h2c_tdata(m_axis_h2c_tdata),
    .m_axis_h2c_tcrc(m_axis_h2c_tcrc),
    .m_axis_h2c_tuser_qid(m_axis_h2c_tuser_qid),
    .m_axis_h2c_tuser_port_id(m_axis_h2c_tuser_port_id),
    .m_axis_h2c_tuser_err(m_axis_h2c_tuser_err),
    .m_axis_h2c_tuser_mdata(m_axis_h2c_tuser_mdata),
    .m_axis_h2c_tuser_mty(m_axis_h2c_tuser_mty),
    .m_axis_h2c_tuser_zero_byte(m_axis_h2c_tuser_zero_byte),
    .m_axis_h2c_tvalid(m_axis_h2c_tvalid),
    .m_axis_h2c_tlast(m_axis_h2c_tlast),
    .m_axis_h2c_tready(m_axis_h2c_tready),

    // C2H (TCP -> QDMA)
    .s_axis_c2h_tdata(s_axis_c2h_tdata),
    .s_axis_c2h_tcrc, //set in axi_st_module
    .s_axis_c2h_ctrl_len(curr_pkt_size), //curr_pkt_size for tcp stack
    .s_axis_c2h_ctrl_qid, //set in axi_st_module (c2h_qid), tcp should provide hash_value to RSS indirection table, compute based on 5-tuple, hash_val can be set to 0 temporarily(only using queue 0)
    .s_axis_c2h_ctrl_has_cmpt, //set in axi_st_module
    .s_axis_c2h_ctrl_port_id, //not needed
    .s_axis_c2h_ctrl_marker, // set in axi_st_module
    .s_axis_c2h_ctrl_ecc,  //not needed
    .s_axis_c2h_mty, //set in axi_st_module, based on curr_pkt_size
    .s_axis_c2h_tvalid(s_axis_c2h_tvalid),
    .s_axis_c2h_tlast(s_axis_c2h_tlast), //need to implement in tcp stack
    .s_axis_c2h_tready(s_axis_c2h_tready)
);

// traffic_gen #(.RX_LEN(C_DATA_WIDTH), .MAX_ETH_FRAME(MAX_ETH_FRAME), .TM_DSC_BITS(TM_DSC_BITS), .NUM_FLOWS(NUM_FLOWS)) 
// traffic_gen_c2h(
//     .axi_aclk(axi_aclk),
//     .axi_aresetn(axi_aresetn),
//     // .control_reg(c2h_control),
//     // .txr_size(s_axis_c2h_ctrl_len),
//     .timestamp(timestamp_counter),
//     .rx_ready(s_axis_c2h_tready),
//     // .cycles_per_pkt(cycles_per_pkt),
//     // .cycles_per_pkt_2(cycles_per_pkt_2),
//     // .qid(c2h_st_qid),
//     // .num_queue(c2h_num_queue),
//     .rx_valid(s_axis_c2h_tvalid),
//     .rx_data(s_axis_c2h_tdata),
//     .rx_last(s_axis_c2h_tlast),
//     .hash_val(hash_val),
//     .rx_qid(c2h_qid),
//     // .c2h_perform(c2h_perform),
//     .qid_fifo_full(qid_fifo_full),
//     .flow_config(flow_config),
//     .flow_running(flow_running),
//     .crdt_valid(c2h_dsc_available),
//     .curr_flow_idx(curr_flow_idx)
//     // .tm_dsc_sts_vld    (tm_dsc_sts_vld   ),
//     // .tm_dsc_sts_qen    (tm_dsc_sts_qen   ),
//     // .tm_dsc_sts_byp    (tm_dsc_sts_byp   ),
//     // .tm_dsc_sts_dir    (tm_dsc_sts_dir   ),
//     // .tm_dsc_sts_mm     (tm_dsc_sts_mm    ),
//     // .tm_dsc_sts_error  (tm_dsc_sts_error ),
//     // .tm_dsc_sts_qid    (tm_dsc_sts_qid   ),
//     // .tm_dsc_sts_avl    (tm_dsc_sts_avl   ),
//     // .tm_dsc_sts_qinv   (tm_dsc_sts_qinv  ),
//     // .tm_dsc_sts_irq_arm(tm_dsc_sts_irq_arm),
//     // .tm_dsc_sts_rdy    (tm_dsc_sts_rdy)
// );
// flow_gen #(
//     .RX_LEN(C_DATA_WIDTH), 
//     .NUM_FLOWS(NUM_FLOWS),
//     .FIFO_DEPTH(64)
// ) flow_gen_c2h (
//     .axi_aclk(axi_aclk),
//     .axi_aresetn(axi_aresetn),
//     .timestamp(timestamp_counter),
//     .rx_ready(s_axis_c2h_tready),
//     .crdt_valid(c2h_dsc_available),
//     .qid_fifo_full(qid_fifo_full),
//     .flow_config(flow_config),
//     .flow_running(flow_running),
//     .rx_valid(s_axis_c2h_tvalid),
//     .rx_data(s_axis_c2h_tdata),
//     .rx_last(s_axis_c2h_tlast),
//     .hash_val(hash_val),
//     .pkt_size(curr_pkt_size)
// );


ST_h2c #(
.BIT_WIDTH         ( C_DATA_WIDTH ),
.C_H2C_TUSER_WIDTH ( C_H2C_TUSER_WIDTH )
)
ST_h2c_0 (
.axi_aclk    (axi_aclk),
.axi_aresetn (axi_aresetn),
.perform_begin(perform_begin),
.read_addr(read_addr),
.rd_output(rd_output),
.timestamp(timestamp_counter),
.h2c_tdata   (m_axis_h2c_tdata),
.h2c_tvalid  (m_axis_h2c_tvalid),
.h2c_tready  (m_axis_h2c_tready),
.h2c_tlast   (m_axis_h2c_tlast),
.h2c_tuser_qid (m_axis_h2c_tuser_qid),
.h2c_tuser_port_id (m_axis_h2c_tuser_port_id),
.h2c_tuser_err (m_axis_h2c_tuser_err),
.h2c_tuser_mdata (m_axis_h2c_tuser_mdata),
.h2c_tuser_mty (m_axis_h2c_tuser_mty),
.h2c_tuser_zero_byte (m_axis_h2c_tuser_zero_byte),
.h2c_count   (h2c_count),
.h2c_match   (h2c_match),
.clr_match   (clr_h2c_match)
);

  reg [C_DATA_WIDTH-1 :0]    m_axis_h2c_tdata_reg;
  reg 			      m_axis_h2c_tvalid_reg;
  reg 			      m_axis_h2c_tlast_reg;
  reg [CRC_WIDTH-1 : 0]      m_axis_h2c_tcrc_reg;
(* max_fanout = 100 *)    reg [$clog2(C_DATA_WIDTH/8)-1 : 0]                m_axis_h2c_tuser_mty_reg;
   
   always @(posedge axi_aclk ) begin
      m_axis_h2c_tdata_reg      <= m_axis_h2c_tdata;
      m_axis_h2c_tvalid_reg     <= m_axis_h2c_tvalid;
      m_axis_h2c_tlast_reg      <= m_axis_h2c_tlast;
      m_axis_h2c_tcrc_reg       <= m_axis_h2c_tcrc;
      m_axis_h2c_tuser_mty_reg  <= m_axis_h2c_tuser_mty;
   end
  
 // C2H Stream data CRC Generator
   crc32_gen #(
     .MAX_DATA_WIDTH   ( C_DATA_WIDTH      ),
     .CRC_WIDTH        ( CRC_WIDTH         )
   ) crc32_gen_h2c_i (
     // Clock and Resetd
     .clk              ( axi_aclk          ),
     .rst_n            ( axi_aresetn       ),
     .in_par_err       ( 1'b0              ),
     .in_misc_err      ( 1'b0              ),
     .in_crc_dis       ( 1'b0              ),

     .in_data          ( m_axis_h2c_tdata_reg  ),
     .in_vld           ( m_axis_h2c_tvalid_reg ),
     .in_tlast         ( m_axis_h2c_tlast_reg  ),
     .in_mty           ( m_axis_h2c_tuser_mty_reg ),
     .out_crc          ( gen_h2c_tcrc   )
   );

   always @(posedge axi_aclk ) begin
      if (~axi_aresetn)
        h2c_crc_match <= 0;
      else if (clr_h2c_match | (m_axis_h2c_tlast_reg & (m_axis_h2c_tcrc_reg != gen_h2c_tcrc)))
      	h2c_crc_match <= 0;
      else if (m_axis_h2c_tlast_reg & (m_axis_h2c_tcrc_reg == gen_h2c_tcrc) )
      	h2c_crc_match <= 1;
      end

localparam [0:0] 
	SM_IDL = 1'b0,
	SM_S1 = 1'b1;
   

assign start_c2h = c2h_control[1] & ~c2h_control[3];  // dont start if disable completions is set


always @(posedge axi_aclk ) begin
  if (~axi_aresetn)
	  start_imm <= 1'b0;
  else
	  start_imm <= c2h_control[2] ? 1'b1 : s_axis_c2h_cmpt_tready ? 1'b0 : start_imm;
end

wire empty;
logic rd_en, wr_en;
wire [10:0] rd_out_qid;
logic [15:0] rd_out_pkt_size;
assign cmpt_tvalid = ~empty;

logic [15 : 0] cmp_par_val;  // fixed 512/32
  // Completione size information
  // cmpt_size[1:0] = 00 : 8Bytes of data 1 beat.
  // cmpt_size[1:0] = 01 : 16Bytes of data 1 beat.
  // cmpt_size[1:0] = 10 : 32Bytes of data 2 beat.
assign s_axis_c2h_cmpt_size = byp_to_cmp ? 2'b11 : cmpt_size[1:0];
//   assign s_axis_c2h_cmpt_dpar = 'd0;
assign s_axis_c2h_cmpt_dpar = ~cmp_par_val;
  
always_comb begin
  for (integer i=0; i< 16; i += 1) begin // 512/32 fixed.
    cmp_par_val[i] = ^s_axis_c2h_cmpt_tdata[i*32 +: 32];
  end
end
wire cmpt_user_fmt;
assign cmpt_user_fmt = cmpt_size[2];  

assign rd_en = cmpt_tvalid & s_axis_c2h_cmpt_tready;
assign wr_en = rx_begin;

xpm_fifo_sync # 
(
  .FIFO_MEMORY_TYPE     ("block"), //string; "auto", "block", "distributed", or "ultra";
  .ECC_MODE             ("no_ecc"), //string; "no_ecc" or "en_ecc";
  .FIFO_WRITE_DEPTH     (512), //positive integer
  .WRITE_DATA_WIDTH     (27), //positive integer
  .WR_DATA_COUNT_WIDTH  (10), //positive integer
  .PROG_FULL_THRESH     (10), //positive integer
  .FULL_RESET_VALUE     (0), //positive integer; 0 or 1
  .READ_MODE            ("fwft"), //string; "std" or "fwft";
  .FIFO_READ_LATENCY    (1), //positive integer;
  .READ_DATA_WIDTH      (27), //positive integer
  .RD_DATA_COUNT_WIDTH  (10), //positive integer
  .PROG_EMPTY_THRESH    (10), //positive integer
  .DOUT_RESET_VALUE     ("0"), //string
  .WAKEUP_TIME          (0) //positive integer; 0 or 2;
) cmpt_qid_fifo (
.sleep           (1'b0),
.rst             (~axi_aresetn),
.wr_clk          (axi_aclk),
.wr_en           (wr_en),
.din             ({curr_pkt_size, c2h_qid}),
.full            (qid_fifo_full),
.prog_full       (),
.wr_data_count   (),
.overflow        (),
.wr_rst_busy     (),
.rd_en           (rd_en),
.dout            ({rd_out_pkt_size, rd_out_qid}),
.empty           (empty),
.prog_empty      (),
.rd_data_count   (),
.underflow       (),
.rd_rst_busy     (),
.injectsbiterr   (1'b0),
.injectdbiterr   (1'b0),
.sbiterr         (),
.dbiterr         ()
);

  // write back data format
  // Standart format
  // 0 : data format. 0 = standard format, 1 = user defined.
  // [11:1] : QID
  // [19:12] : // reserved
  // [255:20] : User data.
  // this format should be same for two cycle if type is [1] is set.
assign s_axis_c2h_cmpt_tdata =  byp_to_cmp ? {byp_data_to_cmp[511:4], 4'b0000} :
        start_imm ? {wb_dat[255:0],wb_dat[255:4], 4'b0000} :          // dsc used is not set
          {wb_dat[255:0], wb_dat[255:20], rd_out_pkt_size, 4'b1000};   // dsc used is set 

assign s_axis_c2h_cmpt_tvalid = start_imm | cmpt_tvalid;

assign s_axis_c2h_cmpt_ctrl_qid = rd_out_qid;
assign s_axis_c2h_cmpt_ctrl_cmpt_type = start_imm ? 2'b00 : cmpt_size[12] ? 2'b01 : 2'b11;
assign s_axis_c2h_cmpt_ctrl_wait_pld_pkt_id = cmpt_pkt_cnt[15:0];
assign s_axis_c2h_cmpt_ctrl_marker = c2h_control[5];    // C2H Marker Enabled
assign s_axis_c2h_cmpt_ctrl_user_trig = cmpt_size[3];
assign s_axis_c2h_cmpt_ctrl_col_idx = cmpt_size[6:4];
assign s_axis_c2h_cmpt_ctrl_err_idx = cmpt_size[10:8];
  
always @(posedge axi_aclk) begin
  if (~axi_aresetn) begin
    cmpt_pkt_cnt <= 1;
  end
  else begin
    cmpt_pkt_cnt <=  (s_axis_c2h_cmpt_tvalid & s_axis_c2h_cmpt_tready) & ~start_imm ? cmpt_pkt_cnt+1 : cmpt_pkt_cnt;
  end
end
/*
// Marker responce from QSTS interface.
   assign qsts_out_rdy = 1'b1;   // ready is always asserted
   always @(posedge axi_aclk ) begin
      if (~axi_aresetn) begin
         c2h_st_marker_rsp <= 1'b0;
         end
      else begin
         c2h_st_marker_rsp <= (c2h_control[5] & qsts_out_vld & (qsts_out_op == 8'b0)) ? 1'b1 : ~c2h_control[5] ? 1'b0 : c2h_st_marker_rsp;
         end
      end
*/
endmodule // axi_st_module

module crc32_gen #(
    parameter MAX_DATA_WIDTH    = 512,
    parameter CRC_WIDTH         = 32,
    parameter TCQ               = 1,
    parameter MTY_BITS          = $clog2(MAX_DATA_WIDTH/8)
) (
    // Clock and Resetd
    input                                  clk,
    input                                  rst_n,
    input                                  in_par_err,
    input                                  in_misc_err,
    input                                  in_crc_dis,


    input  [MAX_DATA_WIDTH-1:0]            in_data,
    input                                  in_vld,
    input                                  in_tlast,
    input  [MTY_BITS-1:0]                  in_mty,
    output logic [CRC_WIDTH-1:0]           out_crc
);


  localparam CRC_POLY = 32'b00000100110000010001110110110111;

  logic [CRC_WIDTH-1:0]             crc_var, crc_reg;
  logic                             sop_nxt,sop;
  logic                             out_par_err, out_par_err_reg;
  logic                             out_misc_err, out_misc_err_reg;

  logic [MAX_DATA_WIDTH-1:0]        data_mask;
  logic [MAX_DATA_WIDTH-1:0]        data_masked;
  always_comb begin
    data_mask   = ~in_tlast ? {MAX_DATA_WIDTH{1'b1}} : {MAX_DATA_WIDTH{1'b1}} >> {in_mty, 3'b0};
    data_masked = in_data & data_mask;
    crc_var     = crc_reg;
    sop_nxt     = sop;
    if (in_vld) begin
      if (sop) 
        crc_var = {CRC_WIDTH{1'b1}};
        
      for (int i=0; i<MAX_DATA_WIDTH; i=i+1) begin
        crc_var = {crc_var[CRC_WIDTH-1-1:0], 1'b0} ^ (CRC_POLY & {CRC_WIDTH{crc_var[CRC_WIDTH-1]^data_masked[MAX_DATA_WIDTH-i-1]}});
      end
      sop_nxt = in_tlast;
    end
  end

  always_comb begin
    out_par_err  = out_par_err_reg;
    out_misc_err = out_misc_err_reg;
    if (in_vld) begin
      out_par_err  = sop ? in_par_err : out_par_err_reg | in_par_err;
      out_misc_err = sop ? in_misc_err : out_misc_err_reg | in_misc_err;
    end
  end

  `XSRREG_XDMA(clk, rst_n, crc_reg, crc_var, 'h0)
  `XSRREG_XDMA(clk, rst_n, sop, sop_nxt, 'h1)
  `XSRREG_XDMA(clk, rst_n, out_par_err_reg, out_par_err, 'h0)
  `XSRREG_XDMA(clk, rst_n, out_misc_err_reg, out_misc_err, 'h0)

  //----------------------------------------------------------------
  // Update/Corrupt CRC for Parity and User Errors
  // Corrupt CRC LSB 2 bits for parity error
  // Corrupt CRC all bits for misc error
  //----------------------------------------------------------------
  always_comb begin
    out_crc          = crc_var;
    if (in_crc_dis)
      out_crc[1:0]   = {out_misc_err,out_par_err};
    else if (out_par_err) 
      out_crc[1:0]   = crc_var[1:0] ^ 2'h3;
    else if (out_misc_err) 
      out_crc        = crc_var ^ {CRC_WIDTH{1'b1}};
  end


endmodule // crc32_gen
