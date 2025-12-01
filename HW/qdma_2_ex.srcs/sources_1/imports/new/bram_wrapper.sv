`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/24/2025 08:23:45 AM
// Design Name: 
// Module Name: bram_wrapper
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


module bram_wrapper #(
    parameter WIDTH = 32,
    parameter DEPTH = 16
)( 
    input logic                     clka,
    input logic                     wea,
    input logic [$clog2(DEPTH)-1:0] addra,
    input logic [WIDTH-1:0]         dina,
    output logic [WIDTH-1:0]        douta,

    input logic                     clkb,
    input logic                     web,
    input logic [$clog2(DEPTH)-1:0] addrb,
    input logic [WIDTH-1:0]         dinb,
    output logic [WIDTH-1:0]        doutb
);

blk_mem_gen_0 cache_mem (
    .*
);

endmodule
