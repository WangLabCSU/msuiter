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

.ms_root <- local({
  found <- NA_character_
  d <- try(normalizePath(getwd()), silent = TRUE)
  if (!inherits(d, "try-error") && nzchar(d)) {
    repeat {
      f <- file.path(d, "DESCRIPTION")
      if (file.exists(f)) {
        l <- try(readLines(f, n = 40L, warn = FALSE), silent = TRUE)
        if (!inherits(l, "try-error") &&
            length(grep("^Package:[[:space:]]*msuiter[[:space:]]*$", l))) {
          found <- d
          break
        }
      }
      up <- dirname(d)
      if (identical(up, d)) break
      d <- up
    }
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
