`include "params.svh"
import attn_pkg::*;

// Top level. Holds all buffers, instantiates the MAC array, softmax unit, and
// control FSM, and muxes operands into the MAC array each cycle by phase.
module attention_top (
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    output logic done
);
    // Phase encoding, must match control_fsm
    localparam [3:0]
        P_IDLE=0, P_PROJ_Q=1, P_PROJ_K=2, P_PROJ_V=3,
        P_SCORE=4, P_SCALE=5, P_SOFTMAX=6, P_OUTPUT=7, P_DONE=8;

    // Flat buffers, row major. Loaded by the testbench via $readmemh.
    logic signed [BITS-1:0] x_buf  [0:31];   // 4x8
    logic signed [BITS-1:0] wq_buf [0:31];   // 8x4
    logic signed [BITS-1:0] wk_buf [0:31];
    logic signed [BITS-1:0] wv_buf [0:31];
    logic signed [BITS-1:0] q_buf  [0:15];   // 4x4
    logic signed [BITS-1:0] k_buf  [0:15];
    logic signed [BITS-1:0] v_buf  [0:15];
    logic signed [BITS-1:0] s_buf  [0:15];
    logic signed [BITS-1:0] a_buf  [0:15];
    logic signed [BITS-1:0] o_buf  [0:15];

    // Control
    logic [3:0] phase, k_idx;
    logic [1:0] row_idx;
    logic       mac_clear, mac_en, mac_wb, sm_start, busy, sm_done;

    control_fsm fsm (
        .clk(clk), .rst_n(rst_n), .start(start), .sm_done(sm_done),
        .phase(phase), .k_idx(k_idx), .row_idx(row_idx),
        .mac_clear(mac_clear), .mac_en(mac_en), .mac_wb(mac_wb),
        .sm_start(sm_start), .busy(busy), .done(done)
    );

    // MAC array
    logic signed [3:0][BITS-1:0]          mac_a, mac_b;
    logic signed [3:0][3:0][ACC_BITS-1:0] mac_acc;

    mac_array #(.ROWS(4), .COLS(4)) mac (
        .clk(clk), .rst_n(rst_n), .clear(mac_clear), .en(mac_en),
        .a(mac_a), .b(mac_b), .acc(mac_acc)
    );

    // Operand mux. k_idx is the variable inner-dimension index.
    always @(*) begin
        mac_a = '0;
        mac_b = '0;
        case (phase)
            P_PROJ_Q: begin
                mac_a[0]=x_buf[k_idx];    mac_a[1]=x_buf[8+k_idx];
                mac_a[2]=x_buf[16+k_idx]; mac_a[3]=x_buf[24+k_idx];
                mac_b[0]=wq_buf[k_idx*4]; mac_b[1]=wq_buf[k_idx*4+1];
                mac_b[2]=wq_buf[k_idx*4+2]; mac_b[3]=wq_buf[k_idx*4+3];
            end
            P_PROJ_K: begin
                mac_a[0]=x_buf[k_idx];    mac_a[1]=x_buf[8+k_idx];
                mac_a[2]=x_buf[16+k_idx]; mac_a[3]=x_buf[24+k_idx];
                mac_b[0]=wk_buf[k_idx*4]; mac_b[1]=wk_buf[k_idx*4+1];
                mac_b[2]=wk_buf[k_idx*4+2]; mac_b[3]=wk_buf[k_idx*4+3];
            end
            P_PROJ_V: begin
                mac_a[0]=x_buf[k_idx];    mac_a[1]=x_buf[8+k_idx];
                mac_a[2]=x_buf[16+k_idx]; mac_a[3]=x_buf[24+k_idx];
                mac_b[0]=wv_buf[k_idx*4]; mac_b[1]=wv_buf[k_idx*4+1];
                mac_b[2]=wv_buf[k_idx*4+2]; mac_b[3]=wv_buf[k_idx*4+3];
            end
            P_SCORE: begin
                // S = Q * K^T, so b picks column k_idx of K (K[j][k_idx])
                mac_a[0]=q_buf[k_idx];    mac_a[1]=q_buf[4+k_idx];
                mac_a[2]=q_buf[8+k_idx];  mac_a[3]=q_buf[12+k_idx];
                mac_b[0]=k_buf[k_idx];    mac_b[1]=k_buf[4+k_idx];
                mac_b[2]=k_buf[8+k_idx];  mac_b[3]=k_buf[12+k_idx];
            end
            P_OUTPUT: begin
                mac_a[0]=a_buf[k_idx];    mac_a[1]=a_buf[4+k_idx];
                mac_a[2]=a_buf[8+k_idx];  mac_a[3]=a_buf[12+k_idx];
                mac_b[0]=v_buf[k_idx*4];  mac_b[1]=v_buf[k_idx*4+1];
                mac_b[2]=v_buf[k_idx*4+2]; mac_b[3]=v_buf[k_idx*4+3];
            end
            default: ;
        endcase
    end

    // Writeback: truncate Q16.24 accumulator to Q4.12 (bits [27:12])
    `define WB_ROW(BUF, BASE, R) \
        BUF[BASE+0] <= mac_acc[R][0][27:12]; \
        BUF[BASE+1] <= mac_acc[R][1][27:12]; \
        BUF[BASE+2] <= mac_acc[R][2][27:12]; \
        BUF[BASE+3] <= mac_acc[R][3][27:12];

    always_ff @(posedge clk) begin
        if (mac_wb) begin
            case (phase)
                P_PROJ_Q: begin `WB_ROW(q_buf,0,0) `WB_ROW(q_buf,4,1) `WB_ROW(q_buf,8,2) `WB_ROW(q_buf,12,3) end
                P_PROJ_K: begin `WB_ROW(k_buf,0,0) `WB_ROW(k_buf,4,1) `WB_ROW(k_buf,8,2) `WB_ROW(k_buf,12,3) end
                P_PROJ_V: begin `WB_ROW(v_buf,0,0) `WB_ROW(v_buf,4,1) `WB_ROW(v_buf,8,2) `WB_ROW(v_buf,12,3) end
                P_SCORE:  begin `WB_ROW(s_buf,0,0) `WB_ROW(s_buf,4,1) `WB_ROW(s_buf,8,2) `WB_ROW(s_buf,12,3) end
                P_OUTPUT: begin `WB_ROW(o_buf,0,0) `WB_ROW(o_buf,4,1) `WB_ROW(o_buf,8,2) `WB_ROW(o_buf,12,3) end
                default: ;
            endcase
        end
    end

    // Scale: divide scores by sqrt(d_k)=2, one cycle in place
    integer si;
    always_ff @(posedge clk) begin
        if (phase == P_SCALE)
            for (si = 0; si < 16; si = si + 1)
                s_buf[si] <= s_buf[si] >>> SCALE_SHIFT;
    end

    // Softmax interface
    logic signed [3:0][BITS-1:0] sm_in, sm_out;
    assign sm_in[0] = s_buf[row_idx*4];
    assign sm_in[1] = s_buf[row_idx*4+1];
    assign sm_in[2] = s_buf[row_idx*4+2];
    assign sm_in[3] = s_buf[row_idx*4+3];

    softmax_unit sm (
        .clk(clk), .rst_n(rst_n), .start(sm_start),
        .row_in(sm_in), .row_out(sm_out), .done(sm_done)
    );

    // Capture softmax result into the active row of a_buf
    always_ff @(posedge clk) begin
        if (sm_done) begin
            a_buf[row_idx*4]   <= sm_out[0];
            a_buf[row_idx*4+1] <= sm_out[1];
            a_buf[row_idx*4+2] <= sm_out[2];
            a_buf[row_idx*4+3] <= sm_out[3];
        end
    end

endmodule