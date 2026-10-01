//! Sparse / minimum-volume NMF kernels (U-M2-05; `docs/CAPABILITY-MATRIX.md`
//! L-C `ms_sparse` row: "volume-regularized mvNMF (Leplat–Gillis) + L1").
//!
//! Two deterministic KL-NMF variants share this module:
//!
//! # 1. Volume-regularized NMF ([`fit_volume`], Leplat–Gillis–Ang)
//!
//! Objective (Leplat, Gillis & Ang, "Blind Audio Source Separation With
//! Minimum-Volume Beta-Divergence NMF", IEEE Trans. Signal Process. 68:
//! 3400–3410, 2020 — the β = 1 / KL member of the paper's family, as
//! implemented by Sonata):
//!
//! ```text
//! min_{W,H ≥ 0}  D_KL(V ‖ WH) + λ · log det(WᵀW + δI)
//! ```
//!
//! The log-determinant volume term shrinks the simplex volume spanned by
//! the signature columns, restoring identifiability under correlated /
//! near-parallel signatures (the linear-world counterpart of Cornet's
//! embedding model, `docs/research/01` §1/§9).
//!
//! Upstream implementation anchor (pinned to source, D11/D13):
//! `parklab/Sonata` `src/sonata/models/mvnmf.py` (MIT), line numbers of
//! master:
//!
//! 1. **H step is the plain KL multiplicative update** (mvnmf.py:162–165,
//!    `update_H` in `_utils_nmf.py:221`) — the volume term does not touch
//!    H. This port reuses [`crate::nmf::kl_h_step`] verbatim.
//! 2. **W proposal** (mvnmf.py:38–66, `update_W_unconstrained`): with
//!    `Y = (WᵀW + δI)⁻¹`, the per-entry positive root of the MM quadratic
//!    (paper eq. 4 objective, KL case):
//!    ```text
//!    a = 4λ·(W|Y|)[i,s]          (|Y| entrywise absolute value)
//!    b = R[s] − 4λ·(W·max(0,−Y))[i,s]
//!    c = −K[i,s]/2,  K = (V ⊘ max(WH, ε))·Hᵀ,  R[s] = Σ_j H[s,j]
//!    W_unc[i,s] ← W[i,s] · (√(b² + 8λ·(W|Y|)[i,s]·K[i,s]) − R[s]
//!                            + 4λ·(W·max(0,−Y))[i,s]) / (4λ·(W|Y|)[i,s])
//!    ```
//!    clipped below at ε (mvnmf.py:63–65).
//! 3. **Backtracking line search** (mvnmf.py:70–92): trial step γ = 1 (the
//!    proposal, W columns renormalized to sum 1 and H rescaled by the same
//!    factors — `normalize_WH`, Sonata `src/sonata/utils.py:155–157`,
//!    preserving WH; both clipped below at ε); while the penalized objective
//!    increases and γ > 1e-16, γ ← 0.8γ and
//!    `W ← (1−γ)·W_old + γ·W_unc` (renormalized + clipped); afterwards
//!    γ ← min(1, 1.2γ) (adaptive step growth). The accepted point never
//!    increases the penalized objective except through the γ-floor exit —
//!    tests assert non-increase within the crate's 1e-9 slack.
//! 4. **Iteration order** (mvnmf.py:197–210): one H step, then the W
//!    proposal + line search. Defaults λ = 1, δ = 1 (mvnmf.py:103–107),
//!    max_iterations = 10000, tol = 1e-7 (mvnmf.py:122–125).
//!
//! λ = 0 falls back to the plain KL W step ([`crate::nmf::kl_w_step`]) —
//! the exact λ → 0 limit of the objective — so the volume pipeline at λ = 0
//! is plain KL-NMF plus W-column normalization.
//!
//! # 2. L1-penalized NMF ([`fit_sparse_l1`], SparseSignatures L1L1)
//!
//! Objective (SparseSignatures; `docs/research/01` §9 "SparseSignatures:
//! L1-penalized Poisson NMF"; classic penalized MU, Hoyer 2002 / Cichocki
//! et al. 2009):
//!
//! ```text
//! min_{W,H ≥ 0}  D_KL(V ‖ WH) + λ · Σ_{k,j} H[k,j] + μ · Σ_{i,k} W[i,k]
//! ```
//!
//! Updates: `H ← H ⊙ (Wᵀ(V ⊘ max(WH,ε))) ⊘ max(Wᵀ1 + λ, ε)` and
//! `W ← W ⊙ ((V ⊘ max(WH,ε))Hᵀ) ⊘ max(1·Hᵀ + μ, ε)` — the linear penalties
//! enter the denominators exactly, so each step is MM-monotone for the
//! penalized objective and the whole trace is non-increasing (within
//! round-off; asserted). λ is the exposure-sparsity knob the ms_sparse face
//! needs; **μ is load-bearing, not decoration**: with μ = 0 the W step
//! rescales each column to whatever the data demands and the exposure L1
//! degenerates to a per-component rescaling (W grows, H shrinks, WH
//! unchanged — the scale lives in the WH product, which the KL alone pins).
//! The two penalties jointly pin the scale: the equilibrium column scale is
//! `c = (num_w − den_h)/μ = λ/(num_h − den_w)`, so a component whose data
//! support does not justify the budget dies. Both knobs are **absolute-scale
//! parameters**: they bite when they are comparable to the running
//! denominator scales (`Wᵀ1` for λ, `1ᵀHᵀ` for μ). A λ far above the W
//! column sums with a fixed μ re-introduces the uniform rescaling (the whole
//! factor pair shrinks; relative shares lose meaning), so the weights must be
//! calibrated to the catalog — exactly what SparseSignatures' 
//! bi-cross-validation does and what the R factory layer (later unit) owns.
//! SparseSignatures itself penalizes both factors; at λ = μ = 0 the mode is
//! exactly the audited [`crate::nmf::fit_kl`] — bit-for-bit, including the
//! objective trace (regression anchor, tested; `0.0·Σ` terms and `+ 0.0`
//! denominators are IEEE identities and the loop/order/ε policy is the
//! audited one).
//!
//! # Convergence, trace, determinism
//!
//! `objective[0]` is the penalized objective at the initializer; entry `t ≥ 1`
//! the value after `t` iterations. Each iteration the relative objective
//! change `|Δ| / max(|prev|, ε)` is compared to `tol`: below → `converged`
//! and stop. `tol = 0` disables early stopping (fixed-iteration mode — the
//! [`crate::nmf`] convention; the λ = 0 anchor test requires it to reproduce
//! `fit_kl`'s full trace bit-for-bit). The L1 trace is monotone (MM); the
//! volume trace is monotone within the 1e-9 slack (line search with γ-floor
//! exit). Fixed loop order, sequential reductions, no parallelism: equal
//! inputs give bit-identical output (ARCH §2.6).
//!
//! # Initialization
//!
//! Seeded deterministic init identical to [`crate::nmf`] (open-interval
//! uniforms (0, 1] from [`crate::rng::MsRng`], W row-major then H row-major,
//! scaled by `(mean(V)/k).sqrt()`). Sonata's default NNDSVD init is out of
//! scope here (U-M1s-03 module composes via the `_with_init` faces). The
//! volume pipeline renormalizes W columns to unit sum from the first line
//! search on (upstream geometry — the line search's `normalize_WH`, Sonata
//! `src/sonata/utils.py:155–157`), so returned volume-mode signatures are
//! unit-sum by construction; exposures carry the scale. The L1L1 mode does
//! not renormalize (the penalties themselves pin the scale; kernel purity
//! as in [`crate::nmf`]).
//!
//! # Deviations from upstream (all deliberate, D13)
//!
//! 1. **ε policy**: Sonata's `EPSILON = f32::eps ≈ 1.19e-7`
//!    (`initialization/initialize.py:29`) and its clip-based guards are
//!    replaced by the crate ε ([`crate::nmf::KL_EPS`] = 1e-12) with floor
//!    guards (ARCH §2 contract).
//! 2. **Convergence check every iteration**; Sonata checks every
//!    `conv_test_freq = 10` (mvnmf.py:124) — same tolerance scale, slightly
//!    earlier stops. Sonata also enforces `min_iterations = 500`
//!    (mvnmf.py:124-125) before the convergence test may fire; this port
//!    has no minimum — with the default tol the runs here converge well
//!    past 500, but a loose tol could stop earlier (declared).
//! 3. **Init**: seeded uniform instead of NNDSVD (see above); the KL data
//!    term uses the crate `log(ε + ·)` path instead of Sonata's raw form.
//! 4. **β-divergence generality**: only the β = 1 (KL) member is
//!    implemented — the mutational-count default and the CAPABILITY-MATRIX
//!    L-C semantics.
//! 5. **L1 defaults**: SparseSignatures selects its (λ, μ) by
//!    bi-cross-validation on relative-frequency catalogs — data-scale
//!    dependent, so no absolute default carries over; [`SPARSE_LAMBDA`] /
//!    [`SPARSE_MU`] = 1 are msuiter working defaults and the R factory layer
//!    (later unit) owns tuning.
//!
//! # Contract notes
//!
//! Pure engine kernel: no FFI face, no `unsafe`, no dependencies; every
//! entry point returns `Result<_, MsError>` (FFI contract 5).

use crate::error::MsError;
use crate::nmf::{kl_h_step, kl_w_step, matmul, KL_EPS};
use crate::rng::{MsRng, StreamId};

/// Sonata default volume weight `lam` (mvnmf.py:103).
pub const SPARSE_LAMBDA: f64 = 1.0;

/// Msuiter working default signature-side L1 weight `μ` (SparseSignatures
/// selects weights by bi-cross-validation — data-scale dependent, so no
/// absolute upstream default exists; see module docs "L1 defaults").
pub const SPARSE_MU: f64 = 1.0;

/// Sonata default volume hyperparameter `delta` (mvnmf.py:106; paper eq. 4 —
/// keeps `WᵀW + δI` positive definite when signature columns collapse).
pub const SPARSE_DELTA: f64 = 1.0;

/// Sonata default convergence tolerance (mvnmf.py:125).
pub const SPARSE_TOL: f64 = 1e-7;

/// Sonata default iteration cap (mvnmf.py:123).
pub const SPARSE_MAX_ITER: usize = 10_000;

/// Line-search γ floor (mvnmf.py:84).
const GAMMA_MIN: f64 = 1e-16;

/// Outcome of a sparse/volume NMF fit.
#[derive(Debug, Clone, PartialEq)]
pub struct SparseFit {
    /// Signature matrix `W`, row-major `m×k`. Volume mode: columns unit-sum.
    pub w: Vec<f64>,
    /// Exposure matrix `H`, row-major `k×n`.
    pub h: Vec<f64>,
    /// Penalized objective trace: `objective[0]` at the initializer,
    /// `objective[t]` after `t` iterations. Length `iterations + 1`.
    pub objective: Vec<f64>,
    /// Iterations actually run.
    pub iterations: usize,
    /// True iff the relative-change criterion fired before the cap.
    pub converged: bool,
}

/// Volume-regularized KL-NMF (Leplat–Gillis–Ang) with the seeded
/// deterministic initializer (module docs).
#[allow(clippy::too_many_arguments)]
pub fn fit_volume(
    v: &[f64],
    m: usize,
    n: usize,
    k: usize,
    lambda: f64,
    delta: f64,
    max_iter: usize,
    tol: f64,
    seed: u64,
) -> Result<SparseFit, MsError> {
    let (w0, h0) = seeded_init(v, m, n, k, seed)?;
    fit_volume_with_init(v, m, n, k, lambda, delta, &w0, &h0, max_iter, tol)
}

/// Volume-regularized KL-NMF from a caller-provided initializer (layout and
/// zero caveat as in [`crate::nmf::fit_kl_with_init`]).
#[allow(clippy::too_many_arguments)]
pub fn fit_volume_with_init(
    v: &[f64],
    m: usize,
    n: usize,
    k: usize,
    lambda: f64,
    delta: f64,
    w0: &[f64],
    h0: &[f64],
    max_iter: usize,
    tol: f64,
) -> Result<SparseFit, MsError> {
    validate(v, m, n, k, w0, h0, tol, lambda, Some(delta))?;
    let mut w = w0.to_vec();
    let mut h = h0.to_vec();
    let mut objective = Vec::with_capacity(max_iter + 1);
    objective.push(volume_objective(v, &w, &h, m, n, k, lambda, delta));

    // Adaptive line-search state, initialized once per fit (mvnmf.py:137,218).
    let mut gamma = 1.0f64;
    let mut converged = false;
    let mut iterations = 0usize;
    for iter in 1..=max_iter {
        // H step: plain KL (mvnmf.py:162–165) — verbatim reuse of the
        // audited kernel; the volume term does not touch H.
        kl_h_step(v, &w, &mut h, m, n, k);
        let w_unc = volume_w_proposal(v, &w, &h, m, n, k, lambda, delta)?;
        let prev = objective[objective.len() - 1];
        // Trial step γ = 1: proposal, normalized + clipped (mvnmf.py:80-82).
        let (mut wn, mut hn) = normalize_wh(&w_unc, &h, m, n, k);
        clip_below(&mut wn);
        clip_below(&mut hn);
        let mut of = volume_objective(v, &wn, &hn, m, n, k, lambda, delta);
        // Backtracking (mvnmf.py:84-89).
        while of > prev && gamma > GAMMA_MIN {
            gamma *= 0.8;
            for i in 0..m {
                for s in 0..k {
                    wn[i * k + s] = (1.0 - gamma) * w[i * k + s] + gamma * w_unc[i * k + s];
                }
            }
            let blended = normalize_wh(&wn, &h, m, n, k);
            wn = blended.0;
            hn = blended.1;
            clip_below(&mut wn);
            clip_below(&mut hn);
            of = volume_objective(v, &wn, &hn, m, n, k, lambda, delta);
        }
        gamma *= 1.2;
        if gamma > 1.0 {
            gamma = 1.0;
        }
        w = wn;
        h = hn;
        objective.push(of);
        iterations = iter;
        if tol > 0.0
            && (of - prev).abs() / (prev.abs().max(KL_EPS)) < tol
        {
            converged = true;
            break;
        }
    }
    Ok(SparseFit { w, h, objective, iterations, converged })
}

/// L1L1-penalized KL-NMF (SparseSignatures) with the seeded deterministic
/// initializer. `lambda` weights the exposure L1 (the sparsity knob);
/// `mu` weights the signature L1 and pins the factor scale (module docs —
/// with `mu = 0` the exposure penalty degenerates to a rescaling).
#[allow(clippy::too_many_arguments)]
pub fn fit_sparse_l1(
    v: &[f64],
    m: usize,
    n: usize,
    k: usize,
    lambda: f64,
    mu: f64,
    max_iter: usize,
    tol: f64,
    seed: u64,
) -> Result<SparseFit, MsError> {
    let (w0, h0) = seeded_init(v, m, n, k, seed)?;
    fit_sparse_l1_with_init(v, m, n, k, lambda, mu, &w0, &h0, max_iter, tol)
}

/// L1L1-penalized KL-NMF from a caller-provided initializer.
#[allow(clippy::too_many_arguments)]
pub fn fit_sparse_l1_with_init(
    v: &[f64],
    m: usize,
    n: usize,
    k: usize,
    lambda: f64,
    mu: f64,
    w0: &[f64],
    h0: &[f64],
    max_iter: usize,
    tol: f64,
) -> Result<SparseFit, MsError> {
    validate(v, m, n, k, w0, h0, tol, lambda, None)?;
    if !mu.is_finite() || mu < 0.0 {
        return Err(MsError::new("argument", "mu must be finite and non-negative").with_i(1));
    }
    let mut w = w0.to_vec();
    let mut h = h0.to_vec();
    let mut objective = Vec::with_capacity(max_iter + 1);
    objective.push(l1_objective(v, &w, &h, m, n, k, lambda, mu));
    let mut converged = false;
    let mut iterations = 0usize;
    for iter in 1..=max_iter {
        l1_h_step(v, &w, &mut h, m, n, k, lambda);
        l1_w_step(v, &mut w, &h, m, n, k, mu);
        let of = l1_objective(v, &w, &h, m, n, k, lambda, mu);
        let prev = objective[objective.len() - 1];
        objective.push(of);
        iterations = iter;
        if tol > 0.0 && (of - prev).abs() / (prev.abs().max(KL_EPS)) < tol {
            converged = true;
            break;
        }
    }
    Ok(SparseFit { w, h, objective, iterations, converged })
}

// ======================================================================
// Kernels
// ======================================================================

/// One L1-penalized KL H step:
/// `H ← H ⊙ (Wᵀ (V ⊘ max(WH, ε))) ⊘ max(Wᵀ1 + λ, ε)`. Loop structure and
/// ε placement mirror [`crate::nmf::kl_h_step`]; `λ = 0` reproduces it
/// bit-for-bit (adding 0.0 is an IEEE identity).
fn l1_h_step(v: &[f64], w: &[f64], h: &mut [f64], m: usize, n: usize, k: usize, lambda: f64) {
    let wh = matmul(w, h, m, n, k);
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
    for s in 0..k {
        let mut col = 0.0f64;
        for i in 0..m {
            col += w[i * k + s];
        }
        for j in 0..n {
            let den = (col + lambda).max(KL_EPS);
            h[s * n + j] *= num[s * n + j] / den;
        }
    }
}

/// One L1-penalized KL W step:
/// `W ← W ⊙ ((V ⊘ max(WH, ε)) Hᵀ) ⊘ max(1_m Hᵀ + μ, ε)`. Mirrors
/// [`crate::nmf::kl_w_step`]; `μ = 0` reproduces it bit-for-bit.
fn l1_w_step(v: &[f64], w: &mut [f64], h: &[f64], m: usize, n: usize, k: usize, mu: f64) {
    let wh = matmul(w, h, m, n, k);
    for i in 0..m {
        for s in 0..k {
            let mut num = 0.0f64;
            for j in 0..n {
                let r = v[i * n + j] / wh[i * n + j].max(KL_EPS);
                num += r * h[s * n + j];
            }
            let mut den = 0.0f64;
            for j in 0..n {
                den += h[s * n + j];
            }
            w[i * k + s] *= num / (den + mu).max(KL_EPS);
        }
    }
}

/// The volume-mode W proposal (Sonata mvnmf.py:38–66, verbatim port): the
/// per-entry positive root of the MM quadratic for the log-det-penalized KL
/// objective (module docs). `λ = 0` falls back to the plain KL W step —
/// the exact λ → 0 limit of the objective.
#[allow(clippy::too_many_arguments)]
fn volume_w_proposal(
    v: &[f64],
    w: &[f64],
    h: &[f64],
    m: usize,
    n: usize,
    k: usize,
    lambda: f64,
    delta: f64,
) -> Result<Vec<f64>, MsError> {
    if lambda == 0.0 {
        let mut wn = w.to_vec();
        kl_w_step(v, &mut wn, h, m, n, k);
        return Ok(wn);
    }
    let y = gram_inverse(w, m, k, delta)?;

    // wy_minus[i][s] = Σ_t W[i][t]·max(0, −Y[t][s]); wy_abs[i][s] with |Y|.
    let mut wy_minus = vec![0.0f64; m * k];
    let mut wy_abs = vec![0.0f64; m * k];
    for i in 0..m {
        for s in 0..k {
            let mut accm = 0.0f64;
            let mut acca = 0.0f64;
            for t in 0..k {
                let yst = y[t * k + s];
                accm += w[i * k + t] * (-yst).max(0.0);
                acca += w[i * k + t] * yst.abs();
            }
            wy_minus[i * k + s] = accm;
            wy_abs[i * k + s] = acca;
        }
    }

    // k_num[i][s] = Σ_j (V ⊘ max(WH, ε))[i][j]·H[s][j]  — the KL numerator.
    let wh = matmul(w, h, m, n, k);
    let mut k_num = vec![0.0f64; m * k];
    for i in 0..m {
        for j in 0..n {
            let r = v[i * n + j] / wh[i * n + j].max(KL_EPS);
            if r != 0.0 {
                for s in 0..k {
                    k_num[i * k + s] += r * h[s * n + j];
                }
            }
        }
    }

    let mut wn = vec![0.0f64; m * k];
    for i in 0..m {
        for s in 0..k {
            // R[s] = Σ_j H[s][j]
            let mut rh = 0.0f64;
            for j in 0..n {
                rh += h[s * n + j];
            }
            let wm = wy_minus[i * k + s];
            let wa = wy_abs[i * k + s];
            let ks = k_num[i * k + s];
            let disc = (rh - 4.0 * lambda * wm) * (rh - 4.0 * lambda * wm)
                + 8.0 * lambda * wa * ks;
            let num = disc.sqrt() + (-rh + 4.0 * lambda * wm);
            // Floor guards the degenerate all-zero W row (crate ε policy;
            // upstream's EPSILON clip keeps this away by construction).
            let den = (4.0 * lambda * wa).max(KL_EPS);
            wn[i * k + s] = (w[i * k + s] * num / den).max(KL_EPS);
        }
    }
    Ok(wn)
}

/// `log det(WᵀW + δI)` via Cholesky (`det = Π L_ss²`).
#[allow(clippy::too_many_arguments)]
fn volume_objective(
    v: &[f64],
    w: &[f64],
    h: &[f64],
    m: usize,
    n: usize,
    k: usize,
    lambda: f64,
    delta: f64,
) -> f64 {
    let kl = kl_objective(v, w, h, m, n, k);
    if lambda == 0.0 {
        return kl;
    }
    match logdet_gram(w, m, k, delta) {
        Some(lg) => kl + lambda * lg,
        // Unreachable behind validate(δ > 0) + chol definiteness; the
        // fit entry points surface the error through the proposal path.
        None => f64::INFINITY,
    }
}

/// Penalized objective of the L1L1 mode: `D_KL(V‖WH) + λ·Σ H + μ·Σ W`. At
/// `λ = μ = 0` the extra terms are exactly `0.0·Σ = 0.0` and `kl + 0.0`,
/// so the value is bit-identical to the [`crate::nmf`] KL objective.
#[allow(clippy::too_many_arguments)]
fn l1_objective(
    v: &[f64],
    w: &[f64],
    h: &[f64],
    m: usize,
    n: usize,
    k: usize,
    lambda: f64,
    mu: f64,
) -> f64 {
    let kl = kl_objective(v, w, h, m, n, k);
    let mut hsum = 0.0f64;
    for &x in h {
        hsum += x;
    }
    let mut wsum = 0.0f64;
    for &x in w {
        wsum += x;
    }
    kl + lambda * hsum + mu * wsum
}

/// Generalized KL divergence, op-for-op the [`crate::nmf`] objective (kept
/// local because that function is private to its module).
fn kl_objective(v: &[f64], w: &[f64], h: &[f64], m: usize, n: usize, k: usize) -> f64 {
    let wh = matmul(w, h, m, n, k);
    let mut acc = 0.0f64;
    for (&vv, &mm) in v.iter().zip(wh.iter()) {
        acc += vv * ((KL_EPS + vv).ln() - (KL_EPS + mm).ln()) - vv + mm;
    }
    acc
}

/// Sonata `normalize_WH` (`src/sonata/utils.py:155–157`): W columns to unit
/// sum, H rows scaled by the same factors (preserves WH exactly in exact
/// arithmetic). Column sums are floored at ε (upstream's EPSILON clip
/// guarantees positivity; the floor plays that role here).
fn normalize_wh(w: &[f64], h: &[f64], m: usize, n: usize, k: usize) -> (Vec<f64>, Vec<f64>) {
    let mut wn = vec![0.0f64; m * k];
    let mut hn = h.to_vec();
    for s in 0..k {
        let mut col = 0.0f64;
        for i in 0..m {
            col += w[i * k + s];
        }
        let f = if col > KL_EPS { col } else { KL_EPS };
        for i in 0..m {
            wn[i * k + s] = w[i * k + s] / f;
        }
        for j in 0..n {
            hn[s * n + j] = h[s * n + j] * f;
        }
    }
    (wn, hn)
}

fn clip_below(x: &mut [f64]) {
    for e in x.iter_mut() {
        if *e < KL_EPS {
            *e = KL_EPS;
        }
    }
}

// ======================================================================
// Small dense helpers (k×k; k is the component count, ≤ ~10², so the
// cubic cost is negligible next to the m·n·k passes).
// ======================================================================

/// Cholesky factorization `A = L Lᵀ` (lower triangular) of a symmetric
/// positive definite `k×k` matrix; `None` if a non-positive pivot appears.
fn cholesky(a: &[f64], k: usize) -> Option<Vec<f64>> {
    let mut l = vec![0.0f64; k * k];
    for s in 0..k {
        for t in 0..=s {
            let mut sum = a[s * k + t];
            for r in 0..t {
                sum -= l[s * k + r] * l[t * k + r];
            }
            if s == t {
                if sum <= 0.0 || !sum.is_finite() {
                    return None;
                }
                l[s * k + s] = sum.sqrt();
            } else {
                l[s * k + t] = sum / l[t * k + t];
            }
        }
    }
    Some(l)
}

/// `log det(A)` for `A = WᵀW + δI` via [`cholesky`].
fn logdet_gram(w: &[f64], m: usize, k: usize, delta: f64) -> Option<f64> {
    let a = gram_add_delta(w, m, k, delta);
    let l = cholesky(&a, k)?;
    let mut acc = 0.0f64;
    for s in 0..k {
        acc += l[s * k + s].ln();
    }
    Some(2.0 * acc)
}

/// `Y = (WᵀW + δI)⁻¹` via Cholesky solve against the identity (Sonata uses
/// `np.linalg.inv`, mvnmf.py:48; a Cholesky inverse is the deterministic,
/// symmetric-exploiting equivalent).
fn gram_inverse(w: &[f64], m: usize, k: usize, delta: f64) -> Result<Vec<f64>, MsError> {
    let a = gram_add_delta(w, m, k, delta);
    let l = cholesky(&a, k)
        .ok_or_else(|| MsError::new("argument", "W^T W + delta*I is not positive definite; increase delta").with_i(1))?;
    let mut y = vec![0.0f64; k * k];
    let mut col = vec![0.0f64; k];
    for t in 0..k {
        // Solve L z = e_t (forward), then Lᵀ y_t = z (backward).
        for r in 0..k {
            let mut s = if r == t { 1.0 } else { 0.0 };
            for p in 0..r {
                s -= l[r * k + p] * col[p];
            }
            col[r] = s / l[r * k + r];
        }
        for r in (0..k).rev() {
            let mut s = col[r];
            for p in (r + 1)..k {
                s -= l[p * k + r] * col[p];
            }
            col[r] = s / l[r * k + r];
        }
        for r in 0..k {
            y[r * k + t] = col[r];
        }
    }
    Ok(y)
}

/// `WᵀW + δI` (symmetric, upper triangle accumulated then mirrored).
fn gram_add_delta(w: &[f64], m: usize, k: usize, delta: f64) -> Vec<f64> {
    let mut a = vec![0.0f64; k * k];
    for i in 0..m {
        for s in 0..k {
            let wis = w[i * k + s];
            if wis == 0.0 {
                continue;
            }
            for t in s..k {
                a[s * k + t] += wis * w[i * k + t];
            }
        }
    }
    for s in 0..k {
        for t in 0..s {
            a[s * k + t] = a[t * k + s];
        }
        a[s * k + s] += delta;
    }
    a
}

// ======================================================================
// Initialization and validation (nmf.rs conventions; identical init so
// the λ = 0 anchor is bit-exact).
// ======================================================================

/// Seeded deterministic initializer, identical to the [`crate::nmf`] one
/// (open-interval uniforms (0, 1], W row-major then H row-major, scale
/// `(mean(V)/k).sqrt()`) — required for the bit-exact λ = 0 anchor.
fn seeded_init(v: &[f64], m: usize, n: usize, k: usize, seed: u64) -> Result<(Vec<f64>, Vec<f64>), MsError> {
    validate_shape(v, m, n, k)?;
    let mut rng = MsRng::from_stream(seed, StreamId::ZERO);
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

/// Uniform draw on (0, 1] (same convention as [`crate::nmf`]).
fn open_unit(rng: &mut MsRng) -> f64 {
    ((rng.next_u64() >> 11) as f64 + 1.0) * (1.0 / (1u64 << 53) as f64)
}

fn validate_shape(v: &[f64], m: usize, n: usize, k: usize) -> Result<(), MsError> {
    if m == 0 || n == 0 || k == 0 {
        return Err(MsError::new("argument", "matrix dimensions must be positive")
            .with_i(m as i64)
            .with_j(n as i64));
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

#[allow(clippy::too_many_arguments)]
fn validate(
    v: &[f64],
    m: usize,
    n: usize,
    k: usize,
    w0: &[f64],
    h0: &[f64],
    tol: f64,
    lambda: f64,
    delta: Option<f64>,
) -> Result<(), MsError> {
    validate_shape(v, m, n, k)?;
    if w0.len() != m * k {
        return Err(
            MsError::new("argument", "w0 storage must be m*k elements").with_i(w0.len() as i64),
        );
    }
    if h0.len() != k * n {
        return Err(
            MsError::new("argument", "h0 storage must be k*n elements").with_i(h0.len() as i64),
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
    if !tol.is_finite() || tol < 0.0 {
        // tol = 0 is the documented fixed-iteration mode.
        return Err(MsError::new("argument", "tol must be finite and non-negative").with_i(1));
    }
    if !lambda.is_finite() || lambda < 0.0 {
        return Err(MsError::new("argument", "lambda must be finite and non-negative").with_i(1));
    }
    if let Some(d) = delta {
        if !d.is_finite() || d <= 0.0 {
            return Err(MsError::new("argument", "delta must be finite and positive").with_i(1));
        }
    }
    Ok(())
}

// ======================================================================
// Tests: hand-derived goldens at 1e-12 (L1 one-step penalized update on a
// 2×2; volume log-determinant and Gram inverse; volume W proposal root),
// the λ = 0 regression anchor (bit-equality with the audited KL kernel),
// separable recovery with the volume term, λ sweeps (L1 sparsity trend,
// volume de-collinearization), bit determinism, and validation. Fixed
// seeds only (MsRng, StreamId layout).
// ======================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::nmf::fit_kl;

    /// Uniform f64 in [0, 1) from the in-house generator (test data only).
    fn uniform(rng: &mut MsRng) -> f64 {
        ((rng.next_u64() >> 11) as f64) * (1.0 / (1u64 << 53) as f64)
    }

    fn cosine(a: &[f64], b: &[f64]) -> f64 {
        let dot: f64 = a.iter().zip(b.iter()).map(|(&x, &y)| x * y).sum();
        let na: f64 = a.iter().map(|x| x * x).sum::<f64>().sqrt();
        let nb: f64 = b.iter().map(|x| x * x).sum::<f64>().sqrt();
        dot / (na * nb)
    }

    fn column(mat: &[f64], rows: usize, cols: usize, c: usize) -> Vec<f64> {
        (0..rows).map(|r| mat[r * cols + c]).collect()
    }

    fn greedy_match(fitted_cols: &[Vec<f64>], true_cols: &[Vec<f64>]) -> Vec<f64> {
        let mut pairs: Vec<(usize, usize, f64)> = Vec::new();
        for (i, fw) in fitted_cols.iter().enumerate() {
            for (t, tw) in true_cols.iter().enumerate() {
                pairs.push((i, t, cosine(fw, tw)));
            }
        }
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

    /// Assert MM-style non-increase within the crate's 1e-9 relative slack.
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

    /// Separable truth (96×3 · 3×20), as in the nmf.rs test suite.
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
            let dom = j / 5;
            for s in 0..k {
                h[s * n + j] = if dom == 3 || s == dom {
                    500.0 + 1000.0 * uniform(&mut rng)
                } else {
                    50.0 * uniform(&mut rng)
                };
            }
        }
        let v = matmul(&w, &h, m, n, k);
        (v, w, h)
    }

    // ------------------------------------------------------------------
    // Golden (hand-derived, 2×2, k = 1, one iteration): V = [[2,0],[0,4]],
    // W0 = [[1],[2]], H0 = [[0.5, 0.5]], λ = 1/2.
    // H step: WH0 = [[0.5,0.5],[1,1]], R = V⊘WH0 = [[4,0],[0,4]];
    // num = [1·4+2·0, 1·0+2·4] = [4, 8]; den = (3 + 1/2);
    // H1 = [0.5·4/(7/2), 0.5·8/(7/2)] = [4/7, 8/7].
    // W step with μ = 0 (plain kl_w_step): W1 = [2, 4]·(7/12) = [7/6, 7/3],
    // so WH1 = [[2/3,4/3],[4/3,8/3]] — identical to the nmf.rs golden's
    // reconstruction, whose KL constants cancel to 0: objective[1] =
    // 2·ln3 + 4·ln(3/2) + 1/2·(12/7). W step with μ = 1/2 (direct kernel
    // golden): den = 12/7 + 1/2 = 31/14, num = [2, 2] ⇒ W1 = [28/31, 56/31].
    // objective[0] = (6·ln4 − 3) + 1/2·(1 + 3).
    // ------------------------------------------------------------------
    #[test]
    fn golden_l1_one_step_2x2() {
        let v = [2.0, 0.0, 0.0, 4.0];
        let (m, n, k) = (2usize, 2usize, 1usize);
        let w0 = [1.0, 2.0];
        let h0 = [0.5, 0.5];
        let lambda = 0.5;

        // One full iteration at (λ, μ) = (1/2, 0).
        let fit = fit_sparse_l1_with_init(&v, m, n, k, lambda, 0.0, &w0, &h0, 1, 0.0).unwrap();
        assert!((fit.h[0] - 4.0 / 7.0).abs() < 1e-12, "h1 = {:?}", fit.h);
        assert!((fit.h[1] - 8.0 / 7.0).abs() < 1e-12);
        assert!((fit.w[0] - 7.0 / 6.0).abs() < 1e-12, "w1 = {:?}", fit.w);
        assert!((fit.w[1] - 7.0 / 3.0).abs() < 1e-12);
        assert!((fit.objective[0] - (6.0 * 4.0f64.ln() - 3.0 + 0.5)).abs() < 1e-9);
        let want1 = 2.0 * 3.0f64.ln() + 4.0 * 1.5f64.ln() + 6.0 / 7.0;
        assert!((fit.objective[1] - want1).abs() < 1e-9);
        assert_eq!(fit.iterations, 1);
        assert!(!fit.converged, "tol = 0 must disable early stopping");

        // Kernel golden: the μ-penalized W step at (H1, μ = 1/2).
        let h1 = [4.0 / 7.0, 8.0 / 7.0];
        let mut w1 = w0;
        l1_w_step(&v, &mut w1, &h1, m, n, k, 0.5);
        assert!((w1[0] - 28.0 / 31.0).abs() < 1e-12, "μ-golden w1 = {w1:?}");
        assert!((w1[1] - 56.0 / 31.0).abs() < 1e-12);
    }

    // ------------------------------------------------------------------
    // Golden (hand-derived): volume log-determinant and Gram inverse.
    // W = [[1,0],[0,1],[1,1]], δ = 1 ⇒ WᵀW + I = [[3,1],[1,3]],
    // det = 8 ⇒ logdet = ln 8; (WᵀW + I)⁻¹ = (1/8)·[[3,−1],[−1,3]].
    // ------------------------------------------------------------------
    #[test]
    fn golden_volume_logdet_and_gram_inverse() {
        let w = [1.0, 0.0, 0.0, 1.0, 1.0, 1.0];
        let (m, k) = (3usize, 2usize);
        let lg = logdet_gram(&w, m, k, 1.0).unwrap();
        assert!((lg - 8.0f64.ln()).abs() < 1e-12, "logdet = {lg}");
        let y = gram_inverse(&w, m, k, 1.0).unwrap();
        let want = [3.0 / 8.0, -1.0 / 8.0, -1.0 / 8.0, 3.0 / 8.0];
        for (got, exp) in y.iter().zip(want) {
            assert!((got - exp).abs() < 1e-12, "Y = {y:?}");
        }
        // δ raises the logdet of a collapsed dictionary: WᵀW + 4I =
        // [[6,1],[1,6]], det = 36 − 1 = 35.
        let lg2 = logdet_gram(&w, m, k, 4.0).unwrap();
        assert!((lg2 - 35.0f64.ln()).abs() < 1e-12);
    }

    // ------------------------------------------------------------------
    // Golden (hand-derived, k = 1): the volume W proposal root.
    // W0 = [[1/2],[1/2]], H0 = [[1,1]], V = 2·W0H0 = ones·1, λ = δ = 1.
    // Y = 1/(Σw² + δ) = 2/3; wy_minus = 0; wy_abs = 1/3; R = 2;
    // K = (V⊘WH)·Hᵀ = 2·(1+1) = 4. num = √(4 + 8·(1/3)·4) − 2 = √(44/3) − 2;
    // den = 4/3; proposal = (1/2)·(√(44/3) − 2)/(4/3).
    // ------------------------------------------------------------------
    #[test]
    fn golden_volume_w_proposal_k1() {
        let v = [1.0, 1.0, 1.0, 1.0];
        let (m, n, k) = (2usize, 2usize, 1usize);
        let w = [0.5, 0.5];
        let h = [1.0, 1.0];
        let got = volume_w_proposal(&v, &w, &h, m, n, k, 1.0, 1.0).unwrap();
        let want = 0.5 * ((44.0f64 / 3.0).sqrt() - 2.0) / (4.0f64 / 3.0);
        assert!((got[0] - want).abs() < 1e-12, "proposal = {:?}", got);
        assert!((got[1] - want).abs() < 1e-12);
    }

    // ------------------------------------------------------------------
    // Regression anchor: the L1L1 mode at λ = μ = 0 IS the audited KL
    // kernel — bit-identical fit, including the objective trace (tol = 0
    // disables early stopping, matching fit_kl's fixed-iteration
    // semantics).
    // ------------------------------------------------------------------
    #[test]
    fn l1_lambda_mu_zero_equals_fit_kl_bitwise() {
        let mut rng = MsRng::from_stream(5, StreamId { replicate: 8, rank: 8, fold: 8 });
        let v: Vec<f64> = (0..20 * 14).map(|_| (uniform(&mut rng) * 40.0).floor()).collect();
        for (seed, iters) in [(0u64, 30usize), (42, 25), (0xDEAD_BEEF, 40)] {
            let a = fit_sparse_l1(&v, 20, 14, 3, 0.0, 0.0, iters, 0.0, seed).unwrap();
            let b = fit_kl(&v, 20, 14, 3, iters, seed).unwrap();
            assert_eq!(a.w, b.w, "seed {seed}");
            assert_eq!(a.h, b.h, "seed {seed}");
            assert_eq!(a.objective, b.objective, "seed {seed}");
        }
        // The volume mode's λ = 0 path (plain KL W proposal) stays finite.
        let c = fit_volume(&v, 20, 14, 3, 0.0, 1.0, 5, 0.0, 42).unwrap();
        assert!(c.w.iter().all(|x| x.is_finite() && *x > 0.0));
    }

    // ------------------------------------------------------------------
    // No-drift contracts on the two fallback/reuse paths.
    // ------------------------------------------------------------------
    #[test]
    fn zero_penalty_steps_match_kl_kernel_bitwise() {
        let mut rng = MsRng::from_stream(11, StreamId { replicate: 5, rank: 5, fold: 5 });
        let (m, n, k) = (7usize, 5usize, 3usize);
        let v: Vec<f64> = (0..m * n).map(|_| (uniform(&mut rng) * 20.0).floor()).collect();
        let w: Vec<f64> = (0..m * k).map(|_| 0.1 + uniform(&mut rng)).collect();
        let h: Vec<f64> = (0..k * n).map(|_| 0.1 + uniform(&mut rng)).collect();

        // l1_h_step at λ = 0 vs kl_h_step.
        let mut h_l1 = h.clone();
        l1_h_step(&v, &w, &mut h_l1, m, n, k, 0.0);
        let mut h_kl = h.clone();
        kl_h_step(&v, &w, &mut h_kl, m, n, k);
        assert_eq!(h_l1, h_kl, "L1 H step drifted from kl_h_step at λ = 0");

        // l1_w_step at μ = 0 vs kl_w_step.
        let mut w_l1 = w.clone();
        l1_w_step(&v, &mut w_l1, &h, m, n, k, 0.0);
        let mut w_kl = w.clone();
        kl_w_step(&v, &mut w_kl, &h, m, n, k);
        assert_eq!(w_l1, w_kl, "L1 W step drifted from kl_w_step at μ = 0");

        // volume W proposal at λ = 0 vs kl_w_step.
        let w_unc = volume_w_proposal(&v, &w, &h, m, n, k, 0.0, 1.0).unwrap();
        let mut w_kl2 = w.clone();
        kl_w_step(&v, &mut w_kl2, &h, m, n, k);
        assert_eq!(w_unc, w_kl2, "volume proposal drifted from kl_w_step at λ = 0");
    }

    // ------------------------------------------------------------------
    // Volume-mode separable recovery: k = 3 truth recovered (cosine ≥ 0.99
    // per matched column), unit-sum signature columns (upstream geometry),
    // monotone penalized trace within slack (line-search contract).
    // ------------------------------------------------------------------
    #[test]
    fn volume_separable_recovery() {
        let (v, w_true, _h_true) = separable_truth(0xBEEF);
        let (m, n, k) = (96usize, 20usize, 3usize);
        let fit = fit_volume(&v, m, n, k, 1.0, 1.0, 600, 0.0, 42).unwrap();
        assert_monotone(&fit.objective);
        let wh = matmul(&fit.w, &fit.h, m, n, k);
        let recon = cosine(&v, &wh);
        assert!(recon >= 0.999, "reconstruction cosine {recon}");
        for s in 0..k {
            let col = column(&fit.w, m, k, s);
            let sum: f64 = col.iter().sum();
            assert!((sum - 1.0).abs() < 1e-9, "volume W column {s} not unit-sum: {sum}");
        }
        let true_cols: Vec<Vec<f64>> = (0..k).map(|s| column(&w_true, m, k, s)).collect();
        let fitted_cols: Vec<Vec<f64>> = (0..k).map(|s| column(&fit.w, m, k, s)).collect();
        for c in greedy_match(&fitted_cols, &true_cols) {
            assert!(c >= 0.99, "matched W column cosine {c}");
        }
    }

    // ------------------------------------------------------------------
    // Minimum-volume mechanism: on data built from two near-parallel
    // signatures (the regime where plain NMF rotations are unidentifiable),
    // the volume term engages: the λ > 0 fit ends at a smaller simplex
    // volume log det(WᵀW + δI) — with δ matched to the unit-sum Gram scale —
    // while the data fit does not degrade (both reconstruct ≥ 0.999).
    // ------------------------------------------------------------------
    #[test]
    fn volume_minimum_volume_engages() {
        let (m, n, k) = (96usize, 16usize, 2usize);
        let mut rng = MsRng::from_stream(0xC0111A, StreamId { replicate: 6, rank: 6, fold: 6 });
        // Two near-parallel signatures (cosine ≈ 0.999) plus dense mixed
        // exposures.
        let base: Vec<f64> = (0..m).map(|_| 1.0 + uniform(&mut rng)).collect();
        let tilt: Vec<f64> = (0..m).map(|_| 1.0 + 0.02 * uniform(&mut rng)).collect();
        let bsum: f64 = base.iter().sum();
        let tsum: f64 = tilt.iter().sum();
        let mut w_true = vec![0.0f64; m * k];
        for i in 0..m {
            w_true[i * k] = base[i] / bsum;
            w_true[i * k + 1] = tilt[i] / tsum;
        }
        let h: Vec<f64> = (0..k * n).map(|_| 200.0 + 400.0 * uniform(&mut rng)).collect();
        let v = matmul(&w_true, &h, m, n, k);

        // Unit-sum 96-channel columns have a Gram diagonal of order 0.03,
        // so δ is matched to that scale (δ = 1 would swamp WᵀW entirely).
        let delta = 0.03;
        let lambda = 10.0;
        let fit0 = fit_volume(&v, m, n, k, 0.0, delta, 400, 0.0, 42).unwrap();
        let fit1 = fit_volume(&v, m, n, k, lambda, delta, 400, 0.0, 42).unwrap();
        let lg0 = logdet_gram(&fit0.w, m, k, delta).unwrap();
        let lg1 = logdet_gram(&fit1.w, m, k, delta).unwrap();
        assert!(lg1 < lg0, "volume term did not shrink the simplex: {lg1} ≥ {lg0}");
        for fit in [&fit0, &fit1] {
            let wh = matmul(&fit.w, &fit.h, m, n, k);
            let recon = cosine(&v, &wh);
            assert!(recon >= 0.999, "reconstruction cosine {recon}");
        }
    }

    // ------------------------------------------------------------------
    // L1L1 λ sweep (μ = 1 calibrated to this catalog's scale, per the
    // module docs' regime note): the truth carries one genuinely weak
    // component (10× less exposure mass). As λ grows, the exposure mass
    // concentrates: the weak component's share collapses to zero (its
    // entries fall below 1e-3 of the global H max), the fraction of
    // sub-threshold entries rises, and the penalized trace stays
    // MM-monotone throughout.
    // ------------------------------------------------------------------
    #[test]
    fn l1_lambda_sweep_sparsity_increases() {
        let (m, n, k) = (48usize, 24usize, 3usize);
        let mut rng = MsRng::from_stream(0x5BA4, StreamId { replicate: 7, rank: 7, fold: 7 });
        let mut w_true = vec![0.0f64; m * k];
        for s in 0..k {
            let mut col: Vec<f64> = (0..m)
                .map(|i| if i / 16 == s { 1.0 + uniform(&mut rng) } else { 0.0 })
                .collect();
            let sum: f64 = col.iter().sum();
            for x in col.iter_mut() {
                *x /= sum;
            }
            for i in 0..m {
                w_true[i * k + s] = col[i];
            }
        }
        // Component 2 is genuinely weak: 10× less exposure mass.
        let mut h_true = vec![0.0f64; k * n];
        for j in 0..n {
            let primary = j % 2;
            h_true[primary * n + j] = 300.0 + 300.0 * uniform(&mut rng);
            h_true[2 * n + j] = 30.0 * uniform(&mut rng);
        }
        let v = matmul(&w_true, &h_true, m, n, k);

        let lambdas = [0.0f64, 100.0, 1000.0];
        let mut sparsity = Vec::new();
        let mut weak_share = Vec::new();
        for &lam in &lambdas {
            let fit = fit_sparse_l1(&v, m, n, k, lam, 1.0, 4000, 0.0, 42).unwrap();
            assert_monotone(&fit.objective);
            let hmax = fit.h.iter().cloned().fold(0.0f64, f64::max);
            let count = fit.h.iter().filter(|&&x| x < 1e-3 * hmax).count();
            sparsity.push(count as f64 / (k * n) as f64);
            let weak: f64 = (0..n).map(|j| fit.h[2 * n + j]).sum();
            let total: f64 = fit.h.iter().sum();
            weak_share.push(weak / total);
        }
        for t in 1..sparsity.len() {
            assert!(
                sparsity[t] >= sparsity[t - 1],
                "sparsity not monotone in λ: {sparsity:?}"
            );
            assert!(
                weak_share[t] <= weak_share[t - 1],
                "weak-component share not monotone in λ: {weak_share:?}"
            );
        }
        assert!(
            sparsity[sparsity.len() - 1] > sparsity[0],
            "largest λ did not sparsify: {sparsity:?}"
        );
        assert!(
            weak_share[weak_share.len() - 1] < 0.01 * weak_share[0],
            "weak component not suppressed: {weak_share:?}"
        );
    }

    // ------------------------------------------------------------------
    // Determinism and bookkeeping.
    // ------------------------------------------------------------------
    #[test]
    fn sparse_fits_are_bit_identical_across_runs() {
        let mut rng = MsRng::from_stream(5, StreamId { replicate: 8, rank: 8, fold: 8 });
        let v: Vec<f64> = (0..20 * 14).map(|_| (uniform(&mut rng) * 40.0).floor()).collect();
        let a = fit_sparse_l1(&v, 20, 14, 3, 1.0, 1.0, 30, 0.0, 42).unwrap();
        let b = fit_sparse_l1(&v, 20, 14, 3, 1.0, 1.0, 30, 0.0, 42).unwrap();
        assert_eq!(a, b);
        let c = fit_volume(&v, 20, 14, 3, 1.0, 1.0, 20, 0.0, 42).unwrap();
        let d = fit_volume(&v, 20, 14, 3, 1.0, 1.0, 20, 0.0, 42).unwrap();
        assert_eq!(c, d);
    }

    #[test]
    fn sparse_zero_iterations_returns_initializer() {
        let v = [2.0, 0.0, 0.0, 4.0];
        let w0 = [1.0, 2.0];
        let h0 = [0.5, 0.5];
        let l1 = fit_sparse_l1_with_init(&v, 2, 2, 1, 0.5, 0.5, &w0, &h0, 0, 0.0).unwrap();
        assert_eq!(l1.w, w0.to_vec());
        assert_eq!(l1.h, h0.to_vec());
        assert_eq!(l1.iterations, 0);
        assert_eq!(l1.objective.len(), 1);
        assert!(!l1.converged);
        let vol = fit_volume_with_init(&v, 2, 2, 1, 1.0, 1.0, &w0, &h0, 0, 0.0).unwrap();
        assert_eq!(vol.w, w0.to_vec());
        assert_eq!(vol.objective.len(), 1);
    }

    // ------------------------------------------------------------------
    // Validation error paths.
    // ------------------------------------------------------------------
    #[test]
    fn sparse_validation_errors() {
        let v = [1.0, 2.0, 3.0, 4.0];
        let w0 = [1.0, 1.0, 1.0, 1.0];
        // Negative / NaN λ or μ.
        assert_eq!(
            fit_sparse_l1(&v, 2, 2, 1, -1.0, 0.0, 1, 0.0, 0).unwrap_err().topic(),
            "argument"
        );
        assert_eq!(
            fit_sparse_l1(&v, 2, 2, 1, f64::NAN, 0.0, 1, 0.0, 0).unwrap_err().topic(),
            "argument"
        );
        assert_eq!(
            fit_sparse_l1(&v, 2, 2, 1, 0.0, -1.0, 1, 0.0, 0).unwrap_err().topic(),
            "argument"
        );
        assert_eq!(
            fit_sparse_l1(&v, 2, 2, 1, 0.0, f64::NAN, 1, 0.0, 0).unwrap_err().topic(),
            "argument"
        );
        assert_eq!(
            fit_volume(&v, 2, 2, 1, -0.5, 1.0, 1, 0.0, 0).unwrap_err().topic(),
            "argument"
        );
        // Negative / zero / NaN δ (volume only).
        for d in [0.0, -1.0, f64::NAN] {
            assert_eq!(fit_volume(&v, 2, 2, 1, 1.0, d, 1, 0.0, 0).unwrap_err().topic(), "argument");
        }
        // k = 0 and storage mismatch (h0 must be k·n = 4 for k = 2).
        assert_eq!(
            fit_sparse_l1(&v, 2, 2, 0, 1.0, 1.0, 1, 0.0, 0).unwrap_err().topic(),
            "argument"
        );
        assert_eq!(
            fit_volume_with_init(&v, 2, 2, 2, 1.0, 1.0, &w0, &[1.0, 1.0], 1, 0.0)
                .unwrap_err()
                .topic(),
            "argument"
        );
        // Negative tolerance.
        assert_eq!(
            fit_sparse_l1(&v, 2, 2, 1, 1.0, 1.0, 1, -1.0, 0).unwrap_err().topic(),
            "argument"
        );
        // Negative / NaN counts, 1-based indices attached.
        let err = fit_sparse_l1(&[1.0, -2.0, 3.0, 4.0], 2, 2, 1, 1.0, 1.0, 1, 0.0, 0).unwrap_err();
        assert_eq!(err.topic(), "argument");
        let err = fit_volume(&[1.0, f64::NAN, 3.0, 4.0], 2, 2, 1, 1.0, 1.0, 1, 0.0, 0).unwrap_err();
        assert_eq!(err.topic(), "na");
        assert_eq!(err.i, Some(1));
        assert_eq!(err.j, Some(2));
    }
}
