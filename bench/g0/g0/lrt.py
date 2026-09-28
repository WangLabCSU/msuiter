"""自有 χ²₁ presence LRT（P3 增补列；NB 语义）。零第三方依赖（numpy + math）。

模型（逐通道独立计数；W 列各归一化为和 1，h ≥ 0）：
  Poisson/多项语义：x_c ~ Poisson((Wh)_c)。注意当 W 列和为 1 时，
  Poisson 似然与多项似然在 h 上有相同的 argmax 方向，且两者的 LRT
  统计量逐点相等（Poisson MLE 自动把总量拟合到 N；多项在总量上
  scale-invariant）——故一个 Poisson EM 同时服务两个语义。
  NB 语义：x_c ~ NB(mean=(Wh)_c, size=s)，Var = μ + μ²/s，精确似然用
  lgamma 计算（_ll_nb）。NB 对数似然对 μ 的得分为
      ∂ll/∂μ_c = x_c/μ_c − (x_c+s)/(μ_c+s)，
  依其正/负部拆分的乘法 MM 上升更新（Lee–Seung 式梯度拆分）为
      h ← h · Wᵀ(x/μ) / Wᵀ((x+s)/(μ+s))，
  每步 NB 对数似然单调不降（数值验证见 tests/test_lrt.py 与 2026-09-28
  独立审核记录；s→∞ 时退化为经典 Poisson EM h ← h·Wᵀ(x/μ)/Wᵀ1）。
  注意：把 Gamma-Poisson 分层的 E 步权重 z_c=(x_c+s)μ_c/(μ_c+s) 直接当
  乘法权重的做法**不是**该边际似然的 MM 更新——ll 会单调下降并在
  h_cap 处假收敛（2026-09-28 修复前的错误实现，实测 ll 一次评估内
  −1.3×10⁵ → −4.7×10⁵；修复后同一数据 ll = −1.0×10⁴ 且单调上升）。

检验：H0: h_j = 0 vs H1: h_j > 0（边界）。Self–Liang (1987, JASA 82:605)
边界渐近：LRT 统计量的零分布 ≈ ½δ₀ ⊕ ½χ²₁，故边界校准 p 值为
  p = ½·sf_χ²₁(stat) = ½·erfc(√(stat/2))（stat>0；stat=0 时 p=1），
由 math.erfc 实现（无 scipy）。报告列同时给出朴素 χ²₁ sf 作对照。

协议依据：P3（assumption-audit-memo §2）——"Self–Liang 边界渐近为名义
参照"；裁决后增补第 1 条——NB 臂追加经验 size 报告列，与 G0 共用种子数据。
"""

from __future__ import annotations

import math

import numpy as np


def sf_chi2_1(stat: float) -> float:
    """χ²₁ 生存函数 = erfc(√(x/2))。"""
    return math.erfc(math.sqrt(max(stat, 0.0) / 2.0))


def pval_boundary_lrt(stat: float) -> float:
    """Self–Liang 边界校准 p 值 = ½·sf_χ²₁（stat>0）。"""
    if stat <= 0.0:
        return 1.0
    return 0.5 * sf_chi2_1(stat)


def _mu(W: np.ndarray, h: np.ndarray) -> np.ndarray:
    """μ = h @ Wᵀ；h (B,K)，W (96,K) → (B,96)。"""
    return h @ W.T


def _em(counts: np.ndarray, W: np.ndarray, size: float | None = None,
        max_iter: int = 500, tol: float = 1e-10, h_cap: float = 1e9) -> np.ndarray:
    """批量 EM/MM 求 MLE ĥ。counts (B,96) ≥0 整数；返回 (B,K)。

    Poisson（size=None）：h ← h·(Wᵀ(x/μ))/colsum（经典 Poisson EM；
    列和 1 ⇒ 分母 1）。
    NB（size=s）：乘法 MM 上升
        h ← h · Wᵀ(x/μ) / Wᵀ((x+s)/(μ+s))，
    即 NB 对数似然得分 x/μ − (x+s)/(μ+s) 的正/负部梯度拆分更新；
    每步 ll 单调不降。固定点即 NB 得分方程的驻点（列和 1 时两 W 权重
    的公共因子相消，尺度自洽）。
    初始化 h = (Σx/96)·1/K + ε，保证离开精确零边界（乘法更新保号）。
    h_cap：防御性上界（≫ 任何合法 MLE exposure——MLE ≤ 总计数），对
    正常拟合无影响。
    收敛判据是相对步长；NB 的 MM 收敛是线性的，500 轮内 ll 已进入
    驻点 0.1% 量级邻域（LRT 的全/约减模型同步欠收敛只会轻微收缩
    stat，方向保守），不追求机器精度不动点。
    """
    B, C = counts.shape
    K = W.shape[1]
    x = counts.astype(float)
    total = x.sum(axis=1, keepdims=True)                       # (B,1)
    h = np.full((B, K), 1.0 / K) * (total / C) + 1e-12
    colsum = W.sum(axis=0)                                     # (K,)（归一后=1）
    for _ in range(max_iter):
        mu = _mu(W, h)
        # 下限与计数尺度相称（G0 通道计数 ≤1e6）：避免除零
        mu = np.maximum(mu, 1e-12)
        if size is None:
            z = x / mu
            h_new = h * (z @ W) / colsum
        else:
            num = (x / mu) @ W
            den = ((x + size) / (mu + size)) @ W
            h_new = h * num / den
        h_new = np.clip(h_new, 0.0, h_cap)
        delta = np.max(np.abs(h_new - h) / np.maximum(h.sum(axis=1, keepdims=True) / K, 1e-12),
                       axis=1).max()
        h = h_new
        if delta < tol:
            break
    return h


def _ll_poisson(counts: np.ndarray, mu: np.ndarray) -> np.ndarray:
    """逐数据集 Poisson 对数似然（去掉与 h 无关的阶乘常数不影响 LRT）。"""
    x = counts.astype(float)
    mu = np.maximum(mu, 1e-300)
    return (x * np.log(mu) - mu).sum(axis=1)


def _ll_nb(counts: np.ndarray, mu: np.ndarray, size: float) -> np.ndarray:
    """NB(mean=μ, size=s) 精确对数似然（lgamma 形式）。"""
    x = counts.astype(float)
    mu = np.maximum(mu, 1e-300)
    s = float(size)
    lg = np.vectorize(math.lgamma)
    term_shape = lg(x + s) - lg(np.full(x.shape, s)) - lg(x + 1.0)
    return (term_shape
            + s * (np.log(s) - np.log(s + mu))
            + x * (np.log(mu) - np.log(s + mu))).sum(axis=1)


def fit_exposures(counts: np.ndarray, W: np.ndarray, size: float | None = None,
                  **kw) -> np.ndarray:
    """单/批数据集的 MLE ĥ。counts (96,) 或 (B,96)。"""
    c = np.atleast_2d(counts)
    return _em(c, W, size=size, **kw)


def presence_lrt_scan(counts_batch: np.ndarray, W: np.ndarray,
                      test_cols: list, size: float | None = None,
                      alpha: float = 0.05, **em_kw) -> list:
    """对若干目录列做 presence LRT 扫描。

    counts_batch (B,96)；W (96,K) 列和 1；test_cols 为被检验的列号列表。
    对每个 j∈test_cols：全模型 fit（K 列）一次复用；约减模型 fit（去掉
    第 j 列）。返回逐 j 的 dict：stat, p_boundary, p_naive_chi2_1, reject。

    注意：stat = 2(ll_full − ll_reduced)，数值上截到 ≥0（EM 收敛误差
    可能产生微小负值）。
    """
    results = []
    x = np.atleast_2d(counts_batch)
    h_full = _em(x, W, size=size, **em_kw)
    ll_full = (_ll_nb(x, _mu(W, h_full), size) if size is not None
               else _ll_poisson(x, _mu(W, h_full)))
    for j in test_cols:
        keep = [k for k in range(W.shape[1]) if k != j]
        h_red = _em(x, W[:, keep], size=size, **em_kw)
        ll_red = (_ll_nb(x, _mu(W[:, keep], h_red), size) if size is not None
                  else _ll_poisson(x, _mu(W[:, keep], h_red)))
        stat = np.maximum(2.0 * (ll_full - ll_red), 0.0)
        results.append({
            "test_col": j,
            "stat": stat,
            "p_boundary": np.array([pval_boundary_lrt(s) for s in stat]),
            "p_naive_chi2_1": np.array([sf_chi2_1(s) for s in stat]),
            "reject": np.array([pval_boundary_lrt(s) < alpha for s in stat]),
        })
    return results
