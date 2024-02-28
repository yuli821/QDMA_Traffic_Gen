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
// File       : xilinx_qdma_pcie_ep.sv
// Version    : 5.0
//-----------------------------------------------------------------------------
`timescale 1ps / 1ps

`include "qdma_stm_defines.svh"
module xilinx_qdma_pcie_ep #
  (
    parameter PL_LINK_CAP_MAX_LINK_WIDTH  = 8,            // 1- X1; 2 - X2; 4 - X4; 8 - X8
    parameter PL_SIM_FAST_LINK_TRAINING   = "FALSE",  // Simulation Speedup
    parameter PL_LINK_CAP_MAX_LINK_SPEED  = 8,             // 1- GEN1; 2 - GEN2; 4 - GEN3
    parameter C_DATA_WIDTH                = 512 ,
    parameter EXT_PIPE_SIM                = "FALSE",  // This Parameter has effect on selecting Enable External PIPE Interface in GUI.
    parameter C_ROOT_PORT                 = "FALSE",  // PCIe block is in root port mode
    parameter C_DEVICE_NUMBER             = 0,        // Device number for Root Port configurations only
    parameter AXIS_CCIX_RX_TDATA_WIDTH    = 256,
    parameter AXIS_CCIX_TX_TDATA_WIDTH    = 256,
    parameter AXIS_CCIX_RX_TUSER_WIDTH    = 46,
    parameter AXIS_CCIX_TX_TUSER_WIDTH    = 46
  )
  (
    output [(PL_LINK_CAP_MAX_LINK_WIDTH - 1) : 0]   pci_exp_txp,
    output [(PL_LINK_CAP_MAX_LINK_WIDTH - 1) : 0]   pci_exp_txn,
    input  [(PL_LINK_CAP_MAX_LINK_WIDTH - 1) : 0]   pci_exp_rxp,
    input  [(PL_LINK_CAP_MAX_LINK_WIDTH - 1) : 0]   pci_exp_rxn,




    input   sys_clk_p,
    input   sys_clk_n,
    input   sys_rst_n
 );

   //-----------------------------------------------------------------------------------------------------------------------


   // Local Parameters derived from user selection
   localparam integer USER_CLK_FREQ = ((PL_LINK_CAP_MAX_LINK_SPEED == 3'h4) ? 5 : 4);
   localparam TCQ = 1;
   localparam C_S_AXI_ID_WIDTH   = 4;
   localparam C_M_AXI_ID_WIDTH   = 4;
   localparam C_S_AXI_DATA_WIDTH = C_DATA_WIDTH;
   localparam C_M_AXI_DATA_WIDTH = C_DATA_WIDTH;
   localparam C_S_AXI_ADDR_WIDTH = 64;
   localparam C_M_AXI_ADDR_WIDTH = 64;
   localparam C_NUM_USR_IRQ  = 16;
   localparam CRC_WIDTH          = 32;
   localparam MULTQ_EN = 1;
   localparam C_DSC_MAGIC_EN	= 1;
   localparam C_H2C_NUM_RIDS	= 64;
   localparam C_H2C_NUM_CHNL	= MULTQ_EN ? 4 : 4;
   localparam C_C2H_NUM_CHNL	= MULTQ_EN ? 4 : 4;
   localparam C_C2H_NUM_RIDS	= 32;
   localparam C_NUM_PCIE_TAGS	= 256;
   localparam C_S_AXI_NUM_READ 	= 32;
   localparam C_S_AXI_NUM_WRITE	= 8;
   localparam C_H2C_TUSER_WIDTH	= 55;
   localparam C_C2H_TUSER_WIDTH	= 64;
   localparam C_MDMA_DSC_IN_NUM_CHNL = 3;   // only 2 interface are userd. 0 is for MM and 2 is for ST. 1 is not used
   localparam C_MAX_NUM_QUEUE    = 128;
   localparam TM_DSC_BITS = 16;
   localparam C_S_AXIS_DATA_WIDTH        = C_DATA_WIDTH;
   localparam C_M_AXIS_DATA_WIDTH        = C_DATA_WIDTH;
   localparam C_M_AXIS_RQ_USER_WIDTH     = 137;
   localparam C_S_AXIS_CQP_USER_WIDTH    = 183;
   localparam C_M_AXIS_RC_USER_WIDTH     = 161;
   localparam C_S_AXIS_CC_USER_WIDTH     = 81;
   localparam C_S_KEEP_WIDTH             = C_S_AXI_DATA_WIDTH / 32;
   localparam C_M_KEEP_WIDTH             = C_M_AXI_DATA_WIDTH / 32;
  wire user_lnk_up;

  //----------------------------------------------------------------------------------------------------------------//
  //  AXI Interface                                                                                                 //
  //----------------------------------------------------------------------------------------------------------------//
  wire user_clk;
  wire axi_aclk;
  wire axi_aresetn;

  wire user_clk_dma_in;
  wire user_reset_dma_in;
  wire user_reset_dma_out;
  // Wires for Avery HOT/WARM and COLD RESET
  wire avy_sys_rst_n_c;
  wire avy_cfg_hot_reset_out;
  reg  avy_sys_rst_n_g;
  reg  avy_cfg_hot_reset_out_g;

  assign  avy_sys_rst_n_c = avy_sys_rst_n_g;
  assign  avy_cfg_hot_reset_out = avy_cfg_hot_reset_out_g;

  initial begin
    avy_sys_rst_n_g = 1;
    avy_cfg_hot_reset_out_g =0;
  end

  assign user_clk = axi_aclk;






  //----------------------------------------------------------------------------------------------------------------//
  //    System(SYS) Interface                                                                                       //
  //----------------------------------------------------------------------------------------------------------------//

  wire  sys_clk;
  wire  sys_rst_n_c;


  // User Clock LED Heartbeat
  reg [25:0] user_clk_heartbeat;

  //-- AXI Master Write Address Channel
  wire [C_M_AXI_ADDR_WIDTH-1:0]  m_axi_awaddr;
  wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_awid;
  wire [2:0]                     m_axi_awprot;
  wire [1:0]                     m_axi_awburst;
  wire [2:0]                     m_axi_awsize;
  wire [3:0]                     m_axi_awcache;
  wire [7:0]                     m_axi_awlen;
  wire                           m_axi_awlock;
  wire                           m_axi_awvalid;
  wire                           m_axi_awready;

  //-- AXI Master Write Data Channel
  wire [C_M_AXI_DATA_WIDTH-1:0]      m_axi_wdata;
  wire [(C_M_AXI_DATA_WIDTH/8)-1:0]  m_axi_wstrb;
  wire                               m_axi_wlast;
  wire                               m_axi_wvalid;
  wire                               m_axi_wready;

  //-- AXI Master Write Response Channel
  wire                           m_axi_bvalid;
  wire                           m_axi_bready;
  wire [C_M_AXI_ID_WIDTH-1 : 0]  m_axi_bid ;
  wire [1:0]                     m_axi_bresp ;

  //-- AXI Master Read Address Channel
  wire [C_M_AXI_ID_WIDTH-1 : 0]  m_axi_arid;
  wire [C_M_AXI_ADDR_WIDTH-1:0]  m_axi_araddr;
  wire [7:0]                     m_axi_arlen;
  wire [2:0]                     m_axi_arsize;
  wire [1:0]                     m_axi_arburst;
  wire [2:0]                     m_axi_arprot;
  wire                           m_axi_arvalid;
  wire                           m_axi_arready;
  wire                           m_axi_arlock;
  wire [3:0]                     m_axi_arcache;

  //-- AXI Master Read Data Channel
  wire [C_M_AXI_ID_WIDTH-1 : 0]  m_axi_rid;
  wire [C_M_AXI_DATA_WIDTH-1:0]  m_axi_rdata;
  wire [1:0]                     m_axi_rresp;
  wire                           m_axi_rvalid;
  wire                           m_axi_rready;
  wire                           m_axi_rlast;


  //////////////////////////////////////////////////  LITE
  //-- AXI Master Write Address Channel
  wire [31:0] m_axil_awaddr;
  wire [2:0]  m_axil_awprot;
  wire        m_axil_awvalid;
  wire        m_axil_awready;

  //-- AXI Master Write Data Channel
  wire [31:0] m_axil_wdata;
  wire [3:0]  m_axil_wstrb;
  wire        m_axil_wvalid;
  wire        m_axil_wready;

  //-- AXI Master Write Response Channel
  wire        m_axil_bvalid;
  wire        m_axil_bready;

  //-- AXI Master Read Address Channel
  wire [31:0] m_axil_araddr;
  wire [2:0]  m_axil_arprot;
  wire        m_axil_arvalid;
  wire        m_axil_arready;

  //-- AXI Master Read Data Channel
  wire [31:0] m_axil_rdata;
  wire [1:0]  m_axil_rresp;
  wire        m_axil_rvalid;
  wire        m_axil_rready;
  wire [1:0]  m_axil_bresp;

  wire [2:0]  msi_vector_width;
  wire        msi_enable;

  wire [3:0]  leds;

  wire   free_run_clock;

  wire [5:0]  cfg_ltssm_state;
  //******************************************************************
  //New ports for split IP
  //******************************************************************
  wire [C_S_AXIS_DATA_WIDTH-1:0]     s_axis_rq_tdata;
  wire                               s_axis_rq_tlast;
  wire [C_M_AXIS_RQ_USER_WIDTH-1:0]  s_axis_rq_tuser;
  wire [C_S_KEEP_WIDTH-1:0]          s_axis_rq_tkeep;
  wire                               s_axis_rq_tvalid;
  wire [3:0]                         s_axis_rq_tready;

  wire [C_M_AXIS_DATA_WIDTH-1:0]     m_axis_rc_tdata;
  wire [C_M_AXIS_RC_USER_WIDTH-1:0]  m_axis_rc_tuser;
  wire                               m_axis_rc_tlast;
  wire [C_M_KEEP_WIDTH-1:0]          m_axis_rc_tkeep;
  wire                               m_axis_rc_tvalid;
  wire                               m_axis_rc_tready;

  wire [C_M_AXIS_DATA_WIDTH-1:0]     m_axis_cq_tdata;
  wire [C_S_AXIS_CQP_USER_WIDTH-1:0] m_axis_cq_tuser;
  wire                               m_axis_cq_tlast;
  wire [C_M_KEEP_WIDTH-1:0]          m_axis_cq_tkeep;
  wire                               m_axis_cq_tvalid;
  wire                               m_axis_cq_tready;

  wire [C_S_AXIS_DATA_WIDTH-1:0]     s_axis_cc_tdata;
  wire [C_S_AXIS_CC_USER_WIDTH-1:0]  s_axis_cc_tuser;
  wire                               s_axis_cc_tlast;
  wire [C_S_KEEP_WIDTH-1:0]          s_axis_cc_tkeep;
  wire                               s_axis_cc_tvalid;
  wire [3:0]                         s_axis_cc_tready;

  wire        user_reset;
  wire        phy_rdy_out;
  wire [1:0]  pcie_cq_np_req;
  wire [5:0]  pcie_cq_np_req_count;
  wire [3:0]  pcie_tfc_nph_av;
  wire [3:0]  pcie_tfc_npd_av;
  wire        pcie_rq_seq_num_vld0;
  wire [5:0]  pcie_rq_seq_num0;
  wire        pcie_rq_seq_num_vld1;
  wire [5:0]  pcie_rq_seq_num1;

  wire [15:0] cfg_function_status;
  wire [503:0] cfg_vf_status;
  wire [2:0]  cfg_max_read_req;
  wire [1:0]  cfg_max_payload;
  wire [7:0]  cfg_fc_nph;
  wire [7:0]  cfg_fc_ph;
  wire [2:0]  cfg_fc_sel;
  wire        cfg_phy_link_down;
  wire [1:0]  cfg_phy_link_status;
  wire [2:0]  cfg_negotiated_width;
  wire [1:0]  cfg_current_speed;
  wire        cfg_pl_status_change;
  wire        cfg_hot_reset_out;
  wire [7:0]  cfg_ds_port_number;
  wire [7:0]  cfg_ds_bus_number;
  wire [7:0]  cfg_bus_number;
  wire [4:0]  cfg_ds_device_number;
  wire [2:0]  cfg_ds_function_number;
  wire        cfg_dbe;
  wire [63:0] cfg_dsn;
  wire        cfg_err_uncor_in;
  wire        cfg_err_cor_in;
  wire        cfg_link_training_enable;

  // Interrupt Interface Signals
  wire [3:0]  cfg_interrupt_int;
  wire        cfg_interrupt_sent;
  wire [3:0]  cfg_interrupt_pending;

  wire [3:0]  cfg_interrupt_msi_enable;
  wire        cfg_interrupt_msi_mask_update;
  wire [31:0] cfg_interrupt_msi_data;
  wire [31:0] cfg_interrupt_msi_int;
  wire [31:0] cfg_interrupt_msi_pending_status;
  wire        cfg_interrupt_msi_pending_status_data_enable;
  wire [3:0]  cfg_interrupt_msi_pending_status_function_num;
  wire [2:0]  cfg_interrupt_msi_attr;
  wire        cfg_interrupt_msi_tph_present;
  wire [1:0]  cfg_interrupt_msi_tph_type;
  wire [8:0]  cfg_interrupt_msi_tph_st_tag;
  wire [7:0]  cfg_interrupt_msi_function_number;
  wire        cfg_interrupt_msi_sent;
  wire        cfg_interrupt_msi_fail;

  wire          cfg_interrupt_msix_int;       // Configuration Interrupt MSI-X Data Valid.
  wire [31:0]   cfg_interrupt_msix_data;      // Configuration Interrupt MSI-X Data.
  wire [63:0]   cfg_interrupt_msix_address;   // Configuration Interrupt MSI-X Address.
  wire [3:0]    cfg_interrupt_msix_enable;    // Configuration Interrupt MSI-X Function Enabled.
  wire [3:0]    cfg_interrupt_msix_mask;      // Configuration Interrupt MSI-X Function Mask.
  wire [251:0]  cfg_interrupt_msix_vf_enable; // Configuration Interrupt MSI-X on VF Enabled.
  wire [251:0]  cfg_interrupt_msix_vf_mask;   // Configuration Interrupt MSI-X VF Mask.
  wire [1:0]    cfg_interrupt_msix_vec_pending; // Configuration Interrupt MSI-X on VF Enabled.
  wire [0:0]    cfg_interrupt_msix_vec_pending_status;   // Configuration Interrupt MSI-X VF Mask.

  // Error Reporting Interface
  wire          cfg_err_cor_out;
  wire          cfg_err_nonfatal_out;
  wire          cfg_err_fatal_out;
  wire [4:0]    cfg_local_error;
  wire          cfg_req_pm_transition_l23_ready;

  wire          cfg_msg_received;
  wire [7:0]    cfg_msg_received_data;
  wire [4:0]    cfg_msg_received_type;
  wire          cfg_msg_transmit;
  wire [2:0]    cfg_msg_transmit_type;
  wire [31:0]   cfg_msg_transmit_data;
  wire          cfg_msg_transmit_done;
  wire [3:0]    cfg_flr_in_process;
  wire [3:0]    cfg_flr_done;
  wire [251:0]  cfg_vf_flr_in_process;

  wire [7:0]		c2h_sts_0;
  wire [7:0]		h2c_sts_0;
  wire [7:0]		c2h_sts_1;
  wire [7:0]		h2c_sts_1;
  wire [7:0]		c2h_sts_2;
  wire [7:0]		h2c_sts_2;
  wire [7:0]		c2h_sts_3;
  wire [7:0]		h2c_sts_3;

  // MDMA signals
  wire   [C_DATA_WIDTH-1:0]   m_axis_h2c_tdata;
  wire   [CRC_WIDTH-1:0]      m_axis_h2c_tcrc;
  wire   [10:0]               m_axis_h2c_tuser_qid;
  wire   [2:0]                m_axis_h2c_tuser_port_id;
  wire                        m_axis_h2c_tuser_err;
  wire   [31:0]               m_axis_h2c_tuser_mdata;
  wire   [5:0]                m_axis_h2c_tuser_mty;
  wire                        m_axis_h2c_tuser_zero_byte;
  wire                        m_axis_h2c_tvalid;
  wire                        m_axis_h2c_tready;
  wire                        m_axis_h2c_tlast;

  wire                        m_axis_h2c_tready_lpbk;
  wire                        m_axis_h2c_tready_int;

  // AXIS C2H packet wire
  wire [C_DATA_WIDTH-1:0]     s_axis_c2h_tdata;
  wire [CRC_WIDTH-1:0]        s_axis_c2h_tcrc;
  wire                        s_axis_c2h_ctrl_marker;
  wire [6:0]                  s_axis_c2h_ctrl_ecc;
  wire [15:0]                 s_axis_c2h_ctrl_len;
  wire [2:0]                  s_axis_c2h_ctrl_port_id;
  wire [10:0]                 s_axis_c2h_ctrl_qid ;
  wire                        s_axis_c2h_ctrl_has_cmpt ;
  wire [C_DATA_WIDTH-1:0]     s_axis_c2h_tdata_int;
  wire                        s_axis_c2h_ctrl_marker_int;
  wire [15:0]                 s_axis_c2h_ctrl_len_int;
  wire [10:0]                 s_axis_c2h_ctrl_qid_int ;
  wire                        s_axis_c2h_ctrl_has_cmpt_int ;
  wire                        s_axis_c2h_tvalid;
  wire                        s_axis_c2h_tready;
  wire                        s_axis_c2h_tlast;
  wire  [5:0]                 s_axis_c2h_mty;
  wire                        s_axis_c2h_tvalid_lpbk;
  wire                        s_axis_c2h_tlast_lpbk;
  wire  [5:0]                 s_axis_c2h_mty_lpbk;
  wire                        s_axis_c2h_tvalid_int;
  wire                        s_axis_c2h_tlast_int;
  wire  [5:0]                 s_axis_c2h_mty_int;

  // AXIS C2H tuser wire
  wire  [511:0] s_axis_c2h_cmpt_tdata;
  wire  [1:0]   s_axis_c2h_cmpt_size;
  wire  [15:0]  s_axis_c2h_cmpt_dpar;
  wire          s_axis_c2h_cmpt_tvalid;
  wire          s_axis_c2h_cmpt_tvalid_int;
  wire  [511:0] s_axis_c2h_cmpt_tdata_int;
  wire  [1:0]   s_axis_c2h_cmpt_size_int;
  wire  [15:0]  s_axis_c2h_cmpt_dpar_int;
  wire          s_axis_c2h_cmpt_tready_int;
  wire          s_axis_c2h_cmpt_tready;
	wire [10:0]		s_axis_c2h_cmpt_ctrl_qid;
	wire [1:0]		s_axis_c2h_cmpt_ctrl_cmpt_type;
	wire [15:0]		s_axis_c2h_cmpt_ctrl_wait_pld_pkt_id;
	wire 				  s_axis_c2h_cmpt_ctrl_marker;
	wire 				  s_axis_c2h_cmpt_ctrl_user_trig;
	wire [2:0]		s_axis_c2h_cmpt_ctrl_col_idx;
	wire [2:0]		s_axis_c2h_cmpt_ctrl_err_idx;

  // Descriptor Bypass Out for qdma
  wire  [255:0] h2c_byp_out_dsc;
  wire  [3:0]   h2c_byp_out_fmt;
  wire          h2c_byp_out_st_mm;
  wire  [10:0]  h2c_byp_out_qid;
  wire  [1:0]   h2c_byp_out_dsc_sz;
  wire          h2c_byp_out_error;
  wire  [7:0]   h2c_byp_out_func;
  wire  [15:0]  h2c_byp_out_cidx;
  wire  [2:0]   h2c_byp_out_port_id;
  wire          h2c_byp_out_vld;
  wire          h2c_byp_out_rdy;

  wire  [255:0] c2h_byp_out_dsc;
  wire  [3:0]   c2h_byp_out_fmt;
  wire          c2h_byp_out_st_mm;
  wire  [1:0]   c2h_byp_out_dsc_sz;
  wire  [10:0]  c2h_byp_out_qid;
  wire          c2h_byp_out_error;
  wire  [7:0]   c2h_byp_out_func;
  wire  [15:0]  c2h_byp_out_cidx;
  wire  [2:0]   c2h_byp_out_port_id;
  wire  [6:0]   c2h_byp_out_pfch_tag;
  wire          c2h_byp_out_vld;
  wire          c2h_byp_out_rdy;

  // Descriptor Bypass In for qdma MM
  wire  [63:0]  h2c_byp_in_mm_radr;
  wire  [63:0]  h2c_byp_in_mm_wadr;
  wire  [15:0]  h2c_byp_in_mm_len;
  wire          h2c_byp_in_mm_mrkr_req;
  wire          h2c_byp_in_mm_sdi;
  wire  [10:0]  h2c_byp_in_mm_qid;
  wire          h2c_byp_in_mm_error;
  wire  [7:0]   h2c_byp_in_mm_func;
  wire  [15:0]  h2c_byp_in_mm_cidx;
  wire  [2:0]   h2c_byp_in_mm_port_id;
  wire  [1:0]   h2c_byp_in_mm_at;
  wire          h2c_byp_in_mm_no_dma;
  wire          h2c_byp_in_mm_vld;
  wire          h2c_byp_in_mm_rdy;

  wire  [63:0]  c2h_byp_in_mm_radr;
  wire  [63:0]  c2h_byp_in_mm_wadr;
  wire  [15:0]  c2h_byp_in_mm_len;
  wire          c2h_byp_in_mm_mrkr_req;
  wire          c2h_byp_in_mm_sdi;
  wire  [10:0]  c2h_byp_in_mm_qid;
  wire          c2h_byp_in_mm_error;
  wire  [7:0]   c2h_byp_in_mm_func;
  wire  [15:0]  c2h_byp_in_mm_cidx;
  wire  [2:0]   c2h_byp_in_mm_port_id;
  wire  [1:0]   c2h_byp_in_mm_at;
  wire          c2h_byp_in_mm_no_dma;
  wire          c2h_byp_in_mm_vld;
  wire          c2h_byp_in_mm_rdy;

  // Descriptor Bypass In for qdma ST
  wire [63:0]   h2c_byp_in_st_addr;
  wire [15:0]   h2c_byp_in_st_len;
  wire          h2c_byp_in_st_eop;
  wire          h2c_byp_in_st_sop;
  wire          h2c_byp_in_st_mrkr_req;
  wire          h2c_byp_in_st_sdi;
  wire  [10:0]  h2c_byp_in_st_qid;
  wire          h2c_byp_in_st_error;
  wire  [7:0]   h2c_byp_in_st_func;
  wire  [15:0]  h2c_byp_in_st_cidx;
  wire  [2:0]   h2c_byp_in_st_port_id;
  wire  [1:0]   h2c_byp_in_st_at;
  wire          h2c_byp_in_st_no_dma;
  wire          h2c_byp_in_st_vld;
  wire          h2c_byp_in_st_rdy;

  wire  [63:0]  c2h_byp_in_st_csh_addr;
  wire  [10:0]  c2h_byp_in_st_csh_qid;
  wire          c2h_byp_in_st_csh_error;
  wire  [7:0]   c2h_byp_in_st_csh_func;
  wire  [2:0]   c2h_byp_in_st_csh_port_id;
  wire  [6:0]   c2h_byp_in_st_csh_pfch_tag;
  wire  [1:0]   c2h_byp_in_st_csh_at;
  wire          c2h_byp_in_st_csh_vld;
  wire          c2h_byp_in_st_csh_rdy;

  wire          usr_irq_in_vld;
  wire [10 : 0] usr_irq_in_vec;
  wire [7 : 0]  usr_irq_in_fnc;
  wire          usr_irq_out_ack;
  wire          usr_irq_out_fail;

  wire          st_rx_msg_rdy;
  wire          st_rx_msg_valid;
  wire          st_rx_msg_last;
  wire [31:0]   st_rx_msg_data;

  wire          tm_dsc_sts_vld;
  wire          tm_dsc_sts_qen;
  wire          tm_dsc_sts_byp;
  wire          tm_dsc_sts_dir;
  wire          tm_dsc_sts_mm;
  wire          tm_dsc_sts_error;
  wire  [10:0]  tm_dsc_sts_qid;
  wire  [15:0]  tm_dsc_sts_avl;
  wire          tm_dsc_sts_qinv;
  wire          tm_dsc_sts_irq_arm;
  wire          tm_dsc_sts_rdy;

  // Descriptor credit In
  wire          dsc_crdt_in_vld;
  wire          dsc_crdt_in_rdy;
  wire          dsc_crdt_in_dir;
  wire          dsc_crdt_in_fence;
  wire [10:0]   dsc_crdt_in_qid;
  wire [15:0]   dsc_crdt_in_crdt;

  // Report the DROP case
  wire          axis_c2h_status_drop;
  wire          axis_c2h_status_last;
  wire          axis_c2h_status_valid;
  wire          axis_c2h_status_imm_or_marker;
  wire          axis_c2h_status_cmp;
  wire [10:0]   axis_c2h_status_qid;
  wire [7:0]    qsts_out_op;
  wire [63:0]   qsts_out_data;
  wire [2:0]    qsts_out_port_id;
  wire [12:0]   qsts_out_qid;
  wire          qsts_out_vld;
  wire          qsts_out_rdy;

  // FLR
  wire [7:0]  usr_flr_fnc;
  wire        usr_flr_set;
  wire        usr_flr_clr;
  wire [7:0]  usr_flr_done_fnc;
  wire        usr_flr_done_vld;
  wire [3:0]		cfg_tph_requester_enable;
  wire [251:0]	cfg_vf_tph_requester_enable;
	wire          soft_reset_n;
	wire					st_loopback;

  wire [10:0]   c2h_num_pkt;
  wire [10:0]   c2h_st_qid;
  wire [15:0]   c2h_st_len;
  wire [31:0]   h2c_count;
  wire          h2c_match;
  wire          clr_h2c_match;
  wire 	        c2h_end;
  wire [31:0]   c2h_control;
  wire [10:0]   h2c_qid;
  wire [31:0]   cmpt_size;
  wire [255:0]  wb_dat;

  wire [TM_DSC_BITS-1:0] credit_out;
  wire [TM_DSC_BITS-1:0] credit_needed;
  wire [TM_DSC_BITS-1:0] credit_perpkt_in;
  wire                   credit_updt;

  wire [15:0] buf_count;
  wire        sys_clk_gt;


  // Ref clock buffer
//  IBUFDS_GTE5 # (.REFCLK_HROW_CK_SEL(2'b00)) refclk_ibuf (.O(sys_clk_gt), .ODIV2(sys_clk), .I(sys_clk_p), .CEB(1'b0), .IB(sys_clk_n));
  // Reset buffer
  IBUF   sys_reset_n_ibuf (.O(sys_rst_n_c), .I(sys_rst_n));




//
//



 qdma_ep qdma_ep_i
  (
    .pcie_refclk_clk_p(sys_clk_p),
    .pcie_refclk_clk_n(sys_clk_n),


    //---------------------------------------------------//
    //  PCI Express (pci_exp) Interface                  //
    //---------------------------------------------------//
    .pcie_mgt_gtx_n (pci_exp_txn),
    .pcie_mgt_gtx_p (pci_exp_txp),
    .pcie_mgt_grx_n (pci_exp_rxn),
    .pcie_mgt_grx_p (pci_exp_rxp),


    // LITE interface
    //-- AXI Master Write Address Channel
    .M_AXI_LITE_awaddr    (m_axil_awaddr),
    .M_AXI_LITE_awprot    (m_axil_awprot),
    .M_AXI_LITE_awvalid   (m_axil_awvalid),
    .M_AXI_LITE_awready   (m_axil_awready),
    //-- AXI Master Write Data Channel
    .M_AXI_LITE_wdata     (m_axil_wdata),
    .M_AXI_LITE_wstrb     (m_axil_wstrb),
    .M_AXI_LITE_wvalid    (m_axil_wvalid),
    .M_AXI_LITE_wready    (m_axil_wready),
    //-- AXI Master Write Response Channel
    .M_AXI_LITE_bvalid    (m_axil_bvalid),
    .M_AXI_LITE_bresp     (m_axil_bresp),
    .M_AXI_LITE_bready    (m_axil_bready),
    //-- AXI Master Read Address Channel
    .M_AXI_LITE_araddr    (m_axil_araddr),
    .M_AXI_LITE_arprot    (m_axil_arprot),
    .M_AXI_LITE_arvalid   (m_axil_arvalid),
    .M_AXI_LITE_arready   (m_axil_arready),
    .M_AXI_LITE_rdata     (m_axil_rdata),
    //-- AXI Master Read Data Channel
    .M_AXI_LITE_rresp     (m_axil_rresp),
    .M_AXI_LITE_rvalid    (m_axil_rvalid),
    .M_AXI_LITE_rready    (m_axil_rready),

    //-- AXI Global
    .axi_aclk(axi_aclk),
    .phy_rdy_out (phy_rdy_out),
    .axi_aresetn (axi_aresetn),
    .soft_reset_n(soft_reset_n),

    .s_axis_c2h_tdata        (s_axis_c2h_tdata),
    .s_axis_c2h_tcrc         (s_axis_c2h_tcrc),
    .s_axis_c2h_ctrl_marker  (s_axis_c2h_ctrl_marker),
    .s_axis_c2h_ctrl_len     (s_axis_c2h_ctrl_len), // c2h_st_len),
    .s_axis_c2h_ctrl_port_id (s_axis_c2h_ctrl_port_id),
    .s_axis_c2h_ecc          (s_axis_c2h_ctrl_ecc),
    .s_axis_c2h_ctrl_qid     (s_axis_c2h_ctrl_qid), // st_qid,
    .s_axis_c2h_ctrl_has_cmpt(s_axis_c2h_ctrl_has_cmpt),   //write back is valid
    .s_axis_c2h_tvalid       (s_axis_c2h_tvalid),
    .s_axis_c2h_tready       (s_axis_c2h_tready),
    .s_axis_c2h_tlast        (s_axis_c2h_tlast),
    .s_axis_c2h_mty          (s_axis_c2h_mty),    // no empthy bytes at EOP

    .m_axis_h2c_tready   (m_axis_h2c_tready),
    .m_axis_h2c_tvalid   (m_axis_h2c_tvalid),
    .m_axis_h2c_tlast    (m_axis_h2c_tlast),
    .m_axis_h2c_qid      (m_axis_h2c_tuser_qid),
    .m_axis_h2c_port_id  (m_axis_h2c_tuser_port_id),
    .m_axis_h2c_err      (m_axis_h2c_tuser_err),
    .m_axis_h2c_mdata    (m_axis_h2c_tuser_mdata),
    .m_axis_h2c_mty      (m_axis_h2c_tuser_mty),
    .m_axis_h2c_zero_byte(m_axis_h2c_tuser_zero_byte),
    .m_axis_h2c_tdata    (m_axis_h2c_tdata),
    .m_axis_h2c_tcrc     (m_axis_h2c_tcrc),

    .axis_c2h_drop_error (axis_c2h_status_error),
    .axis_c2h_drop_drop  (axis_c2h_status_drop),
    .axis_c2h_drop_last  (axis_c2h_status_last),
    .axis_c2h_drop_status_cmp(axis_c2h_status_cmp),
    .axis_c2h_drop_valid (axis_c2h_status_valid),
    .axis_c2h_drop_qid   (axis_c2h_status_qid),
//    .axis_c2h_drop_dmawr_cmp    ( ),
    .s_axis_c2h_cmpt_data    (s_axis_c2h_cmpt_tdata),
    .s_axis_c2h_cmpt_size     (s_axis_c2h_cmpt_size),
    .s_axis_c2h_cmpt_dpar     (s_axis_c2h_cmpt_dpar),
    .s_axis_c2h_cmpt_tvalid   (s_axis_c2h_cmpt_tvalid),
    .s_axis_c2h_cmpt_tready   (s_axis_c2h_cmpt_tready),
    .s_axis_c2h_cmpt_qid      (s_axis_c2h_cmpt_ctrl_qid),
    .s_axis_c2h_cmpt_cmpt_type(s_axis_c2h_cmpt_ctrl_cmpt_type),
    .s_axis_c2h_cmpt_wait_pld_pkt_id(s_axis_c2h_cmpt_ctrl_wait_pld_pkt_id),
    .s_axis_c2h_cmpt_port_id  (3'b000),
    .s_axis_c2h_cmpt_marker   (s_axis_c2h_cmpt_ctrl_marker),
    .s_axis_c2h_cmpt_no_wrb_marker  (1'b0),
    .s_axis_c2h_cmpt_user_trig(s_axis_c2h_cmpt_ctrl_user_trig),
    .s_axis_c2h_cmpt_col_idx  (s_axis_c2h_cmpt_ctrl_col_idx),
    .s_axis_c2h_cmpt_err_idx  (s_axis_c2h_cmpt_ctrl_err_idx),

    .tm_dsc_sts_valid (tm_dsc_sts_vld),
    .tm_dsc_sts_qen   (tm_dsc_sts_qen),
    .tm_dsc_sts_byp   (tm_dsc_sts_byp),
    .tm_dsc_sts_dir   (tm_dsc_sts_dir),
    .tm_dsc_sts_mm    (tm_dsc_sts_mm),
    .tm_dsc_sts_error (tm_dsc_sts_error),
    .tm_dsc_sts_qid   (tm_dsc_sts_qid),
    .tm_dsc_sts_avl   (tm_dsc_sts_avl),
    .tm_dsc_sts_qinv  (tm_dsc_sts_qinv),
    .tm_dsc_sts_irq_arm(tm_dsc_sts_irq_arm),
    .tm_dsc_sts_rdy   (tm_dsc_sts_rdy),

    .dsc_crdt_in_valid(dsc_crdt_in_vld),
    .dsc_crdt_in_rdy  (dsc_crdt_in_rdy),
    .dsc_crdt_in_dir  (dsc_crdt_in_dir),
    .dsc_crdt_in_fence(dsc_crdt_in_fence),
    .dsc_crdt_in_qid  (dsc_crdt_in_qid),
    .dsc_crdt_in_crdt (dsc_crdt_in_crdt),


     .qsts_out_op      (qsts_out_op),
     .qsts_out_data    (qsts_out_data),
     .qsts_out_port_id (qsts_out_port_id),
     .qsts_out_qid     (qsts_out_qid),
     .qsts_out_vld     (qsts_out_vld),
     .qsts_out_rdy     (qsts_out_rdy),

    .usr_irq_valid(usr_irq_in_vld),
    .usr_irq_vec  (usr_irq_in_vec),
    .usr_irq_fnc  (usr_irq_in_fnc),
    .usr_irq_ack  (usr_irq_out_ack),
    .usr_irq_fail (usr_irq_out_fail),

    .usr_flr_fnc      (usr_flr_fnc),
    .usr_flr_set      (usr_flr_set),
    .usr_flr_clear    (usr_flr_clr),
    .usr_flr_done_fnc (usr_flr_done_fnc),
    .usr_flr_done_vld (usr_flr_done_vld),
    .user_lnk_up (user_lnk_up)
);





  // XDMA taget application
  qdma_app #(
    .C_M_AXI_ID_WIDTH(C_M_AXI_ID_WIDTH),
    .MAX_DATA_WIDTH(C_DATA_WIDTH),
    .TDEST_BITS(16),
    .TCQ(TCQ)
  ) qdma_app_i (
    .clk(axi_aclk),
    .rst_n(axi_aresetn),
    .soft_reset_n(soft_reset_n),

      // AXI Lite Master Interface connections
      .s_axil_awaddr  (m_axil_awaddr[31:0]),
      .s_axil_awvalid (m_axil_awvalid),
      .s_axil_awready (m_axil_awready),
      .s_axil_wdata   (m_axil_wdata[31:0]),    // block fifo for AXI lite only 31 bits.
      .s_axil_wstrb   (m_axil_wstrb[3:0]),
      .s_axil_wvalid  (m_axil_wvalid),
      .s_axil_wready  (m_axil_wready),
      .s_axil_bresp   (m_axil_bresp),
      .s_axil_bvalid  (m_axil_bvalid),
      .s_axil_bready  (m_axil_bready),
      .s_axil_araddr  (m_axil_araddr[31:0]),
      .s_axil_arvalid (m_axil_arvalid),
      .s_axil_arready (m_axil_arready),
      .s_axil_rdata   (m_axil_rdata),   // block ram for AXI Lite is only 31 bits
      .s_axil_rresp   (m_axil_rresp),
      .s_axil_rvalid  (m_axil_rvalid),
      .s_axil_rready  (m_axil_rready),



      .c2h_byp_out_dsc      (c2h_byp_out_dsc),
      .c2h_byp_out_fmt      (c2h_byp_out_fmt),
      .c2h_byp_out_st_mm    (c2h_byp_out_st_mm),
      .c2h_byp_out_dsc_sz   (c2h_byp_out_dsc_sz),
      .c2h_byp_out_qid      (c2h_byp_out_qid),
      .c2h_byp_out_error    (c2h_byp_out_error),
      .c2h_byp_out_func     (c2h_byp_out_func),
      .c2h_byp_out_cidx     (c2h_byp_out_cidx),
      .c2h_byp_out_port_id  (c2h_byp_out_port_id),
      .c2h_byp_out_pfch_tag (c2h_byp_out_pfch_tag),
      .c2h_byp_out_vld      (c2h_byp_out_vld),
      .c2h_byp_out_rdy      (c2h_byp_out_rdy),

      .c2h_byp_in_mm_radr     (c2h_byp_in_mm_radr),
      .c2h_byp_in_mm_wadr     (c2h_byp_in_mm_wadr),
      .c2h_byp_in_mm_len      (c2h_byp_in_mm_len),
      .c2h_byp_in_mm_mrkr_req (c2h_byp_in_mm_mrkr_req),
      .c2h_byp_in_mm_sdi      (c2h_byp_in_mm_sdi),
      .c2h_byp_in_mm_qid      (c2h_byp_in_mm_qid),
      .c2h_byp_in_mm_error    (c2h_byp_in_mm_error),
      .c2h_byp_in_mm_func     (c2h_byp_in_mm_func),
      .c2h_byp_in_mm_cidx     (c2h_byp_in_mm_cidx),
      .c2h_byp_in_mm_port_id  (c2h_byp_in_mm_port_id),
      .c2h_byp_in_mm_at       (c2h_byp_in_mm_at),
      .c2h_byp_in_mm_no_dma   (c2h_byp_in_mm_no_dma),
      .c2h_byp_in_mm_vld      (c2h_byp_in_mm_vld),
      .c2h_byp_in_mm_rdy      (c2h_byp_in_mm_rdy),

      .c2h_byp_in_st_csh_addr    (c2h_byp_in_st_csh_addr),
      .c2h_byp_in_st_csh_qid     (c2h_byp_in_st_csh_qid),
      .c2h_byp_in_st_csh_error   (c2h_byp_in_st_csh_error),
      .c2h_byp_in_st_csh_func    (c2h_byp_in_st_csh_func),
      .c2h_byp_in_st_csh_port_id (c2h_byp_in_st_csh_port_id),
      .c2h_byp_in_st_csh_pfch_tag(c2h_byp_in_st_csh_pfch_tag),
      .c2h_byp_in_st_csh_at      (c2h_byp_in_st_csh_at),
      .c2h_byp_in_st_csh_vld     (c2h_byp_in_st_csh_vld),
      .c2h_byp_in_st_csh_rdy     (c2h_byp_in_st_csh_rdy),

      .h2c_byp_out_dsc      (h2c_byp_out_dsc),
      .h2c_byp_out_fmt      (h2c_byp_out_fmt),
      .h2c_byp_out_st_mm    (h2c_byp_out_st_mm),
      .h2c_byp_out_dsc_sz   (h2c_byp_out_dsc_sz),
      .h2c_byp_out_qid      (h2c_byp_out_qid),
      .h2c_byp_out_error    (h2c_byp_out_error),
      .h2c_byp_out_func     (h2c_byp_out_func),
      .h2c_byp_out_cidx     (h2c_byp_out_cidx),
      .h2c_byp_out_port_id  (h2c_byp_out_port_id),
      .h2c_byp_out_vld      (h2c_byp_out_vld),
      .h2c_byp_out_rdy      (h2c_byp_out_rdy),

      .h2c_byp_in_mm_radr     (h2c_byp_in_mm_radr),
      .h2c_byp_in_mm_wadr     (h2c_byp_in_mm_wadr),
      .h2c_byp_in_mm_len      (h2c_byp_in_mm_len),
      .h2c_byp_in_mm_mrkr_req (h2c_byp_in_mm_mrkr_req),
      .h2c_byp_in_mm_sdi      (h2c_byp_in_mm_sdi),
      .h2c_byp_in_mm_qid      (h2c_byp_in_mm_qid),
      .h2c_byp_in_mm_error    (h2c_byp_in_mm_error),
      .h2c_byp_in_mm_func     (h2c_byp_in_mm_func),
      .h2c_byp_in_mm_cidx     (h2c_byp_in_mm_cidx),
      .h2c_byp_in_mm_port_id  (h2c_byp_in_mm_port_id),
      .h2c_byp_in_mm_at       (h2c_byp_in_mm_at),
      .h2c_byp_in_mm_no_dma   (h2c_byp_in_mm_no_dma),
      .h2c_byp_in_mm_vld      (h2c_byp_in_mm_vld),
      .h2c_byp_in_mm_rdy      (h2c_byp_in_mm_rdy),

      .h2c_byp_in_st_addr     (h2c_byp_in_st_addr),
      .h2c_byp_in_st_len      (h2c_byp_in_st_len),
      .h2c_byp_in_st_eop      (h2c_byp_in_st_eop),
      .h2c_byp_in_st_sop      (h2c_byp_in_st_sop),
      .h2c_byp_in_st_mrkr_req (h2c_byp_in_st_mrkr_req),
      .h2c_byp_in_st_sdi      (h2c_byp_in_st_sdi),
      .h2c_byp_in_st_qid      (h2c_byp_in_st_qid),
      .h2c_byp_in_st_error    (h2c_byp_in_st_error),
      .h2c_byp_in_st_func     (h2c_byp_in_st_func),
      .h2c_byp_in_st_cidx     (h2c_byp_in_st_cidx),
      .h2c_byp_in_st_port_id  (h2c_byp_in_st_port_id),
      .h2c_byp_in_st_at       (h2c_byp_in_st_at),
      .h2c_byp_in_st_no_dma   (h2c_byp_in_st_no_dma),
      .h2c_byp_in_st_vld      (h2c_byp_in_st_vld),
      .h2c_byp_in_st_rdy      (h2c_byp_in_st_rdy),

      .user_clk(axi_aclk),
      .user_resetn(axi_aresetn),
      .user_lnk_up(user_lnk_up),


    .usr_flr_fnc ( usr_flr_fnc ),
    .usr_flr_set ( usr_flr_set ),
    .usr_flr_clr ( usr_flr_clr) ,
    .usr_flr_done_fnc (usr_flr_done_fnc),
    .usr_flr_done_vld (usr_flr_done_vld),

  .sys_rst_n(sys_rst_n_c),

  .m_axis_h2c_tvalid         (m_axis_h2c_tvalid),
  .m_axis_h2c_tready         (m_axis_h2c_tready),
  .m_axis_h2c_tdata          (m_axis_h2c_tdata),
  .m_axis_h2c_tcrc           (m_axis_h2c_tcrc),
  .m_axis_h2c_tlast          (m_axis_h2c_tlast),
  .m_axis_h2c_tuser_qid      (m_axis_h2c_tuser_qid),
  .m_axis_h2c_tuser_port_id  (m_axis_h2c_tuser_port_id),
  .m_axis_h2c_tuser_err      (m_axis_h2c_tuser_err),
  .m_axis_h2c_tuser_mdata    (m_axis_h2c_tuser_mdata),
  .m_axis_h2c_tuser_mty      (m_axis_h2c_tuser_mty),
  .m_axis_h2c_tuser_zero_byte(m_axis_h2c_tuser_zero_byte),

  .s_axis_c2h_tdata          (s_axis_c2h_tdata ),
  .s_axis_c2h_tcrc           (s_axis_c2h_tcrc  ),
  .s_axis_c2h_ctrl_marker    (s_axis_c2h_ctrl_marker),
  .s_axis_c2h_ctrl_len       (s_axis_c2h_ctrl_len), // c2h_st_len,
  .s_axis_c2h_ctrl_port_id   (s_axis_c2h_ctrl_port_id),
  .s_axis_c2h_ctrl_ecc       (s_axis_c2h_ctrl_ecc),
  .s_axis_c2h_ctrl_qid       (s_axis_c2h_ctrl_qid ), // st_qid,
  .s_axis_c2h_ctrl_has_cmpt  (s_axis_c2h_ctrl_has_cmpt),   // write back is valid
  .s_axis_c2h_tvalid         (s_axis_c2h_tvalid),
  .s_axis_c2h_tready         (s_axis_c2h_tready),
  .s_axis_c2h_tlast          (s_axis_c2h_tlast ),
  .s_axis_c2h_mty            (s_axis_c2h_mty ),  // no empthy bytes at EOP

  .s_axis_c2h_cmpt_tdata               (s_axis_c2h_cmpt_tdata),
  .s_axis_c2h_cmpt_size                (s_axis_c2h_cmpt_size),
  .s_axis_c2h_cmpt_dpar                (s_axis_c2h_cmpt_dpar),
  .s_axis_c2h_cmpt_tvalid              (s_axis_c2h_cmpt_tvalid),
  .s_axis_c2h_cmpt_tready              (s_axis_c2h_cmpt_tready),
  .s_axis_c2h_cmpt_ctrl_qid            (s_axis_c2h_cmpt_ctrl_qid),
  .s_axis_c2h_cmpt_ctrl_cmpt_type      (s_axis_c2h_cmpt_ctrl_cmpt_type),
  .s_axis_c2h_cmpt_ctrl_wait_pld_pkt_id(s_axis_c2h_cmpt_ctrl_wait_pld_pkt_id ),
  .s_axis_c2h_cmpt_ctrl_marker         (s_axis_c2h_cmpt_ctrl_marker),
  .s_axis_c2h_cmpt_ctrl_user_trig      (s_axis_c2h_cmpt_ctrl_user_trig),
  .s_axis_c2h_cmpt_ctrl_col_idx        (s_axis_c2h_cmpt_ctrl_col_idx),
  .s_axis_c2h_cmpt_ctrl_err_idx        (s_axis_c2h_cmpt_ctrl_err_idx),

  .qsts_out_op      (qsts_out_op),
  .qsts_out_data    (qsts_out_data),
  .qsts_out_port_id (qsts_out_port_id),
  .qsts_out_qid     (qsts_out_qid),
  .qsts_out_vld     (qsts_out_vld),
  .qsts_out_rdy     (qsts_out_rdy),

  .usr_irq_in_vld   (usr_irq_in_vld),
  .usr_irq_in_vec   (usr_irq_in_vec),
  .usr_irq_in_fnc   (usr_irq_in_fnc),
  .usr_irq_out_ack  (usr_irq_out_ack),
  .usr_irq_out_fail (usr_irq_out_fail),


  .tm_dsc_sts_vld     (tm_dsc_sts_vld   ),
  .tm_dsc_sts_qen     (tm_dsc_sts_qen   ),
  .tm_dsc_sts_byp     (tm_dsc_sts_byp   ),
  .tm_dsc_sts_dir     (tm_dsc_sts_dir   ),
  .tm_dsc_sts_mm      (tm_dsc_sts_mm    ),
  .tm_dsc_sts_error   (tm_dsc_sts_error ),
  .tm_dsc_sts_qid     (tm_dsc_sts_qid   ),
  .tm_dsc_sts_avl     (tm_dsc_sts_avl   ),
  .tm_dsc_sts_qinv    (tm_dsc_sts_qinv  ),
  .tm_dsc_sts_irq_arm (tm_dsc_sts_irq_arm),
  .tm_dsc_sts_rdy     (tm_dsc_sts_rdy),

  .dsc_crdt_in_vld        (dsc_crdt_in_vld),
  .dsc_crdt_in_rdy        (dsc_crdt_in_rdy),
  .dsc_crdt_in_dir        (dsc_crdt_in_dir),
  .dsc_crdt_in_fence      (dsc_crdt_in_fence),
  .dsc_crdt_in_qid        (dsc_crdt_in_qid),
  .dsc_crdt_in_crdt       (dsc_crdt_in_crdt),

      .sys_clk (sys_clk ),
    .sys_clk_gt(sys_clk_gt),
     // Tx
    .pci_exp_txn(pci_exp_txn ),
    .pci_exp_txp(pci_exp_txp ),

    // Rx
    .pci_exp_rxn(pci_exp_rxn ),
    .pci_exp_rxp(pci_exp_rxp ),

    //******************************************************************
    //New ports for split IP
    //******************************************************************
    .s_axis_rq_tdata      (s_axis_rq_tdata),
    .s_axis_rq_tlast      (s_axis_rq_tlast ),
    .s_axis_rq_tuser      (s_axis_rq_tuser ),
    .s_axis_rq_tkeep      (s_axis_rq_tkeep ),
    .s_axis_rq_tvalid     (s_axis_rq_tvalid),
    .s_axis_rq_tready     (s_axis_rq_tready),
    .m_axis_rc_tdata      (m_axis_rc_tdata ),
    .m_axis_rc_tuser      (m_axis_rc_tuser ),
    .m_axis_rc_tlast      (m_axis_rc_tlast ),
    .m_axis_rc_tkeep      (m_axis_rc_tkeep ),
    .m_axis_rc_tvalid     (m_axis_rc_tvalid),
    .m_axis_rc_tready     (m_axis_rc_tready),
    .m_axis_cq_tdata      (m_axis_cq_tdata ),
    .m_axis_cq_tuser      (m_axis_cq_tuser ),
    .m_axis_cq_tlast      (m_axis_cq_tlast ),
    .m_axis_cq_tkeep      (m_axis_cq_tkeep ),
    .m_axis_cq_tvalid     (m_axis_cq_tvalid),
    .m_axis_cq_tready     (m_axis_cq_tready),
    .s_axis_cc_tdata      (s_axis_cc_tdata ),
    .s_axis_cc_tuser      (s_axis_cc_tuser ),
    .s_axis_cc_tlast      (s_axis_cc_tlast ),
    .s_axis_cc_tkeep      (s_axis_cc_tkeep ),
    .s_axis_cc_tvalid     (s_axis_cc_tvalid),
    .s_axis_cc_tready     (s_axis_cc_tready),
    .phy_rdy_out           (phy_rdy_out),
    .user_reset            (user_reset),
    .pcie_cq_np_req        (pcie_cq_np_req      ),
    .pcie_cq_np_req_count  (pcie_cq_np_req_count),
    .pcie_tfc_nph_av       (pcie_tfc_nph_av     ),
    .pcie_tfc_npd_av       (pcie_tfc_npd_av     ),
    .pcie_rq_seq_num_vld0  (pcie_rq_seq_num_vld0),
    .pcie_rq_seq_num0      (pcie_rq_seq_num0    ),
    .pcie_rq_seq_num_vld1  (pcie_rq_seq_num_vld1),
    .pcie_rq_seq_num1      (pcie_rq_seq_num1    ),
    .cfg_fc_nph            (cfg_fc_nph),
    .cfg_fc_ph             (cfg_fc_ph),
    .cfg_fc_sel            (cfg_fc_sel),
    .cfg_phy_link_down     (cfg_phy_link_down     ),
    .cfg_phy_link_status   (cfg_phy_link_status   ),
    .cfg_negotiated_width  (cfg_negotiated_width  ),
    .cfg_current_speed     (cfg_current_speed     ),
    .cfg_pl_status_change  (cfg_pl_status_change  ),
    .cfg_hot_reset_out     (cfg_hot_reset_out     ),
    .cfg_ds_port_number    (cfg_ds_port_number    ),
    .cfg_ds_bus_number     (cfg_ds_bus_number     ),
    .cfg_bus_number        (cfg_bus_number        ),
    .cfg_ds_device_number  (cfg_ds_device_number  ),
    .cfg_ds_function_number(cfg_ds_function_number),
    .cfg_dsn               (cfg_dsn),
    .cfg_ltssm_state       (cfg_ltssm_state),
    .cfg_function_status   (cfg_function_status),
    .cfg_vf_status         (cfg_vf_status),
    .cfg_max_read_req      (cfg_max_read_req),
    .cfg_max_payload       (cfg_max_payload),
    .cfg_tph_requester_enable(cfg_tph_requester_enable),
    .cfg_vf_tph_requester_enable(cfg_vf_tph_requester_enable),
    .cfg_interrupt_int    (cfg_interrupt_int    ),
    .cfg_interrupt_sent   (cfg_interrupt_sent   ),
    .cfg_interrupt_pending(cfg_interrupt_pending),


      .cfg_interrupt_msi_function_number (cfg_interrupt_msi_function_number),
      .cfg_interrupt_msi_sent(cfg_interrupt_msi_sent),
      .cfg_interrupt_msi_fail(cfg_interrupt_msi_fail),
      .cfg_interrupt_msix_int         (cfg_interrupt_msix_int      ),   // Configuration Interrupt MSI-X Data Valid.

      .cfg_interrupt_msix_data           ( cfg_interrupt_msix_data            ),      // Configuration Interrupt MSI-X Data.
      .cfg_interrupt_msix_address        ( cfg_interrupt_msix_address         ),   // Configuration Interrupt MSI-X Address.
      .cfg_interrupt_msix_enable      (cfg_interrupt_msix_enable   ),   // Configuration Interrupt MSI-X Function Enabled.
      .cfg_interrupt_msix_mask        (cfg_interrupt_msix_mask     ),   // Configuration Interrupt MSI-X Function Mask.
      .cfg_interrupt_msix_vf_enable   (cfg_interrupt_msix_vf_enable),   // Configuration Interrupt MSI-X on VF Enabled.
      .cfg_interrupt_msix_vf_mask     (cfg_interrupt_msix_vf_mask  ),   // Configuration Interrupt MSI-X VF Mask.
      .cfg_interrupt_msix_vec_pending (cfg_interrupt_msix_vec_pending     ),
      .cfg_interrupt_msix_vec_pending_status (cfg_interrupt_msix_vec_pending_status ),
      .cfg_err_cor_out       (cfg_err_cor_out      ),
      .cfg_err_nonfatal_out  (cfg_err_nonfatal_out ),
      .cfg_err_fatal_out     (cfg_err_fatal_out    ),
      .cfg_local_error       (cfg_local_error      ),
      .cfg_msg_received      (cfg_msg_received     ),
      .cfg_msg_received_data (cfg_msg_received_data),
      .cfg_msg_received_type (cfg_msg_received_type),
      .cfg_msg_transmit      (cfg_msg_transmit     ),
      .cfg_msg_transmit_type (cfg_msg_transmit_type),
      .cfg_msg_transmit_data (cfg_msg_transmit_data),
      .cfg_msg_transmit_done (cfg_msg_transmit_done),
      .cfg_req_pm_transition_l23_ready(cfg_req_pm_transition_l23_ready),

     // Config managemnet interface
      .cfg_mgmt_addr       (19'b0 ),
      .cfg_mgmt_write      (1'b0 ),
      .cfg_mgmt_write_data (32'b0 ),
      .cfg_mgmt_byte_enable(4'b0 ),
      .cfg_mgmt_read       (1'b0 ),
      .cfg_mgmt_read_data  (),
      .cfg_mgmt_read_write_done(),
      .cfg_err_uncor_in         (cfg_err_uncor_in),
      .cfg_err_cor_in           (cfg_err_cor_in),
      .cfg_link_training_enable (cfg_link_training_enable),
      .cfg_flr_in_process       (cfg_flr_in_process),
      .cfg_flr_done             (cfg_flr_done),
      .cfg_vf_flr_in_process    (cfg_vf_flr_in_process),
      .cfg_vf_flr_func_num      (8'b0),
      .cfg_vf_flr_done          (1'b0),


      .leds()

  );

endmodule

