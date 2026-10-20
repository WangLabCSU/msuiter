"""② Coverage calculator correctness: CP analytic anchors + known-σ Gaussian nominal 95% + three-way judgment rules."""

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
    # Textbook value: k=95, n=100 → (0.8872, 0.9836)
    lo, hi = cov.clopper_pearson(95, 100)
    assert abs(lo - 0.8872) < 1e-3 and abs(hi - 0.9836) < 1e-3
    # k grows → the interval shifts right as a whole (both lo and hi rise with k)
    lo_a, hi_a = cov.clopper_pearson(160, 200)
    lo_b, hi_b = cov.clopper_pearson(180, 200)
    assert lo_b > lo_a and hi_b > hi_a
    # ĉ itself is always inside the CP interval
    c = 160 / 200
    assert lo_a <= c <= hi_a


def test_betainc_reg_against_symmetry_and_bounds():
    assert cov.betainc_reg(2.0, 3.0, 0.0) == 0.0
    assert cov.betainc_reg(2.0, 3.0, 1.0) == 1.0
    # Symmetry I_x(a,b) = 1 − I_{1−x}(b,a)
    a, b, x = 3.5, 7.2, 0.37
    assert abs(cov.betainc_reg(a, b, x) + cov.betainc_reg(b, a, 1 - x) - 1.0) < 1e-12


def test_known_sigma_gaussian_nominal_coverage():
    """Known-σ Gaussian: measured coverage of x̂ ± 1.96σ ≈ 0.95±noise; the CP interval agrees with the Wald approximation."""
    rng = np.random.default_rng(20260928)
    n_reps, theta, sigma = 5000, 10.0, 2.0
    xs = rng.normal(theta, sigma, size=n_reps)
    z = 1.959963984540054                     # digit-exact Φ⁻¹(0.975)
    recs = [cov.IntervalRecord(tool="gauss", arm="m", n=1, signature="SBS1",
                               rep=i, estimate=float(x),
                               lo95=float(x - z * sigma), hi95=float(x + z * sigma))
            for i, x in enumerate(xs)]
    cells = cov.cell_coverage(recs, {"SBS1": float(theta)}, LAYER)
    assert len(cells) == 1
    c = cells[0]
    assert c.n_reps == n_reps
    assert abs(c.coverage - 0.95) < 0.015     # binomial se≈0.0031, window ~5σ
    # CP correctness (seed-independent): at n=5000 CP ≈ Wald (diff < 0.005),
    # and the point estimate ĉ is always inside the CP interval
    p_hat = c.k / n_reps
    se = (p_hat * (1 - p_hat) / n_reps) ** 0.5
    assert abs(c.cp_lo - (p_hat - z * se)) < 0.005
    assert abs(c.cp_hi - (p_hat + z * se)) < 0.005
    assert c.cp_lo <= p_hat <= c.cp_hi


def _mk_cells(specs):
    """specs: (tool, n, sig, layer, k, n_reps) → list of CellCoverage."""
    out = []
    for tool, n, sig, k, n_reps in specs:
        lo, hi = cov.clopper_pearson(k, n_reps)
        out.append(cov.CellCoverage(tool=tool, arm="main", n=n, signature=sig,
                                    layer=LAYER(sig), truth_h=0.0, k=k,
                                    n_reps=n_reps, coverage=k / n_reps,
                                    cp_lo=lo, cp_hi=hi))
    return out


NS = (300, 560, 1000, 1800, 3000, 5600, 10000)   # the N≥300 judgment region
ALL_SIGS = ("SBS1", "SBS2", "SBS13", "SBS5", "SBS40")


def _fill(specs, k, n_reps=200, ns=NS):
    """All (tool × n × sig) cells take a fixed k (overridable per cell)."""
    over = dict(specs)
    for tool in ("sigfit", "stl"):
        for n in ns:
            for sig in ALL_SIGS:
                if (tool, n, sig) not in over:
                    over[(tool, n, sig)] = k
    return _mk_cells([(t, n, s, kk, n_reps)
                      for (t, n, s), kk in over.items()])


def test_judge_support_a_clause1():
    """Clause ①: a single cell with ĉ≤0.85 and CP upper bound <0.90 → supports A."""
    cells = _fill({}, 190)                                # all 0.95
    cells += _mk_cells([("sigfit", 1000, "SBS1", 160, 200)])   # ĉ=0.80
    j = cov.judge(cells)
    assert j.verdict == "A" and len(j.clause_a1_cells) == 1


def test_judge_support_a_clause1_ci_guard():
    """CI upper-bound guard: ĉ=0.85 but CP upper bound ≥0.90 (with n=100, k=85 → hi≈0.915) →
    clause ① does not fire; and there is no kill either (ĉ<0.90) → gray, that cell is recorded as borderline."""
    cells = _fill({}, 190)
    cells += _mk_cells([("sigfit", 1000, "SBS1", 85, 100)])   # ĉ=0.85, hi>0.90
    j = cov.judge(cells)
    assert j.verdict == "GRAY"
    assert j.borderline_cells == ["sigfit|main|N=1000|SBS1"]


def test_judge_support_a_clause2_flat_layer():
    """Clause ②: all flat-layer cells with N≥300 are ≤0.90 (both tools) → supports A."""
    cells = _fill({}, 191)                                 # easy-layer high coverage
    flat = {(t, n, s): 178 for t in ("sigfit", "stl") for n in NS
            for s in ("SBS5", "SBS40")}                    # ĉ=0.89
    cells = _fill(flat, 191)
    j = cov.judge(cells)
    assert j.verdict == "A" and j.clause_a2


def test_judge_kill_to_b():
    """kill→B: for both tools every N≥300 cell is ≥0.90 and there is no monotone worsening → B."""
    cells = _fill({}, 195)
    cells += _mk_cells([(t, 100, s, 180, 200)
                        for t in ("sigfit", "stl") for s in ALL_SIGS])  # N=100 does not enter the judgment
    j = cov.judge(cells)
    assert j.verdict == "B"


def test_judge_kill_blocked_by_monotone_worsening():
    """All cells ≥0.90 but the flat signatures worsen monotonically with N (the sole kill blocker) → gray."""
    spec = {}
    dec = (198, 197, 196, 195, 194, 193, 192)   # monotone descent, all ĉ ≥ 0.90
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
    """P2a: the judgment filters by tier1_tools throughout — cells of non-Tier-1 tools must not
    trigger clause ①/②, nor block the kill ("two tools" = the two Tier-1 tools)."""
    cells = _fill({}, 195)
    cells += _mk_cells([("gauss", 1000, "SBS1", 100, 200),   # ĉ=0.50, not Tier-1
                        ("gauss", 1000, "SBS5", 60, 200)])
    j = cov.judge(cells)
    assert j.verdict == "B"                                  # the kill is not blocked by non-Tier-1
    assert all("gauss" not in c for c in j.clause_a1_cells)
    assert all("gauss" not in c for c in j.borderline_cells)


def test_judge_kill_requires_both_tier1_tools():
    """P2a: kill's "two Tier-1 tools" is a conjunction — if either tool is missing from the judgment region → must not rule B."""
    cells = [c for c in _fill({}, 195) if c.tool != "stl"]
    j = cov.judge(cells)
    assert j.verdict == "GRAY" and not j.kill_ok


def test_judge_borderline_has_no_n_floor():
    """P2b: neither the protocol-memo §2.4 original ("double the repetitions of the borderline cells to 400
    and re-judge only then") nor the adjudication §5 retelling carries an N≥300 qualifier → cells at N<300 that miss
    the bar likewise enter the gray doubling flow (per the frozen text).
    Construction: at N=1000 an ĉ=0.88 cell blocks the kill (→GRAY); a cell with the same distribution at N=100
    should only be recorded as borderline (both have ĉ∈(0.85,0.90) and do not trigger clause ①)."""
    cells = _fill({("sigfit", 1000, "SBS1"): 176,     # ĉ=0.88 @ judgment region → blocks the kill
                   ("sigfit", 100, "SBS1"): 176},     # ĉ=0.88 @N=100 → borderline
                  195)
    j = cov.judge(cells)
    assert j.verdict == "GRAY"
    assert "sigfit|main|N=100|SBS1" in j.borderline_cells
    assert "sigfit|main|N=1000|SBS1" in j.borderline_cells


def test_judge_arms_filter_excludes_sensitivity():
    """P0-2 (frozen supplemental clause b): sensitivity-arm cells do not enter the judgment — after the judge_arms filter,
    the catastrophic undercoverage of the nb arm neither triggers clause ① nor blocks the kill, and is only recorded as a note."""
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
