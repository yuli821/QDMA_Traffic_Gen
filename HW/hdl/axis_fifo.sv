`timescale 1ps / 1ps

module axis_fifo #(
    parameter DATA_WIDTH = 512,
    parameter DEPTH = 64
)(
    input  logic clk,
    input  logic rst_n,
    
    // Write side (slave)
    input  logic s_axis_tvalid,
    input  logic [DATA_WIDTH-1:0] s_axis_tdata,
    input  logic s_axis_tlast,
    output logic s_axis_tready,
    
    // Read side (master)
    output logic m_axis_tvalid,
    output logic [DATA_WIDTH-1:0] m_axis_tdata,
    output logic m_axis_tlast,
    input  logic m_axis_tready
);

localparam ADDR_WIDTH = $clog2(DEPTH);

// Storage
logic [DATA_WIDTH-1:0] data_mem [DEPTH-1:0];
logic tlast_mem [DEPTH-1:0];
logic [ADDR_WIDTH-1:0] wr_ptr, rd_ptr;

// Registered status flags (NO combinational comparison in critical path)
logic full_reg, empty_reg;

// Handshake signals
wire write_en = s_axis_tvalid && ~full_reg;
wire read_en = ~empty_reg && m_axis_tready;

assign s_axis_tready = ~full_reg;
assign m_axis_tvalid = ~empty_reg;
assign m_axis_tdata = data_mem[rd_ptr];
assign m_axis_tlast = tlast_mem[rd_ptr];

// Write logic
always_ff @(posedge clk) begin
    if (~rst_n) begin
        wr_ptr <= 0;
    end else if (write_en) begin
        data_mem[wr_ptr] <= s_axis_tdata;
        tlast_mem[wr_ptr] <= s_axis_tlast;
        wr_ptr <= (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1;
    end
end

// Read logic
always_ff @(posedge clk) begin
    if (~rst_n) begin
        rd_ptr <= 0;
    end else if (read_en) begin
        rd_ptr <= (rd_ptr == DEPTH-1) ? '0 : rd_ptr + 1;
    end
end

// Registered full/empty flags - PREDICTIVE update
// Key insight: we know the NEXT state based on current state + write/read action
always_ff @(posedge clk) begin
    if (~rst_n) begin
        full_reg <= 0;
        empty_reg <= 1;
    end else begin
        case ({write_en, read_en})
            2'b10: begin  // Write only
                empty_reg <= 0;  // Can't be empty after write
                // Check if next write position equals read position (will be full)
                if (((wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1) == rd_ptr)
                    full_reg <= 1;
            end
            2'b01: begin  // Read only
                full_reg <= 0;   // Can't be full after read
                // Check if next read position equals write position (will be empty)
                if (((rd_ptr == DEPTH-1) ? '0 : rd_ptr + 1) == wr_ptr)
                    empty_reg <= 1;
            end
            // 2'b00: No change
            // 2'b11: Simultaneous read+write, no change to full/empty
            default: ;
        endcase
    end
end

endmodule