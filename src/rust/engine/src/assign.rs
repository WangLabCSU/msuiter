//! Per-mutation signature assignment and per-signature transcriptional
//! strand-bias testing (U-M3a-04; `docs/CAPABILITY-MATRIX.md` L-D "每突变分配:
//! 比例分配 + unassigned 残差伪签名" and L-E "每签名 TSB 检验: 泊松/二项
//! UTS-vs-TS + 不确定性传播", `docs/ARCHITECTURE.md` §5 post-fit analysis,
//! `docs/research/02` §1/§5).
//!
//! # Per-mutation assignment — upstream semantics (pinned to source, D11/D13)
//!
//! The proportional allocation is the "responsibility" reading of the fitted
//! factorization: every observed mutation in catalog cell `(i, j)` is split
//! across signatures in proportion to each signature's contribution to the
//! reconstruction,
//!
//! ```text
//! c[i,j,s] = v[i,j] · w[i,s] · h[s,j] / (WH)[i,j]
//! ```
//!
//! which is *numerically the same quantity* as the soft-EM E-step attribution
//! count of the audited KL-NMF (see the `crate::nmf` module docs, equation for
//! `c[i,j,s]`) — D11 protocol equivalence by construction, and the reason this
//! module reuses [`crate::nmf::matmul`] verbatim for the denominator.
//!
//! Semantic anchors (verified against upstream source):
//!
//! * **SigProfilerAssignment `probabilities(W, H)`** —
//!   `SigProfilerAssignment/decompose_subroutines.py` (research/02 §1.4, line
//!   60, pinned there to `decompose_subroutines.py:1694`):
//!   `probs = W * H[:, i] / M.T` with `M = np.dot(W, H)` — the same
//!   exposure-weighted channel responsibility, applied per sample and joined
//!   back to per-mutation rows. Upstream performs the division raw: a cell
//!   with zero reconstruction produces NaN, and the downstream per-mutation
//!   join (`probabilities_per_mutation`) then silently *drops* such mutations
//!   (inner merge).
//! * **signature.tools.lib `assignMutationsSignatureProbability.R:12-120`**
//!   (research/04 §5): the equivalent exposure-weighted channel posterior,
//!   plus the optional **"unassigned" pseudo-signature = positive part of
//!   (catalogue − reconstruction)** (research/02 §1.5, line 66).
//! * **MuSiCal has no native per-mutation assignment face** (verified against
//!   parklab/MuSiCal `main`: `musical/refit.py::assign` is match-then-refit
//!   deconvolution — W_s/H_s/sig_map outputs, no responsibilities; no module
//!   computes `W·H/(WH)` per cell). The per-mutation semantics therefore
//!   anchor to SPA/STL above, with MuSiCal contributing the NNLS/refit fit
//!   whose `(W, H)` this module consumes.
//!
//! **Zero-reconstruction cells (documented deviation).** When `(WH)[i,j] = 0`
//! the responsibilities are 0/0 — mathematically undefined. SPA emits NaN and
//! then drops the mutations; msuiter instead routes the *entire* observed mass
//! of such a cell to the unassigned pseudo-signature (`c[·,·,s] = 0`),
//! which is the limit of the responsibility as the reconstruction vanishes.
//! No special-case branch is needed: with the [`crate::nmf::KL_EPS`] floor on
//! the denominator the numerators `v·w·h` are exactly 0 there, so the guard
//! produces the documented semantics by construction. No NaN/Inf is ever
//! returned on validated input (ARCHITECTURE §2.3).
//!
//! **Mass accounting (the two outputs measure different things).** The
//! allocation is mass-conserving per cell: `Σ_s c[i,j,s] = v[i,j]` whenever
//! `(WH)[i,j] > 0` — every observed mutation receives a fractional signature
//! even where the model *under*-reconstructs. The unassigned pseudo-signature
//! `u[i,j] = max(v[i,j] − (WH)[i,j], 0)` is the residual diagnostic tracked
//! alongside (STL semantics), *not* carved out of the allocation: it is the
//! channel catalog a residual-only "signature" would carry. With an exact
//! reconstruction (`v = WH`) both statements coincide: nothing is unassigned.
//!
//! # Transcriptional strand bias (TSB) — semantic anchor statement
//!
//! Design line (research/02 §5(b), the audit of record): *no tool computes
//! per-signature TSB natively* — mmsig and signature.tools.lib are
//! sample-level; the msuiter design is per-mutation assignment probabilities ×
//! strand annotation → per-signature UTS-vs-TS tests. The test semantics are
//! pinned to **MutationalPatterns `strand_bias_test`**
//! (`UMCUGenetics/MutationalPatterns`, `R/strand_bias_test.R`:
//! `stats::poisson.test(c(ts, uts), r = 1, alternative = "two.sided")`, with
//! the upstream source comment *"Is the same as binom in this scenario"*;
//! mmsig reuses the same machinery per mm1 context, research/04 §4):
//!
//! * **Null model** `H0`: the signature's mutation rate is equal on the
//!   transcribed (TS) and untranscribed (UTS) strand.
//! * **Exact conditional test.** For strand masses `(uts, ts)` (integer
//!   counts), condition on the total `n = uts + ts`: under `H0` the UTS count
//!   is `Bin(n, 1/2)` — this is simultaneously (i) the exact two-sample
//!   Poisson rate test at `r = 1` (`poisson.test`) and (ii) the exact
//!   binomial test at `p0 = 1/2` (`binom.test`); the two upstream flavors are
//!   the same test, which is why [`TsbTest`] carries both faces.
//! * **Two-sided p-value** — the R `binom.test`/`poisson.test` point-mass
//!   convention: `p = Σ {k : pmf(k) ≤ pmf(observed)}`, which at `p0 = 1/2`
//!   reduces exactly to the doubled minimum tail
//!   `p = P(X ≤ lo) + P(X ≥ hi)` (rejection region `[0, lo] ∪ [hi, n]`, `lo ≤
//!   hi` the sorted masses; symmetry makes the two tails equal, and at
//!   `lo = hi = n/2` the observed value is the mode, so `p = 1`). Pinned
//!   against a brute-force reference sum in tests.
//! * **p-value engine** — exact log-space summation of the `Bin(n, 1/2)` pmf
//!   over the rejection region, walking outward from the region boundary with
//!   the exact pmf recursion `pmf(k±1)/pmf(k) = (n∓k)/(k±1)` (stable: terms
//!   decrease monotonically away from the mode; terms below `exp(−745)`
//!   underflow to 0 and are dropped, validly, since everything further out is
//!   smaller). This works at any `n`; the textbook incomplete-beta route
//!   cannot (its front factor `2^{−(n+1)}/B` underflows f64 beyond
//!   `n ≈ 1020`), so the summation form *is* the frozen protocol.
//! * **Fractional masses (uncertainty propagation).** Per-signature TS/UTS
//!   totals are *expected* masses from the fractional assignment — the
//!   capability-matrix "不确定性传播" carrier (assignment probabilities, not
//!   hard calls, enter the test). The exact test extends continuously by
//!   linear-in-pmf interpolation of each discrete tail between its bounding
//!   integers: for `hi ∈ (m, m+1)`,
//!   `P(X ≥ hi) ≔ P(X ≥ m+1) + (m+1−hi)·pmf(m)` (mirrored below). At integer
//!   masses the interpolation weight is exactly 1/0 and the exact test falls
//!   out; the extension is monotone and continuous, pinned by tests. This is
//!   a declared msuiter protocol choice (no upstream exists to match — the
//!   per-signature face is greenfield per research/02 §5(b)).
//! * **Modes and reported statistics.** [`TsbTest::Poisson`] reports the rate
//!   ratio `uts/ts` (the `poisson.test` estimate of `r`); [`TsbTest::Binomial`]
//!   reports the UTS fraction `uts/n` (the binomial proportion). Both share
//!   the identical p-value engine and direction — their equivalence at
//!   `r = 1` is the pinned MutationalPatterns statement.
//! * **Direction** — [`TsbDirection::UtsEnriched`] / [`TsbDirection::TsEnriched`]
//!   / [`TsbDirection::Symmetric`] by exact comparison of the two masses.
//!
//! Citations: MutationalPatterns doi:10.1186/s13059-018-1502-4 (Genome Biol
//! 2018); MuSiCal doi:10.1038/s41588-024-01659-0; SigProfilerAssignment
//! (research/02 §1.4); signature.tools.lib (research/04 §5).
//!
//! # Numerical hygiene (zero pseudocounts, ε policy)
//!
//! ε (`KL_EPS`) enters only as a division floor on the reconstruction
//! denominator, exactly as in `crate::nmf`; it never adds mass to counts or
//! factors. The TSB engine uses no ε at all — log-space pmf evaluation needs
//! no guard beyond the underflow cutoff documented above.
//!
//! # Determinism
//!
//! Pure sequential kernels, fixed loop order, single-threaded, no hashing:
//! identical inputs give bit-identical outputs (ARCHITECTURE §2.6).
//!
//! # Contract notes
//!
//! Pure engine kernel: no FFI face, no `unsafe`, no dependencies; every
//! entry point returns `Result<_, MsError>` (FFI contract 5). The R/VCF
//! wiring (joining assignments back to mutation rows) is a later unit.

use crate::error::MsError;
use crate::likelihood::ln_gamma;
use crate::nmf::{matmul, KL_EPS};

// ---------------------------------------------------------------------------
// Per-mutation assignment
// ---------------------------------------------------------------------------

/// Result of [`assign_per_mutation`].
#[derive(Debug, Clone, PartialEq)]
pub struct PerMutationAssignment {
    /// Per-mutation signature responsibilities, row-major `m×n×k` with index
    /// `(i·n + j)·k + s`: the fraction of catalog cell `(i, j)`'s count
    /// attributed to signature `s`. Cell-wise `Σ_s assignments = counts[i,j]`
    /// whenever the reconstruction `(WH)[i,j] > 0`; exactly 0 for every `s`
    /// where the reconstruction is 0 (that mass moves to `unassigned`).
    pub assignments: Vec<f64>,
    /// Unassigned residual pseudo-signature, row-major `m×n`:
    /// `max(counts − WH, 0)` per channel and sample (signature.tools.lib
    /// semantics). Zero-reconstruction cells carry their full observed count
    /// here. This is a residual diagnostic, not part of the allocation.
    pub unassigned: Vec<f64>,
}

/// Proportional per-mutation assignment of a catalog onto a fitted
/// `(W, H)` factorization (module docs carry the full semantic anchor
/// statement).
///
/// * `counts` — row-major `m×n` catalog (channels × samples),
/// * `w` — row-major `m×k` signature matrix,
/// * `h` — row-major `k×n` exposure matrix.
///
/// Errors ([`MsError`]): zero dimension or storage-size mismatch
/// (`"argument"`, sizes attached as `i`/`j`); non-finite entries (`"na"`,
/// 1-based position); negative entries (`"argument"`, 1-based position) —
/// mirroring `crate::nmf` validation so both kernels reject identical inputs.
pub fn assign_per_mutation(
    counts: &[f64],
    w: &[f64],
    h: &[f64],
    m: usize,
    n: usize,
    k: usize,
) -> Result<PerMutationAssignment, MsError> {
    validate_catalog(counts, w, h, m, n, k)?;
    let wh = matmul(w, h, m, n, k);
    let mut assignments = vec![0.0f64; m * n * k];
    let mut unassigned = vec![0.0f64; m * n];
    for i in 0..m {
        for j in 0..n {
            let v = counts[i * n + j];
            let recon = wh[i * n + j];
            // ε floor on the denominator (nmf.rs policy). Where the
            // reconstruction is exactly 0, every numerator v·w·h is 0 too,
            // so the responsibility is exactly 0: the documented
            // zero-reconstruction semantics fall out of the guard — the
            // cell's observed mass lands in `unassigned` instead.
            let denom = recon.max(KL_EPS);
            let cell = (i * n + j) * k;
            for s in 0..k {
                assignments[cell + s] = v * w[i * k + s] * h[s * n + j] / denom;
            }
            unassigned[i * n + j] = (v - recon).max(0.0);
        }
    }
    Ok(PerMutationAssignment { assignments, unassigned })
}

/// Validate the `(counts, w, h)` triple for [`assign_per_mutation`], with the
/// same topics and 1-based positional conventions as `crate::nmf`.
fn validate_catalog(
    counts: &[f64],
    w: &[f64],
    h: &[f64],
    m: usize,
    n: usize,
    k: usize,
) -> Result<(), MsError> {
    if m == 0 || n == 0 || k == 0 {
        return Err(MsError::new("argument", "matrix dimensions must be positive")
            .with_i(m as i64)
            .with_j(n as i64));
    }
    if counts.len() != m * n {
        return Err(
            MsError::new("argument", "counts storage must be m*n elements")
                .with_i(counts.len() as i64),
        );
    }
    if w.len() != m * k {
        return Err(
            MsError::new("argument", "w storage must be m*k elements").with_i(w.len() as i64),
        );
    }
    if h.len() != k * n {
        return Err(
            MsError::new("argument", "h storage must be k*n elements").with_i(h.len() as i64),
        );
    }
    for (idx, &x) in counts.iter().enumerate() {
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
    for (name, mat) in [("w", w), ("h", h)] {
        for (idx, &x) in mat.iter().enumerate() {
            if !x.is_finite() {
                return Err(MsError::new("na", format!("non-finite entry in {name}"))
                    .with_i(idx as i64 + 1));
            }
            if x < 0.0 {
                return Err(MsError::new("argument", format!("negative entry in {name}"))
                    .with_i(idx as i64 + 1));
            }
        }
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Transcriptional strand bias (TSB)
// ---------------------------------------------------------------------------

/// Flavor of the strand-bias test (module docs "Modes and reported
/// statistics"): both are the same exact conditional test at `r = 1`
/// (MutationalPatterns: "Is the same as binom in this scenario"); they differ
/// only in the reported effect-size statistic.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TsbTest {
    /// Exact two-sample Poisson rate test at `r = 1` (`poisson.test`
    /// semantics); statistic = rate ratio `uts/ts`.
    Poisson,
    /// Exact binomial test at `p0 = 1/2` (`binom.test` semantics);
    /// statistic = UTS fraction `uts/(uts + ts)`.
    Binomial,
}

/// Direction of an observed transcriptional strand bias.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TsbDirection {
    /// More assigned mass on the untranscribed strand.
    UtsEnriched,
    /// More assigned mass on the transcribed strand.
    TsEnriched,
    /// Equal masses on both strands (no bias).
    Symmetric,
}

/// Outcome of one transcriptional strand-bias test.
#[derive(Debug, Clone, PartialEq)]
pub struct TsbResult {
    /// Total transcribed-strand mass (count, or assigned expectation).
    pub ts: f64,
    /// Total untranscribed-strand mass (count, or assigned expectation).
    pub uts: f64,
    /// Effect-size statistic: rate ratio `uts/ts` for [`TsbTest::Poisson`]
    /// (`+inf` when `ts = 0 < uts`), UTS fraction `uts/n` for
    /// [`TsbTest::Binomial`]; `0.0` for the degenerate all-zero input.
    pub statistic: f64,
    /// Two-sided exact conditional p-value under `H0: rate(TS) = rate(UTS)`
    /// (module docs; exact at integer masses, continuous extension at
    /// fractional assigned masses).
    pub p_value: f64,
    /// Direction of the observed bias.
    pub direction: TsbDirection,
}

/// Core strand-pair test on `(uts, ts)` masses (module docs carry the full
/// semantic anchor statement).
///
/// Integer masses reproduce the exact `poisson.test(c(uts, ts), r = 1)` /
/// `binom.test(uts, n, p = 1/2)` p-value; fractional masses (per-signature
/// assigned expectations) use the documented continuous extension.
///
/// Errors ([`MsError`]): non-finite (`"na"`) or negative (`"argument"`)
/// masses, 1-based (`i = 1` for `uts`, `i = 2` for `ts`).
pub fn tsb_test(uts: f64, ts: f64, test: TsbTest) -> Result<TsbResult, MsError> {
    validate_mass(uts, 1)?;
    validate_mass(ts, 2)?;
    Ok(tsb_result(uts, ts, test))
}

/// Raw-count face with per-channel strand annotation: aggregates channel
/// counts on each strand (`ts_mask[i] == true` → transcribed) and runs
/// [`tsb_test`] on the totals — the MutationalPatterns-style sample-level
/// test, with counts enforced integral.
///
/// Errors ([`MsError`]): empty counts or mask-length mismatch
/// (`"argument"`); non-finite (`"na"`), negative or non-integral channel
/// counts (`"argument"`, 1-based channel index).
pub fn tsb_test_stranded(
    counts: &[f64],
    ts_mask: &[bool],
    test: TsbTest,
) -> Result<TsbResult, MsError> {
    if counts.is_empty() {
        return Err(MsError::new("argument", "channel counts must not be empty"));
    }
    if ts_mask.len() != counts.len() {
        return Err(
            MsError::new("argument", "strand annotation must cover every channel")
                .with_i(counts.len() as i64)
                .with_j(ts_mask.len() as i64),
        );
    }
    for (i, &c) in counts.iter().enumerate() {
        if !c.is_finite() {
            return Err(MsError::new("na", "channel counts must be finite (no NaN/Inf)")
                .with_i(i as i64 + 1));
        }
        if c < 0.0 {
            return Err(MsError::new("argument", "channel counts must be non-negative")
                .with_i(i as i64 + 1));
        }
        if c != c.trunc() {
            return Err(MsError::new("argument", "channel counts must be integral")
                .with_i(i as i64 + 1));
        }
    }
    let mut uts = 0.0f64;
    let mut ts = 0.0f64;
    for (&c, &on_ts) in counts.iter().zip(ts_mask.iter()) {
        if on_ts {
            ts += c;
        } else {
            uts += c;
        }
    }
    Ok(tsb_result(uts, ts, test))
}

/// Per-signature strand-bias tests over a per-mutation assignment tensor
/// (the greenfield per-signature face of research/02 §5(b)).
///
/// `assignments` is the row-major `m×n×k` tensor from
/// [`assign_per_mutation`] (index `(i·n + j)·k + s`); `ts_mask[i] == true`
/// marks channel `i` as transcribed-strand. For each signature the TS/UTS
/// assigned masses are aggregated over all channels and samples and tested
/// with [`tsb_test`]; fractional masses use the documented continuous
/// extension (assignment probabilities — not hard calls — propagate into the
/// test).
///
/// Errors ([`MsError`]): zero dimension, storage size `≠ m·n·k`, or
/// `ts_mask.len() ≠ m` (`"argument"`); non-finite (`"na"`) or negative
/// (`"argument"`) assignment entries (1-based flat index).
pub fn tsb_test_per_signature(
    assignments: &[f64],
    m: usize,
    n: usize,
    k: usize,
    ts_mask: &[bool],
    test: TsbTest,
) -> Result<Vec<TsbResult>, MsError> {
    if m == 0 || n == 0 || k == 0 {
        return Err(MsError::new("argument", "matrix dimensions must be positive")
            .with_i(m as i64)
            .with_j(n as i64));
    }
    if assignments.len() != m * n * k {
        return Err(MsError::new(
            "argument",
            "assignments storage must be m*n*k elements",
        )
        .with_i(assignments.len() as i64));
    }
    if ts_mask.len() != m {
        return Err(
            MsError::new("argument", "strand annotation must cover every channel")
                .with_i(m as i64)
                .with_j(ts_mask.len() as i64),
        );
    }
    for (idx, &x) in assignments.iter().enumerate() {
        if !x.is_finite() {
            return Err(
                MsError::new("na", "non-finite entry in assignments").with_i(idx as i64 + 1)
            );
        }
        if x < 0.0 {
            return Err(
                MsError::new("argument", "negative entry in assignments")
                    .with_i(idx as i64 + 1),
            );
        }
    }
    let mut ts = vec![0.0f64; k];
    let mut uts = vec![0.0f64; k];
    for (i, &on_ts) in ts_mask.iter().enumerate() {
        for j in 0..n {
            let cell = (i * n + j) * k;
            for s in 0..k {
                let c = assignments[cell + s];
                if on_ts {
                    ts[s] += c;
                } else {
                    uts[s] += c;
                }
            }
        }
    }
    Ok((0..k).map(|s| tsb_result(uts[s], ts[s], test)).collect())
}

/// Validate one strand mass (`pos` = 1 for `uts`, 2 for `ts`).
fn validate_mass(x: f64, pos: i64) -> Result<(), MsError> {
    if !x.is_finite() {
        return Err(
            MsError::new("na", "strand mass must be finite (no NaN/Inf)").with_i(pos),
        );
    }
    if x < 0.0 {
        return Err(MsError::new("argument", "strand mass must be non-negative").with_i(pos));
    }
    Ok(())
}

/// Assemble the [`TsbResult`] for validated masses (shared tail of all faces).
fn tsb_result(uts: f64, ts: f64, test: TsbTest) -> TsbResult {
    let p_value = tsb_p_value(uts, ts);
    let direction = if uts > ts {
        TsbDirection::UtsEnriched
    } else if ts > uts {
        TsbDirection::TsEnriched
    } else {
        TsbDirection::Symmetric
    };
    let n = uts + ts;
    let statistic = match test {
        TsbTest::Poisson => {
            if n <= 0.0 {
                0.0
            } else {
                uts / ts
            }
        }
        TsbTest::Binomial => {
            if n <= 0.0 {
                0.0
            } else {
                uts / n
            }
        }
    };
    TsbResult { ts, uts, statistic, p_value, direction }
}

/// Two-sided exact conditional p-value at `p0 = 1/2`
/// (`p = P(X ≤ lo) + P(X ≥ hi)`, clamped to 1; module docs).
fn tsb_p_value(uts: f64, ts: f64) -> f64 {
    let n = uts + ts;
    if n <= 0.0 {
        // No data on either strand: no evidence against H0.
        return 1.0;
    }
    let hi = uts.max(ts);
    let lo = uts.min(ts);
    (tsb_tail_lower(lo, n) + tsb_tail_upper(hi, n)).min(1.0)
}

/// ln of the generalized binomial pmf at `p0 = 1/2` for integer `k` and real
/// `n ≥ k`: `C(n, k)·2^{−n}` with `C(n, k) = Γ(n+1)/(Γ(k+1)Γ(n−k+1))` (exact
/// binomial pmf at integer `n`; the analytic continuation in `n` is only ever
/// evaluated at positive Γ arguments here, see the call sites).
fn binom_pmf_ln(k: f64, n: f64) -> f64 {
    ln_gamma(n + 1.0) - ln_gamma(k + 1.0) - ln_gamma(n - k + 1.0) - n * std::f64::consts::LN_2
}

/// Underflow cutoff: `exp(−745)` is below the smallest positive subnormal, so
/// pmf terms with `ln pmf < −745` contribute exactly 0 in f64; the tails are
/// monotone away from the mode, so everything beyond the break is smaller.
const PMF_UNDERFLOW_LN: f64 = -745.0;

/// Lower tail `P(X ≤ lo)` for `X ~ Bin(n, 1/2)`, `lo ≤ n/2` (real masses use
/// the documented linear-in-pmf continuous extension; module docs).
fn tsb_tail_lower(lo: f64, n: f64) -> f64 {
    let m = lo.floor(); // lo ≥ 0 ⇒ m ≥ 0
    let mut acc = 0.0f64;
    // Walk k = m, m−1, …, 0: terms decrease monotonically (below the mode).
    let mut ln_pmf = binom_pmf_ln(m, n);
    let mut k = m;
    loop {
        if ln_pmf < PMF_UNDERFLOW_LN {
            break;
        }
        acc += ln_pmf.exp();
        if k == 0.0 {
            break;
        }
        // pmf(k−1)/pmf(k) = k/(n−k+1); denominator > 0 since k ≤ m ≤ n/2.
        ln_pmf += (k / (n - k + 1.0)).ln();
        k -= 1.0;
    }
    // Fractional boundary: P(X ≤ lo) ≔ P(X ≤ m) + (lo − m)·pmf(m+1) — at
    // integer lo the weight is 0 and the exact tail falls out.
    let frac = lo - m;
    if frac > 0.0 {
        acc += frac * binom_pmf_ln(m + 1.0, n).exp();
    }
    acc
}

/// Upper tail `P(X ≥ hi)` for `X ~ Bin(n, 1/2)`, `hi ≥ n/2` (real masses use
/// the documented linear-in-pmf continuous extension; module docs).
fn tsb_tail_upper(hi: f64, n: f64) -> f64 {
    let m = hi.floor(); // hi ≤ n ⇒ m ≤ n
    // Boundary interpolation: P(X ≥ hi) ≔ P(X ≥ m+1) + (m+1−hi)·pmf(m); at
    // integer hi the weight is exactly 1 and the exact tail falls out.
    let mut acc = (m + 1.0 - hi) * binom_pmf_ln(m, n).exp();
    // Walk k = m+1, m+2, …: terms decrease monotonically (above the mode).
    let mut ln_pmf = binom_pmf_ln(m, n);
    let mut k = m + 1.0;
    while k <= n {
        // pmf(k)/pmf(k−1) = (n−k+1)/k; numerator > 0 since k−1 < k ≤ n.
        ln_pmf += ((n - (k - 1.0)) / k).ln();
        if ln_pmf < PMF_UNDERFLOW_LN {
            break;
        }
        acc += ln_pmf.exp();
        k += 1.0;
    }
    acc
}

// ======================================================================
// Tests: hand-derived goldens (2x1/2x2/2x3 per-cell responsibility
// tensors), per-cell and per-signature mass conservation, zero-
// reconstruction and exact-reconstruction behavior, exact binomial
// p-value goldens against a brute-force reference, symmetry/extreme-
// bias/size Monte Carlo construction, poisson-binomial mode
// equivalence, fractional continuous extension, validation errors, and
// bit determinism. Fixed seeds only (MsRng, StreamId layout).
// ======================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rng::{MsRng, StreamId};

    /// Uniform in [0, 1) on the 53-bit grid (test data only).
    fn uniform(rng: &mut MsRng) -> f64 {
        (rng.next_u64() >> 11) as f64 * (1.0 / (1u64 << 53) as f64)
    }

    fn assert_close(actual: f64, expected: f64, rel: f64, what: &str) {
        let scale = expected.abs().max(1e-300);
        assert!(
            (actual - expected).abs() <= rel * scale,
            "{what}: actual {actual}, expected {expected}"
        );
    }

    // ==================================================================
    // Per-mutation assignment
    // ==================================================================

    /// Golden A (hand-derived, 2x1x2): exact reconstruction, all mass
    /// assigned, per-cell responsibilities exact rationals.
    #[test]
    fn golden_assign_2x1x2_exact_reconstruction() {
        let v = [7.0, 6.0];
        let w = [0.25, 0.75, 0.5, 0.5];
        let h = [4.0, 8.0];
        let fit = assign_per_mutation(&v, &w, &h, 2, 1, 2).unwrap();
        // wh = [7, 6]; c[i,j,s] = v * w * h / wh.
        assert_eq!(fit.assignments.len(), 2 * 1 * 2);
        assert_close(fit.assignments[0], 1.0, 1e-12, "c[0,0,0]");
        assert_close(fit.assignments[1], 6.0, 1e-12, "c[0,0,1]");
        assert_close(fit.assignments[2], 2.0, 1e-12, "c[1,0,0]");
        assert_close(fit.assignments[3], 4.0, 1e-12, "c[1,0,1]");
        // Exact reconstruction: nothing unassigned.
        assert!(fit.unassigned.iter().all(|&u| u == 0.0));
    }

    /// Golden B (hand-derived, 2x2x2): one zero-count cell, one
    /// zero-reconstruction channel, one under-reconstructed cell.
    #[test]
    fn golden_assign_2x2x2_zero_recon_and_residual() {
        let v = [5.0, 0.0, 9.0, 0.0];
        let w = [0.25, 0.75, 0.0, 0.0];
        let h = [1.0, 2.0, 3.0, 4.0];
        let fit = assign_per_mutation(&v, &w, &h, 2, 2, 2).unwrap();
        // Row 0: wh = [2.5, 3.5]. c[0,0,*] = 5*[0.25*1, 0.75*3]/2.5.
        assert_close(fit.assignments[0], 0.5, 1e-12, "c[0,0,0]");
        assert_close(fit.assignments[1], 4.5, 1e-12, "c[0,0,1]");
        // c[0,1,*]: v = 0 -> nothing to assign.
        assert_eq!(fit.assignments[2], 0.0);
        assert_eq!(fit.assignments[3], 0.0);
        // Row 1: wh = 0 (zero signature row) -> responsibilities 0,
        // all observed mass lands in the unassigned pseudo-signature.
        assert_eq!(fit.assignments[4], 0.0);
        assert_eq!(fit.assignments[5], 0.0);
        assert_eq!(fit.assignments[6], 0.0);
        assert_eq!(fit.assignments[7], 0.0);
        // unassigned = (v - wh)+ = [2.5, 0, 9, 0].
        assert_close(fit.unassigned[0], 2.5, 1e-12, "u[0,0]");
        assert_eq!(fit.unassigned[1], 0.0);
        assert_close(fit.unassigned[2], 9.0, 1e-12, "u[1,0]");
        assert_eq!(fit.unassigned[3], 0.0);
    }

    /// Golden C (hand-derived, 2x2x1): k = 1 absorbs everything
    /// (responsibility identically 1), residual is (v - wh)+.
    #[test]
    fn golden_assign_2x2x1_single_signature() {
        let v = [2.0, 0.0, 0.0, 4.0];
        let w = [1.0, 2.0];
        let h = [0.5, 0.5];
        let fit = assign_per_mutation(&v, &w, &h, 2, 2, 1).unwrap();
        // wh = [0.5, 0.5, 1.0, 1.0]; c = v * wh / wh = v.
        assert_close(fit.assignments[0], 2.0, 1e-12, "c[0,0,0]");
        assert_eq!(fit.assignments[1], 0.0);
        assert_eq!(fit.assignments[2], 0.0);
        assert_close(fit.assignments[3], 4.0, 1e-12, "c[1,1,0]");
        // unassigned = [1.5, 0, 0, 3].
        assert_close(fit.unassigned[0], 1.5, 1e-12, "u[0,0]");
        assert_close(fit.unassigned[3], 3.0, 1e-12, "u[1,1]");
        assert_eq!(fit.unassigned[1], 0.0);
        assert_eq!(fit.unassigned[2], 0.0);
    }

    /// Per-cell mass conservation on random non-negative factors:
    /// sum_s c[i,j,s] == v[i,j] whenever wh > 0 (the allocation is
    /// mass-conserving), and == 0 when wh == 0.
    #[test]
    fn assign_mass_conserves_per_cell_on_random_factors() {
        let (m, n, k) = (7usize, 5usize, 3usize);
        let mut rng = MsRng::from_stream(11, StreamId { replicate: 4, rank: 2, fold: 1 });
        let counts: Vec<f64> =
            (0..m * n).map(|_| (uniform(&mut rng) * 50.0).floor()).collect();
        let w: Vec<f64> = (0..m * k).map(|_| uniform(&mut rng)).collect();
        let h: Vec<f64> = (0..k * n).map(|_| uniform(&mut rng)).collect();
        let fit = assign_per_mutation(&counts, &w, &h, m, n, k).unwrap();
        let wh = crate::nmf::matmul(&w, &h, m, n, k);
        for i in 0..m {
            for j in 0..n {
                let mut s = 0.0;
                for sig in 0..k {
                    s += fit.assignments[(i * n + j) * k + sig];
                }
                if wh[i * n + j] > 0.0 {
                    assert_close(s, counts[i * n + j], 1e-9, "cell conservation");
                } else {
                    assert_eq!(s, 0.0, "zero-recon cell assigns nothing");
                    assert_close(
                        fit.unassigned[i * n + j],
                        counts[i * n + j],
                        0.0,
                        "zero-recon cell fully unassigned",
                    );
                }
            }
        }
    }

    /// Exact reconstruction (v = W·H, W columns normalized to sum 1):
    /// unassigned is exactly zero everywhere and the per-sample
    /// per-signature allocation reproduces the exposure h[s, j].
    #[test]
    fn assign_exact_reconstruction_zero_unassigned_and_reproduces_exposure() {
        let (m, n, k) = (6usize, 4usize, 2usize);
        let mut rng = MsRng::from_stream(12, StreamId { replicate: 5, rank: 2, fold: 1 });
        let mut w: Vec<f64> = (0..m * k).map(|_| uniform(&mut rng)).collect();
        for s in 0..k {
            let col: f64 = (0..m).map(|i| w[i * k + s]).sum();
            for i in 0..m {
                w[i * k + s] /= col;
            }
        }
        let h: Vec<f64> = (0..k * n).map(|_| 10.0 + 90.0 * uniform(&mut rng)).collect();
        let v = crate::nmf::matmul(&w, &h, m, n, k);
        let fit = assign_per_mutation(&v, &w, &h, m, n, k).unwrap();
        assert!(
            fit.unassigned.iter().all(|&u| u == 0.0),
            "exact reconstruction leaves nothing unassigned"
        );
        for j in 0..n {
            for s in 0..k {
                let mut sum = 0.0;
                for i in 0..m {
                    sum += fit.assignments[(i * n + j) * k + s];
                }
                assert_close(sum, h[s * n + j], 1e-9, "allocation == exposure");
            }
        }
    }

    /// The unassigned pseudo-signature is exactly the positive residual
    /// (v - wh)+, channel by channel (STL semantics).
    #[test]
    fn unassigned_is_the_positive_residual() {
        // v = [5, 3], wh = [7, 1] -> u = [0, 2].
        let v = [5.0, 3.0];
        let w = [0.7, 0.1];
        let h = [10.0];
        let fit = assign_per_mutation(&v, &w, &h, 2, 1, 1).unwrap();
        assert_eq!(fit.unassigned[0], 0.0, "over-reconstruction clamps at 0");
        assert_close(fit.unassigned[1], 2.0, 1e-12, "under-reconstruction residual");
    }

    /// Degenerate all-zero factors stay NaN/Inf-free (epsilon-guard
    /// path): every output is finite, zero-recon cells route to
    /// unassigned.
    #[test]
    fn assign_zero_factors_stay_finite() {
        let v = [3.0, 1.0, 0.0, 2.0];
        let w = [0.0, 0.0];
        let h = [0.0, 0.0];
        let fit = assign_per_mutation(&v, &w, &h, 2, 2, 1).unwrap();
        assert!(fit.assignments.iter().all(|x| x.is_finite() && *x == 0.0));
        assert!(fit.unassigned.iter().all(|x| x.is_finite()));
        assert_eq!(fit.unassigned, vec![3.0, 1.0, 0.0, 2.0]);
    }

    /// Determinism: same inputs, bit-identical outputs.
    #[test]
    fn assign_is_bit_identical_across_runs() {
        let (m, n, k) = (9usize, 6usize, 3usize);
        let mut rng = MsRng::from_stream(13, StreamId { replicate: 6, rank: 2, fold: 1 });
        let counts: Vec<f64> =
            (0..m * n).map(|_| (uniform(&mut rng) * 30.0).floor()).collect();
        let w: Vec<f64> = (0..m * k).map(|_| uniform(&mut rng)).collect();
        let h: Vec<f64> = (0..k * n).map(|_| uniform(&mut rng)).collect();
        let a = assign_per_mutation(&counts, &w, &h, m, n, k).unwrap();
        let b = assign_per_mutation(&counts, &w, &h, m, n, k).unwrap();
        assert_eq!(a, b);
    }

    #[test]
    fn assign_validation_errors_are_structured() {
        let v = [1.0, 2.0, 3.0, 4.0];
        let w2 = [0.5, 0.5, 0.5, 0.5];
        let h2 = [1.0, 1.0, 1.0, 1.0];
        // Zero dimensions.
        assert_eq!(
            assign_per_mutation(&v, &w2, &h2, 0, 2, 2).unwrap_err().topic(),
            "argument"
        );
        // Storage mismatches.
        assert_eq!(
            assign_per_mutation(&v[..3], &w2, &h2, 2, 2, 2).unwrap_err().topic(),
            "argument"
        );
        assert_eq!(
            assign_per_mutation(&v, &w2[..3], &h2, 2, 2, 2).unwrap_err().topic(),
            "argument"
        );
        assert_eq!(
            assign_per_mutation(&v, &w2, &h2[..3], 2, 2, 2).unwrap_err().topic(),
            "argument"
        );
        // Negative / non-finite entries with 1-based positions.
        let err = assign_per_mutation(&[1.0, -2.0, 3.0, 4.0], &w2, &h2, 2, 2, 2).unwrap_err();
        assert_eq!((err.topic(), err.i), ("argument", Some(1)));
        let err =
            assign_per_mutation(&[1.0, f64::NAN, 3.0, 4.0], &w2, &h2, 2, 2, 2).unwrap_err();
        assert_eq!(err.topic(), "na");
        let err =
            assign_per_mutation(&v, &[f64::INFINITY, 0.5, 0.5, 0.5], &h2, 2, 2, 2).unwrap_err();
        assert_eq!(err.topic(), "na");
        let err = assign_per_mutation(&v, &[-0.1, 0.5, 0.5, 0.5], &h2, 2, 2, 2).unwrap_err();
        assert_eq!(err.topic(), "argument");
        // Valid input passes (shape sanity for the asserts above).
        assert!(assign_per_mutation(&v, &w2, &h2, 2, 2, 2).is_ok());
    }

    // ==================================================================
    // TSB: exact p-values
    // ==================================================================

    /// ln Binomial pmf at p0 = 1/2 (test-local brute-force reference).
    fn binom_pmf_ln(k: u64, n: u64) -> f64 {
        (ln_gamma((n + 1) as f64) - ln_gamma(k as f64 + 1.0)
            - ln_gamma((n - k) as f64 + 1.0))
            - (n as f64) * std::f64::consts::LN_2
    }

    /// Brute-force R-binom.test-style reference: sum the pmf over
    /// {k : pmf(k) <= pmf(obs)}. Ties at p0 = 1/2 (the mirrored point
    /// k = n - uts) are detected with a 1e-9 log-space slack because the
    /// reference evaluates the mirrored pmf with its ln-Gamma terms in a
    /// different (non-bit-identical) order; the slack is orders of
    /// magnitude below any adjacent-pmf gap on the tested grid.
    fn exact_p_bruteforce(uts: u64, ts: u64) -> f64 {
        let n = uts + ts;
        let obs = binom_pmf_ln(uts, n);
        let mut acc = 0.0;
        for k in 0..=n {
            let lp = binom_pmf_ln(k, n);
            if lp <= obs + 1e-9 {
                acc += lp.exp();
            }
        }
        acc.min(1.0)
    }

    /// Exact goldens at p0 = 1/2 (powers of two, hand-derived).
    #[test]
    fn tsb_golden_exact_p_values() {
        // (0, 10): p = 2 * 0.5^10 = 1/512; statistic = rate ratio 0/10.
        let r = tsb_test(0.0, 10.0, TsbTest::Poisson).unwrap();
        assert_close(r.p_value, 1.0 / 512.0, 1e-12, "p(0,10)");
        assert_eq!(r.direction, TsbDirection::TsEnriched);
        assert_eq!(r.statistic, 0.0);
        // (3, 7), n = 10: p = 2 * (1+10+45+120)/1024 = 352/1024;
        // binomial statistic = UTS fraction 3/10.
        let r = tsb_test(3.0, 7.0, TsbTest::Binomial).unwrap();
        assert_close(r.p_value, 352.0 / 1024.0, 1e-12, "p(3,7)");
        assert_eq!(r.direction, TsbDirection::TsEnriched);
        assert_close(r.statistic, 0.3, 1e-15, "uts fraction");
        // (5, 5): observed value is the mode -> p = 1 exactly;
        // poisson statistic = rate ratio 1.
        let r = tsb_test(5.0, 5.0, TsbTest::Poisson).unwrap();
        assert_eq!(r.p_value, 1.0);
        assert_eq!(r.direction, TsbDirection::Symmetric);
        assert_eq!(r.statistic, 1.0);
        // Extreme imbalance underflows continuously to exactly 0.
        let r = tsb_test(0.0, 4000.0, TsbTest::Poisson).unwrap();
        assert_eq!(r.p_value, 0.0);
        assert_eq!(r.direction, TsbDirection::TsEnriched);
        // Degenerate: no data at all -> no evidence, statistic 0.
        let r = tsb_test(0.0, 0.0, TsbTest::Binomial).unwrap();
        assert_eq!(r.p_value, 1.0);
        assert_eq!(r.direction, TsbDirection::Symmetric);
        assert_eq!(r.statistic, 0.0);
        assert_eq!((r.ts, r.uts), (0.0, 0.0));
    }

    /// The closed form matches the brute-force exact sum on a grid of
    /// integer strand pairs (binom.test/poisson.test parity).
    #[test]
    fn tsb_matches_bruteforce_exact_sum_on_grid() {
        for &(uts, ts) in &[
            (0u64, 1u64),
            (1, 1),
            (0, 5),
            (2, 8),
            (4, 6),
            (5, 5),
            (7, 13),
            (10, 30),
            (25, 75),
            (30, 70),
            (48, 52),
            (0, 100),
            (3, 300),
            (137, 263),
        ] {
            let got = tsb_test(uts as f64, ts as f64, TsbTest::Poisson).unwrap().p_value;
            let want = exact_p_bruteforce(uts, ts);
            assert_close(got, want, 1e-10, "exact conditional p");
        }
    }

    /// Large-n integer cases (beyond the incomplete-beta front-factor
    /// domain, n > 1020): the summation engine stays finite and
    /// terminates through the underflow break.
    #[test]
    fn tsb_large_n_integer_extremes() {
        // 500 vs 15000 of 15500: p far below any threshold.
        let r = tsb_test(500.0, 15000.0, TsbTest::Poisson).unwrap();
        assert!(r.p_value < 1e-100, "large-n imbalance p = {}", r.p_value);
        assert_eq!(r.direction, TsbDirection::TsEnriched);
        // Near-balanced large n (40 mutations off dead center of 15500,
        // z ~ 0.6): p in the non-significant mid range, finite.
        let r = tsb_test(7730.0, 7770.0, TsbTest::Binomial).unwrap();
        assert!(
            (0.05..=1.0).contains(&r.p_value),
            "balanced large-n p = {}",
            r.p_value
        );
    }

    /// Symmetric construction (uts == ts) is exactly the mode: p = 1
    /// for every balanced pair (analytic pin).
    #[test]
    fn tsb_symmetric_construction_gives_p_one() {
        for k in 0..=60u64 {
            let r = tsb_test(k as f64, k as f64, TsbTest::Poisson).unwrap();
            assert_eq!(r.p_value, 1.0, "uts = ts = {k}");
            assert_eq!(r.direction, TsbDirection::Symmetric);
        }
    }

    /// Monte Carlo size at alpha = 0.05 under the null (equal strand
    /// rates, fixed seed streams): the rejection rate must sit at the
    /// nominal level of the exact conditional test.
    #[test]
    fn tsb_size_at_nominal_level_under_null_mc() {
        let n_reps = 2000u64;
        let lambda = 60.0;
        let mut poisson_rejects = 0u64;
        let mut binomial_rejects = 0u64;
        for r in 0..n_reps {
            let mut rep = MsRng::from_stream(0x7BEF, StreamId { replicate: r, rank: 1, fold: 3 });
            let uts = knuth_poisson(&mut rep, lambda) as f64;
            let ts = knuth_poisson(&mut rep, lambda) as f64;
            if tsb_test(uts, ts, TsbTest::Poisson).unwrap().p_value < 0.05 {
                poisson_rejects += 1;
            }
            if tsb_test(uts, ts, TsbTest::Binomial).unwrap().p_value < 0.05 {
                binomial_rejects += 1;
            }
        }
        let rate = poisson_rejects as f64 / n_reps as f64;
        assert!(
            (0.03..=0.075).contains(&rate),
            "size at alpha=0.05: {rate} ({poisson_rejects}/{n_reps})"
        );
        assert_eq!(poisson_rejects, binomial_rejects, "modes agree on decisions");
    }

    /// Power under biased constructions: all mass on one strand, then
    /// a moderate imbalance, must dominate the nominal size.
    #[test]
    fn tsb_extreme_bias_is_significant() {
        // All 200 mutations on TS: astronomically significant.
        let r = tsb_test(0.0, 200.0, TsbTest::Binomial).unwrap();
        assert!(r.p_value < 1e-15, "all-TS p = {}", r.p_value);
        assert_eq!(r.direction, TsbDirection::TsEnriched);
        // Moderate imbalance (30 vs 70 of 100): significant at 0.001.
        let r = tsb_test(30.0, 70.0, TsbTest::Poisson).unwrap();
        assert!(r.p_value < 1e-3, "30v70 p = {}", r.p_value);
        assert_eq!(r.direction, TsbDirection::TsEnriched);
    }

    /// Poisson and Binomial modes are the same exact conditional test
    /// at r = 1: identical p-values, masses and directions on an
    /// integer grid (MutationalPatterns: "Is the same as binom in this
    /// scenario"); only the reported statistic differs by definition.
    #[test]
    fn tsb_modes_share_the_exact_p_value() {
        for &(uts, ts) in &[
            (0.0f64, 1.0f64),
            (1.0, 0.0),
            (5.0, 5.0),
            (3.0, 7.0),
            (137.0, 263.0),
            (0.0, 4000.0),
            (1234.0, 1234.0),
        ] {
            let p = tsb_test(uts, ts, TsbTest::Poisson).unwrap();
            let b = tsb_test(uts, ts, TsbTest::Binomial).unwrap();
            assert_eq!(p.p_value, b.p_value, "p at (uts={uts}, ts={ts})");
            assert_eq!(p.direction, b.direction);
            assert_eq!((p.ts, p.uts), (b.ts, b.uts));
            // Statistic definitions: ratio vs fraction.
            let n = uts + ts;
            if n > 0.0 {
                if ts > 0.0 {
                    assert_close(p.statistic, uts / ts, 0.0, "poisson ratio");
                } else {
                    assert_eq!(p.statistic, f64::INFINITY, "ratio with ts = 0");
                }
                assert_close(b.statistic, uts / n, 1e-15, "binomial fraction");
            }
        }
    }

    /// Fractional assigned masses are the canonical continuous
    /// extension of the exact test: perturbing an integer pair by
    /// 1e-9 moves the p-value by O(1e-8) only.
    #[test]
    fn tsb_fractional_masses_extend_the_exact_test_continuously() {
        let base = tsb_test(3.0, 7.0, TsbTest::Poisson).unwrap().p_value;
        let frac = tsb_test(3.0 + 1e-9, 7.0, TsbTest::Poisson).unwrap().p_value;
        assert!((base - frac).abs() < 1e-7, "{base} vs {frac}");
        // Direction/statistic remain finite and consistent.
        let r = tsb_test(2.5, 7.5, TsbTest::Binomial).unwrap();
        assert_eq!(r.direction, TsbDirection::TsEnriched);
        assert_close(r.statistic, 0.25, 1e-15, "fractional uts fraction");
        assert!(r.p_value.is_finite());
        // Monotonicity of the extension: more imbalance, smaller p.
        let less_biased = tsb_test(2.5, 7.5, TsbTest::Poisson).unwrap().p_value;
        let more_biased = tsb_test(1.5, 8.5, TsbTest::Poisson).unwrap().p_value;
        assert!(more_biased < less_biased, "{more_biased} vs {less_biased}");
    }

    // ==================================================================
    // TSB: aggregation faces
    // ==================================================================

    /// Raw-count face: aggregates channels by the strand annotation
    /// (MutationalPatterns-style sample-level test).
    #[test]
    fn tsb_stranded_counts_aggregate_by_mask() {
        // 4 channels: TS, UTS, TS, UTS with counts 10, 5, 30, 15.
        let counts = [10.0, 5.0, 30.0, 15.0];
        let mask = [true, false, true, false];
        let r = tsb_test_stranded(&counts, &mask, TsbTest::Poisson).unwrap();
        assert_close(r.ts, 40.0, 0.0, "ts total");
        assert_close(r.uts, 20.0, 0.0, "uts total");
        assert_eq!(r.direction, TsbDirection::TsEnriched);
        // Same result as calling the pair test directly.
        let direct = tsb_test(20.0, 40.0, TsbTest::Poisson).unwrap();
        assert_eq!(r, direct);
        // One-sided annotation (all channels TS) is a legal extreme.
        let all_ts =
            tsb_test_stranded(&counts, &[true, true, true, true], TsbTest::Poisson).unwrap();
        assert_eq!(all_ts.uts, 0.0);
        assert_eq!(all_ts.direction, TsbDirection::TsEnriched);
    }

    /// Per-signature face: a strand-partitioned construction where
    /// signature 0 lives entirely on TS channels and signature 1 is
    /// strand-symmetric. Only signature 0 may be significant.
    #[test]
    fn tsb_per_signature_only_biased_signature_rejects() {
        // 4 channels (2 TS, 2 UTS) x 1 sample x 2 signatures, exact
        // reconstruction: sig0 lives on the TS channels only (wh = 25
        // there, 5 on UTS), sig1 splits evenly across all channels.
        let w = [0.5, 0.125, 0.0, 0.125, 0.5, 0.125, 0.0, 0.125];
        let h = [40.0, 40.0];
        let counts = [25.0, 5.0, 25.0, 5.0];
        let fit = assign_per_mutation(&counts, &w, &h, 4, 1, 2).unwrap();
        let mask = [true, false, true, false];
        let res =
            tsb_test_per_signature(&fit.assignments, 4, 1, 2, &mask, TsbTest::Poisson).unwrap();
        assert_eq!(res.len(), 2);
        // Signature 0: all 40 assigned mutations on TS.
        assert_close(res[0].ts, 40.0, 1e-9, "sig0 ts mass");
        assert_close(res[0].uts, 0.0, 1e-9, "sig0 uts mass");
        assert_eq!(res[0].direction, TsbDirection::TsEnriched);
        assert!(res[0].p_value < 1e-9, "sig0 p = {}", res[0].p_value);
        // Signature 1: 10 vs 10 -> exactly symmetric.
        assert_close(res[1].ts, 10.0, 1e-9, "sig1 ts mass");
        assert_close(res[1].uts, 10.0, 1e-9, "sig1 uts mass");
        assert_eq!(res[1].p_value, 1.0);
        assert_eq!(res[1].direction, TsbDirection::Symmetric);
    }

    /// Per-signature aggregation agrees with a manual fold of the
    /// assignment tensor (cross-kernel D11 pin: assign_per_mutation ->
    /// tsb_test_per_signature composes).
    #[test]
    fn tsb_per_signature_matches_manual_tensor_fold() {
        let (m, n, k) = (6usize, 3usize, 2usize);
        let mut rng = MsRng::from_stream(14, StreamId { replicate: 7, rank: 2, fold: 1 });
        let counts: Vec<f64> =
            (0..m * n).map(|_| (uniform(&mut rng) * 20.0).floor()).collect();
        let w: Vec<f64> = (0..m * k).map(|_| uniform(&mut rng)).collect();
        let h: Vec<f64> = (0..k * n).map(|_| uniform(&mut rng)).collect();
        let fit = assign_per_mutation(&counts, &w, &h, m, n, k).unwrap();
        let mask = [true, false, true, false, true, false];
        let res =
            tsb_test_per_signature(&fit.assignments, m, n, k, &mask, TsbTest::Binomial).unwrap();
        assert_eq!(res.len(), k);
        for s in 0..k {
            let mut ts = 0.0;
            let mut uts = 0.0;
            for i in 0..m {
                for j in 0..n {
                    let c = fit.assignments[(i * n + j) * k + s];
                    if mask[i] {
                        ts += c;
                    } else {
                        uts += c;
                    }
                }
            }
            assert_close(res[s].ts, ts, 1e-12, "tensor fold ts");
            assert_close(res[s].uts, uts, 1e-12, "tensor fold uts");
        }
    }

    // ==================================================================
    // TSB: validation and determinism
    // ==================================================================

    #[test]
    fn tsb_validation_errors_are_structured() {
        // Negative strand mass.
        let err = tsb_test(-1.0, 5.0, TsbTest::Poisson).unwrap_err();
        assert_eq!((err.topic(), err.i), ("argument", Some(1)));
        let err = tsb_test(5.0, -2.0, TsbTest::Binomial).unwrap_err();
        assert_eq!((err.topic(), err.i), ("argument", Some(2)));
        // Non-finite.
        assert_eq!(tsb_test(f64::NAN, 5.0, TsbTest::Poisson).unwrap_err().topic(), "na");
        assert_eq!(
            tsb_test(5.0, f64::INFINITY, TsbTest::Binomial).unwrap_err().topic(),
            "na"
        );
        // Stranded face: empty, length mismatch, negative, non-integral.
        assert_eq!(
            tsb_test_stranded(&[], &[], TsbTest::Poisson).unwrap_err().topic(),
            "argument"
        );
        assert_eq!(
            tsb_test_stranded(&[1.0, 2.0], &[true], TsbTest::Poisson)
                .unwrap_err()
                .topic(),
            "argument"
        );
        let err = tsb_test_stranded(&[1.0, -2.0], &[true, false], TsbTest::Poisson).unwrap_err();
        assert_eq!((err.topic(), err.i), ("argument", Some(2)));
        assert_eq!(
            tsb_test_stranded(&[1.5, 2.0], &[true, false], TsbTest::Poisson)
                .unwrap_err()
                .topic(),
            "argument",
            "raw counts must be integral"
        );
        // Per-signature face: storage and mask mismatch, empty dims.
        assert_eq!(
            tsb_test_per_signature(&[1.0], 2, 1, 1, &[true, false], TsbTest::Poisson)
                .unwrap_err()
                .topic(),
            "argument"
        );
        assert_eq!(
            tsb_test_per_signature(&[1.0, 1.0], 2, 1, 1, &[true], TsbTest::Poisson)
                .unwrap_err()
                .topic(),
            "argument"
        );
        assert_eq!(
            tsb_test_per_signature(&[1.0, 1.0], 0, 1, 1, &[], TsbTest::Poisson)
                .unwrap_err()
                .topic(),
            "argument"
        );
        let err = tsb_test_per_signature(
            &[f64::NAN, 1.0],
            2,
            1,
            1,
            &[true, false],
            TsbTest::Poisson,
        )
        .unwrap_err();
        assert_eq!(err.topic(), "na");
    }

    #[test]
    fn tsb_is_bit_identical_across_runs() {
        let mut rng = MsRng::from_stream(15, StreamId { replicate: 8, rank: 2, fold: 1 });
        let uts = uniform(&mut rng) * 100.0;
        let ts = uniform(&mut rng) * 100.0;
        let a = tsb_test(uts, ts, TsbTest::Poisson).unwrap();
        let b = tsb_test(uts, ts, TsbTest::Poisson).unwrap();
        assert_eq!(a, b);
        let counts = [1.0, 2.0, 3.0, 4.0];
        let mask = [true, false, true, false];
        let c = tsb_test_stranded(&counts, &mask, TsbTest::Binomial).unwrap();
        let d = tsb_test_stranded(&counts, &mask, TsbTest::Binomial).unwrap();
        assert_eq!(c, d);
    }

    /// Knuth Poisson draw (product of uniforms; adequate for the
    /// small rates used here) — same machinery as likelihood.rs tests.
    fn knuth_poisson(rng: &mut MsRng, mu: f64) -> u64 {
        let limit = (-mu).exp();
        let mut k = 0u64;
        let mut p = 1.0f64;
        loop {
            k += 1;
            p *= uniform(rng);
            if p <= limit {
                return k - 1;
            }
        }
    }
}
