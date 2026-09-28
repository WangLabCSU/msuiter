"""② 覆盖率计算器正确性：CP 解析锚点 + 已知 σ 高斯名义 95% + 判定规则三叉。"""

import numpy as np

from g0 import coverage as cov
from g0 import sim

LAYER = sim.layer_of


def test_cp_closed_form_anchors():
    n = 10
    lo0, hi0 = cov.clopper_pearson(0, n)
    lon, hin = cov.clopper_pearson(n, n)
    assert abs(hi0 - (1 - 0.025 ** (1 / n))) < 1e-12
    assert abs(lon - 0.025 ** (1 / n)) < 1e-12
    assert lo0 == 0.0 and hin == 1.0


def test_cp_reference_value_and_monotonicity():
    # 教科书值：k=95, n=100 → (0.8872, 0.9836)
    lo, hi = cov.clopper_pearson(95, 100)
    assert abs(lo - 0.8872) < 1e-3 and abs(hi - 0.9836) < 1e-3
    # k 增大 → 区间整体右移（lo、hi 均随 k 上升）
    lo_a, hi_a = cov.clopper_pearson(160, 200)
    lo_b, hi_b = cov.clopper_pearson(180, 200)
    assert lo_b > lo_a and hi_b > hi_a
    # ĉ 本体恒在 CP 区间内
    c = 160 / 200
    assert lo_a <= c <= hi_a


def test_betainc_reg_against_symmetry_and_bounds():
    assert cov.betainc_reg(2.0, 3.0, 0.0) == 0.0
    assert cov.betainc_reg(2.0, 3.0, 1.0) == 1.0
    # 对称性 I_x(a,b) = 1 − I_{1−x}(b,a)
    a, b, x = 3.5, 7.2, 0.37
    assert abs(cov.betainc_reg(a, b, x) + cov.betainc_reg(b, a, 1 - x) - 1.0) < 1e-12


def test_known_sigma_gaussian_nominal_coverage():
    """已知 σ 高斯：x̂ ± 1.96σ 的实测覆盖 ≈ 0.95±噪声；CP 区间与 Wald 近似一致。"""
    rng = np.random.default_rng(20260928)
    n_reps, theta, sigma = 5000, 10.0, 2.0
    xs = rng.normal(theta, sigma, size=n_reps)
    z = 1.959963984540054                     # 逐位 Φ⁻¹(0.975)
    recs = [cov.IntervalRecord(tool="gauss", arm="m", n=1, signature="SBS1",
                               rep=i, estimate=float(x),
                               lo95=float(x - z * sigma), hi95=float(x + z * sigma))
            for i, x in enumerate(xs)]
    cells = cov.cell_coverage(recs, {"SBS1": float(theta)}, LAYER)
    assert len(cells) == 1
    c = cells[0]
    assert c.n_reps == n_reps
    assert abs(c.coverage - 0.95) < 0.015     # 二项 se≈0.0031，窗口 ~5σ
    # CP 正确性（与种子无关）：n=5000 时 CP ≈ Wald（差 < 0.005），
    # 且点估计 ĉ 恒在 CP 区间内
    p_hat = c.k / n_reps
    se = (p_hat * (1 - p_hat) / n_reps) ** 0.5
    assert abs(c.cp_lo - (p_hat - z * se)) < 0.005
    assert abs(c.cp_hi - (p_hat + z * se)) < 0.005
    assert c.cp_lo <= p_hat <= c.cp_hi


def _mk_cells(specs):
    """specs: (tool, n, sig, layer, k, n_reps) → CellCoverage 列表。"""
    out = []
    for tool, n, sig, k, n_reps in specs:
        lo, hi = cov.clopper_pearson(k, n_reps)
        out.append(cov.CellCoverage(tool=tool, arm="main", n=n, signature=sig,
                                    layer=LAYER(sig), truth_h=0.0, k=k,
                                    n_reps=n_reps, coverage=k / n_reps,
                                    cp_lo=lo, cp_hi=hi))
    return out


NS = (300, 560, 1000, 1800, 3000, 5600, 10000)   # N≥300 判定区
ALL_SIGS = ("SBS1", "SBS2", "SBS13", "SBS5", "SBS40")


def _fill(specs, k, n_reps=200, ns=NS):
    """所有 (tool × n × sig) cell 取固定 k（可逐 cell 覆写）。"""
    over = dict(specs)
    for tool in ("sigfit", "stl"):
        for n in ns:
            for sig in ALL_SIGS:
                if (tool, n, sig) not in over:
                    over[(tool, n, sig)] = k
    return _mk_cells([(t, n, s, kk, n_reps)
                      for (t, n, s), kk in over.items()])


def test_judge_support_a_clause1():
    """clause ①：单 cell ĉ≤0.85 且 CP 上界 <0.90 → 支持 A。"""
    cells = _fill({}, 190)                                # 全部 0.95
    cells += _mk_cells([("sigfit", 1000, "SBS1", 160, 200)])   # ĉ=0.80
    j = cov.judge(cells)
    assert j.verdict == "A" and len(j.clause_a1_cells) == 1


def test_judge_support_a_clause1_ci_guard():
    """CI 上界保护：ĉ=0.85 但 CP 上界 ≥0.90（n=100 时 k=85 → hi≈0.915）→
    不触发 ①；且无 kill（ĉ<0.90）→ gray，borderline 记录该 cell。"""
    cells = _fill({}, 190)
    cells += _mk_cells([("sigfit", 1000, "SBS1", 85, 100)])   # ĉ=0.85, hi>0.90
    j = cov.judge(cells)
    assert j.verdict == "GRAY"
    assert j.borderline_cells == ["sigfit|main|N=1000|SBS1"]


def test_judge_support_a_clause2_flat_layer():
    """clause ②：flat 层 N≥300 全部 cell ≤0.90（两工具）→ 支持 A。"""
    cells = _fill({}, 191)                                 # easy 层高覆盖
    flat = {(t, n, s): 178 for t in ("sigfit", "stl") for n in NS
            for s in ("SBS5", "SBS40")}                    # ĉ=0.89
    cells = _fill(flat, 191)
    j = cov.judge(cells)
    assert j.verdict == "A" and j.clause_a2


def test_judge_kill_to_b():
    """kill→B：两工具全部 N≥300 cell ≥0.90 且无单调恶化 → B。"""
    cells = _fill({}, 195)
    cells += _mk_cells([(t, 100, s, 180, 200)
                        for t in ("sigfit", "stl") for s in ALL_SIGS])  # N=100 不进判定
    j = cov.judge(cells)
    assert j.verdict == "B"


def test_judge_kill_blocked_by_monotone_worsening():
    """全 cell ≥0.90 但 flat 签名随 N 单调恶化（唯一 kill 阻断项）→ gray。"""
    spec = {}
    dec = (198, 197, 196, 195, 194, 193, 192)   # 单调下降，ĉ 全部 ≥ 0.90
    for t in ("sigfit", "stl"):
        for i, n in enumerate(NS):
            spec[(t, n, "SBS5")] = dec[i]
            spec[(t, n, "SBS40")] = dec[i]
    cells = _fill(spec, 195)
    j = cov.judge(cells)
    assert j.verdict == "GRAY"
    assert any("SBS5" in b for b in j.monotone_worse)
    assert any("SBS40" in b for b in j.monotone_worse)


def test_judge_ignores_non_tier1_tools():
    """P2a：判定全程按 tier1_tools 过滤——非 Tier-1 工具的失准 cell 不得
    触发 clause ①/②，也不得阻断 kill（"两工具"= 两 Tier-1 工具）。"""
    cells = _fill({}, 195)
    cells += _mk_cells([("gauss", 1000, "SBS1", 100, 200),   # ĉ=0.50，非 Tier-1
                        ("gauss", 1000, "SBS5", 60, 200)])
    j = cov.judge(cells)
    assert j.verdict == "B"                                  # kill 不被非 Tier-1 阻断
    assert all("gauss" not in c for c in j.clause_a1_cells)
    assert all("gauss" not in c for c in j.borderline_cells)


def test_judge_kill_requires_both_tier1_tools():
    """P2a：kill 的"两 Tier-1 工具"是合取——判定区缺任一工具 → 不得判 B。"""
    cells = [c for c in _fill({}, 195) if c.tool != "stl"]
    j = cov.judge(cells)
    assert j.verdict == "GRAY" and not j.kill_ok


def test_judge_borderline_has_no_n_floor():
    """P2b：protocol-memo §2.4 原文（"仅对 borderline cells 加倍重复至 400
    后重判"）与裁决 §5 转述均无 N≥300 限定 → N<300 的失准 cell 同样进
    gray 加倍流程（照冻结文本）。
    构造：N=1000 处 ĉ=0.88 cell 阻断 kill（→GRAY），N=100 处同分布 cell
    仅应作为 borderline 记录（两者都 ĉ∈(0.85,0.90)，不触发 clause ①）。"""
    cells = _fill({("sigfit", 1000, "SBS1"): 176,     # ĉ=0.88 @判定区 → 阻断 kill
                   ("sigfit", 100, "SBS1"): 176},     # ĉ=0.88 @N=100 → borderline
                  195)
    j = cov.judge(cells)
    assert j.verdict == "GRAY"
    assert "sigfit|main|N=100|SBS1" in j.borderline_cells
    assert "sigfit|main|N=1000|SBS1" in j.borderline_cells


def test_judge_arms_filter_excludes_sensitivity():
    """P0-2（冻结增补条款 b）：敏感性臂 cell 不进判定——judge_arms 过滤后，
    nb 臂的灾难性失准既不触发 clause ① 也不阻断 kill，只记 note。"""
    from g0.coverage import CellCoverage
    cells = _fill({}, 195)
    lo, hi = cov.clopper_pearson(10, 200)
    cells.append(CellCoverage(tool="sigfit", arm="nb", n=1000, signature="SBS1",
                              layer="easy", truth_h=150.0, k=10, n_reps=200,
                              coverage=0.05, cp_lo=lo, cp_hi=hi))
    j = cov.judge(cells, judge_arms={"main"})
    assert j.verdict == "B"
    assert all("|nb|" not in c for c in j.clause_a1_cells)
    assert all("|nb|" not in c for c in j.borderline_cells)
    assert any("nb" in n for n in j.notes)
