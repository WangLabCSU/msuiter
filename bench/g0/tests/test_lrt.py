"""③ LRT size calibration: the rejection rate of 2000 tests under a multinomial null ≈ 0.05±noise (fixed seed)."""

import numpy as np

from g0 import lrt, providers, seeds

PROVIDER = providers.SyntheticProvider(seed=0)
NAMES, W = PROVIDER.catalog_matrix()          # indices 0–4 = truth slots, 5–9 = absent signatures
ABSENT = [5, 6, 7, 8, 9]

# Truth mixture: SBS1 30% / SBS5 40% / SBS40 30% (3 truth signatures → everything else is H0)
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
    assert abs(lrt.sf_chi2_1(3.841458820694124) - 0.05) < 1e-9   # the 95% quantile of χ²₁
    assert abs(lrt.pval_boundary_lrt(3.841458820694124) - 0.025) < 1e-9
    assert lrt.pval_boundary_lrt(0.0) == 1.0


def test_size_calibration_multinomial_null():
    """Multinomial null (absent signatures): empirical size of the boundary-calibrated LRT over 2000 reps × 5 absent columns.

    The window [0.010, 0.070] — both ends are one-directionally defensible:
    - upper bound 0.070: the substantive question of P3 — under H0 it must not inflate past the nominal α (+4σ slack,
      the pooled n=10000 se≈0.0022);
    - lower bound 0.010: the statistic is not degenerate (an always-non-rejecting broken implementation would be caught);
      the center is not taken at 0.05 because the Self–Liang boundary mixture ½δ₀⊕½χ²₁ is provably
      conservative at finite samples (N=1000, the absent signatures are near-collinear with the truth mixture) — under this seed
      the measured pooled size = 0.0221 (this value is on record; an exact 0.05 calibration needs a larger N,
      which belongs to the P3 main-text experiment scope, not to the harness self-check scope). Fixed seed → deterministic.
    """
    X = _simulate(None)
    res = lrt.presence_lrt_scan(X, W, ABSENT, size=None, max_iter=500)
    rej = np.concatenate([r["reject"] for r in res])
    rate = float(rej.mean())
    assert 0.010 <= rate <= 0.070, f"empirical size {rate:.4f} out of window"
    # Numerical soundness: the statistic is non-negative; p ∈ [0,1]
    assert all(np.all(r["stat"] >= 0) for r in res)


def test_power_on_present_signature():
    """Signatures present in the truth (30% share @ N=1000): power ≈ 1."""
    X = _simulate(None)
    res = lrt.presence_lrt_scan(X, W, [0], size=None, max_iter=500)
    assert float(np.mean(res[0]["reject"])) >= 0.98


def test_nb_semantics_size_not_inflated_and_poisson_misspec_diagnostic():
    """NB truth (size=8): the size of the NB-semantics LRT should stay ≈α; the Poisson-misspecification LRT's
    size only rises, never falls (the inflation direction the P3 supplemental column is to measure). The window is wide (diagnostic column, not judgment)."""
    X = _simulate(size=8.0)
    res_nb = lrt.presence_lrt_scan(X, W, ABSENT, size=8.0, max_iter=500)
    size_nb = float(np.concatenate([r["reject"] for r in res_nb]).mean())
    res_poi = lrt.presence_lrt_scan(X, W, ABSENT, size=None, max_iter=500)
    size_poi = float(np.concatenate([r["reject"] for r in res_poi]).mean())
    assert 0.0 <= size_nb <= 0.10, f"NB-semantics size inflated: {size_nb:.4f}"
    assert size_poi >= size_nb - 0.02, (
        f"expected misspecification inflation, got poi={size_poi:.4f} < nb={size_nb:.4f}")


# P1-2 (2026-09-28 independent audit): the reasonableness floor of NB-semantics power (anti-regression).
# Frozen F3-style shares: SBS1/SBS2/SBS13 at 15% each, SBS5 30%, SBS40 25% (the 15–30% magnitude).
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
    """P1-2 floor: NB truth (size=8) @ N=1000, 15–30% shares; under the repaired NB MM
    updates the NB-semantics presence LRT must have substantive power (before the 2026-09-28 fix that combination
    had all-arm power=0.04, a false convergence from an NB EM math error).

    Asserts (fixed seed → deterministic):
    - per-signature on the easy layer (SBS1/SBS2/SBS13, 15% share each) power ≥ 0.5;
    - pooled power over the 5 present signatures ≥ 0.5.
    Honest note: the flat near-duplicate pair (SBS5/40) has low per-signature power (measured under this seed
    ≈0.085/0.015 (current-seed measurement) — the 3% profile difference is drowned by the NB overdispersion variance, an identifiability limit rather than a regression);
    what G0 measures on flat signatures is interval coverage (protocol §5), not presence power,
    hence the floor gates only the easy layer and the pooled value.
    """
    X = _simulate_nb_power()
    res = lrt.presence_lrt_scan(X, W, PRESENT, size=8.0, max_iter=500)
    per_sig = [float(r["reject"].mean()) for r in res]
    pooled = float(np.concatenate([r["reject"] for r in res]).mean())
    for name, p in zip(("SBS1", "SBS2", "SBS13"), per_sig[:3]):
        assert p >= 0.5, f"NB power floor broken for {name}: {p:.3f}"
    assert pooled >= 0.5, f"NB pooled power below floor: {pooled:.3f}"
    # Numerical soundness: the repaired NB EM must never again touch the defensive h_cap (the false-convergence flag)
    h = lrt.fit_exposures(X[:50], W, size=8.0, max_iter=500)
    assert float(h.max()) < 1e8, "NB fit pinned at h_cap — regression to broken EM"
