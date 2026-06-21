`timescale 1ns/1ps
`include "params.svh"
import attn_pkg::*;

// Isolated test for mac_array. Feeds four cycles of a = b = [1.0, 1.0, 1.0, 1.0]
// in Q4.12 and checks each accumulator reaches 4.0 in Q8.24.
module mac_array_tb;
    logic clk = 0;
    logic rst_n;
    logic clear;
    logic en;
    logic signed [BITS-1:0]     a [4];
    logic signed [BITS-1:0]     b [4];
    logic signed [ACC_BITS-1:0] acc [4][4];

    mac_array #(.ROWS(4), .COLS(4)) dut (.*);

    always #5 clk = ~clk;

    initial begin
        $dumpfile("mac_tb.vcd");
        $dumpvars(0, mac_array_tb);

        // initial state
        rst_n = 0;
        clear = 0;
        en    = 0;
        for (int i = 0; i < 4; i++) begin
            a[i] = 0;
            b[i] = 0;
        end

        // release reset
        #20 rst_n = 1;
        @(posedge clk);

        // zero accumulators
        clear = 1;
        @(posedge clk);
        clear = 0;

        // feed four cycles of 1.0 * 1.0
        en = 1;
        for (int k = 0; k < 4; k++) begin
            for (int i = 0; i < 4; i++) begin
                a[i] = 16'h1000;
                b[i] = 16'h1000;
            end
            @(posedge clk);
        end

        // drain pipeline
        en = 0;
        @(posedge clk);
        @(posedge clk);

        // check (expected 4.0 in Q8.24 = 0x04000000)
        for (int i = 0; i < 4; i++) begin
            for (int j = 0; j < 4; j++) begin
                if (acc[i][j] === 'sh04000000)
                    $display("PASS  acc[%0d][%0d] = 0x%h", i, j, acc[i][j]);
                else
                    $display("FAIL  acc[%0d][%0d] = 0x%h (expected 0x04000000)", i, j, acc[i][j]);
            end
        end

        $finish;
    end
endmodule