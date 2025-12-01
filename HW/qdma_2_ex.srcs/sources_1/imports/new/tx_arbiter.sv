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


module tx_arbiter(
    input logic         clk,
    input logic         rst,

    input logic         hp_valid,
    output logic        hp_advance,
    input logic [4:0]   hp_tcb_addr,

    input logic         tick,
    input logic         lp_valid,
    input logic [4:0]   lp_tcb_addr,

    input logic         tx_datapath_ready,
    output logic        tcb_addr_out_valid,
    output logic [4:0]  tcb_addr_out
);

logic [2:0] quota;
logic       grant_hp;
logic       grant_lp;

assign tcb_addr_out_valid = hp_valid | (lp_valid && tick);

always_comb begin
    grant_hp = '0;
    grant_lp = '0;
    hp_advance      = '0;
    tcb_addr_out    = '0;

    if (quota > 'd4) begin
        if (lp_valid) begin
            grant_lp = 1'b1;
            tcb_addr_out    = lp_tcb_addr;
        end
        else if (hp_valid) begin
            grant_hp        = 1'b1;
            hp_advance      = 1'b1;
            tcb_addr_out    = hp_tcb_addr;
        end
    end
    else begin
        if (hp_valid) begin
            grant_hp        = 1'b1;
            hp_advance      = 1'b1;
            tcb_addr_out    = hp_tcb_addr;
        end
        else if (lp_valid) begin
            grant_lp = 1'b1;
            tcb_addr_out    = lp_tcb_addr;
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
