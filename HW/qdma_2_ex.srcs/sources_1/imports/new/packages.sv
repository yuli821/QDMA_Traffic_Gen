`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 10/24/2025 09:22:14 AM
// Design Name:
// Module Name: packages
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

package packages;

    localparam logic [15:0] ETH_TYPE_IPV4 = 16'h0800;
    localparam logic [15:0] ETH_TYPE_IPV6 = 16'h86DD;

    localparam logic [7:0] IP_PROTO_TCP   = 8'h06;

    typedef enum logic [3:0] {
        // OPEN
        CLOSED,
        LISTEN,
        SYN_RECV,
        SYN_SENT,

        // ESTABLISHED
        ESTABLISHED,

        // CLOSE
        FIN_1,
        FIN_2,
        CLOSING,
        CLOSE_WAIT,
        LAST_ACK,
        TIME_WAIT
    } tcp_state_t;

    typedef struct packed {
        logic syn;
        logic ack;
        logic rst;
        logic fin;
    } tcp_csr_t;

    localparam tcp_csr_t CSR_SYN     = '{syn:1'b1, ack:1'b0, rst:1'b0, fin:1'b0};
    localparam tcp_csr_t CSR_ACK     = '{syn:1'b0, ack:1'b1, rst:1'b0, fin:1'b0};
    localparam tcp_csr_t CSR_SYN_ACK = '{syn:1'b1, ack:1'b1, rst:1'b0, fin:1'b0};
    localparam tcp_csr_t CSR_FIN     = '{syn:1'b0, ack:1'b0, rst:1'b0, fin:1'b1};
    localparam tcp_csr_t CSR_FIN_ACK = '{syn:1'b0, ack:1'b1, rst:1'b0, fin:1'b1};
    localparam tcp_csr_t CSR_RST     = '{syn:1'b0, ack:1'b0, rst:1'b1, fin:1'b0};

    typedef struct packed {
        logic [47:0] dest_mac;
        logic [47:0] src_mac;
        logic [15:0] ethertype;
    } l2_hdr_t;

    typedef struct packed {
        logic [3:0]  version;
        logic [3:0]  ihl;
        logic [5:0]  dscp;
        logic [1:0]  ecn;
        logic [15:0] total_len;
        logic [15:0] id;
        logic [2:0]  flags;
        logic [14:0] frag_off;
        logic [7:0]  ttl;
        logic [7:0]  protocol;
        logic [15:0] hdr_checksum;
        logic [31:0] src_ip;
        logic [31:0] dest_ip;
    } ipv4_hdr_t;

    typedef struct packed {
        logic [15:0] src_port;
        logic [15:0] dest_port;
        logic [31:0] seq_num;
        logic [31:0] ack_num;
        logic [3:0]  data_off;
        logic [3:0]  resv;
        logic [7:0]  csr;
        logic [15:0] window;
        logic [15:0] checksum;
        logic [15:0] urgent;
    } tcp_hdr_t;

    typedef struct packed {
        l2_hdr_t    l2_hdr;
        ipv4_hdr_t  ipv4_hdr;
        tcp_hdr_t   tcp_hdr;
        tcp_csr_t   tcp_csr;
    } header_t;

    typedef struct packed {
        logic       valid;
        // 1 - Left
        // 0 - Right
        logic       side;
        logic [1:0] way;
        logic [3:0] set;
    } cache_rmap_t;

    typedef struct packed {
        logic [47:0]    dest_mac;
        logic [47:0]    src_mac;
        logic [31:0]    dest_ip;
        logic [31:0]    src_ip;
        logic [15:0]    dest_port;
        logic [15:0]    src_port;

        tcp_state_t     tcp_curr_t;
        tcp_state_t     tcp_next_t;

        // PAYLOAD LEN
        logic [31:0]    seq_num;
        logic [31:0]    ack_num;
        logic [15:0]    len_num;

        // SYN ACK
        logic [31:0]    snd_una;
        logic [31:0]    snd_nxt;
        logic [31:0]    rcv_nxt;

        logic [5:0]     next_send_time;
        logic [4:0]     backoff_exp;

        tcp_csr_t       csr_curr;
        // tcp_csr_t       csr_next;
    } tcb_t;

    typedef struct packed {
        logic       valid;
        logic [5:0] tcb_addr;
    } timer_wheel_t;

    typedef struct packed {
        logic [5:0] tcb_addr;
        tcb_t       tcb;
    } wb_t;

    typedef struct packed {
        logic       path;
        logic [5:0] tcb_addr;
        tcb_t       tcb;
    } tcb_mgr_t;

endpackage : packages
