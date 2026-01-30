`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/05/2025 12:25:03 AM
// Design Name: 
// Module Name: tcp_fsm
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
module tcp_fsm (
    input logic         rx_valid,

    input tcp_state_t   tcp_curr_t,
    output tcp_state_t  tcp_next_t,

    input tcp_csr_t     tcp_csr_rx,
    output tcp_csr_t    tcp_csr_tx,
    output logic        invalidate,
    output logic        established
);

// http://tcpipguide.com/free/t_TCPOperationalOverviewandtheTCPFiniteStateMachineF-2.htm

/*
RFC793 https://datatracker.ietf.org/doc/html/rfc793
In no case does receipt of a segment containing RST give rise to a RST in response.


*/

tcp_csr_t  last_sent;

assign established = (tcp_curr_t == ESTABLISHED);

always_comb begin
    tcp_csr_tx  = '0;
    invalidate  = 1'b0;

    if (rx_valid) begin
        unique case (tcp_curr_t)
            CLOSED: begin
                if (tcp_csr_rx == CSR_SYN || tcp_csr_rx == CSR_ACK|| tcp_csr_rx == CSR_FIN) begin
                    tcp_csr_tx = CSR_RST;
                    invalidate = 1'b1;
                end
            end
            LISTEN: begin
                if (tcp_csr_rx == CSR_SYN) begin
                    tcp_csr_tx = CSR_SYN_ACK;
                end
                else if (tcp_csr_rx == CSR_FIN || tcp_csr_rx == CSR_ACK) begin
                    tcp_csr_tx = CSR_RST;
                    invalidate = 1'b1;
                end
                else if (tcp_csr_rx == CSR_RST) begin
                    // HOST RESETS (INVALIDATE CACHE AND TCB)
                    invalidate = 1'b1;
                end
                else begin
                    tcp_csr_tx = CSR_RST;
                    invalidate = 1'b1;
                end
            end
            SYN_RECV: begin
                if (tcp_csr_rx == CSR_SYN) begin
                    tcp_csr_tx = CSR_SYN_ACK;
                end
                else if (tcp_csr_rx == CSR_ACK) begin
                end
                else if (tcp_csr_rx == CSR_RST) begin
                    // HOST RESETS (INVALIDATE CACHE AND TCB)
                    invalidate = 1'b1;
                end
                else begin
                    tcp_csr_tx = CSR_RST;
                    invalidate = 1'b1;
                end
            end
            SYN_SENT: begin
                if (tcp_csr_rx.syn && tcp_csr_rx.ack) begin
                    tcp_csr_tx = CSR_ACK;
                end
                else if (tcp_csr_rx.syn) begin
                    tcp_csr_tx = CSR_SYN_ACK;
                end
                else if (tcp_csr_rx.rst) begin
                    // HOST RESETS (INVALIDATE CACHE AND TCB)
                    invalidate = 1'b1;
                end
                else begin
                    tcp_csr_tx = CSR_RST;
                    invalidate = 1'b1;
                end
            end
        ESTABLISHED: begin
            if (tcp_csr_rx.fin) begin
                tcp_csr_tx = CSR_FIN_ACK;
            end
            else if (tcp_csr_rx.syn) begin
                tcp_csr_tx = CSR_RST;
                invalidate = 1'b1;
            end
                else if (tcp_csr_rx.ack) begin
                end
                else if (tcp_csr_rx.rst) begin
                    // HOST RESETS (INVALIDATE CACHE AND TCB)
                    invalidate = 1'b1;
                end
                else begin
                    tcp_csr_tx = CSR_RST;
                    invalidate = 1'b1;
                end
            end
        FIN_1: begin
            if (tcp_csr_rx.fin) begin
                tcp_csr_tx = CSR_FIN_ACK;
            end
            else if (tcp_csr_rx.ack) begin
            end
            else if (tcp_csr_rx.rst) begin
                // HOST RESETS (INVALIDATE CACHE AND TCB)
                    invalidate = 1'b1;
                end
                else begin
                    tcp_csr_tx = CSR_RST;
                    invalidate = 1'b1;
                end
            end
        FIN_2: begin
            if (tcp_csr_rx.fin) begin
                tcp_csr_tx = CSR_FIN_ACK;
            end
            else if (tcp_csr_rx.ack) begin
            end
            else if (tcp_csr_rx.rst) begin
                // HOST RESETS (INVALIDATE CACHE AND TCB)
                    invalidate = 1'b1;
                end
                else begin
                    tcp_csr_tx = CSR_RST;
                    invalidate = 1'b1;
                end
            end
        CLOSING: begin
            if (tcp_csr_rx.fin) begin
                tcp_csr_tx = CSR_FIN_ACK;
            end
            else if (tcp_csr_rx.ack) begin
            end
            else if (tcp_csr_rx.rst) begin
                // HOST RESETS (INVALIDATE CACHE AND TCB)
                    invalidate = 1'b1;
                end
                else begin
                    tcp_csr_tx = CSR_RST;
                    invalidate = 1'b1;
                end
            end
        CLOSE_WAIT: begin
            if (tcp_csr_rx.fin) begin
                tcp_csr_tx = CSR_FIN_ACK;
            end
            else if (tcp_csr_rx.ack) begin
            end
            else if (tcp_csr_rx.rst) begin
                // HOST RESETS (INVALIDATE CACHE AND TCB)
                    invalidate = 1'b1;
                end
                else begin
                    tcp_csr_tx = CSR_RST;
                    invalidate = 1'b1;
                end
            end
        LAST_ACK: begin
            if (tcp_csr_rx.fin) begin
                tcp_csr_tx = CSR_FIN_ACK;
            end
            else if (tcp_csr_rx.ack) begin
            end
            else if (tcp_csr_rx.rst) begin
                // HOST RESETS (INVALIDATE CACHE AND TCB)
                invalidate = 1'b1;
            end
            else begin
                tcp_csr_tx = CSR_RST;
                invalidate = 1'b1;
            end
        end
        TIME_WAIT: begin
            if (tcp_csr_rx.fin) begin
                tcp_csr_tx = CSR_FIN_ACK;
            end
            else if (tcp_csr_rx.ack) begin
            end
            else if (tcp_csr_rx.rst) begin
                // HOST RESETS (INVALIDATE CACHE AND TCB)
                invalidate = 1'b1;
            end
            else begin
                tcp_csr_tx = CSR_RST;
                    invalidate = 1'b1;
                end
            end
            default: begin
                tcp_csr_tx = CSR_RST;
                invalidate = 1'b1;
            end
        endcase
    end
end

always_comb begin
    tcp_next_t = tcp_curr_t;

    case (tcp_curr_t)
        CLOSED : begin      // IDLE
            // passive open only for now
            // host requests data
            tcp_next_t = LISTEN;
        end
        LISTEN : begin
            if (rx_valid && tcp_csr_rx.syn) begin
                tcp_next_t = SYN_RECV;
            end
            else begin
                tcp_next_t = LISTEN;
            end
        end
        SYN_RECV : begin
            if (rx_valid && tcp_csr_rx.ack) begin
                tcp_next_t = ESTABLISHED;
            end
            else if (rx_valid && tcp_csr_rx.rst) begin
                tcp_next_t = CLOSED;
            end
        end
        SYN_SENT : begin
            if (rx_valid && tcp_csr_rx.rst) begin
                tcp_next_t = CLOSED;
            end
            else if (rx_valid && (tcp_csr_rx.syn && tcp_csr_rx.ack)) begin
                tcp_next_t = ESTABLISHED;
            end
            else if (rx_valid && tcp_csr_rx.syn) begin
                tcp_next_t = SYN_RECV;
            end
        end
        ESTABLISHED : begin
            if (rx_valid && tcp_csr_rx.rst) begin
                tcp_next_t = CLOSED;
            end
            else if (rx_valid && tcp_csr_rx.fin) begin
                tcp_next_t = TIME_WAIT;
            end
        end
        FIN_1 : begin
            if (rx_valid && tcp_csr_rx.rst) begin
                tcp_next_t = CLOSED;
            end
            else if (rx_valid && tcp_csr_rx.fin) begin
                tcp_next_t = TIME_WAIT;
            end
            else if (rx_valid && tcp_csr_rx.ack) begin
                tcp_next_t = FIN_2;
            end
        end
        FIN_2 : begin
            if (rx_valid && tcp_csr_rx.rst) begin
                tcp_next_t = CLOSED;
            end
            else if (rx_valid && tcp_csr_rx.fin) begin
                tcp_next_t = TIME_WAIT;
            end
        end
        CLOSING : begin
            if (rx_valid && tcp_csr_rx.rst) begin
                tcp_next_t = CLOSED;
            end
            else if (rx_valid && tcp_csr_rx.ack) begin
                tcp_next_t = TIME_WAIT;
            end
        end
        CLOSE_WAIT : begin
            if (rx_valid && tcp_csr_rx.rst) begin
                tcp_next_t = CLOSED;
            end
        end
        LAST_ACK : begin
            if (rx_valid && tcp_csr_rx.rst) begin
                tcp_next_t = CLOSED;
            end
            else if (rx_valid && tcp_csr_rx.ack) begin
                tcp_next_t = CLOSED;
            end
        end
        TIME_WAIT : begin
            tcp_next_t = CLOSED;
        end
        default : begin
        end
    endcase

    if (invalidate) begin
        tcp_next_t = CLOSED;
    end
end

endmodule

/*
Passive:

LISTEN + RX(SYN) → send SYN+ACK → SYN_RECV

SYN_RECV + RX(ACK_valid) → ESTABLISHED

ESTABLISHED + App_close → send FIN → FIN_1

FIN_1 + RX(ACK_valid) → FIN_2

FIN_2 + RX(FIN) → send ACK → TIME_WAIT

TIME_WAIT + 2MSL → CLOSED

Active:

CLOSED + App_open → send SYN → SYN_SENT

SYN_SENT + RX(SYN+ACK) → send ACK → ESTABLISHED

Peer close first:

ESTABLISHED + RX(FIN) → send ACK → CLOSE_WAIT

CLOSE_WAIT + App_close → send FIN → LAST_ACK

LAST_ACK + RX(ACK_valid) → CLOSED

Simultaneous close:

FIN_1 + RX(FIN) → send ACK → CLOSING

CLOSING + RX(ACK_valid) → TIME_WAIT → (2MSL) → CLOSED

Anytime (valid):

RX(RST) → CLOSED (or LISTEN for passive server)
*/
