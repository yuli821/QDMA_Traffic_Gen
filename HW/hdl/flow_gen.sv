`timescale 1ps / 1ps
`include "types.svh"

module flow_gen #(
    parameter RX_LEN = 512,
    parameter NUM_FLOWS = 16,
    parameter FIFO_DEPTH = 64,  // Beats per FIFO (e.g., 8 packets of 8 beats)
    parameter GLOBAL_DST_IP = 32'hC0A8640A,
    parameter GLOBAL_DST_PORT = 16'h1234,
    parameter GLOBAL_PROTOCOL = 8'h6,
    parameter GLOBAL_DST_MAC = 48'h001112345678
)(
    input  logic axi_aclk,
    input  logic axi_aresetn,
    input  logic [31:0] timestamp,
    input  logic rx_ready,       // Downstream ready
    input  logic crdt_valid,
    input  logic qid_fifo_full,
    
    // Flow configuration
    input  flow_config_t flow_config [0:NUM_FLOWS-1],
    input  logic [NUM_FLOWS-1:0] flow_running,
    
    // Outputs
    output logic rx_valid,
    output logic [RX_LEN-1:0] rx_data,
    output logic rx_last,
    output logic [31:0] hash_val,
    output logic [15:0] pkt_size
);

// ============================================
// Per-flow wires
// ============================================
// Traffic gen to FIFO
logic [NUM_FLOWS-1:0] gen_tvalid;
logic [RX_LEN-1:0] gen_tdata [NUM_FLOWS-1:0];
logic [NUM_FLOWS-1:0] gen_tlast;
logic [NUM_FLOWS-1:0] gen_tready;  // Backpressure to generators
logic [31:0] gen_hash [NUM_FLOWS-1:0];

// FIFO outputs
logic [NUM_FLOWS-1:0] fifo_tvalid;  // !empty
logic [RX_LEN-1:0] fifo_tdata [NUM_FLOWS-1:0];
logic [NUM_FLOWS-1:0] fifo_tlast;
logic [NUM_FLOWS-1:0] fifo_tready;  // Read enable from scheduler

logic packet_complete;

// ============================================
// Generate traffic_gen and FIFO instances
// ============================================
genvar i;
generate
    for (i = 0; i < NUM_FLOWS; i++) begin : gen_flows
        // Traffic generator
        traffic_gen #(
            .RX_LEN(RX_LEN),
            .GLOBAL_DST_IP(GLOBAL_DST_IP),
            .GLOBAL_DST_PORT(GLOBAL_DST_PORT),
            .GLOBAL_PROTOCOL(GLOBAL_PROTOCOL),
            .GLOBAL_DST_MAC(GLOBAL_DST_MAC)
        ) u_traffic_gen (
            .axi_aclk(axi_aclk),
            .axi_aresetn(axi_aresetn),
            .timestamp(timestamp),
            .config_in(flow_config[i]),
            .flow_running(flow_running[i]),
            .m_axis_tvalid(gen_tvalid[i]),
            .m_axis_tdata(gen_tdata[i]),
            .m_axis_tlast(gen_tlast[i]),
            .m_axis_tready(gen_tready[i]),
            .hash_val(gen_hash[i])
        );
        
        // Packet FIFO (with tlast storage)
        axis_fifo #(
            .DATA_WIDTH(RX_LEN),
            .DEPTH(FIFO_DEPTH)
        ) u_fifo (
            .clk(axi_aclk),
            .rst_n(axi_aresetn),
            // Write side (from traffic_gen)
            .s_axis_tvalid(gen_tvalid[i]),
            .s_axis_tdata(gen_tdata[i]),
            .s_axis_tlast(gen_tlast[i]),
            .s_axis_tready(gen_tready[i]),  // Backpressure to generator
            // Read side (to scheduler)
            .m_axis_tvalid(fifo_tvalid[i]),
            .m_axis_tdata(fifo_tdata[i]),
            .m_axis_tlast(fifo_tlast[i]),
            .m_axis_tready(fifo_tready[i])
        );
    end
endgenerate

// ============================================
// Scheduler - Round-robin among non-empty FIFOs
// ============================================
logic [NUM_FLOWS-1:0] current_flow;     // One-hot
logic [NUM_FLOWS-1:0] next_flow;
assign packet_complete = |(current_flow & fifo_tready & fifo_tvalid & fifo_tlast);
// Detect if current flow has NO data
logic current_flow_empty;
assign current_flow_empty = ~|(current_flow & fifo_tvalid);

// Find next flow with data (round-robin)
always_comb begin
    next_flow = current_flow;
    for (int j = 1; j < NUM_FLOWS; j++) begin
        logic [NUM_FLOWS-1:0] candidate;
        candidate = (current_flow << j) | (current_flow >> (NUM_FLOWS - j));
        if (|(candidate & fifo_tvalid & flow_running)) begin
            next_flow = candidate & fifo_tvalid & flow_running;
            next_flow = next_flow & (~next_flow + 1);  // Isolate LSB
            break;
        end
    end
end

logic switch_trigger;
assign switch_trigger = |(next_flow & fifo_tvalid) && (packet_complete || current_flow_empty);
// Update current flow selection
always_ff @(posedge axi_aclk) begin
    if (~axi_aresetn) begin
        current_flow <= {{(NUM_FLOWS-1){1'b0}}, 1'b1};
    end else begin
        if (switch_trigger) begin
            current_flow <= next_flow;
        end
    end
end

logic switch_gap;
always_ff @(posedge axi_aclk) begin 
    if (~axi_aresetn)
        switch_gap <= 1'b0;
    else 
        switch_gap <= switch_trigger;
end

// Output mux - select from current flow's FIFO (combinational)
logic rx_valid_comb;
logic [RX_LEN-1:0] rx_data_comb;
logic rx_last_comb;
logic [31:0] hash_val_comb;
logic [15:0] pkt_size_comb;
always_comb begin
    rx_valid_comb = 1'b0;
    rx_data_comb = '0;
    rx_last_comb = 1'b0;
    hash_val_comb = '0;
    pkt_size_comb = '0;
    for (int j = 0; j < NUM_FLOWS; j++) begin
        if (current_flow[j]) begin
            rx_valid_comb = fifo_tvalid[j] && fifo_tready[j];
            rx_data_comb = fifo_tdata[j];
            rx_last_comb = fifo_tlast[j];
            hash_val_comb = gen_hash[j];
            pkt_size_comb = flow_config[j].pkt_size;
        end
    end
end

// FIFO read enable - only when output register can accept
always_comb begin
    fifo_tready = '0;
    for (int j = 0; j < NUM_FLOWS; j++) begin
        fifo_tready[j] = current_flow[j] && rx_ready && crdt_valid && ~qid_fifo_full && ~switch_gap;
    end
end

assign rx_valid = rx_valid_comb;
assign rx_data = rx_data_comb;
assign rx_last = rx_last_comb;
assign hash_val = hash_val_comb;
assign pkt_size = pkt_size_comb;

endmodule