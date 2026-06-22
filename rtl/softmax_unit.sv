`include "params.svh"
import attn_pkg::*;

// Row softmax: 7-stage pipeline (idle, max, exp, sum, recip, norm, done).
// One row per start pulse. Done high for one cycle when output is ready.
module softmax_unit (
    input  logic                        clk,
    input  logic                        rst_n,
    input  logic                        start,
    input  logic signed [3:0][BITS-1:0] row_in,
    output logic signed [3:0][BITS-1:0] row_out,
    output logic                        done
);
    // localparams instead of enum: avoids iverilog always_comb/enum interaction bug
    localparam [2:0]
        S_IDLE  = 3'd0, S_MAX   = 3'd1, S_EXP  = 3'd2,
        S_SUM   = 3'd3, S_RECIP = 3'd4, S_NORM = 3'd5,
        S_DONE  = 3'd6;

    logic [2:0] state, next_state;

    logic signed [BITS-1:0] pwl_slope  [0:7];
    logic signed [BITS-1:0] pwl_offset [0:7];
    logic signed [BITS-1:0] recip_lut  [0:63];

    initial begin
        pwl_slope[0] = 16'sd2589;  pwl_offset[0] = 16'sd4096;
        pwl_slope[1] = 16'sd952;   pwl_offset[1] = 16'sd2459;
        pwl_slope[2] = 16'sd350;   pwl_offset[2] = 16'sd912;
        pwl_slope[3] = 16'sd129;   pwl_offset[3] = 16'sd338;
        pwl_slope[4] = 16'sd47;    pwl_offset[4] = 16'sd122;
        pwl_slope[5] = 16'sd17;    pwl_offset[5] = 16'sd44;
        pwl_slope[6] = 16'sd6;     pwl_offset[6] = 16'sd16;
        pwl_slope[7] = 16'sd2;     pwl_offset[7] = 16'sd6;
        // 16777216 = 2^24: dividing gives 1/sum in Q4.12
        for (int k = 0; k < 48; k++)
            recip_lut[k] = 32'sd16777216 / (32'sd4096 + k * 256);
        for (int k = 48; k < 64; k++)
            recip_lut[k] = 16'sd1024;
    end

    // Unpacked internal registers so each element has exactly one driver
    logic signed [BITS-1:0] row_reg  [0:3];
    logic signed [BITS-1:0] max_reg;
    logic signed [BITS-1:0] exp_reg  [0:3];
    logic signed [BITS-1:0] sum_reg;
    logic signed [BITS-1:0] recip_reg;
    logic signed [BITS-1:0] out_reg  [0:3];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    // always @(*) instead of always_comb: iverilog infers sensitivity correctly
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:  if (start) next_state = S_MAX;
            S_MAX:   next_state = S_EXP;
            S_EXP:   next_state = S_SUM;
            S_SUM:   next_state = S_RECIP;
            S_RECIP: next_state = S_NORM;
            S_NORM:  next_state = S_DONE;
            S_DONE:  next_state = S_IDLE;
            default: next_state = S_IDLE;
        endcase
    end

    // Latch input row (unrolled to avoid variable indexing into packed port)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_reg[0] <= '0; row_reg[1] <= '0;
            row_reg[2] <= '0; row_reg[3] <= '0;
        end else if (state == S_IDLE && start) begin
            row_reg[0] <= row_in[0]; row_reg[1] <= row_in[1];
            row_reg[2] <= row_in[2]; row_reg[3] <= row_in[3];
        end
    end

    // S_MAX: two level comparator tree
    logic signed [BITS-1:0] m01, m23, m_all;
    assign m01   = ($signed(row_reg[0]) > $signed(row_reg[1])) ? row_reg[0] : row_reg[1];
    assign m23   = ($signed(row_reg[2]) > $signed(row_reg[3])) ? row_reg[2] : row_reg[3];
    assign m_all = ($signed(m01) > $signed(m23)) ? m01 : m23;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)              max_reg <= '0;
        else if (state == S_MAX) max_reg <= m_all;
    end

    // S_EXP: max subtraction then 8-segment PWL approximation of e^x
    genvar ge;
    generate
        for (ge = 0; ge < 4; ge++) begin : exp_blk
            logic signed [BITS-1:0]   cent;
            logic signed [BITS-1:0]   neg;
            logic        [3:0]        ipart;
            logic        [2:0]        seg;
            logic signed [2*BITS-1:0] mul;
            logic signed [BITS-1:0]   ev;

            assign cent  = $signed(row_reg[ge]) - $signed(max_reg);
            assign neg   = -cent;
            assign ipart = neg[15:12];
            assign seg   = (ipart >= 4'd8) ? 3'd7 : ipart[2:0];
            assign mul   = $signed(pwl_slope[seg]) * cent;
            assign ev    = (mul >>> 12) + $signed(pwl_offset[seg]);

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n)              exp_reg[ge] <= '0;
                else if (state == S_EXP) exp_reg[ge] <= ev;
            end
        end
    endgenerate

    // S_SUM: accumulate all four exp values
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) sum_reg <= '0;
        else if (state == S_SUM)
            sum_reg <= $signed(exp_reg[0]) + $signed(exp_reg[1])
                     + $signed(exp_reg[2]) + $signed(exp_reg[3]);
    end

    // S_RECIP: clamp index and look up 1/sum
    logic [5:0] recip_idx;
    assign recip_idx = ($signed(sum_reg) <= 16'sd4096)  ? 6'd0
                     : ($signed(sum_reg) >= 16'sd16384) ? 6'd47
                     : (sum_reg - 16'sd4096) >> 8;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)                recip_reg <= '0;
        else if (state == S_RECIP) recip_reg <= recip_lut[recip_idx];
    end

    // S_NORM: per-element multiply by reciprocal
    genvar gn;
    generate
        for (gn = 0; gn < 4; gn++) begin : norm_blk
            logic signed [2*BITS-1:0] mul_n;
            logic signed [BITS-1:0]   nv;

            assign mul_n = $signed(exp_reg[gn]) * $signed(recip_reg);
            assign nv    = mul_n >>> 12;

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n)               out_reg[gn] <= '0;
                else if (state == S_NORM) out_reg[gn] <= nv;
            end
        end
    endgenerate

    assign row_out[0] = out_reg[0];
    assign row_out[1] = out_reg[1];
    assign row_out[2] = out_reg[2];
    assign row_out[3] = out_reg[3];
    assign done = (state == S_DONE);

endmodule