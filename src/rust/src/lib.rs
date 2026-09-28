//! msuiter FFI shell.
//!
//! The only crate allowed to contain `unsafe` and the only one depending
//! on `extendr-api` (`docs/ARCHITECTURE.md` §2). Stateless per D12: no
//! handles, no `.state`, one call in/out.
//!
//! M0 scaffold: zero user-visible exports. The frozen FFI surface
//! (`ms_tally_rust`, `ms_extract_rust`, ...) lands in U-M1s-09 and is
//! reviewed per release via `docs/ffi-surface.md` (U-M0-09).

use extendr_api::prelude::*;

// Generates the R registration entry point (`R_init_msuiter_extendr`,
// forwarded by `src/entrypoint.c`) and the wrapper metadata consumed by
// the `document` binary. Intentionally empty for this milestone.
extendr_module! {
    mod msuiter;
}

#[cfg(test)]
mod tests {
    use msuiter_catalog as catalog;
    use msuiter_engine as engine;

    /// Workspace direction contract (ARCH §2): the FFI shell links both
    /// lower crates, which stay FFI-free. This is the single M0 test;
    /// algorithm stubs are forbidden in this milestone.
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
}
