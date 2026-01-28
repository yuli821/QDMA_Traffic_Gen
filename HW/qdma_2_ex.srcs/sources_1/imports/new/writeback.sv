`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/09/2025 04:38:45 AM
// Design Name: 
// Module Name: writeback
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
module writeback(
    input logic         clk,
    input logic         rst,

    input logic [63:0]  tcb_alloc,
    input logic         tcb_ready,

    // RX DATAPATH
    input logic         tcb_valid_rx,
    input logic [5:0]   tcb_addr_rx,

    // RTO / TX DATAPATH
    input logic         tcb_valid_tx,
    input logic [5:0]   tcb_addr_tx,
    input tcb_t         tcb_in_tx,

    // TCB PORTS
    // Path to determine whether it was RX or TX
    // Path:
    //      0 - TX
    //      1 - RX
    output logic        path,
    output logic        valid,
    output logic [5:0]  addr
);

logic [5:0] tcb_addr_out_tx;
logic [5:0] tcb_addr_out_rto;

logic fifo_wr_en_tx;
logic fifo_advance_tx;
logic fifo_empty_tx;
logic fifo_valid_tx;

logic fifo_wr_en_rto;
logic fifo_advance_rto;
logic fifo_empty_rto;
logic fifo_valid_rto;

fifo #(
    .WIDTH  (8),
    .DEPTH  (64),
    .FWFT   (1)
) tx_wb_i (
    .clk        (clk),
    .srst       (rst),
    .din        (tcb_addr_tx),
    .wr_en      (fifo_wr_en_tx),
    .rd_en      (fifo_advance_tx),
    .dout       (tcb_addr_out_tx),
    .full       (),
    .empty      (fifo_empty_tx),
    .valid      (fifo_valid_tx),
    .overflow   (),
    .wr_rst_busy(),
    .rd_rst_busy()
);

fifo #(
    .WIDTH  (8),
    .DEPTH  (32),
    .FWFT   (1)
) rto_wb_i (
    .clk        (clk),
    .srst       (rst),
    .din        (tcb_addr_tx),
    .wr_en      (fifo_wr_en_rto),
    .rd_en      (fifo_advance_rto),
    .dout       (tcb_addr_out_rto),
    .full       (),
    .empty      (fifo_empty_rto),
    .valid      (fifo_valid_rto),
    .overflow   (),
    .wr_rst_busy(),
    .rd_rst_busy()
);

always_comb begin
    fifo_wr_en_tx  = '0;
    fifo_wr_en_rto  = '0;

    if (tcb_valid_tx && tcb_in_tx.backoff_exp < 2) begin
        fifo_wr_en_tx   = 1'b1;
    end
    else if (tcb_valid_tx && tcb_in_tx.backoff_exp >= 2) begin
        fifo_wr_en_rto  = 1'b1;
    end
end

always_comb begin
    /*
        Prioritize RX
        RX has entire data, TX only needs few snippets which
        can be stored in a FIFO with little cost.
    */
    fifo_advance_tx     = 1'b0;
    fifo_advance_rto    = 1'b0;
    addr            = '0;
    valid           = '0;
    path            = '0;

    if (tcb_valid_rx) begin
        fifo_advance_tx = 1'b0;
        addr    = tcb_addr_rx;
        valid   = 1'b1;
        path    = 1'b1;
    end
    else if (fifo_valid_rto || ~fifo_empty_rto) begin
        fifo_advance_rto = 1'b1;

        if (tcb_alloc[tcb_addr_out_rto]) begin
            addr            = tcb_addr_out_rto;
            valid           = fifo_valid_rto;
            path            = 1'b0;
        end
        else if (!tcb_alloc[tcb_addr_out_rto]) begin
            // Advance if TCB alloc is invalid but do not write
            valid           = 1'b0;
            path            = 1'b0;
        end
    end
    else if (fifo_valid_tx || ~fifo_empty_tx) begin
        fifo_advance_tx = 1'b1;

        if (tcb_alloc[tcb_addr_out_tx]) begin
            addr            = tcb_addr_out_tx;
            valid           = fifo_valid_tx;
            path            = 1'b0;
        end
        else if (!tcb_alloc[tcb_addr_out_tx]) begin
            // Advance if TCB alloc is invalid but do not write
            valid           = 1'b0;
            path            = 1'b0;
        end
    end
end

endmodule
