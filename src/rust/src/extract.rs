//! Single-method catalog extraction core (U-M1s-12): one seeded NMF fit.
//!
//! This module is the pure (R-type-free) heart of `ms_extract_rust` — the
//! M1s "single method" extraction behind the user-facing `ms_extract()`
//! generic (`R/extract.R`). It runs exactly ONE kernel fit with the seeded
//! initializer drawn from the canonical zero stream (`StreamId::ZERO`):
//! the replicate / consensus / K-selection machinery of the M2 extraction
//! pipeline deliberately does not exist yet (`docs/ROADMAP.md` M1s:
//! "ms_extract（单方法）"). The variant is the [`NmfVariant`] switch: KL
//! (β = 1, the D6 default) or EU (β = 2), both faces of
//! `msuiter_engine::nmf`.
//!
//! # Layout contract (the transposition trap)
//!
//! The kernel consumes `V` in **row-major** `m×n` order (m channels × n
//! samples). R stores matrices column-major, so the FFI adapter (`lib.rs`)
//! receives `t(counts)` — an `n×m` R double matrix whose column-major flat
//! buffer is exactly the row-major `m×n` `V`:
//! `data[j*m + i] == counts[i, j]`. No marshalling loop remains on the Rust
//! side, which is why the acceptance smoke on BOTH sides asserts recovery
//! on an ASYMMETRIC catalog (m ≠ n, here 96×12): a transposed handoff
//! cannot pass the reconstruction-cosine gate (the same discipline as the
//! `msffi_column_major_probe` golden).
//!
//! # Interrupt protocol (contract 7, declared decision)
//!
//! A single fit has no chunk structure to poll at: the kernel runs a fixed
//! `max_iter` loop of dense `O(m·n·k)` updates with no early exit.
//! This export is therefore **declared bounded-duration and
//! non-interruptible within `max_iter`** (documented in
//! `docs/ffi-surface.md`): the alternative — per-iteration boundary polls —
//! would either fork the kernel loop into the FFI shell or require a
//! callback seam through the pure engine crate, both worse trades for M1s.
//! The target workload (96 channels × tens of samples × 500 iterations)
//! completes in well under a second; the M2 replicate pipeline re-introduces
//! chunked polling through the existing replicates driver.
//!
//! # Threads
//!
//! One fit → nothing to parallelize (A7: a sequential kernel is trivially
//! thread-invariant). The FFI face accepts `n_threads` for surface
//! stability ahead of the M2 replicates pipeline and validates it (≥ 0)
//! but does not build a pool.
//!
//! # Normalization policy
//!
//! The kernel returns the RAW factors `W` (m×k) and `H` (k×n). Column-
//! normalizing `W` onto the simplex is a display convention owned by the R
//! assembly layer (`R/extract.R`), which rescales `H` by the same factors
//! so the `W·H` reconstruction is preserved up to floating-point rounding.
//! Nothing is renormalized here (kernel contract, D6).

use msuiter_engine::error::MsError;
use msuiter_engine::nmf;

/// The NMF variant behind the single-method extraction: KL (β = 1, the D6
/// default — the multiplicative updates are the Poisson MLE of the
/// multinomial catalog model) or EU (β = 2, squared Frobenius).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NmfVariant {
    Kl,
    Eu,
}

impl NmfVariant {
    /// Parse the wire name from the R side (contract 4: explicit, errors
    /// not panics; the message lists the legal names).
    pub fn parse(name: &str) -> Result<Self, MsError> {
        match name {
            "kl" => Ok(NmfVariant::Kl),
            "eu" => Ok(NmfVariant::Eu),
            other => Err(MsError::new(
                "argument",
                format!("engine variant \"{other}\" is not one of \"kl\", \"eu\""),
            )),
        }
    }
}

/// Run the single seeded NMF extraction of a catalog matrix (U-M1s-12).
///
/// `v` is the row-major `m×n` count matrix (m channels × n samples), as
/// marshalled by the FFI adapter from R's `t(counts)`. The fit is the plain
/// kernel call of the requested [`NmfVariant`] on `StreamId::ZERO` —
/// bit-identical to the engine golden path — plus the one shape rule the
/// kernel cannot know: a rank-`k` factorization needs `k ≤ min(m, n)`.
pub fn extract(
    v: &[f64],
    m: usize,
    n: usize,
    k: usize,
    max_iter: usize,
    seed: u64,
    variant: NmfVariant,
) -> Result<nmf::NmfFit, MsError> {
    let bound = m.min(n);
    if k > bound {
        return Err(MsError::new(
            "argument",
            format!(
                "k = {k} exceeds min(channels, samples) = {bound}: a rank-k NMF needs k <= min(m, n)"
            ),
        )
        .with_i(k as i64)
        .with_j(bound as i64));
    }
    match variant {
        NmfVariant::Kl => nmf::fit_kl(v, m, n, k, max_iter, seed),
        NmfVariant::Eu => nmf::fit_eu(v, m, n, k, max_iter, seed),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use msuiter_engine::rng::{MsRng, StreamId};

    /// Uniform f64 in [0, 1) from the in-house generator (test data only).
    fn uniform(rng: &mut MsRng) -> f64 {
        ((rng.next_u64() >> 11) as f64) * (1.0 / (1u64 << 53) as f64)
    }

    /// Integer-valued counts with structural zeros, row-major `m×n`.
    fn random_counts(seed: u64, m: usize, n: usize) -> Vec<f64> {
        let mut rng = MsRng::from_stream(seed, StreamId { replicate: 7, rank: 7, fold: 7 });
        (0..m * n)
            .map(|i| {
                if i % 19 == 0 {
                    0.0
                } else {
                    (uniform(&mut rng) * 40.0).floor()
                }
            })
            .collect()
    }

    fn cosine(a: &[f64], b: &[f64]) -> f64 {
        let dot: f64 = a.iter().zip(b.iter()).map(|(&x, &y)| x * y).sum();
        let na: f64 = a.iter().map(|x| x * x).sum::<f64>().sqrt();
        let nb: f64 = b.iter().map(|x| x * x).sum::<f64>().sqrt();
        dot / (na * nb)
    }

    // ------------------------------------------------------------------
    // The extraction core is pure plumbing over the kernels: it must agree
    // bit-for-bit with the engine on the zero stream (same seeded init,
    // same loop), so every kernel golden transfers to this face.
    // ------------------------------------------------------------------
    #[test]
    fn extract_matches_kernel_zero_stream_bit_exact() {
        let v = random_counts(11, 7, 4); // asymmetric: a transposed handoff breaks this
        let fit = extract(&v, 7, 4, 2, 25, 42, NmfVariant::Kl).unwrap();
        let reference = nmf::fit_kl(&v, 7, 4, 2, 25, 42).unwrap();
        assert_eq!(fit, reference);
        assert_eq!(fit.w.len(), 7 * 2);
        assert_eq!(fit.h.len(), 2 * 4);
        assert_eq!(fit.objective.len(), 26);
        assert_eq!(fit.iterations, 25);
        // The EU switch reaches fit_eu on the same stream, not KL in disguise.
        let eu = extract(&v, 7, 4, 2, 25, 42, NmfVariant::Eu).unwrap();
        assert_eq!(eu, nmf::fit_eu(&v, 7, 4, 2, 25, 42).unwrap());
        assert_ne!(eu, fit, "variants must be distinct fits");
    }

    /// Variant names from the R side parse explicitly (contract 4).
    #[test]
    fn variant_names_parse_explicitly() {
        assert_eq!(NmfVariant::parse("kl").unwrap(), NmfVariant::Kl);
        assert_eq!(NmfVariant::parse("eu").unwrap(), NmfVariant::Eu);
        let err = NmfVariant::parse("hals").unwrap_err();
        assert_eq!(err.topic(), "argument");
        assert!(err.to_string().contains("\"kl\", \"eu\""));
    }

    // ------------------------------------------------------------------
    // Shape rule: k must satisfy 1 <= k <= min(m, n); the error carries
    // i = k, j = the bound (contract 4 payload).
    // ------------------------------------------------------------------
    #[test]
    fn k_above_min_mn_is_a_structured_argument_error() {
        let v = random_counts(5, 6, 3);
        let err = extract(&v, 6, 3, 4, 10, 1, NmfVariant::Kl).unwrap_err();
        assert_eq!(err.topic(), "argument");
        assert_eq!(err.i, Some(4));
        assert_eq!(err.j, Some(3));
        // The boundary k == min(m, n) itself is legal.
        assert!(extract(&v, 6, 3, 3, 3, 1, NmfVariant::Kl).is_ok());
        // k = 0 is rejected by the kernel's shape validation.
        assert_eq!(extract(&v, 6, 3, 0, 1, 1, NmfVariant::Kl).unwrap_err().topic(), "argument");
    }

    // ------------------------------------------------------------------
    // Objective descent: the MM property across the FFI face — the final
    // objective is strictly below the initializer's and the trace stays
    // finite.
    // ------------------------------------------------------------------
    #[test]
    fn objective_descends_and_stays_finite() {
        let v = random_counts(23, 12, 9);
        let fit = extract(&v, 12, 9, 3, 50, 9, NmfVariant::Kl).unwrap();
        assert!(fit.objective.iter().all(|x| x.is_finite()));
        assert!(fit.objective[50] < fit.objective[0], "fit did not descend");
        for t in 1..fit.objective.len() {
            let slack = 1e-9 * (1.0 + fit.objective[t - 1].abs());
            assert!(fit.objective[t] <= fit.objective[t - 1] + slack);
        }
    }

    // ------------------------------------------------------------------
    // End-to-end recovery through the extraction face on the acceptance
    // workload shape (96 channels × 12 samples, k = 3, ASYMMETRIC): a
    // separable truth reconstructs to cosine >= 0.99. This is the Rust-side
    // twin of the R smoke in tests/testthat/test-extract.R.
    // ------------------------------------------------------------------
    #[test]
    fn separable_recovery_through_extract_face() {
        let (m, n, k) = (96usize, 12usize, 3usize);
        let mut rng = MsRng::from_stream(0x51C, StreamId { replicate: 2, rank: 2, fold: 2 });
        // Separable dictionary: 32 exclusive anchor channels per signature.
        let mut w_true = vec![0.0f64; m * k];
        for s in 0..k {
            let mut col: Vec<f64> = (0..m)
                .map(|i| if i / 32 == s { 0.5 + uniform(&mut rng) } else { 0.0 })
                .collect();
            let sum: f64 = col.iter().sum();
            for x in col.iter_mut() {
                *x /= sum;
            }
            for i in 0..m {
                w_true[i * k + s] = col[i];
            }
        }
        // 12 samples in four groups of 3: three near-pure groups pin the
        // dictionary rays, one fully mixed group.
        let mut h_true = vec![0.0f64; k * n];
        for j in 0..n {
            let dom = j / 3;
            for s in 0..k {
                h_true[s * n + j] = if dom == 3 || s == dom {
                    500.0 + 1000.0 * uniform(&mut rng)
                } else {
                    50.0 * uniform(&mut rng)
                };
            }
        }
        // Row-major V = W·H.
        let mut v = vec![0.0f64; m * n];
        for i in 0..m {
            for s in 0..k {
                for j in 0..n {
                    v[i * n + j] += w_true[i * k + s] * h_true[s * n + j];
                }
            }
        }
        let fit = extract(&v, m, n, k, 500, 42, NmfVariant::Kl).unwrap();
        let mut wh = vec![0.0f64; m * n];
        for i in 0..m {
            for s in 0..k {
                for j in 0..n {
                    wh[i * n + j] += fit.w[i * k + s] * fit.h[s * n + j];
                }
            }
        }
        let recon = cosine(&v, &wh);
        assert!(recon >= 0.99, "extraction reconstruction cosine {recon}");
    }
}
