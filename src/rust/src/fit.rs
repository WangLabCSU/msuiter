//! Reference-based exposure fitting core (U-M3a-02): the pure (R-type-free)
//! heart of `ms_fit_rust` — the three fitting methods behind the user-facing
//! `ms_fit()` generic (`R/fit.R`). This module composes the audited engine
//! kernels (`engine::nnls`, `engine::likelihood`) into whole-fit procedures;
//! no kernel semantics are changed here (ARCHITECTURE §2 layering).
//!
//! # The three methods (research/02 §1 semantics, D11 anchors)
//!
//! * **`nnls`** — per-sample Lawson–Hanson active-set NNLS on the K-format
//!   Gram pair (`G = SᵀS`, `b_j = Sᵀv_j`; `engine::nnls::nnls_gram`), the
//!   deconstructSigs baseline row of CAPABILITY-MATRIX L-D. The K-format
//!   solves exactly `argmin ‖Sθ − v_j‖₂, θ ≥ 0` (the kernel module docs pin
//!   the identity).
//! * **`likelihood_bidirectional`** — MuSiCal's
//!   `nnls_likelihood_bidirectional` semantics (research/02 §1.1): full
//!   NNLS initial support; then backward/forward steps on the
//!   **per-mutation multinomial log-likelihood scale** `L = Σᵢ xᵢ ln(pᵢ) /
//!   Σx` with the `1e-16` probability guard
//!   ([`msuiter_engine::likelihood::LL_EPS`] — the pinned `nnls_sparse.py`
//!   clip, research/02 §1.1 line 20). Backward step: for each `j` in the
//!   support, re-solve NNLS on the support minus `j`;
//!   `Δ_j = L_current − L_(−j)` (the cost of removal); remove the argmin if
//!   `Δ < ϵ` (research/02 §1.1 line 15: "移除 Δ 最小者若 Δ < ϵ_backward；
//!   否则停"). Forward step: symmetric — add the candidate with maximal
//!   gain `L_(+j) − L_current` if it exceeds `ϵ` (line 16). Steps alternate
//!   until both decline, capped at `max_iter` rounds (upstream 1000, the
//!   anti-cycling cap). A final NNLS re-solve on the surviving support is
//!   implicit: the support is re-solved after every accepted step, so the
//!   returned exposures ARE the final refit. The connected-signature
//!   rejoin and the TMB rescaling of the upstream are deliberately out of
//!   scope (no COSMIC connected-group configuration exists in this unit;
//!   deferred with the MSU-Fit orchestration).
//! * **`lrt`** — mSigAct-flavoured fit (research/02 §1.2): exposures are
//!   the negative-binomial MLE (warm-started from the NNLS solution;
//!   concave objective, projected-gradient ascent with Armijo backtracking
//!   — deterministic, no external optimizer, D9), and the per-signature
//!   evidence is the **entry-wise presence LRT**: full-model NB likelihood
//!   vs the model refit without signature `a`, `D = 2(ll_with − ll_without)`
//!   ([`msuiter_engine::likelihood::lrt_stat`]), raw p-value
//!   `½·erfc(√(D/2))` ([`msuiter_engine::likelihood::p_chisq1_lrt`], the
//!   Self–Liang boundary default; **no BH correction here** — that is
//!   `ms_test_presence()`'s contract, U-M3a-03). The upstream PASA forward
//!   *set search* (candidate pruning + sequential inclusion, research/02
//!   §1.2) is NOT implemented: this unit ships the entry-wise test the task
//!   pins ("逐签名 entry-wise presence LRT"); the set search belongs to the
//!   presence-testing unit.
//!
//! # Uniform evidence columns (documented semantics)
//!
//! The returned `lrt_stat` / `lrt_p` grids are method-INDEPENDENT and
//! bit-identical across the three methods on the same input: they are
//! always computed at the NB-MLE exposures warm-started from the FULL NNLS
//! solution (the mSigAct presence-test machinery), so presence evidence
//! never depends on the exposure estimator. The `exposures` column is
//! method-dependent: least squares (`nnls` / the bidirectional final
//! refit) or NB-MLE (`lrt`). `support` is the zeroing decision on the
//! returned exposures: entries whose compositional share is strictly below
//! `zero_threshold` (default
//! [`msuiter_engine::likelihood::SIGFIT_ZERO_SHARE`] = 0.01, the sigfit
//! CI-zeroing family anchor) are set to **exactly 0** and flagged
//! `support = 0` — the [`msuiter_engine::likelihood::zeroing_mask_share`]
//! predicate semantics, applied as the decision rule (清零). Fisher
//! standard errors ([`msuiter_engine::likelihood::fisher_se`]) are computed
//! on the post-zeroing exposures: interior (kept) components only, `NaN`
//! at the boundary — "boundary parameters get tests, not intervals"
//! (ARCHITECTURE §5).
//!
//! # Layout contract (the transposition trap)
//!
//! Identical to `extract.rs`: R passes `t(counts)` (n×m) and `t(sigs)`
//! (k×m); the column-major flat buffers of those transposes ARE the
//! row-major `m×n` counts and `m×k` signatures this core reads:
//! `counts[i*n + j] == counts[i, j]`, `sigs[i*k + a] == sigs[i, a]`. The
//! acceptance smokes on BOTH sides run on asymmetric shapes, which a
//! transposed handoff cannot pass.
//!
//! # Interrupt / threads (declared decisions, contract 6/7)
//!
//! A single `ms_fit` call is a bounded sequential batch over samples: every
//! inner loop is capped (`max_iter` rounds / NNLS active-set cap / line
//! search caps). Like `ms_extract_rust`, this export is **declared
//! bounded-duration and non-interruptible**: there is no chunk structure
//! below sample granularity worth a callback seam through the pure engine
//! crate. `n_threads` is validated (≥ 0) and otherwise unused — the core
//! is sequential and trivially thread-invariant (A7); sample-parallelism
//! lands with the bootstrap unit (U-M3a-03).
//!
//! # Determinism
//!
//! Fixed loop order, first-index tie-breaking in every argmin/argmax, no
//! hashing, no threads: equal inputs produce bit-identical output (pinned
//! by tests for all three methods).
//!
//! # U-M3a-03 extension: bootstrap CI + cohort presence test
//!
//! Two faces land here, both composed ONLY of the audited primitives above
//! (no kernel semantics change):
//!
//! * [`bootstrap`] — the nonparametric (multinomial) percentile bootstrap
//!   of the whole three-method fit (research/02 §2: "bootstrap 应重采样
//!   突变（多项）而非通道"). Per boot `b`, every sample `j` has its `N_j`
//!   mutations resampled from the empirical channel distribution via
//!   [`msuiter_engine::resample::multinomial`] on the boot's own canonical
//!   stream `StreamId { replicate: b, rank: 0, fold: 0 }` (the
//!   `resample.rs` batch layout; the n per-sample draws consume the stream
//!   sequentially in fixed sample order). Each resampled catalog is fitted
//!   with the selected method; across boots this yields the 2.5/97.5
//!   percentile CI and the support stability (frequency of `support = 1`).
//!   Parallelism exists ONLY between boots (contract 6 independent units,
//!   chunk-boundary interrupt polling per the `replicates.rs` skeleton);
//!   each boot is a sequential fit, so `threads ∈ {1, N}` are bit-identical.
//!   The wire format is the COMPRESSED choice (documented decision): CI
//!   summaries `ci_lower` / `ci_upper` / `support_stability` (k×n), not the
//!   raw `n_boot × k × n` cube — deterministic given the seed, bounded
//!   memory, and the percentile arithmetic is pinned by tests.
//! * [`presence_test`] — the cohort per-signature presence test with
//!   Benjamini–Hochberg multiplicity control (research/02 §2, mSigAct
//!   "χ²₁ + BH q"): the entry-wise LRT machinery of [`fit`] (which is
//!   method-independent by construction) is pooled across samples by
//!   SUMMING the per-sample statistics (independent likelihoods add), the
//!   raw p is the **exact pooled-null tail** — the Binomial(n, ½) mixture
//!   of χ²_m ([`pooled_presence_p`]; the 2026-10 independent-audit P0
//!   correction of the pooled chi-square reference, bit-identical to the
//!   Self–Liang half-tail `½·erfc(√(D/2))` at n = 1) — and [`bh_adjust`]
//!   applies the step-up BH correction over the k-signature family.
//!   `pass_bh` is the `p_bh ≤` [`BH_ALPHA`] verdict.
//!
//! # U-M3a-05 extension: TMB rescale + connected-signature rejoin
//!
//! The two whole-fit post-steps of the MSU-Fit table (ARCHITECTURE §5,
//! "背景签名策略 + connected 组配置") land here as pure grid transforms on
//! the returned exposures (research/02 §1 anchors: the MuSiCal TMB rescale
//! is `02-fitting-inference.md` line 27 — "放大到 N 总突变跑稀疏搜索，再回
//! 原计数重解"; the connected rejoin is line 23 — "保留签名的 connected 签名
//! 在最终 NNLS 前重新加入", groups per line 30 / `utils.py SIGS_ASSOCIATED`):
//!
//! * [`rescale_to_totals`] — per-sample multiplication of the exposure
//!   column back onto the original mutation-total scale (the MuSiCal
//!   rescale semantics: after any fit on a normalized/amplified catalog,
//!   exposures are brought back so that, per sample, the kept exposures sum
//!   to the sample's own mutation total). Conservation is pinned at 1e-12
//!   by tests; an all-zero column stays zero (nothing to conserve).
//! * [`ConnectedSpec`] / [`ConnectedStrategy::FixAndRefit`] — the
//!   clock-like connected components (e.g. the SBS1/SBS5-flavoured
//!   background group) rejoin the fit: they are FIXED at their initial
//!   full-dictionary NNLS solution while the remaining components are
//!   re-optimized against the residual (grouped alternating minimization
//!   with a frozen block, which converges after the single free-block
//!   solve implemented here). **Documented approximation (D13)**: the
//!   upstream rejoins the connected signatures into the final NNLS support
//!   and re-solves ALL components JOINTLY (research/02 §1 line 23);
//!   FixAndRefit instead pins the connected block at the initial solution,
//!   so it never adjusts to the sparse refit. [`ConnectedStrategy::
//!   JointRefit`] — the upstream-exact joint re-solve — is DECLARED FUTURE
//!   WORK: requesting it is a structured argument error, never a silent
//!   simplification.
//!
//! Both steps run after the method's exposure solve and BEFORE the
//! share-zeroing decision (shares are per-sample scale invariant, so the
//! rescale cannot flip a zeroing verdict; the rejoin can). The uniform
//! evidence columns (`lrt_stat` / `lrt_p`) are untouched: they are defined
//! at the NB-MLE exposures of the raw catalog and remain bit-identical
//! across connected/rescale configurations. [`fit`] keeps its frozen
//! signature and delegates to [`fit_with`] with `(connected = None,
//! rescale = false)` — the legacy path, bit-identical by tests.

use std::sync::atomic::{AtomicBool, Ordering};

use rayon::prelude::*;

use msuiter_engine::error::MsError;
use msuiter_engine::likelihood::{
    fisher_se, ln_gamma, lrt_stat, multinomial_ll_per_mutation, nb_ll, p_chisq1_lrt,
    p_chisq1_upper, zeroing_mask_share, LL_EPS,
};
use msuiter_engine::nnls::{nnls_gram, NnlsOptions};
use msuiter_engine::resample;
use msuiter_engine::rng::{MsRng, StreamId};

/// Convergence tolerance of the internal NB-MLE projected-gradient ascent:
/// stop once an accepted step improves the log-likelihood by at most
/// `NB_MLE_TOL · (1 + |ll|)` (relative) or the projected gradient meets
/// [`PG_TOL`] (see below). A fixed internal constant — the FFI `tol` is the
/// MuSiCal ϵ of the bidirectional method — tight enough that the entry-wise
/// LRT columns are optimizer-insensitive (pinned by the size/power smoke
/// below).
pub const NB_MLE_TOL: f64 = 1e-10;

/// Projected-gradient KKT tolerance of the NB-MLE ascent, scaled by the
/// gradient magnitude at the warm start: `pg∞ ≤ PG_TOL · (1 + pg0∞)` where
/// `pg_a = |∂ll/∂h_a|` on the interior and `max(0, ∂ll/∂h_a)` at the
/// boundary. This is the primary stop (linear convergence on
/// ill-conditioned signature dictionaries makes pure improvement stops
/// crawl); the scale anchor keeps it problem-relative and deterministic.
pub const PG_TOL: f64 = 1e-8;

/// Armijo sufficient-decrease constant of the NB-MLE line search.
const ARMIJO_C: f64 = 1e-4;

/// Backtracking cap of one NB-MLE line search (step halvings). Exhaustion
/// means no acceptable ascent step exists at line-search resolution: the
/// point is treated as the (boundary-inclusive) optimum.
const LINE_SEARCH_MAX: u32 = 80;

/// The fitting method behind one `ms_fit` call.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FitMethod {
    /// Lawson–Hanson NNLS baseline (per-sample K-format).
    Nnls,
    /// MuSiCal `nnls_likelihood_bidirectional` semantics (ϵ stepping).
    LikelihoodBidirectional,
    /// NB-MLE exposures + entry-wise presence LRT (mSigAct flavour).
    Lrt,
}

impl FitMethod {
    /// Parse the wire name from the R side (contract 4: explicit, errors
    /// not panics; the message lists the legal names).
    pub fn parse(name: &str) -> Result<Self, MsError> {
        match name {
            "nnls" => Ok(FitMethod::Nnls),
            "likelihood_bidirectional" => Ok(FitMethod::LikelihoodBidirectional),
            "lrt" => Ok(FitMethod::Lrt),
            other => Err(MsError::new(
                "argument",
                format!(
                    "method \"{other}\" is not one of \"nnls\", \"likelihood_bidirectional\", \"lrt\""
                ),
            )),
        }
    }

    /// Canonical wire name (echoed back in the result list).
    pub fn as_str(self) -> &'static str {
        match self {
            FitMethod::Nnls => "nnls",
            FitMethod::LikelihoodBidirectional => "likelihood_bidirectional",
            FitMethod::Lrt => "lrt",
        }
    }
}

/// Outcome of one [`fit`] call. All grids are **row-major k×n** (signatures
/// × samples); the FFI adapter transposes them into column-major R matrices.
#[derive(Debug, Clone, PartialEq)]
pub struct FitOutput {
    /// Fitted exposures (row-major k×n). Zeroed entries are exactly 0.0.
    pub exposures: Vec<f64>,
    /// Zeroing decision per (signature, sample): 1 = kept, 0 = zeroed.
    pub support: Vec<i32>,
    /// Entry-wise presence LRT statistic `D` (row-major k×n).
    pub lrt_stat: Vec<f64>,
    /// Raw boundary p-value `½·erfc(√(D/2))` (row-major k×n; no BH here).
    pub lrt_p: Vec<f64>,
    /// Fisher standard errors on the interior support; NaN at boundary
    /// entries (row-major k×n).
    pub se: Vec<f64>,
    /// AND over samples of (method-internal convergence AND the presence
    /// NB-MLE fits converging within `max_iter`).
    pub converged: bool,
}

/// Run one reference-based fit of `counts` (row-major m×n) against
/// `sigs` (row-major m×k, channels × signatures).
///
/// `nb_size` is the NB size for every likelihood-based column (mSigAct
/// `nbinom.size`; larger = closer to Poisson). `eps` is the MuSiCal LTH ϵ
/// of the bidirectional method (validated for the other methods, unused).
/// `max_iter` caps the bidirectional rounds and the NB-MLE iterations.
/// `zero_threshold` drives the share-based zeroing decision on the returned
/// exposures. See the module docs for the per-method semantics.
///
/// Frozen legacy face: delegates to [`fit_with`] with no connected
/// configuration and no rescale — bit-identical to the pre-U-M3a-05
/// pipeline (pinned by tests).
#[allow(clippy::too_many_arguments)]
pub fn fit(
    counts: &[f64],
    sigs: &[f64],
    m: usize,
    n: usize,
    k: usize,
    method: FitMethod,
    nb_size: f64,
    eps: f64,
    max_iter: usize,
    zero_threshold: f64,
) -> Result<FitOutput, MsError> {
    fit_with(
        counts, sigs, m, n, k, method, nb_size, eps, max_iter, zero_threshold, None, false,
    )
}

// ======================================================================
// U-M3a-05: TMB rescale + connected-signature rejoin (MSU-Fit whole-fit
// post-steps; ARCHITECTURE §5 "背景签名策略 + connected 组配置").
// ======================================================================

/// Rescale the exposure grid back onto the original per-sample mutation
/// totals (the MuSiCal TMB-rescale semantics, research/02 §1 line 27:
/// "放大到 N 总突变跑稀疏搜索，再回原计数重解" — after any fit on a
/// normalized/amplified catalog, exposures are brought back to the original
/// count scale). `exposures` is the row-major k×n grid this module returns
/// everywhere; `sample_totals[j]` is the original mutation total of sample
/// `j`. Every exposure of sample `j` is multiplied by
/// `totals[j] / Σ_a exposures[a, j]`, so the column sums to the original
/// total (conservation pinned at 1e-12 by tests). An all-zero column has
/// nothing to conserve and stays all-zero; a zero total zeroes the column
/// (factor 0). Zeros introduced by an earlier zeroing decision are never
/// resurrected: the rescale multiplies, it does not redistribute.
pub fn rescale_to_totals(
    exposures: &[f64],
    sample_totals: &[f64],
    n: usize,
) -> Result<Vec<f64>, MsError> {
    let k = exposures.len().checked_div(n).unwrap_or(0);
    if exposures.len() != k * n || sample_totals.len() != n {
        return Err(MsError::new(
            "argument",
            "rescale needs exposures of k*n elements and one total per sample",
        )
        .with_i(exposures.len() as i64)
        .with_j(sample_totals.len() as i64));
    }
    for (j, &t) in sample_totals.iter().enumerate() {
        if !t.is_finite() || t < 0.0 {
            return Err(MsError::new(
                "argument",
                "sample totals must be finite and non-negative",
            )
            .with_j(j as i64 + 1));
        }
    }
    let mut out = exposures.to_vec();
    for j in 0..n {
        let sum: f64 = (0..k).map(|a| out[a * n + j]).sum();
        if sum > 0.0 {
            let factor = sample_totals[j] / sum;
            for a in 0..k {
                out[a * n + j] *= factor;
            }
        }
        // sum == 0: nothing to conserve (all-zero column stays all-zero;
        // a zero total is already met exactly).
    }
    Ok(out)
}

/// Strategy of the connected-signature rejoin (U-M3a-05).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectedStrategy {
    /// The connected components (e.g. the SBS1/SBS5-flavoured clock group)
    /// are FIXED at their initial full-dictionary NNLS solution after the
    /// method refit; the remaining components are re-optimized against the
    /// residual (grouped alternating minimization with a frozen block).
    ///
    /// Declared approximation of the upstream MuSiCal connected semantics
    /// (research/02 §1 line 23): upstream rejoins the connected signatures
    /// into the final NNLS support and re-solves ALL components jointly,
    /// so the connected block there DOES adjust to the sparse refit, and
    /// the sparsified solution there can still drop a connected signature
    /// if the joint solve zeroes it. FixAndRefit pins the block instead —
    /// an acceptable background-anchor semantics, documented here per D13
    /// and never presented as upstream-exact.
    FixAndRefit,
    /// The upstream-exact joint re-solve: connected components rejoin the
    /// support and ALL components are optimized together. DECLARED FUTURE
    /// WORK of U-M3a-05 (the joint face needs the upstream's support-set
    /// bookkeeping across the bidirectional machinery); requesting it is a
    /// structured argument error at every entry point — never a silent
    /// simplification.
    JointRefit,
}

/// Connected-signature configuration of one fit: the signature indices
/// (0-based, into the dictionary's column order) forming the connected
/// group, plus the rejoin [`ConnectedStrategy`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConnectedSpec {
    /// 0-based dictionary indices of the connected signatures.
    pub components: Vec<usize>,
    /// The rejoin strategy (only [`ConnectedStrategy::FixAndRefit`] is
    /// implemented; see its docs for the declared approximation).
    pub strategy: ConnectedStrategy,
}

impl ConnectedSpec {
    /// Validate the component list (distinct, in-range) against a
    /// dictionary of `k` signatures.
    pub fn validate(&self, k: usize) -> Result<(), MsError> {
        for (pos, &c) in self.components.iter().enumerate() {
            if c >= k {
                return Err(MsError::new(
                    "argument",
                    format!(
                        "connected component index {c} is outside the dictionary (k = {k})"
                    ),
                )
                .with_i(pos as i64 + 1));
            }
        }
        let mut sorted = self.components.clone();
        sorted.sort_unstable();
        sorted.dedup();
        if sorted.len() != self.components.len() {
            return Err(MsError::new(
                "argument",
                "connected component indices must be distinct",
            ));
        }
        // Audited P1-1 note: consumers (fix_and_refit) normalize the spec
        // themselves — validate takes &self and cannot sort in place.
        Ok(())
    }
}

/// FixAndRefit rejoin for one sample: the connected components are pinned
/// at the initial full-NNLS solution `h_init` and the remaining components
/// are re-optimized by NNLS on the residual `v − S_fix·h_fix` (the
/// free-block minimizer of the grouped problem; with the connected block
/// frozen, grouped alternating minimization converges after this single
/// free-block solve). Returns the rejoined exposure vector (length k).
fn fix_and_refit(
    g: &[f64],
    b_j: &[f64],
    k: usize,
    h_current: &[f64],
    h_init: &[f64],
    components: &[usize],
) -> Result<Vec<f64>, MsError> {
    // Audited P1-1: normalize the spec locally (sorted + deduped) so the
    // binary_search precondition holds regardless of caller input order —
    // `connected = c(2, 1)` previously corrupted the FixAndRefit semantics.
    let mut components: Vec<usize> = components.to_vec();
    components.sort_unstable();
    components.dedup();
    let mut h = h_current.to_vec();
    for &c in &components {
        h[c] = h_init[c];
    }
    let is_fixed = |a: usize| components.binary_search(&a).is_ok();
    let free: Vec<usize> = (0..k).filter(|&a| !is_fixed(a)).collect();
    if free.is_empty() {
        return Ok(h); // degenerate all-connected dictionary: nothing to refit
    }
    // Residual right-hand side for the free block: b_f − G_fc·h_fix.
    let mut rhs = b_j.to_vec();
    for &a in &free {
        let mut acc = 0.0f64;
        for &c in &components {
            acc += g[a * k + c] * h[c];
        }
        rhs[a] -= acc;
    }
    let refit = nnls_on_subset(g, &rhs, k, &free)?;
    for &f in &free {
        h[f] = refit[f];
    }
    Ok(h)
}

/// [`fit`] with the U-M3a-05 whole-fit post-steps: an optional
/// [`ConnectedSpec`] (connected-signature rejoin) and the TMB `rescale`
/// flag (per-sample rescale back onto the original mutation totals via
/// [`rescale_to_totals`]).
///
/// Pipeline per sample: method exposures → (rejoin) → (rescale) →
/// share-zeroing decision → Fisher SE. `rescale` divides nothing: it only
/// multiplies by the per-sample factor, so zeros stay zero. The uniform
/// evidence columns are computed before the post-steps and never see them.
/// Passing `(None, false)` is bit-identical to [`fit`] (pinned by tests).
#[allow(clippy::too_many_arguments)]
pub fn fit_with(
    counts: &[f64],
    sigs: &[f64],
    m: usize,
    n: usize,
    k: usize,
    method: FitMethod,
    nb_size: f64,
    eps: f64,
    max_iter: usize,
    zero_threshold: f64,
    connected: Option<&ConnectedSpec>,
    rescale: bool,
) -> Result<FitOutput, MsError> {
    validate_inputs(counts, sigs, m, n, k, nb_size, eps, max_iter, zero_threshold)?;
    if let Some(spec) = connected {
        spec.validate(k)?;
        if spec.strategy == ConnectedStrategy::JointRefit {
            return Err(MsError::new(
                "argument",
                "ConnectedStrategy::JointRefit is declared future work (U-M3a-05 ships \
                 FixAndRefit only); no joint connected re-solve is implemented",
            ));
        }
    }
    // Per-sample mutation totals for the rescale (counts are validated
    // integral and non-negative, so the sums are exact-integer doubles).
    let totals: Vec<f64> = if rescale {
        (0..n)
            .map(|j| (0..m).map(|i| counts[i * n + j]).sum())
            .collect()
    } else {
        Vec::new()
    };

    let g = gram_from_sigs(sigs, m, k);
    let b = cross_from_sv(sigs, counts, m, k, n);

    let mut out = FitOutput {
        exposures: vec![0.0; k * n],
        support: vec![0; k * n],
        lrt_stat: vec![0.0; k * n],
        lrt_p: vec![0.0; k * n],
        se: vec![f64::NAN; k * n],
        converged: true,
    };

    for j in 0..n {
        let v: Vec<f64> = (0..m).map(|i| counts[i * n + j]).collect();
        let b_j: Vec<f64> = (0..k).map(|a| b[a * n + j]).collect();

        let (mut h_method, warm_x, mut mask, method_converged) = method_exposures(
            sigs, m, &g, &b_j, &v, k, method, nb_size, eps, max_iter, zero_threshold,
        )?;

        // --- uniform presence-LRT evidence (unchanged by the post-steps) --
        let (h_mle, mle_converged) = if method == FitMethod::Lrt {
            (h_method.clone(), method_converged)
        } else {
            let all_free = vec![true; k];
            nb_mle(sigs, m, k, &v, nb_size, &warm_x, &all_free, max_iter)?
        };
        if !method_converged || !mle_converged {
            out.converged = false;
        }

        let mu_full = recon(sigs, m, k, &h_mle);
        let ll_full = nb_ll(&v, &mu_full, nb_size)?;
        for a in 0..k {
            let mut h_without = h_mle.clone();
            h_without[a] = 0.0;
            let mut free = vec![true; k];
            free[a] = false;
            let (h_red, _) = nb_mle(sigs, m, k, &v, nb_size, &h_without, &free, max_iter)?;
            let ll_without = nb_ll(&v, &recon(sigs, m, k, &h_red), nb_size)?;
            out.lrt_stat[a * n + j] = lrt_stat(ll_without, ll_full);
            out.lrt_p[a * n + j] = p_chisq1_lrt(ll_without, ll_full);
        }

        // --- connected rejoin + TMB rescale, then the zeroing decision ---
        let post_steps = connected.is_some() || rescale;
        if post_steps {
            if let Some(spec) = connected {
                h_method = fix_and_refit(
                    &g,
                    &b_j,
                    k,
                    &h_method,
                    &warm_x,
                    &spec.components,
                )?;
            }
            if rescale {
                h_method = rescale_to_totals(&h_method, &[totals[j]], 1)?;
            }
            // Shares are per-sample scale invariant (the rescale cannot flip
            // a verdict) but the rejoin changes them, so the decision rule
            // is re-evaluated on the final exposures.
            mask = zeroing_mask_share(&h_method, zero_threshold)?;
        }

        for a in 0..k {
            let idx = a * n + j;
            if mask[a] {
                out.exposures[idx] = 0.0;
                out.support[idx] = 0;
            } else {
                out.exposures[idx] = h_method[a];
                out.support[idx] = 1;
            }
        }

        // --- Fisher SE on the post-zeroing (interior) support ----------
        let h_zeroed: Vec<f64> = (0..k).map(|a| out.exposures[a * n + j]).collect();
        let se_fit = fisher_se(sigs, m, &h_zeroed)?;
        for (pos, &a) in se_fit.interior.iter().enumerate() {
            out.se[a * n + j] = se_fit.se[pos];
        }
    }
    Ok(out)
}

/// Structured input validation of the two matrices (FFI contracts 3/4,
/// second layer): shapes, finiteness (`"na"`), non-negativity/integrality
/// (`"argument"`), with 1-based (row, column) payload in the natural
/// matrix coordinates of each argument (counts: channel × sample;
/// signatures: channel × signature). Shared by [`fit`], [`bootstrap`] and
/// [`presence_test`].
fn validate_matrices(
    counts: &[f64],
    sigs: &[f64],
    m: usize,
    n: usize,
    k: usize,
) -> Result<(), MsError> {
    if m == 0 || n == 0 || k == 0 {
        return Err(MsError::new(
            "argument",
            "fit needs at least one channel, one sample and one signature",
        )
        .with_i(m as i64)
        .with_j(k as i64));
    }
    if counts.len() != m * n {
        return Err(MsError::new(
            "argument",
            "counts storage must be m*n elements (row-major m x n)",
        )
        .with_i(counts.len() as i64)
        .with_j((m * n) as i64));
    }
    if sigs.len() != m * k {
        return Err(MsError::new(
            "argument",
            "signatures storage must be m*k elements (row-major m x k)",
        )
        .with_i(sigs.len() as i64)
        .with_j((m * k) as i64));
    }
    for i in 0..m {
        for j in 0..n {
            let c = counts[i * n + j];
            let at = |mut e: MsError| {
                e.i = Some(i as i64 + 1);
                e.j = Some(j as i64 + 1);
                e
            };
            if !c.is_finite() {
                return Err(at(MsError::new("na", "counts must be finite (no NaN/Inf)")));
            }
            if c < 0.0 {
                return Err(at(MsError::new("argument", "counts must be non-negative")));
            }
            if c != c.trunc() {
                return Err(at(MsError::new("argument", "counts must be integral")));
            }
        }
    }
    for i in 0..m {
        for a in 0..k {
            let s = sigs[i * k + a];
            let at = |mut e: MsError| {
                e.i = Some(i as i64 + 1);
                e.j = Some(a as i64 + 1);
                e
            };
            if !s.is_finite() {
                return Err(at(MsError::new(
                    "na",
                    "signatures must be finite (no NaN/Inf)",
                )));
            }
            if s < 0.0 {
                return Err(at(MsError::new(
                    "argument",
                    "signatures must be non-negative",
                )));
            }
        }
    }
    Ok(())
}

/// Structured input validation (FFI contracts 3/4, second layer): the
/// shared matrix checks plus the scalar domains of [`fit`].
#[allow(clippy::too_many_arguments)]
fn validate_inputs(
    counts: &[f64],
    sigs: &[f64],
    m: usize,
    n: usize,
    k: usize,
    nb_size: f64,
    eps: f64,
    max_iter: usize,
    zero_threshold: f64,
) -> Result<(), MsError> {
    validate_matrices(counts, sigs, m, n, k)?;
    if !nb_size.is_finite() {
        return Err(MsError::new("na", "nb_size must be finite (no NaN/Inf)"));
    }
    if nb_size <= 0.0 {
        return Err(MsError::new(
            "argument",
            "nb_size must be positive (mSigAct nbinom.size semantics)",
        ));
    }
    if !eps.is_finite() || eps < 0.0 {
        return Err(MsError::new(
            "argument",
            "eps (tol) must be finite and >= 0",
        ));
    }
    if max_iter == 0 {
        return Err(MsError::new(
            "argument",
            "max_iter must be >= 1 (bidirectional rounds / NB-MLE iterations cap)",
        ));
    }
    if !zero_threshold.is_finite() || !(0.0..=1.0).contains(&zero_threshold) {
        return Err(MsError::new(
            "argument",
            "zero_threshold must lie in [0, 1]",
        ));
    }
    Ok(())
}

/// Gram matrix `G = SᵀS` from the row-major m×k signatures (symmetric k×k).
fn gram_from_sigs(sigs: &[f64], m: usize, k: usize) -> Vec<f64> {
    let mut g = vec![0.0f64; k * k];
    for a in 0..k {
        for b in a..k {
            let acc: f64 = (0..m).map(|i| sigs[i * k + a] * sigs[i * k + b]).sum();
            g[a * k + b] = acc;
            g[b * k + a] = acc;
        }
    }
    g
}

/// Cross matrix `B = SᵀV`: column j is `b_j = Sᵀv_j` (row-major k×n).
fn cross_from_sv(sigs: &[f64], counts: &[f64], m: usize, k: usize, n: usize) -> Vec<f64> {
    let mut b = vec![0.0f64; k * n];
    for a in 0..k {
        for j in 0..n {
            let acc: f64 = (0..m).map(|i| sigs[i * k + a] * counts[i * n + j]).sum();
            b[a * n + j] = acc;
        }
    }
    b
}

/// Reconstruction `μ = S·h` for one sample (length m).
fn recon(sigs: &[f64], m: usize, k: usize, h: &[f64]) -> Vec<f64> {
    (0..m)
        .map(|i| (0..k).map(|a| sigs[i * k + a] * h[a]).sum())
        .collect()
}

/// Per-mutation multinomial log-likelihood of `counts` under the
/// reconstruction `recon_vec`: `p = recon / Σrecon`, `L = ll(p) / Σcounts`
/// via the engine primitive (the MuSiCal LTH scale; the pinned
/// Δ-equivalence in the `engine::likelihood` tests carries over because
/// the multinomial coefficient is constant in the probabilities). An
/// all-zero reconstruction scores every positive-count channel at the
/// `LL_EPS` sentinel — the honest "impossible" value, never −inf.
fn per_mutation_ll(counts: &[f64], recon_vec: &[f64]) -> Result<f64, MsError> {
    let total_recon: f64 = recon_vec.iter().sum();
    let probs: Vec<f64> = if total_recon > 0.0 {
        recon_vec.iter().map(|&r| r / total_recon).collect()
    } else {
        vec![0.0; recon_vec.len()]
    };
    multinomial_ll_per_mutation(counts, &probs)
}

/// Solve NNLS restricted to an active subset (ascending signature indices),
/// returning a full-length k vector with zeros off the subset.
fn nnls_on_subset(g: &[f64], b_j: &[f64], k: usize, active: &[usize]) -> Result<Vec<f64>, MsError> {
    let a = active.len();
    let mut h = vec![0.0f64; k];
    if a == 0 {
        return Ok(h);
    }
    let mut gs = vec![0.0f64; a * a];
    for (ii, &i) in active.iter().enumerate() {
        for (jj, &j) in active.iter().enumerate() {
            gs[ii * a + jj] = g[i * k + j];
        }
    }
    let rhs: Vec<f64> = active.iter().map(|&i| b_j[i]).collect();
    let sol = nnls_gram(&gs, &rhs, a, &NnlsOptions::default())?;
    for (s, &i) in active.iter().enumerate() {
        h[i] = sol.x[s];
    }
    Ok(h)
}

/// MuSiCal `nnls_likelihood_bidirectional` (research/02 §1.1): full NNLS
/// initial support, then alternating backward/forward ϵ steps on the
/// per-mutation multinomial scale. Backward removes the argmin-cost
/// signature (first index wins ties) while that cost is `< ϵ`; forward
/// adds the argmax-gain candidate (first index wins ties) while the gain
/// is `> ϵ`. Every accepted step re-solves NNLS on the surviving support,
/// so the returned exposures ARE the final refit. Returns
/// `(h, converged)` with `converged = false` iff the `max_iter` round cap
/// was hit before both steps declined (upstream anti-cycling cap).
#[allow(clippy::too_many_arguments)] // internal face mirrors the frozen FFI scalar set
fn bidirectional(
    sigs: &[f64],
    m: usize,
    g: &[f64],
    b_j: &[f64],
    counts: &[f64],
    k: usize,
    eps: f64,
    max_iter: usize,
) -> Result<(Vec<f64>, bool), MsError> {
    let init = nnls_gram(g, b_j, k, &NnlsOptions::default())?;
    let mut active: Vec<usize> = (0..k).filter(|&a| init.x[a] > 0.0).collect();
    // The full solution restricted to its own support IS the support
    // solution (off-support entries are exactly 0).
    let mut h = init.x;

    // Per-mutation LL of a full-length zero-padded exposure vector: the
    // reconstruction sees the active support only, so no separate
    // sub-matrix bookkeeping is needed for the likelihood.
    let ll_of = |h: &[f64]| per_mutation_ll(counts, &recon(sigs, m, k, h));

    let mut converged = true;
    let mut round = 0usize;
    loop {
        round += 1;
        if round > max_iter {
            converged = false;
            break;
        }
        let l_cur = ll_of(&h)?;

        // --- BACKWARD: cost of removing each active signature ----------
        let mut removal: Option<(usize, f64)> = None; // (position, delta)
        for pos in 0..active.len() {
            let sub: Vec<usize> = active
                .iter()
                .enumerate()
                .filter(|&(p, _)| p != pos)
                .map(|(_, &a)| a)
                .collect();
            let h_minus = nnls_on_subset(g, b_j, k, &sub)?;
            let l_minus = ll_of(&h_minus)?;
            let d = l_cur - l_minus;
            // Strict <: first-index tie-breaking (fixed order).
            if removal.map_or(true, |(_, best)| d < best) {
                removal = Some((pos, d));
            }
        }
        let mut changed = false;
        if let Some((pos, d)) = removal {
            if d < eps {
                let gone = active.remove(pos);
                h[gone] = 0.0;
                h = nnls_on_subset(g, b_j, k, &active)?;
                changed = true;
            }
        }

        // --- FORWARD: gain of adding each inactive candidate -----------
        // (evaluated against the current, post-removal support).
        let l_cur = ll_of(&h)?;
        let mut addition: Option<(usize, f64)> = None; // (candidate, gain)
        for cand in 0..k {
            if active.contains(&cand) {
                continue;
            }
            let mut sub = active.clone();
            sub.push(cand);
            sub.sort_unstable();
            let h_plus = nnls_on_subset(g, b_j, k, &sub)?;
            let l_plus = ll_of(&h_plus)?;
            let gain = l_plus - l_cur;
            // Strict >: first-index tie-breaking (fixed order).
            if addition.map_or(true, |(_, best)| gain > best) {
                addition = Some((cand, gain));
            }
        }
        if let Some((cand, gain)) = addition {
            if gain > eps {
                let at = active.partition_point(|&a| a < cand);
                active.insert(at, cand);
                h = nnls_on_subset(g, b_j, k, &active)?;
                changed = true;
            }
        }

        if !changed {
            break; // both steps declined: converged
        }
    }
    Ok((h, converged))
}

/// NB-MLE of the exposures for one sample: safeguarded Newton ascent
/// (projected, Armijo backtracking, steepest-ascent fallback direction) on
/// the (concave) NB log-likelihood `Σᵢ dnbinom(xᵢ; μᵢ = (Sh)ᵢ, size)`,
/// warm-started at `h0`. `free[a] = false` pins signature a at its `h0`
/// value (0 in the reduced presence refits). The curvature block is
/// `SᵀDS` with `D_ii = xᵢ/(eps+μᵢ)² − (xᵢ+size)/(size+μᵢ)² ≥ 0` — a
/// strict correction on top of the Poisson curvature (audited precision;
/// NB concavity in μ holds only for μ ≤ x + √(x² + x·size), the guarded
/// ascent keeps iterates in that region); a (near-)
/// singular block degrades the step to steepest ascent. Returns
/// `(h, converged)`; `converged` is false only when `max_iter` iterations
/// elapsed without meeting the KKT / relative-improvement stops.
///
/// Edge behaviour under the zero-pseudo-count policy (ARCHITECTURE §7.4):
/// a channel with `μᵢ = 0` and `xᵢ > 0` has the finite [`LL_EPS`] sentinel
/// slope; the line search then simply cannot find an acceptable step within
/// its cap and the point is returned unchanged — the honest
/// "impossible reconstruction" outcome, deterministic, never NaN/Inf.
#[allow(clippy::too_many_arguments)] // internal face mirrors the frozen FFI scalar set
fn nb_mle(
    sigs: &[f64],
    m: usize,
    k: usize,
    counts: &[f64],
    size: f64,
    h0: &[f64],
    free: &[bool],
    max_iter: usize,
) -> Result<(Vec<f64>, bool), MsError> {
    let free_idx: Vec<usize> = (0..k).filter(|&a| free[a]).collect();
    if free_idx.is_empty() {
        return Ok((h0.to_vec(), true));
    }
    let kf = free_idx.len();
    let mut h = h0.to_vec();
    let mut means = recon(sigs, m, k, &h);
    let mut ll = nb_ll(counts, &means, size)?;
    // Gradient-magnitude scale anchor, taken at the warm start (set on the
    // first pass through the loop below).
    let mut g0_max = -1.0f64;

    for _ in 0..max_iter {
        // Gradient wrt the free exposures:
        // d ll/d h_a = Σᵢ S_ia · (xᵢ/(eps+μᵢ) − (size+xᵢ)/(size+μᵢ)).
        let mut grad = vec![0.0f64; k];
        let mut gnorm2 = 0.0f64;
        let mut pg_max = 0.0f64;
        for &a in &free_idx {
            let mut acc = 0.0f64;
            for i in 0..m {
                let mu = means[i];
                acc += sigs[i * k + a]
                    * (counts[i] / (LL_EPS + mu) - (size + counts[i]) / (size + mu));
            }
            grad[a] = acc;
            gnorm2 += acc * acc;
            // Projected-gradient KKT residual (interior: |grad|; boundary:
            // ascent direction only).
            let pg = if h[a] > 0.0 { acc.abs() } else { acc.max(0.0) };
            pg_max = pg_max.max(pg);
        }
        if g0_max < 0.0 {
            g0_max = pg_max;
        }
        if pg_max <= PG_TOL * (1.0 + g0_max) {
            return Ok((h, true)); // KKT met at the projected optimum
        }
        if gnorm2 == 0.0 {
            return Ok((h, true)); // stationary (free) coordinates
        }

        // Curvature block SᵀDS on the free coordinates (D ≥ 0 under the
        // eps guards), factorized by the pivoted LDLᵀ with an ε-ridge; a
        // singular block degrades the step to steepest ascent.
        let mut hess = vec![0.0f64; kf * kf];
        for (ai, &a) in free_idx.iter().enumerate() {
            for (bi, &b) in free_idx.iter().enumerate().skip(ai) {
                let mut acc = 0.0f64;
                for i in 0..m {
                    let mu = means[i];
                    let d = counts[i] / ((LL_EPS + mu) * (LL_EPS + mu))
                        - counts[i] / ((size + mu) * (size + mu));
                    acc += sigs[i * k + a] * sigs[i * k + b] * d;
                }
                hess[ai * kf + bi] = acc;
                hess[bi * kf + ai] = acc;
            }
        }
        let g_free: Vec<f64> = free_idx.iter().map(|&a| grad[a]).collect();
        let newton_dir = msuiter_engine::linalg::gram_factor(&hess, kf, Some(1e-12))
            .and_then(|f| f.solve(&g_free));

        // Armijo backtracking over the Newton direction first, then the
        // gradient direction; steps are projected onto the free h >= 0 box.
        let mut accepted = false;
        let mut step_t = 0.0f64;
        let mut step_slope = 0.0f64;
        for dir_opt in [newton_dir.ok(), Some(g_free.clone())] {
            let Some(dir) = dir_opt else { continue };
            // Predicted first-order ascent gᵀd (> 0 for an ascent direction).
            let slope: f64 = free_idx.iter().zip(dir.iter()).map(|(&a, &d)| grad[a] * d).sum();
            if slope <= 0.0 || !slope.is_finite() {
                continue;
            }
            let mut t = 1.0f64;
            for _ in 0..LINE_SEARCH_MAX {
                let h_try: Vec<f64> = (0..k)
                    .map(|a| {
                        if free[a] {
                            let pos = free_idx.iter().position(|&f| f == a);
                            match pos {
                                Some(p) => (h[a] + t * dir[p]).max(0.0),
                                None => h[a],
                            }
                        } else {
                            h[a]
                        }
                    })
                    .collect();
                let means_try = recon(sigs, m, k, &h_try);
                let ll_try = nb_ll(counts, &means_try, size)?;
                if ll_try >= ll + ARMIJO_C * t * slope {
                    h = h_try;
                    means = means_try;
                    ll = ll_try;
                    accepted = true;
                    step_t = t;
                    step_slope = slope;
                    break;
                }
                t *= 0.5;
            }
            if accepted {
                break;
            }
        }
        if !accepted {
            // No ascent step exists at line-search resolution: the
            // boundary-inclusive optimum, up to float resolution.
            return Ok((h, true));
        }
        if step_t * step_slope <= NB_MLE_TOL * (1.0 + ll.abs()) {
            // The achieved first-order ascent is at the relative stop.
            return Ok((h, true));
        }
    }
    Ok((h, false))
}

/// Per-sample method exposures: the shared heart of [`fit`] and the
/// U-M3a-03 bootstrap driver. One NNLS warm start on the K-format pair,
/// the selected method's exposure solve, the share-zeroing decision, and
/// the raw NNLS solution (the warm start of every NB-MLE evidence fit)
/// alongside. Bit-identical to the original inline block of [`fit`] — a
/// pure extraction, pinned by the untouched fit tests.
///
/// Returns `(h_method, warm_x, mask, converged)`; `mask[a] == true` means
/// "zero the a-th exposure" (the [`zeroing_mask_share`] decision rule).
/// (The tuple face is internal to this module; a struct would freeze a
/// four-field shape used exactly twice.)
#[allow(clippy::too_many_arguments)] // internal face mirrors the frozen FFI scalar set
#[allow(clippy::type_complexity)] // (h_method, warm NNLS start, zeroing mask, converged)
fn method_exposures(
    sigs: &[f64],
    m: usize,
    g: &[f64],
    b_j: &[f64],
    v: &[f64],
    k: usize,
    method: FitMethod,
    nb_size: f64,
    eps: f64,
    max_iter: usize,
    zero_threshold: f64,
) -> Result<(Vec<f64>, Vec<f64>, Vec<bool>, bool), MsError> {
    let warm = nnls_gram(g, b_j, k, &NnlsOptions::default())?;
    let (h_method, converged) = match method {
        FitMethod::Nnls => (warm.x.clone(), true),
        FitMethod::LikelihoodBidirectional => bidirectional(sigs, m, g, b_j, v, k, eps, max_iter)?,
        FitMethod::Lrt => {
            let all_free = vec![true; k];
            nb_mle(sigs, m, k, v, nb_size, &warm.x, &all_free, max_iter)?
        }
    };
    let mask = zeroing_mask_share(&h_method, zero_threshold)?;
    Ok((h_method, warm.x, mask, converged))
}

// ======================================================================
// U-M3a-03: bootstrap CI + cohort presence test (BH)
// ======================================================================

/// Frozen MuSiCal LTH epsilon of every bootstrap replicate's
/// `likelihood_bidirectional` fit: the R-side `.ms_fit_defaults$eps`
/// (research/02 §1.1 upstream default). The `ms_fit_bootstrap_rust` FFI
/// face deliberately does not take `tol`/`max_iter` — the bootstrap reuses
/// the frozen `ms_fit` hyper-parameters (same Delta discipline as
/// `ms_fit`; a re-freeze moves both sides together).
pub const FIT_EPS: f64 = 0.001;

/// Frozen round/iteration cap shared with the R `.ms_fit_defaults$max_iter`
/// (the upstream MuSiCal anti-cycling cap): caps the bidirectional rounds,
/// the NB-MLE iterations of every bootstrap replicate fit, and the
/// NB-MLE refits of the presence test.
pub const FIT_MAX_ITER: usize = 1000;

/// Family-wise alpha of the BH `pass_bh` verdict of the presence test
/// (the conventional 5% genome-wide screening level; the raw and adjusted
/// p-values are returned so callers can re-threshold without a refit).
pub const BH_ALPHA: f64 = 0.05;

/// Percentile levels of the bootstrap CI (the classic percentile method,
/// research/02 §2 "重采样突变→重拟合→百分位 CI").
pub const BOOTSTRAP_CI_LEVELS: (f64, f64) = (0.025, 0.975);

/// Output of [`bootstrap`]. All grids are **row-major k×n** (signatures ×
/// samples); the FFI adapter transposes them into column-major R matrices.
///
/// Documented wire-format decision: the COMPRESSED CI summary is returned,
/// not the raw `n_boot × k × n` exposure cube — deterministic given the
/// seed, bounded memory, and the percentile arithmetic is pinned by tests.
#[derive(Debug, Clone, PartialEq)]
pub struct BootstrapOutput {
    /// Lower percentile-CI bound ([`BOOTSTRAP_CI_LEVELS`].0) per
    /// (signature, sample), over the post-zeroing boot exposures.
    pub ci_lower: Vec<f64>,
    /// Upper percentile-CI bound ([`BOOTSTRAP_CI_LEVELS`].1).
    pub ci_upper: Vec<f64>,
    /// Support stability: the frequency of `support = 1` (the share-rule
    /// zeroing keeping the exposure) across the `n_boot` replicates.
    pub support_stability: Vec<f64>,
    /// The number of bootstrap replicates actually run.
    pub n_boot: usize,
    /// AND over all boots of the per-fit method convergence.
    pub converged: bool,
}

/// Nonparametric (multinomial) percentile bootstrap of the whole fit
/// (U-M3a-03; research/02 §2 semantics: "per-sample 多项重采样").
///
/// For boot `b`, sample `j`: `counts_b[:, j] ~ Multinomial(N_j, v_j / N_j)`
/// drawn with [`msuiter_engine::resample::multinomial`] — exactly `N_j`
/// stream words, zero-weight channels receive exactly zero — from the
/// boot's own canonical stream `StreamId { replicate: b, rank: 0, fold: 0 }`
/// (the `resample.rs` batch layout; the n per-sample draws consume that one
/// stream sequentially in fixed sample order, so a boot is a pure function
/// of `(seed, b, counts)`). The resampled catalog is fitted per sample with
/// the selected method via [`method_exposures`] (post-zeroing exposures +
/// support). Parallelism exists ONLY between boots: they are the
/// independent units of contract 6, scheduled in chunks with main-thread
/// boundary interrupt polling (the `replicates.rs` skeleton, copied
/// locally — see [`run_boots_in_chunks`]); each boot is a single-threaded
/// sequential fit, so `threads ∈ {1, N}` give bit-identical output (A7).
///
/// The CI is the classic percentile interval at [`BOOTSTRAP_CI_LEVELS`]
/// (type-7 linear interpolation on the ascending-sorted boot values, the R
/// `quantile` default — pinned by tests); [`support_stability`][BootstrapOutput::support_stability]
/// is the kept-frequency across boots.
#[allow(clippy::too_many_arguments)]
pub fn bootstrap(
    counts: &[f64],
    sigs: &[f64],
    m: usize,
    n: usize,
    k: usize,
    method: FitMethod,
    n_boot: usize,
    nb_size: f64,
    zero_threshold: f64,
    seed: u64,
    n_threads: usize,
    cancelled: &AtomicBool,
    check_user_interrupt: &mut dyn FnMut(),
) -> Result<BootstrapOutput, MsError> {
    validate_inputs(
        counts,
        sigs,
        m,
        n,
        k,
        nb_size,
        FIT_EPS,
        FIT_MAX_ITER,
        zero_threshold,
    )?;
    if n_boot == 0 {
        return Err(MsError::new("argument", "n_boot must be >= 1"));
    }
    // Per-sample mutation totals N_j: the resample budget of sample j.
    // They must stay in the exactly-representable integer domain (each
    // draw allocates one of N_j words); a catalog beyond 2^53 mutations
    // per sample is outside the double-exact count domain anyway.
    let mut totals = vec![0.0f64; n];
    for j in 0..n {
        let mut t = 0.0f64;
        for i in 0..m {
            t += counts[i * n + j];
        }
        if !t.is_finite() || t > 9.007_199_254_740_992e15 {
            return Err(MsError::new(
                "argument",
                "a sample's total count exceeds the exactly-representable bootstrap domain",
            )
            .with_j(j as i64 + 1));
        }
        totals[j] = t;
    }
    // Per-sample weight vectors, gathered once (constant across boots):
    // the raw counts are passed as unnormalized weights — `multinomial`
    // normalizes by Σp, and raw counts ARE the empirical channel
    // distribution of the nonparametric bootstrap.
    let cols: Vec<Vec<f64>> = (0..n)
        .map(|j| (0..m).map(|i| counts[i * n + j]).collect())
        .collect();
    // The dictionary is constant across boots: one Gram matrix shared by
    // every boot's K-format solves.
    let g = gram_from_sigs(sigs, m, k);

    // One whole boot: resample every sample on the boot's own stream,
    // then fit the resampled catalog per sample (sequential inside).
    let unit = |b: usize| -> Result<(Vec<f64>, Vec<i32>, bool), MsError> {
        let mut rng =
            MsRng::from_stream(seed, StreamId { replicate: b as u64, rank: 0, fold: 0 });
        let mut boot = vec![0.0f64; m * n];
        for j in 0..n {
            let draws = resample::multinomial(&mut rng, &cols[j], totals[j] as u64);
            for i in 0..m {
                boot[i * n + j] = draws[i] as f64;
            }
        }
        let b_cross = cross_from_sv(sigs, &boot, m, k, n);
        let mut exposures = vec![0.0f64; k * n];
        let mut support = vec![0i32; k * n];
        let mut converged = true;
        for j in 0..n {
            let v: Vec<f64> = (0..m).map(|i| boot[i * n + j]).collect();
            let b_j: Vec<f64> = (0..k).map(|a| b_cross[a * n + j]).collect();
            let (h, _warm, mask, conv) = method_exposures(
                sigs,
                m,
                &g,
                &b_j,
                &v,
                k,
                method,
                nb_size,
                FIT_EPS,
                FIT_MAX_ITER,
                zero_threshold,
            )?;
            if !conv {
                converged = false;
            }
            for a in 0..k {
                let idx = a * n + j;
                if mask[a] {
                    exposures[idx] = 0.0;
                } else {
                    exposures[idx] = h[a];
                    support[idx] = 1;
                }
            }
        }
        Ok((exposures, support, converged))
    };

    let per_boot = run_boots_in_chunks(n_boot, n_threads, cancelled, check_user_interrupt, unit)?;

    // Fixed-order reduction (no order-sensitive float accumulation): the
    // percentile CI and support stability per (signature, sample) cell.
    let converged = per_boot.iter().all(|(_, _, c)| *c);
    let mut ci_lower = vec![0.0f64; k * n];
    let mut ci_upper = vec![0.0f64; k * n];
    let mut stability = vec![0.0f64; k * n];
    let mut col = vec![0.0f64; n_boot];
    for a in 0..k {
        for j in 0..n {
            for (b, row) in per_boot.iter().enumerate() {
                col[b] = row.0[a * n + j];
            }
            col.sort_by(f64::total_cmp);
            ci_lower[a * n + j] = percentile_sorted(&col, BOOTSTRAP_CI_LEVELS.0);
            ci_upper[a * n + j] = percentile_sorted(&col, BOOTSTRAP_CI_LEVELS.1);
            let kept: usize = per_boot.iter().map(|r| r.1[a * n + j] as usize).sum();
            stability[a * n + j] = kept as f64 / n_boot as f64;
        }
    }
    Ok(BootstrapOutput {
        ci_lower,
        ci_upper,
        support_stability: stability,
        n_boot,
        converged,
    })
}

/// Chunked parallel driver over independent boot units — the
/// `replicates.rs` scheduling skeleton applied to whole-fit boots (the
/// driver there is module-private and the crates' file discipline keeps
/// this unit self-contained; the protocol is identical): units are
/// scheduled in chunks (≈4 per worker, capped), the main thread polls the
/// interrupt hook between chunks, each chunk runs its units in parallel on
/// the per-call pool, workers see ONLY the `cancelled` flag, and chunks
/// are gathered in chunk-index order (pure index placement — no
/// order-sensitive floating-point reduction anywhere, so `threads ∈ {1, N}`
/// give bit-identical output).
fn run_boots_in_chunks<T, F>(
    units: usize,
    n_threads: usize,
    cancelled: &AtomicBool,
    check_user_interrupt: &mut dyn FnMut(),
    unit: F,
) -> Result<Vec<T>, MsError>
where
    T: Send,
    F: Fn(usize) -> Result<T, MsError> + Sync,
{
    let pool = super::probes::build_call_pool(n_threads)?;
    let target_chunks = n_threads.clamp(1, 16) * 4;
    let chunk_len = ((units + target_chunks - 1) / target_chunks).max(1);
    let n_chunks = (units + chunk_len - 1) / chunk_len;

    let mut per_chunk: Vec<(usize, Vec<T>)> = Vec::with_capacity(n_chunks);
    for c in 0..n_chunks {
        if cancelled.load(Ordering::Relaxed) {
            return Err(MsError::new(
                "interrupted",
                format!(
                    "call interrupted before chunk {}; no partial results are returned",
                    c + 1
                ),
            )
            .with_i((c + 1) as i64));
        }
        // Main-thread boundary poll (under R: R_CheckUserInterrupt).
        check_user_interrupt();
        let start = c * chunk_len;
        let end = (start + chunk_len).min(units);
        let chunk: Vec<T> = pool.install(|| {
            (start..end)
                .into_par_iter()
                .map(|b| {
                    if cancelled.load(Ordering::Relaxed) {
                        return Err(MsError::new(
                            "interrupted",
                            format!("worker observed cancellation at boot {}", b + 1),
                        )
                        .with_i((b + 1) as i64));
                    }
                    unit(b)
                })
                .collect::<Result<Vec<T>, MsError>>()
        })?;
        per_chunk.push((c, chunk));
    }

    per_chunk.sort_unstable_by_key(|(c, _)| *c);
    let mut out = Vec::with_capacity(units);
    for (_, mut vals) in per_chunk {
        out.append(&mut vals);
    }
    debug_assert_eq!(out.len(), units);
    Ok(out)
}

/// Type-7 linear-interpolation percentile of ascending-sorted data (the R
/// `quantile` default): position `p·(len−1)` on the 0-based order
/// statistics, linear interpolation between the neighbours. Exact for
/// `len == 1` (degenerate single-boot CI).
fn percentile_sorted(sorted: &[f64], p: f64) -> f64 {
    let len = sorted.len();
    debug_assert!(len > 0, "percentile of an empty slice");
    if len == 1 {
        return sorted[0];
    }
    let pos = p * (len - 1) as f64;
    let lo = pos.floor() as usize;
    let hi = (lo + 1).min(len - 1);
    let frac = pos - lo as f64;
    sorted[lo] + frac * (sorted[hi] - sorted[lo])
}

// ======================================================================
// The exact pooled null of the cohort presence test (P0 correction,
// independent audit 2026-10)
// ======================================================================
//
// Under H0 (the signature is absent in EVERY cohort sample) each
// per-sample entry-wise statistic D_j follows the Self–Liang (1987)
// boundary law `½·δ₀ + ½·χ²₁`, and independent catalogs make the D_j
// independent. The pooled statistic `D = Σ_j D_j` (the estimand —
// independent likelihoods add) therefore has the EXACT null law
//
//     D ~ Σ_{m=0}^{n} C(n,m)/2ⁿ · χ²_m ,
//
// a Binomial(n, ½) mixture of chi-squares: m counts how many of the n
// samples contributed their χ²₁ component, the remaining n−m contributed
// the δ₀ atom. The previously shipped reference — a single χ²₁ half-tail
// evaluated on the pooled D — is exact only for n = 1 and
// anti-conservative for every n ≥ 2 (the statistic grows with n while the
// reference does not): the audit's H0 simulation measured pass_bh rates
// 0.035 (n=1, calibrated) → 0.135 (n=2) → 0.545 (n=8) → 0.860 (n=16).
//
// This is a CORRECTION OF THE CHI-SQUARE REFERENCE, not a new statistical
// claim (D13 discipline): the pooled-cohort estimand, the per-sample
// `lrt_p` columns, BH and `pass_bh` logic are all unchanged; only the
// reference distribution the raw p reads its tail from is corrected.

/// Log-weight floor of the mixture sum: terms whose Binomial(n, ½) weight
/// falls below `e⁻⁷⁰⁰ ≈ 1e−304` are skipped (their χ² tail evaluation is
/// skipped with them). The skipped probability mass is bounded by the far
/// tail of the Binomial below the floor — it only activates for
/// `n ≥ 1010` (where `2⁻ⁿ` itself underflows past the floor) and stays
/// below `~n·1e−304·2`, i.e. `< 1e−12` in the p-value for every realistic
/// cohort size (pinned by the `pooled_null_weights_sum_to_one` test up to
/// n = 1500).
const MIXTURE_LN_WEIGHT_FLOOR: f64 = -700.0;

/// Exact binomial coefficient `C(n, m)` as `u128` (multiplicative formula;
/// each intermediate is itself a binomial coefficient, so the division is
/// exact). Used on the exact-weight branch, which requires `n ≤ 53` so
/// that `C(n, m) < 2⁵³` and the dyadic weight `C(n,m)/2ⁿ` is exactly
/// representable in `f64`.
fn binom_u128(n: usize, m: usize) -> u128 {
    debug_assert!(m <= n);
    let k = m.min(n - m);
    let mut acc: u128 = 1;
    for i in 1..=k {
        acc = acc * (n - k + i) as u128 / i as u128;
    }
    acc
}

/// Upper regularized incomplete gamma `Q(a, x) = Γ(a,x)/Γ(a)` for `a > 0`,
/// `x ≥ 0` — the Numerical-Recipes split already audited in
/// `engine::likelihood` (`erfc`): power series for `x < a + 1` (as
/// `1 − P(a,x)`), modified-Lentz continued fraction above. The engine's
/// series/continued-fraction helpers are private, so this module carries
/// the identical logic (same iteration form, same `1e−16` break) with a
/// raised 1200-iteration cap — the mixture evaluates `Q` at large shape
/// parameters `a = df/2` (df up to the cohort size), where convergence
/// near the seam can need more terms than the engine's erfc-domain 300.
/// NaN propagates; `x ≤ 0` is exactly 1.
fn gamma_q_reg(a: f64, x: f64) -> f64 {
    debug_assert!(a > 0.0);
    if x.is_nan() {
        return f64::NAN;
    }
    if x <= 0.0 {
        return 1.0;
    }
    if x < a + 1.0 {
        // Power series for P(a, x); Q = 1 − P.
        let mut ap = a;
        let mut sum = 1.0 / a;
        let mut del = sum;
        for _ in 0..1200 {
            ap += 1.0;
            del *= x / ap;
            sum += del;
            if del.abs() < sum.abs() * 1e-16 {
                break;
            }
        }
        let log_prefactor = -x + a * x.ln() - ln_gamma(a);
        1.0 - log_prefactor.exp() * sum
    } else {
        // Modified-Lentz continued fraction for Γ(a,x)/Γ(a).
        const FPMIN: f64 = 1e-300;
        let mut b = x + 1.0 - a;
        let mut c = 1.0 / FPMIN;
        let mut d = 1.0 / b;
        let mut h = d;
        for i in 1..1200 {
            let an = -(i as f64) * (i as f64 - a);
            b += 2.0;
            d = an * d + b;
            if d.abs() < FPMIN {
                d = FPMIN;
            }
            c = b + an / c;
            if c.abs() < FPMIN {
                c = FPMIN;
            }
            d = 1.0 / d;
            let del = d * c;
            h *= del;
            if (del - 1.0).abs() < 1e-16 {
                break;
            }
        }
        let log_prefactor = -x + a * x.ln() - ln_gamma(a);
        log_prefactor.exp() * h
    }
}

/// Chi-square upper tail `P(χ²_df > stat)` for integer `df` — the survival
/// function the pooled null is summed over.
///
/// * `df = 0` is the `δ₀` atom of the boundary law: the STRICT upper tail
///   `P(0 > stat) = [stat < 0]` — 0 for every admissible (clamped ≥ 0)
///   statistic. (R's `pchisq(x, 0, lower.tail = FALSE)` uses a different
///   convention at `x = 0`; the pure-R twin handles the atom explicitly.)
/// * `df = 1` routes to [`msuiter_engine::likelihood::p_chisq1_upper`]
///   (the audited erfc path) — this is what makes the n = 1 pooled p
///   bit-identical to the previous Self–Liang half-tail.
/// * `df ≥ 2` is `Q(df/2, stat/2)` via [`gamma_q_reg`] (the χ²₂ closed
///   form `e^(−stat/2)` and the classic quantile anchors pin the accuracy).
fn chisq_survival(stat: f64, df: u32) -> f64 {
    if df == 0 {
        return if stat < 0.0 { 1.0 } else { 0.0 };
    }
    if stat.is_nan() {
        return f64::NAN;
    }
    if stat <= 0.0 {
        // Strict upper tail of a continuous law at 0: exactly 1.
        return 1.0;
    }
    if stat.is_infinite() {
        return 0.0;
    }
    if df == 1 {
        return p_chisq1_upper(stat);
    }
    gamma_q_reg(df as f64 / 2.0, stat / 2.0)
}

/// Exact pooled-null p-value of the cohort presence test: the strict upper
/// tail of the Binomial(n, ½) mixture of χ²_m at the observed pooled
/// statistic `d`,
///
/// ```text
/// p = Σ_{m=0}^{n} C(n,m)/2ⁿ · P(χ²_m > d)
///   = Σ_{m=1}^{n} C(n,m)/2ⁿ · P(χ²_m > d)    (d ≥ 0; the m=0 atom is 0)
/// ```
///
/// Weights: for `n ≤ 53` the dyadic weights `C(n,m)/2ⁿ` are computed
/// EXACTLY (`C(n,m) < 2⁵³`, power-of-two denominator — this is what makes
/// n = 1 bit-identical to the previous `0.5·erfc` half-tail); for larger n
/// the weights run in log space (`ln Γ` recurrence) with the documented
/// [`MIXTURE_LN_WEIGHT_FLOOR`] skip. Summation order is ascending `m`
/// (deterministic). `d < 0` returns 1 (every component exceeds a negative
/// threshold); `d = +inf` returns 0; NaN propagates (and is rejected
/// downstream by the BH family validation).
pub(crate) fn pooled_presence_p(d: f64, n: usize) -> f64 {
    if d.is_nan() {
        return f64::NAN;
    }
    if d < 0.0 {
        return 1.0;
    }
    if d.is_infinite() {
        return 0.0;
    }
    // The m = 0 term is P(δ₀ > d) = 0 for every d ≥ 0 (see
    // [`chisq_survival`]), so the sum starts at m = 1.
    let mut p = 0.0;
    if n <= 53 {
        // Exact dyadic weights: C(n,m) < 2⁵³ and the denominator is a
        // power of two, so every weight is exactly representable.
        let denom = (1u128 << n) as f64;
        for m in 1..=n {
            p += binom_u128(n, m) as f64 / denom * chisq_survival(d, m as u32);
        }
    } else {
        // Log-space weights, ascending m, incremental recurrence
        // ln w_m = ln w_{m−1} + ln((n−m+1)/m); terms under the weight
        // floor are skipped (tail mass < 1e−12, see the constant's docs).
        let mut ln_w = -(n as f64) * std::f64::consts::LN_2; // m = 0
        for m in 1..=n {
            ln_w += ((n - m + 1) as f64 / m as f64).ln();
            if ln_w < MIXTURE_LN_WEIGHT_FLOOR {
                continue;
            }
            p += ln_w.exp() * chisq_survival(d, m as u32);
        }
    }
    // The exact sum is ≤ 1; cap a possible last-ulp rounding excursion.
    p.min(1.0)
}

/// Output of [`presence_test`]: per-signature pooled evidence with BH
/// multiplicity control (all vectors length k, signature order).
#[derive(Debug, Clone, PartialEq)]
pub struct PresenceOutput {
    /// Pooled LRT statistic `D_a` (length k).
    pub lrt_stat: Vec<f64>,
    /// Raw p-value from the exact pooled null — the strict upper tail of
    /// the Binomial(n, ½) mixture of χ²_m ([`pooled_presence_p`]; bit-level
    /// Self–Liang half-tail `½·erfc(√(D/2))` at n = 1) (length k; no BH).
    pub lrt_p_raw: Vec<f64>,
    /// BH-adjusted p-value over the k-signature family (length k).
    pub lrt_p_bh: Vec<f64>,
    /// `lrt_p_bh[a] <= BH_ALPHA` verdict (length k).
    pub pass_bh: Vec<bool>,
    /// AND over all samples of the full and reduced NB-MLE convergence.
    pub converged: bool,
}

/// Per-signature cohort presence test with BH multiplicity control
/// (U-M3a-03): the entry-wise presence LRT machinery of [`fit`] — which is
/// method-independent by construction (the uniform evidence columns) —
/// pooled across samples by SUMMING the per-sample statistics
/// `D_a = Σ_j D_{a,j}` (independent likelihoods add). The raw p-value is
/// the strict upper tail of the EXACT pooled null — under H0 each
/// per-sample statistic is `½·δ₀ + ½·χ²₁` (Self–Liang boundary law) and
/// independent catalogs make the sum a Binomial(n, ½) mixture of χ²_m
/// ([`pooled_presence_p`]; bit-identical to the `½·erfc(√(D/2))`
/// Self–Liang half-tail at n = 1) — then [`bh_adjust`] over the
/// k-signature family and the [`BH_ALPHA`] verdict.
///
/// NB-MLE refits use the frozen [`FIT_MAX_ITER`] cap (the `ms_fit`
/// default); `nb_size` is the mSigAct `nbinom.size`. Sequential and
/// trivially thread-invariant (A7) — the `ms_fit` bounded-batch decision;
/// `n_threads` lives only on the FFI surface for contract-6 uniformity.
pub fn presence_test(
    counts: &[f64],
    sigs: &[f64],
    m: usize,
    n: usize,
    k: usize,
    nb_size: f64,
) -> Result<PresenceOutput, MsError> {
    validate_matrices(counts, sigs, m, n, k)?;
    if !nb_size.is_finite() {
        return Err(MsError::new("na", "nb_size must be finite (no NaN/Inf)"));
    }
    if nb_size <= 0.0 {
        return Err(MsError::new(
            "argument",
            "nb_size must be positive (mSigAct nbinom.size semantics)",
        ));
    }
    let g = gram_from_sigs(sigs, m, k);
    let b = cross_from_sv(sigs, counts, m, k, n);
    let mut stat = vec![0.0f64; k];
    let mut converged = true;
    for j in 0..n {
        let v: Vec<f64> = (0..m).map(|i| counts[i * n + j]).collect();
        let b_j: Vec<f64> = (0..k).map(|a| b[a * n + j]).collect();
        // The uniform evidence machinery of `fit`: NB-MLE at the FULL NNLS
        // warm start, then the reduced refit without signature a.
        let warm = nnls_gram(&g, &b_j, k, &NnlsOptions::default())?;
        let all_free = vec![true; k];
        let (h_mle, mle_converged) =
            nb_mle(sigs, m, k, &v, nb_size, &warm.x, &all_free, FIT_MAX_ITER)?;
        if !mle_converged {
            converged = false;
        }
        let ll_full = nb_ll(&v, &recon(sigs, m, k, &h_mle), nb_size)?;
        for a in 0..k {
            let mut h_without = h_mle.clone();
            h_without[a] = 0.0;
            let mut free = vec![true; k];
            free[a] = false;
            let (h_red, red_converged) =
                nb_mle(sigs, m, k, &v, nb_size, &h_without, &free, FIT_MAX_ITER)?;
            if !red_converged {
                converged = false;
            }
            let ll_without = nb_ll(&v, &recon(sigs, m, k, &h_red), nb_size)?;
            // Ascending-j accumulation order per signature (fixed).
            stat[a] += lrt_stat(ll_without, ll_full);
        }
    }
    // Exact pooled-null tail per signature (Binomial(n, ½)-χ²_m mixture;
    // n = 1 degenerates bitwise to the Self–Liang half-tail).
    let lrt_p_raw: Vec<f64> = stat.iter().map(|&d| pooled_presence_p(d, n)).collect();
    let lrt_p_bh = bh_adjust(&lrt_p_raw)?;
    let pass_bh = lrt_p_bh.iter().map(|&q| q <= BH_ALPHA).collect();
    Ok(PresenceOutput {
        lrt_stat: stat,
        lrt_p_raw,
        lrt_p_bh,
        pass_bh,
        converged,
    })
}

/// Benjamini–Hochberg step-up adjusted p-values over one family of `m`
/// tests (research/02 §2, the mSigAct "χ²₁ + BH q" semantics): sort the
/// p-values ascending, scale the i-th smallest by `m / i`, then enforce
/// monotonicity with a cumulative minimum from the largest p down (the
/// "单调折返" fold-back), capped at 1. Ties keep first-index order (stable
/// sort); every adjusted value is ≥ its raw p and the adjustment is
/// monotone in the sorted order (both pinned by tests).
pub fn bh_adjust(p: &[f64]) -> Result<Vec<f64>, MsError> {
    for (i, &v) in p.iter().enumerate() {
        if !v.is_finite() {
            return Err(MsError::new(
                "na",
                "p-values must be finite (no NaN/Inf)",
            )
            .with_i(i as i64 + 1));
        }
        if !(0.0..=1.0).contains(&v) {
            return Err(MsError::new("argument", "p-values must lie in [0, 1]")
                .with_i(i as i64 + 1));
        }
    }
    let m = p.len();
    if m == 0 {
        return Err(MsError::new(
            "argument",
            "the BH family must contain at least one p-value",
        ));
    }
    let mut order: Vec<usize> = (0..m).collect();
    order.sort_by(|&x, &y| p[x].total_cmp(&p[y])); // stable: first-index ties
    let mut out = vec![1.0f64; m];
    let mut running = f64::INFINITY;
    for i in (0..m).rev() {
        let raw = p[order[i]] * (m as f64) / (i as f64 + 1.0);
        running = running.min(raw);
        out[order[i]] = running.min(1.0);
    }
    Ok(out)
}

// ======================================================================
// Tests (authored with the implementation, engine-convention goldens):
// per-sample kernel对拍, hand-derived bidirectional trajectory, LRT
// size/power smoke on the MsRng canonical streams, zeroing/SE boundary,
// determinism for all three methods, structured validation errors.
// ======================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use msuiter_engine::likelihood::{fisher_se as kernel_fisher_se, NB_SIZE_SBS96};
    use msuiter_engine::nnls::nnls_gram as kernel_nnls_gram;
    use msuiter_engine::rng::{MsRng, StreamId};

    /// Uniform f64 in [0, 1) from the in-house generator (test data only).
    fn uniform(rng: &mut MsRng) -> f64 {
        ((rng.next_u64() >> 11) as f64) * (1.0 / (1u64 << 53) as f64)
    }

    /// Knuth Poisson draw (product-of-uniforms; adequate for mu <= ~500),
    /// mirroring the engine likelihood tests' smoke machinery.
    fn poisson_draw(rng: &mut MsRng, mu: f64) -> u64 {
        let limit = (-mu).exp();
        let mut k = 0_u64;
        let mut p = 1.0_f64;
        loop {
            k += 1;
            p *= uniform(rng);
            if p <= limit {
                return k - 1;
            }
        }
    }

    fn cosine(a: &[f64], b: &[f64]) -> f64 {
        let dot: f64 = a.iter().zip(b.iter()).map(|(&x, &y)| x * y).sum();
        let na: f64 = a.iter().map(|x| x * x).sum::<f64>().sqrt();
        let nb: f64 = b.iter().map(|x| x * x).sum::<f64>().sqrt();
        dot / (na * nb)
    }

    /// The hand-derived 2x2 fixture: S = [[0.6, 0.5], [0.4, 0.5]] (columns
    /// sum 1; G = [[0.52, 0.5], [0.5, 0.5]], det = 0.01).
    const GOLDEN_SIGS: [f64; 4] = [0.6, 0.5, 0.4, 0.5];
    const GOLDEN_COUNTS: [f64; 2] = [58.0, 42.0];

    // ------------------------------------------------------------------
    // nnls: bit-exact对拍 against the per-sample kernel K-format call.
    // ------------------------------------------------------------------

    #[test]
    fn nnls_matches_per_sample_kernel_bit_exact() {
        let (m, n, k) = (8usize, 5usize, 3usize);
        let mut rng = MsRng::from_stream(2026, StreamId { replicate: 3, rank: 1, fold: 1 });
        let mut sigs = vec![0.0f64; m * k];
        for a in 0..k {
            let mut col: Vec<f64> = (0..m).map(|_| uniform(&mut rng)).collect();
            let s: f64 = col.iter().sum();
            for x in col.iter_mut() {
                *x /= s;
            }
            for i in 0..m {
                sigs[i * k + a] = col[i];
            }
        }
        let counts: Vec<f64> = (0..m * n)
            .map(|i| if i % 13 == 0 { 0.0 } else { (uniform(&mut rng) * 300.0).floor() })
            .collect();
        // zero_threshold = 0: only exact zeros are zeroed, so the output
        // must equal the kernel solution bit-for-bit (including zeros).
        let out = fit(
            &counts, &sigs, m, n, k, FitMethod::Nnls, NB_SIZE_SBS96, 0.001, 1000, 0.0,
        )
        .unwrap();
        let g = gram_from_sigs(&sigs, m, k);
        let b = cross_from_sv(&sigs, &counts, m, k, n);
        for j in 0..n {
            let b_j: Vec<f64> = (0..k).map(|a| b[a * n + j]).collect();
            let sol = kernel_nnls_gram(&g, &b_j, k, &NnlsOptions::default()).unwrap();
            for a in 0..k {
                assert_eq!(out.exposures[a * n + j], sol.x[a], "sample {j}, sig {a}");
                assert_eq!(out.support[a * n + j], i32::from(sol.x[a] > 0.0));
            }
        }
        assert!(out.converged);
    }

    // ------------------------------------------------------------------
    // Bidirectional goldens (hand-derived; ϵ-stepping semantics pinned).
    // ------------------------------------------------------------------

    #[test]
    fn bidirectional_golden_backward_removal() {
        // v = (58, 42): full NNLS h = (80, 20) (feasible 2-var solve).
        // Backward: Δ₁ = L_cur − L_(−1)
        //   = [58·ln(0.58/0.6) + 42·ln(0.42/0.4)]/100 = 8.2897e-4 < ϵ = 1e-3
        // → signature 2 removed; Δ₀ = 1.2855e-2 (never the argmin).
        // Forward: re-adding signature 2 gains exactly Δ₁ < ϵ → declined.
        // Final refit on {sig 1}: h₀ = b₀/G₀₀ = 51.6/0.52 = 99.230769…;
        // shares (1, 0) survive the 0.01 zeroing untouched.
        let out = fit(
            &GOLDEN_COUNTS,
            &GOLDEN_SIGS,
            2,
            1,
            2,
            FitMethod::LikelihoodBidirectional,
            NB_SIZE_SBS96,
            0.001,
            100,
            0.01,
        )
        .unwrap();
        assert!(out.converged);
        assert_eq!(out.support, vec![1, 0]);
        assert_eq!(out.exposures[1], 0.0);
        let h0_expected = 51.6 / 0.52;
        assert!(
            (out.exposures[0] - h0_expected).abs() <= 1e-6 * h0_expected,
            "h0 = {}",
            out.exposures[0]
        );
        // Presence evidence: the removed signature is the weaker one.
        assert!(out.lrt_stat[1] <= out.lrt_stat[0] + 1e-12);
        assert!((0.0..=0.5).contains(&out.lrt_p[0]));
        assert!((0.0..=0.5).contains(&out.lrt_p[1]));
    }

    #[test]
    fn bidirectional_epsilon_is_the_step_threshold() {
        // Same fixture with ϵ = 1e-5: Δ₁ = 8.2897e-4 > ϵ now declines the
        // removal — the full NNLS solution (80, 20) survives untouched.
        // This pins ϵ as the per-step threshold, not a decoration.
        let out = fit(
            &GOLDEN_COUNTS,
            &GOLDEN_SIGS,
            2,
            1,
            2,
            FitMethod::LikelihoodBidirectional,
            NB_SIZE_SBS96,
            1e-5,
            100,
            0.01,
        )
        .unwrap();
        assert!(out.converged);
        assert_eq!(out.support, vec![1, 1]);
        assert!((out.exposures[0] - 80.0).abs() < 1e-6, "h0 = {}", out.exposures[0]);
        assert!((out.exposures[1] - 20.0).abs() < 1e-6, "h1 = {}", out.exposures[1]);
    }

    #[test]
    fn bidirectional_golden_forward_declined() {
        // v = (50, 50) sits exactly on the flat twin: NNLS puts all mass on
        // signature 2 (h = (0, 100)); backward declines (removal would hit
        // the sentinel LL), forward declines (re-adding signature 1 gains
        // exactly 0: the NNLS solution on the full dictionary is unchanged).
        let out = fit(
            &[50.0, 50.0],
            &GOLDEN_SIGS,
            2,
            1,
            2,
            FitMethod::LikelihoodBidirectional,
            NB_SIZE_SBS96,
            0.001,
            100,
            0.01,
        )
        .unwrap();
        assert!(out.converged);
        assert_eq!(out.support, vec![0, 1]);
        assert_eq!(out.exposures[0], 0.0);
        assert!((out.exposures[1] - 100.0).abs() < 1e-6, "h1 = {}", out.exposures[1]);
    }

    #[test]
    fn bidirectional_round_cap_reports_unconverged() {
        // The golden removal needs two rounds (remove in round 1, both
        // steps decline in round 2). Capping at one round must report
        // converged = false while keeping the (already correct) refit.
        let out = fit(
            &GOLDEN_COUNTS,
            &GOLDEN_SIGS,
            2,
            1,
            2,
            FitMethod::LikelihoodBidirectional,
            NB_SIZE_SBS96,
            0.001,
            1,
            0.01,
        )
        .unwrap();
        assert!(!out.converged);
        assert_eq!(out.support, vec![1, 0]);
    }

    // ------------------------------------------------------------------
    // Zeroing decision + interior-support Fisher SE.
    // ------------------------------------------------------------------

    #[test]
    fn zeroing_zeroes_tiny_share_and_se_stays_interior() {
        // S = identity (columns e0, e1; each sums 1); v = (1000, 5):
        // NNLS h = (1000, 5); the share of signature 2 is 5/1005 < 0.01
        // → zeroed. Fisher SE covers the interior only: μ = (1000, 0),
        // H₀₀ = 1/1000 → SE(θ₁) = √1000; the boundary θ₂ gets NaN.
        let sigs = [1.0, 0.0, 0.0, 1.0];
        let out = fit(
            &[1000.0, 5.0],
            &sigs,
            2,
            1,
            2,
            FitMethod::Nnls,
            NB_SIZE_SBS96,
            0.001,
            100,
            0.01,
        )
        .unwrap();
        assert_eq!(out.support, vec![1, 0]);
        // The engine kernel's ε‖G‖ ridge biases the LS solution by O(ε·h)
        // (~1e-9 at h = 1000) — pin within that backward-error scale.
        assert!((out.exposures[0] - 1000.0).abs() <= 1e-8, "h0 = {}", out.exposures[0]);
        assert_eq!(out.exposures[1], 0.0);
        let reference = kernel_fisher_se(&sigs, 2, &[1000.0, 0.0]).unwrap();
        assert_eq!(reference.interior, vec![0]);
        assert!(
            (out.se[0] - reference.se[0]).abs() <= 1e-6 * reference.se[0],
            "SE must match the engine primitive: {} vs {}",
            out.se[0],
            reference.se[0]
        );
        assert!((out.se[0] - 1000.0f64.sqrt()).abs() < 1e-9);
        assert!(out.se[1].is_nan(), "boundary parameters get tests, not intervals");
    }

    #[test]
    fn zeroing_threshold_zero_keeps_everything_positive() {
        // With threshold 0 the share rule degenerates to "zero only exact
        // zeros": the 5-mutation component survives.
        let sigs = [1.0, 0.0, 0.0, 1.0];
        let out = fit(
            &[1000.0, 5.0],
            &sigs,
            2,
            1,
            2,
            FitMethod::Nnls,
            NB_SIZE_SBS96,
            0.001,
            100,
            0.0,
        )
        .unwrap();
        assert_eq!(out.support, vec![1, 1]);
        assert!((out.exposures[1] - 5.0).abs() <= 1e-9, "h1 = {}", out.exposures[1]);
    }

    // ------------------------------------------------------------------
    // Uniform presence-LRT evidence: bit-identical across methods.
    // ------------------------------------------------------------------

    #[test]
    fn presence_lrt_columns_are_method_independent() {
        let (m, n, k) = (6usize, 4usize, 3usize);
        let mut rng = MsRng::from_stream(7, StreamId { replicate: 9, rank: 9, fold: 9 });
        let mut sigs = vec![0.0f64; m * k];
        for a in 0..k {
            let mut col: Vec<f64> = (0..m).map(|_| uniform(&mut rng)).collect();
            let s: f64 = col.iter().sum();
            for x in col.iter_mut() {
                *x /= s;
            }
            for i in 0..m {
                sigs[i * k + a] = col[i];
            }
        }
        let counts: Vec<f64> = (0..m * n)
            .map(|i| if i % 7 == 0 { 0.0 } else { (uniform(&mut rng) * 120.0).floor() })
            .collect();
        let common = (NB_SIZE_SBS96, 0.001, 1000, 0.01);
        let a = fit(&counts, &sigs, m, n, k, FitMethod::Nnls, common.0, common.1, common.2, common.3).unwrap();
        let b = fit(
            &counts, &sigs, m, n, k, FitMethod::LikelihoodBidirectional, common.0, common.1,
            common.2, common.3,
        )
        .unwrap();
        let c = fit(&counts, &sigs, m, n, k, FitMethod::Lrt, common.0, common.1, common.2, common.3).unwrap();
        // Bit-level: these grids are finite, but keep the discipline uniform.
        let same = |x: &[f64], y: &[f64]| {
            x.len() == y.len() && x.iter().zip(y.iter()).all(|(p, q)| p.to_bits() == q.to_bits())
        };
        assert!(same(&a.lrt_stat, &b.lrt_stat));
        assert!(same(&a.lrt_stat, &c.lrt_stat));
        assert!(same(&a.lrt_p, &b.lrt_p));
        assert!(same(&a.lrt_p, &c.lrt_p));
        // And the lrt method's exposures ARE the evidence MLE: NNLS
        // exposures differ (LS vs NB-MLE), the LRT-based ones do not.
        assert_ne!(a.exposures, c.exposures);
    }

    // ------------------------------------------------------------------
    // Separable recovery through the fit face (asymmetric shape: the
    // transposition guard), all three methods.
    // ------------------------------------------------------------------

    #[test]
    fn separable_recovery_all_methods() {
        let (m, n, k) = (48usize, 6usize, 3usize);
        let mut rng = MsRng::from_stream(0x51D, StreamId { replicate: 2, rank: 2, fold: 2 });
        let mut w_true = vec![0.0f64; m * k];
        for a in 0..k {
            let mut col: Vec<f64> = (0..m)
                .map(|i| if i / 16 == a { 0.5 + uniform(&mut rng) } else { 0.0 })
                .collect();
            let s: f64 = col.iter().sum();
            for x in col.iter_mut() {
                *x /= s;
            }
            for i in 0..m {
                w_true[i * k + a] = col[i];
            }
        }
        let mut h_true = vec![0.0f64; k * n];
        for j in 0..n {
            let dom = j / 2; // three near-pure groups (of 2), one mixed
            for a in 0..k {
                h_true[a * n + j] = if dom == 3 || a == dom {
                    800.0 + 400.0 * uniform(&mut rng)
                } else {
                    8.0 * uniform(&mut rng)
                };
            }
        }
        let mut counts = vec![0.0f64; m * n];
        for i in 0..m {
            for a in 0..k {
                for j in 0..n {
                    counts[i * n + j] += w_true[i * k + a] * h_true[a * n + j];
                }
            }
        }
        let counts: Vec<f64> = counts.iter().map(|x| x.floor()).collect();

        for method in [FitMethod::Nnls, FitMethod::LikelihoodBidirectional, FitMethod::Lrt] {
            let out = fit(&counts, &w_true, m, n, k, method, NB_SIZE_SBS96, 0.001, 1000, 0.01)
                .unwrap();
            assert!(out.converged, "{:?} must converge", method);
            // Reconstruction cosine through the (unzeroed) fitted exposures
            // must clear 0.99 for every method on this separable truth.
            for j in 0..n {
                let h: Vec<f64> = (0..k).map(|a| out.exposures[a * n + j]).collect();
                let mu = recon(&w_true, m, k, &h);
                let v: Vec<f64> = (0..m).map(|i| counts[i * n + j]).collect();
                let cos = cosine(&mu, &v);
                assert!(cos >= 0.99, "{:?} sample {j}: cosine {cos}", method);
            }
            // NNLS exposure recovery on a near-pure sample.
            if method == FitMethod::Nnls {
                let h: Vec<f64> = (0..k).map(|a| out.exposures[a * n]).collect();
                let t: Vec<f64> = (0..k).map(|a| h_true[a * n]).collect();
                let cos = cosine(&h, &t);
                assert!(cos >= 0.99, "exposure recovery cosine {cos}");
            }
        }
    }

    // ------------------------------------------------------------------
    // LRT size/power smoke at the fit level (engine test conventions:
    // Poisson-limit NB, canonical MsRng streams, MC windows).
    // ------------------------------------------------------------------

    #[test]
    fn lrt_size_and_power_smoke() {
        // 2 channels, 2 signatures (row-major rows: (0.5, 0.9), (0.5, 0.1)):
        // background = flat column, specific = (0.9, 0.1). nb_size = 1e8
        // (the pinned Poisson limit). H0: means (500, 500) — the entry-wise
        // p of the specific signature must reject at ≈ α = 0.05 (Self–Liang
        // calibration; window ±3 MC standard errors of the engine
        // primitive's exact-rate anchor 0.052). H1: means (700, 300) —
        // power must dominate size decisively.
        let sigs = [0.5, 0.9, 0.5, 0.1];
        let n_reps = 1500_u64;
        let run = |means: [f64; 2], seed: u64| -> f64 {
            let mut rejects = 0_u64;
            for r in 0..n_reps {
                let mut rng = MsRng::from_stream(seed, StreamId { replicate: r, rank: 0, fold: 0 });
                let x0 = poisson_draw(&mut rng, means[0]) as f64;
                let x1 = poisson_draw(&mut rng, means[1]) as f64;
                let out = fit(&[x0, x1], &sigs, 2, 1, 2, FitMethod::Lrt, 1e8, 0.001, 1000, 0.01)
                    .unwrap();
                assert!(out.converged, "NB-MLE must converge in the smoke");
                if out.lrt_p[1] < 0.05 {
                    rejects += 1;
                }
            }
            rejects as f64 / n_reps as f64
        };
        let size = run([500.0, 500.0], 0xDADA);
        let power = run([700.0, 300.0], 0xBEAD);
        assert!((0.03..=0.08).contains(&size), "entry-wise size at α=0.05: {size}");
        assert!(power > 0.9, "power at the strong alternative: {power}");
        assert!(power > size, "power must dominate size: {power} vs {size}");
    }

    // ------------------------------------------------------------------
    // Edges: empty catalog, single signature.
    // ------------------------------------------------------------------

    #[test]
    fn empty_sample_scores_uniformly() {
        // All-zero catalog: NNLS gives the zero solution, the share rule
        // zeroes everything (0/0 totals), the presence LRT has D = 0 →
        // p = ½ exactly, and no interior SE exists.
        let out = fit(
            &[0.0, 0.0],
            &GOLDEN_SIGS,
            2,
            1,
            2,
            FitMethod::Nnls,
            NB_SIZE_SBS96,
            0.001,
            100,
            0.01,
        )
        .unwrap();
        assert_eq!(out.exposures, vec![0.0, 0.0]);
        assert_eq!(out.support, vec![0, 0]);
        assert_eq!(out.lrt_stat[0], 0.0);
        assert_eq!(out.lrt_stat[1], 0.0);
        assert_eq!(out.lrt_p[0], 0.5);
        assert_eq!(out.lrt_p[1], 0.5);
        assert!(out.se.iter().all(|s| s.is_nan()));
        assert!(out.converged);
    }

    #[test]
    fn single_signature_edge() {
        // k = 1: the reduced presence model is empty; the Poisson-limit
        // NB-MLE of θ is Σx/Σs = 100 exactly (channel means (30, 70)).
        let sigs = [0.3, 0.7];
        let out = fit(&[30.0, 70.0], &sigs, 2, 1, 1, FitMethod::Lrt, 1e8, 0.001, 1000, 0.01)
            .unwrap();
        assert!(out.converged);
        assert_eq!(out.support, vec![1]);
        assert!((out.exposures[0] - 100.0).abs() <= 1e-6 * 100.0, "h = {}", out.exposures[0]);
        // The full model fits the counts exactly → decisive presence.
        assert!(out.lrt_p[0] < 1e-3);
    }

    // ------------------------------------------------------------------
    // Determinism: bit-identical reruns, all three methods.
    // ------------------------------------------------------------------

    #[test]
    fn three_methods_deterministic_bit_identical() {
        let (m, n, k) = (7usize, 4usize, 3usize);
        let mut rng = MsRng::from_stream(11, StreamId { replicate: 1, rank: 2, fold: 3 });
        let mut sigs = vec![0.0f64; m * k];
        for a in 0..k {
            let mut col: Vec<f64> = (0..m).map(|_| uniform(&mut rng)).collect();
            let s: f64 = col.iter().sum();
            for x in col.iter_mut() {
                *x /= s;
            }
            for i in 0..m {
                sigs[i * k + a] = col[i];
            }
        }
        let counts: Vec<f64> = (0..m * n)
            .map(|i| if i % 11 == 0 { 0.0 } else { (uniform(&mut rng) * 90.0).floor() })
            .collect();
        for method in [FitMethod::Nnls, FitMethod::LikelihoodBidirectional, FitMethod::Lrt] {
            let a = fit(&counts, &sigs, m, n, k, method, NB_SIZE_SBS96, 0.001, 1000, 0.01).unwrap();
            let b = fit(&counts, &sigs, m, n, k, method, NB_SIZE_SBS96, 0.001, 1000, 0.01).unwrap();
            assert_bit_identical(&a, &b, method);
        }
    }

    /// Bit-level equality of two fit results: derived `PartialEq` cannot be
    /// used because the `se` grid legitimately carries NaN (boundary
    /// entries) and NaN != NaN.
    fn assert_bit_identical(a: &FitOutput, b: &FitOutput, method: FitMethod) {
        let same = |x: &[f64], y: &[f64]| {
            x.len() == y.len() && x.iter().zip(y.iter()).all(|(p, q)| p.to_bits() == q.to_bits())
        };
        assert!(
            same(&a.exposures, &b.exposures)
                && a.support == b.support
                && same(&a.lrt_stat, &b.lrt_stat)
                && same(&a.lrt_p, &b.lrt_p)
                && same(&a.se, &b.se)
                && a.converged == b.converged,
            "{method:?} must be bit-identical across reruns"
        );
    }

    // ------------------------------------------------------------------
    // Method parsing (contract 4) + structured validation errors.
    // ------------------------------------------------------------------

    #[test]
    fn method_names_parse_explicitly() {
        assert_eq!(FitMethod::parse("nnls").unwrap(), FitMethod::Nnls);
        assert_eq!(
            FitMethod::parse("likelihood_bidirectional").unwrap(),
            FitMethod::LikelihoodBidirectional
        );
        assert_eq!(FitMethod::parse("lrt").unwrap(), FitMethod::Lrt);
        assert_eq!(FitMethod::Nnls.as_str(), "nnls");
        assert_eq!(FitMethod::Lrt.as_str(), "lrt");
        let err = FitMethod::parse("em").unwrap_err();
        assert_eq!(err.topic(), "argument");
        let msg = err.to_string();
        assert!(msg.contains("\"nnls\"") && msg.contains("\"lrt\""), "{msg}");
    }

    #[test]
    fn validation_errors_are_structured() {
        let run = |counts: &[f64], sigs: &[f64], m: usize, n: usize, k: usize, nb_size: f64, eps: f64, max_iter: usize, zero: f64| {
            fit(counts, sigs, m, n, k, FitMethod::Nnls, nb_size, eps, max_iter, zero)
        };
        let e = run(&[f64::NAN, 42.0], &GOLDEN_SIGS, 2, 1, 2, 8.0, 0.001, 10, 0.01).unwrap_err();
        assert_eq!((e.topic(), e.i, e.j), ("na", Some(1), Some(1)));
        let e = run(&[58.0, -1.0], &GOLDEN_SIGS, 2, 1, 2, 8.0, 0.001, 10, 0.01).unwrap_err();
        assert_eq!((e.topic(), e.i, e.j), ("argument", Some(2), Some(1)));
        let e = run(&[58.5, 42.0], &GOLDEN_SIGS, 2, 1, 2, 8.0, 0.001, 10, 0.01).unwrap_err();
        assert_eq!((e.topic(), e.i, e.j), ("argument", Some(1), Some(1)));
        let e = run(&[58.0, 42.0], &[0.6, -0.5, 0.4, 0.5], 2, 1, 2, 8.0, 0.001, 10, 0.01).unwrap_err();
        assert_eq!((e.topic(), e.i, e.j), ("argument", Some(1), Some(2)));
        let e = run(&[58.0, 42.0], &[f64::NAN, 0.5, 0.4, 0.5], 2, 1, 2, 8.0, 0.001, 10, 0.01).unwrap_err();
        assert_eq!((e.topic(), e.i, e.j), ("na", Some(1), Some(1)));
        // Shape mismatches.
        let e = run(&[1.0, 2.0, 3.0], &GOLDEN_SIGS, 2, 1, 2, 8.0, 0.001, 10, 0.01).unwrap_err();
        assert_eq!(e.topic(), "argument");
        let e = run(&[58.0, 42.0], &[0.6, 0.5, 0.4], 2, 1, 2, 8.0, 0.001, 10, 0.01).unwrap_err();
        assert_eq!(e.topic(), "argument");
        // Degenerate dimensions.
        let e = run(&[], &[], 0, 1, 1, 8.0, 0.001, 10, 0.01).unwrap_err();
        assert_eq!(e.topic(), "argument");
        // Scalar domains.
        assert_eq!(run(&GOLDEN_COUNTS, &GOLDEN_SIGS, 2, 1, 2, 0.0, 0.001, 10, 0.01).unwrap_err().topic(), "argument");
        assert_eq!(run(&GOLDEN_COUNTS, &GOLDEN_SIGS, 2, 1, 2, f64::NAN, 0.001, 10, 0.01).unwrap_err().topic(), "na");
        assert_eq!(run(&GOLDEN_COUNTS, &GOLDEN_SIGS, 2, 1, 2, 8.0, -0.1, 10, 0.01).unwrap_err().topic(), "argument");
        assert_eq!(run(&GOLDEN_COUNTS, &GOLDEN_SIGS, 2, 1, 2, 8.0, 0.001, 0, 0.01).unwrap_err().topic(), "argument");
        assert_eq!(run(&GOLDEN_COUNTS, &GOLDEN_SIGS, 2, 1, 2, 8.0, 0.001, 10, 1.5).unwrap_err().topic(), "argument");
        assert_eq!(run(&GOLDEN_COUNTS, &GOLDEN_SIGS, 2, 1, 2, 8.0, 0.001, 10, -0.1).unwrap_err().topic(), "argument");
        assert_eq!(run(&GOLDEN_COUNTS, &GOLDEN_SIGS, 2, 1, 2, 8.0, 0.001, 10, f64::NAN).unwrap_err().topic(), "argument");
        // The lrt face runs the same validation gate.
        let e = fit(&[f64::NAN, 42.0], &GOLDEN_SIGS, 2, 1, 2, FitMethod::Lrt, 8.0, 0.001, 10, 0.01)
            .unwrap_err();
        assert_eq!(e.topic(), "na");
    }

    // ==================================================================
    // U-M3a-05: TMB rescale conservation + connected FixAndRefit
    // goldens + the frozen-legacy bit-identity of fit() vs fit_with().
    // ==================================================================

    #[test]
    fn rescale_conserves_per_sample_totals() {
        // Random grid and integer totals: after the rescale every sample's
        // exposure sum equals its original total (relative 1e-12), and the
        // transform is exactly a per-sample scalar multiplication.
        let (k, n) = (4usize, 7usize);
        let mut rng = MsRng::from_stream(0xA5, StreamId { replicate: 5, rank: 5, fold: 5 });
        let grid: Vec<f64> = (0..k * n).map(|_| uniform(&mut rng) * 250.0).collect();
        let totals: Vec<f64> = (0..n).map(|j| 100.0 * (j as f64 + 1.0)).collect();
        let out = rescale_to_totals(&grid, &totals, n).unwrap();
        for j in 0..n {
            let sum: f64 = (0..k).map(|a| out[a * n + j]).sum();
            assert_close(sum, totals[j], 1e-12, "rescale conservation");
            // Column j was scaled by exactly totals[j]/sum_j: spot-check the
            // factor on the largest entry (deterministic, no cancellation).
            let sum_before: f64 = (0..k).map(|a| grid[a * n + j]).sum();
            let factor = totals[j] / sum_before;
            let a_max = (0..k)
                .max_by(|&a, &b| grid[a * n + j].total_cmp(&grid[b * n + j]))
                .unwrap();
            assert_close(
                out[a_max * n + j],
                grid[a_max * n + j] * factor,
                1e-15,
                "per-sample scalar factor",
            );
        }
        // Zeroed entries stay zero (the rescale multiplies, never moves mass
        // onto a zero entry).
        let mut zeroed = grid.clone();
        zeroed[2 * n + 3] = 0.0;
        let out2 = rescale_to_totals(&zeroed, &totals, n).unwrap();
        assert_eq!(out2[2 * n + 3], 0.0);
    }

    #[test]
    fn rescale_edges_all_zero_and_zero_total() {
        // k = 2, n = 3, row-major columns: sample 0 = (3, 0), sample 1 =
        // (4, 0), sample 2 = (0, 5). Totals (10, 7, 0): the first two
        // columns are rescaled onto their totals, the zero-total column is
        // zeroed exactly (factor 0).
        let grid = [3.0, 4.0, 0.0, 0.0, 0.0, 5.0];
        let out = rescale_to_totals(&grid, &[10.0, 7.0, 0.0], 3).unwrap();
        assert_close(out[0], 10.0, 1e-12, "column 0 conserved");
        assert_eq!(out[3], 0.0);
        assert_close(out[1], 7.0, 1e-12, "column 1 conserved");
        assert_eq!(out[4], 0.0);
        // Zero-total column (0, 5): the factor 0 zeroes it exactly.
        assert_eq!(out[2], 0.0);
        assert_eq!(out[5], 0.0);
        // A genuinely all-zero column stays exactly zero even with a
        // positive total (nothing to conserve, nothing to redistribute).
        let zero_col = [3.0, 0.0, 0.0, 0.0, 0.0, 4.0];
        let out2 = rescale_to_totals(&zero_col, &[10.0, 5.0, 4.0], 3).unwrap();
        assert_eq!(out2[1], 0.0);
        assert_eq!(out2[3], 0.0);
        // Validation: negative / NaN totals are structured argument errors.
        assert_eq!(
            rescale_to_totals(&grid, &[-1.0, 7.0, 0.0], 3).unwrap_err().topic,
            "argument"
        );
        assert_eq!(
            rescale_to_totals(&grid, &[f64::NAN, 7.0, 0.0], 3).unwrap_err().topic,
            "argument"
        );
        assert_eq!(
            rescale_to_totals(&grid, &[1.0, 2.0], 3).unwrap_err().topic,
            "argument"
        );
    }

    #[test]
    fn connected_fix_and_refit_golden() {
        // The 2x2 golden: bidirectional removes signature 2 (h = (h0, 0),
        // h0 = 51.6/0.52). FixAndRefit with component 1 (0-based) rejoins
        // the clock signature at its INITIAL full-NNLS value h1 = 20 and
        // re-optimizes signature 1 against the residual:
        //   rhs0 = b0 − G01·20 = 51.6 − 0.5·20 = 41.6;  h0 = 41.6/0.52 = 80.
        // Expected final exposures (80, 20), both above the zeroing share.
        let spec = ConnectedSpec {
            components: vec![1],
            strategy: ConnectedStrategy::FixAndRefit,
        };
        let out = fit_with(
            &GOLDEN_COUNTS,
            &GOLDEN_SIGS,
            2,
            1,
            2,
            FitMethod::LikelihoodBidirectional,
            NB_SIZE_SBS96,
            0.001,
            100,
            0.01,
            Some(&spec),
            false,
        )
        .unwrap();
        assert!(out.converged);
        assert_eq!(out.support, vec![1, 1]);
        assert!((out.exposures[0] - 80.0).abs() <= 1e-8, "h0 = {}", out.exposures[0]);
        assert!((out.exposures[1] - 20.0).abs() <= 1e-8, "h1 = {}", out.exposures[1]);
        // The rescale onto the 100-mutation total is a no-op here (the
        // rejoined exposures already sum to 100) — the two post-steps
        // compose.
        let out_r = fit_with(
            &GOLDEN_COUNTS,
            &GOLDEN_SIGS,
            2,
            1,
            2,
            FitMethod::LikelihoodBidirectional,
            NB_SIZE_SBS96,
            0.001,
            100,
            0.01,
            Some(&spec),
            true,
        )
        .unwrap();
        assert_close(out_r.exposures[0], 80.0, 1e-9, "rejoin + rescale h0");
        assert_close(out_r.exposures[1], 20.0, 1e-9, "rejoin + rescale h1");
        // Uniform evidence columns are untouched by the post-steps: the
        // plain fit's grids must be bit-identical.
        let plain = fit(
            &GOLDEN_COUNTS, &GOLDEN_SIGS, 2, 1, 2,
            FitMethod::LikelihoodBidirectional, NB_SIZE_SBS96, 0.001, 100, 0.01,
        )
        .unwrap();
        assert_eq!(out.lrt_stat, plain.lrt_stat);
        assert_eq!(out.lrt_p, plain.lrt_p);
    }

    #[test]
    fn connected_nnls_is_a_fixed_point() {
        // With the nnls method the method solution IS the initial NNLS
        // solution: the rejoin resets the connected entries to values they
        // already hold and the residual refit reproduces the same free
        // block. Mathematically an exact fixed point; numerically the
        // subset re-solve may differ from the full solve in the last ulps,
        // so the guarantee is pinned at 1e-9 relative (the rejoin is a
        // different arithmetic route, not a different solution).
        let (m, n, k) = (8usize, 3usize, 3usize);
        let mut rng = MsRng::from_stream(2026, StreamId { replicate: 3, rank: 1, fold: 1 });
        let mut sigs = vec![0.0f64; m * k];
        for a in 0..k {
            let mut col: Vec<f64> = (0..m).map(|_| uniform(&mut rng)).collect();
            let s: f64 = col.iter().sum();
            for x in col.iter_mut() {
                *x /= s;
            }
            for i in 0..m {
                sigs[i * k + a] = col[i];
            }
        }
        let counts: Vec<f64> = (0..m * n)
            .map(|i| if i % 13 == 0 { 0.0 } else { (uniform(&mut rng) * 300.0).floor() })
            .collect();
        let spec = ConnectedSpec {
            components: vec![0, 2],
            strategy: ConnectedStrategy::FixAndRefit,
        };
        let plain = fit(&counts, &sigs, m, n, k, FitMethod::Nnls, NB_SIZE_SBS96, 0.001, 1000, 0.0)
            .unwrap();
        let rejoined = fit_with(
            &counts, &sigs, m, n, k, FitMethod::Nnls, NB_SIZE_SBS96, 0.001, 1000, 0.0,
            Some(&spec), false,
        )
        .unwrap();
        for (p, r) in plain.exposures.iter().zip(rejoined.exposures.iter()) {
            assert_close(*r, *p, 1e-9, "nnls rejoin fixed point");
        }
        assert_eq!(plain.support, rejoined.support);
    }

    #[test]
    fn fit_legacy_face_is_bit_identical_to_fit_with_none_false() {
        // The frozen contract: fit(...) == fit_with(..., None, false) at the
        // bit level, for all three methods (the bootstrap driver shares the
        // guarantee through method_exposures, untouched here).
        let (m, n, k) = (7usize, 4usize, 3usize);
        let mut rng = MsRng::from_stream(11, StreamId { replicate: 1, rank: 2, fold: 3 });
        let mut sigs = vec![0.0f64; m * k];
        for a in 0..k {
            let mut col: Vec<f64> = (0..m).map(|_| uniform(&mut rng)).collect();
            let s: f64 = col.iter().sum();
            for x in col.iter_mut() {
                *x /= s;
            }
            for i in 0..m {
                sigs[i * k + a] = col[i];
            }
        }
        let counts: Vec<f64> = (0..m * n)
            .map(|i| if i % 11 == 0 { 0.0 } else { (uniform(&mut rng) * 90.0).floor() })
            .collect();
        let same = |x: &[f64], y: &[f64]| {
            x.len() == y.len() && x.iter().zip(y.iter()).all(|(p, q)| p.to_bits() == q.to_bits())
        };
        for method in [FitMethod::Nnls, FitMethod::LikelihoodBidirectional, FitMethod::Lrt] {
            let a = fit(&counts, &sigs, m, n, k, method, NB_SIZE_SBS96, 0.001, 1000, 0.01).unwrap();
            let b = fit_with(
                &counts, &sigs, m, n, k, method, NB_SIZE_SBS96, 0.001, 1000, 0.01, None, false,
            )
            .unwrap();
            assert!(same(&a.exposures, &b.exposures) && a.support == b.support);
            assert!(same(&a.se, &b.se) && same(&a.lrt_stat, &b.lrt_stat));
        }
        // rescale = true with no zeroing changes the exposures only by the
        // per-sample factor: the column sums equal the sample totals.
        let rescaled = fit_with(
            &counts, &sigs, m, n, k, FitMethod::Nnls, NB_SIZE_SBS96, 0.001, 1000, 0.0,
            None, true,
        )
        .unwrap();
        for j in 0..n {
            let total: f64 = (0..m).map(|i| counts[i * n + j]).sum();
            let sum: f64 = (0..k).map(|a| rescaled.exposures[a * n + j]).sum();
            assert_close(sum, total, 1e-12, "end-to-end rescale conservation");
        }
    }

    #[test]
    fn connected_validation_errors() {
        // JointRefit is declared future work: a structured argument error,
        // never a silent fallback.
        let joint = ConnectedSpec {
            components: vec![0],
            strategy: ConnectedStrategy::JointRefit,
        };
        let e = fit_with(
            &GOLDEN_COUNTS, &GOLDEN_SIGS, 2, 1, 2,
            FitMethod::Nnls, NB_SIZE_SBS96, 0.001, 10, 0.01,
            Some(&joint), false,
        )
        .unwrap_err();
        assert_eq!(e.topic, "argument");
        assert!(e.to_string().contains("future work"), "{}", e);
        // Out-of-range and duplicate components.
        let e = fit_with(
            &GOLDEN_COUNTS, &GOLDEN_SIGS, 2, 1, 2,
            FitMethod::Nnls, NB_SIZE_SBS96, 0.001, 10, 0.01,
            Some(&ConnectedSpec {
                components: vec![2],
                strategy: ConnectedStrategy::FixAndRefit,
            }),
            false,
        )
        .unwrap_err();
        assert_eq!(e.topic, "argument");
        assert!(e.to_string().contains("outside the dictionary"), "{}", e);
        let e = fit_with(
            &GOLDEN_COUNTS, &GOLDEN_SIGS, 2, 1, 2,
            FitMethod::Nnls, NB_SIZE_SBS96, 0.001, 10, 0.01,
            Some(&ConnectedSpec {
                components: vec![1, 1],
                strategy: ConnectedStrategy::FixAndRefit,
            }),
            false,
        )
        .unwrap_err();
        assert_eq!(e.topic, "argument");
        assert!(e.to_string().contains("distinct"), "{}", e);
    }

    // ==================================================================
    // U-M3a-03: bootstrap determinism/threads/layout/CI + BH goldens +
    // presence size/power smoke + validation/interrupt protocol.
    // ==================================================================

    fn no_poll() {}

    /// Bootstrap fixture: separable 12-channel × 4-sample, 2-signature
    /// truth with anchor-channel blocks (the asymmetric m ≠ n layout
    /// guard) and interior truth exposures well away from the zeroing
    /// boundary. Returns `(counts, sigs, h_true, m, n, k)` with `h_true`
    /// row-major k×n.
    fn boot_fixture() -> (Vec<f64>, Vec<f64>, [f64; 8], usize, usize, usize) {
        let (m, n, k) = (12usize, 4usize, 2usize);
        let mut rng = MsRng::from_stream(0xB005, StreamId { replicate: 5, rank: 5, fold: 5 });
        let mut sigs = vec![0.0f64; m * k];
        for a in 0..k {
            let mut col: Vec<f64> = (0..m)
                .map(|i| if i / 6 == a { 0.5 + uniform(&mut rng) } else { 0.0 })
                .collect();
            let s: f64 = col.iter().sum();
            for x in col.iter_mut() {
                *x /= s;
            }
            for i in 0..m {
                sigs[i * k + a] = col[i];
            }
        }
        // Interior, separated truth exposures (row-major k×n).
        let h_true = [700.0, 550.0, 400.0, 250.0, 100.0, 250.0, 400.0, 550.0];
        let mut counts = vec![0.0f64; m * n];
        for i in 0..m {
            for a in 0..k {
                for j in 0..n {
                    counts[i * n + j] += sigs[i * k + a] * h_true[a * n + j];
                }
            }
        }
        let counts: Vec<f64> = counts.iter().map(|x| x.floor()).collect();
        (counts, sigs, h_true, m, n, k)
    }

    fn same_boot_bits(a: &BootstrapOutput, b: &BootstrapOutput) -> bool {
        let g = |x: &[f64], y: &[f64]| {
            x.len() == y.len() && x.iter().zip(y.iter()).all(|(p, q)| p.to_bits() == q.to_bits())
        };
        g(&a.ci_lower, &b.ci_lower)
            && g(&a.ci_upper, &b.ci_upper)
            && g(&a.support_stability, &b.support_stability)
            && a.n_boot == b.n_boot
    }

    #[test]
    fn bootstrap_is_deterministic_and_thread_invariant() {
        let (counts, sigs, _h, m, n, k) = boot_fixture();
        let run = |seed: u64, threads: usize| {
            let cancelled = AtomicBool::new(false);
            bootstrap(
                &counts, &sigs, m, n, k, FitMethod::Nnls, 17, NB_SIZE_SBS96, 0.0, seed, threads,
                &cancelled, &mut no_poll,
            )
            .unwrap()
        };
        let a = run(11, 1);
        let b = run(11, 1);
        let c = run(11, 4);
        assert!(same_boot_bits(&a, &b), "same seed must be bit-identical");
        assert!(same_boot_bits(&a, &c), "threads in {{1, 4}} must be bit-identical");
        // A different seed changes at least one CI bound (resampling live).
        let d = run(12, 1);
        assert!(!same_boot_bits(&a, &d));
        // Sanity: ordered bounds, stability on the unit interval.
        for i in 0..k * n {
            assert!(a.ci_lower[i] <= a.ci_upper[i]);
            assert!((0.0..=1.0).contains(&a.support_stability[i]));
        }
    }

    #[test]
    fn bootstrap_stream_layout_matches_the_canonical_resample_stream() {
        // n_boot = 1 must equal a hand-driven resample + a plain fit: the
        // boot's single canonical stream StreamId { replicate: 0, rank: 0,
        // fold: 0 } is consumed sequentially, one multinomial draw per
        // sample in fixed sample order (the resample.rs composition
        // contract: "composing several resamples on one stream is
        // transparent"). The stream layout (boot index on the replicate
        // axis) is pinned here.
        let (counts, sigs, _h, m, n, k) = boot_fixture();
        let cancelled = AtomicBool::new(false);
        let out = bootstrap(
            &counts, &sigs, m, n, k, FitMethod::Nnls, 1, NB_SIZE_SBS96, 0.0, 42, 1,
            &cancelled, &mut no_poll,
        )
        .unwrap();
        let mut rng = MsRng::from_stream(42, StreamId { replicate: 0, rank: 0, fold: 0 });
        let mut boot = vec![0.0f64; m * n];
        for j in 0..n {
            let col: Vec<f64> = (0..m).map(|i| counts[i * n + j]).collect();
            let total: f64 = col.iter().sum();
            let draws = resample::multinomial(&mut rng, &col, total as u64);
            for i in 0..m {
                boot[i * n + j] = draws[i] as f64;
            }
        }
        let pt = fit(&boot, &sigs, m, n, k, FitMethod::Nnls, NB_SIZE_SBS96, 0.001, 1000, 0.0)
            .unwrap();
        // Bit-identical: the boot unit runs the exact same op sequence.
        assert_eq!(out.ci_lower, pt.exposures);
        assert_eq!(out.ci_upper, pt.exposures);
        assert_eq!(out.support_stability.len(), k * n);
    }

    #[test]
    fn bootstrap_resample_is_per_sample_multinomial() {
        // All mass on channel 0: every boot resample is the same counts
        // vector (zero-weight channels get exactly zero draws), so the
        // percentile CI degenerates to the point solution and the support
        // stability is exactly the point support.
        let sigs = [1.0, 0.0, 0.0, 1.0];
        let counts = [100.0, 0.0];
        let cancelled = AtomicBool::new(false);
        let out = bootstrap(
            &counts, &sigs, 2, 1, 2, FitMethod::Nnls, 9, NB_SIZE_SBS96, 0.01, 7, 2,
            &cancelled, &mut no_poll,
        )
        .unwrap();
        assert_eq!(out.n_boot, 9);
        assert!(out.converged);
        assert!((out.ci_lower[0] - 100.0).abs() <= 1e-8, "h0 = {}", out.ci_lower[0]);
        assert!((out.ci_upper[0] - 100.0).abs() <= 1e-8, "h0 = {}", out.ci_upper[0]);
        assert_eq!(out.ci_lower[1], 0.0);
        assert_eq!(out.ci_upper[1], 0.0);
        assert_eq!(out.support_stability, vec![1.0, 0.0]);
    }

    #[test]
    fn bootstrap_reuses_all_three_methods() {
        let (counts, sigs, _h, m, n, k) = boot_fixture();
        for method in [FitMethod::LikelihoodBidirectional, FitMethod::Lrt] {
            let cancelled = AtomicBool::new(false);
            let out = bootstrap(
                &counts, &sigs, m, n, k, method, 5, NB_SIZE_SBS96, 0.01, 9, 2,
                &cancelled, &mut no_poll,
            )
            .unwrap();
            assert!(out.converged, "{method:?} boots must converge");
            for i in 0..k * n {
                assert!(out.ci_lower[i] <= out.ci_upper[i]);
                assert!((0.0..=1.0).contains(&out.support_stability[i]));
            }
        }
    }

    #[test]
    fn bootstrap_percentile_ci_covers_truth() {
        // True model: 2 well-conditioned signatures over 6 channels, 2
        // samples with interior exposures, ~1200 mutations per sample.
        // 100 experiments: counts ~ Multinomial per sample drawn from the
        // truth; the 40-boot percentile CI must cover the true exposure
        // in ≈95% of experiments. Pooled over the 4 cells (SE of the
        // coverage estimate ≈ sqrt(0.95·0.05/400) ≈ 0.011), the window
        // below leaves room for estimator bias while still failing any
        // systematic miscalibration (a 50%-coverage bug cannot pass).
        let (m, n, k) = (6usize, 2usize, 2usize);
        let mut rng = MsRng::from_stream(0xC0DE, StreamId { replicate: 1, rank: 2, fold: 3 });
        let mut sigs = vec![0.0f64; m * k];
        for a in 0..k {
            let mut col: Vec<f64> = (0..m)
                .map(|i| if i / 3 == a { 0.5 + uniform(&mut rng) } else { 0.0 })
                .collect();
            let s: f64 = col.iter().sum();
            for x in col.iter_mut() {
                *x /= s;
            }
            for i in 0..m {
                sigs[i * k + a] = col[i];
            }
        }
        let h_true = [700.0, 150.0, 250.0, 650.0]; // row-major k×n, interior
        let (n_boot, experiments) = (40usize, 100usize);
        let (mut covered, mut total) = (0usize, 0usize);
        for e in 0..experiments {
            let mut counts = vec![0.0f64; m * n];
            for j in 0..n {
                let expected: Vec<f64> = (0..m)
                    .map(|i| (0..k).map(|a| sigs[i * k + a] * h_true[a * n + j]).sum())
                    .collect();
                // The resample budget is the truth's own per-sample total
                // (signature columns sum to 1, so Σrecon = Σ_a h_true[a,j]).
                let budget: u64 = (h_true[j] + h_true[n + j]) as u64;
                let draws = resample::multinomial_from_stream(
                    0xE0F,
                    StreamId { replicate: e as u64, rank: j as u64, fold: 0 },
                    &expected,
                    budget,
                )
                .unwrap();
                for i in 0..m {
                    counts[i * n + j] = draws[i] as f64;
                }
            }
            let cancelled = AtomicBool::new(false);
            let out = bootstrap(
                &counts, &sigs, m, n, k, FitMethod::Nnls, n_boot, NB_SIZE_SBS96, 0.0, 77, 2,
                &cancelled, &mut no_poll,
            )
            .unwrap();
            for (idx, &truth) in h_true.iter().enumerate() {
                total += 1;
                if out.ci_lower[idx] <= truth && truth <= out.ci_upper[idx] {
                    covered += 1;
                }
            }
        }
        let cov = covered as f64 / total as f64;
        assert!((0.88..=0.995).contains(&cov), "pooled coverage {cov} over {total} cells");
    }

    #[test]
    fn bootstrap_interrupt_protocol_mirrors_replicates() {
        let (counts, sigs, _h, m, n, k) = boot_fixture();
        // Pre-cancelled flag fails the whole call without partial results.
        let cancelled = AtomicBool::new(true);
        let err = bootstrap(
            &counts, &sigs, m, n, k, FitMethod::Nnls, 8, NB_SIZE_SBS96, 0.0, 3, 2,
            &cancelled, &mut no_poll,
        )
        .unwrap_err();
        assert_eq!(err.topic, "interrupted");
        assert_eq!(err.i, Some(1));
        // Mid-run trip at a chunk boundary: the next chunk refuses.
        let cancelled = AtomicBool::new(false);
        let mut chunks = 0usize;
        let err = bootstrap(
            &counts, &sigs, m, n, k, FitMethod::Nnls, 8, NB_SIZE_SBS96, 0.0, 3, 1,
            &cancelled,
            &mut || {
                chunks += 1;
                if chunks == 1 {
                    cancelled.store(true, Ordering::Relaxed);
                }
            },
        )
        .unwrap_err();
        assert_eq!(chunks, 1);
        assert_eq!(err.topic, "interrupted");
        assert!(err.to_string().contains("worker observed"));
        // Boundary polls: 8 boots, 1 thread → target 4 chunks → 4 polls.
        let cancelled = AtomicBool::new(false);
        let mut polls = 0usize;
        bootstrap(
            &counts, &sigs, m, n, k, FitMethod::Nnls, 8, NB_SIZE_SBS96, 0.0, 3, 1,
            &cancelled, &mut || polls += 1,
        )
        .unwrap();
        assert_eq!(polls, 4);
    }

    #[test]
    fn bootstrap_and_presence_validation_errors() {
        let (counts, sigs, _h, m, n, k) = boot_fixture();
        let cancelled = AtomicBool::new(false);
        let mk_boot = |n_boot: usize, nb: f64, c: &[f64]| {
            bootstrap(
                c, &sigs, m, n, k, FitMethod::Nnls, n_boot, nb, 0.0, 1, 1, &cancelled,
                &mut no_poll,
            )
        };
        assert_eq!(mk_boot(0, NB_SIZE_SBS96, &counts).unwrap_err().topic, "argument");
        assert_eq!(mk_boot(5, 0.0, &counts).unwrap_err().topic, "argument");
        let mut bad = counts.clone();
        bad[3] = 1.5; // non-integral count
        assert_eq!(mk_boot(5, NB_SIZE_SBS96, &bad).unwrap_err().topic, "argument");
        // Presence face: the same matrix gate + the nb_size domain.
        assert_eq!(
            presence_test(&[f64::NAN, 1.0], &GOLDEN_SIGS, 2, 1, 2, 8.0)
                .unwrap_err()
                .topic,
            "na"
        );
        assert_eq!(
            presence_test(&GOLDEN_COUNTS, &GOLDEN_SIGS, 2, 1, 2, 0.0)
                .unwrap_err()
                .topic,
            "argument"
        );
        assert_eq!(
            presence_test(&GOLDEN_COUNTS, &GOLDEN_SIGS, 2, 1, 2, f64::NAN)
                .unwrap_err()
                .topic,
            "na"
        );
        assert_eq!(
            presence_test(&GOLDEN_COUNTS, &GOLDEN_SIGS, 2, 1, 2, -1.0)
                .unwrap_err()
                .topic,
            "argument"
        );
    }

    #[test]
    fn bh_golden_fold_back() {
        // Hand-derived: p = [0.01, 0.04, 0.03, 0.005], m = 4 → sorted
        // m/i scaling = [0.02, 0.02, 0.04, 0.04]; the fold-back keeps them
        // monotone; mapped back to the original order:
        // [0.02, 0.04, 0.04, 0.02].
        assert_eq!(bh_adjust(&[0.01, 0.04, 0.03, 0.005]).unwrap(), vec![0.02, 0.04, 0.04, 0.02]);
        // Cap at 1: the m/i scaling of the smaller p exceeds 1 and folds
        // back to the larger p's 0.6.
        assert_eq!(bh_adjust(&[0.5, 0.6]).unwrap(), vec![0.6, 0.6]);
        // Single test: BH is the identity.
        assert_eq!(bh_adjust(&[0.3]).unwrap(), vec![0.3]);
        // Properties on a deterministic p grid: adjusted ≥ raw, monotone
        // in the sorted order.
        let p: Vec<f64> = (0..12).map(|i| (i * 7919 % 97) as f64 / 97.0).collect();
        let adj = bh_adjust(&p).unwrap();
        for (r, a) in p.iter().zip(adj.iter()) {
            assert!(a >= r, "adjusted {a} < raw {r}");
        }
        let mut order: Vec<usize> = (0..12).collect();
        order.sort_by(|&x, &y| p[x].total_cmp(&p[y]));
        for w in order.windows(2) {
            assert!(adj[w[0]] <= adj[w[1]], "fold-back monotonicity broken");
        }
        // Validation errors (contract 5).
        assert_eq!(bh_adjust(&[0.5, f64::NAN]).unwrap_err().topic, "na");
        assert_eq!(bh_adjust(&[0.5, -0.1]).unwrap_err().topic, "argument");
        assert_eq!(bh_adjust(&[1.5]).unwrap_err().topic, "argument");
        assert_eq!(bh_adjust(&[]).unwrap_err().topic, "argument");
    }

    #[test]
    fn presence_single_sample_matches_fit_lrt_columns() {
        // n = 1: the pooled statistic IS the entry-wise fit statistic, and
        // the raw p is the fit's lrt_p — bit-identical (same machinery).
        let (m, n, k) = (6usize, 1usize, 3usize);
        let mut rng = MsRng::from_stream(21, StreamId { replicate: 3, rank: 1, fold: 4 });
        let mut sigs = vec![0.0f64; m * k];
        for a in 0..k {
            let mut col: Vec<f64> = (0..m).map(|_| uniform(&mut rng)).collect();
            let s: f64 = col.iter().sum();
            for x in col.iter_mut() {
                *x /= s;
            }
            for i in 0..m {
                sigs[i * k + a] = col[i];
            }
        }
        let counts: Vec<f64> = (0..m)
            .map(|i| if i % 5 == 0 { 0.0 } else { (uniform(&mut rng) * 200.0).floor() })
            .collect();
        let pt = presence_test(&counts, &sigs, m, n, k, 8.0).unwrap();
        let fl = fit(&counts, &sigs, m, n, k, FitMethod::Nnls, 8.0, 0.001, 1000, 0.01).unwrap();
        assert!(pt.converged);
        for a in 0..k {
            assert_eq!(pt.lrt_stat[a], fl.lrt_stat[a * n], "sig {a} stat");
            assert_eq!(pt.lrt_p_raw[a], fl.lrt_p[a * n], "sig {a} raw p");
        }
        // BH ≥ raw everywhere; the verdict matches BH_ALPHA.
        for (r, q) in pt.lrt_p_raw.iter().zip(pt.lrt_p_bh.iter()) {
            assert!(q >= r);
        }
        for (q, ok) in pt.lrt_p_bh.iter().zip(pt.pass_bh.iter()) {
            assert_eq!(*ok, *q <= BH_ALPHA);
        }
    }

    #[test]
    fn presence_size_and_power_smoke() {
        // Engine-test convention: Poisson-limit NB (size = 1e8), sigs
        // [0.5, 0.9; 0.5, 0.1]. H0 means (500, 500) — signature 1 absent —
        // must reject at ≈ α = 0.05 through the BH verdict (window around
        // the engine primitive's exact-rate anchor 0.052); H1 (700, 300)
        // must give decisive power. Single-sample catalogs keep the
        // Self–Liang boundary calibration exact.
        let sigs = [0.5, 0.9, 0.5, 0.1];
        let n_reps = 1000_u64;
        let run = |means: [f64; 2], seed: u64| -> f64 {
            let mut rejects = 0_u64;
            for r in 0..n_reps {
                let mut rng = MsRng::from_stream(seed, StreamId { replicate: r, rank: 0, fold: 0 });
                let x0 = poisson_draw(&mut rng, means[0]) as f64;
                let x1 = poisson_draw(&mut rng, means[1]) as f64;
                let pt = presence_test(&[x0, x1], &sigs, 2, 1, 2, 1e8).unwrap();
                assert!(pt.converged, "NB-MLE must converge in the smoke");
                if pt.pass_bh[1] {
                    rejects += 1;
                }
            }
            rejects as f64 / n_reps as f64
        };
        let size = run([500.0, 500.0], 0xDADA);
        let power = run([700.0, 300.0], 0xBEAD);
        assert!((0.02..=0.10).contains(&size), "presence size at α=0.05: {size}");
        assert!(power > 0.8, "presence power at the strong alternative: {power}");
        assert!(power > size, "power must dominate size: {power} vs {size}");
    }





    // ==================================================================
    // Exact pooled null (P0 correction): survival-function anchors,
    // mixture analytic anchors, weight-sum identity, H0 calibration
    // matrix, power vs cohort size.
    // ==================================================================

    /// Relative-tolerance assert (D11 numeric-protocol convention).
    fn assert_close(actual: f64, expected: f64, rel: f64, what: &str) {
        let scale = expected.abs().max(1e-300);
        assert!(
            (actual - expected).abs() <= rel * scale,
            "{what}: actual {actual}, expected {expected}"
        );
    }

    #[test]
    fn pooled_null_chisq_survival_anchors() {
        // Known χ² quantiles (scipy.stats.chi2.isf, f64): P(χ²_df > stat) = p.
        // df = 1 takes the audited erfc path, df ≥ 2 the gamma_q_reg path.
        let cases: &[(u32, f64, f64)] = &[
            (1, 3.841_458_820_694_126_3, 0.05),
            (2, 4.605_170_185_988_092, 0.10),
            (3, 7.814_727_903_251_182, 0.05),
            (4, 9.487_729_036_781_158, 0.05),
            (8, 13.361_566_136_511_726, 0.10),
            (16, 26.296_227_604_864_246, 0.05),
            // Arbitrary interior points (not quantile-derived).
            (3, 2.0, 0.572_406_704_470_879_8),
            (8, 20.0, 0.010_336_050_675_925_718),
            (16, 20.0, 0.220_220_646_601_698_94),
        ];
        for &(df, stat, p) in cases {
            assert_close(chisq_survival(stat, df), p, 1e-10, "χ² survival anchor");
        }
        // The χ²₂ closed form e^(−stat/2) pins the gamma path to 1e-12.
        for stat in [0.5_f64, 4.605_170_185_988_092, 12.0] {
            assert_close(
                chisq_survival(stat, 2),
                (-stat / 2.0).exp(),
                1e-12,
                "χ²₂ closed form",
            );
        }
        // Edges: the δ₀ atom (df = 0) uses the STRICT tail [stat < 0]; a
        // nonpositive statistic gives exactly 1 for df ≥ 1; NaN propagates;
        // +inf decays to 0.
        assert_eq!(chisq_survival(0.0, 0), 0.0);
        assert_eq!(chisq_survival(-1.0, 0), 1.0);
        assert_eq!(chisq_survival(0.0, 4), 1.0);
        assert!(chisq_survival(f64::NAN, 4).is_nan());
        assert_eq!(chisq_survival(f64::INFINITY, 4), 0.0);
    }

    #[test]
    fn pooled_null_mixture_analytic_anchors() {
        // n = 1: bit-identical to the previous Self–Liang half-tail (the
        // exact dyadic weight ½ times the audited erfc path).
        for d in [0.0_f64, 0.5, 2.705_543_454_095_404, 12.0, 40.0] {
            assert_eq!(
                pooled_presence_p(d, 1),
                0.5 * p_chisq1_upper(d),
                "n=1 bitwise anchor at d={d}"
            );
        }
        // n = 2 (hand-derivable): P = ½·P(χ²₁ > D) + ¼·P(χ²₂ > D)
        // (the δ₀ atom is 0 for D ≥ 0; P(χ²₂ > D) = e^(−D/2)).
        // Goldens from 30-digit mpmath.
        let cases: &[(f64, f64)] = &[
            (0.5, 0.434_450_256_861_327_95),
            (3.841_458_820_694_124, 0.061_625_016_121_521_11),
            (12.0, 0.000_885_690_796_736_214_4),
        ];
        for &(d, p) in cases {
            assert_close(pooled_presence_p(d, 2), p, 1e-12, "n=2 mixture golden");
        }
        // D = 0: p = 1 − 2⁻ⁿ exactly (every χ²_m term is 1, the atom is 0);
        // the dyadic weight sum is exact.
        assert_eq!(pooled_presence_p(0.0, 1), 0.5);
        assert_eq!(pooled_presence_p(0.0, 2), 0.75);
        assert_eq!(pooled_presence_p(0.0, 16), 1.0 - 0.5_f64.powi(16));
        // Direction and range: p is nonincreasing in D and stays in [0, 1].
        let mut prev = 1.0;
        for i in 0..40 {
            let p = pooled_presence_p(i as f64 * 0.5, 8);
            assert!((0.0..=1.0).contains(&p));
            assert!(p <= prev, "p must be nonincreasing in D");
            prev = p;
        }
        // Degenerate thresholds: negative → 1, +inf → 0, NaN propagates.
        assert_eq!(pooled_presence_p(-1.0, 4), 1.0);
        assert_eq!(pooled_presence_p(f64::INFINITY, 4), 0.0);
        assert!(pooled_presence_p(f64::NAN, 4).is_nan());
    }

    #[test]
    fn pooled_null_weights_sum_to_one() {
        // At D = 0 every χ²_m term is exactly 1, so the returned value IS
        // the computed weight sum 1 − 2⁻ⁿ — an end-to-end check of both
        // weight branches (exact dyadic n ≤ 53 / log-space above) and of
        // the documented skip floor (activated past n ≈ 1010; the skipped
        // mass stays below the pinned 1e−12).
        for &n in &[2usize, 3, 16, 53, 54, 100, 1009, 1500] {
            let p = pooled_presence_p(0.0, n);
            let expected = 1.0 - 0.5_f64.powi(n as i32);
            assert!(
                (p - expected).abs() < 1e-12,
                "weight sum at n={n}: {p} vs {expected}"
            );
        }
    }

    #[test]
    fn presence_h0_calibration_matrix() {
        // P0 acceptance matrix: under H0 (signature 1 absent, signature 0
        // present; Poisson-limit NB) the BH verdict on the absent
        // signature must stay at level for EVERY cohort size. The old
        // χ²₁-half-tail reference measured 0.058 / 0.117 / 0.261 / 0.557 /
        // 0.920 on these exact streams (the independent audit's
        // 0.135/0.545/0.860 phenomenon) — the exact Binomial(n, ½)-mixture
        // reference restores calibration. Fixed seeds, deterministic.
        let sigs = [0.5, 0.9, 0.5, 0.1];
        let n_reps = 1000_u64;
        for &n in &[1usize, 2, 4, 8, 16] {
            let mut rejects = 0_u64;
            for r in 0..n_reps {
                let mut rng =
                    MsRng::from_stream(0xCA1B, StreamId { replicate: r, rank: 0, fold: 0 });
                // Channel-major m×n layout: channel 0 for all samples, then
                // channel 1 (the fit layout contract counts[i*n + j]).
                let mut counts = Vec::with_capacity(2 * n);
                for _j in 0..n {
                    counts.push(poisson_draw(&mut rng, 500.0) as f64);
                }
                for _j in 0..n {
                    counts.push(poisson_draw(&mut rng, 500.0) as f64);
                }
                let pt = presence_test(&counts, &sigs, 2, n, 2, 1e8).unwrap();
                assert!(pt.converged, "NB-MLE must converge in the smoke");
                if pt.pass_bh[1] {
                    rejects += 1;
                }
            }
            let rate = rejects as f64 / n_reps as f64;
            // α = 0.05 with a ±4·SE window at 1000 reps (4SE ≈ 0.028).
            assert!(
                (0.02..=0.08).contains(&rate),
                "H0 pass_bh rate at n={n}: {rate} ({rejects}/{n_reps})"
            );
        }
    }

    #[test]
    fn presence_power_grows_with_cohort_size() {
        // The pooling estimand's payoff: a weak true effect (h₁ = 50 on
        // 1000 mutations, means (520, 480)) must be detected MORE often as
        // the cohort grows — the exact mixture reference keeps the level
        // fixed while the evidence accumulates. (Under the old χ²₁
        // reference this comparison is meaningless: the level itself
        // explodes with n — see the calibration matrix.)
        let sigs = [0.5, 0.9, 0.5, 0.1];
        let n_reps = 1000_u64;
        let power = |n: usize| -> f64 {
            let mut rejects = 0_u64;
            for r in 0..n_reps {
                let mut rng =
                    MsRng::from_stream(0xF0CE, StreamId { replicate: r, rank: 0, fold: 0 });
                let mut counts = Vec::with_capacity(2 * n);
                for _j in 0..n {
                    counts.push(poisson_draw(&mut rng, 520.0) as f64);
                }
                for _j in 0..n {
                    counts.push(poisson_draw(&mut rng, 480.0) as f64);
                }
                let pt = presence_test(&counts, &sigs, 2, n, 2, 1e8).unwrap();
                if pt.pass_bh[1] {
                    rejects += 1;
                }
            }
            rejects as f64 / n_reps as f64
        };
        let p1 = power(1);
        let p8 = power(8);
        assert!((0.15..=0.60).contains(&p1), "weak-effect power at n=1: {p1}");
        assert!(p8 > 0.60, "weak-effect power at n=8: {p8}");
        assert!(p8 > p1, "power must grow with cohort size: {p8} vs {p1}");
    }
}
