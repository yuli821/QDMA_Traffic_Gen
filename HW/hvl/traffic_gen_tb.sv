module traffic_gen_tb;

timeunit 1ns;
timeprecision 1ns;

bit clk;
always #2 clk = clk === 1'b0;//4ns per cycle
default clocking tb_clk @(negedge clk); endclocking

localparam len=128;
localparam ben=128/8;
localparam cycles_per_second = 250000000;

logic resetn;
logic [31:0] ctrlreg;
logic err, rx_valid;
logic [ben-1:0] rx_ben;
logic [len-1:0] rx_data;
logic rx_last;


traffic_gen #(.RX_LEN(len)) dut(
    .user_clk(clk),
    .user_resetn(resetn),
    .control_reg(ctrlreg),
    .error(err),
    .rx_valid(rx_valid),
    .rx_ben(rx_ben),
    .rx_data(rx_data),
    .rx_last(rx_last)
);

task test_generator();
    $display("Start simulation\n");
    ctrlreg <= 32'h2;
    ##cycles_per_second;
    $display("One second pass\n");
    ctrlreg <= 32'h0;
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