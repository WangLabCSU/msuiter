# On-load hooks.
# * S7 method registration (U-M0-03): finalizes method tables for the S7
#   classes defined in R/classes-*.R (flat prefixed sources; see the
#   implementation note in docs/ARCHITECTURE.md section 3.1 — R packages
#   only install top-level R/ files, so the ARCHITECTURE section tree maps
#   to `<section>-<topic>.R` names).
# * FFI entry-point registration happens at the C level via
#   `src/entrypoint.c` (rextendr `.registration = TRUE`), so no R-side
#   init call is needed here.
# * Option plumbing (`msuiter.threads`, per-call thread pool defaults)
#   lands with the FFI hard contracts in U-M0-09.
.onLoad <- function(libname, pkgname) {
  S7::methods_register()
  invisible(NULL)
}
