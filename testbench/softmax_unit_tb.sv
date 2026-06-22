`timescale 1ns/1ps
`include "params.svh"
import attn_pkg::*;

`define CHECK_EL(N, V) \
    if (row_out[N] === (V)) \
        $display("PASS  row_out[%0d] = 0x%h", N, row_out[N]); \
    else \
        $display("FAIL  row_out[%0d] = 0x%h (expected 0x%h)", N, row_out[N], (V));

// Input [0,0,0,0]: max=0, cent=0, e^0=1.0=4096, sum=16384.
// recip_lut[47]=1040. Each output = 4096*1040>>12 = 1040 = 0x0410.
module softmax_unit_tb;
    logic clk = 0;
    logic rst_n = 1;
    logic start = 0;
    logic signed [3:0][BITS-1:0] row_in;
    logic signed [3:0][BITS-1:0] row_out;
    logic done;

    softmax_unit dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .start   (start),
        .row_in  (row_in),
        .row_out (row_out),
        .done    (done)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("softmax_tb.vcd");
        $dumpvars(0, softmax_unit_tb);

        row_in = '0;

        rst_n = 0;
        #20 rst_n = 1;
        @(posedge clk);

        start = 1;
        @(posedge clk);
        start = 0;

        // wait for done, with a timeout guard
        fork
            begin
                wait (done == 1'b1);
                $display("PASS  done fired");
            end
            begin
                repeat (20) @(posedge clk);
                $display("FAIL  done did not fire within timeout");
            end
        join_any
        disable fork;

        `CHECK_EL(0, 16'sh0410)
        `CHECK_EL(1, 16'sh0410)
        `CHECK_EL(2, 16'sh0410)
        `CHECK_EL(3, 16'sh0410)

        $finish;
    end

    // probe: print state every clock
    always @(posedge clk)
        $display("t=%0t  state=%0d  done=%b  out0=0x%h",
                 $time, dut.state, done, row_out[0]);
endmodule