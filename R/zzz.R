# On-load hooks. Deliberately minimal in M0 (U-M0-01):
# * FFI entry-point registration happens at the C level via
#   `src/entrypoint.c` (rextendr `.registration = TRUE`), so no R-side
#   init call is needed here.
# * Option plumbing (`msuiter.threads`, per-call thread pool defaults)
#   lands with the FFI hard contracts in U-M0-09; S7 method registration
#   (`S7::methods_register()`) lands with the class skeleton in U-M0-03.
.onLoad <- function(libname, pkgname) {
  invisible(NULL)
}
