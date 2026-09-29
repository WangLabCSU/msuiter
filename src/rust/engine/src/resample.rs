//! Multinomial resampling over the canonical PCG64 streams (U-M1s-04;
//! `docs/ARCHITECTURE.md` §2 `engine/resample.rs`).
//!
//! This is the bootstrap workhorse of the stability pipeline: given a
//! per-channel weight vector `p` (e.g. a signature profile over SBS96/1536
//! channels) and a count budget `n`, draw category counts from
//! `Multinomial(n, p / Σp)` on the in-house generator ([`crate::rng`]).
//! Every replicate runs on its own `StreamId` stream, so output is a pure
//! function of `(master_seed, stream, p, n)` — never of thread count or call
//! order (ARCH §2.6 thread-invariance contract).
//!
//! # Algorithm: cumulative-CDF inversion (method (b) of the unit spec)
//!
//! For each of the `n` draws:
//!
//! ```text
//! total = Σ p_i                         // sequential left-to-right, f64
//! cum[i] = (Σ_{j≤i} p_j) / total        // inclusive prefix, sequential
//! u      = (next_u64() >> 11) · 2^-53   // uniform in [0, 1), 53-bit grid
//! i*     = min { i : cum[i] > u }       // first index where the CDF exceeds u
//! counts[i*] += 1
//! ```
//!
//! This is the standard inverse-transform method for discrete variates
//! (Devroye 1986, *Non-Uniform Random Variate Generation*, Springer) applied
//! to the classical bootstrap of categorical data (Efron 1979). It was
//! chosen over the alternative — a chain of `k−1` conditional binomial
//! draws (draw `n₁ ~ Bin(n, p₁/Σrest)`, recurse on the remainder) — for
//! three reasons, to be cited in the paper Methods:
//!
//! 1. *Numerics.* The cumulative method's only floating-point operation is
//!    a monotone prefix sum of non-negative weights followed by
//!    comparisons: there is no subtraction, hence no cancellation. The
//!    conditional-binomial chain instead evaluates successive binomial tail
//!    differences `F(x+1) − F(x)` that underflow when the conditional
//!    distribution concentrates (late classes under a nearly exhausted
//!    remainder), which would force clamping/renormalization policies that
//!    themselves must be frozen and defended.
//! 2. *Stream accounting.* One uniform word per draw: a call consumes
//!    **exactly `n` words** of its stream, so composing several resamples
//!    on one stream is transparent and the frozen-seed spec is one line
//!    long. A hand-rolled dependency-free binomial generator either consumes
//!    a variable number of words (rejection/geometric skipping) or needs its
//!    own inversion machinery per class.
//! 3. *Cost is ample.* The relevant regime is `k ≤ 1536` channels and
//!    `n = 10³..10⁷` counts: `n·log₂k ≈ 11n` comparisons on a dense cache
//!    -resident array. The conditional-binomial chain saves uniform words
//!    (`k−1` instead of `n`) but pays `k−1` binomial inversions, and buys
//!    nothing in this regime while costing the numerical hygiene above.
//!
//! # Uniform construction (53-bit)
//!
//! `u = (w >> 11) · 2^-53` with `w` the next [`MsRng::next_u64`] word: the
//! top 53 bits of the word scaled by an exact power of two, so `u` is a
//! uniform multiple of `2^-53` in `[0, 1)` — every value exact in `f64`, no
//! rounding in the construction. `u < 1` always, and `cum[k−1] = total /
//! total = 1.0` exactly, so the search always succeeds inside the array
//! (no wraparound branch, no rejection loop).
//!
//! # Weights need not sum to 1; degenerate and underflowing weights
//!
//! `p` is normalized by its (sequential) sum `Σp`; only the *relative*
//! weights matter. A zero weight has an empty interval and receives **exactly
//! zero** counts. A class whose weight is so small that the running prefix
//! does not move by a full ulp (or whose interval is narrower than the
//! `2^-53` uniform grid) collapses to an empty interval at `f64` resolution
//! and is structurally unreachable — exact zero counts, no error, no
//! re-draw loop. This is the honest double-precision behavior and is pinned
//! by a test; classes at or above ~`2^-53` of the total remain live with
//! the correct probability.
//!
//! # Determinism
//!
//! Pure function of the stream words, `p` and `n`. Sequential fixed-order
//! accumulation, no hashing, no parallelism, no platform-dependent float
//! semantics beyond IEEE 754 basic operations (which `f64` in Rust
//! guarantees bit-reproducibly): identical on stable and on the 1.71 MSRV
//! toolchain (D6/A6), identical across `threads ∈ {1, N}` (U-M1s-05).
//!
//! # Contract notes (`docs/ARCHITECTURE.md` §2)
//!
//! * Pure numeric kernel: no dependencies, no `rand` face, no `unsafe`, no
//!   FFI (D2/D4/A6).
//! * The checked faces ([`validate_weights`], [`multinomial_from_stream`],
//!   [`multinomial_bootstrap`]) return `Result<_, MsError>` per FFI
//!   contract 5. The raw primitive [`multinomial`] takes *pre-validated*
//!   input and panics on contract violations (documented per-item) — it is
//!   the caller's programming-error contract, not a runtime-data path.
//! * Deliberately absent: negative-binomial calibration sampling (Jiang
//!   protocol — U-M3a), Dirichlet draws (later unit), consensus machinery.

use crate::error::MsError;
use crate::rng::{MsRng, StreamId};

/// Draw one count vector `counts ~ Multinomial(n, p / Σp)` from `rng`.
///
/// # Input contract (panics — pre-validated input only)
///
/// * `p` must be non-empty,
/// * every `p[i]` must be finite and `>= 0`,
/// * if `n > 0`, the sum of `p` must be finite and positive.
///
/// Use [`validate_weights`] (or the checked faces) before calling with
/// externally sourced data. With `n = 0` the weights are never evaluated
/// (all-zero weights are fine) and the stream is left **untouched**.
///
/// # Consumption contract
///
/// Exactly `n` [`MsRng::next_u64`] words are consumed — one per draw (see
/// the module docs). This makes the stream position after a call
/// predictable and is pinned by a golden-adjacent test.
///
/// # Output
///
/// `counts.len() == p.len()` with `Σ counts == n` (exact integer
/// arithmetic; each `counts[i] ≤ n`, so `u64` cannot overflow).
pub fn multinomial(rng: &mut MsRng, p: &[f64], n: u64) -> Vec<u64> {
    assert!(
        !p.is_empty(),
        "multinomial: weight vector must contain at least one category"
    );
    for (idx, &w) in p.iter().enumerate() {
        assert!(w.is_finite(), "multinomial: non-finite weight at category {idx}");
        assert!(w >= 0.0, "multinomial: negative weight {w} at category {idx}");
    }
    let mut counts = vec![0u64; p.len()];
    if n == 0 {
        // Zero draws: the distribution is never evaluated (all-zero
        // weights are fine) and the stream is left untouched.
        return counts;
    }
    let cum = normalized_inclusive_prefix(p);
    for _ in 0..n {
        let u = unit_interval(rng);
        // First index whose CDF value strictly exceeds u. Exists because
        // cum[k-1] == 1.0 exactly and u < 1.0 on the 53-bit grid.
        let idx = cum.partition_point(|&c| c <= u);
        counts[idx] += 1;
    }
    counts
}

/// Validate the `(p, n)` input contract of [`multinomial`] as structured
/// errors (FFI contract 5). The FFI shell can run this before entering the
/// panic-contract primitive.
///
/// Errors: empty `p` (`"argument"`); non-finite entry (`"na"`, with 1-based
/// index); negative entry (`"argument"`, with 1-based index); and, when
/// `n > 0`, a zero or non-finite total (`"argument"` / `"na"`). With
/// `n = 0` the total is never evaluated (see [`multinomial`]).
pub fn validate_weights(p: &[f64], n: u64) -> Result<(), MsError> {
    if p.is_empty() {
        return Err(MsError::new(
            "argument",
            "weight vector must contain at least one category",
        ));
    }
    for (idx, &w) in p.iter().enumerate() {
        if !w.is_finite() {
            return Err(MsError::new("na", "non-finite entry in weight vector").with_i(idx as i64 + 1));
        }
        if w < 0.0 {
            return Err(MsError::new("argument", "negative entry in weight vector").with_i(idx as i64 + 1));
        }
    }
    if n > 0 {
        let mut total = 0.0f64;
        for &w in p {
            total += w;
        }
        if !total.is_finite() {
            return Err(MsError::new("na", "total weight overflows to infinity"));
        }
        if total == 0.0 {
            return Err(MsError::new(
                "argument",
                "zero total weight cannot allocate positive counts",
            ));
        }
    }
    Ok(())
}

/// Checked single-stream face: [`multinomial`] on the canonical stream
/// derived from `(master_seed, stream)`.
///
/// Use this for callers that address an explicit stream (e.g. rank/fold
/// -split workers under the U-M1s-05 thread-invariance contract). The
/// bootstrap main path uses [`multinomial_bootstrap`].
pub fn multinomial_from_stream(
    master_seed: u64,
    stream: StreamId,
    p: &[f64],
    n: u64,
) -> Result<Vec<u64>, MsError> {
    validate_weights(p, n)?;
    let mut rng = MsRng::from_stream(master_seed, stream);
    Ok(multinomial(&mut rng, p, n))
}

/// Checked batch face (bootstrap main path): `replicates` independent
/// `Multinomial(n, p / Σp)` count vectors, replicate `r` drawn on stream
/// `StreamId { replicate: r, rank: 0, fold: 0 }`.
///
/// # Output layout
///
/// Flat row-major buffer of length `replicates * p.len()`:
/// `out[r * k + c]` is the count of channel `c` in replicate `r`.
/// `rank`/`fold` stay 0 here; parallel workers that must subdivide the
/// replicate axis use those axes of [`StreamId`] via
/// [`multinomial_from_stream`] instead.
///
/// # Errors
///
/// [`validate_weights`] failures, `replicates == 0` (the dimension-positive
/// convention of [`crate::nmf`]), and address-space overflow of the output
/// length (`"argument"`).
pub fn multinomial_bootstrap(
    master_seed: u64,
    p: &[f64],
    n: u64,
    replicates: u64,
) -> Result<Vec<u64>, MsError> {
    validate_weights(p, n)?;
    if replicates == 0 {
        return Err(MsError::new("argument", "replicates must be positive"));
    }
    let k = p.len();
    let rows = usize::try_from(replicates)
        .map_err(|_| MsError::new("argument", "replicates does not fit the platform address space"))?;
    let len = rows.checked_mul(k).ok_or_else(|| {
        MsError::new("argument", "replicates * categories overflows the platform address space")
    })?;
    let mut out = vec![0u64; len];
    for (r, row) in out.chunks_mut(k).enumerate() {
        let mut rng = MsRng::from_stream(
            master_seed,
            StreamId { replicate: r as u64, rank: 0, fold: 0 },
        );
        row.copy_from_slice(&multinomial(&mut rng, p, n));
    }
    Ok(out)
}

/// 53-bit uniform on `[0, 1)`: top 53 bits of the next word scaled by the
/// exact power of two `2^-53` (module docs "Uniform construction").
#[inline]
fn unit_interval(rng: &mut MsRng) -> f64 {
    (rng.next_u64() >> 11) as f64 * (1.0 / (1u64 << 53) as f64)
}

/// Normalized inclusive prefix `cum[i] = (Σ_{j≤i} p_j) / total`, sequential
/// left-to-right (the exact loop order is part of the frozen spec).
/// Assumes validated input; `cum[k-1] == 1.0` exactly.
fn normalized_inclusive_prefix(p: &[f64]) -> Vec<f64> {
    let mut total = 0.0f64;
    for &w in p {
        total += w;
    }
    assert!(
        total.is_finite() && total > 0.0,
        "multinomial: total weight must be finite and positive to allocate counts (got {total})"
    );
    let mut cum = Vec::with_capacity(p.len());
    let mut acc = 0.0f64;
    for &w in p {
        acc += w;
        cum.push(acc / total);
    }
    cum
}

#[cfg(test)]
mod tests {
    use super::*;

    // ==================================================================
    // Golden vectors (frozen at U-M1s-04; "the algorithm is the spec").
    // Generated by this implementation and recorded verbatim; any future
    // diff means the sampling algorithm, the uniform construction, the
    // prefix/normalization arithmetic, or the stream layout drifted —
    // which requires an explicit spec bump and regenerated goldens, same
    // discipline as engine/rng.rs (D6/A6 paper Methods freeze). They must
    // hold identically on stable and on the 1.71 MSRV toolchain.
    // ==================================================================

    #[test]
    fn golden_bootstrap_replicates_seed42() {
        // Bootstrap main-path golden: master seed 42, p = [0.1, 0.2, 0.3,
        // 0.4], n = 97, replicates 0..8 on StreamId { replicate: r }.
        // Flat row-major: rows [0..4) = replicate 0, [4..8) = replicate 1, …
        assert_eq!(
            multinomial_bootstrap(42, &[0.10, 0.20, 0.30, 0.40], 97, 8).unwrap(),
            vec![
                11, 15, 27, 44, // replicate 0
                11, 27, 20, 39, // replicate 1
                7, 21, 31, 38, // replicate 2
                6, 28, 26, 37, // replicate 3
                12, 23, 28, 34, // replicate 4
                9, 15, 38, 35, // replicate 5
                9, 18, 36, 34, // replicate 6
                7, 23, 26, 41, // replicate 7
            ]
        );
    }

    #[test]
    fn golden_from_stream_unnormalized_with_zero_class() {
        // Arbitrary-stream golden: master seed 2026, stream {7, 3, 5},
        // unnormalized p (sum 10.5) with two zero classes, n = 50.
        assert_eq!(
            multinomial_from_stream(
                2026,
                StreamId { replicate: 7, rank: 3, fold: 5 },
                &[1.0, 2.0, 3.0, 4.0, 0.0, 0.5],
                50,
            )
            .unwrap(),
            vec![7, 8, 14, 21, 0, 0]
        );
    }

    #[test]
    fn golden_sbs_flavored_many_classes_with_zeros() {
        // Eight-class golden (SBS-shaped sparsity), seed 97, ZERO stream,
        // n = 256, five of eight classes at exactly zero weight.
        assert_eq!(
            multinomial_from_stream(
                97,
                StreamId::ZERO,
                &[3.0, 0.0, 1.0, 0.0, 0.0, 2.0, 1.0, 0.0],
                256,
            )
            .unwrap(),
            vec![109, 0, 39, 0, 0, 75, 33, 0]
        );
    }

    #[test]
    fn golden_single_category_and_single_positive_class() {
        assert_eq!(multinomial_from_stream(5, StreamId::ZERO, &[2.5], 13).unwrap(), vec![13]);
        assert_eq!(
            multinomial_from_stream(6, StreamId::ZERO, &[0.0, 7.0, 0.0], 41).unwrap(),
            vec![0, 41, 0]
        );
    }

    // ==================================================================
    // Consumption contract (stream accounting is part of the frozen spec)
    // ==================================================================

    #[test]
    fn consumes_exactly_n_words_from_the_stream() {
        let p = [0.25, 0.5, 0.25];
        let mut a = MsRng::from_stream(42, StreamId { replicate: 1, rank: 0, fold: 0 });
        let _counts = multinomial(&mut a, &p, 7);
        let tail_after_call = a.next_u64();

        // An independent instance of the same stream, skipping the 7 words
        // the call must have consumed, must continue bit-identically.
        let mut b = MsRng::from_stream(42, StreamId { replicate: 1, rank: 0, fold: 0 });
        for _ in 0..7 {
            b.next_u64();
        }
        assert_eq!(tail_after_call, b.next_u64());
    }

    #[test]
    fn zero_draws_leave_the_stream_untouched() {
        let mut a = MsRng::from_stream(42, StreamId::ZERO);
        assert_eq!(multinomial(&mut a, &[0.3, 0.7], 0), vec![0, 0]);
        let mut b = MsRng::from_stream(42, StreamId::ZERO);
        assert_eq!(a.next_u64(), b.next_u64());
    }

    // ==================================================================
    // Structural properties
    // ==================================================================

    #[test]
    fn counts_sum_to_n_across_a_shape_grid() {
        let patterns: &[&[f64]] = &[
            &[0.1, 0.2, 0.3, 0.4],
            &[1.0, 2.0, 3.0, 4.0, 0.0],
            &[0.0, 5.0, 0.0],
            &[2.5],
            &[1.0, 1e-12, 1e-300],
            &[7.0; 12],
        ];
        for p in patterns {
            for n in [0u64, 1, 2, 17, 1000] {
                let mut rng = MsRng::from_stream(2026, StreamId::ZERO);
                let counts = multinomial(&mut rng, p, n);
                assert_eq!(counts.len(), p.len());
                assert_eq!(counts.iter().sum::<u64>(), n, "p = {p:?}, n = {n}");
                assert!(counts.iter().all(|&c| c <= n));
            }
        }
    }

    #[test]
    fn zero_weight_classes_receive_exactly_zero() {
        let p = [0.0, 0.3, 0.0, 0.5, 0.2, 0.0];
        let out = multinomial_bootstrap(11, &p, 50, 16).unwrap();
        for (r, row) in out.chunks(p.len()).enumerate() {
            for (c, &count) in row.iter().enumerate() {
                if p[c] == 0.0 {
                    assert_eq!(count, 0, "replicate {r}, zero-weight class {c}");
                }
            }
        }
    }

    #[test]
    fn single_positive_class_receives_everything() {
        // Raw primitive across seeds and sizes: with a single live class
        // (k = 1 boundary, or one positive weight among dead ones) the
        // mass must land entirely on it — for ANY stream, not just the
        // frozen golden instantiation above.
        for n in [1u64, 2, 41, 999] {
            let mut rng = MsRng::from_stream(6, StreamId::ZERO);
            assert_eq!(multinomial(&mut rng, &[2.5], n), vec![n]);
            let mut rng = MsRng::from_stream(6, StreamId { replicate: 2, rank: 0, fold: 1 });
            assert_eq!(multinomial(&mut rng, &[0.0, 7.0, 0.0], n), vec![0, n, 0]);
        }
    }

    #[test]
    fn power_of_two_rescaling_is_bit_exact() {
        // Exact power-of-two rescaling leaves every prefix value bit
        // -identical (exponent shifts only), so the same stream must
        // produce identical counts — normalization by Σp is exact here.
        let p = [0.4, 0.3, 0.2, 0.1];
        let q = [1.6, 1.2, 0.8, 0.4];
        let stream = StreamId { replicate: 3, rank: 1, fold: 4 };
        let a = multinomial_from_stream(33, stream, &p, 500).unwrap();
        let b = multinomial_from_stream(33, stream, &q, 500).unwrap();
        assert_eq!(a, b);
    }

    // ==================================================================
    // Statistical property: pooled counts are exactly one big multinomial
    // ==================================================================

    #[test]
    fn chi_square_goodness_of_fit_matches_weights() {
        // B independent n-draw bootstrap replicates from the same p pool
        // into exactly Multinomial(B·n, p) (each replicate is n iid
        // categorical draws), so Pearson's X² on the pooled counts is
        // asymptotically χ² with k−1 = 3 dof.
        //
        // Design: p = (0.4, 0.3, 0.2, 0.1), B = 400, n = 500 → N = 2·10⁵,
        // E = (80k, 60k, 40k, 20k): every expected cell ≥ 5 (the standard
        // validity rule for the χ² approximation).
        //
        // Threshold: 16.266 = upper 0.001 tail of χ²₃. Fixed seed makes
        // this a single deterministic number; the 0.999-quantile choice
        // keeps the false-red probability at 0.1% *if the goldens are ever
        // regenerated with a new seed*, while still catching systematic
        // distortions of ≥ ~2% (a relative bias δ on one class adds
        // ≈ N·p·δ²/(1+δ): δ = 2% on the largest class contributes ≈ 31).
        // A broken generator or swapped stream layout distorts far more.
        const P: [f64; 4] = [0.4, 0.3, 0.2, 0.1];
        const N: u64 = 500;
        const B: u64 = 400;
        const CHI2_DF3_UPPER_0_001: f64 = 16.266;

        let out = multinomial_bootstrap(11, &P, N, B).unwrap();
        assert_eq!(out.len(), B as usize * P.len());
        let mut pooled = [0u64; 4];
        for row in out.chunks(4) {
            for (c, &count) in row.iter().enumerate() {
                pooled[c] += count;
            }
        }
        let total: u64 = pooled.iter().sum();
        assert_eq!(total, N * B);

        let big_n = (N * B) as f64;
        let chi2: f64 = pooled
            .iter()
            .zip(P)
            .map(|(&obs, w)| {
                let expected = big_n * w;
                let d = obs as f64 - expected;
                d * d / expected
            })
            .sum();
        assert!(
            chi2 < CHI2_DF3_UPPER_0_001,
            "pooled counts {pooled:?} give X² = {chi2:.3} ≥ {CHI2_DF3_UPPER_0_001}"
        );
    }

    // ==================================================================
    // Stream discipline (thread-invariance readiness, U-M1s-05)
    // ==================================================================

    #[test]
    fn bootstrap_replicate_streams_are_pairwise_distinct() {
        // 12 replicate streams, same (seed, p, n): rows must be pairwise
        // distinct count vectors (collision space ~ C(102, 5) ≈ 8·10⁷ for
        // n = 97 over k = 6, so a layout bug that reuses one stream shows
        // up deterministically here).
        let p = [0.5, 0.2, 0.1, 0.1, 0.05, 0.05];
        let mut rows: Vec<Vec<u64>> = Vec::new();
        for &seed in &[42u64, 43] {
            let out = multinomial_bootstrap(seed, &p, 97, 6).unwrap();
            rows.extend(out.chunks(6).map(<[u64]>::to_vec));
        }
        for i in 0..rows.len() {
            for j in (i + 1)..rows.len() {
                assert_ne!(rows[i], rows[j], "rows {i} and {j} of the grid collide");
            }
        }
    }

    #[test]
    fn same_seed_and_stream_are_bit_identical_across_instantiations() {
        let p = [0.1, 0.9];
        let stream = StreamId { replicate: 4, rank: 2, fold: 9 };
        let a = multinomial_from_stream(0xFEED, stream, &p, 333).unwrap();
        let b = multinomial_from_stream(0xFEED, stream, &p, 333).unwrap();
        assert_eq!(a, b);
        // And through the batch face, twice:
        let c = multinomial_bootstrap(0xFEED, &p, 333, 5).unwrap();
        let d = multinomial_bootstrap(0xFEED, &p, 333, 5).unwrap();
        assert_eq!(c, d);
        // A different master seed must not reproduce the same rows.
        let e = multinomial_bootstrap(0xFEED + 1, &p, 333, 5).unwrap();
        assert_ne!(c, e);
    }

    // ==================================================================
    // Numerical hygiene: documented underflow of tiny classes
    // ==================================================================

    #[test]
    fn underflowing_class_collapses_to_an_empty_interval() {
        // p₂ = 1e-300 cannot move the running prefix 1.0 by a full ulp
        // (ulp(1) = 2⁻⁵² ≈ 2.2·10⁻¹⁶), so class 1's interval is empty at
        // f64 resolution: structurally zero counts, for ANY draws. The
        // mirrored case [1e-300, 1.0] stays reachable only through the
        // single grid point u = 0 (probability 2⁻⁵³ per draw — never hit
        // in the frozen streams below). Documented behavior, not patched.
        let mut rng = MsRng::from_stream(77, StreamId::ZERO);
        let counts = multinomial(&mut rng, &[1.0, 1e-300], 10_000);
        assert_eq!(counts, vec![10_000, 0]);

        let counts = multinomial(&mut rng, &[1e-300, 1.0], 10_000);
        assert_eq!(counts.iter().sum::<u64>(), 10_000);
        assert_eq!(counts[0], 0, "u = 0 is a 2^-53 event; must not occur here");
    }

    // ==================================================================
    // Checked-face validation (FFI contract 5)
    // ==================================================================

    #[test]
    fn validate_weights_error_payloads() {
        assert_eq!(
            validate_weights(&[], 0),
            Err(MsError::new("argument", "weight vector must contain at least one category"))
        );
        assert_eq!(
            validate_weights(&[0.5, f64::NAN], 5),
            Err(MsError::new("na", "non-finite entry in weight vector").with_i(2))
        );
        assert_eq!(
            validate_weights(&[0.5, f64::INFINITY], 0),
            Err(MsError::new("na", "non-finite entry in weight vector").with_i(2))
        );
        assert_eq!(
            validate_weights(&[0.5, -0.1, 0.2], 5),
            Err(MsError::new("argument", "negative entry in weight vector").with_i(2))
        );
        assert_eq!(
            validate_weights(&[0.0, 0.0], 5),
            Err(MsError::new(
                "argument",
                "zero total weight cannot allocate positive counts"
            ))
        );
        // With n = 0 the total is never evaluated: all-zero is fine.
        assert_eq!(validate_weights(&[0.0, 0.0], 0), Ok(()));
        assert_eq!(validate_weights(&[0.3, 0.7], 10), Ok(()));
    }

    #[test]
    fn checked_faces_surface_validation_errors() {
        assert!(multinomial_from_stream(1, StreamId::ZERO, &[-1.0], 5).is_err());
        assert!(multinomial_bootstrap(1, &[], 5, 3).is_err());
        assert!(multinomial_bootstrap(1, &[1.0], 5, 0)
            .unwrap_err()
            .message
            .contains("replicates"));
    }

    #[test]
    fn bootstrap_output_layout_is_replicates_times_categories() {
        let p = [0.25, 0.25, 0.5];
        let out = multinomial_bootstrap(9, &p, 40, 7).unwrap();
        assert_eq!(out.len(), 7 * 3);
        for row in out.chunks(3) {
            assert_eq!(row.iter().sum::<u64>(), 40);
        }
    }

    // ==================================================================
    // Raw-primitive panic contract (pre-validated input only)
    // ==================================================================

    #[test]
    #[should_panic(expected = "at least one category")]
    fn multinomial_panics_on_empty_weights() {
        let mut rng = MsRng::from_stream(1, StreamId::ZERO);
        multinomial(&mut rng, &[], 0);
    }

    #[test]
    #[should_panic(expected = "negative weight")]
    fn multinomial_panics_on_negative_weight() {
        let mut rng = MsRng::from_stream(1, StreamId::ZERO);
        multinomial(&mut rng, &[1.0, -1.0], 3);
    }

    #[test]
    #[should_panic(expected = "non-finite weight")]
    fn multinomial_panics_on_nan_weight() {
        let mut rng = MsRng::from_stream(1, StreamId::ZERO);
        multinomial(&mut rng, &[f64::NAN, 1.0], 3);
    }

    #[test]
    #[should_panic(expected = "finite and positive")]
    fn multinomial_panics_on_zero_total_with_positive_n() {
        let mut rng = MsRng::from_stream(1, StreamId::ZERO);
        multinomial(&mut rng, &[0.0, 0.0], 3);
    }
}
