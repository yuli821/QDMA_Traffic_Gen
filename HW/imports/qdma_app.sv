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
// File       : qdma_app.sv
// Version    : 5.0
//-----------------------------------------------------------------------------

`timescale 1ps / 1ps
`include "qdma_stm_defines.svh"
module qdma_app #(
  parameter TCQ                         = 1,
  parameter C_M_AXI_ID_WIDTH            = 4,
  parameter PL_LINK_CAP_MAX_LINK_WIDTH  = 8,
  parameter C_DATA_WIDTH                = 512,
  parameter C_M_AXI_DATA_WIDTH          = C_DATA_WIDTH,
  parameter C_S_AXI_DATA_WIDTH          = C_DATA_WIDTH,
  parameter C_S_AXIS_DATA_WIDTH         = C_DATA_WIDTH,
  parameter C_M_AXIS_DATA_WIDTH         = C_DATA_WIDTH,
  parameter C_M_AXIS_RQ_USER_WIDTH      = ((C_DATA_WIDTH == 512) ? 137 : 62),
  parameter C_S_AXIS_CQP_USER_WIDTH     = ((C_DATA_WIDTH == 512) ? 183 : 88),
  parameter C_M_AXIS_RC_USER_WIDTH      = ((C_DATA_WIDTH == 512) ? 161 : 75),
  parameter C_S_AXIS_CC_USER_WIDTH      = ((C_DATA_WIDTH == 512) ?  81 : 33),
  parameter C_S_KEEP_WIDTH              = C_S_AXI_DATA_WIDTH / 32,
  parameter C_M_KEEP_WIDTH              = (C_M_AXI_DATA_WIDTH / 32),
  parameter C_XDMA_NUM_CHNL             = 4,

  parameter MAX_DATA_WIDTH    = 512,
  parameter C_H2C_TUSER_WIDTH = 55,
  parameter CRC_WIDTH         = 32,
  parameter TM_DSC_BITS       = 16,
  parameter TDEST_BITS        = 16
)
(

  // AXI Lite Master Interface connections
  input  [31:0]       s_axil_awaddr,
  input               s_axil_awvalid,
  output              s_axil_awready,
  input  [31:0]       s_axil_wdata,
  input   [3:0]       s_axil_wstrb,
  input               s_axil_wvalid,
  output              s_axil_wready,
  output  [1:0]       s_axil_bresp,
  output              s_axil_bvalid,
  input               s_axil_bready,
  input  [31:0]       s_axil_araddr,
  input               s_axil_arvalid,
  output              s_axil_arready,
  output [31:0]       s_axil_rdata,
  output  [1:0]       s_axil_rresp,
  output              s_axil_rvalid,
  input               s_axil_rready,



  // System IO signals
  input           user_resetn,
  input           sys_rst_n,
  output         soft_reset_n,
  input           sys_clk,
  input           sys_clk_gt,
  output          user_lnk_up,

  output  [PL_LINK_CAP_MAX_LINK_WIDTH-1 : 0] 	pci_exp_txp,
  output  [PL_LINK_CAP_MAX_LINK_WIDTH-1 : 0] 	pci_exp_txn,
  input   [PL_LINK_CAP_MAX_LINK_WIDTH-1 : 0] 	pci_exp_rxp,
  input   [PL_LINK_CAP_MAX_LINK_WIDTH-1 : 0] 	pci_exp_rxn,

  input   [C_S_AXIS_DATA_WIDTH-1:0]     s_axis_rq_tdata,
  input                                 s_axis_rq_tlast,
  input   [C_M_AXIS_RQ_USER_WIDTH-1:0]  s_axis_rq_tuser,
  input   [C_S_KEEP_WIDTH-1:0]          s_axis_rq_tkeep,
  input                                 s_axis_rq_tvalid,
  output  [3:0]                         s_axis_rq_tready,

  output  [C_M_AXIS_DATA_WIDTH-1:0]     m_axis_rc_tdata,
  output  [C_M_AXIS_RC_USER_WIDTH-1:0]  m_axis_rc_tuser,
  output                                m_axis_rc_tlast,
  output  [C_M_KEEP_WIDTH-1:0]          m_axis_rc_tkeep,
  output                                m_axis_rc_tvalid,
  input                                 m_axis_rc_tready,

  output  [C_M_AXIS_DATA_WIDTH-1:0]     m_axis_cq_tdata,
  output  [C_S_AXIS_CQP_USER_WIDTH-1:0] m_axis_cq_tuser,
  output                                m_axis_cq_tlast,
  output  [C_M_KEEP_WIDTH-1:0]          m_axis_cq_tkeep,
  output                                m_axis_cq_tvalid,
  input                                 m_axis_cq_tready,

  input   [C_S_AXIS_DATA_WIDTH-1:0]     s_axis_cc_tdata,
  input   [C_S_AXIS_CC_USER_WIDTH-1:0]  s_axis_cc_tuser,
  input                                 s_axis_cc_tlast,
  input   [C_S_KEEP_WIDTH-1:0]          s_axis_cc_tkeep,
  input                                 s_axis_cc_tvalid,
  output  [3:0]                         s_axis_cc_tready,

  input             user_clk,
  input             phy_rdy_out,
  output            user_reset,
  input   [1:0]     pcie_cq_np_req,
  output  [5:0]     pcie_cq_np_req_count,
  output  [3:0]     pcie_tfc_nph_av,
  output  [3:0]     pcie_tfc_npd_av,
  output            pcie_rq_seq_num_vld0,
  output  [5:0]     pcie_rq_seq_num0,
  output            pcie_rq_seq_num_vld1,
  output  [5:0]     pcie_rq_seq_num1,
  output  [7:0]     cfg_fc_nph,
  output  [7:0]     cfg_fc_ph,
  input   [2:0]     cfg_fc_sel,
  output            cfg_phy_link_down,
  output  [1:0]     cfg_phy_link_status,
  output  [2:0]     cfg_negotiated_width,
  output  [1:0]     cfg_current_speed,
  output            cfg_pl_status_change,
  output            cfg_hot_reset_out,
  input   [7:0]     cfg_ds_port_number,
  input   [7:0]     cfg_ds_bus_number,
  input   [4:0]     cfg_ds_device_number,
  input   [2:0]     cfg_ds_function_number,
  output  [7:0]     cfg_bus_number,
  input    [63:0]   cfg_dsn,
  output [5:0]      cfg_ltssm_state,
  output [15:0]     cfg_function_status,
  output [503:0]    cfg_vf_status,
  output [2:0]      cfg_max_read_req,
  output [1:0]      cfg_max_payload,
  input             cfg_err_uncor_in,
  input             cfg_err_cor_in,
  input             cfg_link_training_enable,

  // Interrupt Interface Signals
  input  [3:0]     cfg_interrupt_int,
  output           cfg_interrupt_sent,
  input  [3:0]     cfg_interrupt_pending,


  output           cfg_interrupt_msi_sent,
  output           cfg_interrupt_msi_fail,
  input  [7:0]     cfg_interrupt_msi_function_number,

  input                                cfg_interrupt_msix_int,       // Configuration Interrupt MSI-X Data Valid.
  input     [31:0]                     cfg_interrupt_msix_data,      // Configuration Interrupt MSI-X Data.
  input     [63:0]                     cfg_interrupt_msix_address,   // Configuration Interrupt MSI-X Address.
  output    [3:0]    cfg_interrupt_msix_enable,    // Configuration Interrupt MSI-X Function Enabled.
  output    [3:0]    cfg_interrupt_msix_mask,      // Configuration Interrupt MSI-X Function Mask.
  output    [251:0]  cfg_interrupt_msix_vf_enable, // Configuration Interrupt MSI-X on VF Enabled.
  output    [251:0]  cfg_interrupt_msix_vf_mask,   // Configuration Interrupt MSI-X VF Mask.
  input     [1:0]    cfg_interrupt_msix_vec_pending, // Configuration Interrupt MSI-X on VF Enabled.
  output    [0:0]    cfg_interrupt_msix_vec_pending_status,   // Configuration Interrupt MSI-X VF Mask.

  output            cfg_err_cor_out,
  output            cfg_err_nonfatal_out,
  output            cfg_err_fatal_out,
  output  [4:0]     cfg_local_error,
  input             cfg_req_pm_transition_l23_ready,

  output            cfg_msg_received,
  output    [7:0]   cfg_msg_received_data,
  output    [4:0]   cfg_msg_received_type,
  input             cfg_msg_transmit,
  input    [2:0]    cfg_msg_transmit_type,
  input    [31:0]   cfg_msg_transmit_data,
  output            cfg_msg_transmit_done,

  input  [18:0]    cfg_mgmt_addr,
  input            cfg_mgmt_write,
  input  [31:0]    cfg_mgmt_write_data,
  input  [3:0]     cfg_mgmt_byte_enable,
  input            cfg_mgmt_read,
  output [31:0]    cfg_mgmt_read_data,
  output           cfg_mgmt_read_write_done,
  input            cfg_mgmt_type1_cfg_reg_access,

  input  [3:0]    cfg_flr_done,
  output [3:0]    cfg_flr_in_process,
  output [251:0]  cfg_vf_flr_in_process,
  input  [7:0]    cfg_vf_flr_func_num,
  input           cfg_vf_flr_done,
  output  			  msi_enable,
  output [2:0]    msi_vector_width,

  input  [255:0]    c2h_byp_out_dsc,
  input  [3:0]      c2h_byp_out_fmt,
  input             c2h_byp_out_st_mm,
  input  [1:0]      c2h_byp_out_dsc_sz,
  input  [10:0]     c2h_byp_out_qid,
  input             c2h_byp_out_error,
  input  [7:0]      c2h_byp_out_func,
  input  [15:0]     c2h_byp_out_cidx,
  input  [2:0]      c2h_byp_out_port_id,
  input  [6:0]      c2h_byp_out_pfch_tag,
  input             c2h_byp_out_vld,
  output            c2h_byp_out_rdy,

  output  [63:0]    c2h_byp_in_mm_radr,
  output  [63:0]    c2h_byp_in_mm_wadr,
  output  [15:0]    c2h_byp_in_mm_len,
  output            c2h_byp_in_mm_mrkr_req,
  output            c2h_byp_in_mm_sdi,
  output  [10:0]    c2h_byp_in_mm_qid,
  output            c2h_byp_in_mm_error,
  output  [7:0]     c2h_byp_in_mm_func,
  output  [15:0]    c2h_byp_in_mm_cidx,
  output  [2:0]     c2h_byp_in_mm_port_id,
  output  [1:0]     c2h_byp_in_mm_at,
  output            c2h_byp_in_mm_no_dma,
  output            c2h_byp_in_mm_vld,
  input             c2h_byp_in_mm_rdy,

  output  [63:0]    c2h_byp_in_st_csh_addr,
  output  [10:0]    c2h_byp_in_st_csh_qid,
  output            c2h_byp_in_st_csh_error,
  output  [7:0]     c2h_byp_in_st_csh_func,
  output  [2:0]     c2h_byp_in_st_csh_port_id,
  output  [6:0]     c2h_byp_in_st_csh_pfch_tag,
  output  [1:0]     c2h_byp_in_st_csh_at,
  output            c2h_byp_in_st_csh_vld,
  input             c2h_byp_in_st_csh_rdy,

  // Descriptor Bypass Out for mdma
  input  [255:0]    h2c_byp_out_dsc,
  input  [3:0]      h2c_byp_out_fmt,
  input             h2c_byp_out_st_mm,
  input  [1:0]      h2c_byp_out_dsc_sz,
  input  [10:0]     h2c_byp_out_qid,
  input             h2c_byp_out_error,
  input  [7:0]      h2c_byp_out_func,
  input  [15:0]     h2c_byp_out_cidx,
  input  [2:0]      h2c_byp_out_port_id,
  input             h2c_byp_out_vld,
  output            h2c_byp_out_rdy,

  // Desciptor Bypass for mdma
  output [63:0]     h2c_byp_in_mm_radr,
  output [63:0]     h2c_byp_in_mm_wadr,
  output [15:0]     h2c_byp_in_mm_len,
  output            h2c_byp_in_mm_mrkr_req,
  output            h2c_byp_in_mm_sdi,
  output [10:0]     h2c_byp_in_mm_qid,
  output            h2c_byp_in_mm_error,
  output [7:0]      h2c_byp_in_mm_func,
  output [15:0]     h2c_byp_in_mm_cidx,
  output [2:0]      h2c_byp_in_mm_port_id,
  output [1:0]      h2c_byp_in_mm_at,
  output            h2c_byp_in_mm_no_dma,
  output            h2c_byp_in_mm_vld,
  input             h2c_byp_in_mm_rdy,

  // Desciptor Bypass for mdma
  output  [63:0]    h2c_byp_in_st_addr,
  output  [15:0]    h2c_byp_in_st_len,
  output            h2c_byp_in_st_eop,
  output            h2c_byp_in_st_sop,
  output            h2c_byp_in_st_mrkr_req,
  output            h2c_byp_in_st_sdi,
  output  [10:0]    h2c_byp_in_st_qid,
  output            h2c_byp_in_st_error,
  output  [7:0]     h2c_byp_in_st_func,
  output  [15:0]    h2c_byp_in_st_cidx,
  output  [2:0]     h2c_byp_in_st_port_id,
  output  [1:0]     h2c_byp_in_st_at,
  output            h2c_byp_in_st_no_dma,
  output            h2c_byp_in_st_vld,
  input             h2c_byp_in_st_rdy,

  input          usr_irq_out_fail,
  input          usr_irq_out_ack,
  output [10:0]  usr_irq_in_vec,
  output [7:0]   usr_irq_in_fnc,
  output reg     usr_irq_in_vld,
  output         st_rx_msg_rdy,
  input          st_rx_msg_valid,
  input          st_rx_msg_last,
  input [31:0]   st_rx_msg_data,

  input          tm_dsc_sts_vld,
  input          tm_dsc_sts_byp,
  input          tm_dsc_sts_qen,
  input          tm_dsc_sts_dir,
  input          tm_dsc_sts_mm,
  input          tm_dsc_sts_error,
  input [10:0]   tm_dsc_sts_qid,
  input [15:0]   tm_dsc_sts_avl,
  input          tm_dsc_sts_qinv,
  input          tm_dsc_sts_irq_arm,
  output         tm_dsc_sts_rdy,

  input [7:0]         qsts_out_op ,
  input [63:0]        qsts_out_data ,
  input [2:0]         qsts_out_port_id ,
  input [12:0]        qsts_out_qid ,
  input               qsts_out_vld ,
  output              qsts_out_rdy ,

  input          axis_c2h_status_drop,
  input          axis_c2h_status_valid,
  input          axis_c2h_status_error,
  input          axis_c2h_status_last,
  input          axis_c2h_status_cmp,
  input [10:0]   axis_c2h_status_qid,

  input          clk,
  input          rst_n,

// Input from QDMA
//   input  [MAX_DATA_WIDTH-1:0]         in_axis_tdata,
//   input  mdma_h2c_axis_tuser_exdes_t  in_axis_tuser,
//   input                               in_axis_tlast,
//   input                               in_axis_tvalid,
//   output logic                        in_axis_tready,
  input   [7:0]     usr_flr_fnc,
  input             usr_flr_set,
  input             usr_flr_clr,
  output  reg [7:0] usr_flr_done_fnc,
  output            usr_flr_done_vld,
  output	[3:0]    cfg_tph_requester_enable,
  output	[251:0]  cfg_vf_tph_requester_enable,

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

  output [C_DATA_WIDTH-1 :0]     s_axis_c2h_tdata /* synthesis syn_keep = 1 */,
  output [CRC_WIDTH-1 :0]        s_axis_c2h_tcrc /* synthesis syn_keep = 1 */,
  output                         s_axis_c2h_ctrl_marker /* synthesis syn_keep = 1 */,
  output [15:0]                  s_axis_c2h_ctrl_len /* synthesis syn_keep = 1 */,
  output [2:0]                   s_axis_c2h_ctrl_port_id /* synthesis syn_keep = 1 */,
  output [10:0]                  s_axis_c2h_ctrl_qid /* synthesis syn_keep = 1 */,
  output [6:0]                   s_axis_c2h_ctrl_ecc /* synthesis syn_keep = 1 */,
  output                         s_axis_c2h_ctrl_has_cmpt /* synthesis syn_keep = 1 */,
  output                         s_axis_c2h_tvalid /* synthesis syn_keep = 1 */,
  input                          s_axis_c2h_tready /* synthesis syn_keep = 1 */,
  output                         s_axis_c2h_tlast /* synthesis syn_keep = 1 */,
  output [5:0]                   s_axis_c2h_mty /* synthesis syn_keep = 1 */ ,
  output [511:0]                 s_axis_c2h_cmpt_tdata,
  output [1:0]                   s_axis_c2h_cmpt_size,
  output [15:0]                  s_axis_c2h_cmpt_dpar,
  output                         s_axis_c2h_cmpt_tvalid,

  output  [10:0]		 s_axis_c2h_cmpt_ctrl_qid,
  output  [1:0]		   s_axis_c2h_cmpt_ctrl_cmpt_type,
  output  [15:0]		 s_axis_c2h_cmpt_ctrl_wait_pld_pkt_id,
  output   		   	   s_axis_c2h_cmpt_ctrl_marker,
  output   		   	   s_axis_c2h_cmpt_ctrl_user_trig,
  output  [2:0]      s_axis_c2h_cmpt_ctrl_col_idx,
  output  [2:0]		   s_axis_c2h_cmpt_ctrl_err_idx,
  input              s_axis_c2h_cmpt_tready,

  output             dsc_crdt_in_vld,
  input              dsc_crdt_in_rdy,
  output             dsc_crdt_in_dir,
  output             dsc_crdt_in_fence,
  output [10:0]      dsc_crdt_in_qid,
  output [15:0]      dsc_crdt_in_crdt,

  output [3:0]  leds

);

  // wire/reg declarations
  wire            sys_reset;
  reg  [25:0]     user_clk_heartbeat;
  wire [31:0]     s_axil_rdata_bram;

  // MDMA signals
  wire  m_axis_h2c_tready_lpbk;
  wire  m_axis_h2c_tready_int;

  // AXIS C2H packet wire

  wire [C_DATA_WIDTH-1:0]    s_axis_c2h_tdata_int;
  wire                       s_axis_c2h_ctrl_marker_int;
  wire [2 :0]                s_axis_c2h_ctrl_port_id_int;
  wire [15:0]                s_axis_c2h_ctrl_len_int;
  wire [10:0]                s_axis_c2h_ctrl_qid_int ;
  wire [6:0]                 s_axis_c2h_ctrl_ecc_int ;
  wire                       s_axis_c2h_ctrl_has_cmpt_int ;
  wire [CRC_WIDTH-1:0]       s_axis_c2h_tcrc_int;

  wire        s_axis_c2h_tvalid_lpbk;
  wire        s_axis_c2h_tlast_lpbk;
  wire [$clog2(C_DATA_WIDTH/8)-1:0]  s_axis_c2h_mty_lpbk;
  wire        s_axis_c2h_tvalid_int;
  wire        s_axis_c2h_tlast_int;
  wire [5:0]  s_axis_c2h_mty_int;

  // AXIS C2H tuser wire
  wire           s_axis_c2h_cmpt_tvalid_int;
  wire  [511:0]  s_axis_c2h_cmpt_tdata_int;
  wire  [1:0]    s_axis_c2h_cmpt_size_int;
  wire  [15:0]   s_axis_c2h_cmpt_dpar_int;
  wire           s_axis_c2h_cmpt_tready_int;

  wire  [10:0]   s_axis_c2h_cmpt_ctrl_qid_int;
  wire  [1:0]    s_axis_c2h_cmpt_ctrl_cmpt_type_int;
  wire  [15:0]   s_axis_c2h_cmpt_ctrl_wait_pld_pkt_id_int;
  wire           s_axis_c2h_cmpt_ctrl_marker_int;
  wire           s_axis_c2h_cmpt_ctrl_user_trig_int;
  wire  [2:0]    s_axis_c2h_cmpt_ctrl_col_idx_int;
  wire  [2:0]    s_axis_c2h_cmpt_ctrl_err_idx_int;

  //HDR output to QDMA
  wire  c2h_stub_std_cmp_t       out_axis_cmp_data;
  wire  c2h_stub_std_cmp_ctrl_t  out_axis_cmp_ctrl;
  wire                           out_axis_cmp_tlast;
  wire                           out_axis_cmp_tvalid;
  wire                           out_axis_cmp_tready;

  //PLD output to QDMA
  wire mdma_c2h_axis_data_exdes_t       out_axis_pld_data;
  wire mdma_c2h_axis_ctrl_exdes_t       out_axis_pld_ctrl;
  wire [$clog2(MAX_DATA_WIDTH/8)-1:0]   out_axis_pld_mty;
  wire                                  out_axis_pld_tlast;
  wire                                  out_axis_pld_tvalid;
  wire                                  out_axis_pld_tready;

  wire [31:0]   c2h_num_pkt;
  wire [10:0]   c2h_st_qid;
  wire [15:0]   c2h_st_len;
  wire [31:0]   h2c_count;
  wire          h2c_match;
  wire          h2c_crc_match;
  wire          clr_h2c_match;
  wire [31:0]   c2h_control;
  wire [10:0]   h2c_qid;
  wire [31:0]   cmpt_size;
  wire [255:0]  wb_dat;
  wire [10:0] c2h_qid;
  wire [31:0]  hash_val;

  wire [TM_DSC_BITS-1:0]   credit_out;
  wire [31:0]   credit_needed;
  wire [TM_DSC_BITS-1:0]   credit_perpkt_in;
  wire                     credit_updt;
  wire [15:0]              buf_count;

  wire        st_loopback;
  wire [1:0]  c2h_dsc_bypass;
  wire [6:0]  pfch_byp_tag;
  wire [10:0] pfch_byp_tag_qid;
  wire 			  h2c_dsc_bypass;

  wire [31:0] cycles_per_pkt;
  wire [10:0] c2h_num_queue;
  wire c2h_perform;
  wire [31:0] read_addr;
  wire [31:0] rd_output;

  // The sys_rst_n input is active low based on the core configuration
  assign sys_resetn = sys_rst_n;

  // Create a Clock Heartbeat
  always @(posedge user_clk) begin
    if(!sys_resetn) begin
      user_clk_heartbeat <= #TCQ 26'd0;
    end else begin
      user_clk_heartbeat <= #TCQ user_clk_heartbeat + 1'b1;
    end
  end

  //
  // Descriptor Credit in logic
  //
  reg start_c2h_d, start_c2h_d1;
  always @(posedge user_clk) begin
    if(~user_resetn) begin
      start_c2h_d <= 1'b0;
      start_c2h_d1 <= 1'b0;
    end
    else begin
      start_c2h_d <= c2h_control[1];
      start_c2h_d1 <= start_c2h_d;
    end
   end

  // assign dsc_crdt_in_vld   = (start_c2h_d & ~start_c2h_d1) & (c2h_dsc_bypass == 2'b10);
  // assign dsc_crdt_in_dir   = start_c2h_d;
  // assign dsc_crdt_in_fence = 1'b0;  // fix me
  // assign dsc_crdt_in_qid   = c2h_qid;
  // assign dsc_crdt_in_crdt  = credit_needed;

  assign c2h_byp_in_st_sim_at = c2h_byp_in_st_csh_at;
  user_control
    #(
      .MAX_ETH_FRAME(16'h1000),
      .C_DATA_WIDTH (C_DATA_WIDTH),
      .QID_MAX (2048),
      .PF0_M_AXILITE_ADDR_MSK( 32'h00000FFF),
      .PF1_M_AXILITE_ADDR_MSK( 32'h00000FFF),
      .PF2_M_AXILITE_ADDR_MSK( 32'h00000FFF),
      .PF3_M_AXILITE_ADDR_MSK( 32'h00000FFF),
      .PF0_VF_M_AXILITE_ADDR_MSK( 32'h00000FFF),
      .PF1_VF_M_AXILITE_ADDR_MSK( 32'h00000FFF),
      .PF2_VF_M_AXILITE_ADDR_MSK( 32'h00000FFF),
      .PF3_VF_M_AXILITE_ADDR_MSK( 32'h00000FFF),
      .PF0_PCIEBAR2AXIBAR( 32'h0000000000000000),
      .PF1_PCIEBAR2AXIBAR( 32'h0000000010000000),
      .PF2_PCIEBAR2AXIBAR( 32'h0000000020000000),
      .PF3_PCIEBAR2AXIBAR( 32'h0000000030000000),
      .PF0_VF_PCIEBAR2AXIBAR( 32'h0000000040000000),
      .PF1_VF_PCIEBAR2AXIBAR( 32'h0000000050000000),
      .PF2_VF_PCIEBAR2AXIBAR( 32'h0000000060000000),
      .PF3_VF_PCIEBAR2AXIBAR( 32'h0000000070000000),
      .TM_DSC_BITS (TM_DSC_BITS)
      )
  user_control_i
    (
      .rd_output(rd_output),
      .read_addr(read_addr),
      .c2h_perform(c2h_perform),
      .c2h_qid(c2h_qid),
      .hash_val(hash_val),
     .c2h_num_queue(c2h_num_queue),
     .cycles_per_pkt(cycles_per_pkt),
     .axi_aclk (clk),
     .axi_aresetn    (user_resetn),
     .single_bit_err_inject_reg (),
     .double_bit_err_inject_reg (),
     .m_axil_wvalid    (s_axil_wvalid),
     .m_axil_wready    (s_axil_wready),
     .m_axil_rvalid    (s_axil_rvalid),
     .m_axil_rready    (s_axil_rready),
     .m_axil_awaddr    (s_axil_awaddr),
     .m_axil_wdata     (s_axil_wdata),
     .m_axil_rdata     (s_axil_rdata),
     .m_axil_rdata_bram(s_axil_rdata_bram),
     .m_axil_araddr    (s_axil_araddr[31:0]),
     .m_axil_arvalid   (s_axil_arvalid),
     .soft_reset_n     (soft_reset_n),
     .st_loopback(st_loopback),
     .c2h_st_marker_rsp(c2h_st_marker_rsp),
     .axi_mm_h2c_valid (s_axi_wvalid),
     .axi_mm_h2c_ready (s_axi_wready),
     .axi_mm_c2h_valid (s_axi_rvalid),
     .axi_mm_c2h_ready (s_axi_rready),
     .axi_st_h2c_valid (m_axis_h2c_tvalid),
     .axi_st_h2c_ready (m_axis_h2c_tready),
     .axi_st_c2h_valid (s_axis_c2h_tvalid),
     .axi_st_c2h_ready (s_axis_c2h_tready),
     .c2h_st_qid (c2h_st_qid),
     .c2h_control (c2h_control),
     .c2h_num_pkt (c2h_num_pkt),
     .clr_h2c_match (clr_h2c_match),
     .c2h_st_len (c2h_st_len),
     .h2c_count (h2c_count),
     .h2c_match (h2c_match),
     .h2c_crc_match  ( h2c_crc_match ),
     .h2c_qid (h2c_qid),
     .h2c_zero_byte (m_axis_h2c_tuser_zero_byte),
     .wb_dat (wb_dat),
     .credit_out (credit_out),
     .credit_updt (credit_updt),
     .credit_perpkt_in (credit_perpkt_in),
     .credit_needed (credit_needed),
     .buf_count (buf_count),
     .axis_c2h_drop       (axis_c2h_status_drop),
     .axis_c2h_drop_valid (axis_c2h_status_valid),
     .cmpt_size (cmpt_size),
     .h2c_dsc_bypass (h2c_dsc_bypass),
     .c2h_dsc_bypass (c2h_dsc_bypass),
     .usr_irq_in_vld(usr_irq_in_vld),
     .usr_irq_in_vec(usr_irq_in_vec),
     .usr_irq_in_fnc(usr_irq_in_fnc),
     .usr_irq_out_ack(usr_irq_out_ack),
     .usr_irq_out_fail(usr_irq_out_fail),
     .st_rx_msg_rdy   (st_rx_msg_rdy),
     .st_rx_msg_valid (st_rx_msg_valid),
     .st_rx_msg_last  (st_rx_msg_last),
     .st_rx_msg_data  (st_rx_msg_data),
     .c2h_mm_marker_req (c2h_mm_marker_req),
     .c2h_mm_marker_rsp (c2h_mm_marker_rsp),
     .h2c_mm_marker_req (h2c_mm_marker_req),
     .h2c_mm_marker_rsp (h2c_mm_marker_rsp),
     .h2c_st_marker_req (h2c_st_marker_req),
     .h2c_st_marker_rsp (h2c_st_marker_rsp),
     .h2c_mm_at(h2c_byp_in_mm_at[1:0]),
     .h2c_st_at(h2c_byp_in_st_at[1:0]),
     .c2h_mm_at(c2h_byp_in_mm_at[1:0]),
     .c2h_st_at(c2h_byp_in_st_csh_at[1:0]),
     .pfch_byp_tag (pfch_byp_tag),
     .pfch_byp_tag_qid (pfch_byp_tag_qid),
     .usr_flr_fnc (usr_flr_fnc),
     .usr_flr_set (usr_flr_set),
     .usr_flr_clr (usr_flr_clr),
     .usr_flr_done_fnc (usr_flr_done_fnc),
     .usr_flr_done_vld (usr_flr_done_vld)
    );

  mdma_h2c_axis_tuser_exdes_t   m_axis_h2c_tuser_net;
  assign m_axis_h2c_tuser_net = {m_axis_h2c_tuser_zero_byte,m_axis_h2c_tuser_mty,m_axis_h2c_tuser_mdata,m_axis_h2c_tuser_err,m_axis_h2c_tuser_port_id,m_axis_h2c_tuser_qid};

  assign m_axis_h2c_tready = (st_loopback == 1'b1) ? m_axis_h2c_tready_lpbk : m_axis_h2c_tready_int;
  assign s_axis_c2h_cmpt_tdata = (st_loopback == 1'b1) ?  out_axis_cmp_data.cmp_ent : s_axis_c2h_cmpt_tdata_int;
  assign s_axis_c2h_cmpt_size  = (st_loopback == 1'b1) ?  out_axis_cmp_data.cmp_size : s_axis_c2h_cmpt_size_int;
  assign s_axis_c2h_cmpt_dpar  = (st_loopback == 1'b1) ?  out_axis_cmp_data.dpar : s_axis_c2h_cmpt_dpar_int;
  assign s_axis_c2h_cmpt_tvalid = (st_loopback == 1'b1) ? out_axis_cmp_tvalid : s_axis_c2h_cmpt_tvalid_int;
  assign s_axis_c2h_cmpt_ctrl_qid = (st_loopback == 1'b1) ? out_axis_cmp_ctrl.qid : s_axis_c2h_cmpt_ctrl_qid_int;
  assign s_axis_c2h_cmpt_ctrl_cmpt_type = (st_loopback == 1'b1) ? out_axis_cmp_ctrl.cmpt_type : s_axis_c2h_cmpt_ctrl_cmpt_type_int;
  assign s_axis_c2h_cmpt_ctrl_wait_pld_pkt_id = (st_loopback == 1'b1) ? out_axis_cmp_ctrl.wait_pld_pkt_id : s_axis_c2h_cmpt_ctrl_wait_pld_pkt_id_int;
  assign s_axis_c2h_cmpt_ctrl_marker = (st_loopback == 1'b1) ? out_axis_cmp_ctrl.marker : s_axis_c2h_cmpt_ctrl_marker_int;
  assign s_axis_c2h_cmpt_ctrl_user_trig = (st_loopback == 1'b1) ? out_axis_cmp_ctrl.user_trig : s_axis_c2h_cmpt_ctrl_user_trig_int;
  assign s_axis_c2h_cmpt_ctrl_col_idx = (st_loopback == 1'b1) ? out_axis_cmp_ctrl.color_idx : s_axis_c2h_cmpt_ctrl_col_idx_int;
  assign s_axis_c2h_cmpt_ctrl_err_idx  = (st_loopback == 1'b1) ? out_axis_cmp_ctrl.error_idx : s_axis_c2h_cmpt_ctrl_err_idx_int;
  assign s_axis_c2h_mty = (st_loopback == 1'b1) ? s_axis_c2h_mty_lpbk : s_axis_c2h_mty_int;
  assign s_axis_c2h_tlast = (st_loopback == 1'b1) ? s_axis_c2h_tlast_lpbk : s_axis_c2h_tlast_int;
  assign s_axis_c2h_tvalid = (st_loopback == 1'b1) ? s_axis_c2h_tvalid_lpbk : s_axis_c2h_tvalid_int;
  assign s_axis_c2h_tdata = (st_loopback == 1'b1) ? out_axis_pld_data.tdata : s_axis_c2h_tdata_int;
//  assign s_axis_c2h_dpar = (st_loopback == 1'b1) ? out_axis_pld_data.par : s_axis_c2h_dpar_int;
  assign s_axis_c2h_tcrc = (st_loopback == 1'b1) ? 32'h0 : s_axis_c2h_tcrc_int;
  assign s_axis_c2h_ctrl_marker = (st_loopback == 1'b1) ? out_axis_pld_ctrl.marker : s_axis_c2h_ctrl_marker_int;
  assign s_axis_c2h_ctrl_port_id = (st_loopback == 1'b1) ? 3'h0 : s_axis_c2h_ctrl_port_id_int;
  assign s_axis_c2h_ctrl_len = (st_loopback == 1'b1) ? out_axis_pld_ctrl.len : s_axis_c2h_ctrl_len_int;
  assign s_axis_c2h_ctrl_qid = (st_loopback == 1'b1) ? out_axis_pld_ctrl.qid : s_axis_c2h_ctrl_qid_int;
  assign s_axis_c2h_ctrl_ecc = (st_loopback == 1'b1) ? 7'b0 : s_axis_c2h_ctrl_ecc_int;
  assign s_axis_c2h_ctrl_has_cmpt = (st_loopback == 1'b1) ? out_axis_pld_ctrl.has_cmpt : s_axis_c2h_ctrl_has_cmpt_int;

  // Bypass to Immediate data design
  wire byp_to_cmp;
  wire [511:0] byp_data_to_cmp;
// reg 	      byp_out_vld;
// reg 	      byp_out_vld_d;
   wire       fifo_wr;
   wire       fifo_rd;
   wire       fifo_full;
   wire [511:0] rd_dout;

   xpm_fifo_sync #
     (
      .FIFO_MEMORY_TYPE     ("block"), //string; "auto", "block", "distributed", or "ultra";
      .ECC_MODE             ("no_ecc"), //string; "no_ecc" or "en_ecc";
      .FIFO_WRITE_DEPTH     (32), //positive integer
      .WRITE_DATA_WIDTH     (256), //positive integer
      .WR_DATA_COUNT_WIDTH  (5), //positive integer
      .PROG_FULL_THRESH     (16), //positive integer
      .FULL_RESET_VALUE     (0), //positive integer; 0 or 1
      .READ_MODE            ("fwft"), //string; "std" or "fwft";
      .FIFO_READ_LATENCY    (1), //positive integer;
      .READ_DATA_WIDTH      (512), //positive integer
      .RD_DATA_COUNT_WIDTH  (4), //positive integer
      .PROG_EMPTY_THRESH    (8), //positive integer
      .DOUT_RESET_VALUE     ("0"), //string
      .WAKEUP_TIME          (0) //positive integer; 0 or 2;
      ) xpm_fifo_byp_imm_i
      (
      .sleep        (1'b0),
      .rst          (~user_resetn),
      .wr_clk       (user_clk),
      .wr_en        (fifo_wr),
      .din          (h2c_byp_out_dsc[255:0]),
      .full         (fifo_full),
      .prog_full    (prog_full),
      .wr_data_count(),
      .overflow     (overflow),
      .wr_rst_busy  (wr_rst_busy),
      .rd_en        (fifo_rd),
      .dout         (rd_dout),
      .empty        (vdm_empty),
      .prog_empty   (prog_empty),
      .rd_data_count(),
      .underflow    (underflow),
      .rd_rst_busy  (rd_rst_busy),
      .injectsbiterr(1'b0),
      .injectdbiterr(1'b0),
      .sbiterr      (),
      .dbiterr      ()
	);
   // End of xpm_fifo_sync instance declaration

  assign byp_to_cmp = &c2h_dsc_bypass[1:0];
  // looping back H2C Stream dsc bypass to C2H completion.

   assign fifo_wr = (h2c_byp_out_vld & ~h2c_byp_out_fmt[0] & ~h2c_byp_out_st_mm & (h2c_byp_out_dsc_sz[1:0] == 2'b11));
   assign fifo_rd = byp_to_cmp & c2h_control[2];
   assign byp_data_to_cmp = rd_dout;


   (* max_fanout = 500 *) reg mid_reset_n;
   
      always @(posedge user_clk) begin
      if (~rst_n) begin
	   mid_reset_n <= 1'h0;
      end else begin
           mid_reset_n <= user_resetn & soft_reset_n ;
      end
      end


// Qdma status responce for Maker request
  qdma_qsts qdma_qsts_i
   (
    .axi_aresetn (mid_reset_n),
    .axi_aclk (user_clk),
    .qsts_out_op                         (qsts_out_op),
    .qsts_out_data                       (qsts_out_data),
    .qsts_out_port_id                    (qsts_out_port_id),
    .qsts_out_qid                        (qsts_out_qid),
    .qsts_out_vld                        (qsts_out_vld),
    .qsts_out_rdy                        (qsts_out_rdy),
    .c2h_st_marker_req                   (c2h_control[5]),
    .c2h_mm_marker_req                   (c2h_mm_marker_req),
    .h2c_st_marker_req                   (h2c_st_marker_req),
    .h2c_mm_marker_req                   (h2c_mm_marker_req),
    .c2h_st_marker_rsp                   (c2h_st_marker_rsp),
    .c2h_mm_marker_rsp                   (c2h_mm_marker_rsp),
    .h2c_st_marker_rsp                   (h2c_st_marker_rsp),
    .h2c_mm_marker_rsp                   (h2c_mm_marker_rsp)
   );

  assign s_axis_c2h_ctrl_port_id_int = 3'h0;

  axi_st_module
  #(
    .MAX_ETH_FRAME(16'h1000),
    .C_DATA_WIDTH      ( C_DATA_WIDTH ),
    .CRC_WIDTH         ( CRC_WIDTH ),
    .C_H2C_TUSER_WIDTH ( C_H2C_TUSER_WIDTH ),
    .TM_DSC_BITS       ( TM_DSC_BITS )
    )
  axi_st_module_i
    (
      .rd_output(rd_output),
      .read_addr(read_addr),
    .c2h_perform(c2h_perform),
    .c2h_num_queue(c2h_num_queue),
    .cycles_per_pkt(cycles_per_pkt),
    .axi_aresetn (mid_reset_n),
    .axi_aclk (user_clk),
    .c2h_st_qid (c2h_st_qid),
    .c2h_control (c2h_control),
    .clr_h2c_match (clr_h2c_match),
    .c2h_st_len (c2h_st_len),
    .c2h_num_pkt (c2h_num_pkt),
    .h2c_count (h2c_count),
    .h2c_match (h2c_match),
    .h2c_crc_match   ( h2c_crc_match ),
    .h2c_qid (h2c_qid),
    .wb_dat (wb_dat),
    .cmpt_size (cmpt_size),
    .credit_in (credit_out),
    .credit_updt (credit_updt),
    .credit_perpkt_in (credit_perpkt_in),
    .credit_needed (credit_needed),
    .buf_count (buf_count),
    .byp_to_cmp (byp_to_cmp),
    .byp_data_to_cmp (byp_data_to_cmp),
    .c2h_dsc_bypass    (c2h_dsc_bypass),
    .pfch_byp_tag_qid  (pfch_byp_tag_qid),
    .m_axis_h2c_tvalid (m_axis_h2c_tvalid),
    .m_axis_h2c_tready (m_axis_h2c_tready_int),
    .m_axis_h2c_tdata  (m_axis_h2c_tdata),
    .m_axis_h2c_tcrc   (m_axis_h2c_tcrc),
    .m_axis_h2c_tlast  (m_axis_h2c_tlast),
    .m_axis_h2c_tuser_qid (m_axis_h2c_tuser_qid),
    .m_axis_h2c_tuser_port_id (m_axis_h2c_tuser_port_id),
    .m_axis_h2c_tuser_err (m_axis_h2c_tuser_err),
    .m_axis_h2c_tuser_mdata (m_axis_h2c_tuser_mdata),
    .m_axis_h2c_tuser_mty (m_axis_h2c_tuser_mty),
    .m_axis_h2c_tuser_zero_byte (m_axis_h2c_tuser_zero_byte),
    .s_axis_c2h_tdata          (s_axis_c2h_tdata_int ),
    .s_axis_c2h_tcrc           (s_axis_c2h_tcrc_int  ),
    .s_axis_c2h_ctrl_marker    (s_axis_c2h_ctrl_marker_int),
    .s_axis_c2h_ctrl_len       (s_axis_c2h_ctrl_len_int), // c2h_st_len,
    .s_axis_c2h_ctrl_qid       (s_axis_c2h_ctrl_qid_int ), // st_qid,
    .s_axis_c2h_ctrl_has_cmpt  (s_axis_c2h_ctrl_has_cmpt_int), // disable write back, write back not valid
    .s_axis_c2h_tvalid         (s_axis_c2h_tvalid_int),
    .s_axis_c2h_tready         (s_axis_c2h_tready),
    .s_axis_c2h_tlast          (s_axis_c2h_tlast_int),
    .s_axis_c2h_mty            (s_axis_c2h_mty_int),  // no empthy bytes at EOP
    .s_axis_c2h_cmpt_tdata               (s_axis_c2h_cmpt_tdata_int),
    .s_axis_c2h_cmpt_size                (s_axis_c2h_cmpt_size_int),
    .s_axis_c2h_cmpt_dpar                (s_axis_c2h_cmpt_dpar_int),
    .s_axis_c2h_cmpt_tvalid              (s_axis_c2h_cmpt_tvalid_int),
    .s_axis_c2h_cmpt_ctrl_qid            (s_axis_c2h_cmpt_ctrl_qid_int     ),
    .s_axis_c2h_cmpt_ctrl_cmpt_type      (s_axis_c2h_cmpt_ctrl_cmpt_type_int       ),
    .s_axis_c2h_cmpt_ctrl_wait_pld_pkt_id(s_axis_c2h_cmpt_ctrl_wait_pld_pkt_id_int ),
    .s_axis_c2h_cmpt_ctrl_marker         (s_axis_c2h_cmpt_ctrl_marker_int          ),
    .s_axis_c2h_cmpt_ctrl_user_trig      (s_axis_c2h_cmpt_ctrl_user_trig_int       ),
    .s_axis_c2h_cmpt_ctrl_col_idx        (s_axis_c2h_cmpt_ctrl_col_idx_int),
    .s_axis_c2h_cmpt_ctrl_err_idx        (s_axis_c2h_cmpt_ctrl_err_idx_int),
    .s_axis_c2h_cmpt_tready              (s_axis_c2h_cmpt_tready),
    .c2h_qid(c2h_qid),
    .hash_val(hash_val),

    .tm_dsc_sts_vld    (tm_dsc_sts_vld   ),
     .tm_dsc_sts_qen    (tm_dsc_sts_qen   ),
     .tm_dsc_sts_byp    (tm_dsc_sts_byp   ),
     .tm_dsc_sts_dir    (tm_dsc_sts_dir   ),
     .tm_dsc_sts_mm     (tm_dsc_sts_mm    ),
     .tm_dsc_sts_error  (tm_dsc_sts_error ),
     .tm_dsc_sts_qid    (tm_dsc_sts_qid   ),
     .tm_dsc_sts_avl    (tm_dsc_sts_avl   ),
     .tm_dsc_sts_qinv   (tm_dsc_sts_qinv  ),
     .tm_dsc_sts_irq_arm(tm_dsc_sts_irq_arm),
     .tm_dsc_sts_rdy    (tm_dsc_sts_rdy)
  );

  // LEDs for observation
  assign leds[0] = sys_resetn;
  assign leds[1] = user_resetn;
  assign leds[2] = user_lnk_up;
  assign leds[3] = user_clk_heartbeat[25];


   wire [56:0] 	ecc_gen_datain;
   wire [56:0] 	ecc_data_out;
   wire [6:0] 	ecc_gen_chkout_int;

   assign s_axis_c2h_ctrl_ecc_int = ecc_gen_chkout_int;

   assign ecc_gen_datain = { 17'h0,                             // reserved
			     1'b0,                              // var_desc
			     1'b0,                              // drop_req
			     1'b0,                              // num_buf_ov
			     4'b0,                              // host_id
			     s_axis_c2h_ctrl_has_cmpt_int,      //
			     s_axis_c2h_ctrl_marker_int,        // marker
			     s_axis_c2h_ctrl_port_id_int,       // port_id
			     1'b0,s_axis_c2h_ctrl_qid_int,      // internal Qid is 12 bits so a a 1'b0
			     s_axis_c2h_ctrl_len_int};


  qdma_ecc_enc #(
    //.C_FAMILY("virtexuplus"),
    //.C_COMPONENT_NAME("ecc_0"),
    //.C_ECC_MODE(0),
    //.C_ECC_TYPE(0),
    .C_DATA_WIDTH(57),
    .C_CHK_BIT_WIDTH(7),
    .C_REG_INPUT(0),
    .C_REG_OUTPUT(0),
    .C_PIPELINE(0),
    .C_USE_CLKEN(0)
  ) c2h_ctrl_ecc_enc_int (
    .ecc_clk(1'b0),
    .ecc_reset(1'b0),
    .ecc_enc_clk_en_in(1'b1),
    .ecc_enc_data_in(ecc_gen_datain),           // input data
    .ecc_enc_data_out(ecc_data_out),            // output data
    .ecc_enc_chk_bits_out(ecc_gen_chkout_int)    // output check bits
    );

  qdma_lpbk #(
    .MAX_DATA_WIDTH(C_DATA_WIDTH),
    .TDEST_BITS(16),
    .TCQ(TCQ)
  )
  qdma_st_lpbk_inst(
    // Clock and Reset
    .clk(clk),
    .rst_n(mid_reset_n),

    //Input from QDMA
    .in_axis_tdata(m_axis_h2c_tdata),
    .in_axis_tuser(m_axis_h2c_tuser_net),
    .in_axis_tlast(m_axis_h2c_tlast),
    .in_axis_tvalid(m_axis_h2c_tvalid),
    .in_axis_tready(m_axis_h2c_tready_lpbk),

    //HDR output to QDMA
    .out_axis_cmp_data(out_axis_cmp_data),
    .out_axis_cmp_ctrl(out_axis_cmp_ctrl),
    .out_axis_cmp_tlast(out_axis_cmp_tlast),
    .out_axis_cmp_tvalid(out_axis_cmp_tvalid),
    .out_axis_cmp_tready(s_axis_c2h_cmpt_tready),

    //PLD output to QDMA
    .out_axis_pld_data(out_axis_pld_data),
    .out_axis_pld_ctrl(out_axis_pld_ctrl),
    .out_axis_pld_mty(s_axis_c2h_mty_lpbk),
    .out_axis_pld_tlast(s_axis_c2h_tlast_lpbk),
    .out_axis_pld_tvalid(s_axis_c2h_tvalid_lpbk),
    .out_axis_pld_tready(s_axis_c2h_tready)
  );

  dsc_byp_h2c dsc_byp_h2c_i
  (
    .h2c_dsc_bypass          (h2c_dsc_bypass),
    .h2c_mm_marker_req       (h2c_mm_marker_req),
    .h2c_mm_marker_rsp       (),
    .h2c_st_marker_req       (h2c_st_marker_req),
    .h2c_st_marker_rsp       (),
    .h2c_byp_out_dsc         (h2c_byp_out_dsc),
    .h2c_byp_out_fmt         (h2c_byp_out_fmt[2:0]),
    .h2c_byp_out_st_mm       (h2c_byp_out_st_mm),
    .h2c_byp_out_dsc_sz      (h2c_byp_out_dsc_sz),
    .h2c_byp_out_qid         (h2c_byp_out_qid),
    .h2c_byp_out_error       (h2c_byp_out_error),
    .h2c_byp_out_func        (h2c_byp_out_func),
    .h2c_byp_out_cidx        (h2c_byp_out_cidx),
    .h2c_byp_out_port_id     (h2c_byp_out_port_id),
    .h2c_byp_out_vld         (h2c_byp_out_vld),
    .h2c_byp_out_rdy         (h2c_byp_out_rdy),

    .h2c_byp_in_mm_radr      (h2c_byp_in_mm_radr),
    .h2c_byp_in_mm_wadr      (h2c_byp_in_mm_wadr),
    .h2c_byp_in_mm_len       (h2c_byp_in_mm_len),
    .h2c_byp_in_mm_mrkr_req  (h2c_byp_in_mm_mrkr_req),
    .h2c_byp_in_mm_sdi       (h2c_byp_in_mm_sdi),
    .h2c_byp_in_mm_qid       (h2c_byp_in_mm_qid),
    .h2c_byp_in_mm_error     (h2c_byp_in_mm_error),
    .h2c_byp_in_mm_func      (h2c_byp_in_mm_func),
    .h2c_byp_in_mm_cidx      (h2c_byp_in_mm_cidx),
    .h2c_byp_in_mm_port_id   (h2c_byp_in_mm_port_id),
    .h2c_byp_in_mm_no_dma    (h2c_byp_in_mm_no_dma),
    .h2c_byp_in_mm_vld       (h2c_byp_in_mm_vld),
    .h2c_byp_in_mm_rdy       (h2c_byp_in_mm_rdy),

    .h2c_byp_in_st_addr      (h2c_byp_in_st_addr),
    .h2c_byp_in_st_len       (h2c_byp_in_st_len),
    .h2c_byp_in_st_eop       (h2c_byp_in_st_eop),
    .h2c_byp_in_st_sop       (h2c_byp_in_st_sop),
    .h2c_byp_in_st_mrkr_req  (h2c_byp_in_st_mrkr_req),
    .h2c_byp_in_st_sdi       (h2c_byp_in_st_sdi),
    .h2c_byp_in_st_qid       (h2c_byp_in_st_qid),
    .h2c_byp_in_st_error     (h2c_byp_in_st_error),
    .h2c_byp_in_st_func      (h2c_byp_in_st_func),
    .h2c_byp_in_st_cidx      (h2c_byp_in_st_cidx),
    .h2c_byp_in_st_port_id   (h2c_byp_in_st_port_id),
    .h2c_byp_in_st_no_dma    (h2c_byp_in_st_no_dma),
    .h2c_byp_in_st_vld       (h2c_byp_in_st_vld),
    .h2c_byp_in_st_rdy       (h2c_byp_in_st_rdy)
  );

  dsc_byp_c2h dsc_byp_c2h_i
  (
    .c2h_dsc_bypass          (c2h_dsc_bypass),
    .c2h_mm_marker_req       (c2h_mm_marker_req),
    .c2h_mm_marker_rsp       (),
    .c2h_byp_out_dsc         (c2h_byp_out_dsc),
    .c2h_byp_out_fmt         (c2h_byp_out_fmt[2:0]),
    .c2h_byp_out_st_mm       (c2h_byp_out_st_mm),
    .c2h_byp_out_dsc_sz      (c2h_byp_out_dsc_sz),
    .c2h_byp_out_qid         (c2h_byp_out_qid),
    .c2h_byp_out_error       (c2h_byp_out_error),
    .c2h_byp_out_func        (c2h_byp_out_func),
    .c2h_byp_out_cidx        (c2h_byp_out_cidx),
    .c2h_byp_out_port_id     (c2h_byp_out_port_id),
    .c2h_byp_out_pfch_tag    (c2h_byp_out_pfch_tag),
    .c2h_byp_out_vld         (c2h_byp_out_vld),
    .c2h_byp_out_rdy         (c2h_byp_out_rdy),
//    .c2h_st_marker_rsp       (c2h_st_marker_rsp),
    .c2h_st_marker_rsp       (),

    .c2h_byp_in_mm_radr      (c2h_byp_in_mm_radr),
    .c2h_byp_in_mm_wadr      (c2h_byp_in_mm_wadr),
    .c2h_byp_in_mm_len       (c2h_byp_in_mm_len),
    .c2h_byp_in_mm_mrkr_req  (c2h_byp_in_mm_mrkr_req),
    .c2h_byp_in_mm_sdi       (c2h_byp_in_mm_sdi),
    .c2h_byp_in_mm_qid       (c2h_byp_in_mm_qid),
    .c2h_byp_in_mm_error     (c2h_byp_in_mm_error),
    .c2h_byp_in_mm_func      (c2h_byp_in_mm_func),
    .c2h_byp_in_mm_cidx      (c2h_byp_in_mm_cidx),
    .c2h_byp_in_mm_port_id   (c2h_byp_in_mm_port_id),
    .c2h_byp_in_mm_no_dma    (c2h_byp_in_mm_no_dma),
    .c2h_byp_in_mm_vld       (c2h_byp_in_mm_vld),
    .c2h_byp_in_mm_rdy       (c2h_byp_in_mm_rdy),

    .c2h_byp_in_st_csh_addr      (c2h_byp_in_st_csh_addr),
    .c2h_byp_in_st_csh_qid       (c2h_byp_in_st_csh_qid),
    .c2h_byp_in_st_csh_error     (c2h_byp_in_st_csh_error),
    .c2h_byp_in_st_csh_func      (c2h_byp_in_st_csh_func),
    .c2h_byp_in_st_csh_port_id   (c2h_byp_in_st_csh_port_id),
    .c2h_byp_in_st_csh_pfch_tag  (c2h_byp_in_st_csh_pfch_tag),
    .c2h_byp_in_st_csh_vld       (c2h_byp_in_st_csh_vld),
    .c2h_byp_in_st_csh_rdy       (c2h_byp_in_st_csh_rdy),
    .pfch_byp_tag                (pfch_byp_tag)
  );

  // Block ram for the AXI Lite interface
axi_bram_ctrl_3 axi_bram_ctrl_3_axiLM_inst (
  .s_axi_aclk   (user_clk),            // input s_axi_aclk
  .s_axi_aresetn(user_resetn),         // input s_axi_aresetn
  .s_axi_awaddr (s_axil_awaddr[12:0]), // input [12:0] s_axi_awaddr
  .s_axi_awprot (3'b0),                // input [2:0] s_axi_awprot
  .s_axi_awvalid(s_axil_awvalid),      // input s_axi_awvalid
  .s_axi_awready(s_axil_awready),      // output s_axi_awready
  .s_axi_wdata  (s_axil_wdata),        // input [31:0] s_axi_wdata
  .s_axi_wstrb  (s_axil_wstrb),        // input [3:0] s_axi_wstrb
  .s_axi_wvalid (s_axil_wvalid),       // input s_axi_wvalid
  .s_axi_wready (s_axil_wready),       // output s_axi_wready
  .s_axi_bresp  (s_axil_bresp),        // output [1:0] s_axi_bresp
  .s_axi_bvalid (s_axil_bvalid),       // output s_axi_bvalid
  .s_axi_bready (s_axil_bready),       // input s_axi_bready
  .s_axi_araddr (s_axil_araddr[12:0]), // input [12:0] s_axi_araddr
  .s_axi_arprot (3'b0),                // input [2:0] s_axi_arprot
  .s_axi_arvalid(s_axil_arvalid),      // input s_axi_arvalid
  .s_axi_arready(s_axil_arready),      // output s_axi_arready
  .s_axi_rdata  (s_axil_rdata_bram),   // output [31:0] s_axi_rdata
  .s_axi_rresp  (s_axil_rresp),        // output [1:0] s_axi_rresp
  .s_axi_rvalid (s_axil_rvalid),       // output s_axi_rvalid
  .s_axi_rready (s_axil_rready)        // input s_axi_rready
);




  wire    [1:0]  cfg_link_power_state;
  wire   [11:0]  cfg_function_power_state;
  wire           cfg_ext_read_received;
  wire           cfg_ext_write_received;
  wire [9:0]     cfg_ext_register_number;
  wire [7:0]     cfg_ext_function_number;
  wire [31:0]    cfg_ext_write_data;
  wire [3:0]     cfg_ext_write_byte_enable;
  wire [31:0]    cfg_ext_read_data;
  wire           cfg_ext_read_data_valid;
  wire   [3:0]   cfg_rcb_status;
  wire    [1:0]  cfg_obff_enable;
//wire    [7:0]  cfg_fc_ph;
  wire   [11:0]  cfg_fc_pd;
//wire    [7:0]  cfg_fc_nph;
  wire   [11:0]  cfg_fc_npd;
  wire    [7:0]  cfg_fc_cplh;
  wire   [11:0]  cfg_fc_cpld;
  wire           cfg_power_state_change_ack;
  wire           cfg_power_state_change_interrupt;
  wire   [11:0]  cfg_interrupt_msi_mmenable;

//assign cfg_dbe_int = cfg_dbe | cfg_err_uncor_in;

//assign cfg_msg_transmit = 1'b0;
//assign cfg_msg_transmit_type = 3'b0;
//assign cfg_msg_transmit_data = 32'h0;

// assign cfg_fc_sel = 3'h5;
assign msi_vector_width = 3'b0;
assign msi_enable       = 1'b0;


endmodule
