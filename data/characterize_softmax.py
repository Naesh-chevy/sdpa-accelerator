import numpy as np

FRAC = 12
SCALE = 1 << FRAC

pwl_slope  = [2589, 952, 350, 129, 47, 17, 6, 2]
pwl_offset = [4096, 2459, 912, 338, 122, 44, 16, 6]

recip_lut = []
for k in range(48):
    recip_lut.append((1 << 24) // (4096 + k * 256))
for k in range(48, 64):
    recip_lut.append(1024)

def to_fixed(x):
    return int(np.round(x * SCALE))

def hw_softmax(row):
    r = [to_fixed(v) for v in row]
    m = max(r)
    cent = [v - m for v in r]
    exp = []
    for c in cent:
        neg = -c
        ipart = neg >> 12
        seg = 7 if ipart >= 8 else ipart
        ev = ((pwl_slope[seg] * c) >> 12) + pwl_offset[seg]
        exp.append(ev)
    s = sum(exp)
    idx = 0 if s <= 4096 else (47 if s >= 16384 else (s - 4096) >> 8)
    recip = recip_lut[idx]
    return [((e * recip) >> 12) / SCALE for e in exp]

def sw_softmax(row):
    a = np.exp(np.array(row) - max(row))
    return a / a.sum()

cases = {
    "uniform":     [0.0, 0.0, 0.0, 0.0],
    "mild":        [1.0, 0.5, 0.2, 0.0],
    "peaked":      [3.0, 0.5, 0.2, 0.0],
    "very peaked": [5.0, 1.0, 0.5, 0.0],
    "two hot":     [2.5, 2.5, 0.1, 0.1],
}

print(f"{'case':14s} {'max abs err':>12s} {'mean abs err':>13s}")
print("-" * 42)
worst_overall = 0.0
for name, row in cases.items():
    hw = np.array(hw_softmax(row))
    sw = sw_softmax(row)
    err = np.abs(hw - sw)
    worst_overall = max(worst_overall, err.max())
    print(f"{name:14s} {err.max():12.5f} {err.mean():13.5f}")

print("-" * 42)
print(f"worst case absolute error across all: {worst_overall:.5f}")
print(f"as percentage of full scale [0,1]:    {worst_overall*100:.2f}%")