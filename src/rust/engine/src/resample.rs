//! Multinomial resampling and negative-binomial calibration sampling over
//! the canonical PCG64 streams (U-M1s-04, U-M3b-01;
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
//! # Negative-binomial calibration sampling (U-M3b-01)
//!
//! [`nb_sample`] is the generator of the Jiang-protocol overdispersion
//! stress arm (M3b design memo §2.2, PI ruling 2026-10-04): channel `c`
//! receives `n` independent draws `X ~ NB(mean_c, size)` under the mSigAct
//! size semantics `Var = mean + mean²/size` ([`crate::likelihood::nb_ll`];
//! larger `size` → closer to Poisson). `size = f64::INFINITY` is the exact
//! Poisson arm. The primary dispersion anchor is `size = 8` — mSigAct's
//! SBS96 `nbinom.size` default ([`crate::likelihood::NB_SIZE_SBS96`]);
//! [`nb_sample_size_scan`] emits the frozen sensitivity grid
//! `{2, 8, 50, 200, ∞}` (memo §2.2) in one call for the calibration bench.
//!
//! ## Per-channel independence vs multinomial coupling (semantic anchor)
//!
//! The multinomial path draws each catalog as ONE coupled vector with the
//! total conserved exactly (`Σ counts = n`). The NB arm samples each
//! channel **independently** — there is no total-count constraint; the
//! catalog total fluctuates with the overdispersion. This is exactly the
//! likelihood family mSigAct/Jiang fit (`Σᵢ dnbinom(xᵢ; μᵢ, κ)`), and the
//! memo explicitly rejects the alternative "NB total + multinomial split"
//! construction because it matches a different law (PI ruling, memo
//! §7.2a). The two arms must never be mixed in one calibration claim.
//!
//! ## Algorithm: gamma–Poisson mixture
//!
//! `NB(mean, size)` is generated as `X | λ ~ Poisson(λ)` with
//! `λ ~ Gamma(shape = size, scale = mean/size)` — the standard mixture
//! identity behind `Var = μ + μ²/κ`:
//!
//! * *Gamma* — Marsaglia–Tsang squeeze (2000, ACM TOMS 26:363–372) for
//!   `shape ≥ 1`: `d = shape − 1/3`, `c = 1/√(9d)`, standard normal `x`
//!   (Box–Muller: 2 uniform words), `v = (1 + c·x)³`, accept on the
//!   squeeze `u < 1 − 0.0331·x⁴` or the full log test
//!   `ln u < x²/2 + d(1 − v + ln v)`, return `d·v` (scale applied at the
//!   call site). For `shape < 1` the exact Stuart boost
//!   `Gamma(shape) = Gamma(shape+1)·U^{1/shape}` reuses the same
//!   machinery — substituted for the memo's Ahrens–Dieter sketch (one
//!   code path, exactness unaffected; recorded deviation, memo §2.2).
//! * *Poisson* — sequential CDF inversion (Devroye 1986, *Non-Uniform
//!   Random Variate Generation* — the memo's anchor for the large-rate
//!   regime): the pmf is evaluated at the mode `m = ⌊rate⌋` in log space
//!   (`ln Γ` from [`crate::likelihood::ln_gamma`]; the mode value is
//!   `≈ (2π·rate)^(−1/2)`, so no `e^{−rate}` underflow), then the search
//!   expands two-sided from the mode in the frozen visit order
//!   `m, m+1, m−1, m+2, m−2, …` (pmf recursions
//!   `p(k+1) = p(k)·rate/(k+1)`, `p(k−1) = p(k)·k/rate`), returning the
//!   first visited count whose cumulative mass exceeds the uniform.
//!   Exact inversion under a fixed visit permutation; expected walk
//!   `O(√rate)`.
//!
//! ## Stream-word contract: relaxed per PI ruling (memo §7.2c)
//!
//! Unlike the multinomial's *exactly n words* accounting, NB consumption
//! is **data-dependent** — rejection loops in the Gamma step (3 words per
//! attempt, ≈ 1.05 attempts on average) make the total word count a
//! function of the drawn words themselves. It remains a **pure function
//! of the stream prefix**: a frozen `(master_seed, stream)` yields
//! bit-identical output, so frozen-seed reproducibility (the D11 sampling
//! protocol) holds exactly as for the multinomial; only the "predictable
//! stream position" convenience is given up. Documented accounting per
//! channel draw, in the frozen visit order `(replicate r, channel c)`
//! row-major: `mean_c = 0` → **0 words** (degenerate law at 0);
//! `size = +∞` → **1 word** (Poisson inversion only); otherwise gamma
//! words (3 per Marsaglia–Tsang attempt; +1 boost word when `size < 1`)
//! followed by exactly 1 Poisson word. The arms of
//! [`nb_sample_size_scan`] consume their shared stream sequentially in
//! listed order.
//!
//! ## Determinism and platform note
//!
//! Pure sequential function of the stream words and `(mean, size, n)`, no
//! hashing, no parallelism. The goldens pin the algorithm *including* the
//! host libm `ln`/`exp`/`cos`/`powf` values used inside the acceptance
//! tests; they must hold identically on stable and on the 1.71 MSRV
//! toolchain of this repo's platforms (same-host libm), and any diff
//! requires an explicit spec bump with regenerated goldens — the same
//! discipline as the multinomial goldens above.
//!
//! ## Supported regime
//!
//! `0 ≤ mean_c ≤ NB_MEAN_MAX`; `size ∈ (0, NB_RATE_MAX] ∪ {+∞}`; the
//! internal Poisson rate is asserted `≤ NB_RATE_MAX` (larger rates are
//! meaningless under the 53-bit uniform grid and make the `O(√rate)`
//! inversion walk unbounded in practice — a pathological `(mean, size)`
//! combination escaping the regime is the programming-error contract, not
//! a runtime data path). Degenerate-word policies: a
//! Box–Muller first uniform on the grid point `u = 0` (probability 2⁻⁵³)
//! is redrawn (`ln 0` has no finite role); `u = 0` at an acceptance test
//! accepts — the honest IEEE limit of `ln 0 = −inf`.
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
//! * Deliberately absent: Dirichlet draws (later unit), consensus
//!   machinery. The negative-binomial calibration face (Jiang protocol)
//!   has lived in this module since U-M3b-01 — sections below.

use crate::error::MsError;
use crate::likelihood::ln_gamma;
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

// ---------------------------------------------------------------------------
// Negative-binomial calibration sampling (U-M3b-01; Jiang protocol arm B)
// ---------------------------------------------------------------------------

/// Upper bound of the supported per-channel mean regime for
/// [`nb_sample`] / [`nb_sample_size_scan`]. The 2026 calibration grid caps
/// catalog totals at 10⁵–10⁶ (M3b memo §1.3), so 10⁹ is three-plus orders
/// of headroom; the cap exists because the Poisson inversion's expected
/// walk cost is `O(√rate)` and the goldens only certify the regime below.
/// Support ceilings for NB sampling (audited P2): the Poisson mode
/// inversion accumulates `mode·ln(rate)−rate−lnΓ(mode+1)` in f64 —
/// catastrophic cancellation grows with rate (measured: center-mass
/// distortion ≈1e-11 at rate 1e6, ≈0.4% at 1e12, ~0.16 at 1e15). The
/// calibration grid (μ ≤ 1e6) keeps that error ≲1e-9; the ceilings bound
/// it at ~0.4% — raising a ceiling requires re-pinning the distortion
/// measurement.
pub const NB_MEAN_MAX: f64 = 1e9;

/// Upper bound of the supported finite `size` and of the internal Poisson
/// rate of one NB draw (asserted inside the sampler). `+inf` is handled
/// separately as the exact Poisson arm; a pathological `(mean, size)`
/// combination whose mixed rate escapes the regime is the programming
/// -error contract (panic), not a runtime data path.
pub const NB_RATE_MAX: f64 = 1e12;

/// Validate one `size` parameter: NaN (`"na"`), non-positive
/// (`"argument"`) or a finite value above [`NB_RATE_MAX`] (`"argument"`);
/// `size = f64::INFINITY` is the legal exact-Poisson arm.
fn validate_nb_size(size: f64) -> Result<(), MsError> {
    if size.is_nan() {
        return Err(MsError::new("na", "size must be finite or +inf (no NaN)"));
    }
    if size <= 0.0 {
        return Err(MsError::new(
            "argument",
            "size must be positive (or +inf for the exact Poisson arm)",
        ));
    }
    if size.is_finite() && size > NB_RATE_MAX {
        return Err(MsError::new(
            "argument",
            "finite size exceeds the supported regime",
        ));
    }
    Ok(())
}

/// Validate the `(mean, size, n)` input contract of [`nb_sample`] as
/// structured errors (FFI contract 5). Errors: empty `mean` (`"argument"`);
/// non-finite entry (`"na"`, 1-based channel); negative entry or entry
/// above [`NB_MEAN_MAX`] (`"argument"`, 1-based channel); `size` NaN
/// (`"na"`); `size ≤ 0` or finite `size` above [`NB_RATE_MAX`]
/// (`"argument"`); and `n · channels` address-space overflow
/// (`"argument"`). `n = 0` is legal (empty output); `size = +inf` is legal
/// (exact Poisson arm).
pub fn validate_nb_sample(mean: &[f64], size: f64, n: u64) -> Result<(), MsError> {
    if mean.is_empty() {
        return Err(MsError::new(
            "argument",
            "mean vector must contain at least one channel",
        ));
    }
    for (idx, &m) in mean.iter().enumerate() {
        if !m.is_finite() {
            return Err(MsError::new("na", "non-finite entry in mean vector").with_i(idx as i64 + 1));
        }
        if m < 0.0 {
            return Err(
                MsError::new("argument", "negative entry in mean vector").with_i(idx as i64 + 1)
            );
        }
        if m > NB_MEAN_MAX {
            return Err(
                MsError::new("argument", "channel mean exceeds the supported regime")
                    .with_i(idx as i64 + 1),
            );
        }
    }
    validate_nb_size(size)?;
    let rows = usize::try_from(n)
        .map_err(|_| MsError::new("argument", "n does not fit the platform address space"))?;
    if rows.checked_mul(mean.len()).is_none() {
        return Err(MsError::new(
            "argument",
            "n * channels overflows the platform address space",
        ));
    }
    Ok(())
}

/// Draw `n` independent catalog replicates under the per-channel NB law
/// (module docs "Negative-binomial calibration sampling"): channel `c` is
/// `NB(mean_c, size)` with the mSigAct size semantics
/// `Var = mean + mean²/size`; `size = f64::INFINITY` is the exact Poisson
/// arm. Channels are **independent** — no total-count constraint (the
/// documented semantic difference from [`multinomial`], whose catalogs
/// conserve the total exactly).
///
/// # Input contract (panics — pre-validated input only)
///
/// As [`validate_nb_sample`]: non-empty, finite, non-negative `mean` within
/// [`NB_MEAN_MAX`]; `size` positive (or `+inf`) within [`NB_RATE_MAX`];
/// `n · channels` addressable. `n = 0` returns an empty vector and leaves
/// the stream untouched.
///
/// # Output layout
///
/// Flat row-major buffer of length `n * mean.len()`: `out[r * k + c]` is
/// the `r`-th draw of channel `c` — the same layout as
/// [`multinomial_bootstrap`], so the calibration bench can swap generative
/// arms without reshaping.
///
/// # Consumption contract (relaxed — see module docs)
///
/// Data-dependent but a pure function of the stream prefix, consumed in
/// the frozen `(replicate r, channel c)` row-major order: `mean_c = 0` →
/// 0 words; `size = +∞` → 1 word; else gamma words (3 per Marsaglia–Tsang
/// attempt; +1 boost word when `size < 1`) followed by exactly 1 Poisson
/// inversion word.
pub fn nb_sample(rng: &mut MsRng, mean: &[f64], size: f64, n: u64) -> Vec<u64> {
    if let Err(e) = validate_nb_sample(mean, size, n) {
        panic!("nb_sample: {e}");
    }
    let k = mean.len();
    let mut out = vec![0u64; n as usize * k];
    for row in out.chunks_mut(k) {
        for (c, slot) in row.iter_mut().enumerate() {
            *slot = nb_draw_one(rng, mean[c], size);
        }
    }
    out
}

/// κ-sensitivity tool (M3b memo §2.2): one call, all NB arms.
///
/// For each `size` in `sizes` — in listed order, sequentially consuming
/// the shared stream — this draws [`nb_sample`]`(rng, mean, size, n)`;
/// the result is one output buffer per arm, aligned with `sizes`. The
/// calibration bench passes the frozen grid
/// `{2.0, 8.0, 50.0, 200.0, f64::INFINITY}` (the last arm the exact
/// Poisson limit), with `8.0` the primary anchor — mSigAct's SBS96
/// `nbinom.size` default ([`crate::likelihood::NB_SIZE_SBS96`]).
///
/// Panics (raw-primitive contract): empty `sizes`; any arm failing
/// [`validate_nb_size`]; any [`nb_sample`] input violation.
pub fn nb_sample_size_scan(mean: &[f64], sizes: &[f64], n: u64, rng: &mut MsRng) -> Vec<Vec<u64>> {
    assert!(
        !sizes.is_empty(),
        "nb_sample_size_scan: sizes must contain at least one arm"
    );
    for (arm, &s) in sizes.iter().enumerate() {
        if let Err(e) = validate_nb_size(s) {
            panic!("nb_sample_size_scan: arm {arm}: {e}");
        }
    }
    sizes.iter().map(|&s| nb_sample(rng, mean, s, n)).collect()
}

/// One channel draw of `NB(mean, size)` (module docs "Algorithm"). A
/// zero-mean channel is the degenerate law at 0 and consumes **no** stream
/// words; `size = +∞` skips the gamma step (exact `Poisson(mean)`).
fn nb_draw_one(rng: &mut MsRng, mean_j: f64, size: f64) -> u64 {
    if mean_j == 0.0 {
        return 0;
    }
    let rate = if size.is_infinite() {
        mean_j
    } else {
        gamma_variate(rng, size) * (mean_j / size)
    };
    poisson_variate(rng, rate)
}

/// Standard normal by Box–Muller: exactly 2 uniform words per attempt; a
/// first uniform on the degenerate grid point `u = 0` (probability 2⁻⁵³)
/// is redrawn (`ln 0` has no finite role — module docs). The second
/// Box–Muller variate is discarded: caching it across calls would leak
/// generator state past the stream-accounting contract.
fn standard_normal(rng: &mut MsRng) -> f64 {
    loop {
        let u1 = unit_interval(rng);
        if u1 == 0.0 {
            continue;
        }
        let u2 = unit_interval(rng);
        let r = (-2.0 * u1.ln()).sqrt();
        let theta = std::f64::consts::TAU * u2;
        return r * theta.cos();
    }
}

/// `Gamma(shape, 1)` draw by the Marsaglia–Tsang squeeze (`shape ≥ 1`)
/// with the exact Stuart boost below 1 (module docs "Algorithm").
/// Consumption is data-dependent: 3 words per attempt (2 normal + 1
/// acceptance), plus 1 boost word when `shape < 1`.
fn gamma_variate(rng: &mut MsRng, shape: f64) -> f64 {
    if shape < 1.0 {
        // Stuart boost: Gamma(k) = Gamma(k+1) · U^{1/k}, exact. U = 0
        // (the 2⁻⁵³ grid point) underflows the power to the degenerate
        // variate 0, propagated honestly (rate 0 → Poisson 0).
        let boost = unit_interval(rng).powf(1.0 / shape);
        return boost * gamma_variate(rng, shape + 1.0);
    }
    let d = shape - 1.0 / 3.0;
    let c = 1.0 / (9.0 * d).sqrt();
    loop {
        let x = standard_normal(rng);
        let w = 1.0 + c * x;
        if w <= 0.0 {
            // v = w³ ≤ 0: regenerate x (the acceptance word is not yet drawn).
            continue;
        }
        let v = w * w * w;
        let u = unit_interval(rng);
        let x2 = x * x;
        // Squeeze, then the full log test (Marsaglia–Tsang 2000).
        // u = 0 accepts through ln 0 = −inf — the honest IEEE limit.
        if u < 1.0 - 0.0331 * x2 * x2 {
            return d * v;
        }
        if u.ln() < 0.5 * x2 + d - d * v + d * v.ln() {
            return d * v;
        }
    }
}

/// One `Poisson(rate)` draw by sequential CDF inversion (Devroye 1986;
/// module docs "Algorithm"): exactly **one** uniform word per draw. The
/// pmf is evaluated at the mode `m = ⌊rate⌋` in log space (no
/// `e^{−rate}` underflow) and the search expands two-sided from the mode
/// in the frozen visit order `m, m+1, m−1, m+2, m−2, …`, returning the
/// first visited count whose cumulative mass exceeds the uniform — exact
/// inversion under a fixed visit permutation, expected walk `O(√rate)`.
/// `rate = 0` is the degenerate 0 (the word is still consumed, keeping
/// the accounting uniform); `rate > NB_RATE_MAX` (or NaN, from a
/// pathological scale) trips the internal programming-error guard.
fn poisson_variate(rng: &mut MsRng, rate: f64) -> u64 {
    let u = unit_interval(rng);
    if rate == 0.0 {
        return 0;
    }
    assert!(
        rate <= NB_RATE_MAX,
        "poisson_variate: internal rate {rate} exceeds the supported regime (>{NB_RATE_MAX})"
    );
    let mode = rate.floor();
    let p_mode = (mode * rate.ln() - rate - ln_gamma(mode + 1.0)).exp();
    let mut cum = p_mode;
    if u < cum {
        return mode as u64;
    }
    let mut k_up = mode;
    let mut k_dn = mode;
    let mut p_up = p_mode;
    let mut p_dn = p_mode;
    loop {
        // Up side first — the visit order is part of the frozen spec.
        k_up += 1.0;
        p_up *= rate / k_up;
        cum += p_up;
        if u < cum {
            return k_up as u64;
        }
        if k_dn >= 1.0 {
            // pmf(k−1) = pmf(k)·k/λ — the factor uses the SOURCE index.
            p_dn *= k_dn / rate;
            k_dn -= 1.0;
            cum += p_dn;
            if u < cum {
                return k_dn as u64;
            }
        }
    }
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

    // ==================================================================
    // NB goldens (U-M3b-01; "the algorithm is the spec")
    //
    // Generated by this implementation and recorded verbatim; any future
    // diff means the gamma–Poisson machinery, the acceptance tests, the
    // inversion visit order, or the consumption layout drifted — which
    // requires an explicit spec bump and regenerated goldens (module docs;
    // same discipline as the multinomial goldens above). The NB goldens
    // additionally pin the host libm transcendental outputs inside the
    // acceptance tests: they must hold identically on stable and on the
    // 1.71 MSRV toolchain (same-host libm), D6/A6.
    // ==================================================================

    /// Sample mean/variance of a u64 draw vector (test-side MC machinery).
    fn sample_mean_var(xs: &[u64]) -> (f64, f64) {
        let n = xs.len() as f64;
        let mean = xs.iter().map(|&x| x as f64).sum::<f64>() / n;
        let var = xs
            .iter()
            .map(|&x| {
                let d = x as f64 - mean;
                d * d
            })
            .sum::<f64>()
            / (n - 1.0);
        (mean, var)
    }

    /// Empirical frequencies with the tail lumped at `max_k` (test-side).
    fn empirical_freqs(counts: &[u64], max_k: u64) -> Vec<f64> {
        let n = counts.len() as f64;
        let mut f = vec![0.0; (max_k + 1) as usize];
        for &c in counts {
            f[c.min(max_k) as usize] += 1.0;
        }
        f.iter().map(|&x| x / n).collect()
    }

    #[test]
    fn golden_nb_sample_rows_seed42() {
        // NB main-face golden: seed 42, ZERO stream, mean [2, 5], κ = 8
        // (the mSigAct SBS96 anchor), n = 6 catalogs, row-major.
        assert_eq!(
            nb_sample(&mut MsRng::from_stream(42, StreamId::ZERO), &[2.0, 5.0], 8.0, 6),
            vec![
                0, 7, // replicate 0
                2, 2, // replicate 1
                1, 3, // replicate 2
                2, 7, // replicate 3
                3, 3, // replicate 4
                2, 1, // replicate 5
            ]
        );
    }

    #[test]
    fn golden_nb_size_scan_seed2026() {
        // Scan golden: seed 2026, ZERO stream, mean [10, 3], the frozen
        // sensitivity grid {2, 8, 50, 200, ∞}, n = 4. Pins the arm
        // -sequential stream order and the ∞ = Poisson arm.
        let arms = nb_sample_size_scan(
            &[10.0, 3.0],
            &[2.0, 8.0, 50.0, 200.0, f64::INFINITY],
            4,
            &mut MsRng::from_stream(2026, StreamId::ZERO),
        );
        assert_eq!(
            arms,
            vec![
                [27, 0, 15, 2, 10, 0, 6, 2].to_vec(), // κ = 2 (most overdispersed)
                [8, 4, 9, 6, 13, 6, 7, 7].to_vec(),   // κ = 8 (primary anchor)
                [10, 1, 9, 5, 11, 4, 11, 3].to_vec(), // κ = 50
                [7, 2, 12, 0, 11, 3, 15, 4].to_vec(), // κ = 200
                [13, 7, 5, 3, 8, 1, 13, 2].to_vec(),  // ∞ = exact Poisson
            ]
        );
    }

    #[test]
    fn golden_nb_zero_mean_row_seed7() {
        // Zero-mean channels are exactly zero in place (degenerate law).
        assert_eq!(
            nb_sample(&mut MsRng::from_stream(7, StreamId::ZERO), &[0.0, 5.0, 0.0], 2.0, 4),
            vec![0, 0, 0, 0, 11, 0, 0, 3, 0, 0, 0, 0]
        );
    }

    #[test]
    fn golden_nb_geometric_size_one_exact_pmf() {
        // size = 1, mean = 1: NB collapses to the geometric law
        // P(X = k) = 2^-(k+1) — a fully hand-checkable reference family
        // (brief: "small-mean case, exact enumeration"). n = 2·10⁵ draws,
        // per-cell window 4.5σ.
        let out = nb_sample(&mut MsRng::from_stream(123, StreamId::ZERO), &[1.0], 1.0, 200_000);
        let f = empirical_freqs(&out, 7); // k = 0..=7, tail lumped at 7
        let mut exact: Vec<f64> = (0..7u64).map(|k| 2.0_f64.powi(-(k as i32 + 1))).collect();
        exact.push(2.0_f64.powi(-7)); // Σ_{k≥7} 2^-(k+1)
        for (k, (&fk, &pk)) in f.iter().zip(&exact).enumerate() {
            assert!((fk - pk).abs() < 0.005, "k={k}: f={fk}, p={pk}");
        }
        let (xbar, _) = sample_mean_var(&out);
        assert!((xbar - 1.0).abs() < 0.02, "geometric mean {xbar} vs 1");
    }

    #[test]
    fn golden_nb_two_exact_pmf_small_mean() {
        // mean = 0.5, size = 2: exact pmf
        // P(X = k) = (k+1)·(2/2.5)²·(0.5/2.5)^k = (k+1)·0.64·0.2^k
        // (p0 = 0.64, p1 = 0.256, p2 = 0.0768, …) — enumerated against the
        // sampler on a fixed stream.
        let out = nb_sample(&mut MsRng::from_stream(321, StreamId::ZERO), &[0.5], 2.0, 200_000);
        let f = empirical_freqs(&out, 5);
        let mut exact: Vec<f64> = (0..5u64)
            .map(|k| (k as f64 + 1.0) * 0.64 * 0.2_f64.powf(k as f64))
            .collect();
        exact.push(1.0 - exact.iter().sum::<f64>());
        for (k, (&fk, &pk)) in f.iter().zip(&exact).enumerate() {
            assert!((fk - pk).abs() < 0.004, "k={k}: f={fk}, p={pk}");
        }
    }

    #[test]
    fn golden_nb_poisson_limit_exact_pmf() {
        // The ∞ arm is the exact Poisson(3) law: enumerated pmf (cells
        // 0..=7 plus lumped tail) against the sampler.
        let out = nb_sample(
            &mut MsRng::from_stream(555, StreamId::ZERO),
            &[3.0],
            f64::INFINITY,
            200_000,
        );
        let f = empirical_freqs(&out, 8);
        let mut exact: Vec<f64> = (0..8u64)
            .map(|k| {
                (-3.0 + k as f64 * 3.0f64.ln() - ln_gamma(k as f64 + 1.0)).exp()
            })
            .collect();
        exact.push(1.0 - exact.iter().sum::<f64>());
        for (k, (&fk, &pk)) in f.iter().zip(&exact).enumerate() {
            assert!((fk - pk).abs() < 0.005, "k={k}: f={fk}, p={pk}");
        }
    }

    // ==================================================================
    // NB moments: E[X] = mean, Var = mean + mean²/size (brief: MC
    // relative error < 5% at large n)
    // ==================================================================

    #[test]
    fn nb_mean_matches_across_sizes() {
        let mean = [50.0, 100.0, 200.0, 25.0];
        for size in [2.0, 8.0, 200.0] {
            let out = nb_sample(&mut MsRng::from_stream(314, StreamId::ZERO), &mean, size, 100_000);
            for (c, &m) in mean.iter().enumerate() {
                let xbar = out.chunks(mean.len()).map(|r| r[c] as f64).sum::<f64>() / 100_000.0;
                assert!(
                    (xbar / m - 1.0).abs() < 0.05,
                    "size {size}, channel {c} (mean {m}): x̄ = {xbar}"
                );
            }
        }
    }

    #[test]
    fn nb_variance_matches_formula() {
        // Var = μ + μ²/κ, pinned at κ ∈ {2, 8, 50} for μ = 100
        // (targets 6000 / 2250 / 1300; empirical-variance SD ≈ 0.5–0.8%).
        let m = 100.0_f64;
        for size in [2.0, 8.0, 50.0] {
            let target = m + m * m / size;
            let out = nb_sample(&mut MsRng::from_stream(271, StreamId::ZERO), &[m], size, 100_000);
            let (xbar, var) = sample_mean_var(&out);
            assert!((xbar / m - 1.0).abs() < 0.05, "size {size}: x̄ = {xbar}");
            assert!(
                (var / target - 1.0).abs() < 0.05,
                "size {size}: var {var} vs target {target}"
            );
        }
    }

    #[test]
    fn nb_variance_monotone_towards_poisson_limit() {
        // size → ∞ approaches Poisson monotonically: |Var(κ) − μ| strictly
        // decreases over the frozen grid; the ∞ arm sits within noise of
        // the Poisson variance μ (SD ≈ 0.3% here, window 3%).
        let m = 100.0_f64;
        let mut gaps = Vec::new();
        for size in [2.0, 8.0, 50.0, 200.0, f64::INFINITY] {
            let out = nb_sample(
                &mut MsRng::from_stream(0xBEEF, StreamId { replicate: 5, rank: 0, fold: 0 }),
                &[m],
                size,
                200_000,
            );
            gaps.push((sample_mean_var(&out).1 - m).abs());
        }
        for w in gaps.windows(2) {
            assert!(w[0] > w[1], "|Var−μ| not decreasing: {gaps:?}");
        }
        assert!(gaps[4] < 0.03 * m, "Poisson-arm residual: {}", gaps[4]);
    }

    #[test]
    fn nb_moments_large_mean_smoke() {
        // High-TMB channel (μ = 10⁵, κ = 8): SE(x̄) ≈ 0.8%, SD(var) ≈ 3.7%.
        let m = 100_000.0_f64;
        let target = m + m * m / 8.0;
        let out = nb_sample(&mut MsRng::from_stream(0xCAFE, StreamId::ZERO), &[m], 8.0, 2_000);
        let (xbar, var) = sample_mean_var(&out);
        assert!((xbar / m - 1.0).abs() < 0.05, "x̄ = {xbar}");
        assert!((var / target - 1.0).abs() < 0.15, "var {var} vs {target}");
    }

    #[test]
    fn nb_moments_huge_finite_size_near_poisson() {
        // Finite size 1e8 ≈ Poisson (Var = μ + μ²/1e8). Documented mild
        // precision loss from the MT tail-test cancellation at huge shapes
        // — the exact Poisson arm is +∞, finite 1e8 gets a loose window.
        let m = 50.0_f64;
        let out = nb_sample(&mut MsRng::from_stream(0xF00D, StreamId::ZERO), &[m], 1e8, 100_000);
        let (xbar, var) = sample_mean_var(&out);
        assert!((xbar / m - 1.0).abs() < 0.05, "x̄ = {xbar}");
        assert!((var / m - 1.0).abs() < 0.10, "var = {var}");
    }

    #[test]
    fn nb_small_mean_zero_fraction_matches_closed_form() {
        // P(X = 0) = (κ/(κ+μ))^κ for NB(μ, κ): (2/2.01)² ≈ 0.99007.
        let (m, kappa) = (0.01_f64, 2.0);
        let p0 = (kappa / (kappa + m)).powf(kappa);
        let out = nb_sample(&mut MsRng::from_stream(0x5EED, StreamId::ZERO), &[m], kappa, 200_000);
        let f0 = out.iter().filter(|&&c| c == 0).count() as f64 / out.len() as f64;
        assert!((f0 - p0).abs() < 0.002, "f0 = {f0}, p0 = {p0}");
    }

    // ==================================================================
    // κ sensitivity scan (nb_sample_size_scan)
    // ==================================================================

    #[test]
    fn scan_shape_layout_five_arms() {
        let mean = [10.0, 3.0];
        let sizes = [2.0, 8.0, 50.0, 200.0, f64::INFINITY];
        let arms = nb_sample_size_scan(&mean, &sizes, 25, &mut MsRng::from_stream(9, StreamId::ZERO));
        assert_eq!(arms.len(), sizes.len());
        for arm in &arms {
            assert_eq!(arm.len(), 25 * mean.len());
        }
    }

    #[test]
    fn scan_variance_monotone_in_size() {
        // Same mean, different size: empirical variance strictly decreases
        // over the frozen grid in ONE call on ONE stream (gaps ≥ 11%, MC
        // noise < 1%).
        let m = 100.0_f64;
        let sizes = [2.0, 8.0, 50.0, 200.0, f64::INFINITY];
        let arms = nb_sample_size_scan(&[m], &sizes, 200_000, &mut MsRng::from_stream(0xA11CE, StreamId::ZERO));
        let vars: Vec<f64> = arms.iter().map(|a| sample_mean_var(a).1).collect();
        for w in vars.windows(2) {
            assert!(w[0] > w[1], "vars not strictly decreasing: {vars:?}");
        }
    }

    #[test]
    fn scan_arm_means_match_mean_vector() {
        let mean = [30.0, 120.0];
        let sizes = [2.0, 8.0, f64::INFINITY];
        let arms = nb_sample_size_scan(&mean, &sizes, 60_000, &mut MsRng::from_stream(0xB0B, StreamId::ZERO));
        for arm in &arms {
            for (c, &m) in mean.iter().enumerate() {
                let xbar = arm.chunks(mean.len()).map(|r| r[c] as f64).sum::<f64>() / 60_000.0;
                assert!((xbar / m - 1.0).abs() < 0.05, "c={c}: x̄={xbar}, μ={m}");
            }
        }
    }

    #[test]
    fn scan_rerun_bit_identical_and_seed_sensitive() {
        let mean = [4.0, 9.0];
        let sizes = [2.0, 8.0, f64::INFINITY];
        let a = nb_sample_size_scan(&mean, &sizes, 40, &mut MsRng::from_stream(77, StreamId::ZERO));
        let b = nb_sample_size_scan(&mean, &sizes, 40, &mut MsRng::from_stream(77, StreamId::ZERO));
        assert_eq!(a, b);
        let c = nb_sample_size_scan(&mean, &sizes, 40, &mut MsRng::from_stream(78, StreamId::ZERO));
        assert_ne!(a, c);
    }

    #[test]
    fn scan_arms_pairwise_distinct() {
        let mean = [4.0, 9.0];
        let sizes = [2.0, 8.0, 50.0, f64::INFINITY];
        let arms =
            nb_sample_size_scan(&mean, &sizes, 40, &mut MsRng::from_stream(99, StreamId::ZERO));
        for i in 0..arms.len() {
            for j in (i + 1)..arms.len() {
                assert_ne!(arms[i], arms[j], "arms {i}/{j} identical");
            }
        }
    }

    #[test]
    fn scan_accepts_duplicate_and_infinity_arms() {
        // Duplicate arms are independent draws (sequential stream), and the
        // ∞ arm is legal anywhere in the list.
        let arms = nb_sample_size_scan(
            &[5.0],
            &[f64::INFINITY, f64::INFINITY],
            16,
            &mut MsRng::from_stream(1, StreamId::ZERO),
        );
        assert_eq!(arms.len(), 2);
        assert_ne!(arms[0], arms[1], "sequential consumption must differ");
    }

    // ==================================================================
    // NB boundaries
    // ==================================================================

    #[test]
    fn nb_mean_all_zero_all_sizes() {
        for size in [0.5, 2.0, 8.0, f64::INFINITY] {
            assert_eq!(
                nb_sample(&mut MsRng::from_stream(3, StreamId::ZERO), &[0.0, 0.0, 0.0], size, 5),
                vec![0; 15]
            );
        }
    }

    #[test]
    fn nb_tiny_mean_underflows_to_exact_zeros() {
        // mean = 1e-300: the mixed rate λ ≤ gamma·1e-300/2 < 1e-299 gives
        // P(any nonzero in 4·10⁴ draws) < 10⁻²⁹⁴ — exact zeros for ANY
        // stream words, not merely with high probability.
        for size in [2.0, f64::INFINITY] {
            assert_eq!(
                nb_sample(&mut MsRng::from_stream(11, StreamId::ZERO), &[1e-300], size, 40_000),
                vec![0; 40_000]
            );
        }
    }

    #[test]
    fn nb_n_zero_returns_empty_and_leaves_stream_untouched() {
        let mut a = MsRng::from_stream(42, StreamId::ZERO);
        assert!(nb_sample(&mut a, &[3.0, 4.0], 8.0, 0).is_empty());
        let mut b = MsRng::from_stream(42, StreamId::ZERO);
        assert_eq!(a.next_u64(), b.next_u64());
    }

    #[test]
    fn nb_single_channel_k_one() {
        let out = nb_sample(
            &mut MsRng::from_stream(6, StreamId { replicate: 2, rank: 0, fold: 1 }),
            &[7.0],
            8.0,
            1_000,
        );
        assert_eq!(out.len(), 1_000);
        assert!(out.iter().all(|&c| c < 100_000));
    }

    #[test]
    fn nb_support_grid_sweep_no_panic() {
        // The full supported regime: boost path (0.5), the size anchors,
        // the huge-finite shape, the ∞ arm × degenerate/tiny/small/large
        // means. Everything finite, nothing panics.
        for size in [0.5, 1.0, 2.0, 8.0, 50.0, 200.0, 1e8, f64::INFINITY] {
            for &m in &[0.0, 1e-300, 0.01, 1.0, 100.0, 1e6] {
                let out = nb_sample(&mut MsRng::from_stream(0xFEED, StreamId::ZERO), &[m], size, 8);
                assert_eq!(out.len(), 8);
                assert!(out.iter().all(|&c| c < u64::MAX / 2));
            }
        }
    }

    #[test]
    fn nb_mean_cap_boundary_is_accepted() {
        // The documented regime boundary is inclusive.
        assert_eq!(validate_nb_sample(&[NB_MEAN_MAX], 8.0, 2), Ok(()));
        let out = nb_sample(&mut MsRng::from_stream(2, StreamId::ZERO), &[NB_MEAN_MAX], 8.0, 2);
        assert_eq!(out.len(), 2);
    }

    // ==================================================================
    // NB determinism and consumption order (data-dependent but pure)
    // ==================================================================

    #[test]
    fn nb_same_seed_stream_bit_identical() {
        let mean = [2.5, 7.0, 0.5];
        let stream = StreamId { replicate: 4, rank: 2, fold: 9 };
        let a = nb_sample(&mut MsRng::from_stream(0xFEED, stream), &mean, 8.0, 60);
        let b = nb_sample(&mut MsRng::from_stream(0xFEED, stream), &mean, 8.0, 60);
        assert_eq!(a, b);
        let c = nb_sample(&mut MsRng::from_stream(0xFEED, stream), &mean, f64::INFINITY, 60);
        let d = nb_sample(&mut MsRng::from_stream(0xFEED, stream), &mean, f64::INFINITY, 60);
        assert_eq!(c, d);
    }

    #[test]
    fn nb_different_master_seed_differs() {
        let mean = [2.5, 7.0];
        let a = nb_sample(&mut MsRng::from_stream(1, StreamId::ZERO), &mean, 8.0, 50);
        let b = nb_sample(&mut MsRng::from_stream(2, StreamId::ZERO), &mean, 8.0, 50);
        assert_ne!(a, b);
    }

    #[test]
    fn nb_replicate_streams_pairwise_distinct() {
        let mean = [3.0, 5.0, 11.0];
        let mut rows = Vec::new();
        for r in 0..12u64 {
            let mut rng = MsRng::from_stream(11, StreamId { replicate: r, rank: 0, fold: 0 });
            rows.push(nb_sample(&mut rng, &mean, 8.0, 1));
        }
        for i in 0..rows.len() {
            for j in (i + 1)..rows.len() {
                assert_ne!(rows[i], rows[j], "replicate rows {i}/{j} collide");
            }
        }
    }

    #[test]
    fn nb_consumption_order_is_row_major_gamma_then_poisson() {
        // Replay through the single-draw primitive pins the documented
        // visit order (replicate-major, channel-minor) AND the zero-mean
        // no-word policy (the replay skipping zero-mean channels sits at
        // the same stream position afterwards).
        let mean = [2.5, 0.0, 7.0];
        let size = 8.0_f64;
        let n = 5_u64;
        let stream = StreamId { replicate: 1, rank: 2, fold: 3 };
        let got = nb_sample(&mut MsRng::from_stream(2024, stream), &mean, size, n);
        let mut b = MsRng::from_stream(2024, stream);
        let mut expected = Vec::new();
        for _ in 0..n {
            for &m in &mean {
                expected.push(nb_draw_one(&mut b, m, size));
            }
        }
        assert_eq!(got, expected);
        // Zero-mean channels consumed nothing: b's tail equals that of a
        // replay that skipped them entirely.
        let mut d = MsRng::from_stream(2024, stream);
        for _ in 0..n {
            for &m in &mean {
                if m != 0.0 {
                    nb_draw_one(&mut d, m, size);
                }
            }
        }
        assert_eq!(b.next_u64(), d.next_u64());
    }

    #[test]
    fn nb_poisson_inversion_consumes_exactly_one_word() {
        // The Poisson step's own accounting is fixed: one word per draw,
        // including the rate = 0 degenerate path.
        for rate in [0.0, 1e-3, 7.5, 100.0] {
            let stream = StreamId { replicate: 3, rank: 1, fold: 1 };
            let mut a = MsRng::from_stream(9, stream);
            let _ = poisson_variate(&mut a, rate);
            let tail = a.next_u64();
            let mut b = MsRng::from_stream(9, stream);
            b.next_u64();
            assert_eq!(tail, b.next_u64(), "rate {rate} must consume exactly one word");
        }
    }

    #[test]
    fn nb_poisson_primitive_matches_exact_moments() {
        // Primitive-level cross-check of the inversion against the exact
        // Poisson moments (rate 7.5, n = 2·10⁵).
        let mut rng = MsRng::from_stream(0x1234, StreamId::ZERO);
        let draws: Vec<u64> = (0..200_000).map(|_| poisson_variate(&mut rng, 7.5)).collect();
        let (xbar, var) = sample_mean_var(&draws);
        assert!((xbar / 7.5 - 1.0).abs() < 0.05, "x̄ = {xbar}");
        assert!((var / 7.5 - 1.0).abs() < 0.10, "var = {var}");
    }

    #[test]
    fn nb_output_is_pure_function_of_stream_prefix() {
        // Warming the stream with 3 words then sampling equals skipping
        // those words on a fresh instance — call context never leaks in.
        let mean = [6.0, 1.0];
        let stream = StreamId { replicate: 8, rank: 0, fold: 2 };
        let mut warm = MsRng::from_stream(0xABCD, stream);
        for _ in 0..3 {
            warm.next_u64();
        }
        let a = nb_sample(&mut warm, &mean, 8.0, 20);
        let mut fresh = MsRng::from_stream(0xABCD, stream);
        for _ in 0..3 {
            fresh.next_u64();
        }
        assert_eq!(a, nb_sample(&mut fresh, &mean, 8.0, 20));
    }

    // ==================================================================
    // NB input contract (raw primitive panics + structured validation)
    // ==================================================================

    #[test]
    #[should_panic(expected = "at least one channel")]
    fn nb_panics_on_empty_mean() {
        nb_sample(&mut MsRng::from_stream(1, StreamId::ZERO), &[], 8.0, 3);
    }

    #[test]
    #[should_panic(expected = "negative entry")]
    fn nb_panics_on_negative_mean() {
        nb_sample(&mut MsRng::from_stream(1, StreamId::ZERO), &[1.0, -2.0], 8.0, 3);
    }

    #[test]
    #[should_panic(expected = "non-finite entry")]
    fn nb_panics_on_nan_mean() {
        nb_sample(&mut MsRng::from_stream(1, StreamId::ZERO), &[f64::NAN], 8.0, 3);
    }

    #[test]
    #[should_panic(expected = "size must be positive")]
    fn nb_panics_on_zero_size() {
        nb_sample(&mut MsRng::from_stream(1, StreamId::ZERO), &[1.0], 0.0, 3);
    }

    #[test]
    #[should_panic(expected = "no NaN")]
    fn nb_panics_on_nan_size() {
        nb_sample(&mut MsRng::from_stream(1, StreamId::ZERO), &[1.0], f64::NAN, 3);
    }

    #[test]
    #[should_panic(expected = "supported regime")]
    fn nb_rate_guard_panics_on_pathological_combo() {
        // A denormal size boosts the gamma to the degenerate 0 while the
        // scale overflows — the mixed rate leaves the supported regime and
        // the internal guard fires (programming-error contract).
        nb_sample(&mut MsRng::from_stream(1, StreamId::ZERO), &[NB_MEAN_MAX], 5e-324, 1);
    }

    #[test]
    fn nb_validate_error_payloads() {
        assert_eq!(
            validate_nb_sample(&[], 8.0, 0),
            Err(MsError::new("argument", "mean vector must contain at least one channel"))
        );
        assert_eq!(
            validate_nb_sample(&[0.5, f64::NAN], 8.0, 5),
            Err(MsError::new("na", "non-finite entry in mean vector").with_i(2))
        );
        assert_eq!(
            validate_nb_sample(&[0.5, -1.0], 8.0, 5),
            Err(MsError::new("argument", "negative entry in mean vector").with_i(2))
        );
        assert_eq!(
            validate_nb_sample(&[NB_MEAN_MAX * 10.0], 8.0, 5),
            Err(MsError::new("argument", "channel mean exceeds the supported regime").with_i(1))
        );
        assert_eq!(
            validate_nb_sample(&[1.0], f64::NAN, 5),
            Err(MsError::new("na", "size must be finite or +inf (no NaN)"))
        );
        assert_eq!(
            validate_nb_sample(&[1.0], 0.0, 5),
            Err(MsError::new(
                "argument",
                "size must be positive (or +inf for the exact Poisson arm)"
            ))
        );
        assert_eq!(
            validate_nb_sample(&[1.0], NB_RATE_MAX * 10.0, 5),
            Err(MsError::new("argument", "finite size exceeds the supported regime"))
        );
        // +inf is the legal Poisson arm; the caps are inclusive.
        assert_eq!(validate_nb_sample(&[1.0, 2.0], f64::INFINITY, 5), Ok(()));
        assert_eq!(validate_nb_sample(&[NB_MEAN_MAX], NB_RATE_MAX, 5), Ok(()));
    }

    #[test]
    #[should_panic(expected = "at least one arm")]
    fn scan_panics_on_empty_sizes() {
        nb_sample_size_scan(&[1.0], &[], 3, &mut MsRng::from_stream(1, StreamId::ZERO));
    }

    #[test]
    #[should_panic(expected = "arm 1")]
    fn scan_panics_on_bad_arm() {
        nb_sample_size_scan(&[1.0], &[8.0, -3.0], 3, &mut MsRng::from_stream(1, StreamId::ZERO));
    }
}
