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


module writeback(
    input logic         clk,
    input logic         rst,

    input logic [63:0]  tcb_alloc,
    input logic         tcb_ready,

    // RX DATAPATH
    input logic         tcb_valid_rx,
    input logic [5:0]   tcb_addr_rx,
    input tcb_t         tcb_in_rx,

    // TX DATAPATH
    input logic         tcb_valid_tx,
    input logic [5:0]   tcb_addr_tx,
    input tcb_t         tcb_in_tx,

    // TCB PORTS
    // Path to determine whether it was RX or TX
    // Path:
    //      0 - TX
    //      1 - RX
    output logic        path,
    output logic        valida,
    output logic [5:0]  addra,
    output logic        wea,
    output tcb_t        tcb_out
);

fifo_generator_2 tx_wb_i (
    .clk        (clk),
    .srst       (rst),

    .full       (),
    .din        (tcb_in_tx_updated),
    .wr_en      (tcb_valid_tx),

    .empty      (fifo_empty),
    .dout       (tcb_fifo_out),
    .rd_en      (fifo_advance),

    .valid      (fifo_valid),
    .overflow   (),
    .wr_rst_busy(),
    .rd_rst_busy()
);

/*
    Update before entering FIFO
    Update may take a few cycles which can be
    hidden by the FIFO
*/
wb_t tcb_in_tx_updated;
wb_t tcb_fifo_out;

logic fifo_empty;
logic fifo_valid;
logic fifo_advance;

always_comb begin
    tcb_in_tx_updated.tcb_addr   = tcb_addr_tx;
    tcb_in_tx_updated.tcb        = tcb_in_tx;
end

always_comb begin
    /*
        Prioritize RX
        RX has entire data, TX only needs few snippets which
        can be stored in a FIFO with little cost.
    */
    fifo_advance    = '0;
    tcb_out         = '0;
    addra           = '0;
    valida          = '0;
    wea             = '0;
    path            = '0;

    if (tcb_valid_rx) begin
        tcb_out = tcb_in_rx;
        addra   = tcb_addr_rx;
        valida  = 1'b1;
        wea     = 1'b1;
        path    = 1'b1;
    end
    else if (fifo_valid && ~fifo_empty) begin
        if (tcb_alloc[tcb_fifo_out.tcb_addr]) begin
            fifo_advance    = 1'b1;
            tcb_out         = tcb_fifo_out.tcb;
            addra           = tcb_fifo_out.tcb_addr;
            valida          = 1'b1;
            wea             = 1'b1;
            path            = 1'b0;
        end
        else if (!tcb_alloc[tcb_fifo_out.tcb_addr]) begin
            // Advance if TCB alloc is invalid but do not write
            fifo_advance    = 1'b1;
            valida          = 1'b0;
            path            = 1'b0;
        end
    end
end

endmodule