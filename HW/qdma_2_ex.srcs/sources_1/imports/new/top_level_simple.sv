`timescale 1ns / 1ps
import packages::*;
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/01/2025 09:06:58 AM
// Design Name: 
// Module Name: top_level_simple
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


module top_level_simple(
    input logic         clk,
    input logic         rst,

    input logic         c2h_dsc_available,

    // H2C (QDMA -> TCP)
    input logic [511:0] m_axis_h2c_tdata,
    input logic [31:0]  m_axis_h2c_tcrc,
    input logic [10:0]  m_axis_h2c_tuser_qid,
    input logic [2:0]   m_axis_h2c_tuser_port_id,
    input logic         m_axis_h2c_tuser_err,
    input logic [31:0]  m_axis_h2c_tuser_mdata,
    input logic [5:0]   m_axis_h2c_tuser_mty,
    input logic         m_axis_h2c_tuser_zero_byte,
    input logic         m_axis_h2c_tvalid,
    input logic         m_axis_h2c_tlast,
    output logic        m_axis_h2c_tready,

    // C2H (TCP -> QDMA)
    output logic [511:0]s_axis_c2h_tdata,

    output logic [31:0] s_axis_c2h_tcrc,

    output logic [15:0] s_axis_c2h_ctrl_len,
    output logic [10:0] s_axis_c2h_ctrl_qid,
    output logic        s_axis_c2h_ctrl_has_cmpt,
    output logic [2:0]  s_axis_c2h_ctrl_port_id,

    output logic        s_axis_c2h_ctrl_marker,
    output logic [6:0]  s_axis_c2h_ctrl_ecc,
    output logic [5:0]  s_axis_c2h_mty,

    output logic        s_axis_c2h_tvalid,
    output logic        s_axis_c2h_tlast,
    input logic         s_axis_c2h_tready
);

l2_hdr_t    rx_l2_hdr;
ipv4_hdr_t  rx_ipv4_hdr;
tcp_hdr_t   rx_tcp_hdr;

l2_hdr_t    rx_l2_hdr_d;
ipv4_hdr_t  rx_ipv4_hdr_d;
tcp_hdr_t   rx_tcp_hdr_d;

tcp_csr_t   rx_tcp_csr;
tcp_csr_t   tx_tcp_csr;

logic       sent;
logic       state_entry;

rx_datapath rx_datapath_i (
    .clk                        (clk),
    .rst                        (rst),
    .m_axis_h2c_tdata           (m_axis_h2c_tdata),
    .m_axis_h2c_tcrc            (m_axis_h2c_tcrc),
    .m_axis_h2c_tuser_qid       (m_axis_h2c_tuser_qid),
    .m_axis_h2c_tuser_port_id   (m_axis_h2c_tuser_port_id),
    .m_axis_h2c_tuser_err       (m_axis_h2c_tuser_err),
    .m_axis_h2c_tuser_mdata     (m_axis_h2c_tuser_mdata),
    .m_axis_h2c_tuser_mty       (m_axis_h2c_tuser_mty),
    .m_axis_h2c_tuser_zero_byte (m_axis_h2c_tuser_zero_byte),
    .m_axis_h2c_tvalid          (m_axis_h2c_tvalid),
    .m_axis_h2c_tlast           (m_axis_h2c_tlast),
    .m_axis_h2c_tready          (m_axis_h2c_tready),

    .l2_hdr     (rx_l2_hdr),
    .ipv4_hdr   (rx_ipv4_hdr),
    .tcp_hdr    (rx_tcp_hdr),
    .tcp_csr    (rx_tcp_csr)
);

tx_datapath tx_datapath_i (
    .clk                        (clk),
    .rst                        (rst),
    .c2h_dsc_available          (c2h_dsc_available),
    .sent                       (sent),
    .s_axis_c2h_tready          (s_axis_c2h_tready),
    .s_axis_c2h_tdata           (s_axis_c2h_tdata),
    .s_axis_c2h_tcrc            (s_axis_c2h_tcrc),
    .s_axis_c2h_ctrl_len        (s_axis_c2h_ctrl_len),
    .s_axis_c2h_ctrl_qid        (s_axis_c2h_ctrl_qid),
    .s_axis_c2h_ctrl_has_cmpt   (s_axis_c2h_ctrl_has_cmpt),
    .s_axis_c2h_ctrl_marker     (s_axis_c2h_ctrl_marker),
    .s_axis_c2h_ctrl_port_id    (s_axis_c2h_ctrl_port_id),
    .s_axis_c2h_ctrl_ecc        (s_axis_c2h_ctrl_ecc),
    .s_axis_c2h_mty             (s_axis_c2h_mty),
    .s_axis_c2h_tvalid          (s_axis_c2h_tvalid),
    .s_axis_c2h_tlast           (s_axis_c2h_tlast),
    //Added
    .local_seq_num              (local_seq_num),
    .remote_ack_num             (remote_seq_num),

    .l2_hdr                     (rx_l2_hdr_d),
    .ipv4_hdr                   (rx_ipv4_hdr_d),
    .tcp_hdr                    (rx_tcp_hdr_d),
    .tcp_csr                    (tx_tcp_csr)
);

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
    LAST_ACK
} state_t;

state_t curr_t, next_t;

tcp_csr_t  last_sent;
//Added
logic [31:0] local_seq_num;
logic [31:0] remote_seq_num;

localparam tcp_csr_t CSR_SYN     = '{syn:1'b1, ack:1'b0, rst:1'b0, fin:1'b0};
localparam tcp_csr_t CSR_ACK     = '{syn:1'b0, ack:1'b1, rst:1'b0, fin:1'b0};
localparam tcp_csr_t CSR_SYN_ACK = '{syn:1'b1, ack:1'b1, rst:1'b0, fin:1'b0};
localparam tcp_csr_t CSR_FIN     = '{syn:1'b0, ack:1'b0, rst:1'b0, fin:1'b1};
localparam tcp_csr_t CSR_RST     = '{syn:1'b0, ack:1'b0, rst:1'b1, fin:1'b0};

always_ff @(posedge clk) begin
    rx_l2_hdr_d     <= rx_l2_hdr;
    rx_ipv4_hdr_d   <= rx_ipv4_hdr;
    rx_tcp_hdr_d    <= rx_tcp_hdr;
end

// Add as separate always_comb block
logic [15:0] payload_len;

always_comb begin
    logic [15:0] ip_total, ip_hdr, tcp_hdr;
    ip_total = rx_ipv4_hdr_d.total_len;  // Use delayed version for timing
    ip_hdr = {rx_ipv4_hdr_d.ihl, 2'b00};
    tcp_hdr = {rx_tcp_hdr_d.data_off, 2'b00};
    payload_len = ip_total - ip_hdr - tcp_hdr;
end

always_ff @(posedge clk) begin
    // STATE TRANSITION
    if (rst) begin
        curr_t  <= CLOSED;
        state_entry <= 1'b1;

        // Control signals
        tx_tcp_csr      <= '0;
        last_sent       <= '0;
        
        // Sequence numbers
        local_seq_num   <= 32'hDEADBEEF;
        remote_seq_num  <= '0;
    end
    else begin
        // state transition
        state_entry <= (next_t != curr_t);
        curr_t  <= next_t;
        
        // if (m_axis_h2c_tvalid && m_axis_h2c_tready && (rx_tcp_csr.syn || rx_tcp_csr.fin)) begin
        //     remote_seq_num <= rx_tcp_hdr.seq_num + 1;
        // end

        // Default
        tx_tcp_csr <= '0;
        case (curr_t)
            CLOSED: begin
                if (state_entry) begin 
                    last_sent <= '0;
                end

                if (rx_tcp_csr.syn || rx_tcp_csr.ack || rx_tcp_csr.fin) begin 
                    tx_tcp_csr <= CSR_RST;
                end
            end
            LISTEN: begin
                if (rx_tcp_csr.syn) begin 
                    tx_tcp_csr <= CSR_SYN_ACK;
                    last_sent <= CSR_SYN_ACK;
                    local_seq_num <= local_seq_num + 1; //SYN consumes 1 seq number
                    remote_seq_num <= rx_tcp_hdr.seq_num + 1;
                end
                else if (rx_tcp_csr.fin || rx_tcp_csr.ack) begin 
                    tx_tcp_csr <= CSR_RST;
                end
            end
            SYN_RECV: begin
                if (rx_tcp_csr.syn && !rx_tcp_csr.rst) begin 
                    tx_tcp_csr <= last_sent;
                end else if (rx_tcp_csr.fin)begin
                    tx_tcp_csr <= CSR_RST;
                end
            end
            SYN_SENT: begin
                if (state_entry) begin 
                    tx_tcp_csr <= CSR_SYN;
                    last_sent <= CSR_SYN;
                    local_seq_num <= local_seq_num + 1; //SYN consumes 1 seq number
                end
                else if (rx_tcp_csr.syn && rx_tcp_csr.ack) begin 
                    tx_tcp_csr <= CSR_ACK;
                end
                else if (rx_tcp_csr.syn && !rx_tcp_csr.ack) begin 
                    tx_tcp_csr <= CSR_SYN_ACK;
                    last_sent <= CSR_SYN_ACK;
                    local_seq_num <= local_seq_num + 1; //SYN consumes 1 seq number
                end
            end
            ESTABLISHED: begin
                // ACK any received data
                if (m_axis_h2c_tvalid && m_axis_h2c_tready && (payload_len > 0)) begin
                    remote_seq_num <= rx_tcp_hdr_d.seq_num + payload_len;
                    tx_tcp_csr <= CSR_ACK;
                end
                
                if (rx_tcp_csr.fin) begin 
                    remote_seq_num <= remote_seq_num + 1;  // FIN consumes 1 SEQ
                    tx_tcp_csr <= CSR_ACK;
                end

                // if (rx_tcp_csr.fin) begin 
                //     tx_tcp_csr <= CSR_ACK;
                // end
                // else if (rx_tcp_csr.syn && !rx_tcp_csr.ack) begin 
                //     tx_tcp_csr <= CSR_RST;
                // end
            end
            FIN_1: begin
                if (state_entry) begin 
                    tx_tcp_csr <= CSR_FIN;
                    last_sent <= CSR_FIN;
                    local_seq_num <= local_seq_num + 1; //FIN consumes 1 seq number
                end
                else if (rx_tcp_csr.fin) begin 
                    tx_tcp_csr <= CSR_ACK;
                end
            end
            FIN_2: begin
                if (rx_tcp_csr.fin) begin 
                    tx_tcp_csr <= CSR_ACK;
                end
            end
            CLOSING: begin
                if (rx_tcp_csr.fin) begin 
                    tx_tcp_csr <= CSR_ACK;
                end
            end
            LAST_ACK: begin
                if (state_entry) begin 
                    tx_tcp_csr <= CSR_FIN;
                    last_sent <= CSR_FIN;
                    local_seq_num <= local_seq_num + 1; //FIN consumes 1 seq number
                end
                else if (rx_tcp_csr.fin) begin 
                    tx_tcp_csr <= CSR_ACK;
                end
            end
            default: begin
            end
        endcase
    end

    //Added
    // // RESET SEND SIGNAL
    // if (rst || sent) begin
    //     tx_tcp_csr  <= '0;
    // end

    // if (rst) begin
    //     last_sent   <= '0;
    // end 
    // //Added
    // if (rst) begin 
    //     local_seq_num <= 32'hDEADBEEF;
    //     remote_seq_num <= '0;
    // end
    // else begin 
    //     // Track remote's next expected SEQ (only when valid RX)
    //     if (m_axis_h2c_tvalid && m_axis_h2c_tready && (rx_tcp_csr.syn || rx_tcp_csr.fin)) begin
    //         remote_seq_num <= rx_tcp_hdr.seq_num + 1;
    //     end
        
    //     // Increment our SEQ when we send SYN or FIN (they consume 1 seq number)
    //     if ((tx_tcp_csr.syn || tx_tcp_csr.fin) && !sent) begin
    //         local_seq_num <= local_seq_num + 1;
    //     end
    // end

    // /*
    //     FIXME: Gate with Valid?
    //     Track the last control flags so duplicates can be answered without delay.
    // */
    // tx_tcp_csr <= '0;
    // case (curr_t)
    //     CLOSED : begin
    //         if (state_entry) begin
    //             last_sent <= '0;
    //         end

    //         if (rx_tcp_csr.syn || rx_tcp_csr.ack || rx_tcp_csr.fin) begin
    //             tx_tcp_csr <= CSR_RST;
    //         end
    //     end
    //     LISTEN : begin
    //         if (rx_tcp_csr.syn) begin // send syn ack
    //             tx_tcp_csr <= CSR_SYN_ACK;
    //             last_sent  <= CSR_SYN_ACK;
    //         end
    //         else if (rx_tcp_csr.fin || rx_tcp_csr.ack) begin
    //             tx_tcp_csr <= CSR_RST;
    //         end
    //     end
    //     SYN_RECV : begin
    //         if (rx_tcp_csr.syn && !rx_tcp_csr.rst) begin
    //             if (last_sent == '0) begin
    //                 tx_tcp_csr <= CSR_SYN_ACK;
    //                 last_sent  <= CSR_SYN_ACK;
    //             end
    //             else begin
    //                 tx_tcp_csr <= last_sent;
    //             end
    //         end
    //         else if (rx_tcp_csr.fin) begin
    //             tx_tcp_csr <= CSR_RST;
    //         end
    //     end
    //     SYN_SENT : begin
    //         if (state_entry) begin
    //             tx_tcp_csr <= CSR_SYN;
    //             last_sent  <= CSR_SYN;
    //         end
    //         else if (rx_tcp_csr.syn && rx_tcp_csr.ack) begin
    //             tx_tcp_csr <= CSR_ACK;
    //         end
    //         else if (rx_tcp_csr.syn && !rx_tcp_csr.ack) begin
    //             tx_tcp_csr <= CSR_SYN_ACK;
    //             last_sent  <= CSR_SYN_ACK;
    //         end
    //     end
    //     ESTABLISHED : begin
    //         if (rx_tcp_csr.fin) begin
    //             tx_tcp_csr <= CSR_ACK;
    //         end
    //         else if (rx_tcp_csr.syn && !rx_tcp_csr.ack) begin
    //             tx_tcp_csr <= CSR_RST;
    //         end
    //     end
    //     FIN_1 : begin
    //         if (state_entry) begin
    //             tx_tcp_csr <= CSR_FIN;
    //             last_sent  <= CSR_FIN;
    //         end
    //         else if (rx_tcp_csr.fin) begin
    //             tx_tcp_csr <= CSR_ACK;
    //         end
    //     end
    //     FIN_2 : begin
    //         if (rx_tcp_csr.fin) begin
    //             tx_tcp_csr <= CSR_ACK;
    //         end
    //     end
    //     CLOSING : begin
    //         if (rx_tcp_csr.fin) begin
    //             tx_tcp_csr <= CSR_ACK;
    //         end
    //     end
    //     LAST_ACK : begin
    //         if (state_entry) begin
    //             tx_tcp_csr <= CSR_FIN;
    //             last_sent  <= CSR_FIN;
    //         end
    //         else if (rx_tcp_csr.fin) begin
    //             tx_tcp_csr <= CSR_ACK;
    //         end
    //     end
    //     default : begin
    //     end
    // endcase
end

always_comb begin
    /*
        TODO: Check TCP SYN ACK numbers somewhere
        in the FSM.
    */
    next_t = curr_t;

    case (curr_t)
        CLOSED : begin      // IDLE
            // passive open only for now
            // host requests data
            next_t = LISTEN;
        end
        LISTEN : begin
            if (rx_tcp_csr.syn) begin
                next_t = SYN_RECV;
            end
            else begin
                next_t = LISTEN;
            end
        end
        SYN_RECV : begin
            //Added
            // if (rx_tcp_csr.ack) begin
            if (rx_tcp_csr.ack && (rx_tcp_hdr.ack_num == local_seq_num)) begin
                next_t = ESTABLISHED;
            end
            else if (rx_tcp_csr.rst) begin
                next_t = CLOSED;
            end
            else begin
                next_t = SYN_RECV;
            end
        end
        SYN_SENT : begin
            if (rx_tcp_csr.rst) begin
                next_t = CLOSED;
            end
            else if (rx_tcp_csr.syn && rx_tcp_csr.ack) begin
                next_t = ESTABLISHED;
            end
            else if (rx_tcp_csr.syn && !rx_tcp_csr.ack) begin
                next_t = SYN_RECV;
            end
        end
        ESTABLISHED : begin
            if (rx_tcp_csr.rst) begin
                next_t = CLOSED;
            end
            else if (rx_tcp_csr.fin) begin
                next_t = LAST_ACK;
            end
        end
        FIN_1 : begin
            if (rx_tcp_csr.rst) begin
                next_t = CLOSED;
            end
            else if (rx_tcp_csr.fin) begin
                next_t = CLOSING;
            end
            else if (rx_tcp_csr.ack) begin
                next_t = FIN_2;
            end
        end
        FIN_2 : begin
            if (rx_tcp_csr.rst) begin
                next_t = CLOSED;
            end
            else if (rx_tcp_csr.fin) begin
                next_t = CLOSED;
            end
        end
        CLOSING : begin
            if (rx_tcp_csr.rst) begin
                next_t = CLOSED;
            end
            else if (rx_tcp_csr.ack) begin
                next_t = CLOSED;
            end
        end
        LAST_ACK : begin
            if (rx_tcp_csr.rst) begin
                next_t = CLOSED;
            end
            else if (rx_tcp_csr.ack) begin
                next_t = CLOSED;
            end
        end
        default : begin
        end
    endcase
end


endmodule
