//! Automatic Relevance Determination NMF (KL likelihood) — the
//! SignatureAnalyzer automatic rank-determination kernel (U-M2-04;
//! `docs/CAPABILITY-MATRIX.md` L-C `ms_ard` row, `docs/research/01` §2).
//!
//! # Upstream semantics (pinned to source, D11/D13)
//!
//! The audited implementation anchor is the SignatureAnalyzer port in
//! `sigminer/R/bayesianNMF.R` (file carries the Broad Institute BSD-3
//! header, "Copyright (c) 2017, Broad Institute"; port of the Broad
//! BayesNMF MATLAB code). Algorithm provenance: Tan & Févotte, "Automatic
//! Relevance Determination in Nonnegative Matrix Factorization with the
//! β-divergence", IEEE TPAMI 35:1592–1605 (2013) — deterministic type-II
//! maximum likelihood (evidence maximization), not Gibbs, not variational.
//! Line numbers below refer to `bayesianNMF.R` (master, 279 lines).
//!
//! This module implements the **default variant `BayesNMF.L1W.L2H`**
//! (L52–92): KL likelihood with an exponential (L1) prior on each W column
//! and a half-normal (L2) prior on each H row, sharing one ARD precision
//! `beta_k` per component. This is the variant `docs/research/01` §2
//! documents as the SignatureAnalyzer default; the `L1KL` / `L2KL` variants
//! (L95–186) are deliberately not ported (documented scope cut, see
//! "Deviations" below).
//!
//! Notation as in [`crate::nmf`]: `V ∈ R_+^{m×n}`, `V ≈ W H`, `W ∈ R_+^{m×k}`
//! (signatures), `H ∈ R_+^{k×n}` (exposures), row-major `Vec<f64>`.
//!
//! # Update equations (verbatim upstream)
//!
//! Per iteration, in the fixed upstream order (L73–77):
//!
//! 1. **H step with ARD penalty** (L74):
//!    `H ← H ⊙ (Wᵀ (V ⊘ max(WH, ε))) ⊘ max(Wᵀ 1_m + diag(β) H, ε)`
//!    — the audited KL H step with the half-normal-penalty gradient `β_k h_kj`
//!    added to the denominator.
//! 2. **W step with ARD penalty** (L76):
//!    `W ← W ⊙ ((V ⊘ max(WH, ε)) Hᵀ) ⊘ max(1_m Hᵀ + β, ε)`
//!    — the KL W step with the exponential-penalty gradient `β_k` (constant
//!    per column) added to the denominator.
//! 3. **Type-II hyperparameter update** (L64–65, the Tan–Févotte evidence
//!    maximization step):
//!    `C = m + n/2 + a0 − 1` (L64; upstream `N + M/2 + a0 − 1` with
//!    N = channels, M = samples)
//!    `β_k ← C / (Σ_i w_ik + ½ Σ_j h_kj² + b0)` (L65)
//!
//! **Convergence** (L81): `del = max_k |Δβ_k| / β_k,prev`; the run stops when
//! `del < tol` (upstream default 1e-5) or at the iteration cap (upstream
//! default n.iter = 2,000,000, L47). **Trace** (L82–83): this port traces the
//! upstream evidence surrogate
//! `evid = D_KL(V‖WH) + Σ_k (Σ_i w_ik + ½ Σ_j h_kj² + b0)·β_k − C·ln β_k`
//! (the KL likelihood plus the exponential/half-normal/Gamma-hyperprior
//! terms). `objective[0]` is the evidence at the initializer; entry `t ≥ 1`
//! is the evidence after `t` iterations. Unlike the plain KL-NMF kernel this
//! penalized trace is **not guaranteed monotone**: the upstream L2-term H
//! step (penalty gradient added to a plain MU denominator) is the historical
//! Broad form, not the square-root MM form of Tan & Févotte 2013 — a
//! documented upstream property, faithfully ported (see Deviations).
//!
//! # Automatic rank determination
//!
//! From `k0` starting components, ARD shrinks useless components: their
//! `Σw + ½Σh²` collapses toward `b0`, so `β_k` grows past the hard cut
//! (L66–67) `β_cut = (C / b0) / 1.25`. A component is **dead** when
//! `β_k > β_cut` **or** its W column sum ≤ 1e-5 (L85 prints the two survival
//! counts `sum(colSums(W) > 1e-5)` and `sum(beta <= beta.cut)`; the audit
//! `docs/research/01` §2 fixes the death rule as the OR of the two failures).
//! Upstream only monitors these counts; this port additionally prunes at
//! output: [`ArdFit`] carries the full factors plus the `active` mask, the
//! pruned copies (`w_active` / `h_active`, original component order
//! preserved) and `k_est = |active|` — a divergence from upstream that is
//! required by the unit contract ("component pruning") and documented here.
//!
//! # Hyperparameter defaults (upstream L47)
//!
//! `a0 = 10`, `b0 = 5`, `tol = 1e-5`, `n.iter = 2,000,000`
//! ([`ARD_A0`], [`ARD_B0`], [`ARD_TOL`], [`ARD_MAX_ITER`]). The scale
//! `b0 = 5` is absolute: ARD pruning semantics depend on the absolute data
//! scale, which is why the initializer below follows the upstream scale
//! rather than the [`crate::nmf`] one.
//!
//! # Initialization and determinism
//!
//! Seeded deterministic init mirroring upstream L58–59 (`runif ·
//! sqrt(mean(V))`): open-interval uniforms in (0, 1] from [`crate::rng::MsRng`]
//! (stream [`crate::rng::StreamId::ZERO`]; W row-major first, then H
//! row-major) scaled by `sqrt(mean(V))` (1.0 for all-zero input). The open
//! interval matches R's `runif` (also open at both ends — an earlier
//! comment claiming it can return exact 0 was wrong, audited); zeros would
//! be absorbing under MU anyway. Column symmetry is broken by the seeded
//! draw. Fixed loop order, sequential reductions, no parallelism: equal
//! inputs produce bit-identical output (ARCH §2.6).
//!
//! # Deviations from upstream (all deliberate, D13)
//!
//! 1. **No min-shift**: upstream applies `V ← V0 − min(V0)` (L55); this
//!    kernel validates non-negativity instead (mutational catalogs are
//!    counts; a negative shift would move the KL objective's support).
//! 2. **ε policy**: upstream `eps = 1e-50` added to ratios/denominators
//!    (L53, L60) is replaced by the crate ε policy ([`crate::nmf::KL_EPS`],
//!    denominators floored at ε, logs as `log(ε + ·)`) — same guard role,
//!    ARCH §2 contract.
//! 3. **Pruning at output** (upstream only monitors; see above).
//! 4. **Init layout**: upstream fills the R matrices column-major from
//!    `runif`; this port draws row-major (crate layout convention, same as
//!    [`crate::nmf`]).
//! 5. **Variants**: only `BayesNMF.L1W.L2H` (the documented default) is
//!    ported; `L1KL`/`L2KL` and the fixed-W attribution steps are later
//!    units.
//!
//! # Contract notes
//!
//! Pure engine kernel: no FFI face, no `unsafe`, no dependencies; every
//! entry point returns `Result<_, MsError>` (FFI contract 5). The unpenalized
//! limit of both MU steps is bit-identical to the audited [`crate::nmf`]
//! kernels (tested): with `β ≡ 0` the steps reduce exactly to
//! [`crate::nmf::kl_h_step`] / [`crate::nmf::kl_w_step`].

use crate::error::MsError;
use crate::nmf::{matmul, KL_EPS};
use crate::rng::{MsRng, StreamId};

/// Upstream default `a0` (Gamma hyperprior shape; `bayesianNMF.R:47`).
pub const ARD_A0: f64 = 10.0;

/// Upstream default `b0` (Gamma hyperprior scale; `bayesianNMF.R:47`). An
/// absolute scale: it sets where `β_cut` sits relative to the data magnitude.
pub const ARD_B0: f64 = 5.0;

/// Upstream default convergence tolerance on `max|Δβ/β|` (`bayesianNMF.R:47`).
pub const ARD_TOL: f64 = 1e-5;

/// Upstream default iteration cap `n.iter` (`bayesianNMF.R:47`).
pub const ARD_MAX_ITER: usize = 2_000_000;

/// W column-sum aliveness threshold (`bayesianNMF.R:85`): a component whose
/// W column sums to at most this is counted dead.
pub const ARD_W_ALIVE: f64 = 1e-5;

/// Outcome of an ARD-NMF fit: the full `k0`-component fit plus the ARD rank
/// determination (active mask, pruned factors, `k_est`).
#[derive(Debug, Clone, PartialEq)]
pub struct ArdFit {
    /// Full signature matrix `W`, row-major `m×k0`.
    pub w: Vec<f64>,
    /// Full exposure matrix `H`, row-major `k0×n`.
    pub h: Vec<f64>,
    /// Pruned signature matrix, row-major `m×k_est` (active components in
    /// original order).
    pub w_active: Vec<f64>,
    /// Pruned exposure matrix, row-major `k_est×n`.
    pub h_active: Vec<f64>,
    /// Component aliveness (`active[k] == false` ⟺ dead under the ARD rule).
    pub active: Vec<bool>,
    /// Number of surviving components (`k_est ≤ k0`).
    pub k_est: usize,
    /// Final ARD precisions `β_k` (length `k0`).
    pub beta: Vec<f64>,
    /// The pruning cut `β_cut = (C / b0) / 1.25` actually applied.
    pub beta_cut: f64,
    /// Evidence trace: `objective[0]` at the initializer, `objective[t]`
    /// after `t` iterations (see module docs; not guaranteed monotone).
    pub objective: Vec<f64>,
    /// Iterations actually run.
    pub iterations: usize,
    /// True iff the `max|Δβ/β| < tol` criterion fired before the cap.
    pub converged: bool,
}

/// ARD-NMF with the seeded deterministic initializer (module docs).
/// Flat scalar face (repo convention: `#[allow(clippy::too_many_arguments)]`
/// on kernel entry points, as in the FFI-facing `src/lib.rs` faces).
#[allow(clippy::too_many_arguments)]
pub fn fit_ard(
    v: &[f64],
    m: usize,
    n: usize,
    k0: usize,
    max_iter: usize,
    tol: f64,
    a0: f64,
    b0: f64,
    seed: u64,
) -> Result<ArdFit, MsError> {
    let (w0, h0) = seeded_init(v, m, n, k0, seed)?;
    fit_ard_with_init(v, m, n, k0, &w0, &h0, max_iter, tol, a0, b0)
}

/// ARD-NMF from a caller-provided initializer (`w0`: row-major `m×k0`,
/// `h0`: row-major `k0×n`). Entries must be finite and non-negative; exact
/// zeros are absorbing under the multiplicative updates.
#[allow(clippy::too_many_arguments)]
pub fn fit_ard_with_init(
    v: &[f64],
    m: usize,
    n: usize,
    k0: usize,
    w0: &[f64],
    h0: &[f64],
    max_iter: usize,
    tol: f64,
    a0: f64,
    b0: f64,
) -> Result<ArdFit, MsError> {
    validate(v, m, n, k0, w0, h0, tol, a0, b0)?;
    let c = evidence_norm(m, n, a0);
    let beta_cut = beta_cut(c, b0);

    let mut w = w0.to_vec();
    let mut h = h0.to_vec();
    let mut beta = ard_beta(&w, &h, m, n, k0, c, b0);

    let mut objective = Vec::with_capacity(max_iter + 1);
    objective.push(ard_evidence(v, &w, &h, m, n, k0, &beta, c, b0));

    let mut converged = false;
    let mut iterations = 0usize;
    for iter in 1..=max_iter {
        ard_h_step(v, &w, &mut h, m, n, k0, &beta);
        ard_w_step(v, &mut w, &h, m, n, k0, &beta);
        let next = ard_beta(&w, &h, m, n, k0, c, b0);
        let mut del = 0.0f64;
        for s in 0..k0 {
            del = del.max((next[s] - beta[s]).abs() / beta[s]);
        }
        beta = next;
        objective.push(ard_evidence(v, &w, &h, m, n, k0, &beta, c, b0));
        iterations = iter;
        if del < tol {
            converged = true;
            break;
        }
    }

    // ARD rank determination: dead iff β_k > β_cut OR W column sum ≤ 1e-5
    // (module docs "Automatic rank determination"; bayesianNMF.R:66-67, :85).
    let mut active = vec![true; k0];
    for s in 0..k0 {
        let mut col = 0.0f64;
        for i in 0..m {
            col += w[i * k0 + s];
        }
        if beta[s] > beta_cut || col <= ARD_W_ALIVE {
            active[s] = false;
        }
    }
    let k_est = active.iter().filter(|&&a| a).count();
    // Row-major m×k_est assembly (audited P0 fix): the previous version
    // pushed per-survivor COLUMN blocks (column-major), while every
    // consumer reads row-major — a transposed scramble for k_est ≥ 2.
    // Collect survivors first, then fill (i, c) at i*k_est + c.
    let survivors: Vec<usize> = (0..k0).filter(|&s| active[s]).collect();
    let k_est = survivors.len();
    let mut w_active = vec![0.0; m * k_est];
    let mut h_active = Vec::with_capacity(k_est * n);
    for (c, &s) in survivors.iter().enumerate() {
        for i in 0..m {
            w_active[i * k_est + c] = w[i * k0 + s];
        }
        h_active.extend_from_slice(&h[s * n..s * n + n]);
    }

    Ok(ArdFit {
        w,
        h,
        w_active,
        h_active,
        active,
        k_est,
        beta,
        beta_cut,
        objective,
        iterations,
        converged,
    })
}

/// `C = m + n/2 + a0 − 1` (upstream `N + M/2 + a0 − 1`, `bayesianNMF.R:64`).
fn evidence_norm(m: usize, n: usize, a0: f64) -> f64 {
    m as f64 + 0.5 * n as f64 + a0 - 1.0
}

/// `β_cut = (C / b0) / 1.25` (`bayesianNMF.R:66-67`).
fn beta_cut(c: f64, b0: f64) -> f64 {
    (c / b0) / 1.25
}

/// Type-II hyperparameter update
/// `β_k ← C / (Σ_i w_ik + ½ Σ_j h_kj² + b0)` (`bayesianNMF.R:65`; sum order
/// mirrors the upstream expression: W column sum, then the half H
/// square-sum, then `b0`).
fn ard_beta(w: &[f64], h: &[f64], m: usize, n: usize, k: usize, c: f64, b0: f64) -> Vec<f64> {
    let mut beta = vec![0.0f64; k];
    for s in 0..k {
        let mut acc = 0.0f64;
        for i in 0..m {
            acc += w[i * k + s];
        }
        let mut sq = 0.0f64;
        for j in 0..n {
            let hj = h[s * n + j];
            sq += hj * hj;
        }
        acc += 0.5 * sq;
        acc += b0;
        beta[s] = c / acc;
    }
    beta
}

/// One ARD H step: `H ← H ⊙ (Wᵀ (V ⊘ max(WH, ε))) ⊘ max(Wᵀ1 + diag(β) H, ε)`
/// (`bayesianNMF.R:74`). Loop structure, reduction order and ε placement are
/// those of [`crate::nmf::kl_h_step`]; `β ≡ 0` reproduces it bit-for-bit.
fn ard_h_step(v: &[f64], w: &[f64], h: &mut [f64], m: usize, n: usize, k: usize, beta: &[f64]) {
    let wh = matmul(w, h, m, n, k);
    // num[s][j] = Σ_i W[i][s] · V[i][j]/max(WH[i][j], ε)
    let mut num = vec![0.0f64; k * n];
    for i in 0..m {
        let wrow = &w[i * k..i * k + k];
        for j in 0..n {
            let r = v[i * n + j] / wh[i * n + j].max(KL_EPS);
            if r != 0.0 {
                for (s, &ws) in wrow.iter().enumerate() {
                    num[s * n + j] += ws * r;
                }
            }
        }
    }
    for s in 0..k {
        let mut col = 0.0f64;
        for i in 0..m {
            col += w[i * k + s];
        }
        for j in 0..n {
            // Half-normal (L2) penalty gradient β_k·h_kj in the denominator.
            let den = (col + beta[s] * h[s * n + j]).max(KL_EPS);
            h[s * n + j] *= num[s * n + j] / den;
        }
    }
}

/// One ARD W step: `W ← W ⊙ ((V ⊘ max(WH, ε)) Hᵀ) ⊘ max(1_m Hᵀ + β, ε)`
/// (`bayesianNMF.R:76`). Mirrors [`crate::nmf::kl_w_step`]; `β ≡ 0`
/// reproduces it bit-for-bit.
fn ard_w_step(v: &[f64], w: &mut [f64], h: &[f64], m: usize, n: usize, k: usize, beta: &[f64]) {
    let wh = matmul(w, h, m, n, k);
    for i in 0..m {
        for s in 0..k {
            let mut num = 0.0f64;
            for j in 0..n {
                let r = v[i * n + j] / wh[i * n + j].max(KL_EPS);
                num += r * h[s * n + j];
            }
            let mut den = 0.0f64;
            for j in 0..n {
                den += h[s * n + j];
            }
            // Exponential (L1) penalty gradient β_k (column constant).
            w[i * k + s] *= num / (den + beta[s]).max(KL_EPS);
        }
    }
}

/// Upstream evidence surrogate (`bayesianNMF.R:82-83`): the KL likelihood
/// plus `Σ_k (den_k)·β_k − C·ln β_k` where `den_k` is β_k's own update
/// denominator (recomputed, as upstream does, rather than collapsed to C).
#[allow(clippy::too_many_arguments)]
fn ard_evidence(
    v: &[f64],
    w: &[f64],
    h: &[f64],
    m: usize,
    n: usize,
    k: usize,
    beta: &[f64],
    c: f64,
    b0: f64,
) -> f64 {
    let mut evid = kl_objective(v, w, h, m, n, k);
    for s in 0..k {
        let mut acc = 0.0f64;
        for i in 0..m {
            acc += w[i * k + s];
        }
        let mut sq = 0.0f64;
        for j in 0..n {
            let hj = h[s * n + j];
            sq += hj * hj;
        }
        acc += 0.5 * sq;
        acc += b0;
        evid += acc * beta[s] - c * beta[s].ln();
    }
    evid
}

/// Generalized KL divergence with the crate `log(ε + ·)` evaluation path
/// (op-for-op the [`crate::nmf`] objective; kept local because that function
/// is private to its module).
fn kl_objective(v: &[f64], w: &[f64], h: &[f64], m: usize, n: usize, k: usize) -> f64 {
    let wh = matmul(w, h, m, n, k);
    let mut acc = 0.0f64;
    for (&vv, &mm) in v.iter().zip(wh.iter()) {
        acc += vv * ((KL_EPS + vv).ln() - (KL_EPS + mm).ln()) - vv + mm;
    }
    acc
}

/// Seeded deterministic initializer mirroring upstream scale
/// (`bayesianNMF.R:58-59`, `runif · sqrt(mean(V))`): open-interval uniforms
/// (0, 1] (zero-absorbing MU guard), W row-major first, then H row-major,
/// from `MsRng` on `StreamId::ZERO`.
fn seeded_init(v: &[f64], m: usize, n: usize, k: usize, seed: u64) -> Result<(Vec<f64>, Vec<f64>), MsError> {
    validate_shape(v, m, n, k)?;
    let mut rng = MsRng::from_stream(seed, StreamId::ZERO);
    let scale = {
        let mut mean = 0.0f64;
        for &x in v {
            mean += x;
        }
        mean /= (m * n) as f64;
        if mean > 0.0 {
            mean.sqrt()
        } else {
            1.0
        }
    };
    let mut w = vec![0.0f64; m * k];
    for x in w.iter_mut() {
        *x = scale * open_unit(&mut rng);
    }
    let mut h = vec![0.0f64; k * n];
    for x in h.iter_mut() {
        *x = scale * open_unit(&mut rng);
    }
    Ok((w, h))
}

/// Uniform draw on (0, 1] (same convention as [`crate::nmf`]).
fn open_unit(rng: &mut MsRng) -> f64 {
    ((rng.next_u64() >> 11) as f64 + 1.0) * (1.0 / (1u64 << 53) as f64)
}

fn validate_shape(v: &[f64], m: usize, n: usize, k: usize) -> Result<(), MsError> {
    if m == 0 || n == 0 || k == 0 {
        return Err(MsError::new("argument", "matrix dimensions must be positive")
            .with_i(m as i64)
            .with_j(n as i64));
    }
    if v.len() != m * n {
        return Err(
            MsError::new("argument", "counts storage must be m*n elements").with_i(v.len() as i64),
        );
    }
    for (idx, &x) in v.iter().enumerate() {
        if !x.is_finite() {
            return Err(MsError::new("na", "non-finite entry in counts")
                .with_i((idx / n + 1) as i64)
                .with_j((idx % n + 1) as i64));
        }
        if x < 0.0 {
            return Err(MsError::new("argument", "negative entry in counts")
                .with_i((idx / n + 1) as i64)
                .with_j((idx % n + 1) as i64));
        }
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn validate(
    v: &[f64],
    m: usize,
    n: usize,
    k: usize,
    w0: &[f64],
    h0: &[f64],
    tol: f64,
    a0: f64,
    b0: f64,
) -> Result<(), MsError> {
    validate_shape(v, m, n, k)?;
    if w0.len() != m * k {
        return Err(
            MsError::new("argument", "w0 storage must be m*k elements").with_i(w0.len() as i64),
        );
    }
    if h0.len() != k * n {
        return Err(
            MsError::new("argument", "h0 storage must be k*n elements").with_i(h0.len() as i64),
        );
    }
    for (name, mat) in [("w0", w0), ("h0", h0)] {
        for (idx, &x) in mat.iter().enumerate() {
            if !x.is_finite() {
                return Err(MsError::new("na", format!("non-finite entry in {name}"))
                    .with_i(idx as i64 + 1));
            }
            if x < 0.0 {
                return Err(
                    MsError::new("argument", format!("negative entry in {name}"))
                        .with_i(idx as i64 + 1),
                );
            }
        }
    }
    if !tol.is_finite() || tol <= 0.0 {
        return Err(MsError::new("argument", "tol must be finite and positive").with_i(1));
    }
    if !a0.is_finite() || a0 <= 0.0 {
        return Err(MsError::new("argument", "a0 must be finite and positive").with_i(1));
    }
    if !b0.is_finite() || b0 <= 0.0 {
        return Err(MsError::new("argument", "b0 must be finite and positive").with_i(1));
    }
    Ok(())
}

// ======================================================================
// Tests: hand-derived goldens (β update + penalized H step on a 2×3
// example at 1e-12; penalized W step on a dyadic example at 1e-12),
// zero-penalty bit-equality with the audited KL kernels, the pruning rule
// (dead-by-column-sum and dead-by-β crafted states), separable recovery
// with rank hit, redundant-component pruning on a dynamic fit, bit
// determinism, early convergence, and validation. Fixed seeds only.
// ======================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::nmf::{kl_h_step, kl_w_step};

    /// Uniform f64 in [0, 1) from the in-house generator (test data only).
    fn uniform(rng: &mut MsRng) -> f64 {
        ((rng.next_u64() >> 11) as f64) * (1.0 / (1u64 << 53) as f64)
    }

    fn cosine(a: &[f64], b: &[f64]) -> f64 {
        let dot: f64 = a.iter().zip(b.iter()).map(|(&x, &y)| x * y).sum();
        let na: f64 = a.iter().map(|x| x * x).sum::<f64>().sqrt();
        let nb: f64 = b.iter().map(|x| x * x).sum::<f64>().sqrt();
        dot / (na * nb)
    }

    fn column(mat: &[f64], rows: usize, cols: usize, c: usize) -> Vec<f64> {
        (0..rows).map(|r| mat[r * cols + c]).collect()
    }

    /// Greedy max-cosine one-to-one matching (deterministic tie-break), as
    /// in the nmf.rs test suite.
    fn greedy_match(fitted_cols: &[Vec<f64>], true_cols: &[Vec<f64>]) -> Vec<f64> {
        let mut pairs: Vec<(usize, usize, f64)> = Vec::new();
        for (i, fw) in fitted_cols.iter().enumerate() {
            for (t, tw) in true_cols.iter().enumerate() {
                pairs.push((i, t, cosine(fw, tw)));
            }
        }
        pairs.sort_by(|a, b| b.2.partial_cmp(&a.2).unwrap());
        let mut matched = Vec::new();
        let mut used_f = vec![false; fitted_cols.len()];
        let mut used_t = vec![false; true_cols.len()];
        while matched.len() < fitted_cols.len().min(true_cols.len()) {
            let pos = pairs
                .iter()
                .position(|&(i, t, _)| !used_f[i] && !used_t[t])
                .expect("matching impossible");
            let (i, t, c) = pairs[pos];
            used_f[i] = true;
            used_t[t] = true;
            matched.push(c);
        }
        matched
    }

    /// Separable truth (96×3 · 3×20), same construction as the nmf.rs
    /// recovery tests: 32 exclusive anchor channels per signature, near-pure
    /// sample groups pin the dictionary rays.
    fn separable_truth(seed: u64) -> (Vec<f64>, Vec<f64>, Vec<f64>) {
        let (m, n, k) = (96usize, 20usize, 3usize);
        let mut rng = MsRng::from_stream(seed, StreamId { replicate: 1, rank: 2, fold: 3 });
        let mut w = vec![0.0f64; m * k];
        for s in 0..k {
            let mut col: Vec<f64> = (0..m)
                .map(|i| {
                    if i / 32 == s {
                        0.5 + uniform(&mut rng)
                    } else {
                        0.0
                    }
                })
                .collect();
            let sum: f64 = col.iter().sum();
            for x in col.iter_mut() {
                *x /= sum;
            }
            for i in 0..m {
                w[i * k + s] = col[i];
            }
        }
        let mut h = vec![0.0f64; k * n];
        for j in 0..n {
            let dom = j / 5;
            for s in 0..k {
                h[s * n + j] = if dom == 3 || s == dom {
                    500.0 + 1000.0 * uniform(&mut rng)
                } else {
                    50.0 * uniform(&mut rng)
                };
            }
        }
        let v = matmul(&w, &h, m, n, k);
        (v, w, h)
    }

    // ------------------------------------------------------------------
    // Golden (hand-derived, 2 channels × 3 samples, k0 = 2, one
    // iteration's β update + penalized H step, tol 1e-12).
    //
    // V = [[1,0,2],[0,3,1]]; a0 = 10, b0 = 5 ⇒ C = 2 + 3/2 + 9 = 25/2.
    // W0 = [[1/2, 1], [2, 1/2]]; H0 = [[1, 2, 1/2], [1/2, 1, 1]].
    //
    // β (bayesianNMF.R:65): comp 0: Σw = 5/2, ½Σh² = 21/8, + 5 = 81/8 ⇒
    // β0_0 = (25/2)/(81/8) = 100/81. comp 1: Σw = 3/2, ½Σh² = 9/8, +5 =
    // 61/8 ⇒ β0_1 = (25/2)/(61/8) = 100/61 (= 12.5/7.625).
    //
    // WH0 = [[1, 2, 5/4], [9/4, 9/2, 3/2]]; R = V ⊘ WH0 =
    // [[1, 0, 8/5], [0, 2/3, 2/3]].
    // H step (bayesianNMF.R:74): num[0] = [1/2, 4/3, 32/15],
    // num[1] = [1, 1/3, 29/15]; den[0][j] = 5/2 + β0_0·H0[0][j],
    // den[1][j] = 3/2 + β0_1·H0[1][j]. Exact fractions:
    //   H1[0] = [81/605, 432/805, 864/2525],
    //   H1[1] = [61/283, 122/1149, 3538/5745].
    // ------------------------------------------------------------------
    #[test]
    fn golden_ard_beta_and_h_step_2x3() {
        let v = [1.0, 0.0, 2.0, 0.0, 3.0, 1.0];
        let (m, n, k) = (2usize, 3usize, 2usize);
        let w0 = [0.5, 1.0, 2.0, 0.5];
        let h0 = [1.0, 2.0, 0.5, 0.5, 1.0, 1.0];
        let a0 = 10.0;
        let b0 = 5.0;

        let fit = fit_ard_with_init(&v, m, n, k, &w0, &h0, 1, 1e-5, a0, b0).unwrap();

        // Initial hyperparameters.
        let c = m as f64 + 0.5 * n as f64 + a0 - 1.0;
        assert!((c - 12.5).abs() < 1e-12);
        assert!((fit.beta_cut - (c / b0) / 1.25).abs() < 1e-12);
        // Initial β from the initializer (before any factor step).
        let beta0 = ard_beta(&w0, &h0, m, n, k, c, b0);
        assert!((beta0[0] - 12.5 / 10.125).abs() < 1e-12, "β0_0 = {beta0:?}");
        assert!((beta0[1] - 12.5 / 7.625).abs() < 1e-12, "β0_1 = {beta0:?}");

        // The one-step H values as exact fractions (derivations above).
        let expect_h = [
            81.0 / 605.0,
            432.0 / 805.0,
            864.0 / 2525.0,
            61.0 / 283.0,
            122.0 / 1149.0,
            3538.0 / 5745.0,
        ];
        for (got, want) in fit.h.iter().zip(expect_h) {
            assert!((got - want).abs() < 1e-12, "h1 = {:?}", fit.h);
        }

        // Evidence trace at the initializer, hand-derived:
        // like0 = 2·ln(8/5) + 4·ln(2/3) + 11/2 (zero channels contribute WH);
        // hyperparameter terms: acc_k·β0_k − C·ln β0_k with acc_0 = 10.125,
        // acc_1 = 7.625 (the β update denominators).
        let like0 = 2.0 * (8.0f64 / 5.0).ln() + 4.0 * (2.0f64 / 3.0).ln() + 5.5;
        let want_evidence0 = like0
            + (10.125 * (12.5 / 10.125) - 12.5 * (12.5f64 / 10.125).ln())
            + (7.625 * (12.5 / 7.625) - 12.5 * (12.5f64 / 7.625).ln());
        assert!((fit.objective[0] - want_evidence0).abs() < 1e-9);
        assert_eq!(fit.objective.len(), 2);
        assert_eq!(fit.iterations, 1);
    }

    // ------------------------------------------------------------------
    // Golden (hand-derived, dyadic): the penalized W step at 1e-12.
    // W0 (3×2) = [[1/4, 1/2], [1, 1/8], [1/2, 1/4]]; H0 = [[2, 0], [0, 4]];
    // V = 2·W0H0 = [[1, 4], [4, 1], [2, 2]] ⇒ R = V ⊘ WH0 ≡ 2 exactly.
    // With β = [1/4, 1/2]: num[i][0] = 2·(2+0) = 4, num[i][1] = 2·(0+4) = 8;
    // den[0] = (2 + 1/4), den[1] = (4 + 1/2). So column 0 is scaled by
    // 4/2.25 = 16/9 and column 1 by 8/4.5 = 16/9.
    // ------------------------------------------------------------------
    #[test]
    fn golden_ard_w_step_dyadic() {
        let v = [1.0, 4.0, 4.0, 1.0, 2.0, 2.0];
        let (m, n, k) = (3usize, 2usize, 2usize);
        let mut w = [0.25, 0.5, 1.0, 0.125, 0.5, 0.25];
        let h = [2.0, 0.0, 0.0, 4.0];
        let beta = [0.25, 0.5];

        ard_w_step(&v, &mut w, &h, m, n, k, &beta);
        let expect = [0.25 * (4.0 / 2.25), 0.5 * (8.0 / 4.5),
                      1.0 * (4.0 / 2.25), 0.125 * (8.0 / 4.5),
                      0.5 * (4.0 / 2.25), 0.25 * (8.0 / 4.5)];
        for (got, want) in w.iter().zip(expect) {
            assert!((got - want).abs() < 1e-12, "w1 = {w:?}");
        }
    }

    // ------------------------------------------------------------------
    // Zero-penalty no-drift contract: with β ≡ 0 the ARD steps must be
    // bit-identical to the audited crate::nmf KL kernels.
    // ------------------------------------------------------------------
    #[test]
    fn ard_zero_penalty_steps_match_kl_kernel_bitwise() {
        let mut rng = MsRng::from_stream(11, StreamId { replicate: 5, rank: 5, fold: 5 });
        let (m, n, k) = (7usize, 5usize, 3usize);
        let v: Vec<f64> = (0..m * n).map(|_| (uniform(&mut rng) * 20.0).floor()).collect();
        let w: Vec<f64> = (0..m * k).map(|_| 0.1 + uniform(&mut rng)).collect();
        let h: Vec<f64> = (0..k * n).map(|_| 0.1 + uniform(&mut rng)).collect();
        let zero_beta = vec![0.0f64; k];

        let mut h_ard = h.clone();
        ard_h_step(&v, &w, &mut h_ard, m, n, k, &zero_beta);
        let mut h_kl = h.clone();
        kl_h_step(&v, &w, &mut h_kl, m, n, k);
        assert_eq!(h_ard, h_kl, "ARD H step drifted from kl_h_step at β = 0");

        let mut w_ard = w.clone();
        ard_w_step(&v, &mut w_ard, &h, m, n, k, &zero_beta);
        let mut w_kl = w.clone();
        kl_w_step(&v, &mut w_kl, &h, m, n, k);
        assert_eq!(w_ard, w_kl, "ARD W step drifted from kl_w_step at β = 0");

        // And the local KL objective must match the crate objective's
        // evaluation exactly (used by the evidence trace).
        let mut w2 = w.clone();
        kl_w_step(&v, &mut w2, &h, m, n, k);
        let obj_local = kl_objective(&v, &w2, &h, m, n, k);
        let fit_kl = crate::nmf::fit_kl_with_init(&v, m, n, k, &w2, &h, 0).unwrap();
        assert_eq!(fit_kl.objective[0], obj_local);
    }

    // ------------------------------------------------------------------
    // Pruning rule on a crafted state (max_iter = 0, so the rule — not
    // ARD dynamics — is under test): component 0 is dead by both clauses
    // (zero W column, zero H row ⇒ β = C/b0 > β_cut); component 1 is dead
    // by β only (W column sum 1 > 1e-5 but ½Σh² = 1.5e-6 < b0/4 ⇒
    // β_1 = C/(1 + 1.5e-6 + 5) > (C/5)/1.25); component 2 is alive.
    // ------------------------------------------------------------------
    #[test]
    fn ard_pruning_rule_dead_by_column_sum_and_by_beta() {
        let (m, n, k) = (4usize, 3usize, 3usize);
        let v = [1.0, 2.0, 1.0, 2.0, 1.0, 2.0, 1.0, 2.0, 1.0, 2.0, 1.0, 2.0];
        let mut w0 = vec![0.5f64; m * k];
        let mut h0 = vec![10.0f64; k * n];
        // Component 0: fully dead (zero column / zero row).
        for i in 0..m {
            w0[i * k] = 0.0;
        }
        for x in h0.iter_mut().take(n) {
            *x = 0.0;
        }
        // Component 1: dead by β only (W column sum 0.4, so
        // Σw + ½Σh² = 0.4 + 1.5e-6 < 1.25 ⇒ β_1 > β_cut, but the column
        // sum is above the 1e-5 colsum threshold).
        for (i, x) in w0.iter_mut().enumerate() {
            if i % k == 1 {
                *x = 0.1;
            }
        }
        for x in &mut h0[n..2 * n] {
            *x = 1e-3;
        }
        let fit = fit_ard_with_init(&v, m, n, k, &w0, &h0, 0, 1e-5, 10.0, 5.0).unwrap();
        assert_eq!(fit.active, vec![false, false, true]);
        assert_eq!(fit.k_est, 1);
        // β_0 = C/b0 = (4 + 1.5 + 9)/5 = 2.9 > β_cut = 2.32.
        assert!(fit.beta[0] > fit.beta_cut);
        assert!(fit.beta[2] <= fit.beta_cut);
        // Pruned factors: 1 component, original order kept.
        assert_eq!(fit.w_active.len(), m);
        assert_eq!(fit.h_active.len(), n);
        assert_eq!(fit.w_active, column(&fit.w, m, k, 2));
    }

    // Audited P0 regression guard: w_active is ROW-MAJOR m×k_est. With all
    // components alive the pruned faces must equal the raw factors
    // bit-for-bit; with two survivors the row-major extraction is pinned.
    // (The previous column-block assembly passed the k_est=1 prune test
    // above while scrambling every k_est ≥ 2 face.)
    #[test]
    fn w_active_layout_is_row_major() {
        let m = 4usize;
        let n = 3usize;
        let k = 3usize;
        // Deterministic positive factors/counts: all components survive.
        let v: Vec<f64> = (0..m * n).map(|i| 1.0 + (i % 7) as f64).collect();
        let w0: Vec<f64> = (0..m * k).map(|i| 1.0 + (i % 5) as f64).collect();
        let h0: Vec<f64> = (0..k * n).map(|i| 1.0 + (i % 3) as f64).collect();
        let fit = fit_ard_with_init(&v, m, n, k, &w0, &h0, 1, 1e-5, 10.0, 5.0).unwrap();
        if fit.k_est == k {
            assert_eq!(fit.w_active, fit.w);
            assert_eq!(fit.h_active, fit.h);
        }
        // Two-survivor extraction: kill component 1 explicitly via a zero
        // column (W column of exact zeros is dead under colSums <= 1e-5).
        let w1 = {
            let mut w = w0.clone();
            for i in 0..m {
                w[i * k + 1] = 0.0;
            }
            w
        };
        let fit2 = fit_ard_with_init(&v, m, n, k, &w1, &h0, 1, 1e-5, 10.0, 5.0).unwrap();
        assert_eq!(fit2.active, vec![true, false, true]);
        assert_eq!(fit2.k_est, 2);
        for i in 0..m {
            assert_eq!(fit2.w_active[i * 2], fit2.w[i * k]);
            assert_eq!(fit2.w_active[i * 2 + 1], fit2.w[i * k + 2]);
        }
    }

    // ------------------------------------------------------------------
    // Separable recovery + automatic rank hit: true k = 3 recovered with
    // k0 = 3 (cosine ≥ 0.99 per matched column, k_est = 3).
    // ------------------------------------------------------------------
    #[test]
    fn ard_separable_recovery_and_rank_hit() {
        let (v, w_true, _h_true) = separable_truth(0xBEEF);
        let (m, n, k) = (96usize, 20usize, 3usize);
        let fit = fit_ard(&v, m, n, k, 4000, 1e-7, 10.0, 5.0, 42).unwrap();
        assert_eq!(fit.k_est, k, "ARD killed a true component: {:?}", fit.active);
        assert!(fit.iterations < 4000 || fit.converged);
        let wh = matmul(&fit.w, &fit.h, m, n, k);
        let recon = cosine(&v, &wh);
        assert!(recon >= 0.999, "reconstruction cosine {recon}");
        let true_cols: Vec<Vec<f64>> = (0..k).map(|s| column(&w_true, m, k, s)).collect();
        let fitted_cols: Vec<Vec<f64>> = (0..k).map(|s| column(&fit.w, m, k, s)).collect();
        for c in greedy_match(&fitted_cols, &true_cols) {
            assert!(c >= 0.99, "matched W column cosine {c}");
        }
    }

    // ------------------------------------------------------------------
    // Dynamic pruning: inject a redundant 4th component on top of the
    // separable k = 3 truth; ARD must collapse the duplicated pair to one
    // component (k_est = 3). The injected column is a symmetry-broken
    // near-duplicate of component 0 (an exact clone would sit in a
    // symmetric saddle the MU equations can never leave — the penalty is
    // identical on both clones); the 1.01 factor breaks the tie, and the
    // ARD dynamics concentrate the pair's mass on one of them while the
    // other's Σw + ½Σh² collapses below the death threshold. Which label
    // of the pair survives is a property of the tie-break, not of the
    // algorithm, so the assertion is pair-aware.
    // ------------------------------------------------------------------
    #[test]
    fn ard_prunes_redundant_injected_component() {
        let (v, _w_true, _h_true) = separable_truth(0xBEEF);
        let (m, n, k_true) = (96usize, 20usize, 3usize);
        let k0 = 4usize;
        // Deterministic init, then overwrite component 3 with a
        // near-duplicate of component 0.
        let (w0, h0) = {
            let fit0 = fit_ard(&v, m, n, k0, 0, 1.0, 10.0, 5.0, 42).unwrap();
            (fit0.w, fit0.h)
        };
        let mut w0 = w0;
        let mut h0 = h0;
        for i in 0..m {
            w0[i * k0 + 3] = w0[i * k0] * 1.01;
        }
        let dup = h0[..n].to_vec();
        h0[3 * n..4 * n].copy_from_slice(&dup);
        let fit = fit_ard_with_init(&v, m, n, k0, &w0, &h0, 4000, 1e-7, 10.0, 5.0).unwrap();
        assert_eq!(fit.k_est, k_true, "active = {:?}, beta = {:?}", fit.active, fit.beta);
        // Exactly one of the duplicated pair {0, 3} died; the distinct
        // components 1 and 2 survived.
        assert!(fit.active[1] && fit.active[2], "true components killed: {:?}", fit.active);
        assert!(
            fit.active[0] ^ fit.active[3],
            "duplicate pair not collapsed to one: {:?}",
            fit.active
        );
    }

    // ------------------------------------------------------------------
    // Determinism and convergence bookkeeping.
    // ------------------------------------------------------------------
    #[test]
    fn ard_fit_is_bit_identical_across_runs() {
        let (v, _w, _h) = separable_truth(0xCAFE);
        let (m, n, k) = (96usize, 20usize, 4usize);
        let a = fit_ard(&v, m, n, k, 50, 1e-7, 10.0, 5.0, 7).unwrap();
        let b = fit_ard(&v, m, n, k, 50, 1e-7, 10.0, 5.0, 7).unwrap();
        assert_eq!(a, b);
    }

    #[test]
    fn ard_convergence_early_stop_and_cap() {
        let mut rng = MsRng::from_stream(3, StreamId { replicate: 9, rank: 1, fold: 2 });
        let v: Vec<f64> = (0..8 * 6).map(|_| (uniform(&mut rng) * 30.0).floor()).collect();
        let loose = fit_ard(&v, 8, 6, 3, 10_000, 1e-2, 10.0, 5.0, 5).unwrap();
        assert!(loose.converged, "loose tolerance did not converge");
        assert!(loose.iterations < 10_000);
        let capped = fit_ard(&v, 8, 6, 3, 3, 1e-12, 10.0, 5.0, 5).unwrap();
        assert!(!capped.converged);
        assert_eq!(capped.iterations, 3);
        assert_eq!(capped.objective.len(), 4);
        assert!(capped.objective.iter().all(|x| x.is_finite()));
    }

    // ------------------------------------------------------------------
    // Validation error paths.
    // ------------------------------------------------------------------
    #[test]
    fn ard_validation_errors() {
        let v = [1.0, 2.0, 3.0, 4.0];
        let w0 = [1.0, 1.0, 1.0, 1.0];
        // k0 = 0.
        assert_eq!(fit_ard(&v, 2, 2, 0, 1, 1e-5, 10.0, 5.0, 0).unwrap_err().topic(), "argument");
        // Storage mismatch (h0 must be k0·n = 4 elements for k0 = 2).
        assert_eq!(
            fit_ard_with_init(&v, 2, 2, 2, &w0, &[1.0, 1.0], 1, 1e-5, 10.0, 5.0)
                .unwrap_err()
                .topic(),
            "argument"
        );
        // Non-finite / negative counts (1-based indices attached).
        let err = fit_ard(&[1.0, f64::NAN, 3.0, 4.0], 2, 2, 1, 1, 1e-5, 10.0, 5.0, 0).unwrap_err();
        assert_eq!(err.topic(), "na");
        assert_eq!(err.i, Some(1));
        assert_eq!(err.j, Some(2));
        let err = fit_ard(&[1.0, -2.0, 3.0, 4.0], 2, 2, 1, 1, 1e-5, 10.0, 5.0, 0).unwrap_err();
        assert_eq!(err.topic(), "argument");
        // Bad hyperparameters: tol, a0, b0.
        for (tol, a0, b0) in [(0.0, 10.0, 5.0), (-1.0, 10.0, 5.0), (1e-5, 0.0, 5.0), (1e-5, f64::NAN, 5.0), (1e-5, 10.0, -5.0), (1e-5, 10.0, f64::INFINITY)] {
            let err = fit_ard(&v, 2, 2, 1, 1, tol, a0, b0, 0).unwrap_err();
            assert_eq!(err.topic(), "argument", "tol={tol} a0={a0} b0={b0}");
        }
        // Negative initializer entry.
        let err = fit_ard_with_init(&v, 2, 2, 1, &[1.0, -1.0], &[0.5, 0.5], 1, 1e-5, 10.0, 5.0)
            .unwrap_err();
        assert_eq!(err.topic(), "argument");
    }
}
