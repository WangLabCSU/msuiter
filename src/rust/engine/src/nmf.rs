//! KL (β=1) and EU (β=2) non-negative matrix factorization via multiplicative
//! updates (MM-MU) — the SigProfiler/MutationalPatterns gold-standard
//! extraction kernel (U-M1s-02; `docs/ARCHITECTURE.md` §2 `engine/nmf.rs`,
//! decision D6).
//!
//! # Model and notation
//!
//! `V ∈ R_+^{m×n}` (m channels × n samples) is approximated as `V ≈ W H`
//! with `W ∈ R_+^{m×k}` the signature matrix and `H ∈ R_+^{k×n}` the
//! exposure matrix. All matrices are plain `Vec<f64>` in **row-major**
//! order: `V[i*n + j]`, `W[i*k + s]`, `H[s*n + j]`.
//!
//! # Update equations (audit semantics, `docs/research/01` §10 a/f)
//!
//! Both kernels are block-coordinate **majorization–minimization** (MM):
//! each step replaces one factor by an elementwise multiplicative update
//! that never increases the objective (Lee & Seung 2001 for β ∈ {1, 2};
//! the unified β-divergence form is Févotte & Idier 2011, Marmin et al.
//! 2023). The implemented equations are verbatim the audited ones:
//!
//! KL (β = 1, generalized KL divergence `D(V‖WH) = Σ [V·ln(V/(WH)) − V + WH]`):
//!
//! ```text
//! H ← H ⊙ (Wᵀ (V ⊘ WH)) ⊘ (Wᵀ 1_m)      // denominator = W column sums
//! W ← W ⊙ ((V ⊘ WH) Hᵀ) ⊘ (1_m Hᵀ)      // denominator = H row sums
//! ```
//!
//! EU (β = 2, squared Frobenius / SSE `‖V − WH‖²_F`):
//!
//! ```text
//! H ← H ⊙ (Wᵀ V) ⊘ (Wᵀ W H)
//! W ← W ⊙ (V Hᵀ) ⊘ (W H Hᵀ)
//! ```
//!
//! Each iteration is one H step followed by one W step (the order listed in
//! `docs/research/01` §10; fixed for the whole run). Cost per iteration is a
//! small constant number of dense `m·n·k` passes; nothing else is
//! materialized.
//!
//! For β = 1 the multiplicative update is exactly the soft-EM update of a
//! multinomial (Poisson) likelihood (Cemgil 2009): hidden per-channel
//! attribution counts `c[i,j,s] = v[i,j]·w[i,s]·h[s,j]/(WH)[i,j]` are
//! aggregated in the E step, and the M step renormalizes. **This is why β=1
//! is the default engine (D6): fitting KL-NMF is maximum-likelihood
//! estimation of a multinomial generative model for mutation counts**, not
//! merely "a divergence that happens to work". Precision note (audited): the
//! updates as implemented are exactly the Poisson MLE; the multinomial
//! reading is the Poisson result conditioned on column-normalized W (the
//! multinomial likelihood factors as Poisson × independent multinomials over
//! the column totals), and that normalization lives in the pipeline layer
//! after the fit — the kernel deliberately does not renormalize.
//!
//! # ε policy (numerical hygiene only — NOT a pseudocount)
//!
//! [`KL_EPS`] = 1e-12 enters exactly two places, per the ARCH §2 contract
//! (denominators `max(·, ε)`, logs as `log(ε + ·)`):
//!
//! 1. **Division guards**: every ratio denominator (`WH` in the responsibility
//!    ratios `V ⊘ WH`, and the MU denominators) is floored at `max(·, ε)`.
//! 2. **Objective logs**: `V·ln(V/(WH))` is evaluated as
//!    `V·(ln(ε+V) − ln(ε+WH))`, which is finite for every `V ≥ 0`, `WH ≥ 0`
//!    (at `V = 0` the product is exactly 0 — the correct limit of the KL
//!    term — so structural zero channels never produce NaN/Inf).
//!
//! Statistical meaning (D6 / ARCH §7.4 zero-pseudocount policy): ε never
//! enters the model itself — it does not add mass to V, W or H and does not
//! shift the MLE; it only keeps divisions and logs defined where a factor
//! underflows (dead components are a property of the fit, and exact zeros in
//! V are handled by the limit above). The catalog layer's separate
//! zero-pseudocount policy is untouched. Magnitude: mutational catalogs
//! carry integer counts ≥ 1, so an absolute floor of 1e-12 sits ≥ 12 orders
//! of magnitude below any meaningful model mean while staying far above f64
//! underflow; entries below ε would see an objective perturbation of order
//! O(ε/wh) per log term — negligible precisely when wh ≫ ε, which is the
//! only regime real counts occupy.
//!
//! # Initialization (this unit: fixed deterministic only)
//!
//! [`fit_kl`] / [`fit_eu`] use a **seeded uniform-random init** drawn from
//! the in-house [`crate::rng::MsRng`] (master seed = `seed`, stream
//! `StreamId::ZERO`): open-interval uniforms in (0, 1] (an exact-zero init
//! entry would be absorbing under MU), then both factors are scaled by
//! `(mean(V)/k).sqrt()` so that `E[(WH)[i,j]]` starts on the same order of
//! magnitude as the data (uniforms have mean 1/2, so `E[(WH)] = mean(V)/4`
//! exactly — a deliberate half-scale headroom, not a match).
//!
//! Rationale for random over a constant fill: a constant matrix (e.g. all
//! `1/k`) initializes all k W columns identically, and MU updates are
//! equivariant, so the columns stay clones of each other forever — symmetry
//! is never broken and the model cannot separate signatures. A seeded
//! uniform draw breaks symmetry deterministically. NNDSVDa is deliberately
//! out of scope (U-M1s-03); [`fit_kl_with_init`] / [`fit_eu_with_init`]
//! accept caller-provided factors so that init strategies compose on top of
//! this kernel without touching it.
//!
//! # Trace semantics
//!
//! `NmfFit::objective[0]` is the objective **at the initializer**; entry
//! `t ≥ 1` is the objective after `t` full (H step + W step) iterations.
//! The trace is monotone non-increasing in exact arithmetic (MM property)
//! and monotone up to floating-point roundoff here; tests assert
//! non-increase within a 1e-9 relative slack at the convergence plateau.
//! The iteration count is fixed by the caller (`max_iter`) — no early
//! stopping, so a run is a pure function of `(V, k, max_iter, init)`.
//!
//! # Determinism
//!
//! Fixed loop order everywhere, sequential reductions, no parallelism, no
//! hashing: equal inputs produce bit-identical output regardless of thread
//! count (ARCH §2.6 thread-invariance contract).
//!
//! # Contract notes
//!
//! Pure engine kernel: no FFI face, no `unsafe`, no dependencies; every
//! entry point returns `Result<_, MsError>` (FFI contract 5). HALS / ARD /
//! volume regularization / consensus / NNDSVD are later units and are
//! deliberately absent.

use crate::error::MsError;
use crate::rng::{MsRng, StreamId};

/// Absolute ε floor for division denominators and log arguments (see the
/// module docs for the exact placement and its statistical reading: a
/// floating-point guard only, never a pseudocount).
pub const KL_EPS: f64 = 1e-12;

/// Outcome of a fixed-iteration NMF fit.
#[derive(Debug, Clone, PartialEq)]
pub struct NmfFit {
    /// Signature matrix `W`, row-major `m×k`.
    pub w: Vec<f64>,
    /// Exposure matrix `H`, row-major `k×n`.
    pub h: Vec<f64>,
    /// Objective trace: `objective[0]` at the initializer, `objective[t]`
    /// after `t` iterations (KL divergence for [`fit_kl`]/[`fit_kl_with_init`],
    /// squared error for [`fit_eu`]/[`fit_eu_with_init`]). Length
    /// `max_iter + 1`. Monotone non-increasing up to roundoff (MM property).
    pub objective: Vec<f64>,
    /// Iterations actually run (equals the requested `max_iter`).
    pub iterations: usize,
}

/// KL-NMF (β = 1, default engine — D6). As written, these multiplicative
/// updates are the Poisson MLE; the D6 "multinomial MLE" reading holds once
/// W columns are normalized onto the simplex, which happens in the pipeline
/// layer after the fit, not inside this kernel.
pub fn fit_kl(
    v: &[f64],
    m: usize,
    n: usize,
    k: usize,
    max_iter: usize,
    seed: u64,
) -> Result<NmfFit, MsError> {
    fit_kl_on_stream(v, m, n, k, max_iter, seed, StreamId::ZERO)
}

/// KL-NMF with the seeded initializer drawn from an **explicit canonical
/// stream** (U-M1s-05): identical to [`fit_kl`] except that the initializer
/// comes from `MsRng::from_stream(seed, stream)` instead of
/// `StreamId::ZERO`. This is the face parallel replicate drivers call:
/// replicate `r` addresses `StreamId { replicate: r, rank: 0, fold: 0 }`, so
/// every replicate of one master seed draws from a frozen, disjoint stream
/// of the canonical layout v1 and no unit ever shares generator state
/// (ARCH §2.6 thread-invariance contract). The kernel loop is untouched —
/// still single-threaded, fixed reduction order.
pub fn fit_kl_on_stream(
    v: &[f64],
    m: usize,
    n: usize,
    k: usize,
    max_iter: usize,
    seed: u64,
    stream: StreamId,
) -> Result<NmfFit, MsError> {
    let (w0, h0) = seeded_init(v, m, n, k, seed, stream)?;
    fit_kl_with_init(v, m, n, k, &w0, &h0, max_iter)
}

/// EU-NMF (β = 2, Frobenius) with the seeded deterministic initialization
/// documented in this module.
pub fn fit_eu(
    v: &[f64],
    m: usize,
    n: usize,
    k: usize,
    max_iter: usize,
    seed: u64,
) -> Result<NmfFit, MsError> {
    let (w0, h0) = seeded_init(v, m, n, k, seed, StreamId::ZERO)?;
    fit_eu_with_init(v, m, n, k, &w0, &h0, max_iter)
}

/// KL-NMF from a caller-provided initializer (`w0`: row-major `m×k`,
/// `h0`: row-major `k×n`). Entries must be finite and non-negative; exact
/// zeros are permitted but are **absorbing** under MU (a zero entry can
/// never become positive again) — init strategies should keep the factors
/// strictly positive.
pub fn fit_kl_with_init(
    v: &[f64],
    m: usize,
    n: usize,
    k: usize,
    w0: &[f64],
    h0: &[f64],
    max_iter: usize,
) -> Result<NmfFit, MsError> {
    validate(v, m, n, k, w0, h0)?;
    let mut w = w0.to_vec();
    let mut h = h0.to_vec();
    let mut objective = Vec::with_capacity(max_iter + 1);
    objective.push(kl_objective(v, &w, &h, m, n, k));
    for _ in 0..max_iter {
        kl_h_step(v, &w, &mut h, m, n, k);
        kl_w_step(v, &mut w, &h, m, n, k);
        objective.push(kl_objective(v, &w, &h, m, n, k));
    }
    Ok(NmfFit { w, h, objective, iterations: max_iter })
}

/// EU-NMF from a caller-provided initializer (layout and zero caveat as in
/// [`fit_kl_with_init`]).
pub fn fit_eu_with_init(
    v: &[f64],
    m: usize,
    n: usize,
    k: usize,
    w0: &[f64],
    h0: &[f64],
    max_iter: usize,
) -> Result<NmfFit, MsError> {
    validate(v, m, n, k, w0, h0)?;
    let mut w = w0.to_vec();
    let mut h = h0.to_vec();
    let mut objective = Vec::with_capacity(max_iter + 1);
    objective.push(sse_objective(v, &w, &h, m, n, k));
    for _ in 0..max_iter {
        eu_h_step(v, &w, &mut h, m, n, k);
        eu_w_step(v, &mut w, &h, m, n, k);
        objective.push(sse_objective(v, &w, &h, m, n, k));
    }
    Ok(NmfFit { w, h, objective, iterations: max_iter })
}

// ======================================================================
// Kernels
// ======================================================================

/// One KL H step: `H ← H ⊙ (Wᵀ (V ⊘ max(WH, ε))) ⊘ max(Wᵀ 1_m, ε)`.
/// Crate-visible so the SUITOR CV driver (U-M2-02) reuses the audited MU
/// kernel verbatim instead of forking it.
pub(crate) fn kl_h_step(v: &[f64], w: &[f64], h: &mut [f64], m: usize, n: usize, k: usize) {
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
    // den[s][j] = Σ_i W[i][s]  (W column sums — independent of j)
    for s in 0..k {
        let mut col = 0.0f64;
        for i in 0..m {
            col += w[i * k + s];
        }
        let den = col.max(KL_EPS);
        for j in 0..n {
            h[s * n + j] *= num[s * n + j] / den;
        }
    }
}

/// One KL W step: `W ← W ⊙ ((V ⊘ max(WH, ε)) Hᵀ) ⊘ max(1_m Hᵀ, ε)`.
/// Crate-visible for the SUITOR CV driver (see [`kl_h_step`]).
pub(crate) fn kl_w_step(v: &[f64], w: &mut [f64], h: &[f64], m: usize, n: usize, k: usize) {
    let wh = matmul(w, h, m, n, k);
    for i in 0..m {
        for s in 0..k {
            let mut num = 0.0f64;
            for j in 0..n {
                let r = v[i * n + j] / wh[i * n + j].max(KL_EPS);
                num += r * h[s * n + j];
            }
            // den[s] = Σ_j H[s][j] (H row sums — independent of i)
            let mut den = 0.0f64;
            for j in 0..n {
                den += h[s * n + j];
            }
            w[i * k + s] *= num / den.max(KL_EPS);
        }
    }
}

/// One EU H step: `H ← H ⊙ (WᵀV) ⊘ max(WᵀW H, ε)`.
fn eu_h_step(v: &[f64], w: &[f64], h: &mut [f64], m: usize, n: usize, k: usize) {
    // num = WᵀV (k×n), gww = WᵀW (k×k), den = gww·H (k×n).
    let mut num = vec![0.0f64; k * n];
    for i in 0..m {
        let wrow = &w[i * k..i * k + k];
        for j in 0..n {
            let vv = v[i * n + j];
            if vv != 0.0 {
                for (s, &ws) in wrow.iter().enumerate() {
                    num[s * n + j] += ws * vv;
                }
            }
        }
    }
    let mut gww = vec![0.0f64; k * k];
    for i in 0..m {
        for s in 0..k {
            let wis = w[i * k + s];
            if wis == 0.0 {
                continue;
            }
            for t in s..k {
                let wit = w[i * k + t];
                gww[s * k + t] += wis * wit;
            }
        }
    }
    for s in 0..k {
        for t in 0..s {
            gww[s * k + t] = gww[t * k + s];
        }
    }
    // The audited equation's right-hand side uses the PRE-step H; snapshot so
    // the denominator never sees rows already rewritten this step (audited
    // P1: in-place accumulation is a "half new, half old" hybrid that breaks
    // the MM guarantee for k >= 2).
    let h_pre = h.to_vec();
    for s in 0..k {
        for j in 0..n {
            let mut den = 0.0f64;
            for t in 0..k {
                den += gww[s * k + t] * h_pre[t * n + j];
            }
            h[s * n + j] *= num[s * n + j] / den.max(KL_EPS);
        }
    }
}

/// One EU W step: `W ← W ⊙ (V Hᵀ) ⊘ max(W H Hᵀ, ε)`.
fn eu_w_step(v: &[f64], w: &mut [f64], h: &[f64], m: usize, n: usize, k: usize) {
    // ghh = H Hᵀ (k×k), then den[i][s] = Σ_t W[i][t]·ghh[t][s];
    // num[i][s] = Σ_j V[i][j]·H[s][j].
    let mut ghh = vec![0.0f64; k * k];
    for j in 0..n {
        for s in 0..k {
            let hsj = h[s * n + j];
            if hsj == 0.0 {
                continue;
            }
            for t in s..k {
                ghh[s * k + t] += hsj * h[t * n + j];
            }
        }
    }
    for s in 0..k {
        for t in 0..s {
            ghh[s * k + t] = ghh[t * k + s];
        }
    }
    // Snapshot for the same pre-step semantics as `eu_h_step` (see note
    // there): the denominator must read the W that the numerator equation
    // was written against, not partially rewritten entries.
    let w_pre = w.to_vec();
    for i in 0..m {
        for s in 0..k {
            let mut num = 0.0f64;
            for j in 0..n {
                num += v[i * n + j] * h[s * n + j];
            }
            let mut den = 0.0f64;
            for t in 0..k {
                den += w_pre[i * k + t] * ghh[t * k + s];
            }
            w[i * k + s] *= num / den.max(KL_EPS);
        }
    }
}

/// Row-major `W (m×k) · H (k×n)`. Crate-visible for the SUITOR CV driver
/// (see [`kl_h_step`]).
pub(crate) fn matmul(w: &[f64], h: &[f64], m: usize, n: usize, k: usize) -> Vec<f64> {
    let mut out = vec![0.0f64; m * n];
    for i in 0..m {
        let wrow = &w[i * k..i * k + k];
        for (s, &ws) in wrow.iter().enumerate() {
            if ws == 0.0 {
                continue;
            }
            let hrow = &h[s * n..s * n + n];
            for (j, &hvj) in hrow.iter().enumerate() {
                out[i * n + j] += ws * hvj;
            }
        }
    }
    out
}

/// Generalized KL divergence `D(V‖WH) = Σ [V·ln(V/(WH)) − V + WH]`, with
/// the `log(ε + ·)` evaluation path (module docs, ε policy): finite for all
/// non-negative inputs, and exactly `WH[i,j]` at `V[i,j] = 0`.
fn kl_objective(v: &[f64], w: &[f64], h: &[f64], m: usize, n: usize, k: usize) -> f64 {
    let wh = matmul(w, h, m, n, k);
    let mut acc = 0.0f64;
    for (&vv, &mm) in v.iter().zip(wh.iter()) {
        acc += vv * ((KL_EPS + vv).ln() - (KL_EPS + mm).ln()) - vv + mm;
    }
    acc
}

/// Squared Frobenius objective `‖V − WH‖²_F`.
fn sse_objective(v: &[f64], w: &[f64], h: &[f64], m: usize, n: usize, k: usize) -> f64 {
    let wh = matmul(w, h, m, n, k);
    let mut acc = 0.0f64;
    for (&vv, &mm) in v.iter().zip(wh.iter()) {
        let d = vv - mm;
        acc += d * d;
    }
    acc
}

/// Seeded deterministic initializer (module docs "Initialization"):
/// open-interval uniforms in (0, 1] from `MsRng` on the given canonical
/// stream (W row-major first, then H row-major), both factors scaled by
/// `(mean(V)/k).sqrt()` (scale 1.0 for all-zero input). [`fit_kl`] passes
/// `StreamId::ZERO`; [`fit_kl_on_stream`] forwards the caller's stream.
fn seeded_init(
    v: &[f64],
    m: usize,
    n: usize,
    k: usize,
    seed: u64,
    stream: StreamId,
) -> Result<(Vec<f64>, Vec<f64>), MsError> {
    validate_shape(v, m, n, k)?;
    let mut rng = MsRng::from_stream(seed, stream);
    let scale = {
        let mut mean = 0.0f64;
        for &x in v {
            mean += x;
        }
        mean /= (m * n) as f64;
        if mean > 0.0 {
            (mean / k as f64).sqrt()
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

/// Uniform draw on the open-at-zero, closed-at-one interval (0, 1]: the
/// 53-bit uniform in [0, 1) shifted up by one ulp of 1.0 — strictly
/// positive, so the MU zero-absorbing property is never triggered at init.
fn open_unit(rng: &mut MsRng) -> f64 {
    ((rng.next_u64() >> 11) as f64 + 1.0) * (1.0 / (1u64 << 53) as f64)
}

fn validate_shape(v: &[f64], m: usize, n: usize, k: usize) -> Result<(), MsError> {
    if m == 0 || n == 0 || k == 0 {
        return Err(
            MsError::new("argument", "matrix dimensions must be positive")
                .with_i(m as i64)
                .with_j(n as i64),
        );
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

fn validate(
    v: &[f64],
    m: usize,
    n: usize,
    k: usize,
    w0: &[f64],
    h0: &[f64],
) -> Result<(), MsError> {
    validate_shape(v, m, n, k)?;
    if w0.len() != m * k {
        return Err(
            MsError::new("argument", "w0 storage must be m*k elements").with_i(w0.len() as i64)
        );
    }
    if h0.len() != k * n {
        return Err(
            MsError::new("argument", "h0 storage must be k*n elements").with_i(h0.len() as i64)
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
    Ok(())
}

// ======================================================================
// Tests: hand-derived goldens (KL 2 iterations, EU 1 iteration on a 2×2,
// k=1 example), MM monotonicity on seeded random count grids (KL + EU),
// separable synthetic recovery (96×3 · 3×20), ε behavior on structural
// zeros, bit determinism, flat-signature stability smoke, validation, and
// the zero-absorbing property. Fixed seeds only (MsRng, StreamId layout).
// ======================================================================

#[cfg(test)]
mod tests {
    use super::*;

    /// Uniform f64 in [0, 1) from the in-house generator (test data only).
    fn uniform(rng: &mut MsRng) -> f64 {
        ((rng.next_u64() >> 11) as f64) * (1.0 / (1u64 << 53) as f64)
    }

    /// Random integer-valued counts in {0, …, 39} (some structural zeros).
    fn random_counts(rng: &mut MsRng, m: usize, n: usize) -> Vec<f64> {
        (0..m * n).map(|_| (uniform(rng) * 40.0).floor()).collect()
    }

    // ------------------------------------------------------------------
    // Golden (hand-derived, k = 2): an exact-value case that separates the
    // audited pre-step (Jacobi) semantics from an in-place-aliased variant.
    // V = [[3,0],[0,3],[0,0]], unit init. The H step gives
    // num = WᵀV = [[3,3],[3,3]], den = (WᵀW)·H0 = [[6,6],[6,6]], so
    // H1 = [[1/2,1/2],[1/2,1/2]] (the aliased variant provably differs: its
    // row-1 denominator reads the just-updated row 0, 3·(1/2)+3 = 9/2 ≠ 6,
    // giving H1[1][j] = 2/3). The W step gives W1 = [[3/2,3/2],[3/2,3/2],[0,0]]
    // and SSE = 9. Unit init keeps both components identical (the documented
    // symmetry property of MU), so iteration 2 is an exact fixed point:
    // H2 = H1, W2 = W1, SSE2 = 9.
    // ------------------------------------------------------------------
    #[test]
    fn golden_eu_k2_pre_step_semantics() {
        let v = [3.0, 0.0, 0.0, 3.0, 0.0, 0.0];
        let w0 = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0];
        let h0 = [1.0, 1.0, 1.0, 1.0];
        let expect_h = [0.5, 0.5, 0.5, 0.5];
        let expect_w = [1.5, 1.5, 1.5, 1.5, 0.0, 0.0];

        let one = fit_eu_with_init(&v, 3, 2, 2, &w0, &h0, 1).unwrap();
        for (got, want) in one.h.iter().zip(expect_h) {
            assert!((got - want).abs() < 1e-12, "h1 = {:?}", one.h);
        }
        for (got, want) in one.w.iter().zip(expect_w) {
            assert!((got - want).abs() < 1e-12, "w1 = {:?}", one.w);
        }
        assert!((one.objective[1] - 9.0).abs() < 1e-9, "sse1 = {}", one.objective[1]);

        let two = fit_eu_with_init(&v, 3, 2, 2, &w0, &h0, 2).unwrap();
        assert_eq!(two.h, one.h, "iteration 2 is a fixed point");
        assert_eq!(two.w, one.w);
        assert!((two.objective[2] - 9.0).abs() < 1e-9);
    }

    fn cosine(a: &[f64], b: &[f64]) -> f64 {
        let dot: f64 = a.iter().zip(b.iter()).map(|(&x, &y)| x * y).sum();
        let na: f64 = a.iter().map(|x| x * x).sum::<f64>().sqrt();
        let nb: f64 = b.iter().map(|x| x * x).sum::<f64>().sqrt();
        dot / (na * nb)
    }

    /// Assert the MM monotonicity contract: non-increasing within a 1e-9
    /// relative slack (floating point cannot promise strict monotonicity at
    /// the convergence plateau; 1e-9 is ≫ accumulated roundoff and ≪ any
    /// real MM step).
    fn assert_monotone(trace: &[f64]) {
        assert!(trace.len() >= 2, "trace too short");
        for t in 1..trace.len() {
            let slack = 1e-9 * (1.0 + trace[t - 1].abs());
            assert!(
                trace[t] <= trace[t - 1] + slack,
                "objective increased at t={t}: {} -> {}",
                trace[t - 1],
                trace[t]
            );
        }
    }

    fn assert_all_finite(xs: &[f64]) {
        for (idx, &x) in xs.iter().enumerate() {
            assert!(x.is_finite(), "non-finite at {idx}: {x}");
        }
    }

    /// Greedy max-cosine one-to-one matching between fitted and true W
    /// columns; returns matched cosines in greedy order.
    fn greedy_match(fitted_cols: &[Vec<f64>], true_cols: &[Vec<f64>]) -> Vec<f64> {
        let mut pairs: Vec<(usize, usize, f64)> = Vec::new();
        for (i, fw) in fitted_cols.iter().enumerate() {
            for (t, tw) in true_cols.iter().enumerate() {
                pairs.push((i, t, cosine(fw, tw)));
            }
        }
        // Stable sort on descending cosine; insertion order fixes ties, so
        // the matching is deterministic.
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

    fn column(mat: &[f64], rows: usize, cols: usize, c: usize) -> Vec<f64> {
        (0..rows).map(|r| mat[r * cols + c]).collect()
    }

    // ------------------------------------------------------------------
    // Golden vectors (hand-derived, 2×2 counts, k = 1)
    //
    // V = [[2, 0], [0, 4]], W0 = [[1], [2]], H0 = [[0.5, 0.5]].
    // With k = 1 the KL H step is the closed-form EM optimum
    // (h_j ← colsum_j / Σ_i w_i) and the W step is (w_i ← rowsum_i / Σ_j h_j),
    // so every number below is exact rational arithmetic plus ln.
    // ------------------------------------------------------------------

    #[test]
    fn golden_kl_2x2_k1_two_iterations() {
        let v = [2.0, 0.0, 0.0, 4.0];
        let w0 = [1.0, 2.0];
        let h0 = [0.5, 0.5];
        let fit = fit_kl_with_init(&v, 2, 2, 1, &w0, &h0, 2).unwrap();

        // objective[0] = 2·ln4 − 3/2 + 1/2 + 1 + 4·ln4 − 3 = 6·ln4 − 3.
        assert!((fit.objective[0] - (6.0 * 4.0f64.ln() - 3.0)).abs() < 1e-9);
        // After iteration 1: h = [2/3, 4/3], w = [1, 2] (rowsum/Σh = [2,4]/2).
        // WH = [2/3, 4/3, 4/3, 8/3], so
        // objective[1] = 2·ln3 + 4·ln(3/2)  (zero channels contribute WH).
        assert!((fit.objective[1] - (2.0 * 3.0f64.ln() + 4.0 * (1.5f64).ln())).abs() < 1e-9);
        assert!((fit.w[0] - 1.0).abs() < 1e-12);
        assert!((fit.w[1] - 2.0).abs() < 1e-12);
        assert!((fit.h[0] - 2.0 / 3.0).abs() < 1e-12);
        assert!((fit.h[1] - 4.0 / 3.0).abs() < 1e-12);
        // Iteration 2 is the exact K=1 MLE fixed point: both multiplicative
        // ratios are exactly 1 (up to one ulp of round-to-even), so the
        // state and the trace stay put.
        assert!((fit.objective[2] - fit.objective[1]).abs() < 1e-12);
        assert!((fit.h[0] - 2.0 / 3.0).abs() < 1e-12);
        assert!(fit.iterations == 2 && fit.objective.len() == 3);
    }

    #[test]
    fn golden_eu_2x2_k1_one_iteration() {
        let v = [2.0, 0.0, 0.0, 4.0];
        let w0 = [1.0, 2.0];
        let h0 = [0.5, 0.5];
        let fit = fit_eu_with_init(&v, 2, 2, 1, &w0, &h0, 1).unwrap();

        // SSE at init: (3/2)² + (1/2)² + 1² + 3² = 25/2.
        assert!((fit.objective[0] - 12.5).abs() < 1e-9);
        // H step solves h = WᵀV/‖W‖² = [2, 8]/5 exactly; W step solves
        // w = VHᵀ/‖h‖² = [0.8, 6.4]/2.72 = [5/17, 40/17]. Residuals give
        // SSE = (32² + 8² + 16² + 4²)/17² = 1360/289.
        assert!((fit.objective[1] - 1360.0 / 289.0).abs() < 1e-9);
        assert!((fit.w[0] - 5.0 / 17.0).abs() < 1e-12);
        assert!((fit.w[1] - 40.0 / 17.0).abs() < 1e-12);
        assert!((fit.h[0] - 0.4).abs() < 1e-12);
        assert!((fit.h[1] - 1.6).abs() < 1e-12);
        // Monotone decrease across the single iteration.
        assert!(fit.objective[1] < fit.objective[0]);
    }

    // ------------------------------------------------------------------
    // MM monotonicity (P0 property) on seeded random count grids
    // ------------------------------------------------------------------

    #[test]
    fn kl_trace_monotone_random_count_grid() {
        let master = 2026u64;
        let grid = [
            (5usize, 7usize, 2usize),
            (16, 10, 3),
            (33, 9, 4),
            (7, 25, 3),
            (12, 12, 5),
        ];
        for (case, &(m, n, k)) in grid.iter().enumerate() {
            let mut rng = MsRng::from_stream(
                master,
                StreamId { replicate: case as u64, rank: m as u64, fold: n as u64 },
            );
            let v = random_counts(&mut rng, m, n);
            let fit = fit_kl(&v, m, n, k, 60, master + case as u64).unwrap();
            assert_monotone(&fit.objective);
            assert_all_finite(&fit.objective);
        }
    }

    #[test]
    fn eu_trace_monotone_random_count_grid() {
        let master = 77u64;
        let grid = [
            (5usize, 7usize, 2usize),
            (16, 10, 3),
            (33, 9, 4),
            (7, 25, 3),
            (12, 12, 5),
        ];
        for (case, &(m, n, k)) in grid.iter().enumerate() {
            let mut rng = MsRng::from_stream(
                master,
                StreamId { replicate: 50 + case as u64, rank: m as u64, fold: n as u64 },
            );
            let v = random_counts(&mut rng, m, n);
            let fit = fit_eu(&v, m, n, k, 60, master + case as u64).unwrap();
            assert_monotone(&fit.objective);
            assert_all_finite(&fit.objective);
        }
    }

    // ------------------------------------------------------------------
    // Separable synthetic recovery: W_true(96×3)·H_true(3×20) counts, k=3
    //
    // Construction (see `separable_truth`): separable dictionary (32
    // exclusive anchor channels per signature) + semi-pure exposures.
    // The near-pure sample groups are what pin the dictionary rays: the
    // factorization is then unique up to per-column scale and permutation,
    // which makes the matching tolerance below a test of the kernel, not
    // of identifiability. (A background-leveled or densely mixed truth is
    // NOT recoverable to this tolerance by ANY NMF variant — non-uniqueness,
    // not optimizer quality; see near_flat_signatures_smoke for that
    // regime.)
    //
    // Acceptance (D11 numerical-protocol equivalence, fixed seed + cosine
    // tolerance): reconstruction cosine ≥ 0.999; greedy-matched W columns
    // cosine ≥ 0.99 (scale-free match, per-column permutation resolved by
    // greedy max-cosine with deterministic tie-break).
    // ------------------------------------------------------------------

    /// Separable truth with the sample-purity structure that makes the
    /// dictionary identifiable: each signature owns 32 exclusive anchor
    /// channels (uniform in [0.5, 1.5), exactly 0 elsewhere; columns
    /// normalized to sum 1), and the 20 samples come in four groups of 5 —
    /// near-pure on signature 0/1/2 (cross-exposure ≤ 5%) and one fully
    /// mixed group. Anchor channels alone do NOT pin W: with dense
    /// strictly-positive exposures, `T = I + εS (S ≥ 0)` yields an equally
    /// exact alternative factorization (`W_true·T ≥ 0`, `T⁻¹H_true > 0`),
    /// so near-pure samples are the identifiability carrier — same
    /// mechanism real cohorts rely on (acute/pure tumors).
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
            let dom = j / 5; // 0, 1, 2 near-pure groups; group 3 = mixed
            for s in 0..k {
                h[s * n + j] = if dom == 3 || s == dom {
                    500.0 + 1000.0 * uniform(&mut rng)
                } else {
                    50.0 * uniform(&mut rng) // ≤ 5% cross-exposure
                };
            }
        }
        let v = matmul(&w, &h, m, n, k);
        (v, w, h)
    }

    #[test]
    fn separable_recovery_kl() {
        let (v, w_true, _h_true) = separable_truth(0xBEEF);
        let (m, n, k) = (96usize, 20usize, 3usize);
        let fit = fit_kl(&v, m, n, k, 500, 42).unwrap();
        assert_monotone(&fit.objective);
        let wh = matmul(&fit.w, &fit.h, m, n, k);
        let recon = cosine(&v, &wh);
        assert!(recon >= 0.999, "reconstruction cosine {recon}");
        let true_cols: Vec<Vec<f64>> = (0..k).map(|s| column(&w_true, m, k, s)).collect();
        let fitted_cols: Vec<Vec<f64>> = (0..k).map(|s| column(&fit.w, m, k, s)).collect();
        for c in greedy_match(&fitted_cols, &true_cols) {
            assert!(c >= 0.99, "matched W column cosine {c}");
        }
    }

    #[test]
    fn separable_recovery_eu() {
        let (v, w_true, _h_true) = separable_truth(0xBEEF);
        let (m, n, k) = (96usize, 20usize, 3usize);
        // EU-MU converges more slowly than KL-MU on this scale (linear rate
        // with a worse constant); 2000 fixed iterations buy the same
        // recovery margin at negligible cost for this problem size.
        let fit = fit_eu(&v, m, n, k, 2000, 42).unwrap();
        assert_monotone(&fit.objective);
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
    // ε behavior: structural zero channels (all-zero rows and a zero
    // column) exercise the max(·, ε) ratio path and the log(ε + ·)
    // objective path; the fit must stay NaN/Inf-free (ARCH §2.3).
    // ------------------------------------------------------------------

    #[test]
    fn zero_channels_stay_finite_kl_and_eu() {
        let (m, n, k) = (12usize, 8usize, 3usize);
        let mut rng = MsRng::from_stream(9, StreamId { replicate: 3, rank: 1, fold: 1 });
        let mut v = random_counts(&mut rng, m, n);
        for j in 0..n {
            v[3 * n + j] = 0.0; // dead channel row
            v[7 * n + j] = 0.0;
            v[j] = 0.0; // zero channel, row 0
        }
        for i in 0..m {
            v[i * n + 5] = 0.0; // dead sample column
        }
        let kl = fit_kl(&v, m, n, k, 100, 7).unwrap();
        assert_all_finite(&kl.w);
        assert_all_finite(&kl.h);
        assert_all_finite(&kl.objective);
        assert_monotone(&kl.objective);
        let eu = fit_eu(&v, m, n, k, 100, 7).unwrap();
        assert_all_finite(&eu.w);
        assert_all_finite(&eu.h);
        assert_all_finite(&eu.objective);
        assert_monotone(&eu.objective);
    }

    // ------------------------------------------------------------------
    // Determinism: the same call twice must be bit-identical (fixed loop
    // order, no parallelism, ARCH §2.6).
    // ------------------------------------------------------------------

    #[test]
    fn seeded_fit_is_bit_identical_across_runs() {
        let mut rng = MsRng::from_stream(5, StreamId { replicate: 8, rank: 8, fold: 8 });
        let v = random_counts(&mut rng, 20, 14);
        for seed in [0u64, 42, 0xDEAD_BEEF] {
            let a = fit_kl(&v, 20, 14, 3, 40, seed).unwrap();
            let b = fit_kl(&v, 20, 14, 3, 40, seed).unwrap();
            assert_eq!(a, b);
            let c = fit_eu(&v, 20, 14, 3, 40, seed).unwrap();
            let d = fit_eu(&v, 20, 14, 3, 40, seed).unwrap();
            assert_eq!(c, d);
        }
    }

    /// Different seeds give different (symmetry-broken) fits; the all-equal
    /// constant fill would clone the W columns forever.
    #[test]
    fn seeded_init_breaks_column_symmetry() {
        let mut rng = MsRng::from_stream(5, StreamId { replicate: 8, rank: 8, fold: 8 });
        let v = random_counts(&mut rng, 20, 14);
        let fit = fit_kl(&v, 20, 14, 3, 30, 11).unwrap();
        let c0 = column(&fit.w, 20, 3, 0);
        let c1 = column(&fit.w, 20, 3, 1);
        assert!(cosine(&c0, &c1) < 0.9999, "W columns stayed clones");
    }

    // ------------------------------------------------------------------
    // Flat-signature stability smoke (same spirit as U-M1s-01's
    // ill-conditioned Gram case): two near-flat, mutually near-parallel
    // signatures plus one spiky one; the kernel must not diverge and must
    // reconstruct the catalog. Recovery quality of the flat pair is NOT
    // asserted — flat-signature resolution is the identifiability problem
    // the later volume/correlation engines exist for.
    // ------------------------------------------------------------------

    #[test]
    fn near_flat_signatures_smoke() {
        let (m, n, k) = (96usize, 12usize, 3usize);
        let mut rng = MsRng::from_stream(0xF1A7, StreamId { replicate: 4, rank: 4, fold: 4 });
        let mut w = vec![0.0f64; m * k];
        for s in 0..k {
            let mut col: Vec<f64> = (0..m)
                .map(|i| match s {
                    // Two near-flat signatures differing only by small noise.
                    0 => 1.0 + 0.05 * uniform(&mut rng),
                    1 => 1.0 + 0.05 * uniform(&mut rng),
                    // One spiky signature concentrated on block 0.
                    _ => {
                        if i < 8 {
                            5.0 + uniform(&mut rng)
                        } else {
                            0.01 * uniform(&mut rng)
                        }
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
        let h: Vec<f64> = (0..k * n)
            .map(|_| 400.0 + 800.0 * uniform(&mut rng))
            .collect();
        let v = matmul(&w, &h, m, n, k);

        let fit = fit_kl(&v, m, n, k, 800, 21).unwrap();
        assert_monotone(&fit.objective);
        assert_all_finite(&fit.w);
        assert_all_finite(&fit.h);
        let wh = matmul(&fit.w, &fit.h, m, n, k);
        let recon = cosine(&v, &wh);
        assert!(recon >= 0.99, "flat-case reconstruction cosine {recon}");

        let fit_eu_flat = fit_eu(&v, m, n, k, 400, 21).unwrap();
        assert_monotone(&fit_eu_flat.objective);
        let wh_eu = matmul(&fit_eu_flat.w, &fit_eu_flat.h, m, n, k);
        let recon_eu = cosine(&v, &wh_eu);
        assert!(
            recon_eu >= 0.99,
            "flat-case EU reconstruction cosine {recon_eu}"
        );
    }
    // ------------------------------------------------------------------
    // Stream-addressed init face (U-M1s-05): `fit_kl_on_stream` must agree
    // bit-for-bit with `fit_kl` on the zero stream (the refactor is pure
    // plumbing, the kernel loop is untouched), and distinct canonical
    // streams must break symmetry differently (disjoint generator state).
    // ------------------------------------------------------------------

    #[test]
    fn fit_kl_on_zero_stream_equals_fit_kl() {
        let mut rng = MsRng::from_stream(5, StreamId { replicate: 8, rank: 8, fold: 8 });
        let v = random_counts(&mut rng, 20, 14);
        for seed in [0u64, 42, 0xDEAD_BEEF] {
            let a = fit_kl(&v, 20, 14, 3, 30, seed).unwrap();
            let b = fit_kl_on_stream(&v, 20, 14, 3, 30, seed, StreamId::ZERO).unwrap();
            assert_eq!(a, b);
        }
    }

    #[test]
    fn fit_kl_replicate_streams_are_isolated() {
        let mut rng = MsRng::from_stream(5, StreamId { replicate: 8, rank: 8, fold: 8 });
        let v = random_counts(&mut rng, 20, 14);
        let master = 42u64;
        // Replicate r runs on StreamId { replicate: r, rank: 0, fold: 0 }:
        // the frozen per-replicate layout of the parallel drivers.
        let fits: Vec<NmfFit> = (0..4u64)
            .map(|r| {
                fit_kl_on_stream(
                    &v,
                    20,
                    14,
                    3,
                    30,
                    master,
                    StreamId { replicate: r, rank: 0, fold: 0 },
                )
                .unwrap()
            })
            .collect();
        // Same stream → identical fit; different replicate streams →
        // different symmetry-broken fits (initializers are disjoint).
        for (r, fit) in fits.iter().enumerate() {
            let again = fit_kl_on_stream(
                &v,
                20,
                14,
                3,
                30,
                master,
                StreamId { replicate: r as u64, rank: 0, fold: 0 },
            )
            .unwrap();
            assert_eq!(fit, &again);
        }
        for i in 0..fits.len() {
            for j in (i + 1)..fits.len() {
                assert_ne!(fits[i], fits[j], "replicates {i} and {j} collide");
            }
        }
    }

    // ------------------------------------------------------------------
    // Structural properties and validation
    // ------------------------------------------------------------------

    #[test]
    fn zero_init_entries_are_absorbing() {
        // Documented MU property: an exact-zero init entry stays exactly 0.
        let v = [2.0, 1.0, 3.0, 1.0, 4.0, 0.0, 1.0, 2.0, 5.0];
        let w0 = [1.0, 0.0, 1.0, 1.0, 1.0, 1.0]; // W[0][1] = 0
        let h0 = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0];
        let kl = fit_kl_with_init(&v, 3, 3, 2, &w0, &h0, 5).unwrap();
        assert_eq!(kl.w[1], 0.0);
        let eu = fit_eu_with_init(&v, 3, 3, 2, &w0, &h0, 5).unwrap();
        assert_eq!(eu.w[1], 0.0);
    }

    #[test]
    fn zero_iterations_returns_initializer() {
        let v = [2.0, 0.0, 0.0, 4.0];
        let w0 = [1.0, 2.0];
        let h0 = [0.5, 0.5];
        let fit = fit_kl_with_init(&v, 2, 2, 1, &w0, &h0, 0).unwrap();
        assert_eq!(fit.iterations, 0);
        assert_eq!(fit.objective.len(), 1);
        assert_eq!(fit.w, w0.to_vec());
        assert_eq!(fit.h, h0.to_vec());
        assert!((fit.objective[0] - (6.0 * 4.0f64.ln() - 3.0)).abs() < 1e-9);
    }

    #[test]
    fn input_validation_errors() {
        let v = [1.0, 2.0, 3.0, 4.0];
        // k = 0.
        assert_eq!(fit_kl(&v, 2, 2, 0, 1, 0).unwrap_err().topic(), "argument");
        // Storage mismatch.
        assert_eq!(
            fit_kl(&v[..3], 2, 2, 1, 1, 0).unwrap_err().topic(),
            "argument"
        );
        // NaN / negative counts with 1-based indices attached.
        let err = fit_kl(&[1.0, f64::NAN, 3.0, 4.0], 2, 2, 1, 1, 0).unwrap_err();
        assert_eq!(err.topic(), "na");
        assert_eq!(err.i, Some(1));
        assert_eq!(err.j, Some(2));
        let err = fit_eu(&[1.0, -2.0, 3.0, 4.0], 2, 2, 1, 1, 0).unwrap_err();
        assert_eq!(err.topic(), "argument");
        // Bad initializer shapes / values.
        let err = fit_kl_with_init(&v, 2, 2, 1, &[1.0, 2.0, 3.0], &[0.5, 0.5], 1).unwrap_err();
        assert_eq!(err.topic(), "argument");
        let err = fit_eu_with_init(&v, 2, 2, 1, &[1.0, f64::INFINITY], &[0.5, 0.5], 1).unwrap_err();
        assert_eq!(err.topic(), "na");
        // Negative initializer.
        let err = fit_kl_with_init(&v, 2, 2, 1, &[1.0, -1.0], &[0.5, 0.5], 1).unwrap_err();
        assert_eq!(err.topic(), "argument");
    }

    /// The seeded init contract: with `max_iter = 0` the returned factors
    /// are the raw initializer — strictly positive (open interval, so the
    /// MU zero-absorbing property is never armed) and bounded by the data
    /// scale `(mean(V)/k).sqrt()`.
    #[test]
    fn seeded_init_contract_open_interval_and_scale() {
        let (v, _w, _h) = separable_truth(0xCAFE);
        let (m, n, k) = (96usize, 20usize, 3usize);
        let fit = fit_kl(&v, m, n, k, 0, 1).unwrap();
        let mean: f64 = v.iter().sum::<f64>() / (m * n) as f64;
        let scale = (mean / k as f64).sqrt();
        assert!(fit.w.iter().all(|&x| x > 0.0 && x <= scale));
        assert!(fit.h.iter().all(|&x| x > 0.0 && x <= scale));
        // And the documented draw order: W first, then H, from one stream —
        // same seed therefore reproduces the identical initializer.
        let again = fit_kl(&v, m, n, k, 0, 1).unwrap();
        assert_eq!(fit, again);
    }
}
