# ms_sitrep(): installation situation report (U-M0-09; ARCHITECTURE
# section 1.5 — diagnostics are part of the platform's default entry
# point). Reports what exists today and says "not yet available" for the
# data that ships in later milestones (M1s+).

#' Situation report for the msuiter installation
#'
#' Prints and (invisibly) returns the state of the installation: R and
#' package versions, the compiled Rust compute core (toolchain reported
#' through the `msffi_build_info` FFI probe), the per-call thread-pool
#' configuration, the bundled reference-database status and the
#' msuiter-related options. Items that do not exist in this release are
#' reported as `"not yet available"` rather than guessed.
#'
#' @return A named list (invisibly) with the collected sections:
#'   `r_version`, `package_version`, `rust_core`, `threads`, `refdb`,
#'   `options`, `not_yet_available`.
#' @export
#' @examples
#' ms_sitrep()
ms_sitrep <- function() {
  pkg_version <- as.character(utils::packageVersion("msuiter"))

  rust <- tryCatch(.msffi_build_info(), error = function(e) NULL)
  rust_core <- if (is.null(rust)) {
    "not available (FFI probe failed; the compiled core did not load)"
  } else {
    sprintf(
      "rustc %s (%s/%s), FFI package %s",
      rust$rustc_version, rust$target_os, rust$target_arch, rust$package_version
    )
  }

  opt_threads <- getOption("msuiter.threads")
  effective <- .ms_resolve_threads()
  threads <- list(
    option = opt_threads,
    effective = effective,
    check_limit_cores = nzchar(Sys.getenv("_R_CHECK_LIMIT_CORES_", "")),
    description = if (identical(effective, 0L)) {
      "rayon default (all cores); one per-call pool per top-level call"
    } else {
      sprintf("%d threads; one per-call pool per top-level call", effective)
    }
  )

  # refdb v1 shipped in U-M3a-06: report the bundled version honestly.
  refdb <- "COSMIC v3.6 bundled (SBS96/DBS78 GRCh37+GRCh38, ID83 GRCh37;\n    schema_version 1; see ms_refdb_bundled())"

  not_yet_available <- c(
    "COSMIC on-demand update (tools::R_user_dir cache; planned for M4)",
    paste(
      "MSU-Fit calibration bench result tables (the calibration experiment",
      "face -- ms_calibration_grid()/ms_calibration_verdict()/",
      "plot_calibration_curve()/ms_calibration_sanity() -- shipped in M3b;",
      "the frozen-protocol coverage tables land with the paper bench)"
    )
  )

  msuiter_opts <- options()[grepl("^msuiter\\.", names(options()))]
  out <- list(
    r_version = R.version.string,
    package_version = pkg_version,
    rust_core = rust_core,
    threads = threads,
    refdb = refdb,
    options = msuiter_opts,
    not_yet_available = not_yet_available
  )

  cat(sprintf("== msuiter %s :: situation report ==\n", pkg_version))
  cat(sprintf("R         : %s\n", out$r_version))
  cat(sprintf("Rust core : %s\n", rust_core))
  cat(sprintf("Threads   : %s (option msuiter.threads = %s%s)\n",
              threads$description,
              format(opt_threads),
              if (threads$check_limit_cores)
                "; _R_CHECK_LIMIT_CORES_ active (default capped at 2)"
              else ""))
  cat(sprintf("Refdb     : %s\n", refdb))
  if (length(out$options) == 0L) {
    cat("Options   : none set beyond defaults\n")
  } else {
    cat("Options   :\n")
    for (nm in names(out$options)) {
      cat(sprintf("  - %s = %s\n", nm, format(out$options[[nm]])))
    }
  }
  cat("Not yet available:\n")
  for (item in not_yet_available) {
    cat(sprintf("  - %s\n", item))
  }

  invisible(out)
}
