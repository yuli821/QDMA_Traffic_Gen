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

// blk_mem_gen_0 cache_mem (
//     .*
// );

xpm_memory_tdpram #(
    .ADDR_WIDTH_A        ($clog2(DEPTH)),
    .ADDR_WIDTH_B        ($clog2(DEPTH)),
    .AUTO_SLEEP_TIME     (0),
    .BYTE_WRITE_WIDTH_A  (WIDTH),
    .BYTE_WRITE_WIDTH_B  (WIDTH),
    .CLOCKING_MODE       ("independent_clock"),
    .ECC_MODE            ("no_ecc"),
    .MEMORY_INIT_FILE    ("none"),
    .MEMORY_INIT_PARAM   ("0"),
    .MEMORY_OPTIMIZATION ("true"),
    .MEMORY_PRIMITIVE    ("block"),
    .MEMORY_SIZE         (WIDTH * DEPTH),
    .MESSAGE_CONTROL     (0),
    .READ_DATA_WIDTH_A   (WIDTH),
    .READ_DATA_WIDTH_B   (WIDTH),
    .READ_LATENCY_A      (1),
    .READ_LATENCY_B      (1),
    .READ_RESET_VALUE_A  ("0"),
    .READ_RESET_VALUE_B  ("0"),
    .RST_MODE_A          ("SYNC"),
    .RST_MODE_B          ("SYNC"),
    .SIM_ASSERT_CHK      (0),
    .USE_MEM_INIT        (0),
    .WAKEUP_TIME         ("disable_sleep"),
    .WRITE_DATA_WIDTH_A  (WIDTH),
    .WRITE_DATA_WIDTH_B  (WIDTH),
    .WRITE_MODE_A        ("write_first"),
    .WRITE_MODE_B        ("write_first")
) cache_mem (
    .clka           (clka),
    .clkb           (clkb),
    .ena            (1'b1),
    .enb            (1'b1),
    .addra          (addra),
    .addrb          (addrb),
    .dina           (dina),
    .dinb           (dinb),
    .wea            (wea),
    .web            (web),
    .douta          (douta),
    .doutb          (doutb),
    .regcea         (1'b1),
    .regceb         (1'b1),
    .rsta           (1'b0),
    .rstb           (1'b0),
    .sleep          (1'b0)
);

endmodule
