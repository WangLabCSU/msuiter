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
//! the error mapping):
//! 1. stateless   — every `msffi_*` is one call in/out, no globals;
//! 2. column-major — `msffi_column_major_probe`;
//! 3. NA/NaN      — R validator (primary) + `msffi_na_probe`;
//! 4. indexes     — explicit bounds checks, errors not panics (`msffi_error_probe`);
//! 5. errors      — `Result<_, MsError>` at the boundary only;
//! 6. threads     — per-call pool via `msffi_thread_probe` (thread-count invariance);
//! 7. interrupt   — `msffi_interrupt_probe` (boundary polling + worker `AtomicBool`);
//! 8. build       — Makevars/vendor discipline unchanged; `msffi_build_info` feeds `ms_sitrep()`.

use extendr_api::prelude::*;
use msuiter_engine::error::MsError;
use std::sync::atomic::{AtomicBool, Ordering};

mod condition;
mod probes;

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
fn msffi_build_info() -> Robj {
    let info = probes::build_info();
    let pairs: Vec<(&str, Robj)> = info
        .iter()
        .map(|(k, v)| (*k, Robj::from(v.as_str())))
        .collect();
    Robj::from(List::from_pairs(pairs))
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
    fn msffi_build_info;
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
