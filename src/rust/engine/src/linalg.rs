//! Pivoted LDLᵀ factorization with Bunch–Kaufman diagonal pivoting, block
//! triangular solves, and the symmetric PSD (Gram matrix) entry points
//! (U-M1s-01; `docs/ARCHITECTURE.md` §2 `engine/linalg.rs`).
//!
//! # Pivot strategy: Bunch–Kaufman diagonal pivoting
//!
//! The factorization computes `P A Pᵀ = L D Lᵀ` for a symmetric input `A`,
//! with `P` a permutation, `L` unit lower triangular and `D` block diagonal
//! with 1×1 and 2×2 blocks (unblocked LAPACK `dsytrf`/`dsytf2` scheme).
//! Choice rationale, documented per `docs/ARCHITECTURE.md` §2:
//!
//! * Gram matrices in signature fitting are PSD in exact arithmetic but are
//!   formed in floating point and are frequently near-singular (flat or
//!   nearly parallel signatures). A Bunch–Kaufman factorization tolerates —
//!   and structurally exposes — the mild indefiniteness that roundoff
//!   introduces, where a plain Cholesky would fail noisily.
//! * The α-test (`α = (1+√17)/8`, Bunch–Kaufman 1977) bounds the element
//!   growth of the elimination; the per-step pivot search is a single
//!   column scan, O(n) per step, O(n³) overall — a *complete* (full trailing
//!   submatrix) search would add an O(n²) per-step scan for at most a
//!   constant-factor stability gain, so the standard column search is used.
//! * The pivoting order is rank-revealing: an exactly zero pivot column (or
//!   a zero-determinant 2×2 candidate) is recorded as a structural
//!   singularity ([`Ldlt::singular_at`]) instead of producing NaN/Inf;
//!   [`Ldlt::solve`] then refuses to run (`"singular"` error).
//!
//! # Storage and solves
//!
//! `L` is stored row-major as a full `n×n` array with the strictly lower
//! triangle holding the multipliers, unit diagonal implicit and the upper
//! triangle zero. `A x = b` is solved as `y = L⁻¹ P b`, `z = D⁻¹ y`,
//! `w = L⁻ᵀ z`, `x = Pᵀ w`; the three triangular stages are exposed
//! individually ([`Ldlt::solve_l`], [`Ldlt::solve_d`], [`Ldlt::solve_lt`]).
//! No formed inverse is ever materialized (FFI/numerics contract).
//!
//! # Gram path and ridge
//!
//! [`gram_factor`] factors `G + λ I` with `λ = ε · max_k G_kk` (the natural
//! ‖G‖₂ proxy for PSD input). [`GRAM_RIDGE_EPS`] is the default relative ε:
//!
//! * f64 machine ε is 2.22e-16; the accumulated roundoff in forming
//!   `G = AᵀA` and in the triangular updates is a small multiple of `u‖G‖`.
//!   ε = 1e-12 sits ≈ 4500× above that noise floor, so the ridge dominates
//!   roundoff wherever it is needed at all;
//! * it perturbs the minimizer of a well-posed system by ≲ ε·κ(G) relative,
//!   which is negligible for every κ ≲ 1e8 and only becomes active in the
//!   near-singular regime (κ ≳ 1e12) where unconstrained LS coefficients
//!   are meaningless anyway — exactly the "ε‖G‖ ridge" contract of
//!   `docs/ARCHITECTURE.md` §2 `engine/nnls.rs`.
//!
//! # Contract notes
//!
//! Pure engine kernel: no FFI face, no `unsafe`, no dependencies (FFI
//! contract 5: `Result<_, MsError>` everywhere, never panic across a
//! boundary). All loops have fixed order, so results are thread-count
//! invariant (§2.6). Only the lower triangle of the input is read.

use crate::error::MsError;

/// Bunch–Kaufman pivot threshold α = (1 + √17)/8 ≈ 0.6404 (Bunch & Kaufman
/// 1977). Spelled as a literal because `f64::sqrt` is not usable in a
/// `const` on the 1.71 MSRV toolchain.
const BK_ALPHA: f64 = 0.640_388_203_202_207_6;

/// Default relative Gram ridge ε (see the module docs for the derivation
/// and the justification of the 1e-12 magnitude).
pub const GRAM_RIDGE_EPS: f64 = 1e-12;

/// One block on the diagonal of `D`.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum DBlock {
    /// 1×1 block holding the single pivot `d`.
    D1(f64),
    /// 2×2 block `[[d11, d12], [d12, d22]]` (symmetric by construction).
    D2 { d11: f64, d12: f64, d22: f64 },
}

impl DBlock {
    /// Number of matrix positions covered by the block (1 or 2).
    pub fn size(&self) -> usize {
        match self {
            DBlock::D1(_) => 1,
            DBlock::D2 { .. } => 2,
        }
    }
}

/// Pivoted LDLᵀ factorization `P A Pᵀ = L D Lᵀ` of a symmetric matrix.
///
/// Plain value type; all fields are exposed through accessors so tests and
/// downstream kernels can reconstruct or inspect the factorization.
#[derive(Debug, Clone, PartialEq)]
pub struct Ldlt {
    n: usize,
    /// `perm[k]` = original index sitting at permuted position `k`
    /// (`(P A Pᵀ)[k][j] = A[perm[k]][perm[j]]`).
    perm: Vec<usize>,
    /// Unit lower triangular factor, row-major full `n×n` storage: diagonal
    /// 1.0, strictly lower triangle the multipliers, upper triangle 0.0.
    l: Vec<f64>,
    /// Block-diagonal `D` as consecutive `(start position, block)` pairs.
    blocks: Vec<(usize, DBlock)>,
    /// Position of the first structural singularity (zero 1×1 pivot or
    /// zero-determinant 2×2 block), if any.
    singular_at: Option<usize>,
}

impl Ldlt {
    /// Factor the symmetric `n×n` matrix `sym` (row-major `n×n` storage).
    ///
    /// Only the lower triangle is read; the input is symmetrized from it.
    /// Validation errors: `"argument"` on a storage-size mismatch,
    /// `"na"` on a non-finite entry (FFI contract 3). The factorization
    /// itself never fails: structural singularity is recorded on the
    /// [`Ldlt`] value and surfaces from [`Ldlt::solve`].
    pub fn factor(sym: &[f64], n: usize) -> Result<Ldlt, MsError> {
        if sym.len() != n * n {
            return Err(
                MsError::new("argument", "symmetric matrix storage must be n*n elements")
                    .with_i(sym.len() as i64),
            );
        }
        for (idx, &v) in sym.iter().enumerate() {
            if !v.is_finite() {
                return Err(MsError::new("na", "non-finite entry in symmetric matrix")
                    .with_i((idx / n + 1) as i64)
                    .with_j((idx % n + 1) as i64));
            }
        }

        // Working copy: exactly symmetric, mirrored from the lower triangle.
        // All subsequent reads are from the lower triangle; full row+column
        // swaps preserve symmetry, so the invariant holds throughout.
        let mut a = vec![0.0f64; n * n];
        for i in 0..n {
            for j in 0..=i {
                let v = sym[i * n + j];
                a[i * n + j] = v;
                a[j * n + i] = v;
            }
        }

        let mut perm: Vec<usize> = (0..n).collect();
        let mut blocks: Vec<(usize, DBlock)> = Vec::new();
        let mut singular_at: Option<usize> = None;

        let mut k = 0usize;
        while k < n {
            // Column search: r ∈ [k, n) maximizing |a[r][k]| (lower triangle).
            let mut r = k;
            let mut amax = a[k * n + k].abs();
            for i in (k + 1)..n {
                let v = a[i * n + k].abs();
                if v > amax {
                    amax = v;
                    r = i;
                }
            }

            if amax == 0.0 {
                // The whole pivot column (diagonal included) is exactly zero:
                // record a zero 1×1 pivot and continue with the next column.
                // The remaining submatrix may still be nonzero, so we cannot
                // stop here (LAPACK dsytf2 does the same).
                if singular_at.is_none() {
                    singular_at = Some(k);
                }
                blocks.push((k, DBlock::D1(0.0)));
                k += 1;
                continue;
            }

            let akk = a[k * n + k].abs();
            if k == n - 1 || akk >= BK_ALPHA * amax {
                // 1×1 pivot in place. `d != 0` holds because the α-test with
                // `amax > 0` forces |d| ≥ α·amax > 0 (and `k == n-1` implies
                // `amax == |d| > 0`).
                pivot_1x1(&mut a, n, k);
                blocks.push((k, DBlock::D1(a[k * n + k])));
                k += 1;
            } else if a[r * n + r].abs() >= BK_ALPHA * amax {
                // 1×1 pivot after swapping r into position k.
                // NOTE (documented divergence from LAPACK dsytf2): this second
                // α-test uses `amax` of the ORIGINAL pivot column j, while
                // dsytf2 re-reads ROWMAX of the candidate row AFTER the swap.
                // Pivot choices may therefore differ from LAPACK on
                // ties/near-ties; correctness is unaffected (the PAPᵀ = LDLᵀ
                // reconstruction identity is tested on random matrices).
                symmetric_swap(&mut a, &mut perm, n, k, r);
                pivot_1x1(&mut a, n, k);
                blocks.push((k, DBlock::D1(a[k * n + k])));
                k += 1;
            } else {
                // 2×2 pivot on positions (k, k+1).
                if r != k + 1 {
                    symmetric_swap(&mut a, &mut perm, n, k + 1, r);
                }
                let d11 = a[k * n + k];
                let d12 = a[(k + 1) * n + k];
                let d22 = a[(k + 1) * n + k + 1];
                let det = d11 * d22 - d12 * d12;
                if det == 0.0 {
                    // Exactly singular 2×2 candidate: record it and stop
                    // updating (the Bunch–Kaufman α-test makes this
                    // unreachable in exact arithmetic; it can only be hit by
                    // degenerate inputs at underflow). `solve` refuses to
                    // run on a singular factorization, so the stale
                    // multipliers below are never consumed.
                    if singular_at.is_none() {
                        singular_at = Some(k);
                    }
                } else {
                    // Multipliers w_i = D⁻¹ · a[i, k:k+2], stored in L.
                    for i in (k + 2)..n {
                        let b1 = a[i * n + k];
                        let b2 = a[i * n + k + 1];
                        let w1 = (d22 * b1 - d12 * b2) / det;
                        let w2 = (d11 * b2 - d12 * b1) / det;
                        a[i * n + k] = w1;
                        a[i * n + k + 1] = w2;
                    }
                    // Schur update: A22 ← A22 − L21 D L21ᵀ, both triangles
                    // (see `pivot_1x1` for why exact symmetry is kept).
                    // (i, j) entry: −(w_iᵀ D w_j).
                    for i in (k + 2)..n {
                        let w1i = a[i * n + k];
                        let w2i = a[i * n + k + 1];
                        for j in (k + 2)..n {
                            let w1j = a[j * n + k];
                            let w2j = a[j * n + k + 1];
                            a[i * n + j] -=
                                w1i * d11 * w1j + d12 * (w1i * w2j + w2i * w1j) + w2i * d22 * w2j;
                        }
                    }
                }
                blocks.push((k, DBlock::D2 { d11, d12, d22 }));
                k += 2;
            }
        }

        let mut l = vec![0.0f64; n * n];
        for i in 0..n {
            l[i * n + i] = 1.0;
            for j in 0..i {
                l[i * n + j] = a[i * n + j];
            }
        }
        // A 2×2 block owns its subdiagonal entry (it is d12 of the block):
        // L carries a structural zero there, and the coupling flows through
        // D in the L D Lᵀ product.
        for &(s, blk) in &blocks {
            if matches!(blk, DBlock::D2 { .. }) {
                l[(s + 1) * n + s] = 0.0;
            }
        }

        Ok(Ldlt {
            n,
            perm,
            l,
            blocks,
            singular_at,
        })
    }

    /// Dimension of the factored matrix.
    pub fn n(&self) -> usize {
        self.n
    }

    /// Pivot permutation: `perm[k]` = original index at position `k`.
    pub fn perm(&self) -> &[usize] {
        &self.perm
    }

    /// Unit lower triangular factor `L`, row-major full `n×n` storage
    /// (diagonal 1.0, upper triangle 0.0).
    pub fn l(&self) -> &[f64] {
        &self.l
    }

    /// Block-diagonal `D` as `(start position, block)` pairs in order.
    pub fn blocks(&self) -> &[(usize, DBlock)] {
        &self.blocks
    }

    /// Position (0-based) of the first structural singularity, if any.
    pub fn singular_at(&self) -> Option<usize> {
        self.singular_at
    }

    /// Whether the factorization hit a structural singularity.
    pub fn is_singular(&self) -> bool {
        self.singular_at.is_some()
    }

    /// Forward substitution `L y = b` for the unit lower triangular factor.
    pub fn solve_l(&self, b: &[f64]) -> Result<Vec<f64>, MsError> {
        if b.len() != self.n {
            return Err(
                MsError::new("argument", "right-hand side length must equal n")
                    .with_i(b.len() as i64),
            );
        }
        let mut y = vec![0.0f64; self.n];
        for i in 0..self.n {
            let mut acc = b[i];
            let row = i * self.n;
            for (j, yj) in y[..i].iter().enumerate() {
                acc -= self.l[row + j] * yj;
            }
            y[i] = acc;
        }
        Ok(y)
    }

    /// Block-diagonal solve `D x = y` (1×1 divisions and 2×2 solves).
    pub fn solve_d(&self, y: &[f64]) -> Result<Vec<f64>, MsError> {
        if y.len() != self.n {
            return Err(
                MsError::new("argument", "right-hand side length must equal n")
                    .with_i(y.len() as i64),
            );
        }
        if let Some(k) = self.singular_at {
            return Err(singular_error(k));
        }
        let mut z = vec![0.0f64; self.n];
        for &(s, blk) in self.blocks.iter() {
            match blk {
                DBlock::D1(d) => z[s] = y[s] / d,
                DBlock::D2 { d11, d12, d22 } => {
                    let det = d11 * d22 - d12 * d12;
                    // `det == 0` implies `singular_at` was set at factor
                    // time and we already returned; guard defensively.
                    if det == 0.0 {
                        return Err(singular_error(s));
                    }
                    let (y0, y1) = (y[s], y[s + 1]);
                    z[s] = (d22 * y0 - d12 * y1) / det;
                    z[s + 1] = (d11 * y1 - d12 * y0) / det;
                }
            }
        }
        Ok(z)
    }

    /// Back substitution `Lᵀ x = y` for the unit lower triangular factor.
    pub fn solve_lt(&self, y: &[f64]) -> Result<Vec<f64>, MsError> {
        if y.len() != self.n {
            return Err(
                MsError::new("argument", "right-hand side length must equal n")
                    .with_i(y.len() as i64),
            );
        }
        let mut x = vec![0.0f64; self.n];
        for i in (0..self.n).rev() {
            let mut acc = y[i];
            for (j, xj) in x[(i + 1)..].iter().enumerate() {
                acc -= self.l[(i + 1 + j) * self.n + i] * xj;
            }
            x[i] = acc;
        }
        Ok(x)
    }

    /// Solve `A x = b` using the factorization `P A Pᵀ = L D Lᵀ`.
    ///
    /// Errors: `"argument"` on a length mismatch, `"singular"` when the
    /// factorization recorded a structural singularity.
    pub fn solve(&self, b: &[f64]) -> Result<Vec<f64>, MsError> {
        if b.len() != self.n {
            return Err(
                MsError::new("argument", "right-hand side length must equal n")
                    .with_i(b.len() as i64),
            );
        }
        if let Some(k) = self.singular_at {
            return Err(singular_error(k));
        }
        // Permute, then the three triangular stages, then un-permute.
        let mut pb = vec![0.0f64; self.n];
        for k in 0..self.n {
            pb[k] = b[self.perm[k]];
        }
        let y = self.solve_l(&pb)?;
        let z = self.solve_d(&y)?;
        let w = self.solve_lt(&z)?;
        let mut x = vec![0.0f64; self.n];
        for k in 0..self.n {
            x[self.perm[k]] = w[k];
        }
        Ok(x)
    }
}

/// The natural scale of a symmetric PSD matrix: `max_k G_kk`. This is a
/// computable LOWER bound on ‖G‖₂ (equality only for diagonal-dominant
/// matrices); it is used purely as a scale proxy for relative tolerances,
/// never as a norm bound. Caller must guarantee `g.len() == n * n`; returns
/// 0.0 for an empty or all-zero diagonal.
pub fn gram_scale(g: &[f64], n: usize) -> f64 {
    let mut scale = 0.0f64;
    for i in 0..n {
        let d = g[i * n + i];
        if d > scale {
            scale = d;
        }
    }
    scale
}

/// Factor `G + λ I` for symmetric PSD `G` (row-major `n×n`, lower triangle
/// read), with the relative ridge `λ = ε · max_k G_kk`.
///
/// `ridge_eps = None` disables the ridge (λ = 0); `Some(eps)` with
/// `eps = 0.0` is equivalent. The default [`GRAM_RIDGE_EPS`] and its
/// justification are in the module docs. Validation mirrors
/// [`Ldlt::factor`].
pub fn gram_factor(g: &[f64], n: usize, ridge_eps: Option<f64>) -> Result<Ldlt, MsError> {
    if g.len() != n * n {
        return Err(
            MsError::new("argument", "Gram matrix storage must be n*n elements")
                .with_i(g.len() as i64),
        );
    }
    let scale = gram_scale(g, n);
    let lambda = ridge_eps.unwrap_or(0.0) * scale;
    let mut ridge_g = g.to_vec();
    if lambda != 0.0 {
        for i in 0..n {
            ridge_g[i * n + i] += lambda;
        }
    }
    Ldlt::factor(&ridge_g, n)
}

/// Swap rows and columns `p`/`q` of the symmetric working matrix and keep
/// the pivot permutation in sync. Applied to the full row/column so the
/// already-computed `L` block (columns `< k`) moves with its rows — this is
/// exactly `(W M Wᵀ)` with `W = I_k ⊕ P_step`, under which the previously
/// factored leading block and its `L11` are invariant.
fn symmetric_swap(a: &mut [f64], perm: &mut [usize], n: usize, p: usize, q: usize) {
    for j in 0..n {
        a.swap(p * n + j, q * n + j);
    }
    for i in 0..n {
        a.swap(i * n + p, i * n + q);
    }
    perm.swap(p, q);
}

/// Eliminate a 1×1 pivot at position `k` (`d = a[k][k] != 0` guaranteed by
/// the branch conditions at the call site): store the multipliers in the
/// strictly lower triangle and update the trailing Schur complement.
///
/// The update covers **both** triangles: later pivot steps apply full
/// row+column swaps, which are exact similarity transforms only under
/// exactly symmetric storage — a lower-triangle-only update would leave a
/// stale mirror that a swap then smears into the meaningful data. The 2×
/// update flops are irrelevant at the n this crate targets.
fn pivot_1x1(a: &mut [f64], n: usize, k: usize) {
    let d = a[k * n + k];
    for i in (k + 1)..n {
        let lik = a[i * n + k] / d;
        a[i * n + k] = lik;
    }
    for i in (k + 1)..n {
        let lik = a[i * n + k];
        for j in (k + 1)..n {
            a[i * n + j] -= lik * a[j * n + k] * d;
        }
    }
}

fn singular_error(k: usize) -> MsError {
    MsError::new("singular", "matrix is singular at the given pivot position").with_i(k as i64 + 1)
}

// ======================================================================
// Tests: goldens, triangular solves, reconstruction & residual properties,
// Gram/ridge path, singularity and validation. Fixed seeds only (MsRng,
// StreamId layout — also exercises cross-module composition, ARCH §9).
// ======================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rng::{MsRng, StreamId};

    /// Uniform f64 in [0, 1) from the in-house generator.
    fn uniform(rng: &mut MsRng) -> f64 {
        ((rng.next_u64() >> 11) as f64) * (1.0 / (1u64 << 53) as f64)
    }

    fn max_abs(v: &[f64]) -> f64 {
        v.iter().fold(0.0f64, |m, &x| m.max(x.abs()))
    }

    fn matmul(a: &[f64], b: &[f64], n: usize) -> Vec<f64> {
        let mut c = vec![0.0f64; n * n];
        for i in 0..n {
            for j in 0..n {
                let mut acc = 0.0;
                for kk in 0..n {
                    acc += a[i * n + kk] * b[kk * n + j];
                }
                c[i * n + j] = acc;
            }
        }
        c
    }

    fn matvec(a: &[f64], x: &[f64], n: usize) -> Vec<f64> {
        (0..n)
            .map(|i| (0..n).map(|j| a[i * n + j] * x[j]).sum())
            .collect()
    }

    /// Dense L D Lᵀ from a factorization (dense D, two matmuls).
    fn ldl_t(f: &Ldlt) -> Vec<f64> {
        let n = f.n();
        let mut dd = vec![0.0f64; n * n];
        for &(s, blk) in f.blocks().iter() {
            match blk {
                DBlock::D1(d) => dd[s * n + s] = d,
                DBlock::D2 { d11, d12, d22 } => {
                    dd[s * n + s] = d11;
                    dd[s * n + s + 1] = d12;
                    dd[(s + 1) * n + s] = d12;
                    dd[(s + 1) * n + s + 1] = d22;
                }
            }
        }
        // ld = L·D, then out = ld·Lᵀ.
        let ld = matmul(f.l(), &dd, n);
        let mut out = vec![0.0f64; n * n];
        for i in 0..n {
            for j in 0..n {
                let mut acc = 0.0;
                for s in 0..n {
                    acc += ld[i * n + s] * f.l()[j * n + s];
                }
                out[i * n + j] = acc;
            }
        }
        out
    }

    /// Permute rows and columns of `a` by `f.perm()`.
    fn permute(a: &[f64], perm: &[usize], n: usize) -> Vec<f64> {
        let mut out = vec![0.0f64; n * n];
        for i in 0..n {
            for j in 0..n {
                out[i * n + j] = a[perm[i] * n + perm[j]];
            }
        }
        out
    }

    // ------------------------------------------------------------------
    // Golden vectors (hand-derived)
    // ------------------------------------------------------------------

    #[test]
    fn golden_indefinite_2x2_takes_block_pivot() {
        // A = [[0, 1], [1, 0]] (eigenvalues ±1): the α-test rejects both
        // zero 1×1 candidates and takes the 2×2 block, det = −1.
        let f = Ldlt::factor(&[0.0, 1.0, 1.0, 0.0], 2).unwrap();
        assert_eq!(f.perm(), &[0, 1]);
        assert_eq!(
            f.blocks(),
            &[(
                0,
                DBlock::D2 {
                    d11: 0.0,
                    d12: 1.0,
                    d22: 0.0
                }
            )]
        );
        assert!(!f.is_singular());
        let x = f.solve(&[0.0, 1.0]).unwrap();
        assert_eq!(x, vec![1.0, 0.0]);
        // L carries a structural zero below a 2×2 block.
        assert_eq!(f.l(), &[1.0, 0.0, 0.0, 1.0]);
    }

    #[test]
    fn golden_indefinite_2x2_swaps_before_pivot() {
        // A = [[0, 1], [1, 5]]: column search moves index 1 into the pivot
        // position (α-test branch 2), pivots 5 then −0.2 = −1/5.
        let f = Ldlt::factor(&[0.0, 1.0, 1.0, 5.0], 2).unwrap();
        assert_eq!(f.perm(), &[1, 0]);
        assert_eq!(f.blocks()[0], (0, DBlock::D1(5.0)));
        assert!((f.blocks()[1].0 == 1) && f.blocks()[1].1.size() == 1);
        if let DBlock::D1(d) = f.blocks()[1].1 {
            assert!((d + 0.2).abs() < 1e-15);
        } else {
            panic!("expected a 1x1 second block");
        }
        // A x = b with x = (−29, 6).
        let x = f.solve(&[6.0, 1.0]).unwrap();
        assert!(
            (x[0] + 29.0).abs() < 1e-9 && (x[1] - 6.0).abs() < 1e-9,
            "x = {x:?}"
        );
    }

    #[test]
    fn golden_2x2_block_pivot() {
        // A = [[1, 2], [2, 1]] (eigenvalues −1, 3): the α-test rejects both
        // 1×1 candidates and takes the 2×2 block, det = −3.
        let f = Ldlt::factor(&[1.0, 2.0, 2.0, 1.0], 2).unwrap();
        assert_eq!(
            f.blocks(),
            &[(
                0,
                DBlock::D2 {
                    d11: 1.0,
                    d12: 2.0,
                    d22: 1.0
                }
            )]
        );
        assert_eq!(f.perm(), &[0, 1]);
        let x = f.solve(&[3.0, 3.0]).unwrap();
        assert_eq!(x, vec![1.0, 1.0]);
    }

    #[test]
    fn golden_3x3_block_then_scalar() {
        // A = [[1, 2, 0], [2, 1, 0], [0, 0, 1]]: 2×2 block first (the
        // multipliers of row 2 are exactly 0), then the untouched 1.
        let f = Ldlt::factor(&[1.0, 2.0, 0.0, 2.0, 1.0, 0.0, 0.0, 0.0, 1.0], 3).unwrap();
        assert_eq!(f.blocks().len(), 2);
        assert_eq!(
            f.blocks()[0],
            (
                0,
                DBlock::D2 {
                    d11: 1.0,
                    d12: 2.0,
                    d22: 1.0
                }
            )
        );
        assert_eq!(f.blocks()[1], (2, DBlock::D1(1.0)));
        let x = f.solve(&[3.0, 3.0, 1.0]).unwrap();
        assert_eq!(x, vec![1.0, 1.0, 1.0]);
    }

    #[test]
    fn triangular_solves_known_answers() {
        // L = [[1, 0], [0.5, 1]] in full row-major storage.
        let l = vec![1.0, 0.0, 0.5, 1.0];
        let f = Ldlt {
            n: 2,
            perm: vec![0, 1],
            l,
            blocks: vec![(0, DBlock::D1(4.0))],
            singular_at: None,
        };
        // L y = b with b = (2, 1): y = (2, 0).
        assert_eq!(f.solve_l(&[2.0, 1.0]).unwrap(), vec![2.0, 0.0]);
        // Lᵀ x = y with y = (2, 0): x = (2, 0).
        assert_eq!(f.solve_lt(&[2.0, 0.0]).unwrap(), vec![2.0, 0.0]);
        // D x = y with D = 4: 8 → 2.
        assert_eq!(f.solve_d(&[8.0, 0.0]).unwrap(), vec![2.0, 0.0]);
        // D2 block solve: [[1, 2], [2, 1]] · (1, 1) = (3, 3).
        let f2 = Ldlt {
            n: 2,
            perm: vec![0, 1],
            l: vec![1.0, 0.0, 0.0, 1.0],
            blocks: vec![(
                0,
                DBlock::D2 {
                    d11: 1.0,
                    d12: 2.0,
                    d22: 1.0,
                },
            )],
            singular_at: None,
        };
        assert_eq!(f2.solve_d(&[3.0, 3.0]).unwrap(), vec![1.0, 1.0]);
    }

    // ------------------------------------------------------------------
    // Reconstruction / residual properties (fixed seeds, no proptest)
    // ------------------------------------------------------------------

    #[test]
    fn reconstruction_permuted_identity_random_symmetric() {
        // P A Pᵀ == L D Lᵀ for random symmetric matrices, including
        // indefinite ones (entries in [−1, 1]) and PSD ones (AᵀA).
        let master = 2026u64;
        for case in 0..24u64 {
            let n = 1 + (case % 7) as usize;
            let mut rng = MsRng::from_stream(
                master,
                StreamId {
                    replicate: case,
                    rank: n as u64,
                    fold: 9,
                },
            );
            let m = n + 2;
            let mut a = vec![0.0f64; n * n];
            if case % 2 == 0 {
                // Symmetric indefinite-ish.
                let mut raw = vec![0.0f64; n * n];
                for v in raw.iter_mut() {
                    *v = 2.0 * uniform(&mut rng) - 1.0;
                }
                for i in 0..n {
                    for j in 0..=i {
                        let v = raw[i * n + j];
                        a[i * n + j] = v;
                        a[j * n + i] = v;
                    }
                }
            } else {
                // PSD Gram of a random m×n matrix.
                let mut aa = vec![0.0f64; m * n];
                for v in aa.iter_mut() {
                    *v = 2.0 * uniform(&mut rng) - 1.0;
                }
                for i in 0..n {
                    for j in 0..n {
                        a[i * n + j] = (0..m).map(|r| aa[r * n + i] * aa[r * n + j]).sum();
                    }
                }
            }
            let f = Ldlt::factor(&a, n).unwrap();
            let scale = max_abs(&a).max(1.0);
            let diff: f64 = permute(&a, f.perm(), n)
                .iter()
                .zip(ldl_t(&f).iter())
                .map(|(&p, &q)| (p - q).abs())
                .fold(0.0f64, |m2, d| m2.max(d));
            assert!(
                diff <= 1e-12 * scale * (n as f64),
                "case {case}: reconstruction diff {diff:e}"
            );
            // The permutation must be a permutation.
            let mut seen = vec![false; n];
            for &p in f.perm() {
                assert!(p < n && !seen[p], "case {case}: bad permutation");
                seen[p] = true;
            }
        }
    }

    #[test]
    fn solve_residual_property_random() {
        let master = 77u64;
        for case in 0..24u64 {
            let n = 1 + (case % 7) as usize;
            let mut rng = MsRng::from_stream(
                master,
                StreamId {
                    replicate: 100 + case,
                    rank: n as u64,
                    fold: 3,
                },
            );
            // Diagonally dominant symmetric (well-conditioned) + random b.
            let mut a = vec![0.0f64; n * n];
            for i in 0..n {
                for j in 0..i {
                    let v = 2.0 * uniform(&mut rng) - 1.0;
                    a[i * n + j] = v;
                    a[j * n + i] = v;
                }
                a[i * n + i] = n as f64 + uniform(&mut rng);
            }
            let b: Vec<f64> = (0..n).map(|_| 2.0 * uniform(&mut rng) - 1.0).collect();
            let f = Ldlt::factor(&a, n).unwrap();
            let x = f.solve(&b).unwrap();
            let ax = matvec(&a, &x, n);
            let res: f64 = ax
                .iter()
                .zip(b.iter())
                .map(|(&p, &q)| (p - q).abs())
                .fold(0.0, f64::max);
            let denom = (max_abs(&a) * max_abs(&x) + max_abs(&b)).max(1.0);
            assert!(res <= 1e-12 * denom, "case {case}: residual {res:e}");
        }
    }

    #[test]
    fn hilbert_8_solve_is_backward_stable() {
        // Hilbert 8×8 (κ ≈ 1.5e10): pivoting keeps the factorization sane;
        // the residual is small even though the forward error is not.
        let n = 8;
        let mut h = vec![0.0f64; n * n];
        for i in 0..n {
            for j in 0..n {
                h[i * n + j] = 1.0 / ((i + j + 1) as f64);
            }
        }
        let x_true: Vec<f64> = (1..=8).map(|v| v as f64).collect();
        let b = matvec(&h, &x_true, n);
        let f = Ldlt::factor(&h, n).unwrap();
        assert!(!f.is_singular());
        let x = f.solve(&b).unwrap();
        let ax = matvec(&h, &x, n);
        let res: f64 = ax
            .iter()
            .zip(b.iter())
            .map(|(&p, &q)| (p - q).abs())
            .fold(0.0, f64::max);
        assert!(res <= 1e-10, "residual {res:e}");
    }

    // ------------------------------------------------------------------
    // Gram path: ridge, scale, singularity, validation
    // ------------------------------------------------------------------

    #[test]
    fn gram_factor_applies_relative_ridge() {
        // G = diag(4e6, 9e6): scale = 9e6, λ = 1e-12 · 9e6 = 9e-6.
        // Without ridge the solve would be exact; with it, ‖Gx − b‖ ≈ λ‖x‖.
        let g = [4.0e6, 0.0, 0.0, 9.0e6];
        let b = [8.0e6, 2.7e7];
        let f = gram_factor(&g, 2, Some(GRAM_RIDGE_EPS)).unwrap();
        assert!(!f.is_singular());
        let x = f.solve(&b).unwrap();
        assert!(
            (x[0] - 2.0).abs() < 1e-9 && (x[1] - 3.0).abs() < 1e-9,
            "x = {x:?}"
        );
        let gx = matvec(&g, &x, 2);
        let res: f64 = gx
            .iter()
            .zip(b.iter())
            .map(|(&p, &q)| (p - q).abs())
            .fold(0.0, f64::max);
        // Ridge actually applied: residual sits at λ·‖x‖ ≈ 3.2e-5.
        assert!(res > 1e-6 && res < 1e-3, "ridge residual {res:e}");
    }

    #[test]
    fn gram_factor_without_ridge_is_exact() {
        let g = [4.0e6, 0.0, 0.0, 9.0e6];
        let b = [8.0e6, 2.7e7];
        let f = gram_factor(&g, 2, None).unwrap();
        let x = f.solve(&b).unwrap();
        assert_eq!(x[0], 2.0);
        assert_eq!(x[1], 3.0);
    }

    #[test]
    fn singular_gram_is_detected_and_refuses_to_solve() {
        // Duplicate columns → singular Gram.
        let g = [1.0, 1.0, 1.0, 1.0];
        let f = gram_factor(&g, 2, None).unwrap();
        assert!(f.is_singular());
        // The singularity only shows at the second step: the first pivot
        // is d = 1, the Schur update drives the trailing diagonal to 0.
        assert_eq!(f.singular_at(), Some(1));
        let err = f.solve(&[2.0, 2.0]).unwrap_err();
        assert_eq!(err.topic(), "singular");
        assert!(err.i.is_some());
        // All-zero matrix: every pivot is zero, permutation stays identity.
        let z = gram_factor(&[0.0, 0.0, 0.0, 0.0], 2, None).unwrap();
        assert!(z.is_singular());
        assert_eq!(z.perm(), &[0, 1]);
    }

    #[test]
    fn input_validation_errors() {
        // Storage size mismatch.
        let err = Ldlt::factor(&[1.0, 0.0, 0.0], 2).unwrap_err();
        assert_eq!(err.topic(), "argument");
        // Non-finite entry in the read (lower) triangle, with 1-based
        // indices attached. The upper triangle is never read, so only the
        // lower one is validated.
        let err = Ldlt::factor(&[1.0, 0.0, f64::NAN, 1.0], 2).unwrap_err();
        assert_eq!(err.topic(), "na");
        assert_eq!(err.i, Some(2));
        assert_eq!(err.j, Some(1));
        let err = gram_factor(&[f64::INFINITY], 1, Some(GRAM_RIDGE_EPS)).unwrap_err();
        assert_eq!(err.topic(), "na");
        // Solve length mismatch.
        let f = Ldlt::factor(&[2.0], 1).unwrap();
        assert_eq!(f.solve(&[1.0, 2.0]).unwrap_err().topic(), "argument");
    }

    #[test]
    fn single_variable_round_trip() {
        let f = Ldlt::factor(&[-3.5], 1).unwrap();
        assert_eq!(f.blocks(), &[(0, DBlock::D1(-3.5))]);
        assert_eq!(f.solve(&[7.0]).unwrap(), vec![-2.0]);
    }
}
