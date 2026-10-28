# R/treatment-report.R -- the treatment-forensics reporting face (Phase-8 CS-3)
# Design memo: docs/devlog/2026-10-28-p8-treatment-forensics-design.md.
# Signature identities resolve through the sealed bundled refdb roster only;
# this file ships no reference numerics and fabricates no degraded-face rows.

# Governed default exposure map: therapy class bound to its officially
# recognised signature identities (COSMIC v3.6 labels, served from the refdb).
# Recognition anchors (docs/research/03-applications.md section 3):
# temozolomide SBS11 (PMID 39656916), platinum SBS31 + SBS35 (PMID 32366847),
# thiopurine SBS32 (PMID 31697823).
.ms_treatment_exposure_map <- list(
  temozolomide = "SBS11",
  platinum = c("SBS31", "SBS35"),
  thiopurine = "SBS32"
)

# Two-sided percentile bounds of the bootstrap group-contrast interval.
.MS_TRT_CI_PROBS <- c(0.025, 0.975)

# Adjudication floor in exposure-count units: a contrast is called
# associated only when its bootstrap interval clears zero by at least this
# margin in either direction. Officially recognised therapy signatures are
# pairwise correlated reference vectors, so a correlated sibling of a truly
# planted signature can absorb a deterministic few-count share under NNLS
# refit; a pure interval-excludes-zero rule would promote that artefact to
# an association. The floor makes the call an effect-size claim, mirroring
# the scale on which the recognition literature reports planted activities.
.MS_TRT_ASSOC_FLOOR <- 50

# Assemble one association row: point columns delegate to the fitted point
# matrix; CI columns ride the bootstrap replicate group means.
.ms_trt_assoc_row <- function(sig, exposed, unexposed, exposures, draws) {
  idx <- exposed
  other <- unexposed
  point <- function(sub) {
    if (!length(sub)) return(NA_real_)
    mean(exposures[sig, sub, drop = TRUE])
  }
  prev <- function(sub) {
    if (!length(sub)) return(NA_real_)
    mean(exposures[sig, sub, drop = TRUE] > 0)
  }
  mean_e <- point(idx)
  mean_u <- point(other)
  ci <- c(NA_real_, NA_real_)
  boot_means <- function(sub) {
    if (!length(sub) || length(dim(draws)) != 3L) {
      return(NULL)
    }
    apply(draws[sig, , , drop = TRUE][sub, , drop = FALSE], 2L, mean)
  }
  boot_e <- boot_means(idx)
  boot_u <- boot_means(other)
  if (!is.null(boot_e) && !is.null(boot_u)) {
    ci <- unname(quantile(boot_e - boot_u, probs = .MS_TRT_CI_PROBS))
  }
  data.frame(
    signature = sig,
    n_exposed = length(idx), n_unexposed = length(other),
    prevalence_exposed = prev(idx),
    prevalence_unexposed = prev(other),
    mean_exposed = mean_e, mean_unexposed = mean_u,
    contrast = mean_e - mean_u,
    contrast_lower = ci[[1L]], contrast_upper = ci[[2L]],
    is_associated = !is.na(ci[[1L]]) &&
      (ci[[1L]] > .MS_TRT_ASSOC_FLOOR || ci[[2L]] < -.MS_TRT_ASSOC_FLOOR),
    stringsAsFactors = FALSE
  )
}

# Association table: full treatment x governed-signature grid.
.ms_trt_association <- function(fit, treatments, map, samples) {
  exposures <- fit@exposures
  draws <- attr(exposures, "boot_draws")
  labels <- names(map)
  unexposed <- setdiff(samples, treatments$sample[!is.na(treatments$treatment)])
  rows <- list()
  for (trt in labels) {
    exposed <- match(treatments$sample[which(treatments$treatment == trt)],
                     samples)
    for (sig in sort(unique(unlist(map, use.names = FALSE)))) {
      row <- .ms_trt_assoc_row(sig, exposed, unexposed, exposures, draws)
      rows[[length(rows) + 1L]] <- cbind(treatment = trt, row)
    }
  }
  do.call(rbind, rows)[, c("treatment", "signature", "n_exposed", "n_unexposed",
    "prevalence_exposed", "prevalence_unexposed", "mean_exposed",
    "mean_unexposed", "contrast", "contrast_lower", "contrast_upper",
    "is_associated")]
}

# Bootstrap replicate mean of a weight-split exposure (w per exposed sample).
.ms_trt_boot_split <- function(draws, sig, idx, w) {
  a <- draws[sig, , , drop = TRUE][idx, , drop = FALSE]
  apply(a * matrix(w, nrow = length(idx), ncol = ncol(a)), 2L, mean)
}

# Timing table: clonal fraction attributes exposure pre-treatment, the
# remainder during treatment; intervals ride the same replicate stream.
.ms_trt_timing <- function(fit, clonality, treatments, map, samples) {
  exposures <- fit@exposures
  draws <- attr(exposures, "boot_draws")
  cf <- set_names(clonality$clonal_fraction,
                  paste0(clonality$sample, "::", clonality$signature))
  unexposed <- setdiff(samples, treatments$sample[!is.na(treatments$treatment)])
  rows <- list()
  for (trt in names(map)) {
    idx <- match(treatments$sample[which(treatments$treatment == trt)], samples)
    for (sig in sort(unique(unlist(map, use.names = FALSE)))) {
      w <- cf[paste0(samples[idx], "::", sig)]
      point <- function(v) if (length(idx)) mean(v) else NA_real_
      split <- function(side) {
        if (!length(idx) || length(dim(draws)) != 3L) {
          return(c(NA_real_, NA_real_))
        }
        unname(quantile(.ms_trt_boot_split(draws, sig, idx, side),
                        probs = .MS_TRT_CI_PROBS))
      }
      pre <- point(w * exposures[sig, samples[idx], drop = TRUE])
      post <- point((1 - w) * exposures[sig, samples[idx], drop = TRUE])
      ci_p <- split(w); ci_s <- split(1 - w)
      rows[[length(rows) + 1L]] <- data.frame(
        treatment = trt, signature = sig, n_exposed = length(idx),
        exposure_pre = pre, exposure_post = post,
        pre_lower = ci_p[[1L]], pre_upper = ci_p[[2L]],
        post_lower = ci_s[[1L]], post_upper = ci_s[[2L]],
        stringsAsFactors = FALSE)
    }
  }
  if (length(rows)) do.call(rbind, rows) else .ms_trt_empty_timing()
}

.ms_trt_empty_rows <- function() data.frame(
  treatment = character(), signature = character(), n_exposed = integer(),
  n_unexposed = integer(), prevalence_exposed = numeric(),
  prevalence_unexposed = numeric(), mean_exposed = numeric(),
  mean_unexposed = numeric(), contrast = numeric(),
  contrast_lower = numeric(), contrast_upper = numeric(),
  is_associated = logical(), stringsAsFactors = FALSE)

.ms_trt_empty_timing <- function() data.frame(
  treatment = character(), signature = character(), n_exposed = integer(),
  exposure_pre = numeric(), exposure_post = numeric(),
  pre_lower = numeric(), pre_upper = numeric(),
  post_lower = numeric(), post_upper = numeric(), stringsAsFactors = FALSE)

# Argument gates (topic: input) -- fail closed, name the received value.
.ms_trt_resolve_map <- function(exposure_map) {
  map <- if (is.null(exposure_map)) .ms_treatment_exposure_map else exposure_map
  ok <- is.list(map) && length(map) && all(nzchar(names(map) %||% "")) &&
    all(vapply(map, function(v) is.character(v) && length(v) &&
                  all(nzchar(v)), logical(1)))
  if (!ok) {
    msuiter_abort(
      "input",
      "exposure_map must be a non-empty named list of non-empty signature vectors",
      i = "each entry names one therapy class and binds one or more governed signatures",
      j = paste0("received: ", msuiter_quote_trunc(exposure_map)),
      c = "omit exposure_map for the governed default (temozolomide/platinum/thiopurine)"
    )
  }
  map
}

.ms_trt_check_catalog <- function(catalog) {
  if (!S7::S7_inherits(catalog, MsCatalog)) {
    msuiter_abort(
      "input",
      "catalog must be an MsCatalog (a channel-count matrix with provenance)",
      i = "ms_treatment_report() fits a variant catalog, not a bare matrix",
      j = paste0("received: ", class(catalog)[[1L]]),
      c = "build the cohort with ms_simulate(), ms_tally() or ms_catalog()"
    )
  }
  if (!identical(catalog@channels$name %||% "", "SBS96")) {
    msuiter_abort(
      "input",
      "the treatment-forensics face consumes SBS96 channel space",
      i = "governed therapy signatures are SBS96 identities from the bundled refdb",
      j = paste0("received channel space: ", msuiter_quote_trunc(catalog@channels$name)),
      c = "tally the cohort into SBS96 (ms_tally(catalog, mode = \"SBS96\"))"
    )
  }
  invisible(NULL)
}

.ms_trt_check_treatments <- function(treatments, map, samples) {
  if (is.null(treatments)) {
    return(NULL)
  }
  bad <- !is.data.frame(treatments) || !all(c("sample", "treatment") %in% names(treatments))
  if (bad) {
    msuiter_abort(
      "input",
      "treatments must be a data.frame with columns sample and treatment",
      i = "one row per sequenced sample; treatment NA marks an unexposed sample",
      j = paste0("received: ", msuiter_quote_trunc(treatments)),
      c = "pass data.frame(sample = ids, treatment = class_labels_or_NA)"
    )
  }
  treatment <- as.character(treatments$treatment)
  sample <- as.character(treatments$sample)
  if (anyNA(sample) || anyDuplicated(sample)) {
    msuiter_abort(
      "input",
      "treatments$sample must be non-missing and unique",
      i = "the association groups are defined by a one-to-one sample roster",
      j = paste0("offending: ", msuiter_quote_trunc(c(sample[is.na(sample)],
        sample[duplicated(sample)]))),
      c = "collapse duplicate rows before reporting"
    )
  }
  unknown <- setdiff(sample, samples)
  if (length(unknown)) {
    msuiter_abort(
      "input",
      paste0("treatments$sample names samples absent from the catalog: ",
             msuiter_quote_trunc(unknown)),
      i = "every reported sample must be present in the fitted catalog",
      j = paste0("catalog samples: ", msuiter_quote_trunc(samples[seq_len(4L)])),
      c = "align the treatment roster with ms_catalog() ids"
    )
  }
  bad_lab <- setdiff(unique(treatment[!is.na(treatment)]), names(map))
  if (length(bad_lab)) {
    msuiter_abort(
      "input",
      paste0("treatment labels outside the governed exposure map: ",
             msuiter_quote_trunc(bad_lab)),
      i = "only therapy classes bound by the exposure map may be adjudicated",
      j = paste0("governed classes: ", msuiter_quote_trunc(names(map))),
      c = "extend exposure_map deliberately, never silently"
    )
  }
  data.frame(sample = sample, treatment = treatment, stringsAsFactors = FALSE)
}

.ms_trt_check_clonality <- function(clonality, samples, signatures) {
  if (is.null(clonality)) {
    return(NULL)
  }
  bad <- !is.data.frame(clonality) ||
    !all(c("sample", "signature", "clonal_fraction") %in% names(clonality))
  if (bad) {
    msuiter_abort(
      "input",
      "clonality must be a data.frame with columns sample, signature, clonal_fraction",
      i = "the timing split needs one clonal fraction per sample and signature",
      j = paste0("received: ", msuiter_quote_trunc(clonality)),
      c = "pass the full sample x signature grid (clonal_fraction in [0, 1])"
    )
  }
  fraction <- clonality$clonal_fraction
  if (!is.numeric(fraction) || anyNA(fraction) || !all(is.finite(fraction)) ||
      any(fraction < 0) || any(fraction > 1)) {
    msuiter_abort(
      "input",
      "clonal_fraction must be finite numeric inside [0, 1]",
      i = "the clonal fraction weights the pre-treatment share of an exposure",
      j = paste0("received: ", msuiter_quote_trunc(fraction)),
      c = "1 means wholly clonal, 0 wholly subclonal"
    )
  }
  keys <- paste0(clonality$sample, "::", clonality$signature)
  want <- as.vector(outer(samples, signatures,
                          function(a, b) paste0(a, "::", b)))
  if (anyDuplicated(keys) || !setequal(keys, want)) {
    msuiter_abort(
      "input",
      "clonality must cover every sample x governed-signature cell exactly once",
      i = "partial coverage would fabricate the timing split from assumed zeros",
      j = paste0("missing cells: ", msuiter_quote_trunc(setdiff(want, keys))),
      c = "expand the grid and supply every clonal_fraction"
    )
  }
  clonality[, c("sample", "signature", "clonal_fraction")]
}

# Refdb-governed dictionary: labels must resolve against the sealed roster.
.ms_trt_dictionary <- function(map, build) {
  refdb <- ms_refdb_bundled(build = build)[["SBS_GRCh37"]]
  if (is.null(refdb)) {
    msuiter_abort(
      "refdb",
      paste0("the treatment dictionary needs the SBS reference set for build ",
             msuiter_quote_trunc(build)),
      i = "governed therapy signatures are SBS identities of an official build",
      j = "the bundled roster served no SBS set for the requested build",
      c = "use an official build (GRCh37 or GRCh38)"
    )
  }
  mat <- refdb@matrices[[1L]]
  signatures <- sort(unique(unlist(map, use.names = FALSE)))
  unknown <- setdiff(signatures, colnames(mat))
  if (length(unknown)) {
    msuiter_abort(
      "refdb",
      paste0("exposure_map names signatures outside the bundled refdb roster: ",
             msuiter_quote_trunc(unknown)),
      i = "therapy-signature identities are governed by the sealed reference database",
      j = paste0("nearest official labels: ",
        msuiter_quote_trunc(grep(paste0("^", substr(unknown[[1L]], 1, 5)),
          colnames(mat), value = TRUE))),
      c = "cite a bundled label such as SBS11, SBS31, SBS32 or SBS35"
    )
  }
  dict <- mat[, signatures, drop = FALSE]
  list(dict = dict, version = refdb@metadata$version,
       sha256 = .ms_trt_dict_digest(dict))
}

# Canonical digest of the served dictionary (identity of the adjudicated set).
.ms_trt_dict_digest <- function(dict) {
  payload <- paste0(
    "msuiter-treatment-dictionary-v1",
    paste0(dim(dict), collapse = "x"),
    rownames(dict), colnames(dict),
    paste0(format(as.vector(dict), digits = 17, trim = TRUE), collapse = "\n"),
    collapse = "\n")
  .ms_fit_sha256(charToRaw(payload))
}

.ms_trt_provenance <- function(dict_info, build, method, n_boot, seed) {
  list(
    refdb_version = dict_info$version,
    build = build,
    method = method,
    n_boot = as.integer(n_boot),
    seed = as.integer(seed),    dictionary = colnames(dict_info$dict),
    dictionary_sha256 = dict_info$sha256
  )
}

#' Treatment-forensics report: bootstrap-CI association plus clonal timing
#'
#' Adjudicates which governed therapy class associates which officially
#' recognised signature in a fitted cohort. Point estimates delegate to the
#' public fit face; interval estimates ride the public bootstrap face
#' ([ms_fit_bootstrap()]) -- this module never reimplements a resampler.
#' Without treatment records the association face degrades honestly (empty
#' table plus attestation) instead of fabricating groups; without clonality
#' records the timing face does the same.
#'
#' @param catalog An [MsCatalog] in SBS96 channel space.
#' @param treatments `NULL` or a data.frame with columns `sample` (catalog
#'   ids) and `treatment` (a governed class label or `NA` for unexposed).
#' @param clonality `NULL` or a data.frame with columns `sample`, `signature`
#'   and `clonal_fraction` in `[0, 1]`, covering every sample x governed-
#'   signature cell exactly once.
#' @param exposure_map `NULL` for the governed default map, or a named list
#'   binding therapy classes to bundled-refdb signature labels.
#' @param n_boot Bootstrap replicate count (delegated scalar gate).
#' @param seed Bootstrap master seed (delegated scalar gate).
#' @param build Reference build for the bundled refdb dictionary.
#' @param method Fit method (delegated to [ms_fit_bootstrap()]).
#'
#' @return An object of class `MsTreatmentReport`. [as.data.frame()][as.data.frame.MsTreatmentReport]
#'   yields the association table (`treatment`, `signature`, `n_exposed`,
#'   `n_unexposed`, `prevalence_exposed`, `prevalence_unexposed`,
#'   `mean_exposed`, `mean_unexposed`, `contrast`, `contrast_lower`,
#'   `contrast_upper`, `is_associated`). The clonal-timing table (attrs
#'   `timing`: `treatment`, `signature`, `n_exposed`, `exposure_pre`,
#'   `exposure_post`, `pre_lower`, `pre_upper`, `post_lower`, `post_upper`),
#'   the degradation ledger (attr `attestation`: `face`, `status`, `detail`)
#'   and the run record (attr `provenance`) ride as attributes.
#' @seealso [ms_fit()] and [ms_fit_bootstrap()] for the delegated fit faces.
#'
#' @export
ms_treatment_report <- function(catalog, treatments = NULL, clonality = NULL,
                                exposure_map = NULL, n_boot = 200, seed = 1,
                                build = "GRCh37", method = "nnls") {
  map <- .ms_trt_resolve_map(exposure_map)
  .ms_trt_check_catalog(catalog)
  samples <- catalog@samples
  # Refdb governance precedes cohort binding: an exposure map that cannot
  # resolve against the sealed roster is rejected before any data is read.
  dict_info <- .ms_trt_dictionary(map, build)
  treatments <- .ms_trt_check_treatments(treatments, map, samples)
  signatures <- sort(unique(unlist(map, use.names = FALSE)))
  clonality <- .ms_trt_check_clonality(clonality, samples, signatures)
  attestation <- data.frame(face = character(), status = character(),
                            detail = character(), stringsAsFactors = FALSE)
  if (is.null(treatments)) {
    timing <- .ms_trt_empty_timing()
    rows <- .ms_trt_empty_rows()
    attestation <- rbind(attestation, data.frame(
      face = "association", status = "degraded",
      detail = "no-treatment-records: treatments is NULL", stringsAsFactors = FALSE),
      data.frame(face = "timing", status = "degraded",
        detail = "no-treatment-records: treatments is NULL", stringsAsFactors = FALSE))
  } else {
    fit <- ms_fit_bootstrap(catalog, dict_info$dict, method = method,
                            n_boot = n_boot, seed = seed, return_draws = TRUE)
    rows <- .ms_trt_association(fit, treatments, map, samples)
    if (is.null(clonality)) {
      timing <- .ms_trt_empty_timing()
      attestation <- rbind(attestation, data.frame(
        face = "timing", status = "degraded",
        detail = "no-clonality-records: clonality is NULL", stringsAsFactors = FALSE))
    } else {
      timing <- .ms_trt_timing(fit, clonality, treatments, map, samples)
    }
    attestation <- rbind(attestation, data.frame(
      face = "association", status = "full",
      detail = sprintf("%d groups x %d signatures at n_boot=%d",
                       length(names(map)), length(signatures), n_boot),
      stringsAsFactors = FALSE))
  }
  structure(
    list(rows = rows),
    class = "MsTreatmentReport",
    timing = timing,
    attestation = attestation[, c("face", "status", "detail")],
    provenance = .ms_trt_provenance(dict_info, build, method, n_boot, seed)
  )
}

#' Coerce a treatment report to its association table
#'
#' All-atomic association view of an `MsTreatmentReport`: one row per
#' treatment x governed-signature cell, as documented in [ms_treatment_report()].
#'
#' @param x An `MsTreatmentReport` as returned by [ms_treatment_report()].
#' @param ... Further arguments (unused; compatibility with the generic).
#' @return The report's association table.
#' @export
as.data.frame.MsTreatmentReport <- function(x, ...) x$rows

#' Print a treatment report
#'
#' Compact print of an `MsTreatmentReport`: the provenance line, the
#' attestation ledger and both tables.
#'
#' @param x An `MsTreatmentReport` as returned by [ms_treatment_report()].
#' @param ... Further arguments (unused; compatibility with the generic).
#' @return `x`, invisibly.
#' @export
print.MsTreatmentReport <- function(x, ...) {
  prov <- attr(x, "provenance")
  att <- attr(x, "attestation")
  cat("<msuiter treatment report>\n")
  cat(sprintf("  refdb=%s  build=%s  method=%s  n_boot=%d  seed=%d\n",
              prov$refdb_version, prov$build, prov$method,
              prov$n_boot, prov$seed))
  cat(paste0("  ", att$face, "=", att$status, collapse = "  "), "\n")
  print_attr_table <- function(label, tab) {
    cat(sprintf("  %s (%d rows):\n", label, nrow(tab)))
    if (nrow(tab)) {
      print(format(tab, na.str = "-", trim = TRUE), row.names = FALSE,
            quote = FALSE)
    }
  }
  print_attr_table("association", x$rows)
  print_attr_table("timing", attr(x, "timing"))
  invisible(x)
}
