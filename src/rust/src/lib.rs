//! msuiter FFI shell.
//!
//! The only crate allowed to contain `unsafe` and the only one depending
//! on `extendr-api` (`docs/ARCHITECTURE.md` §2). Stateless per D12: no
//! handles, no `.state`, one call in/out.
//!
//! U-M0-09: this unit lands the eight FFI hard contracts as **testable
//! probes** (`msffi_*`, documented and frozen in `docs/ffi-surface.md`)
//! plus the structured `MsError` → R-condition mapping. It deliberately
//! contains NO algorithm kernel: NMF/NNLS & co. are M1s work.
//!
//! Contract map (see `probes.rs` for the pure cores, `condition.rs` for
//! the error mapping, `replicates.rs` for the first real-kernel driver,
//! `tally.rs` for the catalog tally core, `extract.rs` for the
//! single-method extraction core, `stratify.rs` for the GMM stratification
//! core):
//! 1. stateless   — every `msffi_*` is one call in/out, no globals;
//! 2. column-major — `msffi_column_major_probe`;
//! 3. NA/NaN      — R validator (primary) + `msffi_na_probe`;
//! 4. indexes     — explicit bounds checks, errors not panics (`msffi_error_probe`);
//! 5. errors      — `Result<_, MsError>` at the boundary only;
//! 6. threads     — per-call pool, unit-internal serial (A7 invariance): `msffi_thread_probe` + `msffi_nmf_replicates_probe`;
//! 7. interrupt   — boundary polling + worker `AtomicBool`: `msffi_interrupt_probe` + the real-kernel driver;
//! 8. build       — Makevars/vendor discipline unchanged; `msffi_build_info` feeds `ms_sitrep()`.

use extendr_api::prelude::*;
use msuiter_engine::error::MsError;
use std::collections::HashMap;
use std::fs::File;
use std::sync::atomic::{AtomicBool, Ordering};

mod condition;
mod extract;
mod fit;
mod pipeline;
mod probes;
mod replicates;
mod stratify;
mod tally;

// Contract 7: polled ONLY on the main thread, ONLY at chunk boundaries.
// `R_CheckUserInterrupt` longjmps back into R on user interrupt, skipping
// Rust destructors; that is why kernels never call throwing R APIs
// (contract 5) and why heavy buffers are scoped per chunk. Statelessness
// (D12) makes the interrupt side-effect-free.
extern "C" {
    fn R_CheckUserInterrupt();
}

/// Unpack an R double matrix and hand (nrow, ncol, column-major data) to
/// `f`. Validation errors are `MsError`s (contract 4) — extendr internals
/// that could panic are never allowed to see an invalid object.
fn with_matrix_f64<T>(
    x: &Robj,
    f: impl FnOnce(usize, usize, &[f64]) -> Result<T, MsError>,
) -> Result<T, MsError> {
    if !x.is_matrix() {
        return Err(MsError::new("argument", "expected a matrix with a dim attribute"));
    }
    let m: RMatrix<f64> = x
        .as_matrix()
        .ok_or_else(|| MsError::new("argument", "expected a double (REALSXP) matrix"))?;
    let (nrow, ncol) = (m.nrows(), m.ncols());
    f(nrow, ncol, m.data())
}

// No doc comments on the #[extendr] functions: the generated
// R/extendr-wrappers.R must stay roxygen-neutral; the frozen surface lives
// in docs/ffi-surface.md and the validated R wrappers in R/ffi-probes.R.

#[extendr]
fn msffi_column_major_probe(x: Robj) -> Robj {
    condition::kernel_result_to_robj(with_matrix_f64(&x, |nrow, ncol, data| {
        probes::column_major_position_checksum(data, nrow, ncol)
    }))
}

#[extendr]
fn msffi_na_probe(x: Robj) -> Robj {
    condition::kernel_result_to_robj(with_matrix_f64(&x, |nrow, _ncol, data| {
        // Contract 3: the FIRST layer is the R-side anyNA() validator; this
        // scan is the production-safe second layer. In debug builds the
        // debug_assert additionally hard-stops (panic → caught by the
        // extendr wrapper → R error, still no partial results).
        let scan = probes::scan_no_nan(data, nrow);
        debug_assert!(
            scan.is_ok(),
            "NA/NaN reached a kernel: R-side anyNA validation was bypassed (contract 3)"
        );
        scan.map(|n| n.min(i32::MAX as usize) as i32)
    }))
}

#[extendr]
fn msffi_error_probe(i: i32, j: i32) -> Robj {
    condition::kernel_result_to_robj(probes::error_probe_bounds(i as i64, j as i64))
}

#[extendr]
fn msffi_interrupt_probe(n_chunks: i32, n_threads: i32) -> Robj {
    condition::kernel_result_to_robj(
        (|| -> Result<i32, MsError> {
            if n_chunks < 0 {
                return Err(MsError::new(
                    "argument",
                    format!("n_chunks must be >= 0, got {n_chunks}"),
                )
                .with_i(n_chunks as i64));
            }
            if n_threads < 0 {
                return Err(MsError::new(
                    "argument",
                    format!("n_threads must be >= 0 (0 = rayon default), got {n_threads}"),
                ));
            }
            let cancelled = AtomicBool::new(false);
            let pool = probes::build_call_pool(n_threads as usize)?;
            let mut boundary = || unsafe { R_CheckUserInterrupt() };
            let mut worker = |c: usize| -> Result<(), MsError> {
                // Worker-side view (contract 7): the only cross-thread
                // signal a unit ever sees is the cancellation flag. The
                // trivial unit below runs on the per-call pool (contract
                // 6); no real kernel before M1s.
                if cancelled.load(Ordering::Relaxed) {
                    return Err(MsError::new(
                        "interrupted",
                        format!("worker observed cancellation at chunk {}", c + 1),
                    )
                    .with_i((c + 1) as i64));
                }
                pool.install(|| c.checked_mul(3).map(|_| ())).ok_or_else(|| {
                    MsError::new("bounds", "chunk index overflow").with_i((c + 1) as i64)
                })
            };
            probes::run_interruptible_chunks(
                n_chunks as usize,
                &cancelled,
                &mut boundary,
                &mut worker,
            )
            .map(|done| done.min(i32::MAX as usize) as i32)
        })(),
    )
}

#[extendr]
fn msffi_thread_probe(n_items: i32, seed: i32, n_threads: i32) -> Robj {
    condition::kernel_result_to_robj((|| -> Result<Vec<f64>, MsError> {
        if n_items < 0 {
            return Err(MsError::new(
                "argument",
                format!("n_items must be >= 0, got {n_items}"),
            ));
        }
        if seed < 0 {
            return Err(MsError::new(
                "argument",
                format!("seed must be >= 0, got {seed}"),
            ));
        }
        if n_threads < 0 {
            return Err(MsError::new(
                "argument",
                format!("n_threads must be >= 0 (0 = rayon default), got {n_threads}"),
            ));
        }
        probes::thread_probe_values(n_items as usize, seed as u64, n_threads as usize)
    })())
}

#[extendr]
fn msffi_nmf_replicates_probe(
    counts: Robj,
    k: i32,
    replicates: i32,
    max_iter: i32,
    seed: i32,
    n_threads: i32,
) -> Robj {
    condition::kernel_result_to_robj((|| -> Result<Vec<f64>, MsError> {
        // Argument guards (contract 4): explicit, error-not-panic. The
        // engine's own validate_* re-checks the matrix content per unit.
        if k < 1 {
            return Err(MsError::new("argument", format!("k must be >= 1, got {k}")).with_i(k as i64));
        }
        if replicates < 1 {
            return Err(
                MsError::new("argument", format!("replicates must be >= 1, got {replicates}"))
                    .with_i(replicates as i64),
            );
        }
        if max_iter < 0 {
            return Err(MsError::new(
                "argument",
                format!("max_iter must be >= 0, got {max_iter}"),
            ));
        }
        if seed < 0 {
            return Err(MsError::new(
                "argument",
                format!("seed must be >= 0, got {seed}"),
            ));
        }
        if n_threads < 0 {
            return Err(MsError::new(
                "argument",
                format!("n_threads must be >= 0 (0 = rayon default), got {n_threads}"),
            ));
        }
        // Contract 2: the R matrix crosses the boundary column-major; the
        // engine kernel is row-major. Sequential marshalling before any
        // unit runs (setup, not a unit — no parallelism needed here).
        let (m, n, v) = with_matrix_f64(&counts, |m, n, data| {
            let mut v = vec![0.0f64; m * n];
            for j in 0..n {
                for i in 0..m {
                    v[i * n + j] = data[j * m + i];
                }
            }
            Ok((m, n, v))
        })?;
        let cancelled = AtomicBool::new(false);
        // Contract 7: main-thread boundary poll only; workers see the
        // AtomicBool inside `replicates::nmf_replicates_objectives`.
        let mut boundary = || unsafe { R_CheckUserInterrupt() };
        replicates::nmf_replicates_objectives(
            &v,
            m,
            n,
            k as usize,
            max_iter as usize,
            seed as u64,
            replicates as usize,
            n_threads as usize,
            &cancelled,
            &mut boundary,
        )
    })())
}

#[extendr]
fn msffi_build_info() -> Robj {
    let info = probes::build_info();
    let pairs: Vec<(&str, Robj)> = info
        .iter()
        .map(|(k, v)| (*k, Robj::from(v.as_str())))
        .collect();
    Robj::from(List::from_pairs(pairs))
}

// ---------------------------------------------------------------------------
// U-M1s-09: catalog tally kernel (`ms_tally_rust`, FFI-internal name — the
// user-facing `ms_tally()` generic lands in U-M1s-11). The pure assembly
// core lives in `tally.rs`; this adapter owns the mmap lifetime (D12).
// ---------------------------------------------------------------------------

/// Canonical table lengths, for empty (disabled) matrices.
const SBS96_LEN: usize = 96;
const SBS192_LEN: usize = 192;
const SBS384_LEN: usize = 384;
const SBS1536_LEN: usize = 1536;
const DBS78_LEN: usize = 78;
// ID83's length comes from `indel83::ID83_CHANNELS.len()` at the call
// site (a const here would reference a static: E0013 on MSRV 1.71).

/// Names of the per-record columns, for length-mismatch errors (1-based
/// column number in `j`).
const TALLY_COLUMNS: [(&str, usize); 6] = [
    ("chrom", 1),
    ("pos", 2),
    ("ref_", 3),
    ("alt", 4),
    ("sample", 5),
    ("strand", 6),
];

/// Convert one count buffer into an R integer matrix (column-major,
/// `nrow = table length`: contract 2). Disabled tables keep their row
/// count with zero columns; enabled-but-empty input likewise degenerates
/// to zero columns.
fn counts_matrix(buf: &[u32], nrow: usize, n_samples: usize) -> Result<Robj, MsError> {
    let ncol = if buf.is_empty() { 0 } else { n_samples };
    debug_assert_eq!(buf.len(), nrow * ncol, "count buffer layout drifted");
    let data: Vec<i32> = buf
        .iter()
        .map(|&c| {
            i32::try_from(c)
                .map_err(|_| MsError::new("bounds", "a per-channel count exceeds the R integer range"))
        })
        .collect::<Result<_, _>>()?;
    let m = extendr_api::wrapper::RMatrix::new_matrix(nrow, ncol, |r, c| {
        data[c * nrow + r]
    });
    Ok(m.into())
}

/// One record of the R columns -> a `tally::TallyVariant` (contract 4:
/// explicit validation of every scalar, errors not panics).
#[allow(clippy::too_many_arguments)]
fn tally_variant_at(
    k: usize,
    chrom: &str,
    pos: f64,
    ref_: &str,
    alt: &str,
    sample_col: usize,
    strand: &str,
    chrom_idx: &HashMap<&str, usize>,
) -> Result<tally::TallyVariant, MsError> {
    let rec = k + 1;
    // Contract 3, second layer: NA reaches Rust as NaN.
    if !pos.is_finite() {
        return Err(MsError::new(
            "na",
            format!("pos[{rec}] is NA/NaN (R-side anyNA validation was bypassed)"),
        )
        .with_i(rec as i64)
        .with_j(2));
    }
    // pos is already NaN-rejected above, so `<` is total here.
    if pos < 1.0 || pos.floor() != pos {
        return Err(MsError::new(
            "argument",
            format!("pos[{rec}] = {pos} must be an integer-valued 1-based position"),
        )
        .with_i(rec as i64)
        .with_j(2));
    }
    let strand_val = match strand {
        "T" => msuiter_catalog::sbs::Strand::Transcribed,
        "U" => msuiter_catalog::sbs::Strand::Untranscribed,
        "B" => msuiter_catalog::sbs::Strand::Bidirectional,
        "N" => msuiter_catalog::sbs::Strand::None,
        other => {
            return Err(MsError::new(
                "argument",
                format!(
                    "strand[{rec}] = \"{other}\" is not one of T, U, B, N (transcribed, untranscribed, bidirectional, unannotated)"
                ),
            )
            .with_i(rec as i64)
            .with_j(6))
        }
    };
    let pos0 = (pos as u64).saturating_sub(1); // 1-based POS -> 0-based
    Ok(tally::TallyVariant {
        chrom_idx: chrom_idx.get(chrom).copied().unwrap_or(tally::UNKNOWN_CHROM),
        pos0,
        ref_: ref_.as_bytes().to_vec(),
        alt: alt.as_bytes().to_vec(),
        sample_idx: sample_col,
        strand: strand_val,
    })
}

#[extendr]
#[allow(clippy::too_many_arguments)]
fn ms_tally_rust(
    genome_path: String,
    chrom: Vec<String>,
    pos: Vec<f64>,
    ref_: Vec<String>,
    alt: Vec<String>,
    sample: Vec<String>,
    strand: Vec<String>,
    want_sbs96: bool,
    want_sbs192: bool,
    want_sbs384: bool,
    want_sbs1536: bool,
    want_dbs78: bool,
    want_id83: bool,
    n_threads: i32,
) -> Robj {
    condition::kernel_result_to_robj((|| -> Result<Robj, MsError> {
        // Column agreement (contract 4): all six per-record columns must
        // have the same length; `j` names the offending column.
        let n = chrom.len();
        for ((name, col), observed) in [
            (TALLY_COLUMNS[1], pos.len()),
            (TALLY_COLUMNS[2], ref_.len()),
            (TALLY_COLUMNS[3], alt.len()),
            (TALLY_COLUMNS[4], sample.len()),
            (TALLY_COLUMNS[5], strand.len()),
        ] {
            if observed != n {
                return Err(MsError::new(
                    "argument",
                    format!(
                        "column \"{name}\" has length {observed}, expected {n} (all per-record columns must agree)"
                    ),
                )
                .with_i(observed as i64)
                .with_j(col as i64));
            }
        }
        // Contract 6: the R wrapper resolves `msuiter.threads` (and the
        // `_R_CHECK_LIMIT_CORES_` cap) and passes the effective pool size;
        // 0 is the "rayon default" sentinel.
        if n_threads < 0 {
            return Err(MsError::new(
                "argument",
                format!("n_threads must be >= 0 (0 = rayon default), got {n_threads}"),
            ));
        }

        // D12 (contract 1): one call in/out — the file handle and the
        // mapping are built here and dropped with this scope. SAFETY: the
        // mapping is read-only over a file opened read-only and is never
        // mutated or truncated while borrowed.
        //
        // Interrupt caveat (frozen U-M0-09 limitation, accepted for the
        // M1s tally): `R_CheckUserInterrupt` inside `tally` longjmps back
        // into R, skipping the Rust destructors — this Mmap's address
        // space therefore stays reserved until process exit (contract 7
        // notes in this file). For a whole-human-genome 2bit this is a
        // large but read-only, page-cache-backed reservation; correctness
        // and statelessness (D12) are unaffected. The C-trampoline
        // hardening (run the kernel under an unwind/longjmp-safe trampoline
        // so the mapping is released on interrupt) is deferred to M8/CI —
        // out of scope for this unit; see docs/ffi-surface.md, the
        // ms_tally_rust row.
        let file = File::open(&genome_path).map_err(|e| {
            MsError::new("io", format!("cannot open genome file \"{genome_path}\": {e}"))
        })?;
        let mmap = unsafe { memmap2::Mmap::map(&file) }
            .map_err(|e| MsError::new("io", format!("cannot map genome file \"{genome_path}\": {e}")))?;
        // Parsed once here for chromosome resolution (chromosome names +
        // per-record chrom indexes); the tally core re-parses the same
        // immutable bytes (main thread for validation, once per pool
        // worker on the parallel path — see tally.rs, Concurrency).
        let genome = msuiter_catalog::genome::TwoBitGenome::from_bytes(&mmap[..])?;

        // Chromosome resolution is EXACT string matching (M1s policy, no
        // chr-prefix normalization); unmatched names ledger as
        // skipped:unknown_chrom inside the core.
        let names = genome.chrom_names();
        let chrom_idx: HashMap<&str, usize> = names
            .iter()
            .enumerate()
            .map(|(i, name)| (name.as_str(), i))
            .collect();
        // Sample columns in first-appearance order of the input rows.
        let mut sample_idx: HashMap<&str, usize> = HashMap::new();
        for s in &sample {
            let next = sample_idx.len();
            sample_idx.entry(s.as_str()).or_insert(next);
        }

        let variants = chrom
            .iter()
            .zip(pos.iter())
            .zip(ref_.iter())
            .zip(alt.iter())
            .zip(sample.iter())
            .zip(strand.iter())
            .enumerate()
            .map(
                |(k, (((((c, &p), r), a), s), st))| {
                    let col = sample_idx[s.as_str()];
                    tally_variant_at(k, c, p, r, a, col, st, &chrom_idx)
                },
            )
            .collect::<Result<Vec<_>, MsError>>()?;

        let tables = tally::TallyTables {
            sbs96: want_sbs96,
            sbs192: want_sbs192,
            sbs384: want_sbs384,
            sbs1536: want_sbs1536,
            dbs78: want_dbs78,
            id83: want_id83,
        };
        // Contract 6 + 7: (chrom, sample) partitions run in parallel on a
        // per-call pool; the boundary hook below is polled on THIS (main)
        // thread only, and workers see only the in-call cancellation flag
        // (see tally.rs, Concurrency + Interrupt protocol).
        let cancelled = AtomicBool::new(false);
        let mut boundary = || unsafe { R_CheckUserInterrupt() };
        let result = tally::tally(
            &mmap[..],
            &variants,
            tables,
            n_threads as usize,
            &cancelled,
            &mut boundary,
        )?;

        let n_samples = sample_idx.len();
        let pairs = vec![
            ("sbs96", counts_matrix(&result.sbs96, SBS96_LEN, n_samples)?),
            ("sbs192", counts_matrix(&result.sbs192, SBS192_LEN, n_samples)?),
            ("sbs384", counts_matrix(&result.sbs384, SBS384_LEN, n_samples)?),
            ("sbs1536", counts_matrix(&result.sbs1536, SBS1536_LEN, n_samples)?),
            ("dbs78", counts_matrix(&result.dbs78, DBS78_LEN, n_samples)?),
            ("id83", counts_matrix(&result.id83, msuiter_catalog::indel83::ID83_CHANNELS.len(), n_samples)?),
            ("ledger", Robj::from(result.ledger_tsv)),
            (
                "n_skipped",
                Robj::from(result.n_skipped.min(i32::MAX as u32) as i32),
            ),
            ("n_variants", Robj::from(variants.len().min(i32::MAX as usize) as i32)),
        ];
        Ok(Robj::from(List::from_pairs(pairs)))
    })())
}

// ---------------------------------------------------------------------------
// U-M1s-12: single-method extraction kernel (`ms_extract_rust`, FFI-internal
// name — the user-facing `ms_extract()` generic lands in the same unit,
// R/extract.R). The pure assembly core lives in `extract.rs`; this adapter
// owns the R-matrix handoff (the t(counts) layout contract).
// ---------------------------------------------------------------------------

#[extendr]
fn ms_extract_rust(
    counts: Robj,
    k: i32,
    max_iter: i32,
    seed: i32,
    engine: String,
    n_threads: i32,
) -> Robj {
    condition::kernel_result_to_robj((|| -> Result<Robj, MsError> {
        // Argument guards (contract 4): explicit, error-not-panic. The
        // engine's own validate_* re-checks the matrix content per cell.
        if k < 1 {
            return Err(MsError::new("argument", format!("k must be >= 1, got {k}")).with_i(k as i64));
        }
        if max_iter < 0 {
            return Err(MsError::new(
                "argument",
                format!("max_iter must be >= 0, got {max_iter}"),
            ));
        }
        if seed < 0 {
            return Err(MsError::new(
                "argument",
                format!("seed must be >= 0, got {seed}"),
            ));
        }
        if n_threads < 0 {
            return Err(MsError::new(
                "argument",
                format!("n_threads must be >= 0 (0 = rayon default), got {n_threads}"),
            ));
        }
        // Kernel variant switch: KL (beta = 1, D6 default) or EU (beta = 2).
        let variant = extract::NmfVariant::parse(&engine)?;
        // Layout contract (module docs of `extract.rs`, the transposition
        // trap): R passes `t(counts)` — an n_samples x m_channels double
        // matrix whose column-major flat buffer IS the kernel's row-major
        // m×n V: V[i*n + j] == data[i*n + j] == counts[i, j]. No
        // marshalling loop on this side; the asymmetric-golden recovery
        // smoke on both sides guards the orientation.
        let (n, m, v) = with_matrix_f64(&counts, |nrow, ncol, data| Ok((nrow, ncol, data.to_vec())))?;
        // Single seeded fit on the canonical zero stream (U-M1s-12).
        // Contract 7, declared decision: bounded-duration call, no boundary
        // polls (single fit has no chunk structure; see extract.rs docs).
        // `n_threads` is validated above and otherwise unused: one fit has
        // nothing to parallelize (A7: sequential kernel, thread-invariant).
        let fit = extract::extract(
            &v,
            m,
            n,
            k as usize,
            max_iter as usize,
            seed as u64,
            variant,
        )?;

        // Raw (unnormalized) factors as R matrices (contract 2, column
        // major): signatures channels x signatures (m×k), exposures
        // signatures x samples (k×n). Column-normalizing W is the R
        // assembly layer's display convention, not the kernel's.
        let kk = k as usize;
        let signatures = extendr_api::wrapper::RMatrix::new_matrix(m, kk, |r, c| {
            fit.w[r * kk + c]
        });
        let exposures =
            extendr_api::wrapper::RMatrix::new_matrix(kk, n, |r, c| fit.h[r * n + c]);
        let pairs = vec![
            ("signatures", Robj::from(signatures)),
            ("exposures", Robj::from(exposures)),
            ("objective", Robj::from(fit.objective)),
            (
                "iterations",
                Robj::from(fit.iterations.min(i32::MAX as usize) as i32),
            ),
        ];
        Ok(Robj::from(List::from_pairs(pairs)))
    })())
}

// ---------------------------------------------------------------------------
// U-M3a-02 reference-based fitting kernel (`ms_fit_rust`, FFI-internal name
// — the user-facing `ms_fit()` generic lands in R/fit.R). The pure assembly
// core lives in `fit.rs` (three methods: nnls / likelihood_bidirectional /
// lrt); this adapter owns the R-matrix handoff (the same t(counts) layout
// contract as ms_extract_rust, extended to the t(sigs) dictionary) and the
// scalar domain guards.
// ---------------------------------------------------------------------------

#[extendr]
#[allow(clippy::too_many_arguments)] // FFI face: hyper-parameters are part of the frozen signature
fn ms_fit_rust(
    counts: Robj,
    signatures: Robj,
    method: String,
    nb_size: f64,
    tol: f64,
    max_iter: i32,
    zero_threshold: f64,
    n_threads: i32,
) -> Robj {
    condition::kernel_result_to_robj((|| -> Result<Robj, MsError> {
        // Argument guards (contract 4): explicit, error-not-panic. The
        // core re-validates every matrix cell and the scalar domains.
        if max_iter < 1 {
            return Err(MsError::new(
                "argument",
                format!("max_iter must be >= 1, got {max_iter}"),
            ));
        }
        if n_threads < 0 {
            return Err(MsError::new(
                "argument",
                format!("n_threads must be >= 0 (0 = rayon default), got {n_threads}"),
            ));
        }
        let method = fit::FitMethod::parse(&method)?;
        // Layout contract (fit.rs module docs, the transposition trap):
        // R passes t(counts) — n x m column-major flat buffer IS the
        // row-major m x n counts — and t(sigs) — k x m column-major flat
        // buffer IS the row-major m x k signatures. Zero marshalling here;
        // the asymmetric-golden recovery smokes on both sides guard the
        // orientation.
        let (n, m, counts_data) =
            with_matrix_f64(&counts, |nrow, ncol, data| Ok((nrow, ncol, data.to_vec())))?;
        let (k, m2, sigs_data) =
            with_matrix_f64(&signatures, |nrow, ncol, data| Ok((nrow, ncol, data.to_vec())))?;
        if m2 != m {
            return Err(MsError::new(
                "argument",
                format!(
                    "signatures and counts must share the channel dimension: counts has {m}, signatures have {m2}"
                ),
            )
            .with_i(m as i64)
            .with_j(m2 as i64));
        }
        // Contract 7, declared decision: bounded-duration call, no boundary
        // polls (single bounded batch over samples; see fit.rs docs).
        // `n_threads` is validated above and otherwise unused (A7: the
        // sequential core is trivially thread-invariant).
        let out = fit::fit(
            &counts_data,
            &sigs_data,
            m,
            n,
            k,
            method,
            nb_size,
            tol,
            max_iter as usize,
            zero_threshold,
        )?;

        // Wire shape (contract 2, column-major k x n grids).
        let kk = k;
        let nn = n;
        let col_major_f64 =
            |grid: &[f64]| extendr_api::wrapper::RMatrix::new_matrix(kk, nn, |r, c| grid[r * nn + c]);
        let exposures = col_major_f64(&out.exposures);
        let lrt_stat = col_major_f64(&out.lrt_stat);
        let lrt_p = col_major_f64(&out.lrt_p);
        let se = col_major_f64(&out.se);
        let support_data: Vec<i32> = out.support.clone();
        let support =
            extendr_api::wrapper::RMatrix::new_matrix(kk, nn, |r, c| support_data[r * nn + c]);
        let pairs = vec![
            ("exposures", Robj::from(exposures)),
            ("support", Robj::from(support)),
            ("lrt_stat", Robj::from(lrt_stat)),
            ("lrt_p", Robj::from(lrt_p)),
            ("se", Robj::from(se)),
            ("method", Robj::from(method.as_str())),
            ("converged", Robj::from(out.converged)),
        ];
        Ok(Robj::from(List::from_pairs(pairs)))
    })())
}

// ---------------------------------------------------------------------------
// M2 pipeline plan slot (FFI wiring of U-M1c-02): GMM hypermutant
// stratification kernel (`ms_stratify_rust`, FFI-internal name — the
// user-facing API stays `ms_stratify_hypermutants()` in R/stratify.R). The
// pure assembly core lives in `stratify.rs`; this adapter owns the R-matrix
// handoff and the scalar domain checks.
// ---------------------------------------------------------------------------

#[extendr]
fn ms_stratify_rust(counts: Robj, manual_cutoff: f64, seed: f64, n_threads: i32) -> Robj {
    condition::kernel_result_to_robj((|| -> Result<Robj, MsError> {
        // Scalar domain (contract 4): whole numbers in [0, 2^53] (doubles
        // are exact up to 2^53; the u64 kernel domain is far wider than any
        // count). The R wrapper is the first layer; these guards make the
        // boundary safe on its own.
        for (name, v) in [("manual_cutoff", manual_cutoff), ("seed", seed)] {
            if !v.is_finite() || v < 0.0 || v.fract() != 0.0 || v > 9.007_199_254_740_992e15 {
                return Err(MsError::new(
                    "argument",
                    format!("{name} must be a whole number in [0, 2^53], got {v}"),
                ));
            }
        }
        // Contract 6 surface: the R wrapper resolves `msuiter.threads` (and
        // the `_R_CHECK_LIMIT_CORES_` cap) and passes the effective pool
        // size; 0 is the "rayon default" sentinel. One cutoff-rule run is a
        // fixed-order sequential computation (A7, trivially
        // thread-invariant): the value is validated and otherwise unused.
        if n_threads < 0 {
            return Err(MsError::new(
                "argument",
                format!("n_threads must be >= 0 (0 = rayon default), got {n_threads}"),
            ));
        }
        // Layout: the m×n counts matrix crosses AS-IS (column-major, no
        // transposition — the column sums read column j as a contiguous
        // slab; see stratify.rs module docs for the orientation guard).
        let (m, n, data) = with_matrix_f64(&counts, |m, n, data| Ok((m, n, data.to_vec())))?;
        let decision = stratify::stratify(
            &data,
            m,
            n,
            manual_cutoff as u64,
            seed as u64,
        )?;

        // Wire shape: cutoff as an integer-valued double, 0-based
        // hypermutant indices (documented decision, docs/ffi-surface.md),
        // and the retained-bulk cluster stats.
        let pairs = vec![
            ("cutoff", Robj::from(decision.cutoff as f64)),
            (
                "hypermutant_idx",
                Robj::from(decision.hypermutant_idx.clone()),
            ),
            (
                "n_hypermutants",
                Robj::from(decision.hypermutant_idx.len() as f64),
            ),
            (
                "cluster_stats",
                Robj::from(List::from_pairs(vec![
                    ("retained_mean", Robj::from(decision.cluster.retained_mean)),
                    ("retained_sd", Robj::from(decision.cluster.retained_sd)),
                    (
                        "retained_n",
                        Robj::from(decision.cluster.retained_n as f64),
                    ),
                    ("n_fits", Robj::from(decision.cluster.n_fits as f64)),
                    ("converged", Robj::from(decision.cluster.converged)),
                ])),
            ),
        ];
        Ok(Robj::from(List::from_pairs(pairs)))
    })())
}

// ---------------------------------------------------------------------------
// U-M2-03: default consensus-CV extraction pipeline (`ms_pipeline_rust`,
// FFI-internal name — the user faces are `ms_extract(method = NULL)` (D16
// default path) and `ms_select_k()` in R/extract.R + R/kselect-select.R).
// The pure orchestration core lives in `pipeline.rs`; this adapter owns the
// R-matrix handoff (the same t(counts) layout contract as ms_extract_rust)
// and the scalar domain guards.
// ---------------------------------------------------------------------------

#[extendr]
#[allow(clippy::too_many_arguments)]
fn ms_pipeline_rust(
    counts: Robj,
    k: i32,
    replicates: i32,
    max_iter: i32,
    seed: i32,
    k_folds: i32,
    n_seeds: i32,
    n_threads: i32,
) -> Robj {
    condition::kernel_result_to_robj((|| -> Result<Robj, MsError> {
        // Argument guards (contract 4): explicit, error-not-panic. The
        // pipeline core re-checks the rank bounds against the matrix.
        if k < 1 {
            return Err(MsError::new("argument", format!("k must be >= 1, got {k}")).with_i(k as i64));
        }
        if replicates < 2 {
            return Err(MsError::new(
                "argument",
                format!("replicates must be >= 2 (the consensus silhouette needs two members per cluster), got {replicates}"),
            )
            .with_i(replicates as i64));
        }
        if max_iter < 1 {
            return Err(MsError::new(
                "argument",
                format!("max_iter must be >= 1, got {max_iter}"),
            ));
        }
        if seed < 0 {
            return Err(MsError::new(
                "argument",
                format!("seed must be >= 0, got {seed}"),
            ));
        }
        if k_folds < 2 {
            return Err(MsError::new(
                "argument",
                format!("k_folds must be >= 2, got {k_folds}"),
            ));
        }
        if n_seeds < 1 {
            return Err(MsError::new(
                "argument",
                format!("n_seeds must be >= 1, got {n_seeds}"),
            ));
        }
        if n_threads < 0 {
            return Err(MsError::new(
                "argument",
                format!("n_threads must be >= 0 (0 = rayon default), got {n_threads}"),
            ));
        }
        // Layout contract (extract.rs module docs, the transposition trap):
        // R passes t(counts) — an n x m double matrix whose column-major
        // flat buffer IS the row-major m×n V; zero marshalling here.
        let (n, m, v) = with_matrix_f64(&counts, |nrow, ncol, data| Ok((nrow, ncol, data.to_vec())))?;
        // Contract 7: the parallel ensemble phase polls chunk boundaries on
        // the main thread; the sequential consensus/refit/CV phases are
        // bounded (declared decision, pipeline.rs module docs). Workers see
        // only the AtomicBool.
        let cancelled = AtomicBool::new(false);
        let mut boundary = || unsafe { R_CheckUserInterrupt() };
        let fit = pipeline::run_pipeline(
            &v,
            m,
            n,
            k as usize,
            replicates as usize,
            max_iter as usize,
            seed as u64,
            k_folds as usize,
            n_seeds as usize,
            n_threads as usize,
            &cancelled,
            &mut boundary,
        )?;

        // Wire shape (contract 2, column-major matrices). Optional CV
        // entries cross as NaN (R maps NaN -> NA_real_); a 0 argmin_rank
        // means "no finite rank total".
        let kk = k as usize;
        let consensus_w = extendr_api::wrapper::RMatrix::new_matrix(m, kk, |r, c| {
            fit.consensus_w[r * kk + c]
        });
        let nnls_exposures =
            extendr_api::wrapper::RMatrix::new_matrix(kk, n, |r, c| fit.nnls_h[r * n + c]);
        let nanify = |xs: &[Option<f64>]| {
            xs.iter()
                .map(|x| x.unwrap_or(f64::NAN))
                .collect::<Vec<f64>>()
        };
        let pairs = vec![
            ("consensus_W", Robj::from(consensus_w)),
            (
                "stability_per_cluster",
                Robj::from(fit.cluster_stability.clone()),
            ),
            ("avg_stability", Robj::from(fit.avg_stability)),
            ("nnls_exposures", Robj::from(nnls_exposures)),
            ("cv_per_rank", Robj::from(nanify(&fit.cv_per_rank))),
            (
                "cv_per_rank_train",
                Robj::from(nanify(&fit.cv_per_rank_train)),
            ),
            ("fold_test_deviance", Robj::from(nanify(&fit.fold_test))),
            (
                "argmin_rank",
                Robj::from(fit.argmin_rank.map_or(0i32, |r| r.min(i32::MAX as usize) as i32)),
            ),
            ("consensus_best_restart", Robj::from(fit.best_restart.min(i32::MAX as usize) as i32)),
            ("consensus_n_rounds", Robj::from(fit.n_rounds.min(i32::MAX as usize) as i32)),
            ("consensus_converged", Robj::from(fit.converged)),
        ];
        Ok(Robj::from(List::from_pairs(pairs)))
    })())
}

// ---------------------------------------------------------------------------
// U-M2-04/05 engine faces: ARD-NMF (SignatureAnalyzer semantics, engine/ard.rs)
// and penalized sparse NMF (Leplat-Gillis volume / SparseSignatures L1L1,
// engine/sparse.rs). Both share the ms_extract_rust layout contract: R passes
// `t(counts)` -- the n_samples x m_channels column-major flat buffer IS the
// kernel's row-major m x n V (module docs of `extract.rs`, the transposition
// trap). Declared bounded-duration, non-interruptible (single fit, no chunk
// structure -- same decision as ms_extract_rust); n_threads validated only
// (A7: sequential kernels are trivially thread-invariant).
// ---------------------------------------------------------------------------

#[extendr]
#[allow(clippy::too_many_arguments)] // FFI face: hyper-parameters are part of the frozen signature
fn ms_ard_rust(
    counts: Robj,
    k0: i32,
    max_iter: i32,
    tol: f64,
    a0: f64,
    b0: f64,
    seed: i32,
    n_threads: i32,
) -> Robj {
    condition::kernel_result_to_robj((|| -> Result<Robj, MsError> {
        if k0 < 1 {
            return Err(MsError::new("argument", format!("k0 must be >= 1, got {k0}"))
                .with_i(k0 as i64));
        }
        if max_iter < 0 {
            return Err(MsError::new(
                "argument",
                format!("max_iter must be >= 0, got {max_iter}"),
            ));
        }
        if seed < 0 {
            return Err(MsError::new("argument", format!("seed must be >= 0, got {seed}")));
        }
        if !tol.is_finite() || tol < 0.0 {
            return Err(MsError::new(
                "argument",
                format!("tol must be finite and >= 0, got {tol}"),
            ));
        }
        if !a0.is_finite() || a0 <= 0.0 || !b0.is_finite() || b0 <= 0.0 {
            return Err(MsError::new(
                "argument",
                format!("a0/b0 must be finite and > 0, got a0={a0}, b0={b0}"),
            ));
        }
        if n_threads < 0 {
            return Err(MsError::new(
                "argument",
                format!("n_threads must be >= 0 (0 = rayon default), got {n_threads}"),
            ));
        }
        let (n, m, v) =
            with_matrix_f64(&counts, |nrow, ncol, data| Ok((nrow, ncol, data.to_vec())))?;
        let fit = msuiter_engine::ard::fit_ard(
            &v,
            m,
            n,
            k0 as usize,
            max_iter as usize,
            tol,
            a0,
            b0,
            seed as u64,
        )?;
        let k_est = fit.k_est;
        let signatures = extendr_api::wrapper::RMatrix::new_matrix(m, k_est, |r, c| {
            fit.w_active[r * k_est + c]
        });
        let exposures =
            extendr_api::wrapper::RMatrix::new_matrix(k_est, n, |r, c| fit.h_active[r * n + c]);
        let active: Vec<Robj> = fit.active.iter().map(|&a| Robj::from(a)).collect();
        let pairs = vec![
            ("signatures", Robj::from(signatures)),
            ("exposures", Robj::from(exposures)),
            ("active", Robj::from(active)),
            ("k_est", Robj::from(k_est.min(i32::MAX as usize) as i32)),
            ("beta", Robj::from(fit.beta.clone())),
            ("beta_cut", Robj::from(fit.beta_cut)),
            ("objective", Robj::from(fit.objective)),
            (
                "iterations",
                Robj::from(fit.iterations.min(i32::MAX as usize) as i32),
            ),
            ("converged", Robj::from(fit.converged)),
        ];
        Ok(Robj::from(List::from_pairs(pairs)))
    })())
}

#[extendr]
#[allow(clippy::too_many_arguments)] // FFI face: hyper-parameters are part of the frozen signature
fn ms_sparse_rust(
    counts: Robj,
    k: i32,
    max_iter: i32,
    variant: String,
    lambda: f64,
    mu: f64,
    delta: f64,
    tol: f64,
    seed: i32,
    n_threads: i32,
) -> Robj {
    condition::kernel_result_to_robj((|| -> Result<Robj, MsError> {
        if k < 1 {
            return Err(MsError::new("argument", format!("k must be >= 1, got {k}"))
                .with_i(k as i64));
        }
        if max_iter < 0 {
            return Err(MsError::new(
                "argument",
                format!("max_iter must be >= 0, got {max_iter}"),
            ));
        }
        if seed < 0 {
            return Err(MsError::new("argument", format!("seed must be >= 0, got {seed}")));
        }
        if !matches!(variant.as_str(), "volume" | "l1") {
            return Err(MsError::new(
                "argument",
                format!("variant must be \"volume\" or \"l1\", got {variant:?}"),
            ));
        }
        if !lambda.is_finite() || lambda < 0.0 || !mu.is_finite() || mu < 0.0 {
            return Err(MsError::new(
                "argument",
                format!("lambda/mu must be finite and >= 0, got lambda={lambda}, mu={mu}"),
            ));
        }
        if !tol.is_finite() || tol < 0.0 {
            return Err(MsError::new(
                "argument",
                format!("tol must be finite and >= 0, got {tol}"),
            ));
        }
        if n_threads < 0 {
            return Err(MsError::new(
                "argument",
                format!("n_threads must be >= 0 (0 = rayon default), got {n_threads}"),
            ));
        }
        let (n, m, v) =
            with_matrix_f64(&counts, |nrow, ncol, data| Ok((nrow, ncol, data.to_vec())))?;
        let fit = match variant.as_str() {
            "volume" => msuiter_engine::sparse::fit_volume(
                &v,
                m,
                n,
                k as usize,
                lambda,
                if delta > 0.0 { delta } else { 1.0 },
                max_iter as usize,
                tol,
                seed as u64,
            )?,
            _ => msuiter_engine::sparse::fit_sparse_l1(
                &v,
                m,
                n,
                k as usize,
                lambda,
                mu,
                max_iter as usize,
                tol,
                seed as u64,
            )?,
        };
        let kk = k as usize;
        let signatures =
            extendr_api::wrapper::RMatrix::new_matrix(m, kk, |r, c| fit.w[r * kk + c]);
        let exposures =
            extendr_api::wrapper::RMatrix::new_matrix(kk, n, |r, c| fit.h[r * n + c]);
        let pairs = vec![
            ("signatures", Robj::from(signatures)),
            ("exposures", Robj::from(exposures)),
            ("objective", Robj::from(fit.objective)),
            (
                "iterations",
                Robj::from(fit.iterations.min(i32::MAX as usize) as i32),
            ),
            ("converged", Robj::from(fit.converged)),
        ];
        Ok(Robj::from(List::from_pairs(pairs)))
    })())
}

// ---------------------------------------------------------------------------
// U-M2-01 evaluation face: the memo section 1.5 match-protocol sweep
// (Hungarian one-to-one + Islam-compat greedy + split/merge classes) over
// one cosine matrix. Data face for the M4 `ms_compare()` protocols; the
// kernel-side `match_solutions` (engine/consensus.rs) is the audited
// implementation.
// ---------------------------------------------------------------------------

#[extendr]
fn ms_match_solutions_rust(estimated: Robj, reference: Robj, dim: i32, thresholds: Robj) -> Robj {
    condition::kernel_result_to_robj((|| -> Result<Robj, MsError> {
        if dim < 1 {
            return Err(
                MsError::new("argument", format!("dim must be >= 1, got {dim}")).with_i(dim as i64)
            );
        }
        let est = estimated
            .as_real_vector()
            .ok_or_else(|| MsError::new("argument", "estimated must be a double vector"))?;
        let rf = reference
            .as_real_vector()
            .ok_or_else(|| MsError::new("argument", "reference must be a double vector"))?;
        let tau = thresholds
            .as_real_vector()
            .ok_or_else(|| MsError::new("argument", "thresholds must be a double vector"))?;
        if tau.is_empty() {
            return Err(MsError::new("argument", "thresholds must be non-empty"));
        }
        let sweep =
            msuiter_engine::consensus::match_solutions(&est, &rf, dim as usize, &tau)?;
        // Flat per-threshold vectors in sweep order (R re-splits by rows).
        let mut th: Vec<f64> = Vec::new();
        let mut tp_n: Vec<i32> = Vec::new();
        let mut fp: Vec<i32> = Vec::new();
        let mut fn_miss: Vec<i32> = Vec::new();
        let mut est_idx: Vec<i32> = Vec::new();
        let mut est_class: Vec<String> = Vec::new();
        let mut est_ref: Vec<i32> = Vec::new();
        for tm in &sweep {
            th.push(tm.threshold);
            tp_n.push(tm.tp.len().min(i32::MAX as usize) as i32);
            fp.push(tm.fp.min(i32::MAX as usize) as i32);
            fn_miss.push(tm.fn_count.min(i32::MAX as usize) as i32);
            for (s, cls) in tm.estimated_classes.iter().enumerate() {
                est_idx.push((s + 1).min(i32::MAX as usize) as i32);
                est_class.push(
                    match cls {
                        msuiter_engine::consensus::EstimatedClass::Matched { .. } => "matched",
                        msuiter_engine::consensus::EstimatedClass::Split { .. } => "split",
                        msuiter_engine::consensus::EstimatedClass::Merge { .. } => "merge",
                        msuiter_engine::consensus::EstimatedClass::Novel => "novel",
                    }
                    .to_string(),
                );
                est_ref.push(match cls {
                    msuiter_engine::consensus::EstimatedClass::Matched { reference }
                    | msuiter_engine::consensus::EstimatedClass::Split { reference } => {
                        (*reference + 1).min(i32::MAX as usize) as i32
                    }
                    msuiter_engine::consensus::EstimatedClass::Merge { references } => {
                        (references[0] + 1).min(i32::MAX as usize) as i32
                    }
                    msuiter_engine::consensus::EstimatedClass::Novel => 0,
                });
            }
        }
        let p_per_threshold: Vec<i32> = sweep
            .iter()
            .map(|tm| tm.estimated_classes.len().min(i32::MAX as usize) as i32)
            .collect();
        let pairs = vec![
            ("threshold", Robj::from(th)),
            ("tp", Robj::from(tp_n)),
            ("fp", Robj::from(fp)),
            ("fn", Robj::from(fn_miss)),
            ("p_per_threshold", Robj::from(p_per_threshold)),
            ("estimate_index", Robj::from(est_idx)),
            ("estimated_class", Robj::from(est_class)),
            ("reference_index", Robj::from(est_ref)),
        ];
        Ok(Robj::from(List::from_pairs(pairs)))
    })())
}

// Generates the R registration entry point

// Generates the R registration entry point (`R_init_msuiter_extendr`,
// forwarded by `src/entrypoint.c`) and the wrapper metadata consumed by
// the `document` binary.
extendr_module! {
    mod msuiter;
    fn msffi_column_major_probe;
    fn msffi_na_probe;
    fn msffi_error_probe;
    fn msffi_interrupt_probe;
    fn msffi_thread_probe;
    fn msffi_nmf_replicates_probe;
    fn msffi_build_info;
    fn ms_tally_rust;
    fn ms_extract_rust;
    fn ms_pipeline_rust;
    fn ms_stratify_rust;
    fn ms_ard_rust;
    fn ms_sparse_rust;
    fn ms_fit_rust;
    fn ms_match_solutions_rust;
}

#[cfg(test)]
mod tests {
    use msuiter_catalog as catalog;
    use msuiter_engine as engine;

    /// Workspace direction contract (ARCH §2): the FFI shell links both
    /// lower crates, which stay FFI-free.
    #[test]
    fn ffi_links_engine_and_catalog() {
        assert_eq!(
            engine::CRATE_ROLE,
            "engine: pure numeric kernels, FFI-free"
        );
        assert_eq!(
            catalog::CRATE_ROLE,
            "catalog: channel semantics, FFI-agnostic"
        );
    }

    /// The build-info probe exposes the toolchain recorded by build.rs.
    #[test]
    fn build_info_carries_package_version() {
        let info = super::probes::build_info();
        let version = info
            .iter()
            .find(|(k, _)| *k == "package_version")
            .map(|(_, v)| v.clone())
            .unwrap();
        assert_eq!(version, env!("CARGO_PKG_VERSION"));
    }
}
