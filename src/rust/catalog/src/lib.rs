//! msuiter catalog: channel semantics, FFI-agnostic.
//!
//! Owns mutation channel definitions and event routing (SBS/DBS/ID/MNV
//! families; `docs/ARCHITECTURE.md` §2). FFI-free and `unsafe`-free by
//! contract. The M0 scaffold (U-M0-01) ships no algorithms; the channel
//! registry lands in U-M0-05 and U-M1s-06+.

#![forbid(unsafe_code)]

pub mod channels;
pub mod sbs;
pub mod genome;
pub mod dbs;
pub mod mnv;

/// Role marker used by the FFI shell's link test to assert the workspace
/// dependency direction (ffi → catalog → engine) holds and both crates
/// link cleanly. Keep in sync with `docs/ARCHITECTURE.md` §2.
pub const CRATE_ROLE: &str = "catalog: channel semantics, FFI-agnostic";
