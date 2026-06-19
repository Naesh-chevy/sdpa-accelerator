`ifndef PARAMS_SVH
`define PARAMS_SVH

package attn_pkg;
  localparam int N        = 4;
  localparam int D_MODEL  = 8;
  localparam int D_K      = 4;

  localparam int BITS     = 16;
  localparam int Q_FRAC   = 12;
  localparam int ACC_BITS = 40;

  localparam int SCALE_SHIFT = 1;
endpackage

`endif