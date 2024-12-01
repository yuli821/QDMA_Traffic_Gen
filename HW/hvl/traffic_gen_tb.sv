module traffic_gen_tb;

timeunit 1ns;
timeprecision 1ns;

bit clk;
always #2 clk = clk === 1'b0;//4ns per cycle
default clocking tb_clk @(negedge clk); endclocking

localparam len=512;
localparam ben=len/8;
// localparam cycles_per_second = 25000-1060;
localparam TM_DSC_BITS = 16;
localparam max_frame = 4096;

logic resetn;
logic [31:0] ctrlreg;
logic err1, err2, rx_valid, rx_ready;
// logic [ben-1:0] rx_ben;
logic [len-1:0] rx_data;
logic rx_last;
logic [31:0] cycles;
logic [31:0] num_pkt;
logic [TM_DSC_BITS-1:0] credit_in, credit_perpkt_in, credit_needed;
logic credit_updt;
logic rx_end;
logic [15:0] txr_size;
logic [10:0] qid, num_queue, rx_qid;
logic [31:0] cycles_needed;
logic c2h_begin;
logic tm_dsc_sts_vld;
logic tm_dsc_sts_byp;
logic tm_dsc_sts_error;
logic tm_dsc_sts_qen;
logic tm_dsc_sts_dir;
logic tm_dsc_sts_mm;
logic tm_dsc_sts_irq_arm;
logic [10:0] tm_dsc_sts_qid;
logic [15:0] tm_dsc_sts_avl;
logic tm_dsc_sts_qinv;
logic tm_dsc_sts_rdy;
logic c2h_perform;
logic [5:0] hash_val;

assign tm_dsc_sts_qinv = 1'b0;
assign tm_dsc_sts_qen = 1'b1;
assign tm_dsc_sts_dir = 1'b1;
assign tm_dsc_sts_mm = 1'b0;
assign tm_dsc_sts_byp = 1'b0;
assign tm_dsc_sts_error = 1'b0;
assign tm_dsc_sts_irq_arm = 1'b0;

assign rx_qid = 0;
assign txr_size = 256;
assign cycles = 0;
assign qid = 0;
assign num_queue = 11'h2; //2 queues testing
assign num_pkt = 32'h10000;
assign cycles_needed  = (txr_size/64 > cycles ? txr_size/64 : cycles) * num_pkt;

traffic_gen #(.RX_LEN(len),.MAX_ETH_FRAME(max_frame)) dut(
    .*,
    .axi_aclk(clk),
    .axi_aresetn(resetn),
    .control_reg(ctrlreg),
    .txr_size(txr_size),
    .num_pkt(num_pkt),
    // .credit_in(credit_in),
    // .credit_updt(credit_updt),
    // .credit_perpkt_in(credit_perpkt_in),
    // .credit_needed(credit_needed),
    .num_queue(num_queue),
    .qid(qid), 
    .rx_ready(rx_ready),
    .cycles_per_pkt(cycles),
    .rx_valid(rx_valid),
    // .rx_ben(rx_ben),
    .rx_data(rx_data),
    .rx_last(rx_last),
    .rx_end(rx_end),
    .rx_qid(rx_qid)
);

task test_generator();
    $display("Start simulation\n");
    // ctrlreg <= 32'h2;
    c2h_perform <= 1'b1;
    ##2
    ctrlreg <= 32'h0;
    rx_ready <= 1'b1;
    tm_dsc_sts_qid <= 0;
    tm_dsc_sts_avl <= num_pkt >> 1;
    tm_dsc_sts_vld <= 1'b1;
    ##1;
    tm_dsc_sts_vld <= 1'b0;
    ##12;
    tm_dsc_sts_qid <= 1;
    tm_dsc_sts_avl <= num_pkt >> 1;
    tm_dsc_sts_vld <= 1'b1;
    ##1;
    tm_dsc_sts_vld <= 1'b0;
    ##11;
    rx_ready <= 1'b0;
    ##20;
    rx_ready <= 1'b1;
    // credit_updt <= 1'b0;
    // credit_in <= 1024;
    // credit_updt<= 1'b1;
    // ##1;
    // credit_updt <= 1'b0;
    // ##cycles_per_second;
    // $display("One second pass\n");
    // ctrlreg <= 32'h0;
    // rx_ready <= 1'b0;
    ##cycles_needed
    c2h_perform <= 1'b0;
    $display("Simulation ends");
endtask

initial begin 
    resetn <= 1'b0;
    ##5
    resetn <= 1'b1;
    ##1
    test_generator();
end

endmodule