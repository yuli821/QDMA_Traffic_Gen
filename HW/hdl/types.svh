`ifndef TYPES_SVH
`define TYPES_SVH

typedef struct packed {
    logic [15:0] pkt_size;
    logic [31:0] cycles_per_pkt;
    logic [31:0] traffic_pattern;
    logic [31:0] src_ip;
    logic [15:0] src_port;
    logic [47:0] src_mac;
    logic [31:0] hash_val;
} flow_config_t;

typedef struct packed {
    logic [31:0] wait_counter;
    logic [15:0] trans_counter;
    logic is_header;
    logic [1:0] state;//0 IDEL, 1 TRANSFER, 2 WAIT
} flow_state_t;

function automatic logic [31:0] computeRSShash (
    input logic [31:0] src_ip,
    input logic [31:0] dst_ip,
    input logic [15:0] src_port,
    input logic [15:0] dst_port,
    input logic [7:0] protocol
);
    localparam [319:0] key = 320'h6d5a56da255b0ec24167253d43a38fb0d0ca2bcbae7b30b477cb2da38030f20c6a42b73bbeac01fa; //40 bytes
    logic [103:0] input_hs;
    logic [31:0] result;
    input_hs = {src_ip, dst_ip, src_port, dst_port, protocol};
    result = 32'b0;
    for (int i = 0 ; i < 104; i++) begin 
        if (input_hs[i] == 1'b1) result ^= key[288 - i+:32]; //leftmost 32 bits
    end
    return result;
endfunction

`endif