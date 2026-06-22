# Decode Attention Accelerator

Sequential scaled dot product attention accelerator in SystemVerilog. Single reusable 4x4 MAC array, Q4.12 fixed point datapath, piecewise linear softmax. Designed to run under Icarus Verilog with a Python reference model for verification. Pre-interview task for the ARCH Lab AI Computing Architectures track.

## Architecture

The design implements one transformer attention head in five sequential phases:

1. Project the input X into Q, K, V using three weight matrices
2. Score every query against every key (Q * K^T)
3. Scale by sqrt(d_k), which is a right shift since d_k is a power of two
4. Row wise softmax with max subtraction
5. Mix the value vectors using the softmax weights (A * V)

All five phases share one 4x4 MAC array. A control FSM steers operands into the array each cycle and routes results back to the right buffer. The softmax block sits to the side and takes the score buffer as input.

## Configuration

| Parameter | Value | Notes |
|-----------|-------|-------|
| N | 4 | number of tokens |
| D_MODEL | 8 | input embedding dim |
| D_K | 4 | attention head dim |
| Format | Q4.12 signed | 16 bits per stored value |
| Accumulator | 40 bits | 24 bits of growth headroom |
| MAC array | 4x4 | output stationary |
| Softmax | 8 segment PWL exp, 64 entry reciprocal LUT | with max subtraction |

## Repository layout
'''
.
├── rtl/
│   ├── params.svh        shared parameters
│   ├── mac_array.sv      4x4 MAC array
│   ├── softmax_unit.sv   max, exp PWL, reciprocal LUT
│   ├── control_fsm.sv    phase sequencer
│   └── attention_top.sv  top level
├── tb/
│   ├── attention_tb.sv   top level testbench
│   └── compare.py        per stage verification
├── data/
│   ├── gen_test_data.py  reference model and hex file generator
│   └── *.hex             generated inputs and expected outputs
└── README.md
'''

## Build and run

Generate the test data:

'''
cd data
python3 gen_test_data.py
cd ..
'''

Run the simulation:

'''
iverilog -g2012 -o sim.out rtl/*.sv tb/attention_tb.sv
vvp sim.out
'''

Verify against the reference:

'''
python3 tb/compare.py
'''

View waveforms:

'''
gtkwave dump.vcd
'''

## Design decisions

### Sequential rather than parallel

The MAC array is reused across all five matmul phases. This trades throughput for area, matching the framing of this design as a decode side accelerator. Decode generates one token at a time and is memory bound on modern systems, so a smaller compute fabric kept busy is more area efficient than a larger one used briefly. A fully parallel design with separate matmul units per phase would be the right call for a prefill accelerator instead.

### Q4.12 fixed point

Four integer bits gives a range of about ±8, comfortable headroom over the typical [-1, 1] range of trained weights and embeddings. Twelve fractional bits gives resolution near 0.00024, plenty for attention weights which only need a few digits of precision. Floating point would burn area on a normalizer this design does not need.

### 40 bit accumulator

Two Q4.12 values multiplied give a 32 bit result. Summed over the inner dimension of the matmul (up to 8 for projections), values can grow by log2(8) = 3 bits. Forty bits leaves enough margin to never saturate on realistic inputs.

### Softmax

Three stages:

1. Find the row max and subtract it. After subtraction every input to exp is non-positive, bounding exp in (0, 1] and removing all overflow risk.
2. Approximate exp with eight piecewise linear segments. Each segment is a slope and offset pair stored in registers.
3. Sum the exponentials, look up the reciprocal in a 64 entry table, multiply each exponential by the reciprocal. Avoids a hardware divider.

Piecewise linear was chosen over shift based methods like Softermax because attention weights concentrate in the small input region where shift methods lose the most precision. Reciprocal LUT was chosen over log sum exp because it replaces division with one lookup and a multiply.

### Scaling collapses to a shift

With D_K = 4, sqrt(D_K) = 2, so the scaling step is a one bit right shift. The choice of D_K as a power of two is intentional.

## Verification

`gen_test_data.py` produces both the input hex files and the expected output at every pipeline stage. The testbench loads the inputs into the design, runs the FSM through every phase, and dumps the contents of each buffer.

`compare.py` checks the HDL outputs against the expected files element by element.

Full pipeline result on a peaked test case:

| Stage | Max error | Notes |
|-------|-----------|-------|
| Q, K, V | 0 LSB | bit exact projections |
| S scaled | 1 LSB | single rounding bit from the shift |
| A | 112 LSB (2.7%) | softmax approximation |
| O | 60 LSB (1.5%) | softmax error propagated through A V |


### Softmax characterization

`characterize_softmax.py` reimplements the exact hardware softmax math (same PWL table, same reciprocal LUT, same bit shifts) and runs it against true softmax across distributions from uniform to sharply peaked:

| Distribution | Max absolute error |
|--------------|--------------------|
| uniform | 0.4% |
| mild | 2.3% |
| peaked | 0.9% |
| very peaked | 3.5% |
| two hot | 0.5% |

Worst case is 3.5 percent on the most peaked input, which is the segment 4 region where the eight segment piecewise linear fit is least tight. This is the approximation errorand could be reduced with more segments at the cost of area.


## Latency

The full operation completes in roughly 135 cycles for this configuration. The projections dominate because each accumulates over D_MODEL = 8, while the score and output matmuls accumulate over D_K = 4. The softmax adds a fixed seven cycles per row. Because the design is sequential, latency scales with the sum of the matmul inner dimensions rather than running them in parallel, which is the area for latency trade described above.

## Not in scope

Multi head attention, causal masking, variable sequence length, synthesis to a specific FPGA target, and the backward pass are all out of scope for this task.