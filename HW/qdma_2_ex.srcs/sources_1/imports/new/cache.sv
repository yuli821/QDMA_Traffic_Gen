`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/15/2025 05:49:34 AM
// Design Name: 
// Module Name: cache
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
module cache #(
    parameter WIDTH = 32,
    parameter DEPTH = 16,
    parameter WAYS  = 4
)(
    input logic             clk,
    input logic             rst,

    input logic             read,
    // input logic [31:0]      src_ip,
    // input logic [31:0]      dest_ip,
    // input logic [15:0]      src_port,
    // input logic [15:0]      dest_port,
    input logic [127:0]     input_tuple,
    // TODO: keep track of path to decide whether to switch or not
    input logic             rcv,

    output logic            read_miss,
    output logic            tcb_full,

    output logic [95:0]     input_addr,
    output logic            tcb_addr_valid,
    output logic [5:0]      tcb_addr,

    input logic             invalidate,
    input logic [5:0]       invalidate_addr
);


localparam int MISS_LATENCY = 1;
localparam int HIT_LATENCY  = 1;

logic [MISS_LATENCY-1:0] req_valid;

logic [15:0]    valid [4];
logic [63:0]    valid_bitmap;
cache_rmap_t    reverse_map [64];

logic [31:0]    hash_l;
logic [25:0]    tag_l;
logic [3:0]     set_addr_l [4];
logic [3:0]     hit_l_one_hot;
logic [1:0]     hit_way_l;

logic [31:0]    hash_r;
logic [25:0]    tag_r;
logic [3:0]     set_addr_r [4];
logic [3:0]     hit_r_one_hot;
logic [1:0]     hit_way_r;

logic wea [4];
logic web [4];
logic [31:0] din_l  [4];
logic [31:0] dout_l [4];
logic [31:0] din_r  [4];
logic [31:0] dout_r [4];

logic read_d;
logic [5:0] tcb_alloc;

logic [3:0] free_l_one_hot;
logic [3:0] free_r_one_hot;
logic [1:0] free_l;
logic [1:0] free_r;
logic [2:0] free_l_cnt;
logic [2:0] free_r_cnt;

logic [25:0] tag_l_d;
logic [25:0] tag_r_d;

assign tag_l = hash_l[31:6];
assign tag_r = hash_r[31:6];

assign input_addr = input_tuple[95:0];

// assign input_addr   = rcv ? {dest_ip, src_ip, dest_port, src_port} :
//                             {src_ip, dest_ip, src_port, dest_port};

assign tcb_full     = &valid[0] && &valid[1] && &valid[2] && &valid[3];
assign read_miss    = read_d && ~(|hit_l_one_hot) && ~(|hit_r_one_hot);
// assign tcb_addr_valid   = read_d && (|hit_l_one_hot || |hit_r_one_hot);

toeplitz_hash toeplitz_hash_i (
    .tuple_input    (input_addr),
    .hash_out_1     (hash_l),
    .hash_out_2     (hash_r)
);

generate
for (genvar i = 0; i < 4; i++) begin
    // 32-bit x 16 sets
    // TAG[31:6] | TCB ADDR[5:0]
    bram_wrapper bram_gen (
        .clka   (clk),
        .wea    (wea[i]),
        .addra  (set_addr_l[i]),
        .dina   (din_l[i]),
        .douta  (dout_l[i]),

        .clkb   (clk),
        .web    (web[i]),
        .addrb  (set_addr_r[i]),
        .dinb   (din_r[i]),
        .doutb  (dout_r[i])
    );
end
endgenerate

always_ff @(posedge clk) begin
    req_valid <= req_valid << 1'b1;

    if (rst) begin
        req_valid <= '0;
        tcb_addr_valid  <= 1'b0;
    end
    else begin
        tcb_addr_valid  <= 1'b0;
        if (read) begin
            req_valid[0]    <= 1'b1;
            tcb_addr_valid  <= 1'b0;
        end
        if (req_valid[HIT_LATENCY-1] && ~read_miss) begin   // IF READ HIT
            tcb_addr_valid              <= 1'b1;
            req_valid[HIT_LATENCY]      <= 1'b0;
        end
        if (req_valid[MISS_LATENCY-1]) begin
            tcb_addr_valid              <= 1'b1;
        end
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        tcb_addr <= '0;
    end
    else if (|hit_l_one_hot) begin
        tcb_addr <= dout_l[hit_way_l][5:0];
    end
    else if (|hit_r_one_hot) begin
        tcb_addr <= dout_r[hit_way_r][5:0];
    end
    // FIXME: CHECK THIS WITH MULTIPLE CONNECTIONS
    else if (read_miss) begin
        tcb_addr <= tcb_alloc;
    end
end
// always_comb begin
//     tcb_addr = 0;

//     if (|hit_l_one_hot) begin
//         tcb_addr = dout_l[hit_way_l][5:0];
//     end
//     else if (|hit_r_one_hot) begin
//         tcb_addr = dout_r[hit_way_r][5:0];
//     end
//     // FIXME: CHECK THIS WITH MULTIPLE CONNECTIONS
//     else if (read_miss) begin
//         tcb_addr = tcb_alloc;
//     end
// end

always_ff @(posedge clk) begin
    tag_l_d <= tag_l;
    tag_r_d <= tag_r;
end

always_comb begin
    for (int i = 0; i < 4; i++) begin
        wea[i]      = '0;
        web[i]      = '0;
        din_l[i]    = '0;
        din_r[i]    = '0;
    end
    
    if (read_miss && !invalidate) begin
        if (tcb_alloc == 6'd63) begin
            if (|free_l_one_hot) begin
                wea[free_l]         = '1;
                din_l[free_l][31:6] = tag_l;
            end
            else if (|free_r_one_hot) begin
                web[free_r]         = '1;
                din_r[free_r][31:6] = tag_r;
            end
        end
        else begin
            // ALLOCATE
            if (|free_l_one_hot && |free_r_one_hot) begin
                if (free_l_cnt >= free_r_cnt) begin
                    wea[free_l]     = '1;
                    din_l[free_l]   = {tag_l, tcb_alloc};
                end
                else begin
                    web[free_r]     = '1;
                    din_r[free_r]   = {tag_r, tcb_alloc};
                end
            end
            else if (|free_l_one_hot) begin
                wea[free_l]     = '1;
                din_l[free_l]   = {tag_l, tcb_alloc};
            end
            else if (|free_r_one_hot) begin
                web[free_r]     = '1;
                din_r[free_r]   = {tag_r, tcb_alloc};
            end
        end
    end
end

always_ff @(posedge clk) begin
    read_d  <= read;

    if (rst) begin
        tcb_alloc   <= '0;
        valid_bitmap<= '0;
        valid       <= '{default : 0};
        reverse_map <= '{default : 0};
    end
    else if (invalidate) begin
        automatic logic [1:0] invalidate_way    = reverse_map[invalidate_addr].way;
        automatic logic [3:0] invalidate_set    = reverse_map[invalidate_addr].set;

        valid_bitmap[invalidate_addr]       <= 1'b0;
        reverse_map[invalidate_addr].valid  <= '0;

        if (reverse_map[invalidate_addr].valid) begin
            valid[invalidate_way][invalidate_set]   <= '0;
        end
    end
    else if (read_miss) begin
        if (tcb_alloc == 6'd63) begin
            if (~&valid_bitmap) begin
                automatic logic [5:0] free_bitmap = '0;

                automatic logic [1:0] free_way = '0;
                automatic logic [3:0] free_set = '0;

                for (int i = 0; i < 64; i++) begin
                    if (!valid_bitmap[i]) free_bitmap = i[5:0];
                end

                free_way = reverse_map[free_bitmap].way;
                free_set = reverse_map[free_bitmap].set;

                reverse_map[free_bitmap].valid    <= 1'b1;
                reverse_map[free_bitmap].side     <= 1'b1;
                reverse_map[free_bitmap].way      <= free_way;
                reverse_map[free_bitmap].set      <= free_set;

                valid_bitmap[free_bitmap]         <= 1'b1;

                valid[free_way][free_set]   <= 1'b1;
            end
            else if (|free_l_one_hot) begin
                reverse_map[tcb_alloc].valid    <= 1'b1;
                reverse_map[tcb_alloc].side     <= 1'b1;
                reverse_map[tcb_alloc].way      <= free_l;
                reverse_map[tcb_alloc].set      <= set_addr_l[free_l];

                valid_bitmap[tcb_alloc]         <= 1'b1;

                valid[free_l][set_addr_l[free_l]]   <= 1'b1;
            end
            else if (|free_r_one_hot) begin
                reverse_map[tcb_alloc].valid    <= 1'b1;
                reverse_map[tcb_alloc].side     <= 1'b0;
                reverse_map[tcb_alloc].way      <= free_r;
                reverse_map[tcb_alloc].set      <= set_addr_r[free_r];

                valid_bitmap[tcb_alloc]         <= 1'b1;

                valid[free_r][set_addr_r[free_r]]   <= 1'b1;
            end
            else begin
                /*
                    TODO: Send FIN or RST
                    All sets were allocated and there were
                    no existing slots with invalid bits. Alternatively
                    keep a SYN cache and send a SYN ACK back once
                    a slot opens up with a timer.

                    For example,
                    If full and SYN comes, do not reply instantly. Wait
                    until a connection closes. Once it closes and the SYN
                    came within a set time interval, send back a SYN ACK
                    and ALLOCATE a slot.
                */
                // $display("SEND RST");
            end
        end
        else begin
            // ALLOCATE
            if (|free_l_one_hot && |free_r_one_hot) begin
                if (free_l_cnt >= free_r_cnt) begin
                    reverse_map[tcb_alloc].valid    <= 1'b1;
                    reverse_map[tcb_alloc].side     <= 1'b1;
                    reverse_map[tcb_alloc].way      <= free_l;
                    reverse_map[tcb_alloc].set      <= set_addr_l[free_l];

                    valid_bitmap[tcb_alloc]         <= 1'b1;

                    valid[free_l][set_addr_l[free_l]]   <= 1'b1;
                    
                    tcb_alloc <= tcb_alloc + 1'b1;
                end
                else begin
                    reverse_map[tcb_alloc].valid    <= 1'b1;
                    reverse_map[tcb_alloc].side     <= 1'b0;
                    reverse_map[tcb_alloc].way      <= free_r;
                    reverse_map[tcb_alloc].set      <= set_addr_r[free_r];

                    valid_bitmap[tcb_alloc]         <= 1'b1;

                    valid[free_r][set_addr_r[free_r]]   <= 1'b1;

                    tcb_alloc <= tcb_alloc + 1'b1;
                end
            end
            else if (|free_l_one_hot) begin
                reverse_map[tcb_alloc].valid    <= 1'b1;
                reverse_map[tcb_alloc].side     <= 1'b1;
                reverse_map[tcb_alloc].way      <= free_l;
                reverse_map[tcb_alloc].set      <= set_addr_l[free_l];

                valid_bitmap[tcb_alloc]         <= 1'b1;

                valid[free_l][set_addr_l[free_l]]   <= 1'b1;
                
                tcb_alloc <= tcb_alloc + 1'b1;
            end
            else if (|free_r_one_hot) begin
                reverse_map[tcb_alloc].valid    <= 1'b1;
                reverse_map[tcb_alloc].side     <= 1'b0;
                reverse_map[tcb_alloc].way      <= free_r;
                reverse_map[tcb_alloc].set      <= set_addr_r[free_r];

                valid_bitmap[tcb_alloc]         <= 1'b1;

                valid[free_r][set_addr_r[free_r]]   <= 1'b1;

                tcb_alloc <= tcb_alloc + 1'b1;
            end
        end
    end
end

always_comb begin
    for (int i = 0; i < 4; i++) begin
        set_addr_l[i] = '0;
        set_addr_r[i] = '0;
    end

    hit_l_one_hot = '0;
    hit_r_one_hot = '0;

    hit_way_l = '0;
    hit_way_r = '0;

    free_l_one_hot = '0;
    free_r_one_hot = '0;

    free_l_cnt = '0;
    free_r_cnt = '0;


    for (int i = 0; i < 4; i++) begin
        set_addr_l[i]    = hash_l[3:0];
        set_addr_r[i]    = hash_r[3:0];
    end

    // ------------------------------------------------------------- HIT LOGIC

    // Compare with registered tag to account for BRAM latency
    for (int i = 0; i < 4; i++) begin
        hit_l_one_hot[i] = valid[i][set_addr_l[i]] && (dout_l[i][31:6] == tag_l);
        hit_r_one_hot[i] = valid[i][set_addr_r[i]] && (dout_r[i][31:6] == tag_r);
    end

    for (int i = 0; i < 4; i++) begin
        if (hit_l_one_hot[i])
            hit_way_l = i;
    end
    for (int i = 0; i < 4; i++) begin
        if (hit_r_one_hot[i])
            hit_way_r = i;
    end

    // ------------------------------------------------------------- FREE LOGIC

    free_l_one_hot  = {~valid[3][set_addr_l[3]],
                       ~valid[2][set_addr_l[2]],
                       ~valid[1][set_addr_l[1]],
                       ~valid[0][set_addr_l[0]]};

    free_r_one_hot  = {~valid[3][set_addr_r[3]],
                       ~valid[2][set_addr_r[2]],
                       ~valid[1][set_addr_r[1]],
                       ~valid[0][set_addr_r[0]]};

    for (int i = 0; i < 4; i++) begin
        if (free_l_one_hot[i])
            free_l = i;
    end
    for (int i = 0; i < 4; i++) begin
        if (free_r_one_hot[i])
            free_r = i;
    end

    // ------------------------------------------------------------- DLEFT LOGIC

    for (int i = 0; i < 4; i++) begin
        free_l_cnt += free_l_one_hot[i];
        free_r_cnt += free_r_one_hot[i];
    end

end
endmodule
