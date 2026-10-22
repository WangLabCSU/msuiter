# Check-layout-safe resource location for the repository-drift guards
# (U-M7-04 GO-04D). Under R CMD check the test phase runs from
# <out>/<pkg>.Rcheck/tests/testthat -- a SIBLING of the extracted tree --
# so the test_path('../../X') idiom resolves ABOVE the check directory and
# every repo read there dies or silently mis-gates (measured live
# 2026-10-10; tools/check-layout-sim.R reproduces the layout from the real
# tarball). Consumers resolve artifacts through .ms_src() instead:
#   (a) ancestor-walk from getwd() to the msuiter package root (a directory
#       whose DESCRIPTION declares Package: msuiter), then
#   (b) the installed tree via system.file().
# NA when neither source has it -- callers skip with an explicit reason,
# never read blind.
#
# The walk reads the FULL DESCRIPTION now: the Built: discriminator can
# land past line 40, so the old n = 40L window is gone, digit and all.
# <!-- census-exempt tokens: 40 -->

.ms_root <- local({
  found <- NA_character_
  d <- try(normalizePath(getwd()), silent = TRUE)
  ok <- !inherits(d, "try-error") && nzchar(d)
  while (ok && is.na(found)) {
    f <- file.path(d, "DESCRIPTION")
    if (file.exists(f)) {
      l <- try(readLines(f, warn = FALSE), silent = TRUE)
      if (!inherits(l, "try-error") &&
          length(grep("^Package:[[:space:]]*msuiter[[:space:]]*$", l)) &&
          # An INSTALLED DESCRIPTION also says `Package: msuiter`; the
          # Built: stamp INSTALL writes is what separates a checkout from
          # an install tree (covr's installed testthat child otherwise
          # resolves .ms_root INTO the temp lib and the committed-file
          # laws there LOUDLY die -- banked: run 39536641469 coverage log,
          # "covr coverage failed under instrumentation").
          !any(grepl("^Built:", l, useBytes = FALSE))) {
        found <- d
      }
    }
    up <- dirname(d)
    if (identical(up, d)) ok <- FALSE
    d <- up
  }
  found
})

# root_rel: path under the repository root. inst_rel: path under the
# installed package root (defaults to root_rel; inst/CITATION installs as
# the root CITATION, tools/* keep their subpath). Returns the first existing
# candidate, or NA_character_.
.ms_src <- function(root_rel, inst_rel = NULL) {
  if (is.null(inst_rel)) inst_rel <- root_rel
  cand <- if (!is.na(.ms_root)) file.path(.ms_root, root_rel) else NA_character_
  if (!is.na(cand) && file.exists(cand)) return(cand)
  hit <- try(system.file(inst_rel, package = "msuiter"), silent = TRUE)
  if (!inherits(hit, "try-error") && !is.na(hit[1L]) && nzchar(hit[1L]) &&
      file.exists(hit[1L])) return(hit[1L])
  NA_character_
}

# The CITATION twin: inst/CITATION in the source tree, root CITATION once
# installed.
.cit_src <- function() .ms_src("inst/CITATION", "CITATION")

# R CMD check's test phase (tools:::add_dummies, re-verified verbatim on the
# live 4.5.2) creates <checkdir>/tests/R_check_bin/{R,Rscript} executables
# (mode 0755) whose whole body is the par. 1.6 echo warning + exit 1, and
# PREPENDS that directory to PATH -- every bare-name spawn dies there (CI
# arms 2026-10-10: the stub text surfaced inside every spawning guard's
# captured output). Suite spawns must therefore resolve R.home-absolute and
# never through PATH. Fail-closed STOP, never skip: a silent skip would
# re-open exactly the masking hole this helper exists to seal (a spawn that
# never ran would look like a spawn that passed).
.ms_rscript <- function() {
  p <- file.path(R.home(), "bin", "Rscript")
  if (!file.exists(p)) p <- file.path(R.home(), "bin", "Rscript.exe")
  if (!file.exists(p)) {
    stop(msg = "R.home-absolute Rscript not locatable -- refusing PATH-resolved spawn")
  }
  p
}

# Source-level extraction of the harness's top-level function definitions
# (shared by test-check-layout-sim-gen.R and test-check-layout-sim-sdkroot.R):
# the harness script executes on source, so a targeted helper is reached by
# parsing the file and evaluating only the targeted assignment expressions in
# a clean base-env child. Fail-closed: a requested symbol that no top-level
# assignment provides is a STOP, never a silent partial extraction.
.sim_defs <- function(file, names) {
  env <- new.env(parent = baseenv())
  found <- character()
  for (e in parse(file = file)) {
    if (is.call(e) && identical(as.character(e[[1L]]), "<-") &&
        is.name(e[[2L]]) && as.character(e[[2L]]) %in% names) {
      eval(e, envir = env)
      found <- unique(c(found, as.character(e[[2L]])))
    }
  }
  miss <- setdiff(names, found)
  if (length(miss)) {
    stop(paste0("harness generator symbols not extractable: ",
                paste(miss, collapse = ", ")))
  }
  env
}
