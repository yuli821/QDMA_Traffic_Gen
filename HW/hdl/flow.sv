`timescale 1ps / 1ps
module flow #(
    parameter C_DATA_WIDTH                = 512,
    parameter TM_DSC_BITS = 16
)
(
    input logic            axi_aclk,
    input logic          user_resetn,
    input logic [31:0]   control_reg,
    input logic [15:0] txr_size,
    input logic [10:0] num_pkt,
    input logic [TM_DSC_BITS-1:0] credit_in,
    input logic credit_updt,
    input logic [TM_DSC_BITS-1:0] credit_perpkt_in,
    input logic [TM_DSC_BITS-1:0] credit_needed,
    input logic [15:0] buf_count,
    output logic [C_DATA_WIDTH-1 : 0] c2h_tdata,
    output logic [C_DATA_WIDTH/8 - 1 : 0] c2h_dpar,
    output c2h_tvalid,
    output c2h_tlast,
    output c2h_end,
    input c2h_tready
);
logic start_c2h, control_reg_1_d;
logic [C_DATA_WIDTH-1:0] tg_data;
logic [C_DATA_WIDTH/8 -1:0] tg_dpar;
logic tg_valid;
logic tg_last;
logic tg_ready;
logic fifo_almost_ety, fifo_almost_full;
logic [11:0] wr_data_count_axis, data_count_axis;
logic err1, err2;
logic c2h_end;

traffic_gen #(.RX_LEN(C_DATA_WIDTH), .MAX_ETH_FRAME(2048), .TM_DSC_BITS(TM_DSC_BITS)) dut(
    .axi_aclk(axi_aclk),
    .axi_aresetn(axi_aresetn),
    .control_reg(control_reg),
    .txr_size(txr_size),
    .num_pkt(num_pkt),
    .credit_in(credit_in),
    .credit_updt(credit_updt),
    .credit_perpkt_in(credit_perpkt_in),
    .credit_needed(credit_needed),
    .rx_ready(tg_ready),
    .flow_speed_idx(2),
    .rx_valid(tg_valid),
    .rx_ben(tg_dpar),
    .rx_data(tg_data),
    .rx_last(tg_last),
    .rx_end(c2h_end)
);

design_2_wrapper fifo(   
    .M_AXIS_tdata(c2h_tdata),
    .M_AXIS_tdest(), //
    .M_AXIS_tid(), //
    .M_AXIS_tkeep(c2h_dpar), 
    .M_AXIS_tlast(c2h_tlast),
    .M_AXIS_tready(c2h_tready),
    .M_AXIS_tstrb(), //
    .M_AXIS_tuser(), //
    .M_AXIS_tvalid(c2h_tvalid),
    .S_AXIS_tdata(tg_data),
    .S_AXIS_tdest(4'b0), //
    .S_AXIS_tid(8'b0),  //
    .S_AXIS_tkeep(tg_dpar),
    .S_AXIS_tlast(tg_last),
    .S_AXIS_tready(tg_ready),
    .S_AXIS_tstrb(64'b0), //
    .S_AXIS_tuser(4'b0), //
    .S_AXIS_tvalid(tg_valid),
    .wr_data_count_axis(wr_data_count_axis),
    .data_count_axis(data_count_axis),
    .almost_empty_axis(fifo_almost_ety),
    .almost_full_axis(fifo_almost_full),
    .s_aclk(axi_aclk),
    .s_aresetn(user_resetn)
);

endmodule
