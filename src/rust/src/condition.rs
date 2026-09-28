//! `MsError` → R condition conversion (U-M0-09, FFI contract 5).
//!
//! This module is the ONLY place where a kernel `Result` becomes an
//! R-visible error. The mapping produces a condition object with class
//! `c("msuiter_error_rust", "error", "condition")` — one frozen class for
//! the whole Rust layer — carrying the structured payload `message`,
//! `topic`, `i`, `j` and `c` (the i/j/c triple of ARCHITECTURE §3.5; `i` /
//! `j` are 1-based indices or NULL, `c` is the context string). The R
//! wrappers in `R/ffi-probes.R` re-signal the condition with `stop()`, so
//! `tryCatch` handlers see the documented class and payload end-to-end.
//!
//! Panics never take this path: the generated extendr wrapper catches any
//! panic (`catch_unwind`) and turns it into an R error, and
//! `entrypoint.c` registers the extendr panic hook — contract 5's "any
//! panic fails the whole call, no partial results".

use extendr_api::prelude::*;
use msuiter_engine::error::MsError;

/// Frozen R condition classes for errors raised by the Rust core.
const RUST_ERROR_CLASS: [&str; 3] = ["msuiter_error_rust", "error", "condition"];

/// 1-based index or R `NULL` (R integers are 32-bit; probe/kernel indices
/// fit comfortably, and larger values would already have failed bounds
/// checks contract 4).
fn index_robj(v: Option<i64>) -> Robj {
    match v {
        Some(x) => Robj::from(x as i32),
        None => Robj::from(()),
    }
}

/// Convert an `MsError` into an R condition object (not yet signalled).
pub fn ms_error_to_condition(e: &MsError) -> Robj {
    let pairs = vec![
        ("message", Robj::from(e.to_string())),
        ("topic", Robj::from(e.topic.as_str())),
        ("i", index_robj(e.i)),
        ("j", index_robj(e.j)),
        ("c", Robj::from(format!("rust kernel ({})", e.topic))),
    ];
    let mut robj = Robj::from(List::from_pairs(pairs));
    robj.set_class(RUST_ERROR_CLASS)
        .expect("set_class on a freshly built list cannot fail");
    robj
}

/// Convert a kernel `Result` into the value or the error condition object.
pub fn kernel_result_to_robj<T: Into<Robj>>(res: Result<T, MsError>) -> Robj {
    match res {
        Ok(v) => v.into(),
        Err(e) => ms_error_to_condition(&e),
    }
}
