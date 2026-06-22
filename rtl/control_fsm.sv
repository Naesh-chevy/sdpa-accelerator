`include "params.svh"
import attn_pkg::*;

// Top-level sequencer. Walks through the five matmul phases and the softmax
// phase, emitting control signals. Operand muxing lives in attention_top.
module control_fsm (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       start,
    input  logic       sm_done,      // from softmax_unit
    output logic [3:0] phase,        // current phase, see localparams
    output logic [3:0] k_idx,        // inner dimension counter
    output logic [1:0] row_idx,      // current row for score/softmax/output
    output logic       mac_clear,
    output logic       mac_en,
    output logic       sm_start,
    output logic       busy,
    output logic       done
);
    // Phases
    localparam [3:0]
        P_IDLE    = 4'd0,
        P_PROJ_Q  = 4'd1,
        P_PROJ_K  = 4'd2,
        P_PROJ_V  = 4'd3,
        P_SCORE   = 4'd4,
        P_SCALE   = 4'd5,
        P_SOFTMAX = 4'd6,
        P_OUTPUT  = 4'd7,
        P_DONE    = 4'd8;

    // Inner-dimension length per matmul phase
    // projections accumulate over D_MODEL, score and output over D_K
    function automatic [3:0] inner_len(input [3:0] ph);
        case (ph)
            P_PROJ_Q, P_PROJ_K, P_PROJ_V: inner_len = D_MODEL[3:0];
            P_SCORE, P_OUTPUT:            inner_len = D_K[3:0];
            default:                      inner_len = 4'd0;
        endcase
    endfunction

    logic [3:0] cur_phase, nxt_phase;
    logic [3:0] k;
    logic [1:0] row;

    // pipeline drain counter: MAC needs 2 extra cycles after last input
    logic [1:0] drain;

    localparam [1:0] ST_RUN = 2'd0, ST_DRAIN = 2'd1, ST_STEP = 2'd2;
    logic [1:0] sub;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cur_phase <= P_IDLE;
            k         <= '0;
            row       <= '0;
            drain     <= '0;
            sub       <= ST_RUN;
        end else begin
            case (cur_phase)
                P_IDLE: begin
                    if (start) begin
                        cur_phase <= P_PROJ_Q;
                        k <= '0; row <= '0; sub <= ST_RUN;
                    end
                end

                // matmul phases share the same control skeleton
                P_PROJ_Q, P_PROJ_K, P_PROJ_V, P_SCORE, P_OUTPUT: begin
                    case (sub)
                        ST_RUN: begin
                            if (k == inner_len(cur_phase) - 1) begin
                                sub   <= ST_DRAIN;
                                drain <= 2'd2;
                            end else begin
                                k <= k + 1;
                            end
                        end
                        ST_DRAIN: begin
                            if (drain == 0) sub <= ST_STEP;
                            else drain <= drain - 1;
                        end
                        ST_STEP: begin
                            // score and output iterate over rows; projections do not
                            if ((cur_phase == P_SCORE || cur_phase == P_OUTPUT)
                                 && row != 2'(N - 1)) begin
                                row <= row + 1;
                                k   <= '0;
                                sub <= ST_RUN;
                            end else begin
                                row       <= '0;
                                k         <= '0;
                                sub       <= ST_RUN;
                                cur_phase <= nxt_phase;
                            end
                        end
                        default: sub <= ST_RUN;
                    endcase
                end

                P_SCALE: begin
                    // single cycle in-place shift, handled in datapath
                    cur_phase <= P_SOFTMAX;
                    row <= '0;
                end

                P_SOFTMAX: begin
                    // one start pulse per row, wait for sm_done between rows
                    if (sm_done) begin
                        if (row == 2'(N - 1)) begin
                            cur_phase <= P_OUTPUT;
                            row <= '0;
                        end else begin
                            row <= row + 1;
                        end
                    end
                end

                P_DONE: cur_phase <= P_IDLE;

                default: cur_phase <= P_IDLE;
            endcase
        end
    end

    // next phase after a matmul phase completes
    always @(*) begin
        case (cur_phase)
            P_PROJ_Q: nxt_phase = P_PROJ_K;
            P_PROJ_K: nxt_phase = P_PROJ_V;
            P_PROJ_V: nxt_phase = P_SCORE;
            P_SCORE:  nxt_phase = P_SCALE;
            P_OUTPUT: nxt_phase = P_DONE;
            default:  nxt_phase = P_IDLE;
        endcase
    end

    // softmax start: pulse on entry to each row of the softmax phase
    logic sm_start_r, sm_seen;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sm_start_r <= 1'b0;
            sm_seen    <= 1'b0;
        end else if (cur_phase == P_SOFTMAX) begin
            if (!sm_seen) begin
                sm_start_r <= 1'b1;   // pulse start for current row
                sm_seen    <= 1'b1;
            end else begin
                sm_start_r <= 1'b0;
                if (sm_done) sm_seen <= 1'b0;  // arm for next row
            end
        end else begin
            sm_start_r <= 1'b0;
            sm_seen    <= 1'b0;
        end
    end

    assign phase     = cur_phase;
    assign k_idx     = k;
    assign row_idx   = row;
    logic is_matmul;
    assign is_matmul = (cur_phase == P_PROJ_Q) || (cur_phase == P_PROJ_K)
                    || (cur_phase == P_PROJ_V) || (cur_phase == P_SCORE)
                    || (cur_phase == P_OUTPUT);

    assign mac_clear = (sub == ST_RUN && k == 0 && is_matmul);
    assign mac_en    = (sub == ST_RUN && is_matmul);
    assign sm_start  = sm_start_r;
    assign busy      = (cur_phase != P_IDLE && cur_phase != P_DONE);
    assign done      = (cur_phase == P_DONE);

endmodule