//! Parallel replicate driver over the real KL-NMF kernel (U-M1s-05;
//! extended in U-M2-03 with the factor-pair ensemble).
//!
//! This is the first **real-kernel** application of the FFI concurrency
//! contract (`docs/ARCHITECTURE.md` §2, contracts 6 + 7): `replicates`
//! independent KL-NMF fits of one catalog run in parallel **between**
//! units, while every unit stays single-threaded with the kernel's own
//! fixed reduction order. Each replicate `r` draws its seeded initializer
//! from its own frozen PCG64 stream
//! `StreamId { replicate: r, rank: 0, fold: 0 }` (canonical layout v1), so
//! the output is a pure function of `(counts, k, max_iter, master_seed,
//! replicates)` — never of the thread count (A7 thread-count invariance).
//!
//! Two faces share one scheduling skeleton ([`run_units_in_chunks`]):
//!
//! * [`nmf_replicates_objectives`] — the U-M1s-05 face: one scalar per
//!   replicate (the final KL objective). Semantics frozen since U-M1s-05.
//! * [`nmf_ensemble`] — the U-M2-03 face: one `(W, H)` factor pair per
//!   replicate, the multi-initialization axis of the consensus pipeline
//!   (design memo `docs/devlog/2026-09-30-M2-pipeline-design-memo.md`
//!   §1.1, PI ruling: ensemble = initialization seeds only, no bootstrap).
//!   Same streams, same scheduling, same interrupt protocol — the ONLY
//!   delta is what each unit returns.
//!
//! # What is parallel, what never is
//!
//! * Parallel: whole replicates (the "independent units" of contract 6 —
//!   the replicate axis of the stability pipeline). Units share nothing:
//!   no generator state (disjoint streams), no scratch buffers (each unit
//!   allocates its own), no output slot (results are placed by replicate
//!   index).
//! * Never parallel: the inside of a fit. `engine::nmf` is a fixed-order
//!   sequential kernel and must stay one — in-unit floating-point
//!   accumulation order is part of the frozen numerics contract.
//!
//! # Reduction order
//!
//! Chunks are gathered in chunk-index order and each chunk lists its
//! replicates in index order; the final vector is the plain index-ordered
//! concatenation. There is NO order-sensitive floating-point reduction
//! anywhere: every element is computed by exactly one unit from that
//! unit's own stream, so `threads ∈ {1, N}` give bit-identical output.
//!
//! # Interrupt protocol (contract 7)
//!
//! The main thread polls `check_user_interrupt` (under R:
//! `R_CheckUserInterrupt`) at every chunk boundary, exactly like
//! `probes::run_interruptible_chunks`; workers see ONLY the `cancelled`
//! `AtomicBool` — never R state. Any cancellation (pre-set flag, worker
//! observation, or a boundary longjmp that never returns) fails the whole
//! call with the `interrupted` topic: stateless FFI (D12) means there is
//! nothing to clean up and no partial results to suppress downstream.

use std::sync::atomic::{AtomicBool, Ordering};

use rayon::prelude::*;

use msuiter_engine::error::MsError;
use msuiter_engine::nmf;
use msuiter_engine::rng::StreamId;

use super::probes::build_call_pool;

/// Generic chunked parallel driver over independent units (contract 6/7):
/// the scheduling skeleton shared by the objective replicates
/// ([`nmf_replicates_objectives`]) and the factor-pair ensemble
/// ([`nmf_ensemble`]). Units are scheduled in chunks (≈4 per worker,
/// capped); the main thread polls the interrupt hook between chunks, each
/// chunk runs its units in parallel on the per-call pool, and workers see
/// ONLY the `cancelled` flag. Chunks are gathered in chunk-index order and
/// every element is computed by exactly one unit from that unit's own
/// stream — no order-sensitive floating-point reduction anywhere, so
/// `threads ∈ {1, N}` give bit-identical output.
fn run_units_in_chunks<T, F>(
    units: usize,
    n_threads: usize,
    cancelled: &AtomicBool,
    check_user_interrupt: &mut dyn FnMut(),
    unit: F,
) -> Result<Vec<T>, MsError>
where
    T: Send,
    F: Fn(usize) -> Result<T, MsError> + Sync,
{
    let pool = build_call_pool(n_threads)?;
    let target_chunks = n_threads.clamp(1, 16) * 4;
    let chunk_len = ((units + target_chunks - 1) / target_chunks).max(1);
    let n_chunks = (units + chunk_len - 1) / chunk_len;

    let mut per_chunk: Vec<(usize, Vec<T>)> = Vec::with_capacity(n_chunks);
    for c in 0..n_chunks {
        // Worker-side view (contract 7): the flag is the ONLY cross-thread
        // signal; a tripped flag fails the whole call with no partial
        // results (contract 5).
        if cancelled.load(Ordering::Relaxed) {
            return Err(MsError::new(
                "interrupted",
                format!(
                    "call interrupted before chunk {}; no partial results are returned",
                    c + 1
                ),
            )
            .with_i((c + 1) as i64));
        }
        // Main-thread boundary poll (under R: R_CheckUserInterrupt).
        check_user_interrupt();
        let start = c * chunk_len;
        let end = (start + chunk_len).min(units);
        // Each element is one whole unit: kernel-sequential inside, parallel
        // only across elements (contract 6).
        let chunk: Vec<T> = pool.install(|| {
            (start..end)
                .into_par_iter()
                .map(|r| {
                    if cancelled.load(Ordering::Relaxed) {
                        return Err(MsError::new(
                            "interrupted",
                            format!("worker observed cancellation at replicate {}", r + 1),
                        )
                        .with_i((r + 1) as i64));
                    }
                    unit(r)
                })
                .collect::<Result<Vec<T>, MsError>>()
        })?;
        per_chunk.push((c, chunk));
    }

    // Fixed reduction: index-ordered concatenation — never an
    // order-sensitive floating-point accumulation (module docs).
    per_chunk.sort_unstable_by_key(|(c, _)| *c);
    let mut out = Vec::with_capacity(units);
    for (_, mut vals) in per_chunk {
        out.append(&mut vals);
    }
    debug_assert_eq!(out.len(), units);
    Ok(out)
}

/// Final KL objective of one replicate: an independent `fit_kl_on_stream`
/// run whose initializer is drawn from the replicate's own canonical
/// stream. Single-threaded by construction (the kernel is sequential);
/// this is the "unit" of the parallel driver below.
pub fn kl_replicate_objective(
    v: &[f64],
    m: usize,
    n: usize,
    k: usize,
    max_iter: usize,
    master_seed: u64,
    replicate: u64,
) -> Result<f64, MsError> {
    let fit = nmf::fit_kl_on_stream(
        v,
        m,
        n,
        k,
        max_iter,
        master_seed,
        StreamId { replicate, rank: 0, fold: 0 },
    )?;
    Ok(*fit.objective.last().expect("objective trace is never empty"))
}

/// Run `replicates` independent KL-NMF fits of `v` (row-major `m×n`) on a
/// per-call thread pool and return each replicate's final KL objective,
/// ordered by replicate index.
///
/// `n_threads == 0` means "rayon default" (all cores) — the R side resolves
/// the `msuiter.threads` option and the `_R_CHECK_LIMIT_CORES_` cap and
/// passes the effective value (see `probes::build_call_pool`).
///
/// Replicates are scheduled in chunks (≈4 per worker, capped): the main
/// thread polls the interrupt hook between chunks, and each chunk runs its
/// replicates in parallel on the pool. `cancelled` is the only cross-thread
/// signal; `check_user_interrupt` runs on the calling (main) thread only.
// The signature deliberately mirrors the engine kernel face (v, m, n, k,
// max_iter, seed) plus the scheduling/interrupt plumbing of contract 6/7;
// grouping them would hide the kernel-argument symmetry.
#[allow(clippy::too_many_arguments)]
pub fn nmf_replicates_objectives(
    v: &[f64],
    m: usize,
    n: usize,
    k: usize,
    max_iter: usize,
    master_seed: u64,
    replicates: usize,
    n_threads: usize,
    cancelled: &AtomicBool,
    check_user_interrupt: &mut dyn FnMut(),
) -> Result<Vec<f64>, MsError> {
    if replicates == 0 {
        return Err(MsError::new("argument", "replicates must be positive"));
    }
    run_units_in_chunks(
        replicates,
        n_threads,
        cancelled,
        check_user_interrupt,
        |r| kl_replicate_objective(v, m, n, k, max_iter, master_seed, r as u64),
    )
}

/// Run `replicates` independent KL-NMF fits of `v` (row-major `m×n`) on a
/// per-call thread pool and return each replicate's **factor pair**
/// `(W, H)` (W row-major `m×k`, H row-major `k×n`), ordered by replicate
/// index (U-M2-03 ensemble: the multi-initialization axis of the consensus
/// pipeline; design memo §1.1).
///
/// The parallel semantics are EXACTLY the objective driver's — same frozen
/// streams (`StreamId { replicate: r, rank: 0, fold: 0 }`, canonical
/// layout v1), same chunked scheduling, same interrupt protocol, same
/// index-ordered gather — extended only by returning each replicate's
/// factors instead of its final objective. The kernel face is
/// [`nmf::fit_kl_on_stream`], untouched: each replicate's W/H is
/// bit-identical to a sequential `fit_kl_on_stream` call on its stream
/// (A7 thread-count invariance is inherited, pinned by tests).
///
/// `n_threads == 0` means "rayon default" (all cores) — the R side resolves
/// the `msuiter.threads` option and the `_R_CHECK_LIMIT_CORES_` cap and
/// passes the effective value (see `probes::build_call_pool`).
#[allow(clippy::too_many_arguments)]
#[allow(clippy::type_complexity)]
pub fn nmf_ensemble(
    v: &[f64],
    m: usize,
    n: usize,
    k: usize,
    max_iter: usize,
    master_seed: u64,
    replicates: usize,
    n_threads: usize,
    cancelled: &AtomicBool,
    check_user_interrupt: &mut dyn FnMut(),
) -> Result<Vec<(Vec<f64>, Vec<f64>)>, MsError> {
    if replicates == 0 {
        return Err(MsError::new("argument", "replicates must be positive"));
    }
    run_units_in_chunks(
        replicates,
        n_threads,
        cancelled,
        check_user_interrupt,
        |r| {
            let fit = nmf::fit_kl_on_stream(
                v,
                m,
                n,
                k,
                max_iter,
                master_seed,
                StreamId { replicate: r as u64, rank: 0, fold: 0 },
            )?;
            Ok((fit.w, fit.h))
        },
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use msuiter_engine::rng::MsRng;

    /// Integer-valued counts with structural zeros (same generator family
    /// as the engine kernel tests), row-major `m×n`.
    fn synthetic_counts(seed: u64, m: usize, n: usize) -> Vec<f64> {
        let mut rng = MsRng::from_stream(seed, StreamId { replicate: 9, rank: 9, fold: 9 });
        (0..m * n)
            .map(|i| {
                if i % 17 == 0 {
                    0.0 // structural zeros exercise the ε paths
                } else {
                    ((rng.next_u64() >> 11) as f64 * (40.0 / (1u64 << 53) as f64)).floor()
                }
            })
            .collect()
    }

    /// Small problem size: 7 replicates × 15 iterations stay well under a
    /// second on any runner while still exercising multi-chunk scheduling.
    const M: usize = 12;
    const N: usize = 9;
    const K: usize = 2;
    const REPLICATES: usize = 7;
    const MAX_ITER: usize = 15;
    const MASTER: u64 = 42;

    fn no_poll() {}
    fn clean_run(n_threads: usize) -> Result<Vec<f64>, MsError> {
        let v = synthetic_counts(7, M, N);
        let cancelled = AtomicBool::new(false);
        nmf_replicates_objectives(
            &v, M, N, K, MAX_ITER, MASTER, REPLICATES, n_threads,
            &cancelled, &mut no_poll,
        )
    }

    #[test]
    fn replicates_match_sequential_reference() {
        let v = synthetic_counts(7, M, N);
        let reference: Result<Vec<f64>, MsError> = (0..REPLICATES as u64)
            .map(|r| kl_replicate_objective(&v, M, N, K, MAX_ITER, MASTER, r))
            .collect();
        assert_eq!(clean_run(1).unwrap(), reference.unwrap());
    }

    /// A7 / contract 6, on the real kernel: same seed, threads ∈ {1, 4,
    /// 16} → bit-identical objective vector (`assert_eq!`, not tolerance).
    #[test]
    fn replicates_are_invariant_to_thread_count() {
        let one = clean_run(1).unwrap();
        let four = clean_run(4).unwrap();
        let sixteen = clean_run(16).unwrap();
        assert_eq!(one, four);
        assert_eq!(one, sixteen);
        assert_eq!(one.len(), REPLICATES);
    }

    #[test]
    fn replicate_value_is_the_kernel_final_objective_of_its_stream() {
        let v = synthetic_counts(7, M, N);
        let got = clean_run(3).unwrap();
        for (r, &obj) in got.iter().enumerate() {
            let fit = nmf::fit_kl_on_stream(
                &v, M, N, K, MAX_ITER, MASTER,
                StreamId { replicate: r as u64, rank: 0, fold: 0 },
            )
            .unwrap();
            assert_eq!(obj, *fit.objective.last().unwrap());
            // MM property on the real path: the fit made progress from the
            // initializer (strict progress on this non-degenerate problem).
            assert!(obj < fit.objective[0], "replicate {r} did not descend");
            assert!(obj.is_finite());
        }
    }

    #[test]
    fn replicates_differ_across_streams_and_seeds() {
        let v = synthetic_counts(7, M, N);
        let base = clean_run(2).unwrap();
        for (i, &a) in base.iter().enumerate() {
            for &b in base[i + 1..].iter() {
                assert_ne!(a, b, "replicates {i} collided");
            }
        }
        let other_seed = {
            let cancelled = AtomicBool::new(false);
            nmf_replicates_objectives(
                &v, M, N, K, MAX_ITER, MASTER + 1, REPLICATES, 2,
                &cancelled, &mut no_poll,
            )
            .unwrap()
        };
        assert_ne!(base, other_seed);
    }

    #[test]
    fn polls_once_per_chunk_boundary_on_the_main_thread() {
        let v = synthetic_counts(7, M, N);
        let cancelled = AtomicBool::new(false);
        let mut polls = 0usize;
        nmf_replicates_objectives(
            &v, M, N, K, MAX_ITER, MASTER, REPLICATES, 1, &cancelled,
            &mut || polls += 1,
        )
        .unwrap();
        // 7 replicates, 1 thread → target 4 chunks → chunk_len = 2 →
        // chunks {2, 2, 2, 1}: one boundary poll each.
        assert_eq!(polls, 4);
    }

    #[test]
    fn pre_cancelled_flag_fails_the_whole_call_without_partial_results() {
        let v = synthetic_counts(7, M, N);
        let cancelled = AtomicBool::new(true);
        let err = nmf_replicates_objectives(
            &v, M, N, K, MAX_ITER, MASTER, REPLICATES, 2, &cancelled,
            &mut no_poll,
        )
        .unwrap_err();
        assert_eq!(err.topic, "interrupted");
        assert_eq!(err.i, Some(1));
    }

    #[test]
    fn flag_tripped_mid_run_fails_the_next_chunk() {
        let v = synthetic_counts(7, M, N);
        let cancelled = AtomicBool::new(false);
        let mut chunks = 0usize;
        let err = nmf_replicates_objectives(
            &v, M, N, K, MAX_ITER, MASTER, REPLICATES, 1, &cancelled,
            &mut || {
                chunks += 1;
                if chunks == 1 {
                    cancelled.store(true, Ordering::Relaxed);
                }
            },
        )
        .unwrap_err();
        // The trip happens in chunk 0's boundary poll, so chunk 0's own
        // workers observe the flag at unit start — the worker-side
        // contract-7 view: workers never see R state, only the flag — and
        // the whole call fails with no partial results (contract 5). (The
        // boundary refusal itself is covered by the pre-cancelled test.)
        assert_eq!(chunks, 1);
        assert_eq!(err.topic, "interrupted");
        assert_eq!(err.i, Some(1));
        assert!(err.to_string().contains("worker observed"));
    }

    #[test]
    fn argument_and_input_errors_fail_the_whole_call() {
        let v = synthetic_counts(7, M, N);
        let cancelled = AtomicBool::new(false);
        let mk = |replicates: usize, v: &[f64]| {
            nmf_replicates_objectives(
                v, M, N, K, MAX_ITER, MASTER, replicates, 2, &cancelled,
                &mut no_poll,
            )
        };
        assert_eq!(mk(0, &v).unwrap_err().topic, "argument");
        // Engine-side input validation surfaces through the driver (a
        // negative entry in counts) with its 1-based i/j payload.
        let mut bad = v.clone();
        bad[3] = -1.0;
        let err = mk(2, &bad).unwrap_err();
        assert_eq!(err.topic, "argument");
        assert_eq!(err.i, Some(1));
        assert_eq!(err.j, Some(4));
    }

    // ------------------------------------------------------------------
    // U-M2-03 ensemble (factor pairs): same scheduling contract, the unit
    // returns (W, H) instead of the objective.
    // ------------------------------------------------------------------

    fn ensemble_run(n_threads: usize) -> Vec<(Vec<f64>, Vec<f64>)> {
        let v = synthetic_counts(7, M, N);
        let cancelled = AtomicBool::new(false);
        nmf_ensemble(&v, M, N, K, MAX_ITER, MASTER, REPLICATES, n_threads, &cancelled, &mut no_poll)
            .unwrap()
    }

    #[test]
    fn ensemble_returns_one_factor_pair_per_replicate_on_frozen_streams() {
        let v = synthetic_counts(7, M, N);
        let got = ensemble_run(2);
        assert_eq!(got.len(), REPLICATES);
        for (r, (w, h)) in got.iter().enumerate() {
            // Shapes: W row-major m×k, H row-major k×n.
            assert_eq!(w.len(), M * K);
            assert_eq!(h.len(), K * N);
            // Bit-identical to the sequential kernel fit on the replicate's
            // own canonical stream (the ONLY semantic: same stream, same
            // kernel, raw factors returned untouched).
            let fit = nmf::fit_kl_on_stream(
                &v, M, N, K, MAX_ITER, MASTER,
                StreamId { replicate: r as u64, rank: 0, fold: 0 },
            )
            .unwrap();
            assert_eq!(*w, fit.w, "replicate {r} W drifted from its stream");
            assert_eq!(*h, fit.h, "replicate {r} H drifted from its stream");
        }
    }

    /// A7 / contract 6 on the ensemble face: threads ∈ {1, 4, 16} produce
    /// bit-identical factor pairs (`assert_eq!`, not tolerance).
    #[test]
    fn ensemble_is_invariant_to_thread_count() {
        let one = ensemble_run(1);
        let four = ensemble_run(4);
        let sixteen = ensemble_run(16);
        assert_eq!(one, four);
        assert_eq!(one, sixteen);
    }

    #[test]
    fn ensemble_replicates_differ_across_streams() {
        let got = ensemble_run(2);
        for (i, (wa, _)) in got.iter().enumerate() {
            for (wb, _) in got[i + 1..].iter() {
                assert_ne!(wa, wb, "replicates {i} collided (W)");
            }
        }
    }

    #[test]
    fn ensemble_argument_and_interrupt_paths_mirror_the_objective_driver() {
        let v = synthetic_counts(7, M, N);
        let cancelled = AtomicBool::new(true);
        let err = nmf_ensemble(
            &v, M, N, K, MAX_ITER, MASTER, REPLICATES, 2, &cancelled, &mut no_poll,
        )
        .unwrap_err();
        assert_eq!(err.topic, "interrupted");
        assert_eq!(err.i, Some(1));
        let cancelled = AtomicBool::new(false);
        let err = nmf_ensemble(
            &v, M, N, K, MAX_ITER, MASTER, 0, 2, &cancelled, &mut no_poll,
        )
        .unwrap_err();
        assert_eq!(err.topic, "argument");
    }
}
