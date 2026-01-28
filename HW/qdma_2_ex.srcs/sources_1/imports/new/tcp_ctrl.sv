`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/12/2025 10:31:55 AM
// Design Name: 
// Module Name: tcp_ctrl
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


module tcp_ctrl(
    input logic         clk,
    input logic         rst,

    // ---------------------------------- WB INPUTS
    input logic         path,
    input logic         valid_in,
    input logic [5:0]   addr_in,
    input tcb_t         tcb_in,

    // ---------------------------------- RX INPUTS
    input logic         new_packet_d,
    input tcp_csr_t     rx_csr,
    input header_t      header_data,

    // ---------------------------------- TCB OUTPUTS
    output logic        cancel_rto_temp,
    output logic        invalidate_temp,
    output logic        valid_out_temp,
    output logic [5:0]  addr_out_temp,
    output tcb_t        tcb_out_temp
);

tcp_state_t tcp_curr_t;
tcp_state_t tcp_next_t;
tcp_csr_t   tx_csr;

logic   invalidate_fsm;
logic   invalidate_rto;

logic   ingress;
logic   egress;

// TEMP WNS FIX
logic        cancel_rto;
logic        invalidate;
logic        valid_out;
logic [5:0]  addr_out;
tcb_t        tcb_out;

always_ff @(posedge clk) begin
    cancel_rto_temp <= cancel_rto;
    invalidate_temp <= invalidate;
    valid_out_temp  <= valid_out;

    if (rst) begin
        addr_out_temp   <= '0;
        tcb_out_temp    <= '0;
    end
    else if (valid_out) begin
        addr_out_temp   <= addr_out;
        tcb_out_temp    <= tcb_out;
    end
end


// TCP FSM should only update state in RX
// if TX, 
tcp_fsm tcp_fsm_i (
    .rx_valid       (ingress),
    .tcp_curr_t     (tcp_curr_t),
    .tcp_next_t     (tcp_next_t),
    .tcp_csr_rx     (rx_csr),
    .tcp_csr_tx     (tx_csr),
    .invalidate     (invalidate_fsm),
    .established    ()
);

assign invalidate   = invalidate_fsm || invalidate_rto;

assign ingress      = path && valid_in;
assign egress       = ~path && valid_in;

assign valid_out    = valid_in;
assign addr_out     = addr_in;

// -------------------------------------------------------- STATE TRANSITION AND RTO UPDATE
// -------------------------------------------------------- SEQ/ACK UPDATE
/*
    SEQ/ACK UPDATE PSEUDOCODE:

    if (ingress):
        if (csr.ack):   // includes ACK, SYNACK, FINACK
            if (tcb.snd_una < packet.ack && packet.ack <= tcb.snd_nxt):
                tcb.snd_una = packet.ack;
            else:
                RST or DROP+ACK

        if (packet.seq == tcb.rcv_nxt):
            tcb.rcv_nxt += len + (SYN ? 1 : 0) + (FIN ? 1 : 0);

    if (egress):
        packet.seq  = tcb.snd_nxt;
        packet.ack  = tcb.rcv_nxt;

        if (new_packet && sent): // FPGA opens 
            snd_nxt += len + (SYN ? 1 : 0) + (FIN ? 1 : 0);
*/

always_comb begin
    tcb_out         = tcb_in;
    invalidate_rto  = '0;
    cancel_rto      = '0;

    if (ingress) begin
        tcp_curr_t  = new_packet_d ? LISTEN : tcb_in.tcp_curr_t;
        
        tcb_out.tcp_curr_t  = tcp_next_t; // commit next state on ingress
        tcb_out.tcp_next_t  = tcp_next_t;
        tcb_out.csr_curr    = tx_csr;

        tcb_out.next_send_time  = '0;
        tcb_out.backoff_exp     = new_packet_d ? '0 : 1'b1;

        if (rx_csr.ack) begin
            cancel_rto = rx_csr == CSR_ACK; // 1'b1;
            if (tcp_curr_t == SYN_RECV && tcb_in.ack_num > tcb_in.snd_nxt) begin
                tcb_out.csr_curr = CSR_RST;
            end
            else if (tcb_in.ack_num > tcb_in.snd_una) begin
                tcb_out.snd_una = tcb_in.ack_num;
            end
        end

        if (new_packet_d) begin
            tcb_out.rcv_nxt = tcb_in.seq_num + 1;
        end else if (header_data.tcp_hdr.seq_num == tcb_in.rcv_nxt) begin
            // TODO: Implement PAYLOAD LENGTH
            tcb_out.rcv_nxt = header_data.tcp_hdr.seq_num + tcb_in.len_num + (rx_csr.syn ? 1 : 0) + (rx_csr.fin ? 1 : 0);
        end
    end
    else if (egress) begin
        /*
            TCB should transition to next state on egress
            but the next state is calculated on RX only
            so default next to next
        */
        tcb_out.tcp_curr_t  = tcb_in.tcp_next_t;
        tcb_out.tcp_next_t  = tcb_in.tcp_next_t;

        tcb_out.seq_num     = tcb_in.snd_nxt;
        tcb_out.ack_num     = tcb_in.rcv_nxt;

        if (tcb_in.next_send_time == '0) begin
            tcb_out.next_send_time  = 1'b1;
            tcb_out.backoff_exp     = 1'b1;

            tcb_out.snd_nxt += tcb_in.len_num + (tcb_in.csr_curr.syn ? 1 : 0) + (tcb_in.csr_curr.fin ? 1 : 0);
        end
        else if (tcb_in.backoff_exp == 'd4) begin
            tcb_out.csr_curr    = CSR_RST;
            invalidate_rto      = 1'b1;
        end
        else begin
            tcb_out.next_send_time  = 1'b1;
            tcb_out.backoff_exp     = tcb_in.backoff_exp + 1'b1;
        end
    end
end



endmodule
