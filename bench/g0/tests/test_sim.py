"""① 模拟确定性 + 各臂矩/组成校验。"""

import numpy as np

from g0 import providers, seeds, sim
from g0.grid import NB_SIZE, CLOCK_PURITY

PROVIDER = providers.SyntheticProvider(seed=0)


def _sample(arm, n, rep, seed, params=None):
    return sim.sample_cell(PROVIDER, arm, n, rep, seed, params)


def test_determinism_same_seed_same_counts():
    s = seeds.derive_seed("main", 1000, 7)
    a = _sample("main", 1000, 7, s)
    b = _sample("main", 1000, 7, s)
    assert np.array_equal(a.counts, b.counts)
    assert a.realized_total == b.realized_total == 1000


def test_different_seed_different_counts():
    a = _sample("main", 1000, 1, seeds.derive_seed("main", 1000, 1))
    b = _sample("main", 1000, 2, seeds.derive_seed("main", 1000, 2))
    assert not np.array_equal(a.counts, b.counts)


def test_multinomial_first_moment():
    """主臂：E[X_c] = N·p_c（5000×40 reps，宽松容差）；总量恒为 N。"""
    n, reps = 5000, 40
    p = None
    acc = np.zeros(96)
    for rep in range(reps):
        cell = _sample("main", n, rep, seeds.derive_seed("main", n, rep))
        acc += cell.counts
        p = cell.truth_p
        assert cell.realized_total == n
    emp = acc / (n * reps)
    assert np.allclose(emp, p, rtol=0.08, atol=0.002)


def test_nb_arm_variance_inflation():
    """NB 臂（size=8）：均值 ≈ μ；高计数通道 Var ≈ μ + μ²/8（过散方向）。"""
    n, reps = 2000, 300
    acc, acc2 = np.zeros(96), np.zeros(96)
    for rep in range(reps):
        cell = _sample("nb", n, rep, seeds.derive_seed("nb", n, rep),
                       {"nb_size": NB_SIZE})
        acc += cell.counts
        acc2 += cell.counts ** 2
    mean = acc / reps
    var = acc2 / reps - mean ** 2
    mu = n * (acc / (n * reps))  # 用经验谱近似 μ_c
    hi = mu > 30                                  # 低计数通道矩估计噪声大，只看高通道
    assert np.allclose(mean[hi], mu[hi], rtol=0.10)
    expect_var = mu + mu ** 2 / NB_SIZE
    ratio = var[hi] / expect_var[hi]
    assert np.all(ratio > 0.55) and np.all(ratio < 1.6), ratio


def test_clock_arm_share_uplift():
    """clock 混入臂：p_obs = ρ·p_tumor + (1−ρ)·p_normal，clock 家族份额抬升。"""
    p_main = PROVIDER.truth["SBS1"] * 0.15 + PROVIDER.truth["SBS2"] * 0.15 \
        + PROVIDER.truth["SBS13"] * 0.15 + PROVIDER.truth["SBS5"] * 0.30 \
        + PROVIDER.truth["SBS40"] * 0.25
    p_obs = sim.dilute_for_clock(p_main, PROVIDER, CLOCK_PURITY)
    assert abs(p_obs.sum() - 1.0) < 1e-12
    fam_before = 0.15 + 0.30                       # SBS1 + SBS5
    sbs1 = CLOCK_PURITY * 0.15 + (1 - CLOCK_PURITY) * 0.25
    sbs5 = CLOCK_PURITY * 0.30 + (1 - CLOCK_PURITY) * 0.75
    assert abs(sbs1 - 0.21) < 1e-12 and abs(sbs5 - 0.57) < 1e-12
    assert (sbs1 + sbs5) > fam_before              # 45% → 78%
    # 采样均值方向一致
    acc = np.zeros(96)
    for rep in range(40):
        cell = _sample("clock", 4000, rep, seeds.derive_seed("clock", 4000, rep),
                       {"purity": CLOCK_PURITY})
        acc += cell.counts
    assert np.allclose(acc / (4000 * 40), p_obs, rtol=0.10, atol=0.003)


def test_sparse_arm_composition_and_expectation():
    """稀疏臂：SBS13 → 2%（N=1000 ⇒ E≈20 counts），其余按比例重归一。"""
    comp = sim.truth_composition("sparse", {"sparse_signature": "SBS13",
                                            "sparse_share": 0.02})
    assert abs(comp["SBS13"] - 0.02) < 1e-12
    assert abs(sum(comp.values()) - 1.0) < 1e-12
    assert abs(comp["SBS5"] - 0.30 / 0.85 * 0.98) < 1e-9
    n, reps = 1000, 300
    acc13 = 0.0
    tot13 = 0.0
    for rep in range(reps):
        cell = _sample("sparse", n, rep, seeds.derive_seed("sparse", n, rep),
                       {"sparse_signature": "SBS13", "sparse_share": 0.02})
        tot13 += cell.truth_h["SBS13"]
        acc13 += cell.counts
    assert abs(tot13 / reps - 20.0) < 1e-9          # 真值 h = f·N 精确 20
    # 经验通道均值与生成谱一致（含稀疏成分）
    cell0 = _sample("sparse", n, 0, seeds.derive_seed("sparse", n, 0),
                    {"sparse_signature": "SBS13", "sparse_share": 0.02})
    assert np.allclose(acc13 / (n * reps), cell0.truth_p, rtol=0.10, atol=0.002)


def test_composition_axis_frozen_shares_and_truth_h():
    """真值组合轴（adjudication §3「真值组合 ≥6 组」，P0-3 落库）：
    各组合份额和恒为 1；truth_composition 落库即所写；truth_h = f·N；
    主臂采样均值方向与组合谱一致（粗粒度）；未知组合名必须拒绝。"""
    from g0.grid import COMPOSITIONS
    for name, shares in COMPOSITIONS.items():
        assert abs(sum(shares.values()) - 1.0) < 1e-12, name
    comp = sim.truth_composition("main", {"composition": "mmr"})
    assert comp == dict(COMPOSITIONS["mmr"])
    # 默认 = master（F3 冻结组成）
    assert sim.truth_composition("main", {}) == dict(COMPOSITIONS["master"])
    cell = _sample("main", 1000, 0, seeds.derive_seed("comp", 1000, 0),
                   {"composition": "mmr"})
    assert cell.truth_h == {k: v * 1000 for k, v in COMPOSITIONS["mmr"].items()}
    assert cell.realized_total == 1000
    # 采样均值方向：mmr 组合的生成谱 = Σ f_k·S_k（20 reps 粗校验）
    acc = np.zeros(96)
    for rep in range(20):
        c = _sample("main", 2000, rep, seeds.derive_seed("comp", 2000, rep),
                    {"composition": "strong_flat"})
        acc += c.counts
    p_sf = sum(f * PROVIDER.signature(k) for k, f in COMPOSITIONS["strong_flat"].items())
    assert np.allclose(acc / (2000 * 20), p_sf, rtol=0.12, atol=0.003)
    try:
        sim.truth_composition("main", {"composition": "nope"})
    except Exception as e:
        assert "unknown composition" in str(e)
    else:
        raise AssertionError("unknown composition must be rejected")
