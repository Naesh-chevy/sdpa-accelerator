import numpy as np

N, D_MODEL, D_K = 4, 8, 4
Q_FRAC = 12
SCALE = 1 << Q_FRAC

def to_int(x):
    return max(-32768, min(32767, round(x * SCALE)))

def quantize(M):
    return np.array([to_int(v) / SCALE for v in M.flatten()]).reshape(M.shape)

def write_hex(path, M):
    with open(path, "w") as f:
        for v in M.flatten():
            f.write(f"{to_int(float(v)) & 0xFFFF:04x}\n")

def attention(X, Wq, Wk, Wv):
    Q = quantize(X @ Wq)
    K = quantize(X @ Wk)
    V = quantize(X @ Wv)
    S = quantize(Q @ K.T)
    Ss = quantize(S / np.sqrt(D_K))
    # subtract row max for stability
    A = np.exp(Ss - Ss.max(axis=1, keepdims=True))
    A = quantize(A / A.sum(axis=1, keepdims=True))
    O = quantize(A @ V)
    return Q, K, V, S, Ss, A, O

rng = np.random.default_rng(42)
X = np.zeros((N, D_MODEL))
for i in range(N):
    X[i, (2 * i) % D_MODEL] = 1.0
    X[i, (2 * i + 1) % D_MODEL] = 1.0
Wq = rng.uniform(-1.5, 1.5, (D_MODEL, D_K))
Wk = rng.uniform(-1.5, 1.5, (D_MODEL, D_K))
Wv = rng.uniform(-0.5, 0.5, (D_MODEL, D_K))

X, Wq, Wk, Wv = quantize(X), quantize(Wq), quantize(Wk), quantize(Wv)
Q, K, V, S, Ss, A, O = attention(X, Wq, Wk, Wv)

np.set_printoptions(precision=4, suppress=True)
for name, M in [("X", X), ("Wq", Wq), ("Wk", Wk), ("Wv", Wv),
                ("Q", Q), ("K", K), ("V", V),
                ("S", S), ("S_scaled", Ss), ("A", A), ("O", O)]:
    print(f"\n{name}:\n{M}")

print(f"\nsoftmax row sums: {A.sum(axis=1)}")
print(f"max |O| = {np.abs(O).max():.4f}")

write_hex("x.hex", X)
write_hex("wq.hex", Wq)
write_hex("wk.hex", Wk)
write_hex("wv.hex", Wv)
for name, M in [("q", Q), ("k", K), ("v", V), ("s", S),
                ("s_scaled", Ss), ("a", A), ("o", O)]:
    write_hex(f"expected_{name}.hex", M)
