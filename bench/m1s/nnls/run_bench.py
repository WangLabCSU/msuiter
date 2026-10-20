#!/usr/bin/env python3
# =============================================================================
# bench/m1s/nnls · M1s bench: batch NNLS(101×10³, k=10)vs scipy.optimize.nnls
# per-sample (docs/ARCHITECTURE.md §8 budget row, criterion ≥10×;CI only ships sanity bound).
#
# Ours = driver = driver(path depends on msuiter-engine) shares the Gram G=WᵀW + per-sample
#   nnls_gram(Lawson-Hanson,pivot LDLᵀ + KKT  assertions)—— the timed section includes Gram/b assembly
#   (conservative caliber).scipy baseline = invokes 1000 sample columns one by one with nnls(W, v_j).
# Protocol: each side, warm up 1 run, + timed 3 runs and take the median.
# Correctness anchor: sample 0 s exposed vector agrees on both sides at max|Δx| and the residual ‖Wx−v‖² are cross-checked.
#
# One-shot rerun:.venv or the system python3 bench/m1s/nnls/run_bench.py(requires numpy+scipy)
# =============================================================================
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
from scipy.optimize import nnls

HERE = Path(__file__).resolve().parent
DIR_IN = HERE / "cache" / "input"
DIR_OUT = HERE / "cache" / "output"
DIR_IN.mkdir(parents=True, exist_ok=True)
DIR_OUT.mkdir(parents=True, exist_ok=True)

M, K, N = 101, 10, 1000
SEED = 20260928  # all randomness sources (numpy PCG64); recorded in the manifest


def gen_inputs():
    rng = np.random.default_rng(SEED)
    # W: nonnegative signature matrix (each signature has one dominant spiking channel + density tail,101 channel caliber)
    W = rng.random((M, K)) * 0.1
    for s in range(K):
        W[s * 10 % M, s] += 1.0
    W /= W.sum(axis=0, keepdims=True)
    H = rng.random((K, N)) * (500.0 / K)
    V = np.rint(W @ H).astype(np.int64)          # integer counts
    V += (rng.random((M, N)) < 0.02) * rng.poisson(3.0, (M, N))  # light noise
    np.savetxt(DIR_IN / "W.csv", W, fmt="%.17e", delimiter=",")
    np.savetxt(DIR_IN / "V.csv", V.astype(float), fmt="%.1f", delimiter=",")
    return W, V


def run_ours():
    bin_path = HERE / "driver" / "target" / "release" / "nnls-bench-driver"
    # Always run cargo cargo(incremental, idempotent): prevents running a stale binary after source changes.
    subprocess.run(["cargo", "build", "--release", "--quiet",
                    "--manifest-path", str(HERE / "driver" / "Cargo.toml")],
                   check=True)
    out = subprocess.run([str(bin_path), "--in", str(DIR_IN), "--out", str(DIR_OUT)],
                         capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"driver failed:\n{out.stderr}")
    kv = dict(line.split(",", 1) for line in out.stdout.strip().splitlines())
    runs = [float(kv[f"run{i}"]) for i in range(3)]
    return runs, float(kv["median_ms"]), np.loadtxt(DIR_OUT / "x0.csv", delimiter=",")


def run_scipy(W, V):
    def batch():
        return [nnls(W, V[:, j]) for j in range(N)]
    t0 = time.perf_counter()
    batch()                                       # warm up 1 run
    warm = time.perf_counter() - t0
    runs = []
    for _ in range(3):
        t0 = time.perf_counter()
        res = batch()
        runs.append(time.perf_counter() - t0)
    xs = np.column_stack([r[0] for r in res])
    rsl = np.column_stack([r[1] for r in res])    # scipy: 2-norm residuals
    return runs, float(np.median(runs)), xs, rsl, warm


def main():
    print(f"== M1s NNLS bench: batch {M}x{N}, k={K}, vs scipy per-sample ==")
    print(f"seed={SEED} | numpy {np.__version__} scipy {__import__('scipy').__version__} "
          f"| python {sys.version.split()[0]} | {sys.platform}")
    W, V = gen_inputs()
    print(f"W: {W.shape} (col-normalized) | V: {V.shape} integer counts, "
          f"sum={V.sum():g}")

    runs_ours, med_ours_ms, x0_ours = run_ours()
    for i, r in enumerate(runs_ours):
        print(f"  ours run{i}: {r:.3f} ms")
    print(f"  ours median: {med_ours_ms:.3f} ms")

    runs_sp, med_sp_s, xs_sp, rsl_sp, warm_sp = run_scipy(W, V)
    for i, r in enumerate(runs_sp):
        print(f"  scipy run{i}: {r*1e3:.3f} ms")
    print(f"  scipy median: {med_sp_s*1e3:.3f} ms (warmup {warm_sp*1e3:.1f} ms)")

    # Correctness anchor: sample 0 exposure + + residual (both sides are nonnegative least-squares solutions, so the SSE ⇒ SSE should agree to machine precision)
    x0_sp = xs_sp[:, 0]
    dx = float(np.max(np.abs(x0_ours - x0_sp)))
    sse0_ours = float(np.sum((V[:, 0] - W @ x0_ours) ** 2))
    sse0_sp = float(np.asarray(rsl_sp).ravel()[0] ** 2)
    rel = abs(sse0_ours - sse0_sp) / max(sse0_sp, 1e-300)

    speedup = med_sp_s * 1e3 / med_ours_ms
    verdict = speedup >= 10.0
    print(f"cross-check sample0: max|dx|={dx:.3e} | SSE ours={sse0_ours:.6e} "
          f"scipy={sse0_sp:.6e} rel={rel:.3e}")
    print(f"criterion: speedup = {speedup:.1f}x (>=10x? {'PASS' if verdict else 'FAIL'})")

    lines = [
        "# B3 · NNLS bench(ARCHITECTURE §8: batch NNLS 101×10³, k=10 vs scipy nnls per-sample ≥10×)", "",
        f"Rerun:`python3 bench/m1s/nnls/run_bench.py`.seed={SEED}(numpy PCG64);"
        "Both sides warm up 1 run + timed 3 runs take the median. Ours = driver(engine `nnls_gram`,"
        "shares the Gram + per-sample Lawson-Hanson; the timed section includes Gram/b assembly, conservative caliber);"
        "scipy = `scipy.optimize.nnls(W, v_j)` per-sample.", "",
        "## Environment", "",
        f"- date: {time.strftime('%Y-%m-%d %H:%M:%S')}",
        f"- python {sys.version.split()[0]} | numpy {np.__version__} | "
        f"scipy {__import__('scipy').__version__} | {sys.platform} "
        "(Apple Silicon; the power state is not controllable; figures are for this pinned hardware)", "",
        "## Figures", "",
        f"- Ours 3 3 runs (ms):{', '.join(f'{r:.3f}' for r in runs_ours)} → median = {med_ours_ms:.3f} ms",
        f"- scipy 3 runs (ms):{', '.join(f'{r*1e3:.3f}' for r in runs_sp)} → median = {med_sp_s*1e3:.3f} ms",
        f"- **speedup = {speedup:.1f}×; criterion ≥10×:{'PASS' if verdict else 'FAIL'}**",
        f"- Correctness anchor: sample 0 max|Δx| = {dx:.3e};SSE₀ ours={sse0_ours:.6e} "
        f"vs scipy={sse0_sp:.6e}(relative difference {rel:.3e})",
        f"- Informational: per-sample solve cost ours ≈ {med_ours_ms*1e3/N:.2f} µs vs scipy ≈ "
        f"{med_sp_s*1e6/N:.2f} µs——k=10/m=101 small-scale NNLS are both native "
        "Lawson-Hanson C/Rust kernels;python loop overhead does not form a baseline disadvantage; our per-sample "
        " NnlsSolution heap allocation + KKT assertions are later optimization candidates (batch parallelization is a separate caliber, not in this budget row).", "",
    ]
    (HERE / "result.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"result.md written: {HERE / 'result.md'}")
    sys.exit(0 if verdict else 1)


if __name__ == "__main__":
    main()
