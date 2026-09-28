"""G0 模拟生成器（协议 §2.2 生成模型 + 裁决第 3 条场景升级）。

真值混合：p = Σ_k f_k · S_k。f 来自冻结真值组合轴 grid.COMPOSITIONS
（adjudication §3「真值组合 ≥6 组」，默认 master = F3 冻结组成），S_k =
provider 提供的 96 通道签名向量（各和 1；cosmic-file 档 = COSMIC 实值，
synthetic 档 = 功能类似物）。真值绝对 exposure h_k = f_k · N（counts）。
每 rep 只重抽计数 X，不重抽组成（协议 §2.2：条件覆盖，避免组成抽样
方差稀释判定功效）。

臂算法（全部文档化的确定算法；同 seed 必产出同 counts）：

  main   X ~ Multinomial(N, p)。
         协议主生成模型：竞品自身假设的世界，在其理想设定下失准是最强、
         混淆最少的证据。params["composition"] ∈ grid.COMPOSITIONS
         （master / clock_only / mmr / pole / flat_triple / strong_flat）。

  nb     X_c ~ Poisson(λ_c),  λ_c ~ Gamma(shape=size, rate=size/μ_c)，
         μ_c = N·p_c。边际 X_c ~ NB(mean=μ_c, size)，Var = μ + μ²/size。
         逐通道独立的 Gamma-Poisson 混合（即 NB 的标准构造）；通道间
         独立、总量不再固定为 N（期望 Σμ = N，实际总量有 NB 波动——
         这是过散世界的一部分，记入输出 realized_total）。
         size 语义与 mSigAct 默认 nbinom.size=8 对齐（P3 增补列共用此臂）。

  clock  p_obs = ρ·p_tumor + (1−ρ)·p_normal，再 Multinomial(N, p_obs)。
         ρ = purity（冻结值 0.4）。p_normal = 正常细胞 clock 型谱，限于
         真值集内取 SBS1 25% / SBS5 75%（正常组织突变以 clock-like
         SBS1/5 为主的文献共识；落在 5 签名集内保证 estimand 仍可定义）。
         ρ=0.4 时 clock 家族份额 45% → 78%（SBS1 21%、SBS5 57%），
         即现实性备忘 §3 的"clock 份额抬升"方向。
         **诊断口径诚实注记（P2g）**：本臂输出的真值 h_k = f_k·N 是
         **未稀释**的肿瘤组成（混合前口径）。稀释后"工具可观测真值"
         （h_obs_k = N·p_obs 的分解中含 normal-clock 份额如何计入
         estimand）存在定义选择——绝对 exposure 覆盖应以哪个口径为
         分母尚待裁决，**待定项**，当前臂只作敏感性报告列不进判定，
         判定语义不受影响。

  sparse p'：SPARSE 签名份额改为 share（冻结 2%），其余签名按原比例
         重归一（×(1−share)/(1−f_sparse)），再 Multinomial(N, p')。
         N=1000 时期望 20 counts（协议 §4：专测边界/清零行为）。

输出 counts 为长度 96 的整数向量，顺序 = tools/channel-reference/
SBS96.txt 规范序（providers.load_sbs96_labels）。
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from .grid import (COMPOSITIONS, SIGNATURE_FAMILY, NB_SIZE, CLOCK_PURITY)
from .providers import ProviderError

DEFAULT_COMPOSITION = "master"

NORMAL_CLOCK_SPECTRUM = {"SBS1": 0.25, "SBS2": 0.0, "SBS13": 0.0,
                         "SBS5": 0.75, "SBS40": 0.0}


@dataclass
class SimCell:
    """一个模拟 cell 的输入与输出。"""

    arm: str
    n: int
    rep: int
    seed: int
    counts: np.ndarray            # (96,) int
    truth_p: np.ndarray           # (96,) 生成用混合（稀释/稀疏变换后）
    truth_h: dict                 # {签名: 真值绝对 exposure（counts，主 estimand）}
    realized_total: int
    params: dict = field(default_factory=dict)


def truth_composition(arm: str, params: dict) -> dict:
    """臂对应的真值组成（冻结组合轴 + 臂特异性变换）。"""
    name = params.get("composition", DEFAULT_COMPOSITION)
    if name not in COMPOSITIONS:
        raise ProviderError(
            f"unknown composition '{name}' (frozen axis: {sorted(COMPOSITIONS)})")
    comp = dict(COMPOSITIONS[name])
    if arm == "sparse":
        sig = params.get("sparse_signature", "SBS13")
        share = float(params.get("sparse_share", 0.02))
        rest = 1.0 - share
        total_rest = sum(v for k, v in comp.items() if k != sig)
        comp = {k: (share if k == sig else v / total_rest * rest)
                for k, v in comp.items()}
    return comp


def truth_spectrum(provider, arm: str, params: dict):
    """返回 (p 生成混合, comp)。p = Σ_k comp[k]·S_k，S_k = provider.signature(k)。"""
    comp = truth_composition(arm, params)
    p = np.zeros(96)
    for name, share in comp.items():
        p += share * provider.signature(name)
    return p, comp


def dilute_for_clock(p: np.ndarray, provider, purity: float) -> np.ndarray:
    """clock 混入：p_obs = ρ·p_tumor + (1−ρ)·p_normal（文档化确定算法）。"""
    p_normal = np.zeros(96)
    for name, w in NORMAL_CLOCK_SPECTRUM.items():
        p_normal += w * provider.truth[name]
    return purity * p + (1.0 - purity) * p_normal


def sample_cell(provider, arm: str, n: int, rep: int, seed: int,
                params: dict | None = None) -> SimCell:
    """按臂语义生成一个 counts 向量。确定性：同 (arm, n, rep, seed) 同输出。"""
    params = dict(params or {})
    rng = np.random.default_rng(seed)
    p_raw, comp = truth_spectrum(provider, arm, params)

    if arm == "clock":
        purity = float(params.get("purity", CLOCK_PURITY))
        p = dilute_for_clock(p_raw, provider, purity)
    else:
        p = p_raw
    p = p / p.sum()

    truth_h = {k: comp[k] * n for k in comp}

    if arm == "nb":
        size = float(params.get("nb_size", NB_SIZE))
        mu = n * p
        # Gamma-Poisson 混合（NB 的标准构造；文档见模块 docstring）
        lam = rng.gamma(shape=size, scale=mu / size)
        counts = rng.poisson(lam)
    else:
        counts = rng.multinomial(n, p)

    return SimCell(arm=arm, n=n, rep=rep, seed=seed, counts=counts.astype(np.int64),
                   truth_p=p, truth_h=truth_h,
                   realized_total=int(counts.sum()), params=params)


def layer_of(signature: str) -> str:
    """报告分层：§2.4 easy/flat（判定子句引用；禁跨签名平均掩盖 flat 层）
    + 组合轴扩展族 mmr/pole/strong（仅覆盖表报告列，不进判定子句）。"""
    fam = SIGNATURE_FAMILY.get(signature)
    if fam is None:
        raise KeyError(signature)
    return fam
