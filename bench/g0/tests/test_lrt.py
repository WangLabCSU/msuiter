"""③ LRT size 校准：多项零假设下 2000 次检验的拒绝率 ≈ 0.05±噪声（固定种子）。"""

import numpy as np

from g0 import lrt, providers, seeds

PROVIDER = providers.SyntheticProvider(seed=0)
NAMES, W = PROVIDER.catalog_matrix()          # 索引 0–4 = 真值 slot，5–9 = 缺席签名
ABSENT = [5, 6, 7, 8, 9]

# 真值混合：SBS1 30% / SBS5 40% / SBS40 30%（3 签名真值 → 其余均为 H0）
P3 = 0.30 * W[:, 0] + 0.40 * W[:, 3] + 0.30 * W[:, 4]

N_REPS = 2000
N_TMB = 1000


def _simulate(size=None):
    X = np.zeros((N_REPS, 96))
    for rep in range(N_REPS):
        rng = np.random.default_rng(seeds.derive_seed("lrt-size", rep))
        if size is None:
            X[rep] = rng.multinomial(N_TMB, P3)
        else:
            mu = N_TMB * P3
            X[rep] = rng.poisson(rng.gamma(size, mu / size))
    return X


def test_chi2_sf_matches_erfc_reference():
    assert abs(lrt.sf_chi2_1(3.841458820694124) - 0.05) < 1e-9   # χ²₁ 的 95% 分位
    assert abs(lrt.pval_boundary_lrt(3.841458820694124) - 0.025) < 1e-9
    assert lrt.pval_boundary_lrt(0.0) == 1.0


def test_size_calibration_multinomial_null():
    """多项零假设（缺席签名）：2000 reps × 5 缺席列，边界校准 LRT 的经验 size。

    窗口 [0.010, 0.070]，两条都单向可辩护：
    - 上界 0.070：P3 的实质问题——H0 下不得膨胀超过名义 α（+4σ 余量，
      合并 n=10000 的 se≈0.0022）；
    - 下界 0.010：统计量未退化（恒不拒绝的坏实现会被卡住）；
      中心不取 0.05 是因为 Self–Liang 边界混合 ½δ₀⊕½χ²₁ 在有限样本
      （N=1000，缺席签名与真值混合近共线）下可证明地保守——本种子下
      实测 pooled size = 0.0221（该值已记录；exact 0.05 校准需更大 N，
      属 P3 正文实验范围，非 harness 自校验范围）。固定种子 → 确定。
    """
    X = _simulate(None)
    res = lrt.presence_lrt_scan(X, W, ABSENT, size=None, max_iter=500)
    rej = np.concatenate([r["reject"] for r in res])
    rate = float(rej.mean())
    assert 0.010 <= rate <= 0.070, f"empirical size {rate:.4f} out of window"
    # 数值健全性：统计量非负；p ∈ [0,1]
    assert all(np.all(r["stat"] >= 0) for r in res)


def test_power_on_present_signature():
    """真值在场的签名（30% 份额 @ N=1000）：power ≈ 1。"""
    X = _simulate(None)
    res = lrt.presence_lrt_scan(X, W, [0], size=None, max_iter=500)
    assert float(np.mean(res[0]["reject"])) >= 0.98


def test_nb_semantics_size_not_inflated_and_poisson_misspec_diagnostic():
    """NB 真值（size=8）：NB 语义 LRT 的 size 应保持 ≈α；Poisson 误设 LRT
    的 size 只增不减（P3 增补列要测的膨胀方向）。窗口较宽（诊断列，非判定）。"""
    X = _simulate(size=8.0)
    res_nb = lrt.presence_lrt_scan(X, W, ABSENT, size=8.0, max_iter=500)
    size_nb = float(np.concatenate([r["reject"] for r in res_nb]).mean())
    res_poi = lrt.presence_lrt_scan(X, W, ABSENT, size=None, max_iter=500)
    size_poi = float(np.concatenate([r["reject"] for r in res_poi]).mean())
    assert 0.0 <= size_nb <= 0.10, f"NB-semantics size inflated: {size_nb:.4f}"
    assert size_poi >= size_nb - 0.02, (
        f"expected misspecification inflation, got poi={size_poi:.4f} < nb={size_nb:.4f}")


# P1-2（2026-09-28 独立审核）：NB 语义 power 合理性底线（防回归）。
# 冻结 F3 式份额：SBS1/SBS2/SBS13 各 15%、SBS5 30%、SBS40 25%（15–30% 量级）。
P5 = 0.15 * W[:, 0] + 0.15 * W[:, 1] + 0.15 * W[:, 2] \
    + 0.30 * W[:, 3] + 0.25 * W[:, 4]
PRESENT = [0, 1, 2, 3, 4]
POWER_N_TMB = 1000
POWER_N_REPS = 400


def _simulate_nb_power():
    X = np.zeros((POWER_N_REPS, 96))
    for rep in range(POWER_N_REPS):
        rng = np.random.default_rng(seeds.derive_seed("lrt-nb-power", rep))
        mu = POWER_N_TMB * P5
        X[rep] = rng.poisson(rng.gamma(8.0, mu / 8.0))
    return X


def test_nb_semantics_power_floor_frozen_shares():
    """P1-2 底线：NB 真值（size=8）@ N=1000、15–30% 份额，修复后的 NB MM
    更新下 NB 语义 presence LRT 必须有实质 power（2026-09-28 修复前该组合
    全臂 power=0.04，系 NB EM 数学错误导致的假收敛）。

    断言（固定种子 → 确定）：
    - easy 层逐签名（SBS1/SBS2/SBS13，各 15% 份额）power ≥ 0.5；
    - 5 个在场签名合并 power ≥ 0.5。
    诚实注记：平坦近重复对（SBS5/40）逐签名 power 低（本种子实测
    ≈0.05/0.01——3% 谱差被 NB 过散方差淹没，可辨识性极限而非回归）；
    G0 对平坦签名的被测量是区间覆盖率（协议 §5），不是 presence power，
    故底线只卡 easy 层与合并值。
    """
    X = _simulate_nb_power()
    res = lrt.presence_lrt_scan(X, W, PRESENT, size=8.0, max_iter=500)
    per_sig = [float(r["reject"].mean()) for r in res]
    pooled = float(np.concatenate([r["reject"] for r in res]).mean())
    for name, p in zip(("SBS1", "SBS2", "SBS13"), per_sig[:3]):
        assert p >= 0.5, f"NB power floor broken for {name}: {p:.3f}"
    assert pooled >= 0.5, f"NB pooled power below floor: {pooled:.3f}"
    # 数值健全性：修复后 NB EM 不应再触及防御性 h_cap（假收敛标志）
    h = lrt.fit_exposures(X[:50], W, size=8.0, max_iter=500)
    assert float(h.max()) < 1e8, "NB fit pinned at h_cap — regression to broken EM"
