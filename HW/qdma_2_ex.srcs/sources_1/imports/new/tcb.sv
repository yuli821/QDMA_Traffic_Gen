`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/01/2025 11:44:01 PM
// Design Name: 
// Module Name: tcb
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
module tcb(
    input logic             clk,
    input logic             rst,
    
    output logic            readya,
    input logic             valida,
    input logic [5:0]       addra,
    input logic             wea,
    input tcb_t             dina,
    output tcb_t            douta,
    output logic            douta_valid,

    input logic             validb,
    input logic [5:0]       addrb,
    input logic             web,
    input tcb_t             dinb,
    output tcb_t            doutb,
    output logic            doutb_valid
);

blk_mem_gen_1 tcb (
    .clka   (clk),
    .addra  (addra),
    .wea    (wea),
    .dina   (unpack_a),
    .douta  (pack_a),

    .clkb   (clk),
    .addrb  (addrb),
    .web    (web),
    .dinb   (dinb),
    .doutb  (doutb)
);

/*
    On ingress of invalid data/packet
    -> if RX is not RST, immediately respond with RST
    -> invalidate TCB entry
    -> invalidate cache entry

    On egress
    -> Update TCB state to next state
*/

logic [1023:0]  unpack_a;
logic [1023:0]  pack_a;

assign unpack_a = {'0, dina};
assign douta    = pack_a;
assign readya   = ~(valida || douta_valid);

always_ff @(posedge clk) begin
    douta_valid     <= valida;
    doutb_valid     <= validb;
end

endmodule
