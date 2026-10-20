"""The own χ²₁ presence LRT (the P3 addendum column; the NB semantics). Zero third-party dependencies (numpy + math).

The model (independent per-channel counts; the W columns each normalized to sum 1, h ≥ 0):
  The Poisson/multinomial semantics: x_c ~ Poisson((Wh)_c). Note that when the W columns sum to 1,
  the Poisson likelihood and the multinomial likelihood share the same argmax over h, and their LRT
  statistics are pointwise equal (the Poisson MLE automatically fits the total to N; the multinomial is
  scale-invariant on the total) — hence one Poisson EM serves both semantics.
  The NB semantics: x_c ~ NB(mean=(Wh)_c, size=s), Var = μ + μ²/s, the exact likelihood via
  lgamma (_ll_nb). The score of the NB log likelihood over μ is
      ∂ll/∂μ_c = x_c/μ_c − (x_c+s)/(μ_c+s),
  the multiplicative MM ascent update split by its positive/negative parts (the Lee–Seung style gradient split) is
      h ← h · Wᵀ(x/μ) / Wᵀ((x+s)/(μ+s)),
  the NB log likelihood monotonically non-decreasing each step (numerical validation in tests/test_lrt.py and the 2026-09-28
  independent-audit record; at s→∞ it degenerates to the classic Poisson EM h ← h·Wᵀ(x/μ)/Wᵀ1).
  Beware: taking the Gamma-Poisson stratified E-step weights z_c=(x_c+s)μ_c/(μ_c+s) directly as
  the multiplicative weights is **not** an MM update of this marginal likelihood — the ll would monotonically descend and
  falsely converge at h_cap (the pre-2026-09-28-fix wrong implementation; the measured ll in a single evaluation went
  −1.3×10⁵ → −4.7×10⁵; after the fix the same data gives ll = −1.0×10⁴ and monotonically rises).

The test: H0: h_j = 0 vs H1: h_j > 0 (the boundary). The Self–Liang (1987, JASA 82:605)
boundary asymptotics: the statistic's null distribution ≈ ½δ₀ ⊕ ½χ²₁, hence the boundary-calibrated p value is
  p = ½·sf_χ²₁(stat) = ½·erfc(√(stat/2)) (stat>0; at stat=0 p=1),
implemented via math.erfc (no scipy). The report columns additionally give the naive χ²₁ sf as a contrast.

The protocol basis: P3 (assumption-audit-memo §2) — "the Self–Liang boundary asymptotics as the nominal
reference"; the post-ruling addendum clause 1 — the NB arm appends the empirical size report column, sharing the seeded data with G0.
"""

from __future__ import annotations

import math

import numpy as np


def sf_chi2_1(stat: float) -> float:
    """The χ²₁ survival function = erfc(√(x/2))."""
    return math.erfc(math.sqrt(max(stat, 0.0) / 2.0))


def pval_boundary_lrt(stat: float) -> float:
    """The Self–Liang boundary-calibrated p value = ½·sf_χ²₁ (stat>0)."""
    if stat <= 0.0:
        return 1.0
    return 0.5 * sf_chi2_1(stat)


def _mu(W: np.ndarray, h: np.ndarray) -> np.ndarray:
    """μ = h @ Wᵀ; h (B,K), W (96,K) → (B,96)."""
    return h @ W.T


def _em(counts: np.ndarray, W: np.ndarray, size: float | None = None,
        max_iter: int = 500, tol: float = 1e-10, h_cap: float = 1e9) -> np.ndarray:
    """Batch EM/MM for the MLE ĥ. counts (B,96) ≥0 integers; returns (B,K).

    Poisson (size=None): h ← h·(Wᵀ(x/μ))/colsum (the classic Poisson EM;
    column sums 1 ⇒ the denominator 1).
    NB (size=s): the multiplicative MM ascent
        h ← h · Wᵀ(x/μ) / Wᵀ((x+s)/(μ+s)),
    i.e. the update from the positive/negative-part gradient split of the NB log-likelihood score x/μ − (x+s)/(μ+s);
    the ll is monotonically non-decreasing each step. The fixed point is the stationary point of the NB score equation (with column sums 1 the common factors of the two W
    weights cancel, the scale self-consistent).
    The initialization h = (Σx/96)·1/K + ε guarantees leaving the exact zero boundary (the multiplicative update preserves the sign).
    h_cap: a defensive upper bound (≫ any legitimate MLE exposure — the MLE ≤ the total counts), with no
    effect on normal fits.
    The convergence criterion is the relative step length; the NB's MM convergence is linear; within 500 rounds the ll has entered the
    0.1% magnitude neighbourhood of the stationary point (the LRT's full/reduced models synchronously under-converging only slightly shrinks
    the stat, in the conservative direction); the machine-precision fixed point is not pursued.
    """
    B, C = counts.shape
    K = W.shape[1]
    x = counts.astype(float)
    total = x.sum(axis=1, keepdims=True)                       # (B,1)
    h = np.full((B, K), 1.0 / K) * (total / C) + 1e-12
        # the floor commensurate with the counts scale (the G0 channel counts ≤1e6): avoids the division by zero
    for _ in range(max_iter):
        mu = _mu(W, h)
        colsum = W.sum(axis=0)                                     # (K,) (=1 after normalization)
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
    """The per-dataset Poisson log likelihood (dropping the h-independent factorial constants does not affect the LRT)."""
    x = counts.astype(float)
    mu = np.maximum(mu, 1e-300)
    return (x * np.log(mu) - mu).sum(axis=1)


def _ll_nb(counts: np.ndarray, mu: np.ndarray, size: float) -> np.ndarray:
    """The exact NB(mean=μ, size=s) log likelihood (the lgamma form)."""
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
    """The MLE ĥ of a single/batch dataset. counts (96,) or (B,96)."""
    c = np.atleast_2d(counts)
    return _em(c, W, size=size, **kw)


def presence_lrt_scan(counts_batch: np.ndarray, W: np.ndarray,
                      test_cols: list, size: float | None = None,
                      alpha: float = 0.05, **em_kw) -> list:
    """Runs the presence LRT scan over several catalogue columns.

    counts_batch (B,96); W (96,K) with column sums 1; test_cols is the list of column indices to test.
    For each j∈test_cols: one reused full-model fit (K columns); the reduced-model fit (dropping
    the j-th column). Returns the per-j dict: stat, p_boundary, p_naive_chi2_1, reject.

    Note: stat = 2(ll_full − ll_reduced), numerically clipped to ≥0 (the EM convergence error
    may produce tiny negative values).
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
