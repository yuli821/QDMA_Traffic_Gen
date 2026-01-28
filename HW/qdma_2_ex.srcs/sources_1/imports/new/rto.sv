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
module rto #(
    parameter int       RTO_SZ = 128
) (
    input logic         clk,
    input logic         rst,

    input logic         cancel_rto,
    input logic         write,
    // input logic         tcb_addr_in_valid,
    input logic [5:0]   tcb_addr_in,
    input tcb_t         tcb_data_in,

    input logic         tx_datapath_ready,
    output logic        tcb_addr_out_valid,
    output logic [5:0]  tcb_addr_out,
    output tcb_t        tcb_out
);

/*
    Assume 250 MHz clk for now
    - 1 tick = 1ns -> 250 cycles
*/
typedef struct packed {
    logic [5:0] addr;
    tcb_t       tcb;
} rto_entry_t;

localparam int TW_WIDTH = 1 + $bits(rto_entry_t);
localparam int MAP_W    = $clog2(RTO_SZ);

logic [5:0]    us_tick;
// logic [23:0]    us_tick;
logic           tick;
logic [TW_WIDTH-1:0]    timer_wheel [RTO_SZ];
logic [TW_WIDTH-1:0]    timer_wheel_val;
logic                   timer_wheel_valid;
rto_entry_t             timer_wheel_entry;
logic [$clog2(RTO_SZ)-1:0]    slot_idx;
logic [$clog2(RTO_SZ)-1:0]    rd_ptr;

rto_entry_t     hp_din;
rto_entry_t     hp_dout;
logic           hp_wr_en;
logic           hp_valid;
logic           hp_empty;
logic           hp_advance;

// VALID | SLOT INDEX
// Indexed by TCB ADDRESS
logic [MAP_W:0]    mapping [64];

assign timer_wheel_val    = timer_wheel[rd_ptr];
assign timer_wheel_valid  = timer_wheel_val[TW_WIDTH-1];
assign timer_wheel_entry  = timer_wheel_val[TW_WIDTH-2:0];

fifo #(
    .WIDTH  ($bits(rto_entry_t)),
    .DEPTH  (32),
    .FWFT   (1)
) priority_queue (
    .clk        (clk),
    .srst       (rst),
    .din        (hp_din),
    .wr_en      (hp_wr_en),
    .rd_en      (hp_advance && tx_datapath_ready),
    .dout       (hp_dout),
    .full       (),
    .empty      (hp_empty),
    .valid      (hp_valid),
    .overflow   (),
    .wr_rst_busy(),
    .rd_rst_busy()
);

tx_arbiter tx_arbiter_i (
    .clk            (clk),
    .rst            (rst),

    .hp_valid       (hp_valid),
    .hp_empty       (hp_empty),
    .hp_advance     (hp_advance),
    .hp_tcb_addr    (hp_dout.addr),
    .hp_tcb         (hp_dout.tcb),

    .tick           (tick),
    .lp_valid       (timer_wheel_valid),
    .lp_tcb_addr    (timer_wheel_entry.addr),
    .lp_tcb         (timer_wheel_entry.tcb),

    .tx_datapath_ready  (tx_datapath_ready),
    .tcb_addr_out_valid (tcb_addr_out_valid),
    .tcb_addr_out       (tcb_addr_out),
    .tcb_out            (tcb_out)
);

always_comb begin
    hp_din.addr = '0;
    hp_din.tcb  = '0;
    hp_wr_en    = '0;

    slot_idx = rd_ptr + 1'b1;
    
    if (cancel_rto) begin
        if (mapping[tcb_addr_in][MAP_W]) begin
            slot_idx = mapping[tcb_addr_in][MAP_W-1:0];
        end
    end
    else if (write) begin
        // WRITE TO HIGH PRIORITY FIFO
        if (tcb_data_in.next_send_time == '0 || tcb_data_in.csr_curr == CSR_RST) begin
            hp_din.addr = tcb_addr_in;
            hp_din.tcb  = tcb_data_in;
            hp_wr_en = 1'b1;
        end
        // WRITE TO TIMER WHEEL
        if (tcb_data_in.next_send_time != '0 && tcb_data_in.csr_curr != CSR_RST) begin
            slot_idx = rd_ptr + (tcb_data_in.next_send_time << tcb_data_in.backoff_exp);
        end
    end
end

always_ff @(posedge clk) begin
    tick    <= &us_tick;

    if (rst) begin
        us_tick <= '0;
    end
    // else if (tx_datapath_ready) begin
    else begin
        us_tick <= us_tick + 1'b1;;
    end
end

// -------------------------------------------------------------- READ LOGIC
always_ff @(posedge clk) begin
    if (rst) begin
        rd_ptr  <= '0;
    end
    else if (tick) begin
        rd_ptr  <= rd_ptr + 1'b1;
    end
end

// -------------------------------------------------------------- WRITE LOGIC
// -------------------------------------------------------------- CANCEL LOGIC
always_ff @(posedge clk) begin
    if (rst) begin
        mapping     <= '{default : 0};
        timer_wheel <= '{default : 0};
    end
    else if (cancel_rto && mapping[tcb_addr_in][MAP_W]) begin
        mapping[tcb_addr_in][MAP_W] <= 1'b0;
        timer_wheel[slot_idx]   <= '0;
    end
    else if (write) begin
        if (tcb_data_in.next_send_time != '0 && tcb_data_in.csr_curr != CSR_RST) begin
            // If timer wheel is already allocated
            if (timer_wheel[slot_idx] != '0) begin
                mapping[tcb_addr_in] <= {1'b1, slot_idx + 1'b1};

                timer_wheel[slot_idx + 1'b1][TW_WIDTH-1]   <= 1'b1;
                timer_wheel[slot_idx + 1'b1][TW_WIDTH-2:0] <= {tcb_addr_in, tcb_data_in};
            end
            else begin
                mapping[tcb_addr_in] <= {1'b1, slot_idx};

                timer_wheel[slot_idx][TW_WIDTH-1]   <= 1'b1;
                timer_wheel[slot_idx][TW_WIDTH-2:0] <= {tcb_addr_in, tcb_data_in};
            end
        end
    end

    if (tick) begin
        // Invalidate Previous Index
        timer_wheel[rd_ptr] <= '0;
    end
end

endmodule
