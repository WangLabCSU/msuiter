//! Build script for the msuiter FFI shell (U-M0-09).
//!
//! Records the rustc toolchain that compiles the compute core so that
//! `ms_sitrep()` can report it through the `msffi_build_info` probe.
//! Std-only: no new dependencies (frozen budget, ARCHITECTURE §2).

use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=build.rs");

    // Cargo hands the build script the exact rustc it drives via $RUSTC.
    // Falling back to a PATH lookup would report whatever `rustc` happens
    // to be first on PATH (e.g. a conda-installed one), not the toolchain
    // compiling this crate.
    let rustc_bin = std::env::var("RUSTC").unwrap_or_else(|_| "rustc".to_string());
    let version = Command::new(&rustc_bin)
        .arg("--version")
        .output()
        .ok()
        .and_then(|out| String::from_utf8(out.stdout).ok())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        // Drop the "rustc " prefix of `rustc --version`; ms_sitrep adds its
        // own label.
        .map(|s| {
            s.strip_prefix("rustc ")
                .unwrap_or(&s)
                .trim()
                .to_string()
        })
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "unknown".to_string());
    println!("cargo:rustc-env=MSUITER_RUSTC_VERSION={version}");

    if let Ok(target) = std::env::var("TARGET") {
        println!("cargo:rustc-env=MSUITER_RUSTC_TARGET={target}");
    }
}
