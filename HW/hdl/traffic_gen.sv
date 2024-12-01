`timescale 1ps / 1ps
module traffic_gen #(
    parameter MAX_ETH_FRAME = 16'h1000, //bytes
    parameter RX_LEN = 512, //data width
    parameter RX_BEN = RX_LEN/8,
    parameter TM_DSC_BITS = 16
)
(
    input logic axi_aclk,
    input logic axi_aresetn,
    input logic [31:0] control_reg,
    input logic [15:0] txr_size,
    input logic [31:0] num_pkt,
    // input logic [TM_DSC_BITS-1:0] credit_in,
    // input logic credit_updt,
    // input logic [TM_DSC_BITS-1:0] credit_perpkt_in,
    // input logic [31:0] credit_needed,
    input logic rx_ready,
    input logic [31:0] cycles_per_pkt,
    input logic [10:0] num_queue,
    input logic [10:0] qid, 
    output logic rx_valid,
    // output logic [RX_BEN-1:0] rx_ben,
    output logic [RX_LEN-1:0] rx_data, //1 byte
    output logic rx_last,
    output logic rx_end,
    input logic [10:0] rx_qid,
    output logic [5:0] hash_val,
    input logic c2h_perform,

    input         tm_dsc_sts_vld,
    input         tm_dsc_sts_byp,
    input         tm_dsc_sts_qen,
    input         tm_dsc_sts_dir,
    input         tm_dsc_sts_mm,
    input         tm_dsc_sts_error,
    input [10:0]  tm_dsc_sts_qid,
    input [15:0]  tm_dsc_sts_avl,
    input         tm_dsc_sts_qinv,
    input 	  tm_dsc_sts_irq_arm,
    output        tm_dsc_sts_rdy
    // output logic c2h_begin
);
localparam BYTES_PER_BEAT = RX_LEN/8;
// localparam DST_MAC = 48'h665544332211;
localparam TEMP = BYTES_PER_BEAT * 2;
localparam SRC_MAC = 48'h665544332200;
localparam TCQ = 1;

logic [15:0] frame_size, tot_pkt_size, counter_trans, curr_pkt_size;
logic [31:0] cycles_pkt;
logic [47:0] DST_MAC [4];

logic is_header,updt_crdt,crdt_valid;
logic [31:0] crc;
logic [111:0] header_buf;
logic [RX_LEN-1:0] data_buf;
logic control_reg_1_d, start_c2h, ready;
logic [31:0] tcredit_used, credit_in_sync;
// logic lst_credit_pkt;
logic [31:0] pkt_count;
logic [31:0] cycles_needed;
int counter_wait, counter_rr, off;

//credit logic and bram
logic [10:0] rd_credit_qid, rd_credit_qid_d1;
logic [10:0] wr_credit_qid;
logic [10:0] rx_qid_d1, rx_qid_d2, rx_qid_d3, rx_qid_d4;
logic [31:0] wr_credit_in;
logic signed [31:0] rd_credit_out;
logic  wr_credit_en, wr_conflict, wr_conflict_d1, wr_conflict_d2;
enum logic [6:0] {IDLE_CRDT, CRDT_UPDT, CRDT_UPDT_D1, TM_UPDT, TM_UPDT_D1, CRDT_UPDT_D2, CRDT_UPDT_D3} curr_state_crdt, next_state_crdt;

logic [TM_DSC_BITS-1:0] tm_dsc_sts_avl_d1;
logic [10:0] 		  tm_dsc_sts_qid_d1;
logic tm_update, tm_dsc_sts_qinv_d1, wr_credit_qid_d1, wr_credit_qid_d2, wr_credit_en_d1, wr_credit_en_d2;

always_ff @(posedge axi_aclk) begin 
    rx_qid_d1 <= rx_qid;
    rx_qid_d2 <= rx_qid_d1;
    rx_qid_d3 <= rx_qid_d2;
    rx_qid_d4 <= rx_qid_d3;
    rd_credit_qid_d1 <= rd_credit_qid;
    tm_dsc_sts_qinv_d1 <= tm_dsc_sts_qinv;
    tm_dsc_sts_qid_d1 <= tm_dsc_sts_qid;
    tm_dsc_sts_avl_d1 <= tm_dsc_sts_avl;
    wr_conflict_d1 <= wr_conflict;
    wr_conflict_d2 <= wr_conflict_d1;
    wr_credit_qid_d1 <= wr_credit_qid;
    wr_credit_qid_d2 <= wr_credit_qid_d1;
    wr_credit_en_d1 <= wr_credit_en;
    wr_credit_en_d2 <= wr_credit_en_d1;
end

assign tm_dsc_sts_rdy = 1'b1;
assign tm_update = tm_dsc_sts_vld & (tm_dsc_sts_qen | tm_dsc_sts_qinv ) & ~tm_dsc_sts_mm & tm_dsc_sts_dir;
assign wr_conflict = tm_update & updt_crdt;

//credit fsm
//state logic
always_comb begin 
    rd_credit_qid = rx_qid;
    wr_credit_qid = 0;
    wr_credit_en = 0;
    wr_credit_in = 0;
    case(curr_state_crdt)
        IDLE_CRDT: begin 
            if (tm_update) begin 
                rd_credit_qid = tm_dsc_sts_qid;
            end else if (updt_crdt) begin 
                rd_credit_qid = rx_qid_d1;
            end
        end
        TM_UPDT: begin 
            wr_credit_en = 1'b1;
            wr_credit_qid = tm_dsc_sts_qid_d1;
            wr_credit_in = tm_dsc_sts_qinv_d1 ? 'h0 : rd_credit_out + tm_dsc_sts_avl_d1;
            if (updt_crdt) rd_credit_qid = rx_qid_d1;
            else if (wr_conflict_d1) rd_credit_qid = rx_qid_d2;
            else if (tm_update) rd_credit_qid = tm_dsc_sts_qid;
        end
        TM_UPDT_D1: begin 
            rd_credit_qid = tm_dsc_sts_qid_d1;
        end
        CRDT_UPDT: begin 
            wr_credit_en = 1'b1;
            wr_credit_qid = rx_qid_d3;
            wr_credit_in = rd_credit_out - 1;
            if (tm_update) rd_credit_qid = tm_dsc_sts_qid;
            else if (updt_crdt) rd_credit_qid = rx_qid_d1;
        end
        CRDT_UPDT_D1: begin 
            rd_credit_qid = rx_qid_d2;
        end
        CRDT_UPDT_D2: begin 
            rd_credit_qid = rx_qid_d3;
        end
        CRDT_UPDT_D3: begin 
            wr_credit_en = 1'b1;
            wr_credit_qid = rx_qid_d4;
            wr_credit_in = rd_credit_out - 1;
            if (tm_update) rd_credit_qid = tm_dsc_sts_qid;
            else if (updt_crdt) rd_credit_qid = rx_qid_d1;
        end
    endcase
end
//next_state logic
always_comb begin 
    next_state_crdt = IDLE_CRDT;
    case(curr_state_crdt)
        IDLE_CRDT: begin 
            if(tm_update) next_state_crdt = TM_UPDT;
            else if (updt_crdt) next_state_crdt = CRDT_UPDT;
            else next_state_crdt = IDLE_CRDT;
        end
        TM_UPDT: begin //2 cycles
            // next_state = TM_UPDT_D1;
            if (updt_crdt) next_state_crdt = CRDT_UPDT_D1;
            else if (wr_conflict_d1) next_state_crdt = CRDT_UPDT_D2 ;
            else if (tm_update) next_state_crdt = TM_UPDT_D1;
            else next_state_crdt = IDLE_CRDT;
        end
        TM_UPDT_D1: begin 
            // if (wr_conflict_d2) next_state = CRDT_UPDT;
            next_state_crdt = TM_UPDT;
        end
        CRDT_UPDT: begin //2 cycles
            // next_state = CRDT_UPDT_D1;
            if (tm_update) next_state_crdt = TM_UPDT_D1;
            else if (updt_crdt) next_state_crdt = CRDT_UPDT_D1;
            else next_state_crdt = IDLE_CRDT;
        end
        CRDT_UPDT_D1: begin 
            // if (tm_update) next_state_crdt = TM_UPDT;
            // else if (updt_crdt) next_state_crdt = CRDT_UPDT;
            next_state_crdt = CRDT_UPDT;
        end
        CRDT_UPDT_D2: begin 
            next_state_crdt = CRDT_UPDT_D3;
        end
        CRDT_UPDT_D3: begin 
            if (tm_update) next_state_crdt = TM_UPDT_D1;
            else if (updt_crdt) next_state_crdt = CRDT_UPDT_D1;
            else next_state_crdt = IDLE_CRDT;
        end
    endcase
end

always_ff @(posedge axi_aclk) begin 
    if (~axi_aresetn) begin 
        curr_state_crdt <= IDLE_CRDT;
    end else begin 
        curr_state_crdt <= next_state_crdt;
    end
end

xpm_memory_sdpram #(
   .ADDR_WIDTH_A(11),               // DECIMAL
   .ADDR_WIDTH_B(11),               // DECIMAL
   .AUTO_SLEEP_TIME(0),            // DECIMAL
   .BYTE_WRITE_WIDTH_A(32),        // DECIMAL
   .CASCADE_HEIGHT(0),             // DECIMAL
   .CLOCKING_MODE("common_clock"), // String
   .ECC_MODE("no_ecc"),            // String
   .IGNORE_INIT_SYNTH(0),          // DECIMAL
   .MEMORY_INIT_FILE("none"),      // String
   .MEMORY_INIT_PARAM("0"),        // String
   .MEMORY_OPTIMIZATION("false"),   // String
   .MEMORY_PRIMITIVE("block"),      // String
   .MEMORY_SIZE(2048 * 32),             // DECIMAL
   .MESSAGE_CONTROL(0),            // DECIMAL
   .READ_DATA_WIDTH_B(32),         // DECIMAL
   .READ_LATENCY_B(1),             // DECIMAL
   .READ_RESET_VALUE_B("0"),       // String
   .RST_MODE_A("SYNC"),            // String
   .RST_MODE_B("SYNC"),            // String
   .SIM_ASSERT_CHK(0),             // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
   .USE_EMBEDDED_CONSTRAINT(0),    // DECIMAL
   .USE_MEM_INIT(1),               // DECIMAL
   .USE_MEM_INIT_MMI(0),           // DECIMAL
   .WAKEUP_TIME("disable_sleep"),  // String
   .WRITE_DATA_WIDTH_A(32),        // DECIMAL
   .WRITE_MODE_B("read_first"),     // String
   .WRITE_PROTECT(1)               // DECIMAL
)
xpm_memory_sdpram_inst (
   .dbiterrb(),
   .doutb(rd_credit_out), 
   .sbiterrb(), 
   .addra(wr_credit_qid),    //wr
   .addrb(rd_credit_qid),   //rd
   .clka(axi_aclk), 
   .clkb(axi_aclk),
   .dina(wr_credit_in), 
   .ena(wr_credit_en), 
   .enb(1'b1), //rd_enable
   .injectdbiterra(1'b0),
   .injectsbiterra(1'b0),
   .regceb(1'b1),
   .rstb(~axi_aresetn),              
   .sleep(1'b0),                  
   .wea(wr_credit_en)                       
);

assign DST_MAC = {48'h000000000001, 48'h000000000002, 48'h000000000003, 48'h000000000004};
assign header_buf = {DST_MAC[counter_rr], SRC_MAC, 16'h2121}; //omit the length
// assign rx_qid = qid + counter_rr[10:0]%n_queue;
assign crc = 32'h0a212121;
assign rx_end = (~rx_valid) & (num_pkt == pkt_count);
// assign lst_credit_pkt = (credit_perpkt_in - credit_used_perpkt) == 1;
assign cycles_needed = tot_pkt_size[15:6] +| tot_pkt_size[5:0]; //pkt size must > 64 bytes
assign hash_val = header_buf[69:64] ^ SRC_MAC[5:0];  //dst xor src mac

enum logic [2:0] {IDLE, TRANSFER, WAIT} curr_state, next_state;

//output signal
always_ff @(posedge axi_aclk) begin 
    if (~axi_aresetn) begin 
        // start_c2h <= 0;
        tot_pkt_size <= 0;
    end else begin
        // if (control_reg_1_d) begin 
        //     start_c2h <= 1;
        // end
        // else if (pkt_count >= num_pkt) begin
        //     start_c2h <= 0;
        // end
        tot_pkt_size <= txr_size;
        // control_reg_1_d <= control_reg[1];
    end
    off <= (TEMP - tot_pkt_size + counter_trans)<<3;
end

// always @(posedge axi_aclk)
//     if (~axi_aresetn )
//         credit_in_sync <= 0;
//     else if (~start_c2h )
//         credit_in_sync <= 0;
//     else if (start_c2h & credit_updt)
//         credit_in_sync <= credit_in_sync + credit_in;

//data generation logic
always_comb begin 
    data_buf = {BYTES_PER_BEAT{8'h41}};
    // off = (TEMP - tot_pkt_size + counter_trans)<<3;
    if (is_header) begin 
        data_buf[111:0] = header_buf;
    end
    if (signed'(counter_trans) >= signed'(tot_pkt_size - BYTES_PER_BEAT)) begin 
        data_buf = data_buf << off;
        data_buf[RX_LEN-1 : RX_LEN-32] = crc;
        data_buf = data_buf >> off;
    end 
end
assign rx_data = data_buf;
assign crdt_valid = (wr_credit_en && (wr_credit_qid == rx_qid)) ?  0 : 
                    (wr_credit_en_d1 && (wr_credit_qid_d1 == rx_qid)) ? 0 : (rd_credit_qid_d1 == rx_qid) & (rd_credit_out > 0);

//next_state logic
always_comb begin 
    next_state = IDLE;
    rx_valid = 1'b0;
    rx_last = 1'b0;
    updt_crdt = 1'b0;
    case(curr_state) 
        IDLE: begin 
            if (rx_ready & c2h_perform && crdt_valid) begin 
                next_state = TRANSFER;
            end else begin 
                next_state = IDLE;
            end
            rx_valid = 1'b0;
        end
        TRANSFER: begin 
            if (rx_ready && counter_trans >= (tot_pkt_size - BYTES_PER_BEAT)) begin
                // if (pkt_count == num_pkt-1) next_state = IDLE;
                // else if (rx_ready & crdt_valid & (counter_wait >= cycles_pkt - 1)) next_state = TRANSFER;
                next_state = WAIT;
                updt_crdt = 1'b1;
                rx_last = 1'b1;
            end else begin 
                next_state = TRANSFER;
            end
            rx_valid = 1'b1;
        end
        WAIT: begin 
            if (c2h_perform) begin 
                if (rx_ready & crdt_valid && (counter_wait >= cycles_pkt-1)) begin //check credit
                    next_state = TRANSFER;
                end else begin 
                    next_state = WAIT;
                end
            end else begin 
                next_state = IDLE;
            end
            // if (rx_ready & (pkt_count == num_pkt && ~c2h_perform) && (counter_wait >= cycles_pkt-1) ) begin 
            //     next_state = IDLE;
            // end else if (rx_ready & crdt_valid && (counter_wait >= cycles_pkt-1)) begin //check credit
            //     next_state = TRANSFER;
            // end else begin 
            //     next_state = WAIT;
            // end
            rx_valid = 1'b0;
        end
        endcase
end

always_ff @(posedge axi_aclk) begin 
    if (~axi_aresetn) begin 
        curr_state <= IDLE;
        pkt_count <= 0;
        tcredit_used <= 0;
        counter_wait <= 0;
        counter_trans <= 0;
        is_header <= 1'b1;
        // frame_size <= 0;
        cycles_pkt <= cycles_needed;
        counter_rr <= 0;
        // rx_qid <= qid;
        // updt_crdt <= 1'b0;
    end else begin 
        curr_state <= next_state;
        case(curr_state)
            IDLE: begin 
                // updt_crdt <= 1'b0;
                cycles_pkt <= (cycles_per_pkt > cycles_needed) ? cycles_per_pkt : cycles_needed;
                // frame_size <= tot_pkt_size;
                pkt_count <= 0;
                tcredit_used <= 0;
                counter_wait <= 0;
                counter_trans <= 0;
                is_header <= 1'b1;
                counter_rr <= 0;
                // rx_qid <= qid;
            end
            TRANSFER: begin
                // updt_crdt = 1'b0;
                if (rx_ready) begin 
                    counter_wait = counter_wait + 1;
                    is_header <= 1'b0;
                    if (counter_trans >= (tot_pkt_size - BYTES_PER_BEAT)) begin
                        // counter_wait = 0;
                        counter_trans <= 0;
                        tcredit_used <= tcredit_used + 1;
                        counter_rr <= (counter_rr == 3) ? 0 : counter_rr + 1;
                        // rx_qid <= (rx_qid == qid + num_queue - 1) ? qid : rx_qid + 1;
                        pkt_count <= pkt_count + 1;
                        // updt_crdt <= 1'b1;
                    end 
                    else begin 
                        counter_trans <= counter_trans + BYTES_PER_BEAT;
                    end
                end  
            end
            WAIT: begin 
                // updt_crdt <= 1'b0;
                if (rx_ready) begin
                    is_header <= 1'b1;
                    counter_trans <= 16'h0;
                    // if ((pkt_count == num_pkt) && (counter_wait >= cycles_pkt-1) ) begin 
                    //     counter_wait <= 0;
                    // end else 
                    if (crdt_valid && (counter_wait >= cycles_pkt-1)) begin //check credit
                        counter_wait <= 0;
                    end else begin 
                        counter_wait <= counter_wait + 1;
                    end
                end 
            end
        endcase
        // end
    end
end

endmodule