`timescale 1ns/1ps
`include "params.svh"
import attn_pkg::*;

// Full pipeline test. Loads inputs, runs to done, dumps every buffer to a
// hex file. compare.py then checks each stage against the Python reference.
module attention_tb;
    logic clk = 0;
    logic rst_n = 1;
    logic start = 0;
    logic done;

    attention_top dut (
        .clk(clk), .rst_n(rst_n), .start(start), .done(done)
    );

    always #5 clk = ~clk;

    integer f, i;

    initial begin
        $dumpfile("attention_tb.vcd");
        $dumpvars(0, attention_tb);

        // load inputs into the design buffers
        $readmemh("data/x.hex",  dut.x_buf);
        $readmemh("data/wq.hex", dut.wq_buf);
        $readmemh("data/wk.hex", dut.wk_buf);
        $readmemh("data/wv.hex", dut.wv_buf);

        rst_n = 0;
        #20 rst_n = 1;
        @(posedge clk);

        start = 1;
        @(posedge clk);
        start = 0;

        // run to completion with a timeout guard
        fork
            begin
                wait (done == 1'b1);
                $display("reached DONE at t=%0t", $time);
            end
            begin
                repeat (400) @(posedge clk);
                $display("TIMEOUT before DONE");
            end
        join_any
        disable fork;

        @(posedge clk);

        // dump every stage buffer
        f = $fopen("data/out_q.hex", "w");
        for (i = 0; i < 16; i = i + 1) $fdisplay(f, "%04x", dut.q_buf[i] & 16'hFFFF);
        $fclose(f);

        f = $fopen("data/out_k.hex", "w");
        for (i = 0; i < 16; i = i + 1) $fdisplay(f, "%04x", dut.k_buf[i] & 16'hFFFF);
        $fclose(f);

        f = $fopen("data/out_v.hex", "w");
        for (i = 0; i < 16; i = i + 1) $fdisplay(f, "%04x", dut.v_buf[i] & 16'hFFFF);
        $fclose(f);

        f = $fopen("data/out_s.hex", "w");
        for (i = 0; i < 16; i = i + 1) $fdisplay(f, "%04x", dut.s_buf[i] & 16'hFFFF);
        $fclose(f);

        f = $fopen("data/out_a.hex", "w");
        for (i = 0; i < 16; i = i + 1) $fdisplay(f, "%04x", dut.a_buf[i] & 16'hFFFF);
        $fclose(f);

        f = $fopen("data/out_o.hex", "w");
        for (i = 0; i < 16; i = i + 1) $fdisplay(f, "%04x", dut.o_buf[i] & 16'hFFFF);
        $fclose(f);

        $display("buffers dumped to data/out_*.hex");
        $finish;
    end
endmodule