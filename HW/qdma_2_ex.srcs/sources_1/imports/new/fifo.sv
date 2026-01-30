`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 12/31/2025 01:58:00 AM
// Design Name:
// Module Name: fifo
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//   Common-clock FIFO wrapper using XPM. Supports FWFT or standard read mode.
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module fifo #(
    parameter int WIDTH = 16,
    parameter int DEPTH = 16,
    parameter int FWFT  = 0
) (
    input  logic                 clk,
    input  logic                 srst,
    input  logic [WIDTH-1:0]     din,
    input  logic                 wr_en,
    input  logic                 rd_en,
    output logic [WIDTH-1:0]     dout,
    output logic                 full,
    output logic                 empty,
    output logic                 valid,
    // UNUSED
    output logic                 overflow,
    output logic                 wr_rst_busy,
    output logic                 rd_rst_busy
);

localparam string READ_MODE   = (FWFT != 0) ? "fwft" : "std";
localparam int    READ_LATENCY = (FWFT != 0) ? 0 : 1;

logic [READ_LATENCY:0] rd_shift;

xpm_fifo_sync #(
    .FIFO_WRITE_DEPTH   (DEPTH),
    .READ_DATA_WIDTH    (WIDTH),
    .WRITE_DATA_WIDTH   (WIDTH),
    .READ_MODE          (READ_MODE),
    .FIFO_READ_LATENCY  (READ_LATENCY)
) xpm_fifo_sync_i (
    .almost_empty   (),
    .almost_full    (),
    .data_valid     (),
    .dbiterr        (),
    .din            (din),
    .dout           (dout),
    .empty          (empty),
    .full           (full),
    .injectdbiterr  (1'b0),
    .injectsbiterr  (1'b0),
    .overflow       (overflow),
    .prog_empty     (),
    .prog_full      (),
    .rd_data_count  (),
    .rd_en          (rd_en),
    .rd_rst_busy    (rd_rst_busy),
    .rst            (srst),
    .sbiterr        (),
    .sleep          (1'b0),
    .underflow      (),
    .wr_ack         (),
    .wr_clk         (clk),
    .wr_data_count  (),
    .wr_en          (wr_en),
    .wr_rst_busy    (wr_rst_busy)
);

// Build a valid pulse aligned with dout: FWFT => ~empty, otherwise delay rd_en by read latency
generate
if (READ_LATENCY == 0) begin : g_fwft_valid
    assign valid = ~empty;
end else begin : g_std_valid
    always_ff @(posedge clk) begin
        if (srst) begin
            rd_shift <= '0;
        end else begin
            rd_shift <= {rd_shift[READ_LATENCY-1:0], (rd_en && !empty)};
        end
    end
    assign valid = rd_shift[READ_LATENCY];
end
endgenerate

// localparam LOG_DEPTH = $clog2(DEPTH);

// logic [LOG_DEPTH:0] wr_ptr;
// logic [LOG_DEPTH:0] rd_ptr;

// (* ram_style = "block" *) logic [WIDTH-1:0] fifo_mem [DEPTH];

// assign full = (wr_ptr[LOG_DEPTH] != rd_ptr[LOG_DEPTH]) &&
//               (wr_ptr[LOG_DEPTH-1:0] == rd_ptr[LOG_DEPTH-1:0]);

// assign empty        = (wr_ptr == rd_ptr);
// assign overflow     = '0;
// assign wr_rst_busy  = '0;
// assign rd_rst_busy  = '0;

// always_ff @(posedge clk) begin
//     if (srst) begin
//         valid <= '0;
//     end
//     else begin
//         if (rd_en && !empty) begin
//             valid <= '1;
//         end
//         else begin
//             valid <= '0;
//         end
//     end
// end

// always_ff @(posedge clk) begin
//     if (srst) begin
//         dout        <= '0;
//         wr_ptr      <= '0;
//         rd_ptr      <= '0;
//     end
//     else begin
//         if (wr_en && !full) begin
//             fifo_mem[wr_ptr[LOG_DEPTH-1:0]] <= din;
//             wr_ptr <= wr_ptr + 1'b1;
//         end

//         if (rd_en && !empty) begin
//             dout <= fifo_mem[rd_ptr[LOG_DEPTH-1:0]];
//             rd_ptr <= rd_ptr + 1'b1;
//         end
//     end
// end

endmodule
