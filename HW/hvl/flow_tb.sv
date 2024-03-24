module flow_tb;

timeunit 1ns;
timeprecision 1ns;

bit clk;
always #2 clk = clk === 1'b0;//4ns per cycle
default clocking tb_clk @(negedge clk); endclocking

localparam DATA_WIDTH = 512;
localparam BEN_WIDTH = DATA_WIDTH/8;
localparam cycles_per_second = 250000000;
localparam TM_DSC_BITS = 16;

logic resetn;
logic [31:0] ctrlreg;
logic s_axis_c2h_tvalid, s_axis_c2h_tready;
logic [BEN_WIDTH-1:0] s_axis_c2h_dpar;
logic [DATA_WIDTH-1-1:0] s_axis_c2h_tdata;
logic s_axis_c2h_tlast;
logic [15:0] num_pkt;
logic [TM_DSC_BITS-1:0] credit_in, credit_perpkt_in, credit_needed;
logic [15:0] buf_count;
logic credit_updt;
logic c2h_end;
logic [15:0] len;
assign len = 4096;

flow #(.C_DATA_WIDTH(512), .FLOW_SPEED(10000000),
.MAX_ETH_FRAME(1518), .DST_MAC(48'h800000000000),
.SRC_MAC(48'h800000000001)) flow_c2h
(
    .axi_aclk(clk),
    .user_resetn(resetn),
    .control_reg(ctrlreg),
    .txr_size    (len),
    .num_pkt     (num_pkt),
    .credit_in   (credit_in),
    .credit_perpkt_in (credit_perpkt_in),
    .credit_needed   (credit_needed),
    .credit_updt (credit_updt),
    .buf_count   (buf_count),
    .c2h_tdata(s_axis_c2h_tdata),
    .c2h_dpar(s_axis_c2h_dpar),
    .c2h_tvalid(s_axis_c2h_tvalid),
    .c2h_tlast(s_axis_c2h_tlast),
    .c2h_end(c2h_end),
    .c2h_tready(s_axis_c2h_tready)
);

task test_flow();
    $display("Start simulation\n");
    ctrlreg <= 32'h2;
    s_axis_c2h_tready <= 1'b1;
    num_pkt <= 16'h20;//32
    buf_count <= 16'h1000;//4kb
    credit_in <= ((len < 16'h1000) ? 1 : len[15:12]+|len[11:0]) * 32;
    credit_needed <= ((len < 16'h1000) ? 1 : len[15:12]+|len[11:0]) * 32;
    credit_perpkt_in <= ((len < 16'h1000) ? 1 : len[15:12]+|len[11:0]);
    credit_updt <= 1'b1;
    ##3;
    credit_updt <= 1'b0;
    ##200000;
    credit_updt <= 1'b1;
    ##1;
    credit_updt <= 1'b0;
    ##(cycles_per_second-200004);
    $display("One second pass\n");
    ctrlreg <= 32'h0;
    s_axis_c2h_tready <= 1'b0;
    ##1;
endtask

initial begin 
    resetn <= 1'b0;
    ##5;
    resetn <= 1'b1;
    ##1; 
    test_flow();
end

endmodule
