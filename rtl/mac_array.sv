`include "params.svh"
import attn_pkg::*;

// 4x4 output stationary MAC array, two stage pipeline (multiply, accumulate)
module mac_array #(
    parameter int ROWS = 4,
    parameter int COLS = 4
) (
    input  logic                        clk,
    input  logic                        rst_n,
    input  logic                        clear,
    input  logic                        en,
    input  logic signed [BITS-1:0]      a [ROWS],
    input  logic signed [BITS-1:0]      b [COLS],
    output logic signed [ACC_BITS-1:0]  acc [ROWS][COLS]
);
    logic signed [2*BITS-1:0] prod [ROWS][COLS];
    logic                     prod_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prod_valid <= 1'b0;
            for (int i = 0; i < ROWS; i++) begin
                for (int j = 0; j < COLS; j++) begin
                    prod[i][j] <= '0;
                    acc[i][j]  <= '0;
                end
            end
        end else begin
            prod_valid <= en;

            // multiply
            if (en) begin
                for (int i = 0; i < ROWS; i++)
                    for (int j = 0; j < COLS; j++)
                        prod[i][j] <= a[i] * b[j];
            end

            // accumulate, clear takes priority
            if (clear) begin
                for (int i = 0; i < ROWS; i++)
                    for (int j = 0; j < COLS; j++)
                        acc[i][j] <= '0;
            end else if (prod_valid) begin
                for (int i = 0; i < ROWS; i++)
                    for (int j = 0; j < COLS; j++)
                        acc[i][j] <= acc[i][j] + prod[i][j];
            end
        end
    end
endmodule