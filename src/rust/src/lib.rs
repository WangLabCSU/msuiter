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
//! the error mapping, `replicates.rs` for the first real-kernel driver):
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
mod probes;
mod replicates;
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

        // D12 (contract 1): one call in/out — the file handle and the
        // mapping are built here and dropped with this scope. SAFETY: the
        // mapping is read-only over a file opened read-only and is never
        // mutated or truncated while borrowed.
        let file = File::open(&genome_path).map_err(|e| {
            MsError::new("io", format!("cannot open genome file \"{genome_path}\": {e}"))
        })?;
        let mmap = unsafe { memmap2::Mmap::map(&file) }
            .map_err(|e| MsError::new("io", format!("cannot map genome file \"{genome_path}\": {e}")))?;
        let mut genome = msuiter_catalog::genome::TwoBitGenome::from_bytes(&mmap[..])?;

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
        };
        // Contract 7: single-threaded (M1s scope), so the boundary hook is
        // the whole interrupt story.
        let mut boundary = || unsafe { R_CheckUserInterrupt() };
        let result = tally::tally(&mut genome, &variants, tables, &mut boundary)?;

        let n_samples = sample_idx.len();
        let pairs = vec![
            ("sbs96", counts_matrix(&result.sbs96, SBS96_LEN, n_samples)?),
            ("sbs192", counts_matrix(&result.sbs192, SBS192_LEN, n_samples)?),
            ("sbs384", counts_matrix(&result.sbs384, SBS384_LEN, n_samples)?),
            ("sbs1536", counts_matrix(&result.sbs1536, SBS1536_LEN, n_samples)?),
            ("dbs78", counts_matrix(&result.dbs78, DBS78_LEN, n_samples)?),
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
