#!/usr/bin/env Rscript
# catalog-currency.R -- the operator CLI of the P5 catalog-currency
# instrument (parity plan docs/research/09 section 5, phase P5).
#
# It answers one operational question at the console: is msuiter's pinned
# COSMIC catalog snapshot still current against the official COSMIC release
# line? -- and keeps the answer machine-checkable in CI.
#
# Subcommands
#   verify    [default] read-only verdict over the cache vs the committed
#             registry + the shipped refdb governance (never fetches).
#   update    (re-)derive the cache from the official source documents, or
#             from an injected `--source` capture (offline by construction).
#   registry  print the committed digest sidecar (pinned digests, URLs,
#             version labels, the UNMEASURED matrix-bytes policy).
#   help      this usage.
#
# Flags
#   --source=PATH     injected downloads-page file or split document dir
#                     (update only); with it, no network leg is attempted.
#   --cache=DIR       override the cache directory (else the package
#                     resolves it: option msuiter.catalog_currency.cache_dir
#                     -> env MSUITER_CATALOG_CURRENCY_CACHE_DIR -> user cache).
#   --registry=PATH   override the committed sidecar path (review/fixture).
#   --offline         update: refuse every network leg (requires --source).
#   --verbose         print the full per-document report, not just the verdict.
#
# Exit codes (the CI contract): 0 = verdict ok (or a non-actionable command),
#   1 = a currency verdict that is not `ok` (behind / drift / corrupt /
#   no-cache / inconsistent), 2 = usage or load error.
#
# D3 law: this tool only ever handles digests, URLs, version labels and
# structural shape facts -- never COSMIC numeric content.
#
# macOS note: the load_all step compiles the native core; on a broken-SDK
# toolchain export SDKROOT=<working SDK> first (same as the other tools).

options(warn = 1)

.root <- local({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", grep("^--file=", a, value = TRUE))
  if (length(f) > 0L) {
    cand <- normalizePath(f[1L], mustWork = FALSE)
    if (file.exists(cand)) dirname(dirname(cand)) else dirname(dirname(dirname(cand)))
  } else {
    normalizePath(".")
  }
})

.args <- local({
  # trailingOnly = TRUE yields exactly the script's own arguments (the R
  # binary path and the --file= injection are excluded by construction).
  commandArgs(trailingOnly = TRUE)
})

.get_opt <- function(flag, default = NULL) {
  hit <- grepl(paste0("^", flag, "="), .args)
  if (!any(hit)) return(default)
  sub(paste0("^", flag, "="), "", .args[hit][1L])
}

.usage <- function() {
  writeLines(c(
    "usage: Rscript tools/catalog-currency.R [verify|update|registry|help] [flags]",
    "",
    "  verify    read-only verdict (cache vs committed registry vs shipped refdb)",
    "  update    (re-)derive the cache from the official documents or --source",
    "  registry  print the committed digest sidecar",
    "  help      this usage",
    "",
    "flags: --source=PATH --cache=DIR --registry=PATH --offline --verbose",
    "exit:  0 = ok | 1 = non-ok currency verdict | 2 = usage/load error"
  ))
}

.subcommand <- local({
  positional <- .args[!grepl("^--", .args)]
  if (!length(positional)) "verify" else positional[1L]
})

if (.subcommand %in% c("help", "--help", "-h")) {
  .usage()
  quit(save = "no", status = 0L)
}
if (!.subcommand %in% c("verify", "update", "registry")) {
  cat("catalog-currency: unknown subcommand '", .subcommand, "'\n\n", sep = "")
  .usage()
  quit(save = "no", status = 2L)
}

# Load the package face (source checkout preferred, else installed).
if (requireNamespace("pkgload", quietly = TRUE) && dir.exists(file.path(.root, "R"))) {
  suppressPackageStartupMessages(pkgload::load_all(.root, quiet = TRUE))
} else if (requireNamespace("msuiter", quietly = TRUE)) {
  suppressPackageStartupMessages(library(msuiter))
} else {
  cat("catalog-currency: cannot load msuiter (no source tree, not installed)\n")
  quit(save = "no", status = 2L)
}

.cache    <- .get_opt("--cache")
.registry <- .get_opt("--registry")
.source   <- .get_opt("--source")
.offline  <- "--offline" %in% .args
.verbose  <- "--verbose" %in% .args

report <- function(rep, banner) {
  if (isTRUE(.verbose)) {
    print(rep)
  } else {
    cat(sprintf("%s: verdict=%s version=%s pinned=%s latest=%s\n",
                banner, rep$verdict, rep$version_state,
                rep$pinned$release,
                if (identical(rep$latest$status, "measured")) rep$latest$release else "-"))
    if (!identical(rep$verdict, "ok")) {
      for (m in rep$messages) cat("  ! ", m, "\n", sep = "")
      for (h in rep$hints) cat("  i ", h, "\n", sep = "")
    }
  }
  if (identical(rep$verdict, "ok")) 0L else 1L
}

status <- tryCatch({
  if (identical(.subcommand, "registry")) {
    reg <- ms_catalog_registry(path = .registry)
    cat("catalog-currency committed registry\n")
    cat(sprintf("  schema %s | pinned_release %s\n", reg$schema_version, reg$pinned_release))
    cat(sprintf("  mirror %s @ %s (%s)\n", reg$mirror$repo,
                substr(reg$mirror$commit, 1L, 12L), reg$mirror$license))
    cat(sprintf("  refdb  %s | governed: %s\n", reg$refdb$version,
                paste(reg$refdb$governed_files, collapse = ", ")))
    cat(sprintf("  page   %s\n", reg$official$page_url))
    for (k in names(reg$official$documents)) {
      d <- reg$official$documents[[k]]
      cat(sprintf("  %-16s sha256 %s (%d bytes)\n", k, d$sha256, d$bytes))
    }
    cat(sprintf("  releases %s | latest %s | structure @ %s\n",
                paste(reg$official$releases, collapse = ", "),
                reg$official$latest_release, reg$official$structure_release))
    cat(sprintf("  matrix-bytes: %s\n", reg$matrix_bytes$status))
    0L
  } else if (identical(.subcommand, "update")) {
    rep <- ms_catalog_currency_update(source = .source, cache = .cache,
                                    registry = .registry, offline = .offline)
    report(rep, "update")
  } else {
    rep <- ms_catalog_currency(cache = .cache, registry = .registry)
    report(rep, "verify")
  }
}, error = function(e) {
  cat("catalog-currency: ", conditionMessage(e), "\n", sep = "")
  2L
})

quit(save = "no", status = status)
