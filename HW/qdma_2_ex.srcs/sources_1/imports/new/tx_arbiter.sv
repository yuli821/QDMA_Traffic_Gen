`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/07/2025 02:11:02 PM
// Design Name: 
// Module Name: tx_arbiter
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
module tx_arbiter(
    input logic         clk,
    input logic         rst,

    input logic         hp_valid,
    input logic         hp_empty,
    output logic        hp_advance,
    input logic [5:0]   hp_tcb_addr,
    input tcb_t         hp_tcb,

    input logic         tick,
    input logic         lp_valid,
    input logic [5:0]   lp_tcb_addr,
    input tcb_t         lp_tcb,

    input logic         tx_datapath_ready,
    output logic        tcb_addr_out_valid,
    output logic [5:0]  tcb_addr_out,
    output tcb_t        tcb_out
);

logic [2:0] quota;
logic       grant_hp;
logic       grant_lp;

assign tcb_addr_out_valid = (hp_valid || (lp_valid && tick)) && tx_datapath_ready;

always_comb begin
    grant_hp = '0;
    grant_lp = '0;
    hp_advance      = '0;
    tcb_addr_out    = '0;
    tcb_out         = '0;

    if (tx_datapath_ready) begin
        if (quota > 'd4) begin
            if (lp_valid) begin
                grant_lp = 1'b1;
                tcb_addr_out    = lp_tcb_addr;
                tcb_out         = lp_tcb;
            end
            else if (hp_valid || !hp_empty) begin
                grant_hp        = 1'b1;
                hp_advance      = 1'b1;
                tcb_addr_out    = hp_tcb_addr;
                tcb_out         = hp_tcb;
            end
        end
        else begin
            if (hp_valid || !hp_empty) begin
                grant_hp        = 1'b1;
                hp_advance      = 1'b1;
                tcb_addr_out    = hp_tcb_addr;
                tcb_out         = hp_tcb;
            end
            else if (lp_valid) begin
                grant_lp = 1'b1;
                tcb_addr_out    = lp_tcb_addr;
                tcb_out         = lp_tcb;
            end
        end
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        quota <= '0;
    end
    else begin
        if (quota > 'd4) begin
            if (grant_lp) begin
                quota <= '0;
            end
        end
        else begin
            if (grant_hp) begin
                quota <= quota + 1'b1;
            end
            else if (grant_lp) begin
                quota <= '0;
            end
        end
    end
end

endmodule
