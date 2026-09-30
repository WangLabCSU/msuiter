//! One-dimensional two-component Gaussian mixture and the SigProfiler
//! hypermutant normalization cutoff (U-M1c-02; `docs/ARCHITECTURE.md` §2
//! `engine/stats.rs`, §5 consensus-extraction pipeline).
//!
//! # Upstream semantics (pinned to source, D11/D13)
//!
//! SigProfilerExtractor handles hypermutated cohorts through a GMM-derived
//! "normalization cutoff". The design memo
//! `docs/devlog/2026-09-30-GMM-stratify-memo.md` pins the rule to upstream
//! master `cc6bf5ef` (tag v1.5.0; line numbers below refer to
//! `SigProfilerExtractor/subroutines.py` = Sub and `sigpro.py` = Sig):
//!
//! * **Statistic** — the raw per-sample mutation total (catalog column
//!   sums; Sub:154). No log transform and no opportunity normalization:
//!   the mixture is fitted directly on raw counts (Sub:156-157).
//! * **Mixture** — `GaussianMixture(n_components=2, covariance_type="full")`
//!   (Sub:163-167); on 1-D data "full" is a scalar variance. Upstream seeds
//!   it from the run root seed since b71b6cd (v1.5.0); before that it was
//!   unseeded. sklearn's `reg_covar = 1e-6` additive variance floor is kept
//!   here ([`GMM_VAR_REG`]).
//! * **Cutoff rule** — NOT a posterior-0.5 crossing and NOT a component-mean
//!   ordering. Starting from all totals, fit k = 2, then repeatedly keep
//!   only the **majority cluster** (argmax count, first-max tie-break on
//!   ascending labels) while the cluster means differ by at least
//!   `4 × sd` of the majority cluster (population sd; Sub:154-194), then
//!   `cutoff = trunc(mean + 2·sd)` over the retained values
//!   (Sub:195-200), floored at `manual_cutoff = 100 × channels`
//!   (Sig:918-919). The mixture only supplies the labels; the cutoff is a
//!   population statistic of the retained subset.
//! * **Classification** — a sample is hypermutated iff
//!   `total > cutoff` (Sub:236, strict inequality). Upstream then rescales
//!   flagged columns down to the cutoff; msuiter's pipeline deliberately
//!   diverges (exclude from de novo extraction + forced refit,
//!   ARCHITECTURE §5 "非归一化"). That downstream policy belongs to the M2
//!   pipeline layer: this kernel ships the frozen cutoff rule, the
//!   classification predicate, and nothing more.
//!
//! # Determinism contract
//!
//! sklearn's GMM (kmeans initialization, version-dependent) is replaced by
//! an in-house EM with a frozen seeded initialization drawn from [`MsRng`]
//! (canonical stream layout v1): [`StreamId::ZERO`], one stream threaded
//! through every prune iteration of [`normalization_cutoff`]. Same input +
//! same seed produces bit-identical output on a given toolchain (single
//! thread, fixed reduction order). Golden tests pin integer outcomes
//! (cutoff, cluster sizes) that are robust to libm ulp drift, plus model
//! parameters under a 1e-9 relative tolerance. The convergence criterion
//! (frozen mean-log-likelihood tolerance) is a declared implementation
//! divergence from sklearn's lower-bound tolerance (memo §2.1/§4).

use crate::error::MsError;
use crate::rng::{MsRng, StreamId};

/// Additive variance floor applied in every M step (`1e-6`), mirroring
/// sklearn's `GaussianMixture(reg_covar=1e-6)` default: a degenerate
/// (all-identical) input collapses towards zero variance, and the additive
/// term keeps the model positive definite instead of singular.
pub const GMM_VAR_REG: f64 = 1e-6;

/// Frozen convergence tolerance on the absolute change of the mean
/// log-likelihood between EM iterations (memo §2.1). Deliberately our own
/// constant: upstream inherits sklearn's lower-bound tolerance, which is a
/// moving target across sklearn releases.
pub const GMM_TOL: f64 = 1e-8;

/// Hard EM iteration cap. A run that stops here reports
/// [`Gmm1DFit::converged == false`] instead of erroring (mirrors upstream,
/// where a non-converged fit still yields labels).
pub const GMM_MAX_ITER: usize = 200;

/// Fitted 1-D Gaussian mixture with k = 2 components, canonicalized to
/// ascending component mean (`means[0] <= means[1]`).
#[derive(Debug, Clone, PartialEq)]
pub struct Gmm1D {
    /// Component means, ascending.
    pub means: [f64; 2],
    /// Component variances (positive; `>=` [`GMM_VAR_REG`]).
    pub vars: [f64; 2],
    /// Mixture weights, summing to 1.
    pub weights: [f64; 2],
}

/// Result of [`fit_gmm1d`]: the canonicalized mixture plus hard
/// assignments under the final model.
#[derive(Debug, Clone, PartialEq)]
pub struct Gmm1DFit {
    /// Canonicalized mixture (component 0 = lower mean).
    pub model: Gmm1D,
    /// Hard assignment per input point under the final model
    /// (posterior argmax; exact ties go to component 0). Indices follow the
    /// *canonical* components.
    pub labels: Vec<u8>,
    /// Mean per-point log-likelihood under the final model.
    pub mean_loglik: f64,
    /// Whether EM met [`GMM_TOL`] before the iteration cap.
    pub converged: bool,
    /// Number of EM iterations performed (E+M pairs).
    pub n_iter: usize,
}

/// Result of [`normalization_cutoff`]: the frozen SigProfiler cutoff rule
/// applied to per-sample mutation totals.
#[derive(Debug, Clone, PartialEq)]
pub struct CutoffFit {
    /// The cutoff in mutations per sample (integer, as upstream's
    /// `int(mean + 2·sd)` with the `manual_cutoff` floor applied).
    pub cutoff: u64,
    /// Number of samples surviving the majority-cluster pruning (the
    /// "bulk" population the cutoff is derived from).
    pub retained_n: usize,
    /// Population mean of the retained totals.
    pub retained_mean: f64,
    /// Population standard deviation (ddof = 0) of the retained totals.
    pub retained_sd: f64,
    /// Number of GMM fits executed inside the prune loop (0 for degenerate
    /// inputs where the loop never runs).
    pub n_fits: usize,
    /// True when every executed EM run converged (vacuously true when none
    /// ran; false when a fit hit the iteration cap or failed).
    pub converged: bool,
}

/// Natural log of the N(x | mean, var) density. `var > 0` is guaranteed by
/// the additive [`GMM_VAR_REG`] floor, so no extra guard is needed.
fn log_normal_pdf(x: f64, mean: f64, var: f64) -> f64 {
    -0.5 * (std::f64::consts::TAU.ln() + var.ln() + (x - mean) * (x - mean) / var)
}

/// Population mean and standard deviation (ddof = 0) over all elements.
fn population_mean_sd(values: &[f64]) -> (f64, f64) {
    let n = values.len() as f64;
    let mean = values.iter().sum::<f64>() / n;
    let var = values.iter().map(|&v| (v - mean) * (v - mean)).sum::<f64>() / n;
    (mean, var.sqrt())
}

/// Validate a sample-value slice for the mixture: non-empty and finite.
fn validate_values(x: &[f64]) -> Result<usize, MsError> {
    if x.is_empty() {
        return Err(MsError::new(
            "argument",
            "sample values must not be empty",
        ));
    }
    if let Some(pos) = x.iter().position(|v| !v.is_finite()) {
        return Err(MsError::new(
            "argument",
            "sample values must be finite (no NaN/Inf)",
        )
        .with_i(pos as i64 + 1));
    }
    Ok(x.len())
}

/// Validate per-sample mutation totals for the cutoff rule: finite and
/// non-negative (counts semantics; upstream receives integer count matrices).
fn validate_totals(totals: &[f64]) -> Result<usize, MsError> {
    let n = validate_values(totals)?;
    if let Some(pos) = totals.iter().position(|&v| v < 0.0) {
        return Err(MsError::new(
            "argument",
            "mutation totals must be non-negative",
        )
        .with_i(pos as i64 + 1));
    }
    Ok(n)
}

/// Fit a 1-D two-component Gaussian mixture by Expectation-Maximization
/// with a frozen MsRng-seeded initialization (canonical stream layout v1,
/// `StreamId::ZERO`).
///
/// Initialization: two distinct data points drawn with the seeded stream
/// become the initial means (ascending), the population variance of all
/// points plus [`GMM_VAR_REG`] seeds both variances, weights start at
/// 1/2 each. Each EM iteration is one E step (log-space responsibilities
/// via log-sum-exp) followed by one M step (means, then variances with the
/// new means — sklearn's order — plus the additive [`GMM_VAR_REG`]).
///
/// The returned model is canonicalized to ascending means; `labels` are
/// hard assignments under the canonical model. Same input and seed give
/// bit-identical results (single thread, fixed reduction order).
///
/// Errors ([`MsError`] topic `"argument"`): empty input, non-finite values,
/// or fewer than two points (a two-component fit is undefined).
pub fn fit_gmm1d(
    x: &[f64],
    master_seed: u64,
    max_iter: usize,
    tol: f64,
) -> Result<Gmm1DFit, MsError> {
    let mut rng = MsRng::from_stream(master_seed, StreamId::ZERO);
    fit_gmm1d_with_rng(x, &mut rng, max_iter, tol)
}

/// [`fit_gmm1d`] with a caller-owned generator: lets a longer protocol (the
/// [`normalization_cutoff`] prune loop, or future replicate streams in M2)
/// keep one deterministic stream across successive fits.
pub fn fit_gmm1d_with_rng(
    x: &[f64],
    rng: &mut MsRng,
    max_iter: usize,
    tol: f64,
) -> Result<Gmm1DFit, MsError> {
    let n = validate_values(x)?;
    if n < 2 {
        return Err(MsError::new(
            "argument",
            "a two-component mixture needs at least two samples",
        ));
    }

    // ---- Seeded initialization (frozen; memo §2.1) --------------------
    // Seeded anchor + farthest-point partner: the anchor index is drawn
    // from the seeded stream, the partner is the data point farthest from
    // it (earliest index on ties, hard fallback to the next index for
    // all-identical inputs). This is distance-aware like the upstream
    // sklearn k-means++ seeding — a lone extreme sample always receives a
    // component — while staying fully deterministic.
    let n64 = n as u64;
    let ia = (rng.next_u64() % n64) as usize;
    let mut ib = 0_usize;
    let mut best = -1.0_f64;
    for (j, &v) in x.iter().enumerate() {
        let d = (v - x[ia]).abs();
        if d > best {
            best = d;
            ib = j;
        }
    }
    if ib == ia {
        ib = (ia + 1) % n;
    }
    let (lo, hi) = if x[ia] <= x[ib] { (x[ia], x[ib]) } else { (x[ib], x[ia]) };
    let (_, pop_sd) = population_mean_sd(x);
    let pop_var = pop_sd * pop_sd + GMM_VAR_REG;
    let mut means = [lo, hi];
    let mut vars = [pop_var, pop_var];
    let mut weights = [0.5_f64, 0.5_f64];

    // ---- EM ------------------------------------------------------------
    let mut resp = vec![0.0_f64; n];
    let mut prev_ll = f64::NEG_INFINITY;
    let mut converged = false;
    let mut n_iter = 0_usize;
    for it in 0..max_iter {
        // E step: log-space responsibilities + mean log-likelihood under
        // the current parameters.
        let mut ll_sum = 0.0_f64;
        for (k, &v) in x.iter().enumerate() {
            let l0 = log_normal_pdf(v, means[0], vars[0]);
            let l1 = log_normal_pdf(v, means[1], vars[1]);
            let top = l0.max(l1);
            // log-sum-exp of the two component densities (weights enter as
            // additive log terms).
            let mix = top
                + (weights[0] * (l0 - top).exp() + weights[1] * (l1 - top).exp()).ln();
            ll_sum += mix;
            // Clamp into [0, 1]: rounding can push the raw responsibility a
            // few ulp past the boundary, and a >1 responsibility makes
            // r1 = 1 - r0 negative, which can drive a collapsed component's
            // variance below zero (log(var) -> NaN). Standard EM hygiene,
            // mirrored exactly by the R protocol twin.
            let r0 = (weights[0] * (l0 - mix).exp()).clamp(0.0, 1.0);
            resp[k] = r0; // r1 = 1 - r0 by the two-component identity
        }
        let ll = ll_sum / n as f64;
        if it > 0 && (ll - prev_ll).abs() < tol {
            converged = true;
            n_iter = it;
            break;
        }
        prev_ll = ll;

        // M step: means first, then variances around the new means
        // (sklearn's order), each variance floored additively.
        let mut r0_sum = 0.0_f64;
        let mut m0_num = 0.0_f64;
        let mut m1_num = 0.0_f64;
        for (k, &v) in x.iter().enumerate() {
            let r0 = resp[k];
            let r1 = 1.0 - r0;
            r0_sum += r0;
            m0_num += r0 * v;
            m1_num += r1 * v;
        }
        let r1_sum = n as f64 - r0_sum;
        let n0 = if r0_sum > 0.0 { r0_sum } else { 1.0 };
        let n1 = if r1_sum > 0.0 { r1_sum } else { 1.0 };
        // A component whose responsibility mass underflows to exactly zero
        // is frozen at its previous parameters (dead-component guard).
        let new_means = [
            if r0_sum > 0.0 { m0_num / n0 } else { means[0] },
            if r1_sum > 0.0 { m1_num / n1 } else { means[1] },
        ];
        let mut v0_num = 0.0_f64;
        let mut v1_num = 0.0_f64;
        for (k, &v) in x.iter().enumerate() {
            let r0 = resp[k];
            v0_num += r0 * (v - new_means[0]) * (v - new_means[0]);
            v1_num += (1.0 - r0) * (v - new_means[1]) * (v - new_means[1]);
        }
        let new_vars = [
            if r0_sum > 0.0 { v0_num / n0 + GMM_VAR_REG } else { vars[0] },
            if r1_sum > 0.0 { v1_num / n1 + GMM_VAR_REG } else { vars[1] },
        ];
        means = new_means;
        vars = new_vars;
        weights = [r0_sum / n as f64, r1_sum / n as f64];
        n_iter = it + 1;
    }

    // Final pass: hard labels + log-likelihood under the final model.
    let mut labels = vec![0_u8; n];
    let mut ll_sum = 0.0_f64;
    for (k, &v) in x.iter().enumerate() {
        let l0 = log_normal_pdf(v, means[0], vars[0]);
        let l1 = log_normal_pdf(v, means[1], vars[1]);
        let top = l0.max(l1);
        let mix = top
            + (weights[0] * (l0 - top).exp() + weights[1] * (l1 - top).exp()).ln();
        ll_sum += mix;
        labels[k] = if weights[0] * (l0 - mix).exp() >= 0.5 { 0 } else { 1 };
    }
    let mean_loglik = ll_sum / n as f64;

    // Canonicalization: ascending component means (component 0 = low).
    if means[0] > means[1] {
        means.swap(0, 1);
        vars.swap(0, 1);
        weights.swap(0, 1);
        for l in labels.iter_mut() {
            *l = 1 - *l;
        }
    }

    Ok(Gmm1DFit {
        model: Gmm1D { means, vars, weights },
        labels,
        mean_loglik,
        converged,
        n_iter,
    })
}

/// Apply the frozen SigProfiler hypermutant normalization-cutoff rule
/// (`docs/devlog/2026-09-30-GMM-stratify-memo.md` §1.3) to per-sample
/// mutation totals.
///
/// Protocol (upstream `cc6bf5ef`, Sub:149-200, Sig:913-921):
/// 1. fit the k = 2 mixture on the current totals (one MsRng stream
///    threaded through every iteration);
/// 2. if the fit fails or all points land in one cluster: stop
///    (upstream's `try/except` break and `len(unique) == 1` break);
/// 3. if the cluster means differ by less than `4 × sd` of the majority
///    cluster (population sd; `np.argmax` first-max tie-break on ascending
///    labels): stop;
/// 4. otherwise keep only the majority cluster's values and refit;
/// 5. `cutoff = trunc(mean + 2·sd)` over the retained values, floored at
///    `manual_cutoff` (call-site convention: `100 × channel count`).
///
/// Classification of a sample against the returned cutoff is
/// [`classify_hypermutants`] (`total > cutoff`, upstream Sub:236).
///
/// Errors ([`MsError`] topic `"argument"`): empty, non-finite or negative
/// totals.
pub fn normalization_cutoff(
    totals: &[f64],
    manual_cutoff: u64,
    master_seed: u64,
) -> Result<CutoffFit, MsError> {
    validate_totals(totals)?;

    let mut rng = MsRng::from_stream(master_seed, StreamId::ZERO);
    let mut values: Vec<f64> = totals.to_vec();
    let mut n_fits = 0_usize;
    // Vacuously true when no fit runs (degenerate inputs); a failed or
    // non-converged fit marks the whole rule run as not fully converged.
    let mut converged = true;

    loop {
        if values.len() < 2 {
            break;
        }
        let fit = match fit_gmm1d_with_rng(&values, &mut rng, GMM_MAX_ITER, GMM_TOL) {
            Ok(f) => f,
            // Upstream wraps the fit in try/except and breaks on any
            // failure (Sub:190-192); a structured error degrades to the
            // same stop, mirroring the semantics without panicking.
            Err(_) => {
                converged = false;
                break;
            }
        };
        n_fits += 1;
        converged &= fit.converged;

        let c0 = fit.labels.iter().filter(|&&l| l == 0).count();
        let c1 = values.len() - c0;
        if c0 == 0 || c1 == 0 {
            break; // single occupied cluster (Sub:169-170)
        }
        // np.argmax/np.argmin first-extremum tie-break on ascending labels:
        // both ties resolve to label 0.
        let bigger = if c0 >= c1 { 0_usize } else { 1_usize };
        let smaller = 1 - bigger;
        let (mean_big, sd_big) = subset_mean_sd(&values, &fit.labels, bigger);
        let (mean_small, _) = subset_mean_sd(&values, &fit.labels, smaller);
        if (mean_big - mean_small).abs() < 4.0 * sd_big {
            break; // bulk is homogeneous enough (Sub:186-192)
        }
        let keep = bigger;
        values = values
            .iter()
            .zip(fit.labels.iter())
            .filter(|&(_, &l)| l as usize == keep)
            .map(|(&v, _)| v)
            .collect();
        // The retained subset is a strict subset (both clusters non-empty),
        // so the loop is bounded by the initial sample count.
        debug_assert!(n_fits <= totals.len());
    }

    let (mean, sd) = population_mean_sd(&values);
    let mut cutoff = (mean + 2.0 * sd).max(0.0) as u64; // trunc toward zero; positive domain => floor
    if cutoff < manual_cutoff {
        cutoff = manual_cutoff;
    }

    Ok(CutoffFit {
        cutoff,
        retained_n: values.len(),
        retained_mean: mean,
        retained_sd: sd,
        n_fits,
        converged,
    })
}

/// Population mean/sd over the subset of `values` whose label equals `label`.
fn subset_mean_sd(values: &[f64], labels: &[u8], label: usize) -> (f64, f64) {
    let mut sum = 0.0_f64;
    let mut count = 0_usize;
    for (i, &l) in labels.iter().enumerate() {
        if l as usize == label {
            sum += values[i];
            count += 1;
        }
    }
    if count == 0 {
        return (0.0, 0.0);
    }
    let mean = sum / count as f64;
    let mut var = 0.0_f64;
    for (i, &l) in labels.iter().enumerate() {
        if l as usize == label {
            let d = values[i] - mean;
            var += d * d;
        }
    }
    (mean, (var / count as f64).sqrt())
}

/// Classification predicate of the cutoff rule: a sample is hypermutated
/// iff its total is strictly greater than the cutoff (upstream Sub:236,
/// `totalMutations > normalization_cutoff`).
///
/// Callers own input hygiene (the MsCatalog validator rejects NA upstream
/// of this point); non-finite totals classify as `false` by IEEE ordering,
/// mirroring numpy's comparison semantics.
pub fn classify_hypermutants(totals: &[f64], cutoff: u64) -> Vec<bool> {
    totals.iter().map(|&t| t > cutoff as f64).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    // ------------------------------------------------------------------
    // Fixtures (deterministic arithmetic formulas; no RNG dependency so
    // the goldens are readable and hand-checkable).
    // ------------------------------------------------------------------

    /// A bimodal cohort in the shape the stratifier targets: 44 bulk
    /// samples in the low thousands and 6 hypermutants two orders of
    /// magnitude above the bulk (the ARCHITECTURE §8 "hypermutant arm"
    /// scenario at 5-10% prevalence).
    fn bimodal_cohort() -> Vec<f64> {
        let mut v = Vec::with_capacity(50);
        for i in 0..44u64 {
            let t = 4200 + 700 * (i % 13) + 130 * (i % 7) + 40 * (i % 3);
            v.push(t as f64);
        }
        v.extend([81_000.0, 96_000.0, 120_000.0, 133_000.0, 145_000.0, 158_000.0]);
        v
    }

    /// 40 samples on a deterministic ramp plus one extreme outlier
    /// (500 000) — the adversarial "lone hypermutant" shape.
    fn ramp_with_outlier() -> Vec<f64> {
        let mut v: Vec<f64> = (0..40u64).map(|i| (4800 + 37 * i) as f64).collect();
        v.push(500_000.0);
        v
    }

    // ------------------------------------------------------------------
    // Golden (frozen at U-M1c-02; values produced by this implementation
    // and cross-checked against the upstream rule by hand:
    // retained bulk = the 44 low samples, cutoff = trunc(mean + 2·sd)
    // over them). Integer outcomes are the D11-stable pins; model
    // parameters are asserted under a 1e-6 relative tolerance so libm ulp
    // drift across platforms cannot flip a golden.
    // ------------------------------------------------------------------

    #[test]
    fn golden_bimodal_cohort_cutoff() {
        let x = bimodal_cohort();
        let c = normalization_cutoff(&x, 0, 1).unwrap();
        assert_eq!(c.cutoff, 13_804);
        assert_eq!(c.retained_n, 44);
        assert_eq!(c.n_fits, 2);
        assert!(c.converged);
        // The 6 injected hypermutants are exactly the flagged samples.
        let hyper = classify_hypermutants(&x, c.cutoff);
        let flagged: Vec<usize> = hyper
            .iter()
            .enumerate()
            .filter(|(_, &b)| b)
            .map(|(i, _)| i)
            .collect();
        assert_eq!(flagged, vec![44, 45, 46, 47, 48, 49]);

        let fit = fit_gmm1d(&x, 1, GMM_MAX_ITER, GMM_TOL).unwrap();
        assert!(fit.converged);
        // Canonical ordering: component 0 = the bulk, component 1 = hyper.
        assert!(
            (fit.model.means[0] - 8_496.129_238).abs() < 1e-6 * 8_496.0,
            "bulk mean = {:?}",
            fit.model.means
        );
        assert!(
            (fit.model.means[1] - 122_163.637_368).abs() < 1e-6 * 122_163.0,
            "hyper mean = {:?}",
            fit.model.means
        );
        assert!(fit.model.means[0] < fit.model.means[1]);
        assert!((fit.model.weights[0] + fit.model.weights[1] - 1.0).abs() < 1e-12);
        let n_hyper = fit.labels.iter().filter(|&&l| l == 1).count();
        assert_eq!(n_hyper, 6);
    }

    #[test]
    fn golden_cutoff_is_seed_robust_on_separated_cohorts() {
        let x = bimodal_cohort();
        for seed in 1..=8u64 {
            let c = normalization_cutoff(&x, 0, seed).unwrap();
            assert_eq!(c.cutoff, 13_804, "seed {seed}");
            assert_eq!(c.retained_n, 44, "seed {seed}");
        }
    }

    #[test]
    fn golden_extreme_outlier_is_pruned() {
        let x = ramp_with_outlier();
        let c = normalization_cutoff(&x, 0, 1).unwrap();
        // The lone 500 000 sample is stripped by the majority-cluster
        // pruning; the cutoff is the bulk statistic (5521.5 + 2·427.1).
        assert_eq!(c.cutoff, 6_375);
        assert_eq!(c.retained_n, 40);
        assert_eq!(c.n_fits, 2);
        assert!((c.retained_mean - 5_521.5).abs() < 1e-9);
        assert!((c.retained_sd - 427.105_7).abs() < 1e-3);
        let hyper = classify_hypermutants(&x, c.cutoff);
        assert!(hyper[40], "the outlier must be flagged");
        assert_eq!(hyper.iter().filter(|&&b| b).count(), 1);
    }

    // ------------------------------------------------------------------
    // Degenerate inputs (upstream parity: sklearn failures degrade to the
    // try/except break, leaving the current values as the bulk).
    // ------------------------------------------------------------------

    #[test]
    fn degenerate_all_identical_values() {
        let x = vec![7_000.0; 30];
        let c = normalization_cutoff(&x, 0, 1).unwrap();
        assert_eq!(c.cutoff, 7_000, "cutoff collapses to the shared value");
        assert_eq!(c.retained_n, 30);
        assert_eq!(c.n_fits, 1);
        assert!(c.converged);
        // No hypermutants: the predicate flags nothing.
        assert!(classify_hypermutants(&x, c.cutoff).iter().all(|b| !b));
        // The mixture itself stays finite (no NaN/inf anywhere).
        let fit = fit_gmm1d(&x, 1, GMM_MAX_ITER, GMM_TOL).unwrap();
        assert!(fit.model.means.iter().all(|m| m.is_finite()));
        assert!(fit.model.vars.iter().all(|v| v.is_finite() && *v >= GMM_VAR_REG));
        assert!(fit.mean_loglik.is_finite());
    }

    #[test]
    fn degenerate_single_sample() {
        let x = [12_345.0];
        let c = normalization_cutoff(&x, 0, 1).unwrap();
        // Upstream: the sklearn fit raises inside try/except -> break, and
        // the cutoff is the single sample's own total (sd of n=1 is 0).
        assert_eq!(c.cutoff, 12_345);
        assert_eq!(c.retained_n, 1);
        assert_eq!(c.n_fits, 0);
        // The bare mixture fit rejects a single point instead.
        assert!(fit_gmm1d(&x, 1, GMM_MAX_ITER, GMM_TOL).is_err());
    }

    #[test]
    fn degenerate_two_sample_tie_break_favors_low_label() {
        // Two clusters of one point each: np.argmax's first-max tie-break
        // on ascending labels picks label 0, which our canonicalization
        // pins to the LOW-mean component — so the low value survives and
        // the cutoff collapses to it. Frozen deterministic behavior on a
        // degenerate shape (memo §4 failure-mode register).
        let x = [100.0, 90_000.0];
        let c = normalization_cutoff(&x, 0, 1).unwrap();
        assert_eq!(c.cutoff, 100);
        assert_eq!(c.retained_n, 1);
        assert_eq!(c.n_fits, 1);
    }

    // ------------------------------------------------------------------
    // Rule mechanics
    // ------------------------------------------------------------------

    #[test]
    fn manual_cutoff_floors_the_derived_value() {
        let x = bimodal_cohort();
        // Derived cutoff 13 804: a smaller manual floor is inert, a larger
        // one wins (upstream Sub:197-199 floor semantics, Sig:919).
        assert_eq!(normalization_cutoff(&x, 9_600, 1).unwrap().cutoff, 13_804);
        assert_eq!(normalization_cutoff(&x, 20_000, 1).unwrap().cutoff, 20_000);
    }

    #[test]
    fn classify_predicate_is_strictly_greater() {
        // Upstream Sub:236 `totalMutations > normalization_cutoff`:
        // equality is NOT hypermutated.
        let flags = classify_hypermutants(&[9_599.0, 9_600.0, 9_601.0], 9_600);
        assert_eq!(flags, vec![false, false, true]);
    }

    #[test]
    fn labels_are_canonical_low_then_high() {
        let x = bimodal_cohort();
        let fit = fit_gmm1d(&x, 1, GMM_MAX_ITER, GMM_TOL).unwrap();
        assert!(fit.labels[..44].iter().all(|&l| l == 0));
        assert!(fit.labels[44..].iter().all(|&l| l == 1));
    }

    // ------------------------------------------------------------------
    // Determinism and input hygiene
    // ------------------------------------------------------------------

    #[test]
    fn determinism_same_seed_is_bit_identical() {
        let x = bimodal_cohort();
        let a = normalization_cutoff(&x, 9_600, 42).unwrap();
        let b = normalization_cutoff(&x, 9_600, 42).unwrap();
        assert_eq!(a, b);
        let fa = fit_gmm1d(&x, 42, GMM_MAX_ITER, GMM_TOL).unwrap();
        let fb = fit_gmm1d(&x, 42, GMM_MAX_ITER, GMM_TOL).unwrap();
        assert_eq!(fa, fb);
    }

    #[test]
    fn argument_errors_are_structured() {
        assert_eq!(
            normalization_cutoff(&[], 0, 1).unwrap_err().topic,
            "argument"
        );
        let with_nan = vec![1.0, f64::NAN, 3.0];
        let err = normalization_cutoff(&with_nan, 0, 1).unwrap_err();
        assert_eq!(err.topic, "argument");
        assert_eq!(err.i, Some(2));
        let negative = vec![1.0, -5.0, 3.0];
        let err = normalization_cutoff(&negative, 0, 1).unwrap_err();
        assert_eq!(err.topic, "argument");
        assert_eq!(err.i, Some(2));
        let err = fit_gmm1d(&[f64::INFINITY, 2.0], 1, GMM_MAX_ITER, GMM_TOL).unwrap_err();
        assert_eq!(err.topic, "argument");
    }
}
