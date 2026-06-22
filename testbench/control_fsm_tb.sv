`timescale 1ns/1ps
`include "params.svh"
import attn_pkg::*;

// Drives the FSM through a full run. Fakes softmax done after a few cycles
// per row. Logs each phase transition and checks the sequence is correct.
module control_fsm_tb;
    logic       clk = 0;
    logic       rst_n = 1;
    logic       start = 0;
    logic       sm_done = 0;
    logic [3:0] phase;
    logic [3:0] k_idx;
    logic [1:0] row_idx;
    logic       mac_clear;
    logic       mac_en;
    logic       sm_start;
    logic       busy;
    logic       done;

    control_fsm dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (start),
        .sm_done   (sm_done),
        .phase     (phase),
        .k_idx     (k_idx),
        .row_idx   (row_idx),
        .mac_clear (mac_clear),
        .mac_en    (mac_en),
        .sm_start  (sm_start),
        .busy      (busy),
        .done      (done)
    );

    always #5 clk = ~clk;

    // phase names for readable logging
    function automatic string pname(input [3:0] p);
        case (p)
            4'd0: pname = "IDLE";
            4'd1: pname = "PROJ_Q";
            4'd2: pname = "PROJ_K";
            4'd3: pname = "PROJ_V";
            4'd4: pname = "SCORE";
            4'd5: pname = "SCALE";
            4'd6: pname = "SOFTMAX";
            4'd7: pname = "OUTPUT";
            4'd8: pname = "DONE";
            default: pname = "?";
        endcase
    endfunction

    // log every phase change
    logic [3:0] last_phase = 4'hF;
    always @(posedge clk) begin
        if (phase != last_phase) begin
            $display("t=%0t  phase -> %s", $time, pname(phase));
            last_phase <= phase;
        end
    end
    
    // fake the softmax unit: assert sm_done 3 cycles after each sm_start pulse
    logic [2:0] sm_timer = 0;
    logic       sm_active = 0;
    always @(posedge clk) begin
        sm_done <= 0;
        if (sm_start) begin
            sm_active <= 1;
            sm_timer  <= 3;
        end else if (sm_active) begin
            if (sm_timer == 1) begin
                sm_done   <= 1;
                sm_active <= 0;
            end
            sm_timer <= sm_timer - 1;
        end
    end

    initial begin
        $dumpfile("fsm_tb.vcd");
        $dumpvars(0, control_fsm_tb);

        rst_n = 0;
        #20 rst_n = 1;
        @(posedge clk);

        // kick off
        start = 1;
        @(posedge clk);
        start = 0;

        // wait for done, with a generous timeout
        fork
            begin
                wait (done == 1'b1);
                $display("t=%0t  PASS  reached DONE", $time);
            end
            begin
                repeat (300) @(posedge clk);
                $display("t=%0t  FAIL  timed out before DONE", $time);
            end
        join_any
        disable fork;

        @(posedge clk);
        $finish;
    end
endmodule