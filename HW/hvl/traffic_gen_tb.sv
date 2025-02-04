module traffic_gen_tb;

timeunit 1ns;
timeprecision 1ns;

bit clk;
always #2 clk = clk === 1'b0;//4ns per cycle
default clocking tb_clk @(negedge clk); endclocking

localparam len=512;
localparam ben=len/8;
localparam cycles_per_second = 25000;
localparam TM_DSC_BITS = 16;
localparam max_frame = 4096;
localparam cmpt_size = 512;

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
logic c2h_perform, c2h_perform_d1, rx_begin;
logic [31:0] hash_val;
logic [79:0] timestamp;
logic perform_begin;
wire back_pres;
logic qid_fifo_full, empty, cmpt_ready;
int cmpt_count;
assign empty = cmpt_count == 0;
assign qid_fifo_full = cmpt_count == cmpt_size;
assign back_pres = 1'b1;
always_ff @(posedge clk) begin 
    c2h_perform_d1 <= c2h_perform;
end
assign perform_begin = c2h_perform & ~c2h_perform_d1;

always_ff @(posedge clk) begin 
    if (~resetn || perform_begin) timestamp <= 0;
    else timestamp += 1;
end

always_ff @(posedge clk) begin 
    if (~resetn) cmpt_count <= 0;
    else if (rx_begin && ~empty && cmpt_ready) cmpt_count <= cmpt_count;
    else if (rx_begin) cmpt_count <= (cmpt_count == cmpt_size) ? cmpt_size : cmpt_count+1;
    else if (~empty && cmpt_ready) cmpt_count <= cmpt_count-1;
end

assign tm_dsc_sts_qinv = 1'b0;
assign tm_dsc_sts_qen = 1'b1;
assign tm_dsc_sts_dir = 1'b1;
assign tm_dsc_sts_mm = 1'b0;
assign tm_dsc_sts_byp = 1'b0;
assign tm_dsc_sts_error = 1'b0;
assign tm_dsc_sts_irq_arm = 1'b0;

// assign rx_qid = 0;
assign txr_size = 128;
assign cycles = 0;
assign qid = 0;
assign num_queue = 11'h4; //4 queues testing
assign num_pkt = 32'h2000;
assign cycles_needed  = (txr_size/64 > cycles ? txr_size/64 : cycles) * num_pkt;
logic [31:0] indir_table [128]; 
always_comb begin
    rx_qid = indir_table[hash_val[6:0]];
end

reg [15:0] 	       bp_lfsr;
wire 	       bp_lfsr_net;
assign bp_lfsr_net = bp_lfsr[0] ^ bp_lfsr[2] ^ bp_lfsr[3] ^ bp_lfsr[5];

always @(posedge clk) begin
    if (~resetn) begin
        bp_lfsr <= 16'h00ff; // initial seed for back pressure LFSR
        rx_ready <= 1'b1;
    end
    else begin
        bp_lfsr <= {bp_lfsr_net,bp_lfsr[15:1]};
        rx_ready <= (back_pres && bp_lfsr[0]) ? 1'b0 : 1'b1; // some random back pressure
    end
end
// assign rx_ready = 1'b1;
traffic_gen #(.RX_LEN(len),.MAX_ETH_FRAME(max_frame)) dut(
    .*,
    .axi_aclk(clk),
    .axi_aresetn(resetn),
    .control_reg(ctrlreg),
    .txr_size(txr_size),
    // .num_pkt(num_pkt),
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
    .rx_qid(rx_qid)
);

logic [9:0] target, target_cmpt, counter, counter_cmpt;

always_ff @(posedge clk) begin 
    if (~resetn) begin 
        cmpt_ready <= 1'b0;
        target_cmpt = 0;
        target_cmpt[3:0] = $urandom;
        if (target_cmpt == 0) target_cmpt = 1023;
        counter_cmpt <= 0;
    end else if (~empty && (counter_cmpt == target_cmpt)) begin 
        cmpt_ready <= 1'b1;
        counter_cmpt <= 0;
        target_cmpt = 0;
        target_cmpt[3:0] = $urandom;
        if (target_cmpt==0) target_cmpt = 1023;
    end else begin 
        cmpt_ready <= 1'b0;
        counter_cmpt <= counter_cmpt + 1;
    end
end

always_ff @(posedge clk) begin 
    if (~resetn) begin 
        target = $urandom;
        if (target==0) target = 1023;
        counter <= 0;
        tm_dsc_sts_qid <= 3;
        tm_dsc_sts_avl <= 0;
        tm_dsc_sts_vld <= 0;
    end
    else if ((counter == target) & tm_dsc_sts_rdy) begin
        tm_dsc_sts_qid <= (tm_dsc_sts_qid + 1)%num_queue;
        tm_dsc_sts_avl = $urandom;
        tm_dsc_sts_avl = tm_dsc_sts_avl>>7;
        tm_dsc_sts_vld <= 1'b1;
        counter <= 0;
        target <= $urandom;
        if (target==0) target = 1023;
    end else begin 
        counter++;
        tm_dsc_sts_vld <= 0;
    end
end

task test_generator();
    $display("Start simulation\n");
    // ctrlreg <= 32'h2;
    // rx_ready <= 1'b1;
    @(posedge clk iff(tm_dsc_sts_rdy == 1'b1));
    tm_dsc_sts_qid <= 0;
    tm_dsc_sts_avl <= 1024;
    tm_dsc_sts_vld <= 1'b1;
    ##1;
    tm_dsc_sts_vld <= 1'b0;
    tm_dsc_sts_avl <= 0;
    // ##1;
    @(posedge clk iff(tm_dsc_sts_rdy == 1'b1));
    tm_dsc_sts_vld <= 1'b1;
    tm_dsc_sts_qid <= 1;
    tm_dsc_sts_avl <= 1024;
    ##1;
    tm_dsc_sts_vld <= 1'b0;
    tm_dsc_sts_avl <= 0;
    tm_dsc_sts_qid <= 0;
    // ##1;
    @(posedge clk iff(tm_dsc_sts_rdy == 1'b1));
    tm_dsc_sts_vld <= 1'b1;
    tm_dsc_sts_qid <= 2;
    tm_dsc_sts_avl <= 1024;
    ##1;
    tm_dsc_sts_vld <= 1'b0;
    tm_dsc_sts_avl <= 0;
    tm_dsc_sts_qid <= 0;
    // ##1;
    @(posedge clk iff(tm_dsc_sts_rdy == 1'b1));
    tm_dsc_sts_vld <= 1'b1;
    tm_dsc_sts_qid <= 3;
    tm_dsc_sts_avl <= 1024;
    ##1;
    tm_dsc_sts_vld <= 1'b0;
    tm_dsc_sts_avl <= 0;
    tm_dsc_sts_qid <= 0;
    ##1;
    c2h_perform <= 1'b1;
    ##(cycles_needed/4 + 1);
    // rx_ready <= 1'b1;
    @(posedge clk iff(tm_dsc_sts_rdy == 1'b1));
    tm_dsc_sts_qid <= 0;
    tm_dsc_sts_avl <= 1024;
    tm_dsc_sts_vld <= 1'b1;
    ##1;
    tm_dsc_sts_vld <= 1'b0;
    // ##1;
    @(posedge clk iff(tm_dsc_sts_rdy == 1'b1));
    tm_dsc_sts_vld <= 1'b1;
    tm_dsc_sts_qid <= 1;
    ##1;
    tm_dsc_sts_vld <= 1'b0;
    // ##1;
    @(posedge clk iff(tm_dsc_sts_rdy == 1'b1));
    tm_dsc_sts_vld <= 1'b1;
    tm_dsc_sts_qid <= 2;
    ##1;
    tm_dsc_sts_vld <= 1'b0;
    // ##1;
    @(posedge clk iff(tm_dsc_sts_rdy == 1'b1));
    tm_dsc_sts_vld <= 1'b1;
    tm_dsc_sts_qid <= 3;
    ##1;
    tm_dsc_sts_vld <= 1'b0;
    ##(cycles_needed/4);
    // rx_ready <= 1'b1;
    @(posedge clk iff(tm_dsc_sts_rdy == 1'b1));
    tm_dsc_sts_qid <= 0;
    tm_dsc_sts_avl <= 1024;
    tm_dsc_sts_vld <= 1'b1;
    ##1;
    tm_dsc_sts_vld <= 1'b0;
    // ##1;
    @(posedge clk iff(tm_dsc_sts_rdy == 1'b1));
    tm_dsc_sts_vld <= 1'b1;
    tm_dsc_sts_qid <= 1;
    ##1;
    tm_dsc_sts_vld <= 1'b0;
    // ##1;
    @(posedge clk iff(tm_dsc_sts_rdy == 1'b1));
    tm_dsc_sts_vld <= 1'b1;
    tm_dsc_sts_qid <= 2;
    ##1;
    tm_dsc_sts_vld <= 1'b0;
    // ##1;
    @(posedge clk iff(tm_dsc_sts_rdy == 1'b1));
    tm_dsc_sts_vld <= 1'b1;
    tm_dsc_sts_qid <= 3;
    ##1;
    tm_dsc_sts_vld <= 1'b0;
    // ##1;
    ##(cycles_needed/4);
    // rx_ready <= 1'b1;
    tm_dsc_sts_qid <= 0;
    tm_dsc_sts_avl <= 1024;
    tm_dsc_sts_vld <= 1'b1;
    ##1;
    tm_dsc_sts_vld <= 1'b0;
    // ##1;
    @(posedge clk iff(tm_dsc_sts_rdy == 1'b1));
    tm_dsc_sts_vld <= 1'b1;
    tm_dsc_sts_qid <= 1;
    ##1;
    tm_dsc_sts_vld <= 1'b0;
    // ##1;
    @(posedge clk iff(tm_dsc_sts_rdy == 1'b1));
    tm_dsc_sts_vld <= 1'b1;
    tm_dsc_sts_qid <= 2;
    ##1;
    tm_dsc_sts_vld <= 1'b0;
    // ##1;
    @(posedge clk iff(tm_dsc_sts_rdy == 1'b1));
    tm_dsc_sts_vld <= 1'b1;
    tm_dsc_sts_qid <= 3;
    ##1;
    tm_dsc_sts_vld <= 1'b0;
    // ##1;
    ##(cycles_needed/4);
    ##11;
    rx_ready <= 1'b0;
    ##20;
    rx_ready <= 1'b1;
    credit_updt <= 1'b0;
    credit_in <= 1024;
    credit_updt<= 1'b1;
    ##1;
    credit_updt <= 1'b0;
    ##cycles_per_second;
    $display("One second pass\n");
    ctrlreg <= 32'h0;
    rx_ready <= 1'b0;
    c2h_perform <= 1'b0;
    $display("Simulation ends");
endtask

initial begin 
    for (int i = 0 ; i < 128 ; i++) begin 
        indir_table[i] = i % num_queue;
    end
    resetn <= 1'b0;
    ##5
    resetn <= 1'b1;
    ##1
    // test_generator();
    // ##1
    c2h_perform <= 1'b1;
    ##250000
    c2h_perform <= 1'b0;
end

endmodule