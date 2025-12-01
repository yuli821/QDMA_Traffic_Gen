`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/05/2025 12:31:39 AM
// Design Name: 
// Module Name: rto
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

import packages::*;
module rto(
    input logic         clk,
    input logic         rst,

    input logic         write,
    // input logic         tcb_addr_in_valid,
    input logic [5:0]   tcb_addr_in,
    input tcb_t         tcb_data_in,

    input logic         tx_datapath_ready,
    output logic        tcb_addr_out_valid,
    output logic [5:0]  tcb_addr_out,
    output tcb_t        tcb_data_out
);

fifo_generator_0 priority_queue (
    .clk        (clk),
    .srst       (rst),
    
    .full       (), // TODO: If full allocate in TIMER WHEEL
    .din        (hp_din),
    .wr_en      (hp_wr_en),

    .valid      (hp_valid),
    .empty      (),
    .dout       (hp_dout),
    .rd_en      (hp_advance),

    .wr_rst_busy(),
    .rd_rst_busy()
);

tx_arbiter tx_arbiter_i (
    .clk            (clk),
    .rst            (rst),

    .hp_valid       (hp_valid),
    .hp_advance     (hp_advance),
    .hp_tcb_addr    (hp_dout),

    .tick           (tick),
    .lp_valid       (timer_wheel_val[9]),
    .lp_tcb_addr    (timer_wheel_val[4:0]),

    .tx_datapath_ready  (tx_datapath_ready),
    .tcb_addr_out_valid (tcb_addr_out_valid),
    .tcb_addr_out       (tcb_addr_out)
);

/*
    TODO: Use GTREFCLK or external PLL with low jitter for accurate time

    Assume 250 MHz clk for now
    - 1 tick = 1ns -> 250 cycles
*/
// logic [7:0]     us_tick;
logic [3:0]     us_tick;
logic           tick;
logic [9:0]     timer_wheel [1024];
logic [9:0]     timer_wheel_val;
logic [9:0]     slot_idx;
logic [9:0]     rd_ptr;

logic [31:0]    hp_din;
logic [31:0]    hp_dout;
logic           hp_wr_en;

logic           hp_valid;
logic           hp_advance;

assign timer_wheel_val = timer_wheel[rd_ptr];

always_comb begin
    hp_din      = '0;
    hp_wr_en    = '0;

    slot_idx = rd_ptr + 1'b1;

    if (write) begin
        // WRITE TO HIGH PRIORITY FIFO
        if (tcb_data_in.next_send_time == '0) begin
            hp_din   = {'0, tcb_data_in.csr_curr, tcb_addr_in};
            hp_wr_en = 1'b1;
        end
        // WRITE TO TIMER WHEEL
        if (tcb_data_in.next_send_time != '0) begin
            slot_idx = rd_ptr + (tcb_data_in.next_send_time << tcb_data_in.backoff_exp);
        end
    end
end

always_ff @(posedge clk) begin
    us_tick <= (rst) ? '0 : us_tick + 1'b1;
    tick    <= &us_tick;
end

// READ LOGIC
always_ff @(posedge clk) begin
    if (rst) begin
        rd_ptr  <= '0;
    end
    else if (tick) begin
        rd_ptr  <= rd_ptr + 1'b1;
        // Invalidate Previous Index
        timer_wheel[rd_ptr] <= '0;
    end
end

// WRITE LOGIC
always_ff @(posedge clk) begin
    if (rst) begin
        for (int i = 0; i < 1024; i++) begin
            timer_wheel[i] <= '0;
        end
    end
    else if (write) begin
        if (tcb_data_in.next_send_time != '0) begin
            // If timer wheel is already allocated
            if (timer_wheel[slot_idx] != '0) begin
                timer_wheel[slot_idx + 1'b1][4:0]  <= tcb_addr_in;
                timer_wheel[slot_idx + 1'b1][8:5]  <= tcb_data_in.csr_curr;
                timer_wheel[slot_idx + 1'b1][9]    <= 1'b1;
            end
            else begin
                timer_wheel[slot_idx][4:0]  <= tcb_addr_in;
                timer_wheel[slot_idx][8:5]  <= tcb_data_in.csr_curr;
                timer_wheel[slot_idx][9]    <= 1'b1;
            end
        end
    end
end

endmodule