//! Default extraction pipeline orchestration (U-M2-03): the pure (R-type-
//! free) heart of `ms_pipeline_rust` behind the D16 default path of
//! `ms_extract(method = NULL)` and the K-evidence face of `ms_select_k()`.
//!
//! Pipeline order (design memo
//! `docs/devlog/2026-09-30-M2-pipeline-design-memo.md` §1/§2/§4; ARCHITECTURE
//! §5 framework component "共识-CV 提取流水线"):
//!
//! 1. **Ensemble** — [`replicates::nmf_ensemble`], the multi-initialization
//!    axis only (PI ruling: no bootstrap resampling). Each replicate fits
//!    the untouched KL kernel on its own canonical stream, in parallel
//!    between units on the per-call pool.
//! 2. **Stacking** — each replicate's `W` is column-normalized to sum 1
//!    before stacking (upstream `pnmf`, memo §1.1; cosine is scale-
//!    invariant so the reassignment itself is unaffected, but the consensus
//!    centroids — within-cluster *means* — follow the upstream convention).
//!    A degenerate all-zero signature column keeps its zeros (the zero-
//!    vector cosine convention of `engine::consensus` handles it).
//! 3. **Consensus** — [`consensus::consensus_cluster`], the iterative
//!    Hungarian reassignment with silhouette convergence, run sequentially
//!    on the calling thread: a bounded, fixed-order computation with no
//!    internal parallelism (its determinism is inherited, not re-proven).
//!    Restarts draw `StreamId { replicate: restart, rank: k, fold: 0 }` —
//!    disjoint from the ensemble streams (rank axis 0 there).
//! 4. **Per-sample NNLS refit** — the consensus centroids fixed, every
//!    sample's exposures are the non-negative least squares solution in
//!    K-format ([`nnls::nnls_gram`], `G = WᵀW`, `b_j = Wᵀ v_j`), the
//!    upstream `fit_signatures_pool` step (memo §1.4). Sequential over
//!    samples, deterministic (first-index tie-breaks).
//! 5. **CV evidence** — [`cv::cv_error`] on the rank grid `1..=k`
//!    (SUITOR semantics: per-column rotated fold masks, row-median initial
//!    imputation, ECM conditional-mean refills, held-out Poisson deviance;
//!    memo §2). Streams `StreamId { replicate: seed, rank, fold ≥ 1 }` are
//!    disjoint from both the ensemble (fold 0, rank 0) and the consensus
//!    restarts (fold 0). CV budget note: `n_seeds` defaults to 10 on the R
//!    side (PI-ruled divergence from the upstream 30, memo fork 3).
//!
//! # Threads and interrupt (contracts 6/7)
//!
//! Phase 1 polls chunk boundaries exactly like the replicates driver
//! (workers see only the `cancelled` flag). Phases 2–5 are bounded
//! sequential computations (consensus restarts are capped, NNLS is one
//! small active-set solve per sample, the CV grid is `k·k_folds·n_seeds`
//! capped ECM runs): the export is declared bounded-duration and
//! non-interruptible WITHIN those phases, polled only around the ensemble
//! — the same documented trade as `ms_extract_rust`, revisited per phase
//! because the ensemble dominates the wall clock.
//!
//! # Determinism
//!
//! Every phase is a pure function of `(v, m, n, k, replicates, max_iter,
//! master_seed, k_folds, n_seeds)`: disjoint seeded streams, fixed
//! reduction orders, no shared generator state. The thread count only
//! changes the scheduling of whole units, never any arithmetic (pinned by
//! the `threads ∈ {1, 4}` identity tests).

use std::sync::atomic::AtomicBool;

use msuiter_engine::consensus::{consensus_cluster, ConsensusConfig, ConsensusFit};
use msuiter_engine::cv::{self, CvResult};
use msuiter_engine::error::MsError;
use msuiter_engine::nnls::{self, NnlsOptions};

use super::replicates;

/// Upstream restart/round defaults of the consensus layer (memo §1.2:
/// `parallel_clustering(iterations=50)` and `convergence_count == 10`).
const CONSENSUS_RESTARTS: usize = 50;
const CONSENSUS_MAX_ROUNDS: usize = 10;

/// One pipeline run at a single rank `k`.
#[derive(Debug, Clone, PartialEq)]
pub struct PipelineFit {
    /// Consensus signature matrix, row-major `m×k` (raw within-cluster
    /// means of the stacked, column-normalized replicate signatures).
    pub consensus_w: Vec<f64>,
    /// Per-cluster (per consensus signature) stability of the winning
    /// restart (`k` values).
    pub cluster_stability: Vec<f64>,
    /// Mean silhouette over all stacked signatures of the winning restart.
    pub avg_stability: f64,
    /// Index of the winning consensus restart (evidence transparency).
    pub best_restart: usize,
    /// Reassignment rounds of the winning restart.
    pub n_rounds: usize,
    /// Whether the winning restart stopped on exact silhouette equality.
    pub converged: bool,
    /// Refit exposures, row-major `k×n` (sample `j`'s NNLS solution in
    /// column `j`), against the RAW consensus centroids.
    pub nnls_h: Vec<f64>,
    /// CV test totals `CV.te` for ranks `1..=k` (upstream aggregation:
    /// per-fold seed picked by training error, folds summed; `None` = no
    /// finite seed in any fold).
    pub cv_per_rank: Vec<Option<f64>>,
    /// CV training totals for ranks `1..=k` (same aggregation shape).
    pub cv_per_rank_train: Vec<Option<f64>>,
    /// Per-(rank, fold) held-out deviance of the selected seed, ranks
    /// `1..=k` × folds `0..k_folds`, row-major by rank (`None` = the fold
    /// had no finite seed).
    pub fold_test: Vec<Option<f64>>,
    /// First-minimum rank of `cv_per_rank` (lowest rank on ties), if any.
    pub argmin_rank: Option<usize>,
}

/// Scalar/domain validation shared by the FFI adapter and tests (contract
/// 4: structured errors before any unit runs — the ensemble must not burn
/// a thread pool on a request that the CV grid would reject anyway).
fn validate_inputs(
    m: usize,
    n: usize,
    k: usize,
    replicates: usize,
    max_iter: usize,
    k_folds: usize,
    n_seeds: usize,
) -> Result<(), MsError> {
    let bound = m.min(n);
    if k == 0 || k > bound {
        return Err(MsError::new(
            "argument",
            format!(
                "k = {k} must be in [1, min(channels, samples) = {bound}]: a rank-k NMF needs k <= min(m, n)"
            ),
        )
        .with_i(k as i64)
        .with_j(bound as i64));
    }
    if replicates < 2 {
        return Err(MsError::new(
            "argument",
            "replicates must be at least 2: the consensus silhouette needs two members per cluster",
        )
        .with_i(replicates as i64));
    }
    if max_iter == 0 {
        return Err(MsError::new("argument", "max_iter must be positive"));
    }
    if k_folds < 2 {
        return Err(MsError::new(
            "argument",
            "k_folds must be at least 2 (upstream check_op)",
        ));
    }
    if k_folds > m {
        return Err(MsError::new(
            "argument",
            "k_folds must not exceed the channel count (every fold must hold out at least one row per column)",
        ));
    }
    if n_seeds == 0 {
        return Err(MsError::new("argument", "n_seeds must be positive"));
    }
    Ok(())
}

/// Run the full consensus-CV pipeline of one rank `k` (module docs for the
/// phase semantics and the stream layout).
///
/// `v` is the row-major `m×n` count matrix as marshalled by the FFI
/// adapter from R's `t(counts)`. Content validation (finite, non-negative)
/// is delegated to the kernels and surfaces from the first offending unit
/// with its 1-based payload, exactly like the replicates driver.
///
/// Errors: `"argument"` for the scalar/domain violations above or a
/// degenerate matrix, kernel errors re-thrown unchanged (contract 5:
/// `Result` everywhere, no partial results).
#[allow(clippy::too_many_arguments)]
pub fn run_pipeline(
    v: &[f64],
    m: usize,
    n: usize,
    k: usize,
    replicates: usize,
    max_iter: usize,
    master_seed: u64,
    k_folds: usize,
    n_seeds: usize,
    n_threads: usize,
    cancelled: &AtomicBool,
    check_user_interrupt: &mut dyn FnMut(),
) -> Result<PipelineFit, MsError> {
    if m == 0 || n == 0 {
        return Err(MsError::new(
            "argument",
            "matrix dimensions must be positive",
        ));
    }
    if v.len() != m * n {
        return Err(MsError::new(
            "bounds",
            format!(
                "counts buffer has {} entries, expected m*n = {m}*{n} = {}",
                v.len(),
                m * n
            ),
        ));
    }
    validate_inputs(m, n, k, replicates, max_iter, k_folds, n_seeds)?;

    // --- Phase 1: parallel ensemble (chunk-boundary interrupt protocol) ---
    let factors = replicates::nmf_ensemble(
        v,
        m,
        n,
        k,
        max_iter,
        master_seed,
        replicates,
        n_threads,
        cancelled,
        check_user_interrupt,
    )?;

    // --- Phase 2: stack column-normalized replicate signatures -----------
    // (upstream pnmf: W columns to sum 1 before stacking; a zero column
    // keeps its zeros — the zero-vector cosine convention absorbs it).
    let k_total = k * replicates;
    let mut stacked = vec![0.0f64; m * k_total];
    for (r, (w, _h)) in factors.iter().enumerate() {
        let mut col_sums = vec![0.0f64; k];
        for c in 0..k {
            for i in 0..m {
                col_sums[c] += w[i * k + c];
            }
        }
        for i in 0..m {
            for c in 0..k {
                let value = if col_sums[c] > 0.0 {
                    w[i * k + c] / col_sums[c]
                } else {
                    0.0
                };
                stacked[i * k_total + r * k + c] = value;
            }
        }
    }

    // --- Phase 3: consensus (sequential, bounded) ------------------------
    let fit: ConsensusFit = consensus_cluster(
        &stacked,
        m,
        k,
        ConsensusConfig {
            master_seed,
            n_restarts: CONSENSUS_RESTARTS,
            max_rounds: CONSENSUS_MAX_ROUNDS,
        },
    )?;

    // --- Phase 4: per-sample NNLS refit in K-format ----------------------
    // G = WᵀW (k×k, row-major symmetric); b_j = Wᵀ v_j (k) per sample.
    let w = &fit.centroids;
    let mut gram = vec![0.0f64; k * k];
    for a in 0..k {
        for b in a..k {
            let mut acc = 0.0f64;
            for i in 0..m {
                acc += w[i * k + a] * w[i * k + b];
            }
            gram[a * k + b] = acc;
            gram[b * k + a] = acc;
        }
    }
    let mut nnls_h = vec![0.0f64; k * n];
    let opts = NnlsOptions::default();
    for j in 0..n {
        let mut b = vec![0.0f64; k];
        for i in 0..m {
            let vij = v[i * n + j];
            if vij != 0.0 {
                for a in 0..k {
                    b[a] += w[i * k + a] * vij;
                }
            }
        }
        let sol = nnls::nnls_gram(&gram, &b, k, &opts)?;
        for a in 0..k {
            nnls_h[a * n + j] = sol.x[a];
        }
    }

    // --- Phase 5: SUITOR CV evidence on the rank grid 1..=k --------------
    let cv: CvResult = cv::cv_error(v, m, n, k, k_folds, n_seeds, max_iter, master_seed)?;

    Ok(PipelineFit {
        consensus_w: fit.centroids,
        cluster_stability: fit.cluster_stability,
        avg_stability: fit.avg_stability,
        best_restart: fit.best_restart,
        n_rounds: fit.n_rounds,
        converged: fit.converged,
        nnls_h,
        cv_per_rank: cv.per_rank_cv,
        cv_per_rank_train: cv.per_rank_cv_tr,
        fold_test: cv.per_rank_fold_te,
        argmin_rank: cv.argmin_rank,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use msuiter_engine::rng::{MsRng, StreamId};
    use std::sync::atomic::Ordering;

    const M: usize = 24;
    const N: usize = 9;
    const K: usize = 2;
    const REPLICATES: usize = 4;
    const MAX_ITER: usize = 40;
    const K_FOLDS: usize = 3;
    const N_SEEDS: usize = 2;
    const MASTER: u64 = 42;

    fn no_poll() {}

    fn run(v: &[f64], n_threads: usize, k: usize) -> Result<PipelineFit, MsError> {
        let cancelled = AtomicBool::new(false);
        run_pipeline(
            v,
            M,
            N,
            k,
            REPLICATES,
            MAX_ITER,
            MASTER,
            K_FOLDS,
            N_SEEDS,
            n_threads,
            &cancelled,
            &mut no_poll,
        )
    }

    /// Separable truth with `k_true` signatures, `m/k_true` exclusive
    /// anchor channels each, near-pure sample groups (the engine CV smoke
    /// construction; deterministic via the in-house generator).
    fn separable_counts(m: usize, n: usize, k_true: usize) -> Vec<f64> {
        let mut rng = MsRng::from_stream(
            0x51C,
            StreamId {
                replicate: 3,
                rank: 3,
                fold: 3,
            },
        );
        let uniform =
            |rng: &mut MsRng| ((rng.next_u64() >> 11) as f64) * (1.0 / (1u64 << 53) as f64);
        let anchors = m / k_true;
        let mut w = vec![0.0f64; m * k_true];
        for s in 0..k_true {
            let mut col: Vec<f64> = (0..m)
                .map(|i| {
                    if i / anchors == s {
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
                w[i * k_true + s] = col[i];
            }
        }
        let mut h = vec![0.0f64; k_true * n];
        for j in 0..n {
            let dom = j * k_true / n;
            for s in 0..k_true {
                h[s * n + j] = if s == dom {
                    600.0 + 600.0 * uniform(&mut rng)
                } else {
                    15.0 * uniform(&mut rng)
                };
            }
        }
        let mut v = vec![0.0f64; m * n];
        for i in 0..m {
            for s in 0..k_true {
                let ws = w[i * k_true + s];
                if ws == 0.0 {
                    continue;
                }
                for j in 0..n {
                    v[i * n + j] += ws * h[s * n + j];
                }
            }
        }
        v
    }

    fn cosine(a: &[f64], b: &[f64]) -> f64 {
        let dot: f64 = a.iter().zip(b.iter()).map(|(&x, &y)| x * y).sum();
        let na: f64 = a.iter().map(|x| x * x).sum::<f64>().sqrt();
        let nb: f64 = b.iter().map(|x| x * x).sum::<f64>().sqrt();
        dot / (na * nb)
    }

    // ------------------------------------------------------------------
    // End-to-end: the separable k = 2 truth reconstructs through the
    // consensus + refit factors and the CV argmin lands on the true rank.
    // ------------------------------------------------------------------
    #[test]
    fn pipeline_recovers_separable_truth_and_pins_cv_argmin() {
        let v = separable_counts(M, N, K);
        let fit = run(&v, 2, K).unwrap();
        // Shapes.
        assert_eq!(fit.consensus_w.len(), M * K);
        assert_eq!(fit.nnls_h.len(), K * N);
        assert_eq!(fit.cluster_stability.len(), K);
        assert_eq!(fit.cv_per_rank.len(), K);
        assert_eq!(fit.fold_test.len(), K * K_FOLDS);
        // Consensus is tight on separable data (stable replicates agree).
        assert!(fit.avg_stability > 0.9, "avg {}", fit.avg_stability);
        // Refit reconstruction cosine gate.
        let mut wh = vec![0.0f64; M * N];
        for i in 0..M {
            for s in 0..K {
                let ws = fit.consensus_w[i * K + s];
                if ws == 0.0 {
                    continue;
                }
                for j in 0..N {
                    wh[i * N + j] += ws * fit.nnls_h[s * N + j];
                }
            }
        }
        let recon = cosine(&v, &wh);
        assert!(recon >= 0.98, "pipeline reconstruction cosine {recon}");
        // Exposures are non-negative and non-degenerate (every sample group
        // carries mass on its dominant signature).
        assert!(fit.nnls_h.iter().all(|&x| x.is_finite() && x >= 0.0));
        assert!(fit.nnls_h.iter().any(|&x| x > 0.0));
        // CV evidence: argmin on the separable truth is the true rank.
        assert_eq!(fit.argmin_rank, Some(K), "cv = {:?}", fit.cv_per_rank);
        assert!(fit
            .cv_per_rank
            .iter()
            .all(|c| matches!(c, Some(x) if x.is_finite())));
    }

    // ------------------------------------------------------------------
    // Determinism and thread-count invariance: same inputs, threads
    // ∈ {1, 4} → bit-identical PipelineFit (A7/contract 6 across the whole
    // pipeline: the parallel phase schedules whole units only).
    // ------------------------------------------------------------------
    #[test]
    fn pipeline_is_deterministic_and_thread_invariant() {
        let v = separable_counts(M, N, K);
        let one = run(&v, 1, K).unwrap();
        let four = run(&v, 4, K).unwrap();
        assert_eq!(one, four);
        let again = run(&v, 1, K).unwrap();
        assert_eq!(one, again);
        // A different master seed moves every stream (ensemble, consensus
        // restarts and CV alike) — the result is seed-separated.
        let cancelled = AtomicBool::new(false);
        let other = run_pipeline(
            &v,
            M,
            N,
            K,
            REPLICATES,
            MAX_ITER,
            MASTER + 1,
            K_FOLDS,
            N_SEEDS,
            1,
            &cancelled,
            &mut no_poll,
        )
        .unwrap();
        assert_ne!(one.consensus_w, other.consensus_w);
    }

    // ------------------------------------------------------------------
    // Structure: consensus per-cluster stability lies in [-1, 1], the
    // k = 1 pipeline takes the all-ones silhouette convention, and the
    // refit exposures are exact NNLS solutions of the returned W.
    // ------------------------------------------------------------------
    #[test]
    fn pipeline_structure_stability_bounds_rank1_and_exact_refit() {
        let v = separable_counts(M, N, K);
        let fit = run(&v, 1, K).unwrap();
        for &s in &fit.cluster_stability {
            assert!((-1.0..=1.0).contains(&s), "stability {s} out of range");
        }
        assert!(fit.avg_stability <= 1.0);

        // Rank 1: the consensus convention gives every stacked signature
        // silhouette 1.0 → avg/min stability exactly 1.
        let one = run(&v, 1, 1).unwrap();
        assert_eq!(one.cluster_stability, vec![1.0]);
        assert_eq!(one.avg_stability, 1.0);
        assert_eq!(one.cv_per_rank.len(), 1);

        // The refit is the exact K-format NNLS of the returned consensus W:
        // recompute G and b here and re-solve; the exposures must match
        // bit for bit (same kernel, same input order).
        let k = K;
        let mut gram = vec![0.0f64; k * k];
        for a in 0..k {
            for b in a..k {
                let acc: f64 = (0..M)
                    .map(|i| fit.consensus_w[i * k + a] * fit.consensus_w[i * k + b])
                    .sum();
                gram[a * k + b] = acc;
                gram[b * k + a] = acc;
            }
        }
        for j in 0..N {
            let b: Vec<f64> = (0..k)
                .map(|a| {
                    (0..M)
                        .map(|i| fit.consensus_w[i * k + a] * v[i * N + j])
                        .sum()
                })
                .collect();
            let sol = nnls::nnls_gram(&gram, &b, k, &NnlsOptions::default()).unwrap();
            let col: Vec<f64> = (0..k).map(|a| fit.nnls_h[a * N + j]).collect();
            assert_eq!(col, sol.x, "sample {j} exposure is not the NNLS solution");
        }
    }

    // ------------------------------------------------------------------
    // Error paths: k bounds (i = k, j = min(m, n) payload), replicates < 2,
    // k_folds < 2, k_folds > channels, n_seeds = 0, max_iter = 0, shape
    // mismatch, and the kernel content error surfacing (negative entry).
    // ------------------------------------------------------------------
    #[test]
    fn pipeline_scalar_and_domain_errors_are_structured() {
        let v = separable_counts(M, N, K);
        assert_eq!(run(&v, 1, 0).unwrap_err().topic, "argument");
        let err = run(&v, 1, M.min(N) + 1).unwrap_err();
        assert_eq!(err.topic, "argument");
        assert_eq!(err.i, Some((M.min(N) + 1) as i64));
        assert_eq!(err.j, Some(M.min(N) as i64));

        let cancelled = AtomicBool::new(false);
        let mk = |replicates: usize, k_folds: usize, n_seeds: usize, max_iter: usize| {
            run_pipeline(
                &v,
                M,
                N,
                K,
                replicates,
                max_iter,
                MASTER,
                k_folds,
                n_seeds,
                1,
                &cancelled,
                &mut no_poll,
            )
            .unwrap_err()
            .topic
        };
        assert_eq!(mk(1, K_FOLDS, N_SEEDS, MAX_ITER), "argument");
        assert_eq!(mk(REPLICATES, 1, N_SEEDS, MAX_ITER), "argument");
        assert_eq!(mk(REPLICATES, M + 1, N_SEEDS, MAX_ITER), "argument");
        assert_eq!(mk(REPLICATES, K_FOLDS, 0, MAX_ITER), "argument");
        assert_eq!(mk(REPLICATES, K_FOLDS, N_SEEDS, 0), "argument");

        // Shape mismatch and negative content (contract 4 payloads).
        assert_eq!(
            run_pipeline(
                &v[..v.len() - 1],
                M,
                N,
                K,
                REPLICATES,
                MAX_ITER,
                MASTER,
                K_FOLDS,
                N_SEEDS,
                1,
                &cancelled,
                &mut no_poll,
            )
            .unwrap_err()
            .topic,
            "bounds"
        );
        let mut bad = v.clone();
        bad[5] = -1.0;
        let err = run(&bad, 1, K).unwrap_err();
        assert_eq!(err.topic, "argument");
        assert_eq!(err.i, Some(1));
        assert_eq!(err.j, Some(6));
    }

    // ------------------------------------------------------------------
    // Interrupt protocol: a pre-set flag fails the whole call before the
    // first ensemble chunk (contract 5: no partial results); a trip in the
    // boundary poll fails at the next boundary with the worker-side topic.
    // ------------------------------------------------------------------
    #[test]
    fn pipeline_interrupt_flag_fails_before_any_output() {
        let v = separable_counts(M, N, K);
        let cancelled = AtomicBool::new(true);
        let err = run_pipeline(
            &v,
            M,
            N,
            K,
            REPLICATES,
            MAX_ITER,
            MASTER,
            K_FOLDS,
            N_SEEDS,
            2,
            &cancelled,
            &mut no_poll,
        )
        .unwrap_err();
        assert_eq!(err.topic, "interrupted");
        assert_eq!(err.i, Some(1));

        let cancelled = AtomicBool::new(false);
        let mut polls = 0usize;
        let err = run_pipeline(
            &v,
            M,
            N,
            K,
            REPLICATES,
            MAX_ITER,
            MASTER,
            K_FOLDS,
            N_SEEDS,
            1,
            &cancelled,
            &mut || {
                polls += 1;
                if polls == 1 {
                    cancelled.store(true, Ordering::Relaxed);
                }
            },
        )
        .unwrap_err();
        assert_eq!(polls, 1);
        assert_eq!(err.topic, "interrupted");
        assert!(err.to_string().contains("worker observed"));
    }
}
