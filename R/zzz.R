# On-load hooks.
# * S7 method registration (U-M0-03): finalizes method tables for the S7
#   classes defined in R/classes-*.R (flat prefixed sources; see the
#   implementation note in docs/ARCHITECTURE.md section 3.1 — R packages
#   only install top-level R/ files, so the ARCHITECTURE section tree maps
#   to `<section>-<topic>.R` names).
# * FFI entry-point registration happens at the C level via
#   `src/entrypoint.c` (rextendr `.registration = TRUE`), so no R-side
#   init call is needed here.
# * Option plumbing (`msuiter.threads`, U-M0-09 / FFI contract 6): the
#   per-call rayon pool size for every Rust call. The option is
#   deliberately left NULL by default (= "rayon default, all cores");
#   the effective value is resolved at CALL time by
#   `.ms_resolve_threads()` (R/ffi-probes.R), which honors the
#   `_R_CHECK_LIMIT_CORES_` switch (default capped at 2 under
#   `R CMD check --as-cran`). Freezing a numeric default here would bake
#   the load-time machine's core count into every session and break the
#   thread-count invariance contract (identical() output for
#   threads in {1, N}, synthesis A7).
#   Set it explicitly with, e.g.: options(msuiter.threads = 4L)
.onLoad <- function(libname, pkgname) {
  S7::methods_register()
  invisible(NULL)
}
