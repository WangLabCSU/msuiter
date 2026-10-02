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

use msuiter_engine::error::MsError;
use msuiter_engine::likelihood::{
    fisher_se, lrt_stat, multinomial_ll_per_mutation, nb_ll, p_chisq1_lrt, zeroing_mask_share,
    LL_EPS,
};
use msuiter_engine::nnls::{nnls_gram, NnlsOptions};

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
    validate_inputs(counts, sigs, m, n, k, nb_size, eps, max_iter, zero_threshold)?;

    // K-format pair, computed once: G = SᵀS (k×k, symmetric) and
    // B = SᵀV (row-major k×n; column j is b_j = Sᵀv_j).
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

        // Full NNLS solution: the nnls exposures themselves and the warm
        // start of every NB-MLE below (one shared deterministic start).
        let warm = nnls_gram(&g, &b_j, k, &NnlsOptions::default())?;

        // --- method exposures (h_method) -------------------------------
        let (h_method, method_converged) = match method {
            FitMethod::Nnls => (warm.x.clone(), true),
            FitMethod::LikelihoodBidirectional => {
                bidirectional(sigs, m, &g, &b_j, &v, k, eps, max_iter)?
            }
            FitMethod::Lrt => {
                let all_free = vec![true; k];
                nb_mle(sigs, m, k, &v, nb_size, &warm.x, &all_free, max_iter)?
            }
        };

        // --- uniform presence-LRT evidence at the NB-MLE exposures -----
        // Always warm-started from the FULL NNLS solution, so the columns
        // are bit-identical across methods for the same input (see the
        // module docs, "uniform evidence columns").
        let (h_mle, mle_converged) = if method == FitMethod::Lrt {
            (h_method.clone(), method_converged)
        } else {
            let all_free = vec![true; k];
            nb_mle(sigs, m, k, &v, nb_size, &warm.x, &all_free, max_iter)?
        };
        if !method_converged || !mle_converged {
            out.converged = false;
        }

        let mu_full = recon(sigs, m, k, &h_mle);
        let ll_full = nb_ll(&v, &mu_full, nb_size)?;
        for a in 0..k {
            // Refit without signature a (mSigAct "去目标签名拟合"): warm
            // start from the full solution minus a; the objective is
            // concave, so the warm start reaches the same optimum.
            let mut h_without = h_mle.clone();
            h_without[a] = 0.0;
            let mut free = vec![true; k];
            free[a] = false;
            let (h_red, _) = nb_mle(sigs, m, k, &v, nb_size, &h_without, &free, max_iter)?;
            let ll_without = nb_ll(&v, &recon(sigs, m, k, &h_red), nb_size)?;
            out.lrt_stat[a * n + j] = lrt_stat(ll_without, ll_full);
            out.lrt_p[a * n + j] = p_chisq1_lrt(ll_without, ll_full);
        }

        // --- zeroing decision on the RETURNED exposures ----------------
        let mask = zeroing_mask_share(&h_method, zero_threshold)?;
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

/// Structured input validation (FFI contracts 3/4, second layer): shape,
/// finiteness (`"na"`), non-negativity/integrality (`"argument"`), with
/// 1-based (row, column) payload in the natural matrix coordinates of each
/// argument (counts: channel × sample; signatures: channel × signature).
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
/// `SᵀDS` with `D_ii = xᵢ/(eps+μᵢ)² − xᵢ/(size+μᵢ)² ≥ 0`; a (near-)
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

}
