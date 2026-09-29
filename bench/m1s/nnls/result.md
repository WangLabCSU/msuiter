# B3 · NNLS bench（ARCHITECTURE §8：批量 NNLS 101×10³, k=10 vs scipy nnls 逐样本 ≥10×）

重跑：`python3 bench/m1s/nnls/run_bench.py`。seed=20260928（numpy PCG64）；双侧预热 1 次 + 计时 3 次取中位。我方 = driver（engine `nnls_gram`，共享 Gram + 每样本 Lawson-Hanson；计时段含 Gram/b 装配，保守口径）；scipy = `scipy.optimize.nnls(W, v_j)` 逐样本。

## 环境

- date: 2026-09-30 07:34:59
- python 3.13.9 | numpy 2.3.5 | scipy 1.17.0 | darwin (Apple Silicon；功耗状态不可控，数字为该钉硬件口径)

## 数字

- 我方 3 次（ms）：7.610, 6.606, 6.568 → median = 6.606 ms
- scipy 3 次（ms）：11.389, 11.323, 11.258 → median = 11.323 ms
- **speedup = 1.7×；判据 ≥10×：FAIL**
- 正确性锚：样本 0 max|Δx| = 3.768e-11；SSE₀ ours=9.660059e+00 vs scipy=9.660059e+00（相对差 3.678e-16）
- 信息项：单样本解成本 ours ≈ 6.61 µs vs scipy ≈ 11.32 µs——k=10/m=101 的小规模 NNLS 两侧同为原生 Lawson-Hanson C/Rust 内核，python 循环开销不构成基线劣势；我方每样本 的 NnlsSolution 堆分配 + KKT 断言是后续优化候选（batch 并行化是另立口径，不在本预算行）。
