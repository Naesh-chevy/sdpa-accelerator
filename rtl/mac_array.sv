`include "params.svh"
import attn_pkg::*;

// 4x4 output stationary MAC array, two stage pipeline (multiply, accumulate)
module mac_array #(
    parameter int ROWS = 4,
    parameter int COLS = 4
) (
    input  logic                                            clk,
    input  logic                                            rst_n,
    input  logic                                            clear,
    input  logic                                            en,
    input  logic signed [ROWS-1:0][BITS-1:0]                a,
    input  logic signed [COLS-1:0][BITS-1:0]                b,
    output logic signed [ROWS-1:0][COLS-1:0][ACC_BITS-1:0]  acc
);
    logic signed [ROWS-1:0][COLS-1:0][2*BITS-1:0] prod;
    logic                                          prod_valid;

    // delay en by one cycle to line up with when prod becomes valid
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) prod_valid <= 1'b0;
        else        prod_valid <= en;
    end

    // one always_ff per PE, generated so all indices become compile time constants
    genvar gi, gj;
    generate
        for (gi = 0; gi < ROWS; gi++) begin : row
            for (gj = 0; gj < COLS; gj++) begin : col
                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        prod[gi][gj] <= '0;
                        acc[gi][gj]  <= '0;
                    end else begin
                        if (en)
                            prod[gi][gj] <= $signed(a[gi]) * $signed(b[gj]);

                        if (clear)
                            acc[gi][gj] <= '0;
                        else if (prod_valid)
                            acc[gi][gj] <= $signed(acc[gi][gj]) + $signed(prod[gi][gj]);
                    end
                end
            end
        end
    endgenerate
endmodule