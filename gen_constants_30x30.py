import numpy as np
from itertools import product

N = 30
QMIN, QMAX = -32, 31
NUM_OTHERS = N - 1  # 29

# ----- width sizing (worst case across the whole allowed Q range) -----
h_min = 2*QMIN + NUM_OTHERS*QMIN
h_max = 2*QMAX + NUM_OTHERS*QMAX
term_min, term_max = -QMAX, -QMIN   # widen-before-negate range
lf_min = h_min + NUM_OTHERS*term_min
lf_max = h_max + NUM_OTHERS*term_max
dE_max = max(2*abs(lf_min), 2*abs(lf_max))
print(f"h' range: [{h_min},{h_max}]")
print(f"local_field' range: [{lf_min},{lf_max}]")
print(f"dE'_max: {dE_max}")

def bits_needed_signed(lo, hi):
    import math
    mag = max(abs(lo), abs(hi-0)+1)
    return math.ceil(math.log2(mag)) + 1

print(f"h_i needs >= {bits_needed_signed(h_min,h_max)} bits signed")
print(f"local_field needs >= {bits_needed_signed(lf_min,lf_max)} bits signed")
print(f"dE needs >= {bits_needed_signed(-dE_max,dE_max)} bits signed")

T_start_hw = -dE_max / np.log(0.8)
T_FRAC_BITS = 4
T_reg_start = round(T_start_hw * (1 << T_FRAC_BITS))
print(f"\nT_start (hw units) = {T_start_hw:.2f}  ->  T_reg initial = {T_reg_start} "
      f"(needs {T_reg_start.bit_length()} bits)")

N_TEMPS = 40
SWEEPS_PER_TEMP = 10
T_end_hw = 0.5
alpha = (T_end_hw / T_start_hw) ** (1.0 / N_TEMPS)
ALPHA_FRAC_BITS = 8
alpha_fixed = round(alpha * (1 << ALPHA_FRAC_BITS))
print(f"alpha = {alpha:.4f}, alpha_fixed (Q0.8) = {alpha_fixed}")

print(f"\n2^30 = {2**30:,} states -- brute force is not attempted at this scale")

# ----- generate a random 30x30 symmetric test matrix -----
rng = np.random.default_rng(11)
qd = rng.integers(QMIN, QMAX+1, size=N)
qo = {}
for i in range(N):
    for j in range(i+1, N):
        qo[(i,j)] = int(rng.integers(QMIN, QMAX+1))
def Qij(i,j):
    if i==j: return int(qd[i])
    a,b=min(i,j),max(i,j)
    return qo[(a,b)]

# sanity-check the QUBO<->scaled-Ising identity on many RANDOM states
# (can't enumerate all 2^30, but can verify the algebraic relationship holds
# pointwise on a large random sample -- if the formula were wrong, this would
# almost certainly catch it)
def qubo_energy(x):
    e = sum(Qij(i,i)*x[i] for i in range(N))
    e += sum(Qij(i,j)*x[i]*x[j] for i in range(N) for j in range(i+1,N))
    return e

def h_prime(i):
    return 2*Qij(i,i) + sum(Qij(i,j) for j in range(N) if j!=i)
h = [h_prime(i) for i in range(N)]

def ising_energy_scaled(s):
    e = sum(h[i]*s[i] for i in range(N))
    e += sum(Qij(i,j)*s[i]*s[j] for i in range(N) for j in range(i+1,N))
    return e

const = sum(Qij(i,i) for i in range(N))*0 # placeholder, we check via ratio instead
mismatches = 0
samples = 20000
e0_qubo = None
for trial in range(samples):
    x = tuple(rng.integers(0,2,size=N))
    s = tuple(2*b-1 for b in x)
    eq = qubo_energy(x)
    ei = ising_energy_scaled(s)
    if trial == 0:
        # establish the constant offset from the first sample, then check it's FIXED across all others
        offset = ei - 4*eq
    else:
        if ei - 4*eq != offset:
            mismatches += 1
print(f"\nSanity check over {samples} random states: consistent affine relationship "
      f"(scaled_E = 4*QUBO_E + const) holds: {mismatches==0}")

with open('/home/claude/rtl/matrix_30x30.txt','w') as f:
    for i in range(N):
        for j in range(N):
            f.write(f"        q[{i}][{j}] = {Qij(i,j)};\n")
print("Wrote matrix_30x30.txt")
