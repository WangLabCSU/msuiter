//! Lawson–Hanson active-set NNLS on the precomputed Gram matrix
//! (U-M1s-01; `docs/ARCHITECTURE.md` §2 `engine/nnls.rs`).
//!
//! # Interface: the K-format
//!
//! [`nnls_gram`] takes `G = AᵀA` (symmetric PSD, row-major `n×n`) and
//! `b = Aᵀy` instead of the design matrix `A`. This is the common interface
//! for the KL/MM inner loop and per-sample exposure fitting: callers never
//! retain `A`, and one inner iteration costs `O(n²)` instead of `O(mn)` for
//! `m` channels. It solves
//!
//! ```text
//! minimize ½ xᵀGx − bᵀx   subject to   x ≥ 0
//! ```
//!
//! i.e. `argmin ‖Ax − y‖₂` for `x ≥ 0`, and returns the non-negative
//! solution together with its KKT diagnostics.
//!
//! # Algorithm
//!
//! Classic Lawson–Hanson (1974) active-set loop: passive set `P` (positive
//! coefficients), steepest-ascent column selection on the negative gradient
//! `w = b − Gx`, equality-constrained solve on `P`, and a feasible-direction
//! truncation step `α = min x_i/(x_i − z_i)` whenever the new solution
//! leaves the non-negative orthant, dropping the zeroed variables. The
//! subproblem `G_PP z = b_P` is solved by pivoted Bunch–Kaufman LDLᵀ +
//! ε‖G‖ ridge ([`crate::linalg`]); no inverse is ever formed.
//!
//! # Numerical hygiene (ARCH §2 contract)
//!
//! * **Diagonal scaling**: internally the problem is solved in correlation
//!   form `G̃ = D G D`, `b̃ = D b` with `D = diag(1/√G_kk)` — unit diagonal,
//!   scale-free pivots and tolerances, and the objective `½xᵀGx − bᵀx` is
//!   invariant under the transform.
//! * **Zero-variance columns**: `G_kk = 0` means the column (hence
//!   `b_k = a_kᵀy`, by Cauchy–Schwarz on consistent input) carries no
//!   information. Such columns are *dead*: never selected, always returned
//!   as exactly 0, and excluded from the KKT check (their coefficient is
//!   unidentified but prediction-irrelevant). A *negative* diagonal is
//!   rejected as a non-PSD input (`"argument"`).
//! * **ε‖G‖ ridge** (default [`crate::linalg::GRAM_RIDGE_EPS`]) keeps the
//!   passive-set solves well-posed under duplicate/parallel signatures and
//!   makes the regularized objective strictly convex (unique minimizer).
//! * **Iteration cap**: total inner (refactorizing) iterations are bounded;
//!   exhaustion returns an `"iterations"` error rather than cycling.
//! * **KKT assertion** (configurable, on by default): the returned point
//!   must satisfy `|(Gx − b)_i| ≤ tol` on the passive set and
//!   `(Gx − b)_j ≥ −tol` off it, with
//!   `tol = kkt_tol_factor · max_k G_kk · (1 + max|x|)` — the natural
//!   backward-error scale of the gradient (roundoff in forming and solving
//!   the system is `O(u · ‖G‖‖x‖)`). Violation returns a `"kkt"` error.
//!
//! # Determinism
//!
//! Fixed loop order, first-index tie-breaking, no hashing: equal inputs
//! produce bit-identical output regardless of thread count (ARCH §2.6).

use crate::error::MsError;
use crate::linalg::{gram_scale, Ldlt, GRAM_RIDGE_EPS};

/// Solver options; see the module docs for the semantics of each field.
#[derive(Debug, Clone, PartialEq)]
pub struct NnlsOptions {
    /// Relative ε‖G‖ ridge applied to passive-set solves. `None` disables
    /// it (then a singular passive set surfaces as an `"singular"` error).
    pub ridge_eps: Option<f64>,
    /// Assert the KKT conditions at the returned solution (default on).
    pub assert_kkt: bool,
    /// Relative KKT tolerance factor (see module docs); default 1e-8.
    pub kkt_tol_factor: f64,
    /// Relative gradient-selection tolerance factor; a free column enters
    /// the passive set only while `w_j > select_tol_factor · max(1, ‖b̃‖∞)`
    /// (normalized space). Default 1e-11.
    pub select_tol_factor: f64,
    /// Hard cap on total inner (refactorizing) iterations; `None` derives
    /// `10·n + 100`.
    pub max_iter: Option<usize>,
}

impl Default for NnlsOptions {
    fn default() -> Self {
        Self {
            ridge_eps: Some(GRAM_RIDGE_EPS),
            assert_kkt: true,
            kkt_tol_factor: 1e-8,
            select_tol_factor: 1e-11,
            max_iter: None,
        }
    }
}

/// Outcome of [`nnls_gram`].
#[derive(Debug, Clone, PartialEq)]
pub struct NnlsSolution {
    /// Non-negative minimizer (dead columns exactly 0.0).
    pub x: Vec<f64>,
    /// Sorted original indices of the passive (positive-coefficient) set.
    pub passive: Vec<usize>,
    /// Max KKT violation at the solution (see module docs for the norm).
    pub kkt_residual: f64,
    /// KKT tolerance the residual was asserted against.
    pub kkt_tol: f64,
    /// Objective ½xᵀGx − bᵀx at the solution (raw coordinates).
    pub objective: f64,
    /// Objective at the running iterate after each outer iteration
    /// (`trace[0]` is the objective at `x = 0`, i.e. 0.0). Monotone
    /// non-increasing up to roundoff — a main-loop invariant.
    pub objective_trace: Vec<f64>,
    /// Total inner iterations (passive-set refactorizations) performed.
    pub iterations: usize,
    /// Number of feasible-direction truncation steps taken.
    pub truncations: usize,
    /// Effective relative ridge actually applied (0.0 when disabled).
    pub ridge_eps: f64,
}

// Gradient of ½xᵀGx − bᵀx in raw coordinates.
fn raw_gradient(g: &[f64], b: &[f64], x: &[f64], n: usize) -> Vec<f64> {
    (0..n)
        .map(|i| (0..n).map(|j| g[i * n + j] * x[j]).sum::<f64>() - b[i])
        .collect()
}

/// Objective ½xᵀGx − bᵀx (any coordinates consistent with the matrix pair).
fn quadratic_objective(g: &[f64], b: &[f64], x: &[f64], n: usize) -> f64 {
    let mut quad = 0.0f64;
    for i in 0..n {
        for j in 0..n {
            quad += x[i] * g[i * n + j] * x[j];
        }
    }
    0.5 * quad - (0..n).map(|i| b[i] * x[i]).sum::<f64>()
}

fn max_abs(v: &[f64]) -> f64 {
    v.iter().fold(0.0f64, |m, &x| m.max(x.abs()))
}

/// Solve NNLS on the precomputed Gram pair `(G, b)`; see the module docs.
pub fn nnls_gram(
    g: &[f64],
    b: &[f64],
    n: usize,
    opts: &NnlsOptions,
) -> Result<NnlsSolution, MsError> {
    // --- input validation (FFI contract 3/4 style: structured errors) ---
    if g.len() != n * n {
        return Err(
            MsError::new("argument", "Gram matrix storage must be n*n elements")
                .with_i(g.len() as i64),
        );
    }
    if b.len() != n {
        return Err(
            MsError::new("argument", "right-hand side length must equal n").with_i(b.len() as i64),
        );
    }
    for (idx, &v) in g.iter().enumerate() {
        if !v.is_finite() {
            return Err(MsError::new("na", "non-finite entry in Gram matrix")
                .with_i((idx / n + 1) as i64)
                .with_j((idx % n + 1) as i64));
        }
    }
    for (idx, &v) in b.iter().enumerate() {
        if !v.is_finite() {
            return Err(
                MsError::new("na", "non-finite entry in right-hand side").with_i(idx as i64 + 1)
            );
        }
    }
    for i in 0..n {
        if g[i * n + i] < 0.0 {
            return Err(MsError::new(
                "argument",
                "Gram matrix diagonal must be non-negative (PSD precondition)",
            )
            .with_i(i as i64 + 1));
        }
    }

    let ridge_eps = opts.ridge_eps.unwrap_or(0.0);
    if n == 0 {
        return Ok(NnlsSolution {
            x: Vec::new(),
            passive: Vec::new(),
            kkt_residual: 0.0,
            kkt_tol: 0.0,
            objective: 0.0,
            objective_trace: vec![0.0],
            iterations: 0,
            truncations: 0,
            ridge_eps,
        });
    }

    // --- diagonal scaling to correlation form (unit diagonal) ---
    // Zero-diagonal columns are dead: never selected, exactly 0 output,
    // excluded from the KKT check (their coefficient is unidentified but
    // prediction-irrelevant; on consistent input b_k = a_kᵀy = 0 too).
    let mut dnorm = vec![0.0f64; n];
    let mut dead = vec![false; n];
    for i in 0..n {
        let gii = g[i * n + i];
        if gii > 0.0 {
            dnorm[i] = gii.sqrt();
        } else {
            dead[i] = true;
        }
    }
    let mut gn = vec![0.0f64; n * n];
    for i in 0..n {
        if dead[i] {
            continue;
        }
        for j in 0..n {
            if !dead[j] {
                gn[i * n + j] = g[i * n + j] / (dnorm[i] * dnorm[j]);
            }
        }
    }
    let bn: Vec<f64> = (0..n)
        .map(|i| if dead[i] { 0.0 } else { b[i] / dnorm[i] })
        .collect();
    // Selection tolerance in the normalized space (‖G̃‖∞-diagonal = 1).
    let b_scale = bn.iter().fold(0.0f64, |m, &v| m.max(v.abs()));
    let select_tol = opts.select_tol_factor * b_scale.max(1.0);

    // --- Lawson–Hanson active-set main loop (normalized space) ---
    let mut x = vec![0.0f64; n];
    let mut in_p = vec![false; n];
    let mut w = bn.clone();
    let mut iterations = 0usize;
    let mut truncations = 0usize;
    // trace[0] = objective at x = 0, i.e. 0.
    let mut trace = vec![0.0f64];
    let max_iter = opts.max_iter.unwrap_or(10 * n + 100);

    loop {
        // Steepest-descent column selection among free, live columns
        // (first index wins ties — fixed, deterministic rule).
        let mut best = None;
        let mut wmax = select_tol;
        for j in 0..n {
            if !in_p[j] && !dead[j] && w[j] > wmax {
                wmax = w[j];
                best = Some(j);
            }
        }
        let Some(j0) = best else { break };
        in_p[j0] = true;

        // Inner loop: equality-constrained solve on P, feasible-direction
        // truncation, boundary removals. Each pass refactorizes (no formed
        // inverse); the total is capped to rule out cycling.
        loop {
            iterations += 1;
            if iterations > max_iter {
                return Err(MsError::new(
                    "iterations",
                    "NNLS active-set loop exceeded its iteration cap",
                )
                .with_i(max_iter as i64));
            }
            let idx: Vec<usize> = (0..n).filter(|&j| in_p[j]).collect();
            let m = idx.len();
            let mut gp = vec![0.0f64; m * m];
            for (ii, &i) in idx.iter().enumerate() {
                for (jj, &j) in idx.iter().enumerate() {
                    gp[ii * m + jj] = gn[i * n + j];
                }
                gp[ii * m + ii] += ridge_eps; // ε‖G̃‖ on the unit diagonal
            }
            let rhs: Vec<f64> = idx.iter().map(|&i| bn[i]).collect();
            let z = Ldlt::factor(&gp, m).and_then(|f| f.solve(&rhs))?;

            if z.iter().all(|&v| v >= 0.0) {
                for (s, &i) in idx.iter().enumerate() {
                    x[i] = z[s];
                }
                break;
            }

            // Feasible-direction truncation: move from x toward z only as
            // far as the non-negative orthant allows. α < 1 guarantees at
            // least one coefficient hits exactly 0 (and α = 0 degenerates
            // to removing an already-zero coefficient), so P shrinks every
            // pass and the subset lattice makes progress.
            truncations += 1;
            let mut alpha = 1.0f64;
            for (s, &i) in idx.iter().enumerate() {
                if z[s] <= 0.0 {
                    let denom = x[i] - z[s];
                    if denom > 0.0 {
                        alpha = alpha.min(x[i] / denom);
                    }
                }
            }
            for (s, &i) in idx.iter().enumerate() {
                x[i] += alpha * (z[s] - x[i]);
            }
            for &i in idx.iter() {
                if x[i] <= 0.0 {
                    x[i] = 0.0;
                    in_p[i] = false;
                }
            }
        }

        // Refresh the gradient and record the running objective. The
        // objective ½xᵀGx − bᵀx is invariant under the diagonal scaling,
        // so the trace is in raw-space units.
        for i in 0..n {
            let mut acc = bn[i];
            for j in 0..n {
                acc -= gn[i * n + j] * x[j];
            }
            w[i] = acc;
        }
        trace.push(quadratic_objective(&gn, &bn, &x, n));
    }

    // --- de-scale and evaluate on the raw problem ---
    let xs: Vec<f64> = (0..n)
        .map(|i| if dead[i] { 0.0 } else { x[i] / dnorm[i] })
        .collect();
    let passive: Vec<usize> = (0..n).filter(|&j| in_p[j]).collect();

    let grad = raw_gradient(g, b, &xs, n);
    let mut kkt_residual = 0.0f64;
    let mut worst = 0usize;
    for i in 0..n {
        if dead[i] {
            continue;
        }
        let v = if in_p[i] {
            grad[i].abs()
        } else {
            (-grad[i]).max(0.0)
        };
        if v > kkt_residual {
            kkt_residual = v;
            worst = i;
        }
    }
    // Backward-error scale of the gradient: roundoff is O(u·‖G‖‖x‖), so the
    // assertion threshold grows with ‖x‖ (matters for ill-conditioned Grams).
    let kkt_tol = opts.kkt_tol_factor * gram_scale(g, n) * (1.0 + max_abs(&xs));
    if opts.assert_kkt && kkt_residual > kkt_tol {
        return Err(MsError::new(
            "kkt",
            "NNLS solution violates the KKT conditions beyond tolerance",
        )
        .with_i(worst as i64 + 1));
    }

    let objective_raw = quadratic_objective(g, b, &xs, n);
    Ok(NnlsSolution {
        objective: objective_raw,
        x: xs,
        passive,
        kkt_residual,
        kkt_tol,
        objective_trace: trace,
        iterations,
        truncations,
        ridge_eps,
    })
}

// ======================================================================
// Tests (authored first, TDD): goldens, degenerate inputs, brute-force
// enumeration cross-check, ill-conditioned Grams, invariants. Fixed
// seeds only, via the in-house MsRng + StreamId layout (module
// composition check, ARCH §9).
// ======================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rng::{MsRng, StreamId};

    /// Uniform f64 in [0, 1).
    fn uniform(rng: &mut MsRng) -> f64 {
        ((rng.next_u64() >> 11) as f64) * (1.0 / (1u64 << 53) as f64)
    }

    fn max_abs(v: &[f64]) -> f64 {
        v.iter().fold(0.0f64, |m, &x| m.max(x.abs()))
    }

    /// Raw objective ½xᵀGx − bᵀx.
    fn objective(g: &[f64], b: &[f64], x: &[f64], n: usize) -> f64 {
        let mut quad = 0.0;
        for i in 0..n {
            for j in 0..n {
                quad += x[i] * g[i * n + j] * x[j];
            }
        }
        let lin: f64 = (0..n).map(|i| b[i] * x[i]).sum();
        0.5 * quad - lin
    }

    fn matvec(a: &[f64], x: &[f64], n: usize) -> Vec<f64> {
        (0..n)
            .map(|i| (0..n).map(|j| a[i * n + j] * x[j]).sum())
            .collect()
    }

    fn cosine(a: &[f64], b: &[f64]) -> f64 {
        let dot: f64 = a.iter().zip(b.iter()).map(|(&p, &q)| p * q).sum();
        let na = a.iter().map(|v| v * v).sum::<f64>().sqrt();
        let nb = b.iter().map(|v| v * v).sum::<f64>().sqrt();
        dot / (na * nb)
    }

    /// Brute-force reference: enumerate every active set, solve the
    /// equality-constrained subproblem in the same normalized coordinates
    /// and with the same relative ridge as `nnls_gram`, keep the feasible
    /// (non-negative) candidate with the lowest regularized objective.
    /// Returns `(x, ridged objective, true objective)`.
    ///
    /// With a strictly convex (ridged) objective the minimizer is unique,
    /// so this is an exact reference for the active-set loop.
    fn brute_force_nnls(
        g: &[f64],
        b: &[f64],
        n: usize,
        ridge_eps: Option<f64>,
    ) -> (Vec<f64>, f64, f64) {
        // Same normalization as the kernel: D = diag(1/√G_kk); test inputs
        // always have strictly positive diagonals (asserted below).
        let d: Vec<f64> = (0..n).map(|i| g[i * n + i].sqrt()).collect();
        assert!(
            d.iter().all(|&v| v > 0.0),
            "brute-force helper needs live columns"
        );
        let mut gn = vec![0.0f64; n * n];
        for i in 0..n {
            for j in 0..n {
                gn[i * n + j] = g[i * n + j] / (d[i] * d[j]);
            }
        }
        let bn: Vec<f64> = (0..n).map(|i| b[i] / d[i]).collect();
        let eps = ridge_eps.unwrap_or(0.0);

        let mut best_x = vec![0.0f64; n];
        let mut best_f = 0.0f64; // at x = 0 the (ridged) objective is 0
        let mut have = true;
        for mask in 0..(1usize << n) {
            let idx: Vec<usize> = (0..n).filter(|&j| mask & (1 << j) != 0).collect();
            let m = idx.len();
            let (z, feasible): (Vec<f64>, bool) = if m == 0 {
                (Vec::new(), true)
            } else {
                let mut gp = vec![0.0f64; m * m];
                for (ii, &i) in idx.iter().enumerate() {
                    for (jj, &j) in idx.iter().enumerate() {
                        gp[ii * m + jj] = gn[i * n + j];
                    }
                    gp[ii * m + ii] += eps;
                }
                let rhs: Vec<f64> = idx.iter().map(|&i| bn[i]).collect();
                match Ldlt::factor(&gp, m).and_then(|f| f.solve(&rhs)) {
                    Ok(z) => {
                        let feasible = z.iter().all(|&v| v >= 0.0);
                        (z, feasible)
                    }
                    Err(_) => (Vec::new(), false), // singular subset: skip
                }
            };
            if !feasible {
                continue;
            }
            let mut xn = vec![0.0f64; n];
            for (s, &i) in idx.iter().enumerate() {
                xn[i] = z[s];
            }
            // Regularized objective on the normalized problem.
            let mut quad = 0.0;
            for i in 0..n {
                for j in 0..n {
                    let mut gij = gn[i * n + j];
                    if i == j {
                        gij += eps;
                    }
                    quad += xn[i] * gij * xn[j];
                }
            }
            let lin: f64 = (0..n).map(|i| bn[i] * xn[i]).sum();
            let f = 0.5 * quad - lin;
            if !have || f < best_f {
                have = true;
                best_f = f;
                best_x = xn;
            }
        }
        // De-scale to raw coordinates and compute the raw objective there.
        let x: Vec<f64> = (0..n).map(|i| best_x[i] / d[i]).collect();
        let f_true = objective(g, b, &x, n);
        (x, best_f, f_true)
    }

    /// Random test problem: column-normalized random A (m×n), G = AᵀA,
    /// b = Aᵀy with y ∈ [0, 2]^m. Deterministic per `(master, stream)`.
    fn random_problem(master: u64, stream: StreamId, n: usize, m: usize) -> (Vec<f64>, Vec<f64>) {
        let mut rng = MsRng::from_stream(master, stream);
        let mut a = vec![0.0f64; m * n];
        for j in 0..n {
            let mut col: Vec<f64> = (0..m).map(|_| 2.0 * uniform(&mut rng) - 1.0).collect();
            let norm = col.iter().map(|v| v * v).sum::<f64>().sqrt();
            for v in col.iter_mut() {
                *v /= norm;
            }
            for i in 0..m {
                a[i * n + j] = col[i];
            }
        }
        let y: Vec<f64> = (0..m).map(|_| 2.0 * uniform(&mut rng)).collect();
        let mut g = vec![0.0f64; n * n];
        for i in 0..n {
            for j in 0..n {
                g[i * n + j] = (0..m).map(|r| a[r * n + i] * a[r * n + j]).sum();
            }
        }
        // b = Aᵀy (transpose product: sum over the m rows per column).
        let b: Vec<f64> = (0..n)
            .map(|j| (0..m).map(|r| a[r * n + j] * y[r]).sum())
            .collect();
        (g, b)
    }

    /// Shared invariant checks for one random case: non-negativity, KKT,
    /// monotone trace, brute-force agreement, determinism.
    fn assert_invariants(g: &[f64], b: &[f64], n: usize, opts: &NnlsOptions) -> NnlsSolution {
        let sol = nnls_gram(g, b, n, opts).unwrap();
        // (a) feasibility, exactly.
        assert!(
            sol.x.iter().all(|&v| v >= 0.0),
            "negative component: {:?}",
            sol.x
        );
        // (b) KKT residual within the documented tolerance.
        let scale = gram_scale(g, n);
        let tol = opts.kkt_tol_factor * scale * (1.0 + max_abs(&sol.x));
        assert!(
            sol.kkt_residual <= sol.kkt_tol && sol.kkt_tol <= tol * (1.0 + 1e-12),
            "kkt residual {} > tol {}",
            sol.kkt_residual,
            sol.kkt_tol
        );
        // (c) trace[0] = 0 and non-increasing (objective at x = 0 is 0; the
        // objective is invariant under the internal diagonal scaling).
        assert_eq!(sol.objective_trace[0], 0.0);
        let slack = 1e-9 * (1.0 + sol.objective.abs());
        for w in sol.objective_trace.windows(2) {
            assert!(
                w[1] <= w[0] + slack,
                "trace increased: {:?}",
                sol.objective_trace
            );
        }
        // (d) brute-force agreement (unique ridged minimizer), 1e-10
        // relative per component.
        let (xbf, _fr, f_true_bf) = brute_force_nnls(g, b, n, opts.ridge_eps);
        for (i, (&xv, &xb)) in sol.x.iter().zip(xbf.iter()).enumerate() {
            let d = (xv - xb).abs();
            assert!(
                d <= 1e-10 * (1.0 + xb.abs()),
                "component {i}: {xv} vs brute {xb}"
            );
        }
        let f_true = objective(g, b, &sol.x, n);
        assert!((f_true - f_true_bf).abs() <= 1e-10 * (1.0 + f_true_bf.abs()));
        // (e) determinism: identical inputs → bit-identical output.
        let sol2 = nnls_gram(g, b, n, opts).unwrap();
        assert_eq!(sol, sol2);
        sol
    }

    // ------------------------------------------------------------------
    // Golden vector (hand-derived): correlated 2-var problem whose
    // unconstrained solution has a negative component, forcing a passive
    // set of only the second variable. Hand check: w = (10, 9) → after
    // the first single-variable step x = (10, 0); the free gradient of
    // column 1 goes negative (9 − 0.9·10 = −0.8 raw / −5 normalized), so
    // the loop stops with x = (0, 30), objective −135.
    // ------------------------------------------------------------------

    #[test]
    fn golden_correlated_two_variable() {
        let g = [1.0, 0.5, 0.5, 0.3];
        let b = [10.0, 9.0];
        let sol = nnls_gram(&g, &b, 2, &NnlsOptions::default()).unwrap();
        assert!((sol.x[0] - 0.0).abs() < 1e-9);
        assert!((sol.x[1] - 30.0).abs() < 1e-9, "x = {:?}", sol.x);
        assert_eq!(sol.passive, vec![1]);
        assert!((sol.objective - (-135.0)).abs() < 1e-6);
        assert_eq!(sol.objective_trace[0], 0.0);
        let last = *sol.objective_trace.last().unwrap();
        assert!((last - (-135.0)).abs() < 1e-6);
        assert!(sol.objective_trace.windows(2).all(|w| w[1] <= w[0] + 1e-9));
        assert!(sol.kkt_residual <= sol.kkt_tol);
    }

    #[test]
    fn golden_already_nonnegative_returns_identity_like() {
        // G = I, b ≥ 0: every single-variable solve is final; the loop is
        // n outer iterations with one inner solve each and no truncation.
        let g = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];
        let b = [0.5, 1.5, 2.5];
        let sol = nnls_gram(&g, &b, 3, &NnlsOptions::default()).unwrap();
        // The default ε‖G‖ ridge perturbs each coefficient by O(ε·x).
        assert!(sol
            .x
            .iter()
            .zip(b.iter())
            .all(|(&p, &q)| (p - q).abs() < 1e-9));
        assert_eq!(sol.passive, vec![0, 1, 2]);
        assert_eq!(sol.iterations, 3);
        assert_eq!(sol.truncations, 0);
    }

    #[test]
    fn golden_zero_rhs_gives_zero() {
        let g = [2.0, 1.0, 1.0, 2.0];
        let b = [0.0, 0.0];
        let sol = nnls_gram(&g, &b, 2, &NnlsOptions::default()).unwrap();
        assert!(sol.x.iter().all(|&v| v == 0.0));
        assert!(sol.passive.is_empty());
        assert_eq!(sol.kkt_residual, 0.0);
        assert_eq!(sol.objective, 0.0);
    }

    #[test]
    fn single_variable_extremes() {
        // Negative rhs → 0; positive rhs → exact LS coefficient.
        let sol = nnls_gram(&[4.0], &[-2.0], 1, &NnlsOptions::default()).unwrap();
        assert_eq!(sol.x, vec![0.0]);
        assert!(sol.passive.is_empty());
        let sol = nnls_gram(&[4.0], &[2.0], 1, &NnlsOptions::default()).unwrap();
        assert!((sol.x[0] - 0.5).abs() < 1e-9);
        assert_eq!(sol.passive, vec![0]);
    }

    // ------------------------------------------------------------------
    // Degenerate inputs
    // ------------------------------------------------------------------

    #[test]
    fn zero_variance_column_is_dead() {
        // G_11 = 0: column 1 can never help; consistent input has b_1 = 0.
        let g = [1.0, 0.0, 0.0, 0.0];
        let sol = nnls_gram(&g, &[2.0, 0.0], 2, &NnlsOptions::default()).unwrap();
        assert!((sol.x[0] - 2.0).abs() < 1e-9 && sol.x[1] == 0.0);
        assert_eq!(sol.passive, vec![0]);
        // Inconsistent input (b_1 != 0) still solves; the dead column is
        // excluded from both selection and the KKT check.
        let sol = nnls_gram(&g, &[2.0, 5.0], 2, &NnlsOptions::default()).unwrap();
        assert!((sol.x[0] - 2.0).abs() < 1e-9 && sol.x[1] == 0.0);
        assert!(sol.kkt_residual <= sol.kkt_tol);
    }

    #[test]
    fn negative_diagonal_rejected_as_non_psd() {
        let err = nnls_gram(
            &[1.0, 0.0, 0.0, -1.0],
            &[1.0, 1.0],
            2,
            &NnlsOptions::default(),
        )
        .unwrap_err();
        assert_eq!(err.topic(), "argument");
    }

    #[test]
    fn non_finite_inputs_rejected() {
        let err = nnls_gram(
            &[f64::NAN, 0.0, 0.0, 1.0],
            &[1.0, 1.0],
            2,
            &NnlsOptions::default(),
        )
        .unwrap_err();
        assert_eq!(err.topic(), "na");
        let err = nnls_gram(
            &[1.0, 0.0, 0.0, 1.0],
            &[1.0, f64::INFINITY],
            2,
            &NnlsOptions::default(),
        )
        .unwrap_err();
        assert_eq!(err.topic(), "na");
    }

    #[test]
    fn length_mismatch_rejected() {
        let err = nnls_gram(&[1.0, 0.0, 0.0, 1.0], &[1.0], 2, &NnlsOptions::default()).unwrap_err();
        assert_eq!(err.topic(), "argument");
        let err = nnls_gram(&[1.0], &[1.0], 2, &NnlsOptions::default()).unwrap_err();
        assert_eq!(err.topic(), "argument");
    }

    #[test]
    fn empty_problem_is_trivially_solved() {
        let sol = nnls_gram(&[], &[], 0, &NnlsOptions::default()).unwrap();
        assert!(sol.x.is_empty() && sol.passive.is_empty());
        assert_eq!(sol.objective, 0.0);
    }

    #[test]
    fn duplicate_columns_converge_optimally() {
        // Duplicate columns (singular Gram): Lawson–Hanson's greedy order
        // keeps the passive set basic (one of the twins), so no singular
        // subproblem arises even with the ridge disabled.
        let g = [1.0, 1.0, 1.0, 1.0];
        let b = [2.0, 2.0];
        let opts_plain = NnlsOptions {
            ridge_eps: None,
            ..NnlsOptions::default()
        };
        for opts in [&opts_plain, &NnlsOptions::default()] {
            let sol = nnls_gram(&g, &b, 2, opts).unwrap();
            assert!(sol.x.iter().all(|&v| v >= 0.0));
            // Any non-negative point with x_0 + x_1 = 2 is optimal (the
            // objective only sees the sum); assert sum, KKT and objective
            // parity with the brute-force enumeration.
            assert!((sol.x[0] + sol.x[1] - 2.0).abs() < 1e-9);
            assert!(sol.kkt_residual <= sol.kkt_tol);
            let (_xbf, _fr, f_true_bf) = brute_force_nnls(&g, &b, 2, opts.ridge_eps);
            let f_true = objective(&g, &b, &sol.x, 2);
            assert!((f_true - f_true_bf).abs() <= 1e-10 * (1.0 + f_true_bf.abs()));
        }
    }

    // ------------------------------------------------------------------
    // Random property suite: KKT + monotone trace + brute-force对拍.
    // Fixed seeds via MsRng + StreamId (module composition).
    // ------------------------------------------------------------------

    #[test]
    fn property_random_gram_brute_force_and_invariants() {
        let master = 2026u64;
        for case in 0..60u64 {
            let n = 1 + (case % 6) as usize;
            let m = n + (case % 3) as usize;
            let (g, b) = random_problem(
                master,
                StreamId {
                    replicate: case,
                    rank: n as u64,
                    fold: m as u64,
                },
                n,
                m,
            );
            assert_invariants(&g, &b, n, &NnlsOptions::default());
        }
    }

    #[test]
    fn truncation_path_is_exercised_and_stays_correct() {
        // Scan fixed seeds until the feasible-direction truncation fires;
        // every truncating case must still satisfy all invariants. The
        // near-square design (m = n) with mixed-sign y produces strongly
        // correlated Grams where the greedy order is suboptimal — exactly
        // the regime where the α-step branch is needed. Empirically ~5% of
        // these 300 deterministic cases truncate.
        let master = 11u64;
        let mut truncating = 0usize;
        for case in 0..300u64 {
            let n = 4 + (case % 3) as usize;
            let m = n;
            let mut rng = MsRng::from_stream(
                master,
                StreamId {
                    replicate: 900 + case,
                    rank: n as u64,
                    fold: m as u64,
                },
            );
            let mut a = vec![0.0f64; m * n];
            for j in 0..n {
                let mut col: Vec<f64> = (0..m).map(|_| 2.0 * uniform(&mut rng) - 1.0).collect();
                let norm = col.iter().map(|v| v * v).sum::<f64>().sqrt();
                for v in col.iter_mut() {
                    *v /= norm;
                }
                for i in 0..m {
                    a[i * n + j] = col[i];
                }
            }
            let y: Vec<f64> = (0..m).map(|_| 2.0 * uniform(&mut rng) - 1.0).collect();
            let mut g = vec![0.0f64; n * n];
            for i in 0..n {
                for j in 0..n {
                    g[i * n + j] = (0..m).map(|r| a[r * n + i] * a[r * n + j]).sum();
                }
            }
            let b: Vec<f64> = (0..n)
                .map(|j| (0..m).map(|r| a[r * n + j] * y[r]).sum())
                .collect();
            let opts = NnlsOptions::default();
            let sol = nnls_gram(&g, &b, n, &opts).unwrap();
            if sol.truncations > 0 {
                truncating += 1;
                assert_invariants(&g, &b, n, &opts);
            }
        }
        assert!(truncating >= 1, "no case exercised the truncation path");
    }

    // ------------------------------------------------------------------
    // Ill-conditioned Grams (ARCH §9: NNLS KKT + 病态 Gram, pivot LDLᵀ)
    // ------------------------------------------------------------------

    #[test]
    fn ill_conditioned_hilbert_gram() {
        // Hilbert 8×8: κ ≈ 1.5e10 ≥ 1e10. b = H·x_true with positive
        // x_true; the (ridge-regularized) solution stays positive and
        // agrees with brute force; profile cosine ≥ 1 − 1e-4.
        let n = 8;
        let mut h = vec![0.0f64; n * n];
        for i in 0..n {
            for j in 0..n {
                h[i * n + j] = 1.0 / ((i + j + 1) as f64);
            }
        }
        let x_true: Vec<f64> = (1..=8).map(|v| v as f64).collect();
        let b = matvec(&h, &x_true, n);
        let sol = nnls_gram(&h, &b, n, &NnlsOptions::default()).unwrap();
        assert!(sol.x.iter().all(|&v| v.is_finite() && v >= 0.0));
        assert!(sol.passive.len() == n, "passive = {:?}", sol.passive);
        let cos = cosine(&sol.x, &x_true);
        assert!(cos >= 1.0 - 1e-4, "cosine {cos}");
        let (xbf, _fr, _ft) = brute_force_nnls(&h, &b, n, Some(GRAM_RIDGE_EPS));
        for (i, (&xv, &xb)) in sol.x.iter().zip(xbf.iter()).enumerate() {
            assert!(
                (xv - xb).abs() <= 1e-10 * (1.0 + xb.abs()),
                "component {i}: {xv} vs {xb}"
            );
        }
        assert!(sol.kkt_residual <= sol.kkt_tol);
    }

    /// Build the near-flat signature scenario: K signatures in DIM channels
    /// that are flat direction u plus an η·e_k perturbation (e_k orthonormal,
    /// ⊥ u). Pairwise cosine = 1/(1+η²), so κ(G) ≈ 1/η². Returns (G, b)
    /// with b = G·x_true (the K-format right-hand side).
    fn near_flat_problem(eta: f64) -> (Vec<f64>, Vec<f64>, [f64; 4]) {
        const DIM: usize = 96;
        const K: usize = 4;
        let mut rng = MsRng::from_stream(
            2026,
            StreamId {
                replicate: 41,
                rank: K as u64,
                fold: 1,
            },
        );
        let inv_sqrt = 1.0 / (DIM as f64).sqrt();
        let mut es: Vec<Vec<f64>> = Vec::new();
        for _ in 0..K {
            let mut v: Vec<f64> = (0..DIM).map(|_| 2.0 * uniform(&mut rng) - 1.0).collect();
            let dot: f64 = v.iter().map(|&x| x * inv_sqrt).sum();
            for x in v.iter_mut() {
                *x -= dot * inv_sqrt;
            }
            for _pass in 0..2 {
                for e in es.iter() {
                    let d: f64 = v.iter().zip(e.iter()).map(|(&p, &q)| p * q).sum();
                    for (x, &q) in v.iter_mut().zip(e.iter()) {
                        *x -= d * q;
                    }
                }
            }
            let norm = v.iter().map(|x| x * x).sum::<f64>().sqrt();
            for x in v.iter_mut() {
                *x /= norm;
            }
            es.push(v);
        }
        let norm_inv = 1.0 / (1.0 + eta * eta).sqrt();
        let mut a = vec![0.0f64; DIM * K];
        for k in 0..K {
            for i in 0..DIM {
                a[i * K + k] = (inv_sqrt + eta * es[k][i]) * norm_inv;
            }
        }
        let x_true = [0.4f64, 0.3, 0.2, 0.1];
        let mut g = vec![0.0f64; K * K];
        for i in 0..K {
            for j in 0..K {
                g[i * K + j] = (0..DIM).map(|r| a[r * K + i] * a[r * K + j]).sum();
            }
        }
        // K-format right-hand side for exposures x_true: b = Aᵀ(A x) = G x.
        let b = matvec(&g, &x_true, K);
        (g, b, x_true)
    }

    #[test]
    fn near_flat_signature_gram_ill_conditioned_stability() {
        // Domain scenario at κ(G) ≈ 1e10 (pairwise cosine 1 − 1e-10): the
        // NNLS objective is genuinely flat at that scale, so exact recovery
        // of x_true is ill-posed; what the contract demands (ARCH §9) is a
        // stable, KKT-satisfiable, non-negative solution with a near-exact
        // profile fit — the ridge does the tie-breaking.
        let (g, b, _x_true) = near_flat_problem(1e-5);
        let sol = nnls_gram(&g, &b, 4, &NnlsOptions::default()).unwrap();
        assert!(
            sol.x.iter().all(|&v| v.is_finite() && v >= 0.0),
            "x = {:?}",
            sol.x
        );
        assert!(!sol.passive.is_empty());
        assert!(sol.kkt_residual <= sol.kkt_tol);
        // Profile fit: the reconstructed exposure vector matches b closely.
        let k = 4usize;
        let fit = matvec(&g, &sol.x, k);
        let mut rel = 0.0f64;
        for i in 0..k {
            rel = rel.max((fit[i] - b[i]).abs() / b[i].abs().max(1e-300));
        }
        assert!(rel <= 1e-8, "profile relative misfit {rel:e}");
        // Objective parity with the exhaustive active-set enumeration.
        let (_xbf, fr_bf, _ft) = brute_force_nnls(&g, &b, 4, Some(GRAM_RIDGE_EPS));
        let f = objective(&g, &b, &sol.x, 4);
        assert!((f - fr_bf).abs() <= 1e-10 * (1.0 + fr_bf.abs()));
    }

    #[test]
    fn near_flat_signature_gram_recovery_at_moderate_condition() {
        // Same scenario at κ ≈ 1e6 (cosine 1 − 1e-6): the ridge-induced bias
        // is λ/δ ≈ 1e-6 and roundoff κ·u ≈ 2e-10, so x_true is recoverable.
        let (g, b, x_true) = near_flat_problem(1e-3);
        let sol = nnls_gram(&g, &b, 4, &NnlsOptions::default()).unwrap();
        assert!(
            sol.x.iter().all(|&v| v.is_finite() && v >= 0.0),
            "x = {:?}",
            sol.x
        );
        assert_eq!(sol.passive, vec![0, 1, 2, 3]);
        for (k, (&xv, &xt)) in sol.x.iter().zip(x_true.iter()).enumerate() {
            let rel = (xv - xt).abs() / xt;
            assert!(rel <= 1e-4, "component {k}: {xv} vs {xt} (rel {rel:e})");
        }
        assert!(sol.kkt_residual <= sol.kkt_tol);
    }
}
