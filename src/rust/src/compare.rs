//! Null-distribution faces for the M4 `ms_compare()` calibration library
//! (U-M4-01; design memo `docs/devlog/2026-10-04-M4-01-design-memo.md`
//! §2/§5) — the pure (R-type-free) heart of `ms_compare_null_rust`.
//!
//! # The two frozen null families (D13: estimation object = null quantiles;
//! generative model = these families; calibration protocol = MC; failure
//! condition = the frozen MC-SE tolerance, enforced at the R face)
//!
//! * [`NullFamily::SignatureUniform`] — the "unrelated signatures at
//!   channel count m" null: one draw = cosine between two independent
//!   uniform `Dirichlet(1, …, 1)` signatures over m channels
//!   (`engine::resample::dirichlet_uniform`). The analytic anchors are the
//!   exact moment identities `E⟨x,y⟩ = 1/m`, `E‖x‖² = 2/(m+1)` and the
//!   large-m delta approximation `E[cos] ≈ (m+1)/(2m)` — the test layer
//!   pins the MC against all three. Islam 2022's "random 96-vector chance
//!   baseline ≈ 0.75" is a DIFFERENT family construction and is explicitly
//!   not an anchor here (memo §2).
//! * [`NullFamily::Catalog`] — the "reconstruction at this burden" null
//!   (the 零校准 semantics of the capability matrix's "按通道数×负荷"): a
//!   truth μ is drawn once per call from the same uniform family and held
//!   fixed, then each draw reconstructs it at burden N —
//!   `Multinomial(N, μ)` (exact-N main arm) or the NB(μ, κ) stress arm
//!   ([`GenerativeArm`] string grammar shared with the calibration driver)
//!   — and the draw's cosine is `cos(counts/N, μ)`. The (m, N)
//!   parameterization is deliberately marginal over μ (uniform): the
//!   per-signature entropy-matched null is the recorded upgrade arm, not
//!   this face.
//!
//! # Stream layout (PCG64 canonical layout v1)
//!
//! `StreamId { replicate: 0, rank: family_band, fold: 0 }` with family
//! bands 1/2/3 (signature / multinomial / NB) — replicate 0 and fold 0 are
//! never used by bootstrap (rank 0, replicate = boot) or CV (fold ≥ 1)
//! streams, and rank 0 stays reserved, so these null streams cannot
//! collide with any other face's streams at the same master seed. The
//! catalog families draw μ first, then the N draws, all from the one
//! stream: the whole result is a bitwise function of `seed`.
//!
//! # Threads / interrupt (contracts 6/7)
//!
//! Bounded sequential loop (`n_draws` draws, each `O(m + expected
//! Poisson walk)`); no thread pool is created and no cancellation flag is
//! taken — the documented "bounded, declared uninterruptible" decision,
//! the same one as `ms_test_presence_rust`. Callers who need interruptible
//! nulls should loop smaller `n_draws` calls from R.

use msuiter_engine::error::MsError;
use msuiter_engine::resample::{dirichlet_uniform, multinomial, nb_sample};
use msuiter_engine::rng::{MsRng, StreamId};

// The MC-SE tolerance for the null mean is frozen at the R face
// (`ms_compare_defaults$mc_se_tol` = 0.01): the kernel reports the
// number, policy lives at the boundary (design memo §5).

/// Batch count for the batch-means MC standard error (frozen).
const MC_BATCHES: usize = 20;

/// The null families (memo §2). The catalog arm reuses the calibration
/// driver's [`crate::calibrate::GenerativeArm`] string grammar so the two
/// faces never grow apart.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum NullFamily {
    /// Two independent uniform Dirichlet signatures (channel count only).
    SignatureUniform,
    /// Truth μ reconstructed at burden N (multinomial or NB stress arm).
    Catalog(crate::calibrate::GenerativeArm),
}

impl NullFamily {
    /// Parse the wire name: `"signature_uniform"`, `"catalog_multinomial"`,
    /// `"catalog_poisson"` (the exact NB limit) or `"catalog_nb:<κ>"`.
    /// Errors list the legal names (contract 4).
    pub fn parse(name: &str) -> Result<Self, MsError> {
        let legal = "\"signature_uniform\", \"catalog_multinomial\", \
                     \"catalog_poisson\" or \"catalog_nb:<size>\"";
        match name {
            "signature_uniform" => Ok(NullFamily::SignatureUniform),
            "catalog_multinomial" => Ok(NullFamily::Catalog(
                crate::calibrate::GenerativeArm::Multinomial,
            )),
            "catalog_poisson" => Ok(NullFamily::Catalog(
                crate::calibrate::GenerativeArm::NegativeBinomial(f64::INFINITY),
            )),
            other => {
                if let Some(size) = other.strip_prefix("catalog_nb:") {
                    let arm = crate::calibrate::GenerativeArm::parse(&format!("nb:{size}"))
                        .map_err(|_| {
                            MsError::new(
                                "argument",
                                format!("catalog_nb size \"{size}\" is not a positive number; \
                                         legal families are {legal}"),
                            )
                        })?;
                    return Ok(NullFamily::Catalog(arm));
                }
                Err(MsError::new(
                    "argument",
                    format!("family \"{other}\" is not one of {legal}"),
                ))
            }
        }
    }

    /// Canonical echo name (the input form for the NB arm is preserved at
    /// the FFI layer; this is the family band name for the stream).
    fn band(self) -> u64 {
        match self {
            NullFamily::SignatureUniform => 1,
            NullFamily::Catalog(crate::calibrate::GenerativeArm::Multinomial) => 2,
            NullFamily::Catalog(_) => 3,
        }
    }
}

/// One null evaluation: the mean/sd over all draws, the batch-means MC
/// standard error of the mean, and the empirical (type-7) quantiles in
/// caller order. The draws themselves are not returned (the quantiles are
/// the estimation object; echoing 20k draws across the FFI buys nothing).
#[derive(Clone, Debug)]
pub struct NullDraw {
    pub mean: f64,
    pub sd: f64,
    pub mc_se: f64,
    /// Caller-order empirical type-7 quantiles (bitwise `quantile(type=7)`
    /// semantics of R).
    pub quantiles: Vec<f64>,
}

/// Run one null evaluation (memo §5 contract): `m ≥ 2` channels,
/// `n_draws ≥ 200`, finite `burden ≥ 1` for the catalog families, finite
/// quantiles in (0, 1), any `seed ≥ 0`. Every violation is a structured
/// error with 1-based offender coordinates (contract 5), raised before any
/// draw burns work.
pub fn compare_null(
    family: NullFamily,
    m: usize,
    burden: f64,
    n_draws: usize,
    quantiles: &[f64],
    seed: u64,
) -> Result<NullDraw, MsError> {
    if m < 2 {
        return Err(MsError::new(
            "argument",
            format!("null needs at least 2 channels (m=1 cosine is degenerate), got {m}"),
        )
        .with_i(m as i64));
    }
    if n_draws < 200 {
        return Err(MsError::new(
            "argument",
            format!("null needs n_draws >= 200 for a stable MC, got {n_draws}"),
        )
        .with_i(n_draws as i64));
    }
    if let NullFamily::Catalog(_) = family {
        if !burden.is_finite() || burden < 1.0 {
            return Err(MsError::new(
                "argument",
                format!("catalog nulls need a finite burden >= 1, got {burden}"),
            ));
        }
    }
    if quantiles.is_empty() {
        return Err(MsError::new("argument", "quantiles must be non-empty"));
    }
    for (k, &q) in quantiles.iter().enumerate() {
        if !q.is_finite() || q <= 0.0 || q >= 1.0 {
            return Err(MsError::new("argument", "quantiles must lie strictly in (0, 1)")
                .with_i(k as i64 + 1));
        }
    }

    let mut rng = MsRng::from_stream(seed, StreamId { replicate: 0, rank: family.band(), fold: 0 });

    // The catalog truth: drawn once per call from the uniform family and
    // held fixed across draws (memo §2 — the (m, N) null is marginal over
    // μ, not conditional on a caller signature).
    let truth: Option<Vec<f64>> = match family {
        NullFamily::Catalog(_) => Some(dirichlet_uniform(&mut rng, m)),
        NullFamily::SignatureUniform => None,
    };
    let truth_norm = truth
        .as_ref()
        .map(|mu| mu.iter().map(|&v| v * v).sum::<f64>().sqrt());

    let mut draws = Vec::with_capacity(n_draws);
    for r in 0..n_draws {
        let c = match family {
            NullFamily::SignatureUniform => {
                let x = dirichlet_uniform(&mut rng, m);
                let y = dirichlet_uniform(&mut rng, m);
                cosine(&x, &y)
            }
            NullFamily::Catalog(crate::calibrate::GenerativeArm::Multinomial) => {
                let mu = truth.as_ref().unwrap();
                let n = burden as u64; // burden >= 1 validated; the freeze
                // floors fractional burdens at the FFI layer (integer
                // mutation counts only — a catalog has a whole number of
                // mutations).
                let counts = multinomial(&mut rng, mu, n);
                let total = n as f64; // burden >= 1 validated; the freeze
                // accepts fractional burdens only at whole counts (a
                // catalog has a whole number of mutations — the floor is
                // taken here, honestly documented at the FFI row).
                // ‖p̂‖ = ‖counts‖/total: the reconstruction is counts/total,
                // so the norm must live on the same share scale as the dot
                // (audited fix — the first sketch fed ‖counts‖, scaling the
                // cosine by 1/total).
                let norm =
                    counts.iter().map(|&c| (c as f64) * (c as f64)).sum::<f64>().sqrt() / total;
                if norm == 0.0 || truth_norm.unwrap() == 0.0 {
                    return Err(MsError::new("na", "degenerate null draw (zero norm)")
                        .with_i(r as i64 + 1));
                }
                let dot: f64 = mu
                    .iter()
                    .zip(counts.iter())
                    .map(|(&u, &c)| u * (c as f64 / total))
                    .sum();
                dot / (norm * truth_norm.unwrap())
            }
            NullFamily::Catalog(arm_size) => {
                let mu = truth.as_ref().unwrap();
                let size = match arm_size {
                    crate::calibrate::GenerativeArm::NegativeBinomial(s) => s,
                    crate::calibrate::GenerativeArm::Multinomial => unreachable!(),
                };
                // The NB arm takes PER-CHANNEL MEAN COUNTS: the truth is a
                // share vector, so the expected count at burden N is
                // N·μ_c (the multinomial arm gets the same scaling through
                // its N draws — audited fix: the first sketch fed the raw
                // shares and expected a total of 1, making all-zero
                // catalogs likely at every burden).
                let mean_c: Vec<f64> = mu.iter().map(|&u| u * burden).collect();
                let flat = nb_sample(&mut rng, &mean_c, size, 1);
                let total: f64 = flat.iter().map(|&c| c as f64).sum();
                if total == 0.0 {
                    // The NB stress arm can draw an all-zero catalog at
                    // small burdens: an honest structured failure, not a
                    // silent NaN in the quantiles (contract 4/5).
                    return Err(MsError::new(
                        "na",
                        "NB null draw produced an all-zero catalog (raise the burden)",
                    )
                    .with_i(r as i64 + 1));
                }
                let norm = flat.iter().map(|&c| (c as f64) * (c as f64)).sum::<f64>().sqrt()
                    / total;
                let dot: f64 = mu
                    .iter()
                    .zip(flat.iter())
                    .map(|(&u, &c)| u * (c as f64 / total))
                    .sum();
                dot / (norm * truth_norm.unwrap())
            }
        };
        if !c.is_finite() {
            return Err(MsError::new("na", "null draw produced a non-finite cosine")
                .with_i(r as i64 + 1));
        }
        draws.push(c);
    }

    // Fixed-order reductions: mean/sd over the draws in stream order (no
    // order-sensitive reassociation — the draws are already sequential).
    let n = draws.len() as f64;
    let mean = draws.iter().sum::<f64>() / n;
    let var = draws.iter().map(|&c| (c - mean) * (c - mean)).sum::<f64>() / (n - 1.0);
    let sd = var.sqrt();

    // Batch means over MC_BATCHES consecutive, near-equal batches (the
    // first `n_draws % MC_BATCHES` batches take one extra draw): the draws
    // are i.i.d., so the batch means are too, and se = sd(batches)/√B.
    let per = n_draws / MC_BATCHES;
    let rem = n_draws % MC_BATCHES;
    let mut batch_means = Vec::with_capacity(MC_BATCHES);
    let mut start = 0usize;
    for b in 0..MC_BATCHES {
        let len = per + if b < rem { 1 } else { 0 };
        let slice = &draws[start..start + len];
        batch_means.push(slice.iter().sum::<f64>() / len as f64);
        start += len;
    }
    let b = MC_BATCHES as f64;
    let bm_mean = batch_means.iter().sum::<f64>() / b;
    let bm_var = batch_means
        .iter()
        .map(|&x| (x - bm_mean) * (x - bm_mean))
        .sum::<f64>()
        / (b - 1.0);
    let mc_se = (bm_var / b).sqrt();

    draws.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let quantile_values = quantiles
        .iter()
        .map(|&q| quantile_type7(&draws, q))
        .collect();

    Ok(NullDraw {
        mean,
        sd,
        mc_se,
        quantiles: quantile_values,
    })
}

/// Cosine of two equal-length, finite vectors. Zero norms propagate as
/// NaN — the caller converts them to structured errors (the uniform
/// Dirichlet cannot produce one, but honesty is cheap here).
fn cosine(x: &[f64], y: &[f64]) -> f64 {
    let dot: f64 = x.iter().zip(y.iter()).map(|(&a, &b)| a * b).sum();
    let nx: f64 = x.iter().map(|&a| a * a).sum::<f64>().sqrt();
    let ny: f64 = y.iter().map(|&a| a * a).sum::<f64>().sqrt();
    dot / (nx * ny)
}

/// R's `quantile(type = 7)` on an ascending slice: index `h = (n−1)·q`
/// (1-based), linear interpolation between the floor and ceiling order
/// statistics — bitwise-identical to the R convention for the same input
/// order statistics.
fn quantile_type7(sorted: &[f64], q: f64) -> f64 {
    let n = sorted.len();
    let h = (n as f64 - 1.0) * q;
    let lo = (h.floor() as usize).min(n - 1);
    let hi = (lo + 1).min(n - 1);
    let frac = h - lo as f64;
    sorted[lo] + frac * (sorted[hi] - sorted[lo])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn family_parse_round_trip_and_errors() {
        assert_eq!(
            NullFamily::parse("signature_uniform").unwrap(),
            NullFamily::SignatureUniform
        );
        assert_eq!(
            NullFamily::parse("catalog_multinomial").unwrap(),
            NullFamily::Catalog(crate::calibrate::GenerativeArm::Multinomial)
        );
        assert_eq!(
            NullFamily::parse("catalog_poisson").unwrap(),
            NullFamily::Catalog(crate::calibrate::GenerativeArm::NegativeBinomial(
                f64::INFINITY
            ))
        );
        match NullFamily::parse("catalog_nb:8") {
            Ok(NullFamily::Catalog(crate::calibrate::GenerativeArm::NegativeBinomial(s))) => {
                assert_eq!(s, 8.0)
            }
            other => panic!("unexpected parse: {other:?}"),
        }
        let e = NullFamily::parse("cosmic").unwrap_err();
        assert_eq!(e.topic, "argument");
        assert!(e.message.contains("signature_uniform"));
        let e = NullFamily::parse("catalog_nb:0").unwrap_err();
        assert_eq!(e.topic, "argument");
        let e = NullFamily::parse("catalog_nb:x").unwrap_err();
        assert_eq!(e.topic, "argument");
    }

    #[test]
    fn validation_errors_are_structured_and_pre_draw() {
        let q = [0.95];
        let e = compare_null(NullFamily::SignatureUniform, 1, 0.0, 1000, &q, 1).unwrap_err();
        assert_eq!(e.topic, "argument");
        assert_eq!(e.i, Some(1));
        let e = compare_null(NullFamily::SignatureUniform, 96, 0.0, 199, &q, 1).unwrap_err();
        assert_eq!(e.topic, "argument");
        assert_eq!(e.i, Some(199));
        let e = compare_null(
            NullFamily::Catalog(crate::calibrate::GenerativeArm::Multinomial),
            96,
            0.5,
            1000,
            &q,
            1,
        )
        .unwrap_err();
        assert_eq!(e.topic, "argument");
        let e =
            compare_null(NullFamily::SignatureUniform, 96, 0.0, 1000, &[], 1).unwrap_err();
        assert_eq!(e.topic, "argument");
        let e = compare_null(NullFamily::SignatureUniform, 96, 0.0, 1000, &[0.0], 1)
            .unwrap_err();
        assert_eq!(e.topic, "argument");
        assert_eq!(e.i, Some(1));
        let e = compare_null(NullFamily::SignatureUniform, 96, 0.0, 1000, &[1.5], 1)
            .unwrap_err();
        assert_eq!(e.topic, "argument");
        // And a legal call works (so the guards above guard real draws).
        let ok = compare_null(NullFamily::SignatureUniform, 96, 0.0, 200, &q, 1).unwrap();
        assert!(ok.mean.is_finite());
    }

    #[test]
    fn signature_null_matches_the_exact_moment_identities() {
        // The exact anchors: E⟨x,y⟩ = 1/m, E‖x‖² = 2/(m+1) — pinned on the
        // DRAW level (the null face draws the pairs internally, so the
        // identities are verified through the same dirichlet_uniform
        // primitive on an independent stream).
        let m = 96usize;
        let draws = 20_000;
        let mut rng = MsRng::from_stream(1234, StreamId { replicate: 9, rank: 0, fold: 0 });
        let mut acc_inner = 0.0;
        let mut acc_norm2 = 0.0;
        for _ in 0..draws {
            let x = dirichlet_uniform(&mut rng, m);
            let y = dirichlet_uniform(&mut rng, m);
            acc_inner += x.iter().zip(y.iter()).map(|(&a, &b)| a * b).sum::<f64>();
            acc_norm2 += x.iter().map(|&a| a * a).sum::<f64>();
        }
        // 4·MC-SE tolerances (SD of ⟨x,y⟩ ≈ 1/m·√2; of ‖x‖² ≈ small).
        let se_inner = (2.0f64 / m as f64 / draws as f64).sqrt();
        assert!(
            (acc_inner / draws as f64 - 1.0 / m as f64).abs() < 4.0 * se_inner,
            "E<x,y> anchor"
        );
        let want_norm2 = 2.0 / (m as f64 + 1.0);
        let se_norm2 = (2.0f64 / (m as f64 + 1.0) / draws as f64).sqrt();
        assert!(
            (acc_norm2 / draws as f64 - want_norm2).abs() < 4.0 * se_norm2,
            "E||x||^2 anchor"
        );
    }

    #[test]
    fn signature_null_mean_near_the_delta_approximation() {
        // Large-m delta approximation E[cos] ≈ (m+1)/(2m): an O(1/m)
        // asymptotic, so the tolerance is loose but not vacuous (m=96 puts
        // the anchor at 97/192 ≈ 0.5052; the MC se is ~1e-3).
        let res =
            compare_null(NullFamily::SignatureUniform, 96, 0.0, 20_000, &[0.5, 0.95, 0.999], 42)
                .unwrap();
        let anchor = 97.0 / 192.0;
        assert!(
            (res.mean - anchor).abs() < 0.02,
            "mean {} vs delta anchor {anchor}",
            res.mean
        );
        // Quantile monotonicity only: the cosine null is skewed, so the
        // mean has no generic bracket between the median and q95.
        assert!(res.quantiles[0] < res.quantiles[1]);
        assert!(res.quantiles[1] < res.quantiles[2]);
    }

    #[test]
    fn catalog_null_rises_with_burden_and_tightens() {
        let q = [0.95];
        let lo = compare_null(
            NullFamily::Catalog(crate::calibrate::GenerativeArm::Multinomial),
            96,
            100.0,
            2_000,
            &q,
            7,
        )
        .unwrap();
        let hi = compare_null(
            NullFamily::Catalog(crate::calibrate::GenerativeArm::Multinomial),
            96,
            10_000.0,
            2_000,
            &q,
            7,
        )
        .unwrap();
        assert!(hi.mean > lo.mean, "burden monotonicity");
        assert!(hi.sd < lo.sd, "burden concentration");
        // A low burden leaves real room below the 0.95 quantile (the null
        // is not degenerate at 1).
        assert!(lo.quantiles[0] < 0.99);
    }

    #[test]
    fn nb_stress_arm_runs_and_lowers_the_null() {
        // Overdispersion widens the reconstruction noise: at the same
        // burden the NB null mean sits below the multinomial one.
        let q = [0.95];
        let nb = compare_null(
            NullFamily::Catalog(crate::calibrate::GenerativeArm::parse("nb:8").unwrap()),
            96,
            1_000.0,
            2_000,
            &q,
            9,
        )
        .unwrap();
        let multi = compare_null(
            NullFamily::Catalog(crate::calibrate::GenerativeArm::Multinomial),
            96,
            1_000.0,
            2_000,
            &q,
            9,
        )
        .unwrap();
        assert!(nb.mean < multi.mean);
    }

    #[test]
    fn deterministic_and_quantile_convention_matches_r_type7() {
        let a = compare_null(NullFamily::SignatureUniform, 24, 0.0, 2_000, &[0.95], 5).unwrap();
        let b = compare_null(NullFamily::SignatureUniform, 24, 0.0, 2_000, &[0.95], 5).unwrap();
        assert_eq!(a.mean, b.mean);
        assert_eq!(a.quantiles, b.quantiles);
        // type-7 semantics on a hand-built order-statistic grid (tolerance
        // assert: the hand value takes a different arithmetic path than
        // the function; the bitwise R parity is pinned at the R layer by
        // feeding identical order statistics to quantile(type=7)).
        let grid: Vec<f64> = (1..=10).map(|i| i as f64).collect();
        let got = quantile_type7(&grid, 0.95);
        assert!((got - 9.55).abs() < 1e-12, "type-7 quantile {got}");
    }
}
