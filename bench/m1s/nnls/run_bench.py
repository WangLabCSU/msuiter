#!/usr/bin/env python3
# =============================================================================
# bench/m1s/nnls · M1s bench：批量 NNLS（101×10³, k=10）vs scipy.optimize.nnls
# 逐样本（docs/ARCHITECTURE.md §8 预算行，判据 ≥10×；CI 只放 sanity bound）。
#
# 我方 = driver（path 依赖 msuiter-engine）共享 Gram G=WᵀW + 每样本
#   nnls_gram（Lawson-Hanson，pivot LDLᵀ + KKT 断言）——计时段含 Gram/b 装配
#   （保守口径）。scipy 基线 = 对 1000 个样本列逐个 nnls(W, v_j)。
# 协议：双侧各 预热 1 次 + 计时 3 次取中位。
# 正确性锚：样本 0 的暴露向量两侧 max|Δx| 与残差 ‖Wx−v‖² 交叉核对。
#
# 一键重跑：.venv 或系统 python3 bench/m1s/nnls/run_bench.py（需 numpy+scipy）
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
SEED = 20260928  # 全部随机性来源（numpy PCG64），记录在案


def gen_inputs():
    rng = np.random.default_rng(SEED)
    # W：非负签名矩阵（每签名一个尖峰主导通道 + 密度尾，101 通道口径）
    W = rng.random((M, K)) * 0.1
    for s in range(K):
        W[s * 10 % M, s] += 1.0
    W /= W.sum(axis=0, keepdims=True)
    H = rng.random((K, N)) * (500.0 / K)
    V = np.rint(W @ H).astype(np.int64)          # 整数计数
    V += (rng.random((M, N)) < 0.02) * rng.poisson(3.0, (M, N))  # 少量噪声
    np.savetxt(DIR_IN / "W.csv", W, fmt="%.17e", delimiter=",")
    np.savetxt(DIR_IN / "V.csv", V.astype(float), fmt="%.1f", delimiter=",")
    return W, V


def run_ours():
    bin_path = HERE / "driver" / "target" / "release" / "nnls-bench-driver"
    # 始终过一遍 cargo（增量、幂等）：防源码改动后跑陈旧二进制。
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
    batch()                                       # 预热 1 次
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

    # 正确性锚：样本 0 暴露 + 残差（两侧同为非负最小二乘解 ⇒ SSE 应一致到机器精度级）
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
        "# B3 · NNLS bench（ARCHITECTURE §8：批量 NNLS 101×10³, k=10 vs scipy nnls 逐样本 ≥10×）", "",
        f"重跑：`python3 bench/m1s/nnls/run_bench.py`。seed={SEED}（numpy PCG64）；"
        "双侧预热 1 次 + 计时 3 次取中位。我方 = driver（engine `nnls_gram`，"
        "共享 Gram + 每样本 Lawson-Hanson；计时段含 Gram/b 装配，保守口径）；"
        "scipy = `scipy.optimize.nnls(W, v_j)` 逐样本。", "",
        "## 环境", "",
        f"- date: {time.strftime('%Y-%m-%d %H:%M:%S')}",
        f"- python {sys.version.split()[0]} | numpy {np.__version__} | "
        f"scipy {__import__('scipy').__version__} | {sys.platform} "
        "(Apple Silicon；功耗状态不可控，数字为该钉硬件口径)", "",
        "## 数字", "",
        f"- 我方 3 次（ms）：{', '.join(f'{r:.3f}' for r in runs_ours)} → median = {med_ours_ms:.3f} ms",
        f"- scipy 3 次（ms）：{', '.join(f'{r*1e3:.3f}' for r in runs_sp)} → median = {med_sp_s*1e3:.3f} ms",
        f"- **speedup = {speedup:.1f}×；判据 ≥10×：{'PASS' if verdict else 'FAIL'}**",
        f"- 正确性锚：样本 0 max|Δx| = {dx:.3e}；SSE₀ ours={sse0_ours:.6e} "
        f"vs scipy={sse0_sp:.6e}（相对差 {rel:.3e}）",
        f"- 信息项：单样本解成本 ours ≈ {med_ours_ms*1e3/N:.2f} µs vs scipy ≈ "
        f"{med_sp_s*1e6/N:.2f} µs——k=10/m=101 的小规模 NNLS 两侧同为原生 "
        "Lawson-Hanson C/Rust 内核，python 循环开销不构成基线劣势；我方每样本 "
        "的 NnlsSolution 堆分配 + KKT 断言是后续优化候选（batch 并行化是另立口径，不在本预算行）。", "",
    ]
    (HERE / "result.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"result.md written: {HERE / 'result.md'}")
    sys.exit(0 if verdict else 1)


if __name__ == "__main__":
    main()
