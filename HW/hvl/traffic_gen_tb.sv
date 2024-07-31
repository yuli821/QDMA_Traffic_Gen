module traffic_gen_tb;

timeunit 1ns;
timeprecision 1ns;

bit clk;
always #2 clk = clk === 1'b0;//4ns per cycle
default clocking tb_clk @(negedge clk); endclocking

localparam len=512;
localparam ben=len/8;
localparam cycles_per_second = 250000000;
localparam TM_DSC_BITS = 16;
localparam max_frame = 4096;

logic resetn;
logic [31:0] ctrlreg;
logic err1, err2, rx_valid, rx_ready;
logic [ben-1:0] rx_ben;
logic [len-1:0] rx_data;
logic rx_last;
logic [15:0] num_pkt;
logic [TM_DSC_BITS-1:0] credit_in, credit_perpkt_in, credit_needed;
logic credit_updt;
logic rx_end;
logic [15:0] txr_size;
assign txr_size = 4096;

traffic_gen #(.RX_LEN(len), .FLOW_SPEED(1000000000), .MAX_ETH_FRAME(max_frame)) dut(
    .axi_aclk(clk),
    .axi_aresetn(resetn),
    .control_reg(ctrlreg),
    .txr_size(txr_size),
    .num_pkt(num_pkt),
    .credit_in(credit_in),
    .credit_updt(credit_updt),
    .credit_perpkt_in(credit_perpkt_in),
    .credit_needed(credit_needed),
    .rx_ready(rx_ready),
    .rx_valid(rx_valid),
    .rx_ben(rx_ben),
    .rx_data(rx_data),
    .rx_last(rx_last),
    .rx_end(rx_end)
);

task test_generator();
    $display("Start simulation\n");
    ctrlreg <= 32'h2;
    ##2
    ctrlreg <= 32'h0;
    rx_ready <= 1'b1;
    num_pkt <= 16'h20;//32
    credit_in <= 128;
    credit_needed <= (txr_size % max_frame > 0 ? txr_size/max_frame + 1 : txr_size/max_frame) * 32;
    credit_perpkt_in <= (txr_size < max_frame) ? 1 : (txr_size % max_frame > 0 ? txr_size/max_frame + 1 : txr_size/max_frame);
    credit_updt <= 1'b1;
    ##3;
    credit_updt <= 1'b0;
    ##cycles_per_second;
    // $display("One second pass\n");
    // ctrlreg <= 32'h0;
    // rx_ready <= 1'b0;
    ##1;
endtask

initial begin 
    resetn <= 1'b0;
    ##5;
    resetn <= 1'b1;
    ##1; 
    test_generator();
end

endmodule