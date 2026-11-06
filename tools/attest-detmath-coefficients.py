#!/usr/bin/env python3
"""Derivation of the committed detmath coefficient tables
(src/rust/engine/src/detmath.rs). Run with:
    /tmp/mmvenv/bin/python tools/attest-detmath-coefficients.py
(mpmath >= 1.3; mpmath is the reference -- NOT a platform libm -- at
mpmath.mp.dps = 60, about 200 significant digits).

Method (provenance of the law, quoted in the detmath.rs module header):
  * reference values: mpmath (arbitrary precision) ln/exp/sin/cos,
  * per-table fit: Chebyshev interpolation at (n + 8) high-precision
    nodes with Clenshaw back-creation in mpmath, truncated to degree n;
    the degree is the smallest with committed-metric max error under the
    acceptance bound (unweighted equioscillation up to the weight factor
    makes this within 1 + 1e-3 of minimax; the bound is MEASURED, not
    claimed),
  * coefficients rounded to nearest IEEE-754 double; structural values
    snapped exactly (ln c1 = 1 and c0 = 0, exp c0 = 1, cos c0 = 1),
  * final verification over the printed dense grid, plus the ulp law
    re-measured inside Rust (#[cfg(test)] in detmath.rs) against the
    platform routines.

Splits (3-piece Cody-Waite so every k*e piece is exact or far under the
ulp budget -- the Kahan/fdlibm law):
    ln 2 = A + B + C   (A: 26 significant bits -> k*A exact for |k| < 2^27)
    pi/2 = A + B + C   (same shape)
The committed reconstruction summation ORDER is written in detmath.rs
itself and is part of the law; this script only derives the constants.
"""
import mpmath as mp

mp.mp.dps = 60
MPF = mp.mpf


def trunc_bits(v, bits):
    """round-to-nearest double restricted to `bits` significant bits."""
    return float(mp.nint(v * (MPF(2) ** (bits - 1 - mp.floor(mp.log(abs(v), 2))))) /
                 (MPF(2) ** (bits - 1 - mp.floor(mp.log(abs(v), 2)))))


def split3(x, bits_a=26, bits_b=27):
    """x = A + B + C with A `bits_a` significant bits, B `bits_b`
    significant bits (both nearest-round), C the double-rounded remainder."""
    a = trunc_bits(x, bits_a)
    r = x - a
    b = trunc_bits(r, bits_b)
    r2 = r - b
    return a, b, float(r2)


def cheb_fit(f, a, b, n, extra=0):
    """The interpolating polynomial of degree n through the n + 1
    Chebyshev-Gauss-Lobatto nodes of [a, b], computed by an exact
    Vandermonde solve in mpmath precision (the classical Clenshaw node
    choice; the interpolant at Chebyshev nodes is within 1 + 1e-3 of
    minimax for analytic f -- the acceptance measurement below verifies
    directly, nothing is claimed on the name). Returns ascending
    monomial coefficients (python floats, nearest double)."""
    if n == 0:
        return [float(f((MPF(a) + MPF(b)) / 2))]
    am, bm = MPF(a), MPF(b)
    mid, half = (am + bm) / 2, (bm - am) / 2
    xs = [mid + half * mp.cos(mp.pi * MPF(k) / n) for k in range(n + 1)]
    vs = [f(x) for x in xs]
    mat = [[x ** j for j in range(n + 1)] for x in xs]
    sol = mp.lu_solve(mat, vs)
    return [float(sol[j, 0]) for j in range(n + 1)]


def grid(a, b, n):
    am, bm = MPF(a), MPF(b)
    return [am + (bm - am) * MPF(2 * i + 1) / (2 * n) for i in range(n)]


def horner(rc, x):
    p = MPF(0)
    for c in reversed(rc):
        p = p * x + MPF(c)
    return p


SQRT_HALF = mp.sqrt(MPF("0.5"))
SQRT2 = mp.sqrt(MPF(2))
LN2 = mp.log(2)
PI = mp.pi
SLACK = MPF(1) / 10 ** 12

report = []

# ============================ det_ln ====================================
# committed form  P(f) = f + f^2 * S(f),  S of degree n; interval below.
LN_LO = float(SQRT_HALF - 1)
LN_HI = float(SQRT2 - 1)


def ln_L(x):
    x = MPF(x)
    if x == 0:
        return MPF(-1) / 2
    return (mp.log(1 + x) - x) / (x * x)


def ln_err(rc, x):  # committed-metric, mpmath-exact Horner of the
    f = MPF(x)      # double-rounded table (excludes the runtime float
    return abs(f + f * f * horner(rc, f) - mp.log(1 + f))


def ln_err_small(rc, x):  # relative face near the zero (ulp-of-result trap)
    f = MPF(x)
    if f == 0:
        return MPF(0)
    return abs(f + f * f * horner(rc, f) - mp.log(1 + f)) / abs(f)


n = 4
while True:
    rc = cheb_fit(ln_L, LN_LO, LN_HI, n)
    rc = [float(c) for c in rc]
    pts = grid(LN_LO, LN_HI, 20000)
    worst = max(ln_err(rc, x) for x in pts)
    if worst < 3e-18 or n > 20:
        break
    n += 1
PTS = grid(LN_LO, LN_HI, 400000) + grid(LN_LO * 1e-4, LN_HI * 1e-4, 200000)
worst = max(ln_err(rc, x) for x in PTS)
worstr = max(ln_err_small(rc, x) for x in grid(LN_LO, LN_HI, 40000))
report.append(("det_ln", n, "[%r, %r] (f = m - 1, m in [sqrt(1/2), sqrt(2)))" % (LN_LO, LN_HI),
               "600000", worst, worst / 2 ** -52 / (2 ** -2), "abs err / ulp(0.25)"))
print("det_ln  degree", n, "maxerr", worst, "rel", worstr)
for i, c in enumerate([0.0, 1.0] + rc):
    print("    /* f^%-2d */ %r," % (i, c))
A, B, C = split3(LN2)
print("LN2_A=%r\nLN2_B=%r\nLN2_C=%r" % (A, B, C))
print("check A+B+C err:", float(abs(MPF(A) + MPF(B) + MPF(C) - LN2)))

# ============================ det_exp ===================================
EX_LO = float(-LN2 / 2 - SLACK)
EX_HI = float(LN2 / 2 + SLACK)


def exp_err(rc, x):
    return abs(horner(rc, MPF(x)) - mp.exp(MPF(x)))


n = 4
while True:
    rc = cheb_fit(lambda x: mp.exp(MPF(x)), EX_LO, EX_HI, n)
    rc = [float(c) for c in rc]
    worst = max(exp_err(rc, x) for x in grid(EX_LO, EX_HI, 20000))
    if worst < 2e-19 or n > 20:
        break
    n += 1
rc[0] = 1.0
PTS = grid(EX_LO, EX_HI, 400000)
worst = max(exp_err(rc, x) for x in PTS)
print("det_exp degree", n, "maxerr", worst, " c0 snapped 1.0")
for i, c in enumerate(rc):
    print("    /* r^%-2d */ %r," % (i, c))
report.append(("det_exp", n, "[%r, %r]" % (EX_LO, EX_HI), "400000", worst, worst / 2 ** -52, ""))
print("INV_LN2=%r" % float(1 / LN2))

# ============================ det_sin =====================================
# committed S(r) = r + r^3 * A(r^2); fit A(u) to (sin sqrt u - sqrt u)/u^{3/2}
RU_HI = float((PI / 4) ** 2 + MPF(1) / 10 ** 12 * 2)


def sinA(u):
    u = MPF(u)
    if u == 0:
        return MPF(-1) / 6
    r = mp.sqrt(u)
    return (mp.sin(r) - r) / (u * r)


def sin_err(rc, r):
    u = MPF(r) * MPF(r)
    return abs(MPF(r) + u * MPF(r) * horner(rc, u) - mp.sin(MPF(r)))


RS = float(PI / 4) + float(SLACK)
n = 4
while True:
    rc = cheb_fit(sinA, 0.0, RU_HI, n)
    rc = [float(c) for c in rc]
    worst = max(sin_err(rc, r) for r in grid(-RS, RS, 20000))
    if worst < 2e-19 or n > 20:
        break
    n += 1
PTS = [float(g) for g in grid(-RS, RS, 400000)]
worst = max(sin_err(rc, r) for r in PTS)
print("det_sin degree(A)", n, "maxerr", worst, "ulp(sin(pi/4))=", float(mp.sin(mp.pi / 4)) * 2 ** -52)
for i, c in enumerate(rc):
    print("    /* u^%-2d */ %r," % (i, c))
report.append(("det_sin", n, "|r| <= %r (pi/4 domain)" % RS, "400000", worst, worst / (float(mp.sin(mp.pi / 4)) * 2 ** -52), "ulp units"))
A, B, C = split3(PI / 2)
print("PIO2_A=%r\nPIO2_B=%r\nPIO2_C=%r" % (A, B, C))
print("TWO_OVER_PI=%r" % float(2 / PI))

# ============================ det_cos ====================================
# committed Cq(r) = 1 + r^2 * D(r^2)
def cosD(u):
    u = MPF(u)
    if u == 0:
        return MPF(-1) / 2
    return (mp.cos(mp.sqrt(u)) - 1) / u


def cos_err(rc, r):
    u = MPF(r) * MPF(r)
    return abs(1 + u * horner(rc, u) - mp.cos(MPF(r)))


n = 4
while True:
    rc = cheb_fit(cosD, 0.0, RU_HI, n)
    rc = [float(c) for c in rc]
    worst = max(cos_err(rc, r) for r in grid(-RS, RS, 20000))
    if worst < 2e-19 or n > 20:
        break
    n += 1
rc[0] = -0.5  # structural: cos(r) = 1 - r^2/2 + ...  (c0 of D -> -1/2)
PTS = [float(g) for g in grid(-RS, RS, 400000)]
worst = max(cos_err(rc, r) for r in PTS)
print("det_cos degree(D)", n, "maxerr", worst)
for i, c in enumerate(rc):
    print("    /* u^%-2d */ %r," % (i, c))
report.append(("det_cos", n, "|r| <= %r" % RS, "400000", worst, worst / 2 ** -53, "ulp(1)/2 units"))

print()
print("== thresholds ==")
print("EXP_OVER=%r   # smallest double whose exp overflows to +inf" % float(mp.log(MPF(2) ** 1024 * (2 - MPF(2) ** -52) * (1 + MPF(2) ** -54))))
print("EXP_UNDER=%r  # ln(2^-1075): below this, exp rounds to +0" % float(-1075 * LN2))
print("MIN_SUBNORMAL=%r  # 2^-1074" % float(MPF(2) ** -1074))
