`timescale 1ns/1ps
`include "params.svh"
import attn_pkg::*;

// Macro expands at compile time so all indices into acc are constants
`define CHECK(I, J) \
    if (acc[I][J] === 40'sh04000000) \
        $display("PASS  acc[%0d][%0d] = 0x%h", I, J, acc[I][J]); \
    else \
        $display("FAIL  acc[%0d][%0d] = 0x%h (expected 0x04000000)", I, J, acc[I][J]);

// Isolated test for mac_array. Feeds four cycles of a = b = [1.0, 1.0, 1.0, 1.0]
// in Q4.12 and checks each accumulator reaches 4.0 in Q8.24.
module mac_array_tb;
    logic clk = 0;
    logic rst_n = 1;
    logic clear;
    logic en;
    logic signed [3:0][BITS-1:0]          a;
    logic signed [3:0][BITS-1:0]          b;
    logic signed [3:0][3:0][ACC_BITS-1:0] acc;

    mac_array #(.ROWS(4), .COLS(4)) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .clear (clear),
        .en    (en),
        .a     (a),
        .b     (b),
        .acc   (acc)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("mac_tb.vcd");
        $dumpvars(0, mac_array_tb);

        clear = 0;
        en    = 0;
        a     = '0;
        b     = '0;

        rst_n = 0;
        #20 rst_n = 1;
        @(posedge clk);

        clear = 1;
        @(posedge clk);
        clear = 0;

        a  = {4{16'h1000}};
        b  = {4{16'h1000}};
        en = 1;
        repeat (4) @(posedge clk);

        en = 0;
        @(posedge clk);
        @(posedge clk);

        // expected 4.0 in Q8.24 = 0x04000000
        `CHECK(0, 0) `CHECK(0, 1) `CHECK(0, 2) `CHECK(0, 3)
        `CHECK(1, 0) `CHECK(1, 1) `CHECK(1, 2) `CHECK(1, 3)
        `CHECK(2, 0) `CHECK(2, 1) `CHECK(2, 2) `CHECK(2, 3)
        `CHECK(3, 0) `CHECK(3, 1) `CHECK(3, 2) `CHECK(3, 3)

        $finish;
    end
endmodule