`timescale 1ps / 1ps
`include "types.svh"

module traffic_gen #(
    parameter RX_LEN = 512,
    parameter GLOBAL_DST_IP = 32'hC0A8640A,
    parameter GLOBAL_DST_PORT = 16'h1234,
    parameter GLOBAL_PROTOCOL = 8'h6,
    parameter GLOBAL_DST_MAC = 48'h001112345678
)(
    input  logic axi_aclk,
    input  logic axi_aresetn,
    input  logic [31:0] timestamp,
    
    // Flow configuration
    input  flow_config_t config_in,
    input  logic flow_running,
    
    // AXI-Stream Master output (to FIFO)
    output logic m_axis_tvalid,
    output logic [RX_LEN-1:0] m_axis_tdata,
    output logic m_axis_tlast,
    input  logic m_axis_tready,  // Backpressure from FIFO
    
    // Hash value (constant per flow)
    output logic [31:0] hash_val
);

localparam BYTES_PER_BEAT = RX_LEN / 8;
localparam [1:0] IDLE = 2'b00, TRANSFER = 2'b01, WAIT = 2'b10;

logic [1:0] state;
logic [31:0] wait_counter;
logic [15:0] trans_counter;
logic is_header;

assign hash_val = config_in.hash_val;

// Packet header generation
logic [111:0] header_eth_buf;
logic [159:0] header_ip_buf;
logic [159:0] header_trans_buf;
logic [31:0] crc;

assign header_eth_buf = {GLOBAL_DST_MAC, config_in.src_mac, 16'h0800};
assign header_ip_buf = {72'h0, GLOBAL_PROTOCOL, 16'h0, config_in.src_ip, GLOBAL_DST_IP};
assign header_trans_buf = {config_in.src_port, GLOBAL_DST_PORT, 128'h0};
assign crc = 32'h0a212121;

// Data generation
logic [RX_LEN-1:0] data_buf;
always_comb begin
    data_buf = {BYTES_PER_BEAT{8'h41}};
    if (is_header) begin
        data_buf[RX_LEN-1 : RX_LEN-112] = header_eth_buf;
        data_buf[RX_LEN-113 : RX_LEN-272] = header_ip_buf;
        data_buf[RX_LEN-273 : RX_LEN-432] = header_trans_buf;
        data_buf[RX_LEN-433:0] = {timestamp, 16'h1234, 32'h0};
    end
    if (signed'(trans_counter) >= signed'(config_in.pkt_size - BYTES_PER_BEAT)) begin
        data_buf[31:0] = crc;
    end
end

assign m_axis_tdata = data_buf;
assign m_axis_tvalid = (state == TRANSFER) && flow_running;
assign m_axis_tlast = m_axis_tvalid && (trans_counter >= (config_in.pkt_size - BYTES_PER_BEAT));

// State machine
always_ff @(posedge axi_aclk) begin
    if (~axi_aresetn) begin
        state <= IDLE;
        wait_counter <= 0;
        trans_counter <= 0;
        is_header <= 1;
    end else if (~flow_running) begin
        // Graceful stop - wait for current packet to finish
        if (state == WAIT || state == IDLE) begin
            state <= IDLE;
            wait_counter <= 0;
            trans_counter <= 0;
            is_header <= 1;
        end else if (state == TRANSFER && m_axis_tready && m_axis_tlast) begin
            state <= IDLE;
            wait_counter <= 0;
            trans_counter <= 0;
            is_header <= 1;
        end
    end else begin
        case (state)
            IDLE: begin
                wait_counter <= 0;
                trans_counter <= 0;
                is_header <= 1;
                state <= TRANSFER;  // Start immediately when running
            end
            
            TRANSFER: begin
                if (m_axis_tready) begin  // Only advance when FIFO accepts
                    wait_counter <= wait_counter + 1;
                    is_header <= 0;
                    if (trans_counter >= (config_in.pkt_size - BYTES_PER_BEAT)) begin
                        // Packet complete
                        trans_counter <= 0;
                        is_header <= 1;
                        state <= WAIT;
                    end else begin
                        trans_counter <= trans_counter + BYTES_PER_BEAT;
                    end
                end
                // If !m_axis_tready, hold state (backpressure)
            end
            
            WAIT: begin
                is_header <= 1;
                trans_counter <= 0;
                if (wait_counter >= config_in.cycles_per_pkt) begin
                    state <= TRANSFER;  // Start next packet
                    wait_counter <= 0;
                end else begin
                    wait_counter <= wait_counter + 1;
                end
            end
            
            default: state <= IDLE;
        endcase
    end
end

endmodule