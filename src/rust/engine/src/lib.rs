//! msuiter engine: pure numeric kernels, zero FFI.
//!
//! Layer L1 of `docs/ARCHITECTURE.md` §1/§2. This crate must never depend
//! on `extendr-api` and must never contain `unsafe` code. The M0 scaffold
//! (U-M0-01) ships no algorithms; kernels land from U-M1s-01 onwards.

#![forbid(unsafe_code)]

pub mod error;
pub mod linalg;
pub mod nmf;
pub mod nndsvd;
pub mod nnls;
pub mod resample;
pub mod rng;

pub use error::MsError;

/// Role marker used by the FFI shell's link test to assert the workspace
/// dependency direction (ffi → catalog → engine) holds and both crates
/// link cleanly. Keep in sync with `docs/ARCHITECTURE.md` §2.
pub const CRATE_ROLE: &str = "engine: pure numeric kernels, FFI-free";
