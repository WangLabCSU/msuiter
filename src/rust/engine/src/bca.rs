//! BCa (bias-corrected and accelerated) bootstrap intervals for signature
//! exposures (U-M3b-02; design memo `docs/devlog/2026-10-04-M3b-design-memo.md`
//! §1.2, PI ruling: BCa default, percentile as the degenerate fallback).
//!
//! # The interval (Hall 1988, Ann. Statist. 16(3):927–985,
//! doi:10.1214/aos/1176350930; Efron 1987, JASA 82:171–185)
//!
//! Given the point estimate `θ̂`, the `B` bootstrap replicates `θ*_b`
//! (shared with the percentile face — **zero extra resampling**), and the
//! acceleration `a` below, the BCa interval at nominal level pair
//! `(α_lo, α_hi)` is the type-7 quantiles of the boot sample at the
//! *corrected* levels
//!
//! ```text
//! z₀     = Φ⁻¹( #{b : θ*_b < θ̂} / B )
//! α_corr = Φ( z₀ + (z₀ + z_α) / (1 − a·(z₀ + z_α)) ),   z_α = Φ⁻¹(α)
//! [q_type7(α_corr,lo), q_type7(α_corr,hi)]
//! ```
//!
//! `z₀` corrects median bias, `a` corrects skewness of the influence
//! distribution; with `z₀ = a = 0` the formula collapses exactly to the
//! percentile interval (α_corr = α), which is why the degenerate fallback
//! below is *arithmetically* the same map the percentile face uses.
//!
//! # The fixed-active-set analytic jackknife (the memo-frozen `a`)
//!
//! Let `A` be the point fit's support (`support = 1` signatures) and
//! `v ∈ ℝ^m` the sample's channel counts. On the interior (`θ̂ ≫ 0`, `A`
//! fixed) the exposure solve is the **linear** map
//!
//! ```text
//! θ(v) = h_A = G_A⁻¹ b_A,   G_A = S_Aᵀ S_A,   b_A = S_Aᵀ v,
//! ```
//!
//! so the leave-one-**mutation**-out estimate is *exact* (not an
//! infinitesimal approximation): removing one mutation at channel `c`
//! sends `v → v − e_c`, hence
//!
//! ```text
//! θ_(−mut@c) = θ̂ − u_c,   u_c = G_A⁻¹ s_A[c] = ∂θ/∂v_c ,
//! ```
//!
//! with `s_A[c]` the `c`-th channel row of `S_A` (k_A-vector). All `u_c`
//! come from **one** pivoted LDLᵀ of `G_A` (k_A right-hand sides,
//! `engine::linalg`), never a per-mutation refit. The jackknife average is
//! `θ̄_(−) = θ̂ − ū` with `ū = Σ_c (v_c/V)·u_c`, `V = Σ_c v_c`, so the
//! Efron jackknife deviations are `θ̄_(−) − θ_(−mut@c) = u_c − ū` and the
//! acceleration (summing per-mutation deviations with multiplicity `w_c =
//! v_c`, the channel counts) is
//!
//! ```text
//! a = Σ_c v_c·(u_c − ū)³ / (6·(Σ_c v_c·(u_c − ū)²)^{3/2}) ,
//! ```
//!
//! returned per active signature (each component of `u` is jackknifed
//! independently). `a` is invariant under positive rescaling of `u`.
//! Documented approximation: the acceleration reads the **raw** interior
//! map above (frozen memo semantics); the TMB rescale's differential term
//! (`θ' = θ·T/(1ᵀh_A)` is a ratio of linear functions of `v`) is omitted —
//! the empirical coverage measurement of U-M3b-03 is the arbiter, with the
//! memo's escalation ladder behind it.
//!
//! # Degenerate fallback (frozen thresholds, FFI-visible constants)
//!
//! The cell falls back to the percentile interval (i.e. the corrected
//! levels ARE the nominal ones and the flag column records it) iff any of:
//!
//! * `|ẑ₀| < [`BCA_Z0_FLAT`] ∧ |â| < [`BCA_A_FLAT`]` — the correction is
//!   smaller than the MC noise of `B = 1000` bounds (PI ruling, memo §1.2
//!   row 1);
//! * `|â| > [`BCA_A_MAX`]` — influence function unreliable (memo row 3);
//! * `support_stability < [`BCA_STABILITY_MIN`]` — unstable active set
//!   (memo row 3);
//! * boundary cell (point `support = 0` — no interior, no influence map;
//!   the "boundary parameters get tests, not intervals" discipline);
//! * `G_A` singular, an empty active set, or a zero-count sample;
//! * non-finite inputs or a non-increasing corrected level pair (ordering
//!   guard, possible when the denominator `1 − a(z₀+z_α)` turns small).
//!
//! `h₀` is clamped to `[`H0_GUARD`, 1 − `H0_GUARD`]` so `z₀` is always
//! finite (`boot` all on one side gives `|z₀| ≤ 5.62`, not `±∞`). The
//! clamp replaces the sketch "add 1e-8" (which breaks at `h₀ = 1` —
//! `Φ⁻¹(1 + 1e-8)` is NaN); both express the same interior guard.
//!
//! # Normal special functions (zero new dependencies)
//!
//! `Φ` follows the audited `likelihood::erfc` path: `Φ(z) = ½·erfc(−z/√2)`.
//! `Φ⁻¹` is self-implemented: Acklam's rational approximation (max raw
//! relative error ≈ 1.15e-9) polished by one Halley step against `Φ`
//! (documented relative error ≈ 1e-13 on `p ∈ [1e-15, 1−1e-15]`, pinned
//! against R `qnorm` anchors; `erfc`'s accuracy is the binding constraint).
//!
//! # Independent implementation anchor
//!
//! The z₀ / level-correction / type-7 arithmetic was cross-checked against
//! R (`pnorm`/`qnorm`/`quantile(type=7)`) on the literature case — the
//! mean of `n = 12` Exp(1) draws (skew ≈ 1.77, jackknife `a = 0.085`) with
//! a `B = 200` fixed-seed boot sample: the hand formula is the
//! bit-exact anchor (audited), pinned in this module's tests.
//! `boot::boot.ci(type = "bca")` agrees only qualitatively on the same
//! data (bounds differ ~1e-2–2e-1 *relative*: `boot` interpolates on the
//! `(R+1)·α` order-statistic grid vs type-7 here, and B = 200 puts the
//! 0.9914 corrected level between the 199th/200th order statistics — an
//! earlier draft claiming ~3e-4 was not reproducible, audited).
//!
//! # Determinism
//!
//! Pure sequential kernels over fixed-order reductions: identical inputs
//! give bit-identical outputs on a given toolchain.

use crate::error::MsError;
use crate::likelihood::erfc;
use crate::linalg::Ldlt;

/// Interior clamp of the bias proportion `h₀` (see module docs): keeps
/// `Φ⁻¹` finite when every boot replicate sits on one side of `θ̂`.
pub const H0_GUARD: f64 = 1e-8;

/// Degeneracy band: `|ẑ₀| < BCA_Z0_FLAT` together with `|â| < BCA_A_FLAT`
/// means the BCa correction is below the `B = 1000` MC noise of the
/// bounds — the cell falls back to the percentile interval (PI ruling,
/// memo §1.2 row 1; thresholds frozen here and in the protocol docs).
pub const BCA_Z0_FLAT: f64 = 0.1;

/// Degeneracy band partner of [`BCA_Z0_FLAT`] (see its docs).
pub const BCA_A_FLAT: f64 = 0.05;

/// Hard acceleration cap: `|â| > BCA_A_MAX` means the fixed-active-set
/// influence function is unreliable (memo §1.2 row 3) — percentile
/// fallback with the flag column set.
pub const BCA_A_MAX: f64 = 0.2;

/// Support-stability floor: a cell whose point-fit support survives fewer
/// than this fraction of boots has an unstable active set (memo §1.2 row
/// 3) — percentile fallback with the flag column set.
pub const BCA_STABILITY_MIN: f64 = 0.9;

/// Standard normal CDF `Φ(z)`, via the audited `likelihood::erfc` path:
/// `Φ(z) = ½·erfc(−z/√2)`. Accuracy inherits `erfc`'s (relative error well
/// below 1e-13); NaN propagates.
pub fn phi(z: f64) -> f64 {
    0.5 * erfc(-z / std::f64::consts::SQRT_2)
}

/// Acklam's rational approximation to `Φ⁻¹` (P. J. Acklam's published
/// coefficients; max raw relative error ≈ 1.15e-9 over the open unit
/// interval). Central branch for `0.02425 ≤ p ≤ 0.97575`, rational tails
/// outside.
fn phi_inv_acklam(p: f64) -> f64 {
    const A: [f64; 6] = [
        -3.969_683_028_665_376e1,
        2.209_460_984_245_205e2,
        -2.759_285_104_469_687e2,
        1.383_577_518_672_69e2,
        -3.066_479_806_614_716e1,
        2.506_628_277_459_239,
    ];
    const B: [f64; 5] = [
        -5.447_609_879_822_406e1,
        1.615_858_368_580_409e2,
        -1.556_989_798_598_866e2,
        6.680_131_188_771_972e1,
        -1.328_068_155_288_572e1,
    ];
    const C: [f64; 6] = [
        -7.784_894_002_430_293e-3,
        -3.223_964_580_411_365e-1,
        -2.400_758_277_161_838,
        -2.549_732_539_343_734,
        4.374_664_141_464_968,
        2.938_163_982_698_783,
    ];
    const D: [f64; 4] = [
        7.784_695_709_041_462e-3,
        3.224_671_290_700_398e-1,
        2.445_134_137_142_996,
        3.754_408_661_907_416,
    ];
    const P_LOW: f64 = 0.024_25;
    if p < P_LOW {
        // Lower tail: q = √(−2 ln p).
        let q = (-2.0 * p.ln()).sqrt();
        (((((C[0] * q + C[1]) * q + C[2]) * q + C[3]) * q + C[4]) * q + C[5])
            / ((((D[0] * q + D[1]) * q + D[2]) * q + D[3]) * q + 1.0)
    } else if p <= 1.0 - P_LOW {
        // Central branch.
        let q = p - 0.5;
        let r = q * q;
        (((((A[0] * r + A[1]) * r + A[2]) * r + A[3]) * r + A[4]) * r + A[5]) * q
            / (((((B[0] * r + B[1]) * r + B[2]) * r + B[3]) * r + B[4]) * r + 1.0)
    } else {
        // Upper tail via the Φ⁻¹(p) = −Φ⁻¹(1−p) symmetry.
        let q = (-2.0 * (1.0 - p).ln()).sqrt();
        -(((((C[0] * q + C[1]) * q + C[2]) * q + C[3]) * q + C[4]) * q + C[5])
            / ((((D[0] * q + D[1]) * q + D[2]) * q + D[3]) * q + 1.0)
    }
}

/// Inverse standard normal CDF `Φ⁻¹(p)`: Acklam's rational approximation
/// polished by one Halley step against [`phi`]. Documented relative error
/// ≈ 1e-13 on the clamped domain (erfc-accuracy-limited); pinned against
/// R `qnorm` anchors. Domain: `p` is clamped to `[1e-15, 1 − 1e-15]`
/// (`|z| ≤ 8`, far outside every caller's range; NaN propagates).
pub fn phi_inv(p: f64) -> f64 {
    if p.is_nan() {
        return f64::NAN;
    }
    let p = p.clamp(1e-15, 1.0 - 1e-15);
    // Work on the lower half and mirror: keeps the Halley step in the
    // well-conditioned branch for every input.
    let (mirror, q) = if p > 0.5 { (true, 1.0 - p) } else { (false, p) };
    let mut z = phi_inv_acklam(q);
    // Halley refinement (the cubic Newton): with e = Φ(z) − q, the update
    // u = e·√(2π)·exp(z²/2) cancels φ(z)'s exponential.
    let e = phi(z) - q;
    let u = e * (2.0 * std::f64::consts::PI).sqrt() * (z * z / 2.0).exp();
    z -= u / (1.0 + z * u / 2.0);
    if mirror {
        -z
    } else {
        z
    }
}

/// Corrected quantile levels of one cell's BCa interval.
///
/// `alpha_lower` / `alpha_upper` are the levels the caller feeds to its
/// type-7 quantile routine over the boot sample: on the BCa path they are
/// the Hall-corrected `α_corr`, on the fallback path they are EXACTLY the
/// nominal `levels` the caller passed in — so the fallback arithmetic is
/// bit-identical to the percentile face by construction.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BcaLevels {
    /// Corrected (or, on fallback, nominal) lower quantile level.
    pub alpha_lower: f64,
    /// Corrected (or, on fallback, nominal) upper quantile level.
    pub alpha_upper: f64,
    /// `true` = the cell took the percentile fallback path (any rule of
    /// the module-docs list); surfaces as the explicit flag column.
    pub fallback: bool,
}

/// BCa corrected levels for one (signature, sample) cell.
///
/// `point` is `θ̂`, `boot_sorted` the ascending boot replicates `θ*_b`
/// (len ≥ 1), `accel` the cell's acceleration `a` (from
/// [`analytic_acceleration`]), `levels` the nominal `(α_lo, α_hi)` pair,
/// `stability` the cell's boot support stability, `supported` whether the
/// point fit kept the signature (`support = 1`). Never panics: every
/// degenerate input routes to the percentile fallback (see module docs).
pub fn bca_levels(
    point: f64,
    boot_sorted: &[f64],
    accel: f64,
    levels: (f64, f64),
    stability: f64,
    supported: bool,
) -> BcaLevels {
    let fallback = || BcaLevels {
        alpha_lower: levels.0,
        alpha_upper: levels.1,
        fallback: true,
    };
    // Boundary cells, unstable supports, and degenerate boot samples have
    // no honest BCa: the percentile face IS the answer (flagged).
    if !supported || boot_sorted.is_empty() || stability < BCA_STABILITY_MIN {
        return fallback();
    }
    if !accel.is_finite() || !point.is_finite() {
        return fallback();
    }
    // Bias proportion (module docs): boot values are ascending, so the
    // strict-less count is a partition point.
    let n_less = boot_sorted.partition_point(|&b| b < point);
    // Audited P1 (PI-frozen criterion row 3): boot all on ONE side of the
    // point estimate (n_less == 0 or == B) means z0 = ±∞ — the h0 clamp
    // below would keep the cell on the BCa path with a degenerate interval
    // pinned at the boot extremes. Fall back to percentile + flag instead.
    if n_less == 0 || n_less == boot_sorted.len() {
        return fallback();
    }
    let h0 = (n_less as f64) / (boot_sorted.len() as f64);
    let h0 = h0.clamp(H0_GUARD, 1.0 - H0_GUARD);
    let z0 = phi_inv(h0);
    let a = accel;
    // PI degeneracy band + memo hard cap: below the B=1000 MC noise, or
    // an influence function past its reliability boundary.
    if z0.abs() < BCA_Z0_FLAT && a.abs() < BCA_A_FLAT {
        return fallback();
    }
    if a.abs() > BCA_A_MAX {
        return fallback();
    }
    let z_lo = phi_inv(levels.0);
    let z_hi = phi_inv(levels.1);
    let corrected = |z_alpha: f64| -> Option<f64> {
        let denom = 1.0 - a * (z0 + z_alpha);
        if !denom.is_finite() || denom <= 0.0 {
            return None;
        }
        let alpha = phi(z0 + (z0 + z_alpha) / denom);
        if alpha.is_finite() && alpha > 0.0 && alpha < 1.0 {
            Some(alpha)
        } else {
            None
        }
    };
    let (lo, hi) = match (corrected(z_lo), corrected(z_hi)) {
        (Some(lo), Some(hi)) if lo <= hi => (lo, hi),
        _ => return fallback(),
    };
    BcaLevels {
        alpha_lower: lo,
        alpha_upper: hi,
        fallback: false,
    }
}

/// Analytic jackknife acceleration `a` for the active signatures of one
/// sample (the memo-frozen fixed-active-set influence function; the full
/// derivation is in the module docs).
///
/// Inputs: `gram` the FULL row-major k×k Gram `SᵀS` (the bootstrap
/// driver's shared matrix — the active submatrix is read here, never
/// refactored twice), `sigs` the row-major m×k signature matrix, `counts`
/// the sample's channel counts (m, finite, non-negative), `active` the
/// ascending point-fit support indices (`support = 1`, each `< k`).
/// Returns the acceleration per active signature (same order).
///
/// Errors: argument-shaped on empty/zero-count/malformed input (the
/// caller falls back to the percentile face); the `linalg` "singular"
/// error propagates when `G_A` is singular (collinear active signatures —
/// no interior influence map).
pub fn analytic_acceleration(
    gram: &[f64],
    sigs: &[f64],
    counts: &[f64],
    m: usize,
    k: usize,
    active: &[usize],
) -> Result<Vec<f64>, MsError> {
    if gram.len() != k * k {
        return Err(MsError::new("argument", "Gram storage must be k*k elements")
            .with_i(gram.len() as i64));
    }
    if sigs.len() != m * k || counts.len() != m {
        return Err(MsError::new(
            "argument",
            "signatures/counts must be m*k and m elements",
        ));
    }
    let k_a = active.len();
    if k_a == 0 {
        return Err(MsError::new("argument", "empty active set has no influence map"));
    }
    if active.windows(2).any(|w| w[0] >= w[1]) || active[k_a - 1] >= k {
        return Err(MsError::new(
            "argument",
            "active set must be strictly ascending indices below k",
        ));
    }
    for (i, &v) in counts.iter().enumerate() {
        if !v.is_finite() || v < 0.0 {
            return Err(MsError::new(
                "argument",
                "channel counts must be finite and >= 0",
            )
            .with_i(i as i64 + 1));
        }
    }
    let total: f64 = counts.iter().sum();
    if total <= 0.0 {
        return Err(MsError::new("argument", "zero-count sample has no jackknife"));
    }
    // Active submatrix G_A = S_Aᵀ S_A (read from the shared Gram).
    let mut g_a = vec![0.0f64; k_a * k_a];
    for (p, &ap) in active.iter().enumerate() {
        for (q, &aq) in active.iter().enumerate() {
            g_a[p * k_a + q] = gram[ap * k + aq];
        }
    }
    // ONE pivoted LDLᵀ of G_A solves every channel's u_c = G_A⁻¹ s_A[c].
    let factor = Ldlt::factor(&g_a, k_a)?;
    let mut u = vec![0.0f64; k_a * m]; // row-major k_a × m: u[a*m + c]
    for c in 0..m {
        let s_c: Vec<f64> = active.iter().map(|&a| sigs[c * k + a]).collect();
        let u_c = factor.solve(&s_c)?;
        for a in 0..k_a {
            u[a * m + c] = u_c[a];
        }
    }
    // Weighted central moments of the per-mutation influence (w_c = v_c):
    // a = Σ w(u−ū)³ / (6 (Σ w(u−ū)²)^{3/2}); a flat influence (all u_c
    // equal — e.g. a single-signature ones dictionary) has zero variance
    // and yields a = 0 by definition, not NaN.
    let mut accels = Vec::with_capacity(k_a);
    for a in 0..k_a {
        let row = &u[a * m..(a + 1) * m];
        let mean: f64 = (0..m).map(|c| counts[c] * row[c]).sum::<f64>() / total;
        let mut m2 = 0.0f64;
        let mut m3 = 0.0f64;
        for c in 0..m {
            let d = row[c] - mean;
            m2 += counts[c] * d * d;
            m3 += counts[c] * d * d * d;
        }
        let accel = if m2 > 0.0 {
            m3 / (6.0 * m2 * m2.sqrt())
        } else {
            0.0
        };
        accels.push(accel);
    }
    Ok(accels)
}

// ======================================================================
// Tests: R-anchored goldens (pnorm/qnorm anchors, the Exp(1)-mean BCa
// classic), fallback threshold semantics, the numeric leave-one-out
// cross-check of the analytic influence, monotonicity/continuity,
// degeneracy paths, determinism. Fixed data only — no resampling here
// (the boot sample below is a frozen R-generated fixture, module docs).
// ======================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::nnls::{nnls_gram, NnlsOptions};

    fn assert_close(actual: f64, expected: f64, rel: f64, what: &str) {
        let scale = expected.abs().max(1e-300);
        assert!(
            (actual - expected).abs() <= rel * scale,
            "{what}: actual {actual}, expected {expected}"
        );
    }

    /// The classic BCa literature case (module docs): the mean of n = 12
    /// Exp(1) draws — a right-skewed statistic where the percentile
    /// interval is visibly wrong and BCa is the fix. Data and the B = 200
    /// boot sample are a FROZEN R fixture (set.seed(4242) /
    /// round(rexp(12), 4) + set.seed(777) / replicate(200, ...), R 4.5.2);
    /// θ̂ = 0.89616666666666667 and the
    /// observation-level jackknife acceleration a = 0.085022443718641275
    /// are R-computed on the same data.
    const EXP_THETA: f64 = 0.896_166_666_666_666_7;
    const EXP_ACCEL: f64 = 0.085_022_443_718_641_27;
    const EXP_BOOT: [f64; 200] = [
        0.259_258_333_333_333_3, 0.261_225, 0.27813333333333334, 0.283_716_666_666_666_7,
        0.34468333333333334, 0.35934166666666667, 0.36006666666666665, 0.405_825,
        0.416_025, 0.426_775, 0.430_691_666_666_666_7, 0.43811666666666665,
        0.4412416666666667, 0.454_75, 0.46492500000000003, 0.465_491_666_666_666_7,
        0.475_216_666_666_666_7, 0.479, 0.47991666666666666, 0.487_058_333_333_333_3,
        0.4917083333333333, 0.498_366_666_666_666_7, 0.50405, 0.5041916666666667,
        0.507_991_666_666_666_7, 0.509_533_333_333_333_3, 0.514_058_333_333_333_3, 0.5309666666666667,
        0.533_241_666_666_666_6, 0.535_45, 0.543_533_333_333_333_3, 0.546_5,
        0.560_7, 0.572_666_666_666_666_7, 0.588_041_666_666_666_7, 0.588_233_333_333_333_4,
        0.593_65, 0.601_966_666_666_666_6, 0.611_558_333_333_333_3, 0.6171416666666667,
        0.618_716_666_666_666_7, 0.6488666666666667, 0.649_133_333_333_333_3, 0.656_383_333_333_333_3,
        0.658_891_666_666_666_7, 0.665_65, 0.667_841_666_666_666_7, 0.668_558_333_333_333_4,
        0.6751583333333333, 0.690_35, 0.692_091_666_666_666_7, 0.6993166666666667,
        0.700_908_333_333_333_4, 0.704_241_666_666_666_7, 0.711_8, 0.713_533_333_333_333_4,
        0.716_150_000_000_000_1, 0.716_333_333_333_333_4, 0.722_449_999_999_999_9, 0.722_958_333_333_333_3,
        0.724_733_333_333_333_3, 0.726_7, 0.731_975, 0.732325,
        0.739_458_333_333_333_3, 0.742_4, 0.751_875, 0.7562416666666667,
        0.762_108_333_333_333_3, 0.762_833_333_333_333_3, 0.768_741_666_666_666_7, 0.768_783_333_333_333_3,
        0.772_841_666_666_666_6, 0.781_433_333_333_333_3, 0.793_866_666_666_666_6, 0.796_258_333_333_333_3,
        0.798_958_333_333_333_3, 0.799_058_333_333_333_3, 0.799_808_333_333_333_3, 0.799_991_666_666_666_7,
        0.804_3, 0.805_675, 0.807_2, 0.812_15,
        0.821_125, 0.823_441_666_666_666_6, 0.841_208_333_333_333_3, 0.841_616_666_666_666_7,
        0.846_116_666_666_666_6, 0.85, 0.851_250_000_000_000_1, 0.854_883_333_333_333_3,
        0.860_408_333_333_333_3, 0.866_416_666_666_666_6, 0.870_216_666_666_666_6, 0.871_708_333_333_333_3,
        0.872_608_333_333_333_3, 0.876_416_666_666_666_7, 0.879_008_333_333_333_3, 0.879_766_666_666_666_6,
        0.891_933_333_333_333_4, 0.900_241_666_666_666_6, 0.905_333_333_333_333_3, 0.908_958_333_333_333_3,
        0.914_958_333_333_333_3, 0.916_508_333_333_333_4, 0.919_283_333_333_333_3, 0.920_183_333_333_333_4,
        0.924_524_999_999_999_9, 0.925_033_333_333_333_3, 0.925_575, 0.926_233_333_333_333_4,
        0.936_566_666_666_666_5, 0.937025, 0.939_316_666_666_666_7, 0.940_341_666_666_666_6,
        0.956_241_666_666_666_7, 0.958_908_333_333_333_4, 0.962_449_999_999_999_9, 0.991_325,
        0.994_100_000_000_000_1, 0.994_866_666_666_666_7, 0.995_625, 0.999_208_333_333_333_4,
        0.999_383_333_333_333_3, 1.0048583333333334, 1.0119, 1.0167583333333332, 1.016975,
        1.016975, 1.0309333333333333, 1.035_8, 1.0421166666666666,
        1.0423916666666666, 1.0446833333333334, 1.0467333333333333, 1.0504166666666666,
        1.055_125, 1.064_825, 1.0799333333333334, 1.0836000000000001,
        1.0877916666666667, 1.0926666666666667, 1.0986666666666667, 1.1053083333333333,
        1.1095916666666665, 1.1171333333333333, 1.1215583333333332, 1.1281583333333334,
        1.1307916666666666, 1.1534666666666666, 1.158_7, 1.1599249999999999,
        1.174925, 1.1757, 1.178275, 1.1811666666666667, 1.1813166666666666,
        1.1826833333333333, 1.1845833333333333, 1.1883916666666665, 1.1907916666666667,
        1.1937416666666667, 1.1960416666666667, 1.1987583333333334, 1.1988083333333333,
        1.202_15, 1.2030416666666666, 1.2173916666666666, 1.2193416666666668,
        1.2331583333333334, 1.2357083333333334, 1.2499, 1.2559833333333332,
        1.265_65, 1.28755, 1.2965416666666667, 1.3034333333333332,
        1.3258666666666667, 1.32975, 1.3379833333333333, 1.3825583333333333,
        1.4016166666666667, 1.4431916666666667, 1.460_15, 1.464_675,
        1.4838583333333333, 1.4841833333333334, 1.5371583333333332, 1.5504833333333334,
        1.5543583333333333, 1.5620833333333333, 1.5649916666666666, 1.5890166666666665,
        1.5916583333333334, 1.6077416666666666, 1.6400916666666667, 1.6773333333333333,
        1.85175, 2.056_825,
    ];

    /// Type-7 quantile (the R `quantile` default; the same routine
    /// `fit.rs` applies the corrected levels with).
    fn type7(sorted: &[f64], p: f64) -> f64 {
        let len = sorted.len();
        if len == 1 {
            return sorted[0];
        }
        let pos = p * (len - 1) as f64;
        let lo = pos.floor() as usize;
        let hi = (lo + 1).min(len - 1);
        let frac = pos - lo as f64;
        sorted[lo] + frac * (sorted[hi] - sorted[lo])
    }

    #[test]
    fn phi_matches_r_pnorm_anchors() {
        // R 4.5.2 pnorm anchors (17 significant digits).
        assert_close(phi(0.0), 0.5, 1e-15, "phi(0)");
        assert_close(phi(0.5), 0.691_462_461_274_013, 1e-13, "phi(0.5)");
        assert_close(
            phi(-1.959_963_984_540_054_5),
            0.024_999_999_999_999_988,
            1e-13,
            "phi(-1.96)",
        );
        assert_close(phi(3.0), 0.998_650_101_968_369_9, 1e-13, "phi(3)");
        // Tails decay via erfc (no underflow surprise on the BCa domain).
        assert_close(phi(-8.0), 6.220_960_574_271_78e-16, 1e-12, "phi(-8)");
        assert!(phi(f64::NAN).is_nan());
    }

    #[test]
    fn phi_inv_matches_r_qnorm_anchors() {
        // R 4.5.2 qnorm anchors (17 significant digits).
        assert_close(phi_inv(0.5), 0.0, 1e-12, "qnorm(0.5)");
        assert_close(phi_inv(0.6), 0.253_347_103_135_799_8, 1e-12, "qnorm(0.6)");
        assert_close(phi_inv(0.025), -1.959_963_984_540_053_8, 1e-12, "qnorm(0.025)");
        assert_close(phi_inv(0.975), 1.959_963_984_540_053_4, 1e-12, "qnorm(0.975)");
        assert_close(phi_inv(0.001), -3.090_232_306_167_813, 1e-11, "qnorm(0.001)");
        assert_close(phi_inv(0.999), 3.090_232_306_167_813, 1e-11, "qnorm(0.999)");
        assert_close(phi_inv(1e-8), -5.612_001_244_174_788, 1e-9, "qnorm(1e-8)");
        // Symmetry and round-trip.
        assert_close(phi_inv(0.3), -phi_inv(0.7), 1e-13, "phi_inv symmetry");
        for &p in &[0.01, 0.2, 0.5, 0.77, 0.95, 0.999] {
            assert_close(phi(phi_inv(p)), p, 1e-12, "phi∘phi_inv round-trip");
        }
    }

    #[test]
    fn bca_matches_the_r_reference_golden_on_the_exponential_mean() {
        // The R hand formula (independent implementation: R pnorm/qnorm +
        // quantile(type = 7)) on the frozen fixture above:
        //   h0 = 0.505, z0 = qnorm(0.505) = 0.012533469508069274,
        //   alpha1 = 0.048632939707922325, alpha2 = 0.99140194902923207,
        //   bca bounds [0.4294303237573498, 1.727737632026531]
        // (percentile would give [0.35897520833333335, 1.592060416666667]
        // — the BCa correction visibly re-centers the skewed interval).
        let lv = bca_levels(EXP_THETA, &EXP_BOOT, EXP_ACCEL, (0.025, 0.975), 1.0, true);
        assert!(!lv.fallback, "a = 0.085 must keep the BCa path");
        let z0 = phi_inv(0.505);
        assert_close(z0, 0.012_533_469_508_069_274, 1e-11, "z0");
        assert_close(lv.alpha_lower, 0.048_632_939_707_922_325, 1e-10, "alpha1");
        assert_close(lv.alpha_upper, 0.991_401_949_029_232_1, 1e-10, "alpha2");
        let lo = type7(&EXP_BOOT, lv.alpha_lower);
        let hi = type7(&EXP_BOOT, lv.alpha_upper);
        assert_close(lo, 0.429_430_323_757_349_8, 1e-9, "bca_lower");
        assert_close(hi, 1.727_737_632_026_531, 1e-9, "bca_upper");
        // And the correction really moved the interval (percentile face):
        assert!(lo > type7(&EXP_BOOT, 0.025));
        assert!(hi > type7(&EXP_BOOT, 0.975));
    }

    #[test]
    fn bca_degenerate_band_falls_back_to_exact_percentile_levels() {
        // Threshold semantics of the PI ruling: fallback iff
        // |z0| < 0.1 AND |a| < 0.05. Grid boot values 1.00..1.99; a point
        // between the 53rd and 54nd order statistic gives h0 = 0.53,
        // z0 ≈ 0.0753 (< 0.1).
        let boot: Vec<f64> = (0..100).map(|i| 1.0 + (i as f64) * 0.01).collect();
        let point = 1.5255f64; // 53 strict-less of 100
        assert!((boot.partition_point(|&b| b < point) as f64 / 100.0 - 0.53).abs() < 1e-12);
        // Small but non-degenerate correction: BCa keeps the path and
        // shifts both corrected levels upward (z0 > 0).
        let lv = bca_levels(point, &boot, 0.06, (0.025, 0.975), 1.0, true);
        assert!(!lv.fallback);
        assert!(lv.alpha_lower > 0.025 && lv.alpha_upper > 0.975);
        // a inside the band with z0 already below it: fallback, and the
        // returned levels ARE the nominal pair (bit-identical percentile).
        let lv = bca_levels(point, &boot, 0.049, (0.025, 0.975), 1.0, true);
        assert!(lv.fallback);
        assert_eq!(lv.alpha_lower.to_bits(), 0.025f64.to_bits());
        assert_eq!(lv.alpha_upper.to_bits(), 0.975f64.to_bits());
        // z0 above the band keeps BCa even with a small a (the frozen AND
        // rule): 62 strict-less -> h0 = 0.62, z0 ≈ 0.3055 ≥ 0.1.
        let point_hi = 1.6155f64;
        let lv = bca_levels(point_hi, &boot, 0.049, (0.025, 0.975), 1.0, true);
        assert!(!lv.fallback, "z0 = {} must leave the band", phi_inv(0.62));
        // Band boundary: |a| = 0.05 exactly is NOT inside (strict <) —
        // no fallback with z0 < 0.1.
        let lv = bca_levels(point, &boot, 0.05, (0.025, 0.975), 1.0, true);
        assert!(!lv.fallback);
    }

    #[test]
    fn bca_stability_and_boundary_gates_fall_back() {
        let boot: Vec<f64> = (0..50).map(|i| 1.0 + (i as f64) * 0.1).collect();
        // Unstable support (memo row 3): flagged percentile.
        let lv = bca_levels(10.0, &boot, 0.15, (0.025, 0.975), 0.89, true);
        assert!(lv.fallback);
        assert_eq!(lv.alpha_lower.to_bits(), 0.025f64.to_bits());
        // Boundary cell (point support = 0): flagged percentile.
        let lv = bca_levels(0.0, &boot, 0.15, (0.025, 0.975), 1.0, false);
        assert!(lv.fallback);
        // Hard acceleration cap: |a| = 0.21 > 0.2 -> flagged percentile.
        let lv = bca_levels(10.0, &boot, 0.21, (0.025, 0.975), 1.0, true);
        assert!(lv.fallback);
        // Non-finite accel: defensive fallback, never NaN propagation.
        let lv = bca_levels(10.0, &boot, f64::NAN, (0.025, 0.975), 1.0, true);
        assert!(lv.fallback);
        // Empty boot sample: defensive fallback.
        let lv = bca_levels(10.0, &[], 0.15, (0.025, 0.975), 1.0, true);
        assert!(lv.fallback);
    }

    #[test]
    fn bca_all_identical_boot_values_falls_back_to_percentile() {
        // All boot values identical and equal to the point: n_less = 0 (no
        // strict-less) — audited P1 (PI-frozen criterion row 3): boot all
        // on one side means z0 = ±∞ and the h0 clamp would keep the cell
        // on the BCa path with a degenerate interval pinned at the boot
        // extremes. The correct behavior is the percentile fallback +
        // flag (the bounds still come out finite/ordered, but the caller
        // sees the flag and reports the degraded face).
        let boot = [3.0f64; 40];
        let lv = bca_levels(3.0, &boot, 0.0, (0.025, 0.975), 1.0, true);
        assert!(lv.fallback, "all-one-side boot must fall back");
        assert!(lv.alpha_lower.is_finite() && lv.alpha_upper.is_finite());
        assert!(lv.alpha_lower <= lv.alpha_upper);
        assert!(lv.alpha_lower >= 0.0 && lv.alpha_upper <= 1.0);
        assert_eq!(type7(&boot, lv.alpha_lower), 3.0);
        assert_eq!(type7(&boot, lv.alpha_upper), 3.0);
        // The zero-variance influence path: the acceleration primitive
        // returns a = 0 (not NaN) when every u_c is equal — the
        // single-signature ones-dictionary jackknife.
        let gram = [12.0f64];
        let sigs = [1.0f64; 12];
        let counts = [1.0f64; 12];
        let a = analytic_acceleration(&gram, &sigs, &counts, 12, 1, &[0]).unwrap();
        assert_eq!(a.len(), 1);
        assert_eq!(a[0].to_bits(), 0.0f64.to_bits());
    }

    #[test]
    fn bca_levels_are_continuous_and_monotone_across_the_level_grid() {
        // Sweep symmetric nominal pairs (p, 1−p) on the skewed fixture:
        // lower/upper bounds never decrease in p, and a 1e-9 perturbation
        // of the level moves the corrected level by < 1e-9 (continuity of
        // Φ(z0 + (z0+z)/(1−a(z0+z))) in z).
        let mut prev_lo = f64::NEG_INFINITY;
        let mut prev_hi = f64::INFINITY;
        for i in 1..99 {
            let p = i as f64 / 200.0; // 0.005 .. 0.495
            let lv = bca_levels(EXP_THETA, &EXP_BOOT, EXP_ACCEL, (p, 1.0 - p), 1.0, true);
            assert!(!lv.fallback);
            let lo = type7(&EXP_BOOT, lv.alpha_lower);
            let hi = type7(&EXP_BOOT, lv.alpha_upper);
            assert!(lo <= hi, "bounds crossed at p = {p}");
            // The pair (p, 1−p) moves BOTH nominal levels toward the
            // centre as p grows: the corrected lower level rises, the
            // corrected upper level falls (the correction map is
            // monotone in z_alpha, and z_alpha(1−p) falls in p).
            assert!(lo >= prev_lo, "lower bound must not decrease in p");
            assert!(hi <= prev_hi, "upper bound must not increase in p");
            prev_lo = lo;
            prev_hi = hi;
            if i % 7 == 0 {
                // Continuity across the special-function branch seams: a
                // 1e-9 nominal-level wiggle moves the corrected level by
                // less than the worst-case chain-rule Lipschitz bound
                // (|dα_corr/dp| = |dΦ/dz|·|dz_corr/dz_α|·|dz_α/dp| ≲
                // 0.5 · 1 · 1/φ(z_lo) ≈ 25 at the lowest swept level;
                // 1e-6 leaves two orders of headroom while still failing
                // any seam discontinuity, which would jump ~1e-3+).
                let wiggle =
                    bca_levels(EXP_THETA, &EXP_BOOT, EXP_ACCEL, (p + 1e-9, 1.0 - p), 1.0, true);
                assert!((wiggle.alpha_lower - lv.alpha_lower).abs() < 1e-6);
            }
        }
    }

    #[test]
    fn bca_levels_are_deterministic() {
        let run = || bca_levels(EXP_THETA, &EXP_BOOT, EXP_ACCEL, (0.025, 0.975), 1.0, true);
        let a = run();
        let b = run();
        assert_eq!(a.alpha_lower.to_bits(), b.alpha_lower.to_bits());
        assert_eq!(a.alpha_upper.to_bits(), b.alpha_upper.to_bits());
        assert_eq!(a.fallback, b.fallback);
    }

    /// Interior exposure fixture for the influence cross-check: two
    /// deliberately asymmetric signatures over six channels, one sample
    /// with an interior NNLS solution (both exposures strictly positive,
    /// so the fixed-active-set linear map is the exact solve).
    fn influence_fixture() -> (Vec<f64>, Vec<f64>, Vec<f64>, usize, usize) {
        let (m, k) = (6usize, 2usize);
        let sigs = vec![
            0.50, 0.10, // channel 0
            0.30, 0.05, // channel 1
            0.10, 0.05, // channel 2
            0.05, 0.30, // channel 3
            0.04, 0.30, // channel 4
            0.01, 0.20, // channel 5
        ];
        let counts = vec![400.0, 250.0, 90.0, 150.0, 120.0, 40.0];
        // Gram = SᵀS.
        let mut gram = vec![0.0f64; k * k];
        for i in 0..m {
            for p in 0..k {
                for q in 0..k {
                    gram[p * k + q] += sigs[i * k + p] * sigs[i * k + q];
                }
            }
        }
        (gram, sigs, counts, m, k)
    }

    #[test]
    fn analytic_acceleration_matches_the_numeric_leave_one_out() {
        // Numerical jackknife, mutation level: for each channel c the
        // leave-one-mutation-out solve is a FRESH active-set NNLS on
        // (G_A, b_A − s_A[c]) — a different code path end to end
        // (active-set pivoting vs the single LDLᵀ). Every influence u_c
        // and the resulting empirical acceleration must agree with the
        // analytic ones to 1e-10 (relative).
        let (gram, sigs, counts, m, k) = influence_fixture();
        let active = vec![0usize, 1usize];
        let k_a = active.len();
        let accels = analytic_acceleration(&gram, &sigs, &counts, m, k, &active).unwrap();
        assert_eq!(accels.len(), 2);
        // Active Gram + the analytic u = G_A⁻¹ S_Aᵀ (one factorization).
        let mut g_a = vec![0.0f64; k_a * k_a];
        for (p, &ap) in active.iter().enumerate() {
            for (q, &aq) in active.iter().enumerate() {
                g_a[p * k_a + q] = gram[ap * k + aq];
            }
        }
        let factor = crate::linalg::Ldlt::factor(&g_a, k_a).unwrap();
        let total: f64 = counts.iter().sum();
        // b_A = S_Aᵀ v.
        let b: Vec<f64> = (0..k_a)
            .map(|x| (0..m).map(|c| sigs[c * k + active[x]] * counts[c]).sum::<f64>())
            .collect();
        let base = nnls_gram(&g_a, &b, k_a, &NnlsOptions::default()).unwrap().x;
        for a in 0..k_a {
            let u_row: Vec<f64> = (0..m)
                .map(|c| {
                    let s_c: Vec<f64> = active.iter().map(|&x| sigs[c * k + x]).collect();
                    factor.solve(&s_c).unwrap()[a]
                })
                .collect();
            // Jackknife mean ū (weighted by channel counts).
            let mean: f64 = (0..m).map(|c| counts[c] * u_row[c]).sum::<f64>() / total;
            let mut m2 = 0.0f64;
            let mut m3 = 0.0f64;
            for c in 0..m {
                if counts[c] <= 0.0 {
                    continue;
                }
                // Fresh NNLS solve on the leave-one-mutation-out data.
                let mut b_loo = b.clone();
                for x in 0..k_a {
                    b_loo[x] -= sigs[c * k + active[x]];
                }
                let h_loo = nnls_gram(&g_a, &b_loo, k_a, &NnlsOptions::default())
                    .unwrap()
                    .x;
                let uc_numeric = base[a] - h_loo[a];
                assert_close(uc_numeric, u_row[c], 1e-10, "u_c analytic vs numeric");
                let dev = uc_numeric - mean;
                m2 += counts[c] * dev * dev;
                m3 += counts[c] * dev * dev * dev;
            }
            let a_numeric = m3 / (6.0 * m2 * m2.sqrt());
            assert_close(a_numeric, accels[a], 1e-10, "acceleration analytic vs numeric");
        }
    }

    #[test]
    fn analytic_acceleration_validates_inputs_and_singularity() {
        let (gram, sigs, counts, m, k) = influence_fixture();
        // Malformed Gram storage.
        assert_eq!(
            analytic_acceleration(&gram[..k * k - 1], &sigs, &counts, m, k, &[0, 1])
                .unwrap_err()
                .topic,
            "argument"
        );
        // Empty active set.
        assert_eq!(
            analytic_acceleration(&gram, &sigs, &counts, m, k, &[])
                .unwrap_err()
                .topic,
            "argument"
        );
        // Non-ascending active set.
        assert_eq!(
            analytic_acceleration(&gram, &sigs, &counts, m, k, &[1, 1])
                .unwrap_err()
                .topic,
            "argument"
        );
        // Active index out of range.
        assert_eq!(
            analytic_acceleration(&gram, &sigs, &counts, m, k, &[0, k])
                .unwrap_err()
                .topic,
            "argument"
        );
        // Zero-count sample.
        let zeros = vec![0.0f64; m];
        assert_eq!(
            analytic_acceleration(&gram, &sigs, &zeros, m, k, &[0, 1])
                .unwrap_err()
                .topic,
            "argument"
        );
        // Negative count.
        let mut neg = counts.clone();
        neg[0] = -1.0;
        assert_eq!(
            analytic_acceleration(&gram, &sigs, &neg, m, k, &[0, 1])
                .unwrap_err()
                .topic,
            "argument"
        );
        // Singular G_A: collinear active signatures have no influence map.
        let collinear = vec![
            1.0, 2.0, // proportional columns -> G_A singular
            2.0, 4.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        ];
        let mut g_col = vec![0.0f64; k * k];
        for i in 0..m {
            for p in 0..k {
                for q in 0..k {
                    g_col[p * k + q] += collinear[i * k + p] * collinear[i * k + q];
                }
            }
        }
        assert_eq!(
            analytic_acceleration(&g_col, &collinear, &counts, m, k, &[0, 1])
                .unwrap_err()
                .topic,
            "singular"
        );
    }
}

