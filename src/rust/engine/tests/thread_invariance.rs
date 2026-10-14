//! P1 kernel-extension face (c): thread-count invariance `identical()` suite.
//!
//! The ARCH §2.6 contract (docs/ARCHITECTURE.md §2, the report-checklist
//! promise "the thread count [promised not to affect the result]") states
//! that the engine kernels are pure functions of their explicit inputs: the
//! FFI shell pins this at the driver level with
//! `replicates_are_invariant_to_thread_count` (src/rust/src/replicates.rs,
//! rayon per-call pools), but the kernel itself never pinned it against a
//! hostile host-thread placement. The kernel is single-threaded by
//! construction (fixed loop order, sequential reductions, no parallelism, no
//! hashing — nmf.rs module docs "Determinism"); this suite makes that a
//! committed, executable fact: the same call executed concurrently on many
//! spawned OS threads with scrambled scheduling must be bit-identical
//! (`assert_eq!`, not tolerance) to the sequential reference, for
//! `fit_kl`/`fit_eu` (seeded init) and for the stream-addressed face
//! `fit_kl_on_stream` used by the parallel replicate drivers.
//!
//! P1 context: docs/research/09-sigminer-v3-parity-plan.md §5 row P1
//! ("thread-count invariance `identical()`"). This file is the
//! msuiter-side kernel-extension face of that gate; the sigminer-side
//! isolated-process wiring is the follow-on PR.

use std::thread;

use msuiter_engine::nmf::{fit_eu, fit_kl, fit_kl_on_stream, NmfFit};
use msuiter_engine::rng::{MsRng, StreamId};

/// Uniform f64 in [0, 1) from the in-house generator (test data only;
/// same construction as the nmf.rs in-crate test helpers).
fn uniform(rng: &mut MsRng) -> f64 {
    ((rng.next_u64() >> 11) as f64) * (1.0 / (1u64 << 53) as f64)
}

/// Random integer-valued counts in {0, ..., 39} (same recipe as the nmf.rs
/// unit tests, own stream so the two suites stay independent).
fn random_counts(rng: &mut MsRng, m: usize, n: usize) -> Vec<f64> {
    (0..m * n)
        .map(|_| (uniform(rng) * 40.0).floor())
        .collect()
}

const M: usize = 20;
const N: usize = 14;
const K: usize = 3;
const ITERS: usize = 40;

fn fixture() -> Vec<f64> {
    let mut rng = MsRng::from_stream(5, StreamId { replicate: 21, rank: 7, fold: 3 });
    random_counts(&mut rng, M, N)
}

/// Run `f` once on the calling thread and once per spawned worker thread,
/// with `jobs` concurrent copies of the closure, and return every produced
/// value. Workers get interleaved by the OS scheduler; nothing here
/// synchronizes them beyond `join`, so a hidden dependency on shared,
/// thread-visit-order-sensitive state (a global pool, a lazy cache keyed on
/// thread id) would surface as a value difference.
fn fan_out<T: Send + 'static>(jobs: usize, f: impl Fn() -> T + Send + Sync + Clone) -> Vec<T> {
    thread::scope(|scope| {
        (0..jobs)
            .map(|_| scope.spawn(f.clone()))
            .collect::<Vec<_>>()
            .into_iter()
            .map(|h| h.join().expect("worker thread panicked"))
            .collect()
    })
}

#[test]
fn kl_fit_is_bit_identical_across_host_threads() {
    let v = fixture();
    let reference = fit_kl(&v, M, N, K, ITERS, 42).expect("reference fit");

    let got: Vec<NmfFit> = fan_out(8, {
        let v = v.clone();
        move || fit_kl(&v, M, N, K, ITERS, 42).expect("worker fit")
    });

    for (i, fit) in got.iter().enumerate() {
        assert_eq!(fit, &reference, "worker {i} diverged from the sequential fit");
    }
    // The trace and the iteration count are part of the bit contract.
    assert_eq!(got[0].objective.len(), ITERS + 1);
    assert_eq!(got[0].iterations, ITERS);
}

#[test]
fn eu_fit_is_bit_identical_across_host_threads() {
    let v = fixture();
    let reference = fit_eu(&v, M, N, K, ITERS, 42).expect("reference fit");

    let got = fan_out(8, {
        let v = v.clone();
        move || fit_eu(&v, M, N, K, ITERS, 42).expect("worker fit")
    });

    for (i, fit) in got.iter().enumerate() {
        assert_eq!(fit, &reference, "worker {i} diverged from the sequential EU fit");
    }
}

#[test]
fn replicate_stream_fits_survive_thread_scrambling() {
    // The parallel replicate drivers address replicate r on
    // StreamId { replicate: r, rank: 0, fold: 0 } (U-M1s-05). Sequential
    // reference first, then the same per-replicate calls fanned out across
    // threads in a scrambled order; every replicate must land bit-for-bit.
    let v = fixture();
    const R: usize = 6;
    let master = 42u64;

    let sequential: Vec<NmfFit> = (0..R as u64)
        .map(|r| {
            fit_kl_on_stream(
                &v,
                M,
                N,
                K,
                ITERS,
                master,
                StreamId { replicate: r, rank: 0, fold: 0 },
            )
            .expect("sequential replicate fit")
        })
        .collect();

    // Interleave the per-replicate jobs across worker threads: every worker
    // runs the replicate jobs in a rotated order so no two workers share a
    // (replicate, visit-position) alignment.
    let mut handles = Vec::new();
    for rot in 0..R {
        let v = v.clone();
        handles.push(
            thread::Builder::new()
                .name(format!("replicate-scrambler-{rot}"))
                .spawn(move || {
                    (0..R as u64)
                        .map(|i| {
                            let r = (i + rot as u64) % R as u64;
                            fit_kl_on_stream(
                                &v,
                                M,
                                N,
                                K,
                                ITERS,
                                master,
                                StreamId { replicate: r, rank: 0, fold: 0 },
                            )
                            .expect("worker replicate fit")
                        })
                        .collect::<Vec<NmfFit>>()
                })
                .expect("spawn"),
        );
    }
    for (rot, h) in handles.into_iter().enumerate() {
        let fits = h.join().expect("scrambler panicked");
        for (i, fit) in fits.iter().enumerate() {
            let r = ((i + rot) % R) as u64;
            assert_eq!(fit, &sequential[r as usize], "replicate {r} lost bits under scrambling");
        }
    }
}

#[test]
fn zero_iteration_probe_is_thread_invariant_too() {
    // The init-only path (max_iter = 0) exposes the raw initializer; it is
    // the piece the isolated-process boundary stamps for injection proofs,
    // so it shares the invariance contract.
    let v = fixture();
    let reference = fit_kl(&v, M, N, K, 0, 7).expect("reference");
    let got = fan_out(6, {
        let v = v.clone();
        move || fit_kl(&v, M, N, K, 0, 7).expect("worker")
    });
    for fit in &got {
        assert_eq!(fit, &reference);
    }
}
