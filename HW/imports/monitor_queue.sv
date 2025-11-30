`timescale 1ps / 1ps
module monitor_queue(
    input user_clk_ip,
    input user_reset_ip,
    input [15:0] m_axis_cq_monitor_tkeep,
    input m_axis_cq_monitor_tlast,
    input m_axis_cq_monitor_tready,
    input [228:0] m_axis_cq_monitor_tuser,
    input m_axis_cq_monitor_tvalid,
    input [511:0] m_axis_cq_monitor_tdata
);
parameter BASE_C2H_PIDX = 20'h18008; //reg offset
parameter BASE_CMPT_CIDX = 20'h1800C;

logic [15:0] avail_desc;
logic [15:0] c2h_pidx;
logic [15:0] cmpt_cidx;

always_ff @(posedge user_clk_ip) begin 
    if (user_reset_ip) begin 
        c2h_pidx = 16'h0;
        cmpt_cidx = 16'h0;
    end else begin 
        if (m_axis_cq_monitor_tvalid && m_axis_cq_monitor_tready) begin //the update should only be one cycle, 128 bits header + 32 bits register

        end
    end
end

endmodule
