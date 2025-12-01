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
    input logic         we_in,
    input tcb_t         tcb_in,

    // ---------------------------------- RX INPUTS
    input logic         new_packet,
    input tcp_csr_t     rx_csr,

    // ---------------------------------- TCB OUTPUTS
    output logic        invalidate,
    output logic        valid_out,
    output logic [5:0]  addr_out,
    output logic        we_out,
    output tcb_t        tcb_out
);

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

// flag_check flag_check_i (
    
// );
tcb_t       tcb_d;
tcp_state_t tcp_curr_t;
tcp_state_t tcp_next_t;
tcp_csr_t   tx_csr;

logic   invalidate_fsm;
logic   invalidate_rto;

logic   new_packet_d;
logic   ingress;
logic   egress;

assign invalidate   = invalidate_fsm || invalidate_rto;

assign ingress      = path && valid_in;
assign egress       = ~path && valid_in;

assign valid_out    = valid_in;
assign addr_out     = addr_in;
assign we_out       = we_in;

always_ff @(posedge clk) begin
    if (rst) begin
        tcb_d           <= '0;
    end
    else if (valid_in) begin
        tcb_d           <= tcb_in;
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        new_packet_d    <= 1'b0;
    end
    else if (new_packet || valid_in) begin
        new_packet_d    <= new_packet;
    end
end

always_comb begin
    tcb_out         = tcb_in;
    invalidate_rto  = '0;

    if (ingress) begin
        tcp_curr_t  = new_packet_d ? LISTEN : tcb_d.tcp_curr_t;
        
        tcb_out.tcp_curr_t  = tcp_curr_t;
        tcb_out.tcp_next_t  = tcp_next_t;
        tcb_out.csr_curr    = tx_csr;

        tcb_out.next_send_time  = new_packet_d ? '0 : tcb_d.next_send_time;
        tcb_out.backoff_exp     = new_packet_d ? '0 : 1'b1;
    end
    else if (egress) begin
        /*
            TCB should transition to next state on egress
            but the next state is calculated on RX only
            so default next to next
        */
        tcb_out.tcp_curr_t  = tcb_in.tcp_next_t;
        tcb_out.tcp_next_t  = tcb_in.tcp_next_t;

        if (tcb_in.next_send_time == '0) begin
            tcb_out.next_send_time  = 1'b1;
            tcb_out.backoff_exp     = 1'b1;
        end
        else if (tcb_in.backoff_exp == 'd6) begin
            // TODO: Invalidate cache and TCB_ALLOC
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