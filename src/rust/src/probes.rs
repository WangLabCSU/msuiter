//! Pure cores of the FFI contract probes (U-M0-09).
//!
//! Everything in this module is plain Rust: no R types, no `unsafe`, no
//! algorithm kernels (NMF/NNLS & co. are M1s work and deliberately absent).
//! The `#[extendr]` wrappers in `lib.rs` are thin adapters that unpack R
//! objects, call these cores, and convert `Result<_, MsError>` into either
//! the value or an `msuiter_error_rust` condition object. Keeping the cores
//! pure makes every contract probe unit-testable with plain `cargo test`
//! (no embedded R), while the R-side testthat suite covers the end-to-end
//! mapping through the real FFI.
//!
//! Probe ↔ contract map (`docs/ARCHITECTURE.md` §2):
//! * `column_major_position_checksum` — contract 2 (column-major layout),
//! * `scan_no_nan`                    — contract 3 (NA/NaN rejection),
//! * `error_probe_bounds`             — contracts 4 + 5 (index bounds,
//!   `Result<_, MsError>` errors, no panics),
//! * `build_call_pool` / `thread_probe_values` — contract 6 (per-call
//!   thread pool, fixed reduction order, thread-count invariance),
//! * `run_interruptible_chunks`       — contract 7 (chunk-boundary
//!   interrupt polling, worker-side `AtomicBool` only).

use std::sync::atomic::{AtomicBool, Ordering};

use rayon::prelude::*;

use msuiter_engine::error::MsError;
use msuiter_engine::rng::{MsRng, StreamId};

// ---------------------------------------------------------------------------
// Contract 2 — column-major layout
// ---------------------------------------------------------------------------

/// Weighted positional checksum of a matrix read in **column-major** order.
///
/// This is the "asymmetric golden round-trip detector" of contract 2: the
/// checksum sums `(flat_position + 1) * value` over the R column-major
/// buffer, so any implementation that mistakenly reads the buffer row-major
/// (the classic transpose bug) assigns different weights to the same values
/// and produces a different scalar — for any non-square or asymmetrically
/// filled matrix. The R-side test compares against R's own column-major
/// flattening (`as.numeric(m)`), closing the golden round-trip.
///
/// The accumulation is sequential in flat position order — a fixed
/// reduction order by construction (contract 6's unit-internal rule); the
/// probe is deliberately single-threaded.
pub fn column_major_position_checksum(
    data: &[f64],
    nrow: usize,
    ncol: usize,
) -> Result<f64, MsError> {
    let expected = nrow
        .checked_mul(ncol)
        .ok_or_else(|| MsError::new("argument", "matrix dimensions overflow usize"))?;
    if data.len() != expected {
        return Err(MsError::new(
            "argument",
            format!(
                "matrix buffer length {} does not match dimensions {}x{}",
                data.len(),
                nrow,
                ncol
            ),
        ));
    }
    let mut acc = 0.0;
    for (k, &v) in data.iter().enumerate() {
        // Contract 3, second layer: R's anyNA() validator rejects NA/NaN
        // before the call; kernels still debug_assert on arrival. (Active
        // in debug builds; release builds rely on the explicit scans.)
        debug_assert!(!v.is_nan(), "NA/NaN reached a kernel (contract 3)");
        acc += (k + 1) as f64 * v;
    }
    Ok(acc)
}

/// What a row-major misread of the same buffer would compute — used by the
/// unit tests to prove the detector discriminates (never shipped logic).
#[cfg(test)]
fn row_major_misread_checksum(data: &[f64], nrow: usize, ncol: usize) -> f64 {
    let mut acc = 0.0;
    for i in 0..nrow {
        for j in 0..ncol {
            let claimed = j * nrow + i; // position (i, j) *claims* in column-major
            acc += (claimed + 1) as f64 * data[i * ncol + j]; // ...but is read row-major
        }
    }
    acc
}

// ---------------------------------------------------------------------------
// Contract 3 — NA/NaN
// ---------------------------------------------------------------------------

/// Production-safe NA/NaN scan over a column-major buffer.
///
/// Returns the number of scanned elements, or an `MsError` carrying the
/// 1-based (i, j) position of the first offender. `NA_real_` is a NaN
/// payload in R, so `is_nan()` catches both NA and NaN — but the FIRST
/// layer of defense is the R-side `anyNA()` validator (R/ffi-probes.R);
/// this scan is the belt-and-braces layer inside Rust.
pub fn scan_no_nan(data: &[f64], nrow: usize) -> Result<usize, MsError> {
    let nrow = nrow.max(1);
    for (k, &v) in data.iter().enumerate() {
        if v.is_nan() {
            let i = (k % nrow + 1) as i64;
            let j = (k / nrow + 1) as i64;
            return Err(MsError::new(
                "na",
                format!(
                    "NA/NaN found at 1-based position ({i}, {j}) of the incoming matrix (column-major scan)"
                ),
            )
            .with_i(i)
            .with_j(j));
        }
    }
    Ok(data.len())
}

// ---------------------------------------------------------------------------
// Contracts 4 + 5 — index bounds and Result errors
// ---------------------------------------------------------------------------

/// Dimensions of the probe's virtual matrix (`error_probe_bounds`).
pub const ERROR_PROBE_NROW: i64 = 4;
pub const ERROR_PROBE_NCOL: i64 = 3;

/// Bounds check on 1-based indices into a virtual `4x3` matrix.
///
/// Demonstrates contracts 4 and 5 end-to-end: explicit bounds validation of
/// R-provided indices, out-of-bounds → `Err(MsError)` (never a panic,
/// never a partial result), in-bounds → a deterministic column-major
/// flat offset as `f64`.
pub fn error_probe_bounds(i: i64, j: i64) -> Result<f64, MsError> {
    if !(1..=ERROR_PROBE_NROW).contains(&i) || !(1..=ERROR_PROBE_NCOL).contains(&j) {
        return Err(MsError::new(
            "bounds",
            format!(
                "probe index (i={i}, j={j}) is outside the virtual {ERROR_PROBE_NROW}x{ERROR_PROBE_NCOL} matrix"
            ),
        )
        .with_i(i)
        .with_j(j));
    }
    Ok(((i - 1) * ERROR_PROBE_NCOL + (j - 1)) as f64)
}

// ---------------------------------------------------------------------------
// Contract 6 — per-call thread pool and thread-count invariance
// ---------------------------------------------------------------------------

/// Build the per-call thread pool (contract 6).
///
/// `n_threads == 0` means "rayon default" (all cores): the R side resolves
/// the `msuiter.threads` option and the `_R_CHECK_LIMIT_CORES_` cap and
/// passes the effective value; 0 is the sentinel for "leave rayon's
/// default". The pool is owned by the call and dropped with it — the
/// global rayon pool is never used.
pub fn build_call_pool(n_threads: usize) -> Result<rayon::ThreadPool, MsError> {
    let builder = rayon::ThreadPoolBuilder::new();
    let builder = if n_threads == 0 {
        builder
    } else {
        builder.num_threads(n_threads)
    };
    builder
        .build()
        .map_err(|e| MsError::new("argument", format!("failed to build the per-call thread pool: {e}")))
}

/// One probe unit: the value of item `i` from its own independent PCG64
/// stream (canonical layout v1: `replicate = 0, rank = i, fold = 0`).
///
/// Integer-only math keeps this bit-identical everywhere: `(w >> 11)` is
/// `< 2^53`, converts exactly to `f64`, and the product with `2^-53` is
/// exact — no platform-dependent floating-point, no order sensitivity.
pub fn thread_probe_unit(seed: u64, i: usize) -> f64 {
    let mut rng = MsRng::from_stream(seed, StreamId { replicate: 0, rank: i as u64, fold: 0 });
    let w = rng.next_u64();
    ((w >> 11) as f64) * (1.0 / 9_007_199_254_740_992.0) // 2^-53
}

/// Compute the probe value of every item in `[0, n_items)` on a per-call
/// thread pool (contract 6).
///
/// Parallelism exists only *between* independent units (items), mirroring
/// the replicate/sample/bootstrap axis of real kernels. Chunking is a
/// scheduling decision only: each item's value depends on `(seed, index)`
/// alone, units are concatenated in chunk-index order (fixed reduction
/// order — never an order-sensitive floating-point accumulation), so the
/// output is bit-identical for every thread count (thread-count
/// invariance, synthesis A7).
pub fn thread_probe_values(n_items: usize, seed: u64, n_threads: usize) -> Result<Vec<f64>, MsError> {
    let pool = build_call_pool(n_threads)?;
    let target_chunks = n_threads.clamp(1, 16) * 4;
    let chunk_len = if n_items == 0 {
        1
    } else {
        ((n_items + target_chunks - 1) / target_chunks).max(1)
    };
    let n_chunks = if n_items == 0 {
        0
    } else {
        (n_items + chunk_len - 1) / chunk_len
    };

    let mut per_chunk: Vec<(usize, Vec<f64>)> = pool.install(|| {
        (0..n_chunks)
            .into_par_iter()
            .map(|c| {
                let start = c * chunk_len;
                let end = (start + chunk_len).min(n_items);
                let mut vals = Vec::with_capacity(end - start);
                for i in start..end {
                    vals.push(thread_probe_unit(seed, i));
                }
                (c, vals)
            })
            .collect()
    });

    // Fixed reduction: concatenate by chunk index. `collect()` on an indexed
    // parallel iterator already preserves order; the sort makes the
    // contract explicit and immune to any future scheduling change.
    per_chunk.sort_unstable_by_key(|(c, _)| *c);
    let mut out = Vec::with_capacity(n_items);
    for (_, mut vals) in per_chunk {
        out.append(&mut vals);
    }
    debug_assert_eq!(out.len(), n_items);
    Ok(out)
}

// ---------------------------------------------------------------------------
// Contract 7 — interrupt
// ---------------------------------------------------------------------------

/// Chunked loop with main-thread interrupt polling (contract 7).
///
/// * `check_user_interrupt` runs at every chunk boundary **on the main
///   thread**; under R it is `R_CheckUserInterrupt`. Because the FFI is
///   stateless (D12), a user interrupt can only leave the call — there is
///   nothing to clean up.
/// * `worker_unit` runs each chunk's work unit; in real kernels workers
///   live on the per-call pool and the ONLY cross-thread signal they ever
///   see is `cancelled` (`AtomicBool`) — never R state.
///
/// Any cancellation trips `Err(topic = "interrupted")`: the whole call
/// fails with no partial results (contract 5).
pub fn run_interruptible_chunks(
    n_chunks: usize,
    cancelled: &AtomicBool,
    check_user_interrupt: &mut dyn FnMut(),
    worker_unit: &mut dyn FnMut(usize) -> Result<(), MsError>,
) -> Result<usize, MsError> {
    let mut done = 0usize;
    for c in 0..n_chunks {
        // Worker-side view: units stop as soon as the flag is visible.
        if cancelled.load(Ordering::Relaxed) {
            return Err(MsError::new(
                "interrupted",
                format!("call interrupted before chunk {}; no partial results are returned", c + 1),
            )
            .with_i((c + 1) as i64));
        }
        // Main-thread boundary poll (under R: R_CheckUserInterrupt).
        check_user_interrupt();
        worker_unit(c)?;
        done += 1;
    }
    Ok(done)
}

// ---------------------------------------------------------------------------
// Probe: build info (feeds ms_sitrep; not a contract probe per se)
// ---------------------------------------------------------------------------

/// Compile-time facts about the Rust core, reported by `ms_sitrep()`.
pub fn build_info() -> Vec<(&'static str, String)> {
    vec![
        ("package_version", env!("CARGO_PKG_VERSION").to_string()),
        (
            "rustc_version",
            option_env!("MSUITER_RUSTC_VERSION").unwrap_or("unknown").to_string(),
        ),
        ("target_os", std::env::consts::OS.to_string()),
        ("target_arch", std::env::consts::ARCH.to_string()),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    // ------------------------------------------------------------------
    // Contract 2 — column-major
    // ------------------------------------------------------------------

    /// The buffer of R's `matrix(1:12, nrow = 3)` (column-major fill).
    fn col_major_buffer_3x4() -> Vec<f64> {
        (1..=12).map(f64::from).collect()
    }

    #[test]
    fn checksum_matches_reference_column_major_read() {
        let data = col_major_buffer_3x4();
        let expect: f64 = data
            .iter()
            .enumerate()
            .map(|(k, v)| (k + 1) as f64 * v)
            .sum();
        assert_eq!(
            column_major_position_checksum(&data, 3, 4).unwrap(),
            expect
        );
    }

    #[test]
    fn checksum_discriminates_row_major_misread() {
        // The asymmetric golden property: for a non-square, asymmetrically
        // filled matrix the column-major read and the row-major misread
        // must disagree.
        let data = col_major_buffer_3x4();
        let col = column_major_position_checksum(&data, 3, 4).unwrap();
        let mis = row_major_misread_checksum(&data, 3, 4);
        assert_ne!(col, mis);
    }

    #[test]
    fn checksum_is_position_sensitive_and_transpose_asymmetric() {
        // Reading the transposed matrix (its own column-major buffer) must
        // give a different scalar: weights are positions, and transposing
        // permutes value↔position.
        let data = vec![10.0, 20.0, 30.0, 40.0, 50.0, 60.0]; // 3x2 col-major
        // t(M)(r, c) = M(c, r); with M stored 3x2 column-major the
        // transposed 2x3 column-major buffer is:
        let transposed: Vec<f64> = (0..6).map(|k| data[(k % 2) * 3 + k / 2]).collect();
        let a = column_major_position_checksum(&data, 3, 2).unwrap();
        let b = column_major_position_checksum(&transposed, 2, 3).unwrap();
        assert_ne!(a, b);
    }

    #[test]
    fn checksum_is_exact_for_integer_valued_matrices() {
        // Probe sizes keep every product and partial sum an exactly
        // representable integer, so `identical()` comparisons are safe.
        let data = col_major_buffer_3x4();
        let sum = column_major_position_checksum(&data, 3, 4).unwrap();
        assert_eq!(sum, sum.round());
        assert!(sum.abs() < (1u64 << 53) as f64);
    }

    #[test]
    fn checksum_rejects_dim_mismatch() {
        assert!(column_major_position_checksum(&[1.0, 2.0], 3, 4).is_err());
        assert!(column_major_position_checksum(&[], 0, 0).is_ok());
        assert_eq!(
            column_major_position_checksum(&[1.0, 2.0], 2, 1).unwrap(),
            5.0 // 1·1 + 2·2
        );
    }

    // ------------------------------------------------------------------
    // Contract 3 — NA/NaN
    // ------------------------------------------------------------------

    #[test]
    fn na_scan_accepts_clean_buffer() {
        assert_eq!(scan_no_nan(&[1.0, 2.0, 3.0], 3).unwrap(), 3);
        assert_eq!(scan_no_nan(&[], 0).unwrap(), 0);
    }

    #[test]
    fn na_scan_locates_first_offender_1based_column_major() {
        // 3 rows; the 4th flat element (k = 3) is NaN → (i=1, j=2).
        let err =
            scan_no_nan(&[1.0, 2.0, 3.0, f64::NAN, 5.0, 6.0], 3).unwrap_err();
        assert_eq!(err.topic, "na");
        assert_eq!(err.i, Some(1));
        assert_eq!(err.j, Some(2));
        // Column-major order: the first offender wins.
        let err =
            scan_no_nan(&[f64::NAN, 2.0, 3.0, f64::NAN, 5.0, 6.0], 3).unwrap_err();
        assert_eq!(err.i, Some(1));
        assert_eq!(err.j, Some(1));
    }

    // ------------------------------------------------------------------
    // Contracts 4 + 5 — bounds / Result errors
    // ------------------------------------------------------------------

    #[test]
    fn error_probe_bounds_checks() {
        assert_eq!(error_probe_bounds(1, 1).unwrap(), 0.0);
        assert_eq!(error_probe_bounds(4, 3).unwrap(), 11.0);
        assert_eq!(error_probe_bounds(2, 3).unwrap(), 5.0);
        for (i, j) in [(0, 1), (5, 1), (1, 0), (1, 4), (-1, 2)] {
            let err = error_probe_bounds(i, j).unwrap_err();
            assert_eq!(err.topic, "bounds");
            assert_eq!(err.i, Some(i));
            assert_eq!(err.j, Some(j));
        }
    }

    // ------------------------------------------------------------------
    // Contract 6 — per-call pool, thread invariance
    // ------------------------------------------------------------------

    #[test]
    fn thread_probe_matches_sequential_reference() {
        let reference: Vec<f64> = (0..257).map(|i| thread_probe_unit(42, i)).collect();
        assert_eq!(thread_probe_values(257, 42, 1).unwrap(), reference);
        assert_eq!(thread_probe_values(257, 42, 4).unwrap(), reference);
    }

    #[test]
    fn thread_probe_is_invariant_to_thread_count() {
        // A7/contract 6: same seed, threads ∈ {1, N} → identical output.
        let one = thread_probe_values(1000, 7, 1).unwrap();
        let four = thread_probe_values(1000, 7, 4).unwrap();
        let sixteen = thread_probe_values(1000, 7, 16).unwrap();
        assert_eq!(one, four);
        assert_eq!(one, sixteen);
        // Empty request stays empty (and is still an Ok).
        assert_eq!(thread_probe_values(0, 7, 4).unwrap(), Vec::<f64>::new());
    }

    #[test]
    fn thread_probe_units_use_isolated_streams() {
        assert_eq!(thread_probe_unit(42, 9), thread_probe_unit(42, 9));
        for i in [0usize, 5, 100] {
            let v = thread_probe_unit(42, i);
            assert!((0.0..1.0).contains(&v), "value {v} outside [0, 1)");
        }
        let units: Vec<f64> = (0..64).map(|i| thread_probe_unit(42, i)).collect();
        for i in 0..units.len() {
            for j in (i + 1)..units.len() {
                assert_ne!(units[i], units[j], "items {i} and {j} collide");
            }
        }
    }

    #[test]
    fn thread_probe_seed_changes_output() {
        assert_ne!(
            thread_probe_values(64, 1, 2).unwrap(),
            thread_probe_values(64, 2, 2).unwrap()
        );
    }

    #[test]
    fn call_pool_builds_for_all_requested_sizes() {
        for t in [0usize, 1, 2, 4, 16] {
            assert!(build_call_pool(t).is_ok());
        }
    }

    // ------------------------------------------------------------------
    // Contract 7 — interrupt
    // ------------------------------------------------------------------

    #[test]
    fn interrupt_loop_completes_when_not_cancelled() {
        let cancelled = AtomicBool::new(false);
        let mut boundaries = 0usize;
        let mut units = Vec::new();
        let done = run_interruptible_chunks(
            5,
            &cancelled,
            &mut || boundaries += 1,
            &mut |c| {
                units.push(c);
                Ok(())
            },
        )
        .unwrap();
        assert_eq!(done, 5);
        assert_eq!(boundaries, 5); // one boundary poll per chunk
        assert_eq!(units, vec![0, 1, 2, 3, 4]);
    }

    #[test]
    fn interrupt_loop_fails_without_partial_results_when_pre_cancelled() {
        let cancelled = AtomicBool::new(true);
        let mut ran = 0usize;
        let err = run_interruptible_chunks(
            4,
            &cancelled,
            &mut || {},
            &mut |_| {
                ran += 1;
                Ok(())
            },
        )
        .unwrap_err();
        assert_eq!(err.topic, "interrupted");
        assert_eq!(err.i, Some(1));
        assert_eq!(ran, 0); // no unit ran: no partial results
    }

    #[test]
    fn interrupt_loop_worker_flag_trip_fails_whole_call() {
        // Workers only see the AtomicBool: when it trips mid-run, the whole
        // call fails with the interrupted error.
        let cancelled = AtomicBool::new(false);
        let mut boundaries = 0usize;
        let err = run_interruptible_chunks(
            4,
            &cancelled,
            &mut || {
                boundaries += 1;
                if boundaries == 3 {
                    cancelled.store(true, Ordering::Relaxed);
                }
            },
            &mut |c| {
                if c >= 3 {
                    Err(MsError::new("interrupted", "worker observed cancellation")
                        .with_i((c + 1) as i64))
                } else {
                    Ok(())
                }
            },
        )
        .unwrap_err();
        assert_eq!(err.topic, "interrupted");
        assert_eq!(err.i, Some(4));
    }
}
