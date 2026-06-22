import sys
from pathlib import Path

FRAC = 12
SCALE = 1 << FRAC
TOL_LSB = 64   # allow 64 LSBs (~0.0156) for softmax approx and rounding

data = Path(__file__).resolve().parent.parent / "data"

def load(path):
    vals = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            v = int(line, 16)
            if v >= 0x8000:
                v -= 0x10000
            vals.append(v)
    return vals

def compare(name, got_file, exp_file, tol=TOL_LSB):
    got = load(data / got_file)
    exp = load(data / exp_file)
    if len(got) != len(exp):
        print(f"{name:10s} FAIL  length {len(got)} vs {len(exp)}")
        return False
    worst = 0
    worst_i = -1
    for i, (g, e) in enumerate(zip(got, exp)):
        d = abs(g - e)
        if d > worst:
            worst, worst_i = d, i
    ok = worst <= tol
    tag = "PASS" if ok else "FAIL"
    print(f"{name:10s} {tag}  max diff {worst} LSB "
          f"({worst/SCALE:+.4f}) at index {worst_i}")
    return ok

stages = [
    ("Q",       "out_q.hex", "expected_q.hex",        TOL_LSB),
    ("K",       "out_k.hex", "expected_k.hex",        TOL_LSB),
    ("V",       "out_v.hex", "expected_v.hex",        TOL_LSB),
    ("S_scaled","out_s.hex", "expected_s_scaled.hex", TOL_LSB),
    ("A",       "out_a.hex", "expected_a.hex",        128),
    ("O",       "out_o.hex", "expected_o.hex",        128),
]

all_ok = True
for name, g, e, tol in stages:
    all_ok &= compare(name, g, e, tol)

print()
print("ALL STAGES PASS" if all_ok else "SOME STAGES FAILED")
sys.exit(0 if all_ok else 1)