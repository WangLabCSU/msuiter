//! Likelihood kernels and calibration primitives for exposure fitting and
//! signature-presence testing (U-M3a-01; `docs/ARCHITECTURE.md` §2
//! `engine/likelihood.rs`, §5 MSU-Fit estimand table). This module ships the
//! *statistical primitives only*: likelihood evaluation, the boundary
//! likelihood-ratio test, interior-support Fisher standard errors, and the
//! zeroing predicates. Fitting orchestration (`ms_fit`), bootstrap resampling
//! and the QP faces are later units (U-M3a-02/03/04).
//!
//! # Upstream semantics (pinned to source, D11/D13)
//!
//! * **Multinomial log-likelihood** — the generative law of a catalog given
//!   signatures and total exposure (research/02 §3). The per-channel log
//!   guard `log(eps + p)` uses [`LL_EPS`] `= 1e-16`, pinned to MuSiCal's
//!   probability clip in `nnls_likelihood_bidirectional`
//!   (`musical/nnls_sparse.py`; research/02 §1.1, line 20). The per-mutation
//!   rescaled variant [`multinomial_ll_per_mutation`] divides by the total —
//!   exactly the scale MuSiCal's LTH threshold epsilon acts on (research/02
//!   §1.1, line 14: "每突变（per-trial）多项对数似然尺度").
//! * **Negative binomial log-likelihood** — mSigAct's default exposure
//!   likelihood `sum_i dnbinom(x_i; mu = recon_i, size = nbinom.size)`
//!   (research/02 §1.2, line 38), with the upstream size anchors
//!   [`NB_SIZE_SBS96`] = 8, [`NB_SIZE_DBS78`] = 50, [`NB_SIZE_ID83`] = 100.
//!   Size semantics follow mSigAct: **larger size → closer to Poisson**
//!   (`Var = mu + mu^2/size`); the Poisson limit is a pinned test.
//! * **χ²₁ likelihood-ratio test** — see the anchor statement below.
//! * **Fisher information** — the analytic interior-support information of
//!   research/02 §2, line 89 ("I = N·Σᵢ(wᵢ)⁻¹∇wᵢ∇wᵢᵀ", the analytic /
//!   delta-method cell flagged as greenfield there): with reconstruction
//!   `w = W·θ` this is `H_jk = Σ_i W_ij·W_ik / w_i`. Under the multinomial
//!   with profiled total (and under the Poisson model) this is the expected
//!   information; `-N·log(Σθ)` contributes no second derivative, so both
//!   laws share the same `H`. Only interior (positive-exposure) components
//!   receive standard errors — "boundary parameters get tests, not
//!   intervals" (ARCHITECTURE §5, MSU-Fit row).
//! * **Zeroing rules** — the exposure-zeroing conventions audited in
//!   research/02 §6, line 127 (sigfit CI-lower-bound < 0.01; MuSiCal
//!   share-threshold iteration, default 0.05; COSMIC-style < 10 mutations).
//!   This module ships the two *share/absolute-count predicate* faces; the
//!   CI-lower-bound face needs intervals (U-M3b) and is deliberately absent.
//!
//! # χ²₁ LRT — formula pinned and documented (semantic anchor statement)
//!
//! * **Statistic** — `D = 2·(ll_alt − ll_null)`, clamped at 0 for
//!   floating-point noise, pinned to mSigAct v3.0.3-branch
//!   `R/SignaturePresenceTest1.R`:
//!   `statistic = 2 * (loglh.with - loglh.without)` (research/02 §1.2,
//!   line 39: "统计量 = 2(ll_with − ll_without)").
//! * **p-value (msuiter default)** — [`p_chisq1_lrt`] = **½·P(χ²₁ > D) =
//!   ½·erfc(√(D/2))**, the Self–Liang (1987) boundary asymptotic: under
//!   H0: θ = 0 with θ constrained to θ ≥ 0, `D → ½·δ₀ + ½·χ²₁`, so the
//!   calibrated boundary p-value is *half* the ordinary χ²₁ upper tail and
//!   the level-α test has simulated size ≈ α (pinned by the size/power
//!   smoke below). This is the msuiter contract: ARCHITECTURE §5 declares
//!   MSU-Fit presence estimand ① as "χ²₁ LRT（Self–Liang 边界渐近）", and
//!   per its header the living ARCHITECTURE decision record supersedes the
//!   archival research snapshot.
//! * **p-value (mSigAct upstream convention)** — [`p_chisq1_upper`] =
//!   `P(χ²₁ > D) = erfc(√(D/2)) = 2·[`p_chisq1_lrt` of the same statistic]`,
//!   exactly what mSigAct computes (`pchisq(statistic, 1, lower.tail =
//!   FALSE)`). Under H0 this is conservative by *exactly* a factor of two
//!   (simulated size 0.0227 vs nominal 0.05 at the smoke calibration point;
//!   exact finite-sample computation agrees). It is kept as an explicit,
//!   documented variant for upstream-comparable reporting and for the
//!   boundary-p relation tests.
//!
//! # Zero pseudo-counts and the ε strategy (ARCHITECTURE §7.4)
//!
//! Catalog channels are never smoothed: a zero count contributes *exactly
//! zero* to every log-likelihood (no `0·log 0 → −inf` damage, no pseudo
//! observation). The only numeric guards live inside logarithms and
//! divisions: `log(eps + p)` for channel probabilities, `log(eps + mean)`
//! for NB means, `max(w_i, eps)` in the Fisher denominator. A channel with
//! `p = 0` (or mean 0) but a *positive* count evaluates to the finite
//! sentinel `x·log(eps)`: the honest "this reconstruction is impossible"
//! value, without leaving the float domain.
//!
//! # `erfc` / `ln_gamma` (zero new dependencies)
//!
//! Both are self-implemented pure Rust (`f64::ln_gamma` and libm `erfc` are
//! not on the stable/1.71 surface): `ln_gamma` via the Lanczos approximation
//! (g = 7, 9 coefficients; reflection for `x < 0.5`), `erfc` via the
//! regularized incomplete gamma at `a = 1/2` — power series for `x² < 1.5`,
//! modified-Lentz continued fraction above — the classic Numerical-Recipes
//! split. Documented accuracy: relative error well below 1e-13 across the
//! tested domain (validated against platform libm anchors; `erfc` decays
//! continuously to 0 for large arguments). `χ²₁` tails use the exact
//! identity `P(χ²₁ > t) = erfc(√(t/2))` (t = Z², Z standard normal).
//!
//! # Determinism
//!
//! Pure sequential kernels, fixed reduction order, single-threaded, no
//! hashing: identical inputs give bit-identical outputs on a given
//! toolchain (golden values are asserted under relative tolerances so libm
//! ulp drift across platforms cannot flip a pin; repeated same-process
//! calls are asserted bit-identical). Simulation-based size/power tests use
//! canonical [`MsRng`] streams with fixed master seeds (ARCH §2 stream
//! layout v1).

use crate::error::MsError;
use crate::linalg::gram_factor;

/// Additive log guard `log(eps + p)` / `log(eps + mu)` / `max(w, eps)`.
///
/// Value pinned to MuSiCal's reconstruction clip `1e-16`
/// (`nnls_likelihood_bidirectional`; research/02 §1.1, line 20). This is a
/// numeric *guard inside logarithms and divisions only* — it is never added
/// to observed counts (zero pseudo-count policy, ARCHITECTURE §7.4).
pub const LL_EPS: f64 = 1e-16;

// ---------------------------------------------------------------------------
// Special functions (self-implemented; zero new dependencies)
// ---------------------------------------------------------------------------

/// Lanczos approximation coefficients (g = 7, n = 9; the standard
/// public-domain set, ~15 significant digits for `x >= 0.5`).
const LANCZOS: [f64; 9] = [
    0.999_999_999_999_809_9,
    676.520_368_121_885_1,
    -1_259.139_216_722_402_8,
    771.323_428_777_653_1,
    -176.615_029_162_140_6,
    12.507_343_278_686_905,
    -0.138_571_095_265_720_12,
    9.984_369_578_019_572e-6,
    1.505_632_735_149_311_6e-7,
];

/// Natural log of the gamma function, `ln Γ(x)`.
///
/// Lanczos approximation (g = 7, n = 9) for `x >= 0.5` with the reflection
/// formula `Γ(x)Γ(1−x) = π/sin(πx)` below. Accuracy ~1e-15 relative on the
/// positive axis (pinned against platform libm anchors in tests; absolute
/// error of the returned *log* grows with `|ln Γ(x)|` at huge arguments,
/// which only matters through cancellations — the NB Poisson-limit test
/// pins the relevant difference accuracy at `size = 1e8`).
///
/// Domain notes: `x = 0` and negative integers sit on poles (`±inf`/NaN per
/// honest IEEE propagation); the kernels in this module only ever call it
/// with `x >= 1`. NaN input propagates. `ln Γ(1) = ln Γ(2) = 0` is returned
/// **exactly** (the Lanczos form leaves ~1e-15 residue there; the exact
/// zeros matter because count-offset arguments `ln Γ(x+1)` land on them and
/// the zero-count/empty-catalog pins below are bit-exact).
pub fn ln_gamma(x: f64) -> f64 {
    if x == 1.0 || x == 2.0 {
        return 0.0;
    }
    if x < 0.5 {
        // Reflection: ln Γ(x) = ln(π/sin(πx)) − ln Γ(1−x).
        (std::f64::consts::PI / (std::f64::consts::PI * x).sin()).ln() - ln_gamma(1.0 - x)
    } else {
        let z = x - 1.0;
        // a = c₀ + Σ cᵢ/(z+i); t = z + g + 1/2 = z + 7.5.
        let mut a = LANCZOS[0];
        for (i, &c) in LANCZOS.iter().enumerate().skip(1) {
            a += c / (z + i as f64);
        }
        let t = z + LANCZOS_G_HALF;
        std::f64::consts::LN_2 * 0.5 + std::f64::consts::PI.ln() * 0.5 + (z + 0.5) * t.ln() - t
            + a.ln()
    }
}

/// `g + 1/2 = 7.5` for the g = 7 Lanczos set (spelled out; see [`LANCZOS`]).
const LANCZOS_G_HALF: f64 = 7.5;

/// Complementary error function, `erfc(x) = 2/√π · ∫ₓ^∞ e^(−t²) dt`.
///
/// Evaluated as the regularized upper incomplete gamma at `a = 1/2`:
/// `erfc(x) = Q(1/2, x²)` — power series for `x² < 1.5`, modified-Lentz
/// continued fraction above (the classic Numerical-Recipes split). Negative
/// arguments use the symmetry `erfc(−x) = 2 − erfc(x)`; `|x| ≥ 38` decays
/// to the exact limit (`0` / `2`; `erfc(38)² ≈ 1e−1258`, far below the f64
/// underflow boundary at ~1e−308, so the early return is value-exact).
///
/// Documented accuracy: relative error well below 1e-13 on the tested grid
/// (0, 0.5, …, 6) against platform libm; the series/continued-fraction seam
/// at `x = √1.5` is pinned continuous to 1e-12. NaN input propagates.
pub fn erfc(x: f64) -> f64 {
    if x.is_nan() {
        return f64::NAN;
    }
    if x < 0.0 {
        return 2.0 - erfc(-x);
    }
    if x >= 38.0 {
        return 0.0;
    }
    let z2 = x * x;
    if z2 < 1.5 {
        1.0 - gamma_p_series(0.5, z2)
    } else {
        gamma_q_cf(0.5, z2)
    }
}

/// Lower regularized incomplete gamma `P(a, x)` by power series
/// (`γ(a,x)/Γ(a)`); used only with `x < a + 1` (i.e. `x² < 1.5` here).
fn gamma_p_series(a: f64, x: f64) -> f64 {
    let mut ap = a;
    let mut sum = 1.0 / a;
    let mut del = sum;
    for _ in 0..300 {
        ap += 1.0;
        del *= x / ap;
        sum += del;
        if del.abs() < sum.abs() * 1e-16 {
            break;
        }
    }
    let log_prefactor = -x + a * x.ln() - ln_gamma(a);
    log_prefactor.exp() * sum
}

/// Upper regularized incomplete gamma `Q(a, x) = Γ(a,x)/Γ(a)` by the
/// modified-Lentz continued fraction; used with `x ≥ a + 1` where it
/// converges monotonically (~15 digits in well under 300 iterations).
fn gamma_q_cf(a: f64, x: f64) -> f64 {
    const FPMIN: f64 = 1e-300;
    let mut b = x + 1.0 - a;
    let mut c = 1.0 / FPMIN;
    let mut d = 1.0 / b;
    let mut h = d;
    for i in 1..300 {
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

// ---------------------------------------------------------------------------
// Validation helpers (FFI contract 5: structured errors, 1-based indices)
// ---------------------------------------------------------------------------

/// Common count-vector validation: non-empty, finite (`"na"`), non-negative
/// and integral (`"argument"`), with 1-based offending index.
fn validate_counts(counts: &[f64], what: &str) -> Result<(), MsError> {
    if counts.is_empty() {
        return Err(MsError::new(
            "argument",
            format!("{what} must not be empty"),
        ));
    }
    for (i, &c) in counts.iter().enumerate() {
        if !c.is_finite() {
            return Err(
                MsError::new("na", format!("{what} must be finite (no NaN/Inf)"))
                    .with_i(i as i64 + 1),
            );
        }
        if c < 0.0 {
            return Err(
                MsError::new("argument", format!("{what} must be non-negative"))
                    .with_i(i as i64 + 1),
            );
        }
        if c != c.trunc() {
            return Err(
                MsError::new("argument", format!("{what} must be integral counts"))
                    .with_i(i as i64 + 1),
            );
        }
    }
    Ok(())
}

/// Probability/mean-vector validation: finite (`"na"`) and non-negative
/// (`"argument"`), with 1-based offending index. Length checks are the
/// caller's (they need the pairing context).
fn validate_non_negative(values: &[f64], what: &str) -> Result<(), MsError> {
    for (i, &v) in values.iter().enumerate() {
        if !v.is_finite() {
            return Err(
                MsError::new("na", format!("{what} must be finite (no NaN/Inf)"))
                    .with_i(i as i64 + 1),
            );
        }
        if v < 0.0 {
            return Err(
                MsError::new("argument", format!("{what} must be non-negative"))
                    .with_i(i as i64 + 1),
            );
        }
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Multinomial log-likelihood
// ---------------------------------------------------------------------------

/// Multinomial log-likelihood of `counts` under per-channel probabilities
/// `probs` (up to the multinomial coefficient convention below, this is the
/// exact log pmf: `ln Γ(T+1) − Σ ln Γ(xᵢ+1) + Σ_{xᵢ>0} xᵢ·ln(pᵢ)`).
///
/// Semantics pinned to the zero pseudo-count policy (ARCHITECTURE §7.4):
///
/// * a channel with `xᵢ = 0` contributes **exactly 0** — it is skipped, so
///   its probability value (including `pᵢ = 0`) cannot damage the sum;
/// * a channel with `xᵢ > 0` and `pᵢ = 0` evaluates to the finite sentinel
///   `xᵢ·ln(eps)` via the [`LL_EPS`] guard — "impossible reconstruction",
///   representable, never `−inf`;
/// * an all-zero catalog returns exactly `0.0`.
///
/// `probs` are used as given (no silent renormalization — the caller's
/// catalog/signature layer owns the sum-to-one contract); negative or
/// non-finite entries are structured errors.
///
/// Errors (topic, 1-based `i` where applicable): empty input
/// (`"argument"`); non-finite (`"na"`); negative or non-integral counts /
/// negative or non-finite probs (`"argument"`); length mismatch
/// (`"argument"`).
pub fn multinomial_ll(counts: &[f64], probs: &[f64]) -> Result<f64, MsError> {
    validate_counts(counts, "counts")?;
    validate_non_negative(probs, "probs")?;
    if counts.len() != probs.len() {
        return Err(
            MsError::new("argument", "counts and probs must have equal length")
                .with_i(counts.len() as i64)
                .with_j(probs.len() as i64),
        );
    }

    let total: f64 = counts.iter().sum();
    let mut ll = ln_gamma(total + 1.0);
    for (&c, &p) in counts.iter().zip(probs.iter()) {
        ll -= ln_gamma(c + 1.0);
        if c > 0.0 {
            // log(eps + p) guard; the eps never touches the counts.
            ll += c * (LL_EPS + p).ln();
        }
    }
    Ok(ll)
}

/// Per-mutation (per-trial) rescaled multinomial log-likelihood
/// `multinomial_ll / Σcounts` — the scale MuSiCal's LTH epsilon threshold
/// acts on (research/02 §1.1, line 14; total-count-invariant by
/// construction). An empty catalog scores `0.0`.
///
/// This is the primitive U-M3a-02's bidirectional refit steps are built on;
/// the stepping logic itself is out of scope here.
pub fn multinomial_ll_per_mutation(counts: &[f64], probs: &[f64]) -> Result<f64, MsError> {
    let total: f64 = counts.iter().sum();
    if total <= 0.0 {
        // Empty (or null) catalog: define the per-mutation score as 0.
        validate_counts(counts, "counts")?;
        validate_non_negative(probs, "probs")?;
        return Ok(0.0);
    }
    Ok(multinomial_ll(counts, probs)? / total)
}

// ---------------------------------------------------------------------------
// Negative binomial log-likelihood (mSigAct semantics)
// ---------------------------------------------------------------------------

/// mSigAct `nbinom.size` anchor for SBS96 catalogs (research/02 §1.2).
pub const NB_SIZE_SBS96: f64 = 8.0;
/// mSigAct `nbinom.size` anchor for DBS78 catalogs (research/02 §1.2).
pub const NB_SIZE_DBS78: f64 = 50.0;
/// mSigAct `nbinom.size` anchor for ID83 catalogs (research/02 §1.2).
pub const NB_SIZE_ID83: f64 = 100.0;

/// Negative binomial log-pmf of one channel: `x ~ NB(mean = mu, size = k)`.
///
/// Evaluation path (all `lgamma`, per the unit spec):
///
/// ```text
/// ln Γ(x+k) − ln Γ(k) − ln Γ(x+1)
///   + k·(ln k − ln(k+μ))                    // always
///   + x·(ln(eps+μ) − ln(k+μ))   [only x > 0] // zero-count channels: exactly 0
/// ```
///
/// Size semantics follow mSigAct: `k` large → Poisson(`μ`) (`Var = μ +
/// μ²/k`); the Poisson limit is pinned by a test at `k = 1e8`. `μ = 0` with
/// `x = 0` scores exactly `0.0`; `μ = 0` (or μ ≪ eps) with `x > 0` hits the
/// [`LL_EPS`] guard and returns the finite "impossible" sentinel — no
/// NaN/Inf on valid inputs.
///
/// Errors: non-finite inputs (`"na"`); negative count/mean or non-positive
/// size (`"argument"`); non-integral count (`"argument"`), each with the
/// 1-based-free scalar context in the message.
pub fn nb_ll_one(count: f64, mean: f64, size: f64) -> Result<f64, MsError> {
    validate_counts(&[count], "count")?;
    validate_non_negative(&[mean], "mean")?;
    if !size.is_finite() {
        return Err(MsError::new("na", "size must be finite (no NaN/Inf)"));
    }
    if size <= 0.0 {
        return Err(MsError::new("argument", "size must be positive"));
    }

    let mut ll = ln_gamma(count + size) - ln_gamma(size) - ln_gamma(count + 1.0);
    ll += size * (size.ln() - (size + mean).ln());
    if count > 0.0 {
        ll += count * ((LL_EPS + mean).ln() - (size + mean).ln());
    }
    Ok(ll)
}

/// Summed negative binomial log-likelihood over channels — mSigAct's
/// exposure likelihood `Σᵢ dnbinom(xᵢ; mu = reconᵢ, size)` (research/02
/// §1.2, line 38), with one shared `size` (upstream per-catalog-type sizes:
/// [`NB_SIZE_SBS96`] / [`NB_SIZE_DBS78`] / [`NB_SIZE_ID83`]).
///
/// Errors: as [`nb_ll_one`], plus length mismatch (`"argument"`).
pub fn nb_ll(counts: &[f64], means: &[f64], size: f64) -> Result<f64, MsError> {
    validate_counts(counts, "counts")?;
    validate_non_negative(means, "means")?;
    if counts.len() != means.len() {
        return Err(
            MsError::new("argument", "counts and means must have equal length")
                .with_i(counts.len() as i64)
                .with_j(means.len() as i64),
        );
    }
    // size itself is validated once through the first channel evaluation.
    let mut ll = 0.0;
    for (&c, &m) in counts.iter().zip(means.iter()) {
        ll += nb_ll_one(c, m, size)?;
    }
    Ok(ll)
}

// ---------------------------------------------------------------------------
// χ²₁ likelihood-ratio test (boundary)
// ---------------------------------------------------------------------------

/// Likelihood-ratio statistic `D = max(0, 2·(ll_alt − ll_null))`.
///
/// Pinned to mSigAct v3.0.3-branch `R/SignaturePresenceTest1.R`
/// (`statistic = 2 * (loglh.with - loglh.without)`). The clamp at 0 is
/// numerical hygiene: for nested models `ll_alt ≥ ll_null` analytically,
/// and rounding can push the difference a few ulp negative. Callers pass
/// finite likelihoods (every LL kernel in this module returns finite
/// values); NaN propagates honestly.
pub fn lrt_stat(ll_null: f64, ll_alt: f64) -> f64 {
    (2.0 * (ll_alt - ll_null)).max(0.0)
}

/// Ordinary χ²₁ upper-tail p-value `P(χ²₁ > stat) = erfc(√(stat/2))`.
///
/// **Semantic anchor (mSigAct upstream convention):** this is exactly the
/// p-value mSigAct computes (`pchisq(statistic, 1, lower.tail = FALSE)` in
/// `SignaturePresenceTest1`). Under the H0 boundary (`exposure = 0`), the
/// Self–Liang limit makes this conservative by exactly a factor of two —
/// see the module anchor statement and [`p_chisq1_lrt`]. Negative input is
/// treated as 0 (p = 1) per the statistic clamp policy; NaN propagates.
pub fn p_chisq1_upper(stat: f64) -> f64 {
    erfc((stat.max(0.0) / 2.0).sqrt())
}

/// Boundary-calibrated LRT p-value for `H0: exposure = 0` vs `H1: > 0`:
/// `½·P(χ²₁ > D) = ½·erfc(√(D/2))` with `D =` [`lrt_stat`]`(ll_null,
/// ll_alt)`.
///
/// **This is the msuiter default** (ARCHITECTURE §5, MSU-Fit presence
/// estimand ①): Self–Liang (1987) boundary asymptotics give
/// `D → ½·δ₀ + ½·χ²₁` under H0, so the calibrated one-parameter boundary
/// p-value is *half* the ordinary χ²₁ tail and the level-α test achieves
/// simulated size ≈ α (pinned by `size_power_*` tests below). The mSigAct
/// full-tail convention is [`p_chisq1_upper`]; the two relate exactly as
/// `p_chisq1_upper = 2·p_chisq1_lrt` (bit-exact ½-scaling), asserted by
/// test.
pub fn p_chisq1_lrt(ll_null: f64, ll_alt: f64) -> f64 {
    0.5 * p_chisq1_upper(lrt_stat(ll_null, ll_alt))
}

// ---------------------------------------------------------------------------
// Fisher information — interior support only
// ---------------------------------------------------------------------------

/// Interior-support Fisher standard errors (support-conditional).
///
/// `interior` lists the indices of strictly positive exposures (the support
/// returned by a non-negative solver; the zeroing rules decide what counts
/// as negligibly small, Fisher only sees exact zeros as boundary).
/// `se[a]` is the support-conditional standard error of
/// `exposures[interior[a]]`, and `info` is the row-major
/// `interior.len() × interior.len()` expected information submatrix.
/// Boundary components get **no interval** — they get the χ²₁ LRT
/// ("boundary parameters get tests, not intervals", ARCHITECTURE §5).
#[derive(Debug, Clone, PartialEq)]
pub struct FisherSe {
    /// Indices of interior (positive-exposure) components, ascending.
    pub interior: Vec<usize>,
    /// Standard errors, parallel to [`FisherSe::interior`].
    pub se: Vec<f64>,
    /// Support-conditional expected information, row-major
    /// `interior.len()²` entries.
    pub info: Vec<f64>,
}

/// Expected Fisher information and standard errors for exposures `θ` over
/// signatures `W` — the analytic interior-support primitive of research/02
/// §2 (line 89): with reconstruction `mᵢ = (Wθ)ᵢ`,
///
/// ```text
/// H_jk = Σᵢ W_ij·W_ik / max(mᵢ, eps)
/// ```
///
/// (Poisson-form expected information; identical for the multinomial with
/// profiled total, see the module docs). `w` is row-major
/// `n_channels × n_signatures`. Only interior components (`θ_j > 0`)
/// enter: the information is factorized and inverted on the interior block
/// alone (pivoted LDLᵀ from [`crate::linalg`]), and `se` covers the
/// interior only.
///
/// Errors: empty signature matrix or zero channels, storage size not
/// divisible by `n_channels`, signature/exposure count mismatch
/// (`"argument"`); non-finite (`"na"`) or negative (`"argument"`) entries;
/// `"singular"` when the interior information is structurally singular
/// (e.g. duplicate signature columns on the support).
pub fn fisher_se(w: &[f64], n_channels: usize, exposures: &[f64]) -> Result<FisherSe, MsError> {
    if n_channels == 0 || w.is_empty() || exposures.is_empty() {
        return Err(MsError::new(
            "argument",
            "fisher_se needs at least one channel and one signature",
        ));
    }
    if w.len() % n_channels != 0 {
        return Err(MsError::new(
            "argument",
            "signature storage must be n_channels * n_signatures",
        )
        .with_i(w.len() as i64));
    }
    let k = w.len() / n_channels;
    if k != exposures.len() {
        return Err(
            MsError::new("argument", "exposure count must equal the signature count")
                .with_i(exposures.len() as i64)
                .with_j(k as i64),
        );
    }
    validate_non_negative(w, "signatures")?;
    validate_non_negative(exposures, "exposures")?;

    // Reconstruction exposures m_i = (Wθ)_i.
    let mut m = vec![0.0_f64; n_channels];
    for (i, m_i) in m.iter_mut().enumerate() {
        let mut acc = 0.0_f64;
        for (j, &theta_j) in exposures.iter().enumerate() {
            acc += w[i * k + j] * theta_j;
        }
        *m_i = acc;
    }

    let interior: Vec<usize> = (0..k).filter(|&j| exposures[j] > 0.0).collect();
    let q = interior.len();
    if q == 0 {
        // All-boundary support: nothing to interval — tests, not intervals.
        return Ok(FisherSe {
            interior,
            se: Vec::new(),
            info: Vec::new(),
        });
    }

    // Support-conditional information block (symmetric, filled once).
    let mut info = vec![0.0_f64; q * q];
    for (a, &ja) in interior.iter().enumerate() {
        for (b, &jb) in interior.iter().enumerate().skip(a) {
            let mut acc = 0.0_f64;
            for (i, m_i) in m.iter().enumerate() {
                acc += w[i * k + ja] * w[i * k + jb] / m_i.max(LL_EPS);
            }
            info[a * q + b] = acc;
            info[b * q + a] = acc;
        }
    }

    let ldlt = gram_factor(&info, q, None)?;
    let mut se = Vec::with_capacity(q);
    for a in 0..q {
        let mut e = vec![0.0_f64; q];
        e[a] = 1.0;
        let x = ldlt.solve(&e)?;
        se.push(x[a].sqrt());
    }

    Ok(FisherSe { interior, se, info })
}

// ---------------------------------------------------------------------------
// Zeroing rules (exposure-zeroing predicates)
// ---------------------------------------------------------------------------

/// Share-threshold anchor from the sigfit CI-zeroing family: the 95% CI
/// lower bound < 0.01 ⇒ zero (research/02 §6, line 127; Medo-confirmed
/// beneficial). The CI-bound face lives in U-M3b; this constant pins the
/// threshold value of that family for the share predicate.
pub const SIGFIT_ZERO_SHARE: f64 = 0.01;

/// Share-threshold anchor from MuSiCal's `thresh` variant (per-signature
/// exposure-share iteration, default 0.05; research/02 §1.1, line 26).
pub const MUSICAL_THRESH_SHARE: f64 = 0.05;

/// Absolute-count anchor from the COSMIC-style convention: exposures below
/// 10 mutations are zeroed (research/02 §6, line 127).
pub const COSMIC_ZERO_MUTATIONS: f64 = 10.0;

/// Share-based zeroing predicate: component `j` is zeroed iff its
/// *compositional share* `θⱼ / Σθ` is **strictly below** `share_threshold`
/// (or `θⱼ = 0` exactly). An all-zero vector zeroes everything (shares
/// defined as 0, no division); an empty input yields an empty mask.
///
/// Semantics: this is the MuSiCal `thresh`-family rule (share iteration,
/// research/02 §1.1 line 26 / §6 line 127) as a pure predicate — the
/// iterative refit around it belongs to U-M3a-02/04. Strict `<` pins the
/// boundary: a share exactly at the threshold survives.
///
/// Errors: negative or non-finite exposures (`"argument"` / `"na"`);
/// threshold outside `[0, 1]` or non-finite (`"argument"`).
pub fn zeroing_mask_share(exposures: &[f64], share_threshold: f64) -> Result<Vec<bool>, MsError> {
    validate_non_negative(exposures, "exposures")?;
    if !share_threshold.is_finite() || !(0.0..=1.0).contains(&share_threshold) {
        return Err(MsError::new(
            "argument",
            "share threshold must lie in [0, 1]",
        ));
    }
    let total: f64 = exposures.iter().sum();
    Ok(exposures
        .iter()
        .map(|&e| e == 0.0 || (total > 0.0 && e / total < share_threshold))
        .collect())
}

/// Absolute-count zeroing predicate: component `j` is zeroed iff
/// `θⱼ < min_mutations` (strictly) — the COSMIC-style "< 10 mutations"
/// family (research/02 §6, line 127; anchor [`COSMIC_ZERO_MUTATIONS`]).
///
/// Errors: negative or non-finite exposures (`"argument"` / `"na"`);
/// negative or non-finite threshold (`"argument"`).
pub fn zeroing_mask_mutations(exposures: &[f64], min_mutations: f64) -> Result<Vec<bool>, MsError> {
    validate_non_negative(exposures, "exposures")?;
    if !min_mutations.is_finite() || min_mutations < 0.0 {
        return Err(MsError::new(
            "argument",
            "mutation threshold must be finite and non-negative",
        ));
    }
    Ok(exposures.iter().map(|&e| e < min_mutations).collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rng::{MsRng, StreamId};

    /// Test-local relative-tolerance assert (goldens survive cross-platform
    /// libm ulp drift; D11 numeric-protocol convention).
    fn assert_close(actual: f64, expected: f64, rel: f64, what: &str) {
        let scale = expected.abs().max(1e-300);
        assert!(
            (actual - expected).abs() <= rel * scale,
            "{what}: actual {actual}, expected {expected}"
        );
    }

    // ------------------------------------------------------------------
    // Test-local generators (documented smoke machinery; production
    // sampling lives in resample.rs which has no Poisson face yet).
    // ------------------------------------------------------------------

    /// Uniform in [0, 1) on the 53-bit grid (same construction as
    /// resample.rs).
    fn unit(rng: &mut MsRng) -> f64 {
        (rng.next_u64() >> 11) as f64 * (1.0 / (1u64 << 53) as f64)
    }

    /// Knuth Poisson draw (product-of-uniforms; adequate for mu <= ~500).
    fn poisson_draw(rng: &mut MsRng, mu: f64) -> u64 {
        let limit = (-mu).exp();
        let mut k = 0_u64;
        let mut p = 1.0_f64;
        loop {
            k += 1;
            p *= unit(rng);
            if p <= limit {
                return k - 1;
            }
        }
    }

    /// Poisson log-pmf via the module's `ln_gamma` (test-side reference for
    /// the NB Poisson-limit and the analytic LRT case).
    fn poisson_ll(x: f64, mu: f64) -> f64 {
        x * mu.ln() - mu - ln_gamma(x + 1.0)
    }

    // ==================================================================
    // Multinomial LL
    // ==================================================================

    #[test]
    fn multinomial_golden_two_channel_and_three_channel() {
        // Hand-checkable: lnΓ(41) − lnΓ(11) − lnΓ(31) + 10·ln(0.25) +
        // 30·ln(0.75); reference from Python stdlib lgamma.
        let ll = multinomial_ll(&[10.0, 30.0], &[0.25, 0.75]).unwrap();
        assert_close(ll, -1.935_414_991_900_614_7, 1e-12, "multinomial 2x2");
        // 3-channel uniform: (3,5,2) | (1/3,1/3,1/3).
        let ll3 = multinomial_ll(&[3.0, 5.0, 2.0], &[1.0 / 3.0; 3]).unwrap();
        assert_close(ll3, -3.154_108_706_175_625_4, 1e-12, "multinomial 3x1/3");
        // Exact combinatorial identity for the uniform 3-channel case:
        // ll = ln(10!/(3!5!2!)) − 10·ln 3.
        let by_hand =
            ln_gamma(11.0) - ln_gamma(4.0) - ln_gamma(6.0) - ln_gamma(3.0) - 10.0 * 3_f64.ln();
        assert_close(ll3, by_hand, 1e-12, "multinomial 3-channel identity");
    }

    #[test]
    fn multinomial_zero_cell_contributes_exactly_zero() {
        // (10, 0) under (0.3, 0.7) must equal (10, 0) under (0.3, 0.0)
        // bit-for-bit: the zero-count channel is skipped, its probability
        // never enters. Both equal the 1-channel value 10·ln(0.3+eps).
        let a = multinomial_ll(&[10.0, 0.0], &[0.3, 0.7]).unwrap();
        let b = multinomial_ll(&[10.0, 0.0], &[0.3, 0.0]).unwrap();
        assert_eq!(a, b, "zero-count channel must be a no-op");
        assert_close(a, -12.039_728_043_259_357, 1e-12, "zero-cell golden");
        assert_close(a, 10.0 * (LL_EPS + 0.3).ln(), 1e-12, "single-term form");
        // Adding a whole channel with x=0, p=0 changes nothing (bit-identical).
        let c = multinomial_ll(&[10.0, 0.0, 0.0], &[0.3, 0.0, 0.0]).unwrap();
        assert_eq!(a, c, "structural zero-pseudo-count policy");
    }

    #[test]
    fn multinomial_zero_prob_positive_count_is_finite_sentinel() {
        // x = 2 on a p = 0 channel: the full ll (including the
        // multinomial coefficient lnΓ(13) − lnΓ(11) − lnΓ(3) = ln 66)
        // stays finite (never −inf) and is exactly reconstructible.
        let ll = multinomial_ll(&[10.0, 2.0], &[0.5, 0.0]).unwrap();
        let expected = ln_gamma(13.0) - ln_gamma(11.0) - ln_gamma(3.0)
            + 10.0 * (LL_EPS + 0.5).ln()
            + 2.0 * LL_EPS.ln();
        assert_close(ll, expected, 1e-12, "sentinel form");
        assert!(ll.is_finite());
        assert!(ll < -70.0, "sentinel must be strongly negative: {ll}");
    }

    #[test]
    fn multinomial_empty_catalog_is_exactly_zero() {
        let ll = multinomial_ll(&[0.0, 0.0, 0.0], &[0.5, 0.3, 0.2]).unwrap();
        assert_eq!(ll, 0.0);
        let per = multinomial_ll_per_mutation(&[0.0, 0.0], &[0.5, 0.5]).unwrap();
        assert_eq!(per, 0.0);
    }

    #[test]
    fn multinomial_per_mutation_scale_matches_musical_semantics() {
        // Per-mutation LL = ll / total (definition). MuSiCal's LTH acts on
        // the cross-entropy-per-mutation Σxᵢ·ln(pᵢ)/Σx, which differs from
        // our scale by the multinomial coefficient / T — a quantity that is
        // *constant in the probabilities*, so the two scales rank candidate
        // supports identically and every step decision Δ is the same. Pin
        // exactly that: the per-mutation difference between two candidate
        // probability vectors equals MuSiCal's ΔL to 1e-12.
        let counts = [10.0, 30.0];
        let probs_a = [0.25, 0.75];
        let probs_b = [0.5, 0.5];
        let delta_ours = multinomial_ll_per_mutation(&counts, &probs_a).unwrap()
            - multinomial_ll_per_mutation(&counts, &probs_b).unwrap();
        let cross = |p: &[f64]| -> f64 {
            counts
                .iter()
                .zip(p)
                .map(|(&c, &pi)| c * (LL_EPS + pi).ln())
                .sum::<f64>()
                / 40.0
        };
        let delta_musical = cross(&probs_a) - cross(&probs_b);
        assert_close(delta_ours, delta_musical, 1e-12, "LTH-scale equivalence");
    }

    #[test]
    fn multinomial_validation_errors_are_structured() {
        assert_eq!(
            multinomial_ll(&[], &[]).unwrap_err().topic,
            "argument",
            "empty input"
        );
        let err = multinomial_ll(&[1.0, -2.0], &[0.5, 0.5]).unwrap_err();
        assert_eq!((err.topic.as_str(), err.i), ("argument", Some(2)));
        let err = multinomial_ll(&[1.5, 2.0], &[0.5, 0.5]).unwrap_err();
        assert_eq!(
            (err.topic.as_str(), err.i),
            ("argument", Some(1)),
            "non-integral"
        );
        let err = multinomial_ll(&[1.0, f64::NAN], &[0.5, 0.5]).unwrap_err();
        assert_eq!((err.topic.as_str(), err.i), ("na", Some(2)));
        let err = multinomial_ll(&[1.0, 2.0], &[0.5, -0.1]).unwrap_err();
        assert_eq!((err.topic.as_str(), err.i), ("argument", Some(2)));
        let err = multinomial_ll(&[1.0, 2.0], &[0.5]).unwrap_err();
        assert_eq!(err.topic, "argument", "length mismatch");
        // Per-mutation face inherits the same guards.
        assert_eq!(
            multinomial_ll_per_mutation(&[1.0], &[f64::NAN])
                .unwrap_err()
                .topic,
            "na"
        );
    }

    #[test]
    fn multinomial_determinism_bit_identical() {
        let a = multinomial_ll(&[7.0, 0.0, 13.0, 2.0], &[0.1, 0.2, 0.3, 0.4]).unwrap();
        let b = multinomial_ll(&[7.0, 0.0, 13.0, 2.0], &[0.1, 0.2, 0.3, 0.4]).unwrap();
        assert_eq!(a, b);
        let pa = multinomial_ll_per_mutation(&[7.0, 13.0], &[0.4, 0.6]).unwrap();
        let pb = multinomial_ll_per_mutation(&[7.0, 13.0], &[0.4, 0.6]).unwrap();
        assert_eq!(pa, pb);
    }

    // ==================================================================
    // Negative binomial LL
    // ==================================================================

    #[test]
    fn nb_golden_msigact_sizes() {
        // Single channel, mSigAct SBS96 size: dnbinom(7; 5, 8).
        let ll = nb_ll_one(7.0, 5.0, NB_SIZE_SBS96).unwrap();
        assert_close(ll, -2.431_744_180_837_809, 1e-12, "nb(7;5,k=8)");
        // Vector form sums channels: (7;5,k=8) + (12;9.5,k=100).
        let llv = nb_ll(&[7.0, 12.0], &[5.0, 9.5], NB_SIZE_ID83).unwrap();
        // Note: the vector shares one size; recompute both at k=100.
        let expected = nb_ll_one(7.0, 5.0, 100.0).unwrap() + nb_ll_one(12.0, 9.5, 100.0).unwrap();
        assert_eq!(llv, expected);
        // Reference at k=100 for the (12; 9.5) channel.
        assert_close(
            nb_ll_one(12.0, 9.5, NB_SIZE_ID83).unwrap(),
            -2.500_142_471_634_749_3,
            1e-12,
            "nb(12;9.5,k=100)",
        );
        // Size anchors equal the mSigAct defaults exactly.
        assert_eq!(NB_SIZE_SBS96, 8.0);
        assert_eq!(NB_SIZE_DBS78, 50.0);
        assert_eq!(NB_SIZE_ID83, 100.0);
    }

    #[test]
    fn nb_zero_count_cells() {
        // x = 0, mu = 5: only the size normalizer k·ln(k/(k+mu)) survives.
        let ll = nb_ll_one(0.0, 5.0, NB_SIZE_SBS96).unwrap();
        assert_close(ll, -3.884_062_526_253_608, 1e-12, "nb(0;5,k=8)");
        // x = 0, mu = 0: exactly 0 (degenerate but well-defined).
        assert_eq!(nb_ll_one(0.0, 0.0, NB_SIZE_SBS96).unwrap(), 0.0);
        // And in vector form a whole-zero catalog scores 0.
        assert_eq!(
            nb_ll(&[0.0, 0.0], &[0.0, 3.0], 8.0).unwrap(),
            nb_ll_one(0.0, 3.0, 8.0).unwrap()
        );
    }

    #[test]
    fn nb_poisson_limit_as_size_grows() {
        // size → ∞ approaches Poisson(mu): |NB − Poisson| shrinks with k
        // (theory ~ (x²−x+mu²)/2k) and is < 1e-5 at k = 1e8 (the bound
        // absorbs ln-gamma cancellation at the 1e8 argument scale).
        let (x, mu) = (20.0_f64, 20.0_f64);
        let pois = poisson_ll(x, mu);
        let d1 = (nb_ll_one(x, mu, 1e4).unwrap() - pois).abs();
        let d2 = (nb_ll_one(x, mu, 1e6).unwrap() - pois).abs();
        let d3 = (nb_ll_one(x, mu, 1e8).unwrap() - pois).abs();
        assert!(
            d1 > d2 && d2 > d3,
            "must shrink monotonically: {d1} {d2} {d3}"
        );
        assert!(d3 < 1e-5, "Poisson limit at size=1e8: {d3}");
        // Sanity: the k = 8 value is meaningfully away from Poisson.
        assert!((nb_ll_one(x, mu, 8.0).unwrap() - pois).abs() > 0.5);
    }

    #[test]
    fn nb_size_semantics_absorb_overdispersion() {
        // Overdispersed counts around mu=50: Poisson penalizes the spread
        // far more than NB(k=8) (reference values from Python stdlib).
        let flat = [40.0, 50.0, 60.0];
        let over = [5.0, 50.0, 95.0];
        let mus = [50.0, 50.0, 50.0];
        let pois_flat: f64 = flat.iter().zip(mus).map(|(&c, m)| poisson_ll(c, m)).sum();
        let pois_over: f64 = over.iter().zip(mus).map(|(&c, m)| poisson_ll(c, m)).sum();
        let nb_flat = nb_ll(&flat, &mus, NB_SIZE_SBS96).unwrap();
        let nb_over = nb_ll(&over, &mus, NB_SIZE_SBS96).unwrap();
        // Directional anchors (D13: the NB robustness claim, quantified).
        assert!(pois_flat - nb_flat < 2.0, "flat data: NB ≈ Poisson");
        assert!(nb_over - pois_over > 35.0, "overdispersion penalty gap");
        // And larger size sits between: NB(k=50) closer to Poisson than k=8.
        let nb_over_50 = nb_ll(&over, &mus, NB_SIZE_DBS78).unwrap();
        assert!(pois_over < nb_over_50 && nb_over_50 < nb_over);
    }

    #[test]
    fn nb_tiny_and_zero_means_stay_finite() {
        // mu = 1e-300: the eps guard yields the finite impossible-sentinel.
        let ll = nb_ll_one(3.0, 1e-300, NB_SIZE_SBS96).unwrap();
        assert_close(ll, -111.974_917_345_971_68, 1e-9, "nb tiny-mean golden");
        // mu = 0 with x > 0: finite sentinel via the same guard.
        let ll0 = nb_ll_one(3.0, 0.0, NB_SIZE_SBS96).unwrap();
        assert!(ll0.is_finite(), "no -inf on zero mean");
        assert!((ll0 - ll).abs() < 1e-6, "eps+0 == eps+1e-300 at this scale");
        // No NaN anywhere in a small sweep of extreme inputs.
        for mean in [0.0, 1e-300, 1e-16, 1.0, 1e9] {
            for count in [0.0, 1.0, 50.0] {
                let v = nb_ll_one(count, mean, 8.0).unwrap();
                assert!(v.is_finite(), "nb({count};{mean},8) = {v}");
            }
        }
    }

    #[test]
    fn nb_validation_errors_are_structured() {
        assert_eq!(
            nb_ll_one(5.0, 5.0, 0.0).unwrap_err().topic,
            "argument",
            "size=0"
        );
        assert_eq!(nb_ll_one(5.0, 5.0, -2.0).unwrap_err().topic, "argument");
        assert_eq!(nb_ll_one(5.0, f64::NAN, 8.0).unwrap_err().topic, "na");
        assert_eq!(nb_ll_one(-1.0, 5.0, 8.0).unwrap_err().topic, "argument");
        assert_eq!(
            nb_ll_one(2.5, 5.0, 8.0).unwrap_err().topic,
            "argument",
            "non-integral"
        );
        assert_eq!(
            nb_ll(&[1.0], &[], 8.0).unwrap_err().topic,
            "argument",
            "length mismatch"
        );
    }

    #[test]
    fn nb_determinism_bit_identical() {
        let a = nb_ll(&[7.0, 0.0, 12.0], &[5.0, 0.0, 9.5], 8.0).unwrap();
        let b = nb_ll(&[7.0, 0.0, 12.0], &[5.0, 0.0, 9.5], 8.0).unwrap();
        assert_eq!(a, b);
    }

    // ==================================================================
    // erfc / ln_gamma
    // ==================================================================

    #[test]
    fn ln_gamma_goldens() {
        // Platform-libm anchors (Python stdlib math.lgamma).
        let cases: &[(f64, f64)] = &[
            (0.5, 0.572_364_942_924_700_4),
            (1.0, 0.0),
            (1.5, -0.120_782_237_635_245_43),
            (2.0, 0.0),
            (3.0, std::f64::consts::LN_2), // = 0.6931471805599453, the ln 2 anchor
            (5.5, 3.957_813_967_618_716_5),
            (10.0, 12.801_827_480_081_467),
            (11.0, 15.104_412_573_075_514),
            (100.0, 359.134_205_369_575_4),
            (1001.0, 5_912.128_178_488_163),
        ];
        for &(x, expected) in cases {
            let got = ln_gamma(x);
            if expected == 0.0 {
                assert!(got.abs() < 1e-13, "ln_gamma({x}) = {got}");
            } else {
                assert_close(got, expected, 1e-12, "ln_gamma");
            }
        }
    }

    #[test]
    fn erfc_goldens_against_libm_anchors() {
        let cases: &[(f64, f64)] = &[
            (0.0, 1.0),
            (0.5, 0.479_500_122_186_953_5),
            (1.0, 0.157_299_207_050_285_16),
            (1.5, 0.033_894_853_524_689_274),
            (2.0, 0.004_677_734_981_047_264_5),
            (3.0, 2.209_049_699_858_543_8e-5),
            (4.0, 1.541_725_790_028_002e-8),
            (5.0, 1.537_459_794_428_035e-12),
            (6.0, 2.151_973_671_249_891_3e-17),
        ];
        for &(x, expected) in cases {
            assert_close(erfc(x), expected, 1e-11, "erfc golden");
        }
    }

    #[test]
    fn erfc_symmetry_and_decay_edges() {
        assert_eq!(erfc(0.0), 1.0);
        // erfc(−x) = 2 − erfc(x): exact by construction for the mirrored call.
        assert_eq!(erfc(-1.0), 2.0 - erfc(1.0));
        assert_eq!(erfc(-3.5), 2.0 - erfc(3.5));
        // Large |x| decay to the exact limits.
        assert_eq!(erfc(38.0), 0.0);
        assert_eq!(erfc(1e6), 0.0);
        assert_eq!(erfc(-1e6), 2.0);
    }

    #[test]
    fn erfc_seam_is_continuous_across_the_branch_switch() {
        // The series → continued-fraction seam sits at x = √1.5; approach
        // it from both sides and require agreement to 1e-12.
        let seam = 1.5_f64.sqrt();
        let below = erfc(seam - 1e-9);
        let above = erfc(seam + 1e-9);
        // Reference derivative |erfc'| <= 2/√π ≈ 1.13, so a 2e-9 step moves
        // the value by at most ~2.3e-9; a healthy implementation shows a
        // smooth difference, a broken branch a jump >> that.
        assert!(
            (below - above).abs() < 3e-9,
            "branch seam jump: {below} vs {above}"
        );
        assert_close(erfc(seam), 0.083_264_516_663_550_43, 1e-11, "seam value");
    }

    #[test]
    fn p_chisq1_upper_matches_erfc_formula_and_quantiles() {
        for t in [
            0.0_f64,
            0.5,
            2.705_543_454_095_404,
            3.841_458_820_694_124,
            10.0,
            123.0,
        ] {
            assert_eq!(
                p_chisq1_upper(t),
                erfc((t / 2.0).sqrt()),
                "formula pin at t={t}"
            );
        }
        // Known χ²₁ quantiles: P(χ²₁ > q) = 0.1 / 0.05 / 0.01.
        assert_close(p_chisq1_upper(2.705_543_454_095_404), 0.1, 1e-9, "q90");
        assert_close(p_chisq1_upper(3.841_458_820_694_124), 0.05, 1e-9, "q95");
        assert_close(p_chisq1_upper(6.634_896_601_021_213), 0.01, 1e-9, "q99");
        // Negative stats clamp to p = 1 (the statistic is never negative).
        assert_eq!(p_chisq1_upper(-3.0), 1.0);
        // Large stats underflow continuously to 0 — no NaN/Inf.
        assert_eq!(p_chisq1_upper(1e5), 0.0);
        assert_eq!(p_chisq1_upper(f64::INFINITY), 0.0);
    }

    #[test]
    fn p_chisq1_upper_agrees_with_independent_normal_tail() {
        // Cross-path check: P(χ²₁ > t) = 2·(1 − Φ(√t)), with Φ from the
        // Abramowitz–Stegun 26.2.17 rational approximation (|err| < 7.5e-8),
        // i.e. an implementation path disjoint from our erfc.
        fn phi(z: f64) -> f64 {
            if z < 0.0 {
                return 1.0 - phi(-z);
            }
            let t = 1.0 / (1.0 + 0.231_641_9 * z);
            let poly = t
                * (0.319_381_530
                    + t * (-0.356_563_782
                        + t * (1.781_477_937 + t * (-1.821_255_978 + t * 1.330_274_429))));
            1.0 - (-z * z / 2.0).exp() / std::f64::consts::TAU.sqrt() * poly
        }
        for t in [0.5_f64, 2.705_543_454_095_404, 10.0] {
            let via_normal = 2.0 * (1.0 - phi(t.sqrt()));
            assert!(
                (p_chisq1_upper(t) - via_normal).abs() < 2e-7,
                "t={t}: erfc path {} vs A&S path {}",
                p_chisq1_upper(t),
                via_normal
            );
        }
    }

    // ==================================================================
    // LRT statistic and boundary p-values
    // ==================================================================

    /// Analytic single-sample single-channel case: `x ~ Poisson(b + θ)`
    /// with known background `b`; H0: θ = 0 (boundary). Closed-form MLE
    /// `θ̂ = max(0, x−b)` and closed-form statistic.
    fn lrt_poisson(x: f64, b: f64) -> (f64, f64, f64) {
        let ll_null = poisson_ll(x, b);
        let ll_alt = poisson_ll(x, x.max(b));
        let stat = lrt_stat(ll_null, ll_alt);
        (stat, p_chisq1_lrt(ll_null, ll_alt), p_chisq1_upper(stat))
    }

    #[test]
    fn lrt_golden_analytic_poisson_case() {
        // x = 137 over background b = 100: stat = 2[137·ln(1.37) − 37].
        let (stat, p_lrt, p_full) = lrt_poisson(137.0, 100.0);
        assert_close(stat, 12.258_142_716_169_203, 1e-12, "analytic statistic");
        assert_close(p_lrt, 0.000_231_616_166_995_151_6, 1e-9, "Self–Liang p");
        assert_close(
            p_full,
            0.000_463_232_333_990_303_2,
            1e-9,
            "mSigAct full-tail p",
        );
        // The background-only observation cannot reject: θ̂ = 0 → D = 0.
        let (stat0, p0, pf0) = lrt_poisson(95.0, 100.0);
        assert_eq!(stat0, 0.0);
        assert_eq!(p0, 0.5, "boundary p at D = 0 is exactly ½");
        assert_eq!(pf0, 1.0);
        // Float-noise negative difference clamps to a zero statistic.
        assert_eq!(lrt_stat(-5.0, -5.0 - 1e-16), 0.0);
    }

    #[test]
    fn lrt_boundary_p_is_exactly_half_the_upper_tail() {
        // The doubling relation is bit-exact (0.5·x is an exponent shift).
        for ll_null in [-1000.0_f64, -123.456, -0.5] {
            for ll_alt in [ll_null, ll_null + 0.7, ll_null + 55.0] {
                let stat = lrt_stat(ll_null, ll_alt);
                assert_eq!(
                    p_chisq1_upper(stat),
                    2.0 * p_chisq1_lrt(ll_null, ll_alt),
                    "doubling relation at ({ll_null}, {ll_alt})"
                );
            }
        }
        // And at D = 0 both pins hold: ½ and 1.
        assert_eq!(p_chisq1_lrt(-7.0, -7.0), 0.5);
        assert_eq!(p_chisq1_upper(0.0), 1.0);
    }

    #[test]
    fn size_self_liang_boundary_p_matches_nominal_level() {
        // 2000 H0 replicates of the analytic case (b = 100): the rejection
        // rate at α = 0.05 must sit at the nominal level. The exact
        // finite-sample rate (summing the Poisson(100) pmf over the
        // rejection region) is 0.0522, so the window is [0.035, 0.070] —
        // ±3 MC standard errors around the exact value. Fixed seed.
        let n = 2000_u64;
        let mut rejects = 0_u64;
        for r in 0..n {
            let mut rep = MsRng::from_stream(
                0xFEED,
                StreamId {
                    replicate: r,
                    rank: 0,
                    fold: 7,
                },
            );
            let x = poisson_draw(&mut rep, 100.0) as f64;
            let (_, p, _) = lrt_poisson(x, 100.0);
            if p < 0.05 {
                rejects += 1;
            }
        }
        let rate = rejects as f64 / n as f64;
        assert!(
            (0.035..=0.070).contains(&rate),
            "boundary size at α=0.05: {rate} ({rejects}/{n})"
        );
    }

    #[test]
    fn power_grows_with_the_true_effect() {
        // Same engine, true θ > 0: power must dominate size and grow with
        // the effect (exact finite-sample anchors: 0.2645 at θ=10, 0.7746
        // at θ=25, so windows ±0.10 around them with MC noise).
        let n = 2000_u64;
        let run = |theta_true: f64, alpha: f64| -> f64 {
            let mut rejects = 0_u64;
            for r in 0..n {
                let mut rep = MsRng::from_stream(
                    0xBEAD,
                    StreamId {
                        replicate: r,
                        rank: 3,
                        fold: 1,
                    },
                );
                let x = poisson_draw(&mut rep, 100.0 + theta_true) as f64;
                let (_, p, _) = lrt_poisson(x, 100.0);
                if p < alpha {
                    rejects += 1;
                }
            }
            rejects as f64 / n as f64
        };
        let p10 = run(10.0, 0.05);
        let p25 = run(25.0, 0.05);
        assert!((0.16..=0.37).contains(&p10), "power at θ=10: {p10}");
        assert!((0.65..=0.90).contains(&p25), "power at θ=25: {p25}");
        assert!(p25 > p10, "power must grow with the effect: {p25} vs {p10}");
    }

    #[test]
    fn msigact_full_tail_is_conservative_by_half_under_h0() {
        // The mSigAct convention (full χ²₁ tail) rejects about half as
        // often at the same nominal level: exact finite-sample size 0.0227
        // at α = 0.05, window [0.008, 0.04]. Same draws as the size test
        // (same streams) for an apples-to-apples comparison.
        let n = 2000_u64;
        let mut rejects_full = 0_u64;
        let mut rejects_half = 0_u64;
        for r in 0..n {
            let mut rep = MsRng::from_stream(
                0xFEED,
                StreamId {
                    replicate: r,
                    rank: 0,
                    fold: 7,
                },
            );
            let x = poisson_draw(&mut rep, 100.0) as f64;
            let (_, p_half, p_full) = lrt_poisson(x, 100.0);
            if p_full < 0.05 {
                rejects_full += 1;
            }
            if p_half < 0.05 {
                rejects_half += 1;
            }
        }
        let rate_full = rejects_full as f64 / n as f64;
        assert!(
            (0.008..=0.045).contains(&rate_full),
            "full-tail size at α=0.05: {rate_full}"
        );
        assert!(rejects_full < rejects_half, "conservative by construction");
    }

    // ==================================================================
    // Fisher information / interior-support SE
    // ==================================================================

    /// 2×2 fixture: W = [[0.9, 0.5], [0.1, 0.5]] (channels × signatures),
    /// θ = (25, 100). Reference values from the closed form computed with
    /// Python (H = Wᵀ D⁻¹ W, m = (72.5, 52.5)).
    const W2: [f64; 4] = [0.9, 0.5, 0.1, 0.5];

    #[test]
    fn fisher_golden_two_by_two_information_and_se() {
        let fit = fisher_se(&W2, 2, &[25.0, 100.0]).unwrap();
        assert_eq!(fit.interior, vec![0, 1]);
        assert_close(fit.info[0], 0.011_362_889_983_579_639, 1e-10, "H00");
        assert_close(fit.info[1], 0.007_159_277_504_105_09, 1e-10, "H01");
        assert_close(fit.info[3], 0.008_210_180_623_973_728, 1e-10, "H11");
        assert_close(fit.se[0], 13.975_424_859_373_682, 1e-9, "se0");
        assert_close(fit.se[1], 16.441_183_047_457_38, 1e-9, "se1");
    }

    #[test]
    fn fisher_golden_one_dimensional_hand_value() {
        // W = [[0.3], [0.7]], θ = 10 → m = (3, 7);
        // H = 0.09/3 + 0.49/7 = 0.1 → SE = √10.
        let w = [0.3, 0.7];
        let fit = fisher_se(&w, 2, &[10.0]).unwrap();
        assert_eq!(fit.interior, vec![0]);
        assert_close(fit.info[0], 0.1, 1e-12, "H (1-D)");
        assert_close(fit.se[0], 10.0_f64.sqrt(), 1e-12, "SE (1-D)");
    }

    #[test]
    fn fisher_boundary_components_get_no_interval() {
        // A boundary exposure is excluded: interior = [1], one SE only.
        // With θ = (0, 100) the reconstruction is m = (50, 50) and the
        // support-conditional information is (0.5² + 0.5²)/50 = 0.01,
        // so SE(θ₂) = 10 — different from the both-interior case.
        let fit = fisher_se(&W2, 2, &[0.0, 100.0]).unwrap();
        assert_eq!(fit.interior, vec![1]);
        assert_eq!(fit.se.len(), 1);
        assert_close(fit.se[0], 10.0, 1e-9, "se(θ2) support-conditional");
        // All-boundary support: empty (and no error — tests, not intervals).
        let none = fisher_se(&W2, 2, &[0.0, 0.0]).unwrap();
        assert!(none.interior.is_empty() && none.se.is_empty() && none.info.is_empty());
    }

    #[test]
    fn fisher_se_matches_monte_carlo_sd_of_the_mle() {
        // Large-sample consistency smoke: under the Poisson law with m =
        // Wθ (θ = (25, 100), the information fixture), the MLE is the exact
        // 2×2 solve θ̂ = W⁻¹x; its Monte-Carlo SD must match the kernel's
        // Fisher SE (theory: Cov(θ̂) = (Wᵀ D⁻¹ W)⁻¹ exactly).
        let reps = 4000_u64;
        let mut hats0 = Vec::with_capacity(reps as usize);
        let mut hats1 = Vec::with_capacity(reps as usize);
        for r in 0..reps {
            let mut rep = MsRng::from_stream(
                0xF157,
                StreamId {
                    replicate: r,
                    rank: 0,
                    fold: 0,
                },
            );
            let x0 = poisson_draw(&mut rep, 72.5) as f64;
            let x1 = poisson_draw(&mut rep, 52.5) as f64;
            // W⁻¹ = 1/0.40 · [[0.5, −0.5], [−0.1, 0.9]].
            let inv_det = 1.0 / (W2[0] * W2[3] - W2[1] * W2[2]);
            hats0.push(inv_det * (W2[3] * x0 - W2[1] * x1));
            hats1.push(inv_det * (-W2[2] * x0 + W2[0] * x1));
        }
        let mean_sd = |v: &[f64]| -> (f64, f64) {
            let n = v.len() as f64;
            let mean = v.iter().sum::<f64>() / n;
            let var = v.iter().map(|&t| (t - mean) * (t - mean)).sum::<f64>() / (n - 1.0);
            (mean, var.sqrt())
        };
        let fit = fisher_se(&W2, 2, &[25.0, 100.0]).unwrap();
        // Sample SD within 15% of the analytic SE (4000 reps: ~1% MC noise
        // on the SD, plus the Knuth-generator's small-mu wobble).
        let (mean0, sd0) = mean_sd(&hats0);
        let (_, sd1) = mean_sd(&hats1);
        assert!(
            (sd0 / fit.se[0] - 1.0).abs() < 0.15,
            "SD(θ̂₀) {} vs SE {}",
            sd0,
            fit.se[0]
        );
        assert!(
            (sd1 / fit.se[1] - 1.0).abs() < 0.15,
            "SD(θ̂₁) {} vs SE {}",
            sd1,
            fit.se[1]
        );
        // Unbiasedness of the MLE at this scale (|bias| < 15% of one SD).
        assert!((mean0 - 25.0).abs() < 0.15 * fit.se[0], "mean θ̂₀ = {mean0}");
    }

    #[test]
    fn fisher_zero_reconstruction_channel_hits_epsilon_guard() {
        // First channel has an all-zero signature row → m₀ = 0; the
        // max(mᵢ, eps) denominator keeps everything finite (no NaN/Inf).
        // Two further non-proportional rows keep the 2×2 information
        // non-singular (on a single informative row any two signature
        // columns are proportional and the block would be rank-1).
        let w = [0.0, 0.0, 0.3, 0.6, 0.2, 0.1];
        let fit = fisher_se(&w, 3, &[10.0, 20.0]).unwrap();
        assert_eq!(fit.interior, vec![0, 1]);
        assert!(fit.info.iter().all(|v| v.is_finite()));
        assert!(fit.se.iter().all(|v| v.is_finite() && *v > 0.0));
        // The information comes entirely from the two live channels:
        // m = (0, 15, 4).
        assert_close(
            fit.info[0],
            0.09 / 15.0 + 0.04 / 4.0,
            1e-12,
            "degenerate-row info",
        );
        assert_close(
            fit.info[1],
            0.18 / 15.0 + 0.02 / 4.0,
            1e-12,
            "off-diagonal info",
        );
    }

    #[test]
    fn fisher_singular_support_is_a_structured_error() {
        // Duplicate signature columns on an interior support → singular
        // information → the LDLᵀ layer's structured error, not a panic.
        let w = [0.5, 0.5, 0.5, 0.5];
        let err = fisher_se(&w, 2, &[1.0, 1.0]).unwrap_err();
        assert_eq!(err.topic, "singular");
    }

    #[test]
    fn fisher_validation_and_determinism() {
        assert_eq!(fisher_se(&[], 0, &[]).unwrap_err().topic, "argument");
        assert_eq!(fisher_se(&W2, 3, &[1.0]).unwrap_err().topic, "argument");
        assert_eq!(
            fisher_se(&W2, 2, &[1.0]).unwrap_err().topic,
            "argument",
            "count mismatch"
        );
        let err = fisher_se(&W2, 2, &[-1.0, 5.0]).unwrap_err();
        assert_eq!((err.topic.as_str(), err.i), ("argument", Some(1)));
        let err = fisher_se(&[f64::NAN, 0.5, 0.1, 0.5], 2, &[1.0, 1.0]).unwrap_err();
        assert_eq!((err.topic.as_str(), err.i), ("na", Some(1)));
        // Bit-identical repeat (both the values and the support).
        let a = fisher_se(&W2, 2, &[25.0, 100.0]).unwrap();
        let b = fisher_se(&W2, 2, &[25.0, 100.0]).unwrap();
        assert_eq!(a, b);
    }

    // ==================================================================
    // Zeroing rules
    // ==================================================================

    #[test]
    fn zeroing_share_mask_basic_rule() {
        // Shares (0.9, 0.09, 0.01): only the 0.01 share is below 0.05.
        let mask = zeroing_mask_share(&[900.0, 90.0, 10.0], MUSICAL_THRESH_SHARE).unwrap();
        assert_eq!(mask, vec![false, false, true]);
        // Sigfit-family anchor value 0.01 on the same vector: 0.01 < 0.01
        // is false (strict), 0.09 and 0.9 survive.
        let mask = zeroing_mask_share(&[900.0, 90.0, 10.0], SIGFIT_ZERO_SHARE).unwrap();
        assert_eq!(mask, vec![false, false, false]);
    }

    #[test]
    fn zeroing_share_strict_inequality_boundary() {
        // A share exactly at the threshold survives (strict <).
        let mask = zeroing_mask_share(&[0.5, 0.5], 0.5).unwrap();
        assert_eq!(mask, vec![false, false]);
        // Just below is zeroed.
        let mask = zeroing_mask_share(&[0.75, 0.25], 0.5).unwrap();
        assert_eq!(mask, vec![false, true]);
        // Degenerate thresholds: 0 zeroes only exact zeros; 1 zeroes every
        // component whose share is strictly below 1 (a lone survivor with
        // share 1.0 stays).
        assert_eq!(
            zeroing_mask_share(&[0.0, 10.0], 0.0).unwrap(),
            vec![true, false]
        );
        assert_eq!(
            zeroing_mask_share(&[0.0, 10.0], 1.0).unwrap(),
            vec![true, false]
        );
    }

    #[test]
    fn zeroing_mutations_mask_absolute_rule() {
        // COSMIC-style "< 10 mutations" anchor (strict <).
        let mask = zeroing_mask_mutations(&[5.0, 10.0, 500.0], COSMIC_ZERO_MUTATIONS).unwrap();
        assert_eq!(mask, vec![true, false, false]);
        // Strictness at the threshold: 0.5 < 0.5 is false.
        assert_eq!(
            zeroing_mask_mutations(&[0.0, 0.5], 0.5).unwrap(),
            vec![true, false]
        );
    }

    #[test]
    fn zeroing_handles_zero_and_empty_exposures() {
        // All-zero exposures: total = 0, shares defined as 0 → all zeroed,
        // no division by zero.
        assert_eq!(
            zeroing_mask_share(&[0.0, 0.0], 0.05).unwrap(),
            vec![true, true]
        );
        // Exact zeros inside a live vector are always zeroed.
        assert_eq!(
            zeroing_mask_share(&[0.0, 100.0], 0.0).unwrap(),
            vec![true, false]
        );
        // Empty input → empty mask (no error).
        assert!(zeroing_mask_share(&[], 0.05).unwrap().is_empty());
        assert!(zeroing_mask_mutations(&[], 10.0).unwrap().is_empty());
    }

    #[test]
    fn zeroing_anchor_constants_are_the_documented_values() {
        assert_eq!(SIGFIT_ZERO_SHARE, 0.01);
        assert_eq!(MUSICAL_THRESH_SHARE, 0.05);
        assert_eq!(COSMIC_ZERO_MUTATIONS, 10.0);
    }

    #[test]
    fn zeroing_validation_errors_are_structured() {
        let err = zeroing_mask_share(&[-1.0], 0.05).unwrap_err();
        assert_eq!((err.topic.as_str(), err.i), ("argument", Some(1)));
        assert_eq!(
            zeroing_mask_share(&[f64::NAN], 0.05).unwrap_err().topic,
            "na"
        );
        assert_eq!(
            zeroing_mask_share(&[1.0], 1.5).unwrap_err().topic,
            "argument"
        );
        assert_eq!(
            zeroing_mask_share(&[1.0], -0.1).unwrap_err().topic,
            "argument"
        );
        assert_eq!(
            zeroing_mask_share(&[1.0], f64::NAN).unwrap_err().topic,
            "argument"
        );
        let err = zeroing_mask_mutations(&[-3.0], 10.0).unwrap_err();
        assert_eq!((err.topic.as_str(), err.i), ("argument", Some(1)));
        assert_eq!(
            zeroing_mask_mutations(&[1.0], -1.0).unwrap_err().topic,
            "argument"
        );
    }

    // ==================================================================
    // Cross-module determinism (bit-stability of a full pipeline pass)
    // ==================================================================

    #[test]
    fn full_pipeline_pass_is_bit_identical() {
        // The U-M3a-01 surface in one pass: LLs → LRT p → Fisher SE →
        // zeroing mask. Same input, two runs, identical bits everywhere.
        let run = || -> (f64, f64, f64, Vec<f64>, Vec<bool>) {
            let counts = [137.0, 0.0, 12.0];
            let probs = [0.6, 0.1, 0.3];
            let means = [80.0, 10.0, 30.0];
            let ll_m = multinomial_ll(&counts, &probs).unwrap();
            let ll_nb = nb_ll(&counts, &means, NB_SIZE_SBS96).unwrap();
            let p = p_chisq1_lrt(ll_m, ll_nb);
            let fit = fisher_se(&W2, 2, &[25.0, 100.0]).unwrap();
            let mask = zeroing_mask_share(&[25.0, 0.0, 100.0], 0.05).unwrap();
            (ll_m, ll_nb, p, fit.se.clone(), mask)
        };
        assert_eq!(run(), run());
    }
}
