# U-M6s-01 -- ms_hrd_report(): the HRD (homologous-recombination-deficiency)
# report face. Public API and the two hard gates are the design memo's
# (docs/devlog/2026-10-07-m6s-hrd-report-design.md section 2); the verbatim
# scorers and every frozen constant live in R/hrd-reference.R (single
# ground truth: cran/SigMiner get_pLOH_score.R / get_Aneuploidy_score.R).
# All violations raise `msuiter_error_*` conditions via msuiter_abort().

# --- argument validators -------------------------------------------------------

# The caller whitelist gate (adjudication section 9): the observed caller is
# lowercased before comparison; unknown / non-string callers still hit the
# gate. The offending label is carried in the top-level message so the
# condition reads "caller 'x' is not on the ... whitelist". Returns the
# validated single caller label (or NA for the empty / derive-from-column
# path); raises `msuiter_error_hrd-caller-whitelist` on a miss.
.hrd_check_caller <- function(caller, segments) {
  labels <- character(0)
  auto <- is.null(caller) ||
    (is.character(caller) && length(caller) == 1L && identical(tolower(caller[1L]), "auto"))
  if (auto) {
    # derive from the segment table's caller column
  } else if (is.character(caller)) {
    labels <- c(labels, tolower(caller[!is.na(caller)]))
  } else {
    labels <- c(labels, paste0(as.character(caller)))
  }
  col <- segments$caller
  if (is.character(col)) labels <- c(labels, tolower(col[!is.na(col)]))

  offenders <- unique(setdiff(labels, .HRD_CALLERS))
  if (length(offenders)) {
    msuiter_abort(
      "hrd-caller-whitelist",
      paste0("caller ", msuiter_quote_trunc(offenders),
             " is not on the HRD caller whitelist"),
      i = "the HRD report accepts only the five validated allele-specific callers",
      j = paste0("whitelist: ", msuiter_quote_trunc(.HRD_CALLERS)),
      c = "score the sample with a validated caller, or omit 'caller' to derive it from the segment table"
    )
  }

  if (!auto) return(tolower(caller[1L]))
  derived <- unique(if (is.character(col)) tolower(col[!is.na(col)]) else character(0))
  if (length(derived) <= 1L) {
    return(if (length(derived) == 1L) derived else NA_character_)
  }
  msuiter_abort(
    "input",
    "the caller column is ambiguous; pass a single 'caller' value",
    i = "one HRD report row is attributed to exactly one caller",
    j = paste0("observed callers: ", msuiter_quote_trunc(derived)),
    c = "split the segment table by caller, or pass the caller explicitly"
  )
}

# The reference-geometry resolution (adjudication section 5). Geometry is
# injected through `...`; there is deliberately NO invented genome default --
# msuiter ships no get_cn_ploidy / arm-table API, so un-supplied geometry is
# reported as unavailable (NA score / zero count) through the uncertainty
# columns rather than fabricated. Injected values always win (this is the only
# source). Validates the injected shapes; raises `msuiter_error_input`.
.hrd_resolve_geometry <- function(opts) {
  chr_size <- opts$chr_size
  arms <- opts$arms
  ploidy <- opts$ploidy
  rm_black_arms <- isTRUE(opts$rm_black_arms)

  if (!is.null(chr_size) &&
      (!is.numeric(chr_size) || length(chr_size) != 1L || is.na(chr_size) || chr_size <= 0)) {
    msuiter_abort("input", "injected 'chr_size' must be a single positive number",
      i = "chr_size is the pLOH denominator over which LOH bases are normalised",
      j = paste0("received: ", msuiter_quote_trunc(chr_size)),
      c = "pass a single positive chromosome-length scalar (e.g. 1e6)")
  }
  if (!is.null(arms)) {
    need <- c("chrom", "location", "arm_start", "arm_end")
    if (!is.data.frame(arms) || !all(need %in% names(arms)) ||
        !is.numeric(arms$arm_start) || !is.numeric(arms$arm_end) ||
        !is.character(arms$location)) {
      msuiter_abort("input", "injected 'arms' must be a data.frame(chrom, location, arm_start, arm_end)",
        i = "the arm table drives the per-arm aneuploidy weighting",
        j = paste0("received: ", if (is.data.frame(arms)) paste0(names(arms), collapse = ", ") else class(arms)[1L]),
        c = "pass a data.frame with columns chrom, location (p/q), arm_start, arm_end")
      }
  }
  if (!is.null(ploidy) && (!is.numeric(ploidy) || length(ploidy) < 1L || all(is.na(ploidy)))) {
    msuiter_abort("input", "injected 'ploidy' must be a numeric vector with a non-NA first element",
      i = "the aneuploidy flag subtracts ploidy[1] from the arm-weighted copy number",
      j = paste0("received: ", msuiter_quote_trunc(ploidy)),
      c = "pass the caller ploidy (e.g. 2), or omit it to mark the row ploidy-derived")
  }
  list(chr_size = chr_size, arms = arms, ploidy = ploidy,
       rm_black_arms = rm_black_arms,
       ploidy_source = if (!is.null(ploidy)) "caller" else "derived")
}

# Composite HRD classifier (adjudication section 4; provenance Cortes-Castro
# et al., Cancer Research 2020 -- see .HRD_PLOH_CUTOFF/.HRD_ANEU_CUTOFF).
# 1L iff BOTH cut-offs are met inclusively; NA where a sub-score is unknown.
.hrd_composite <- function(ploh_fraction, aneuploidy_count) {
  n <- length(ploh_fraction)
  out <- integer(n)
  known <- !is.na(ploh_fraction) & !is.na(aneuploidy_count)
  pos <- known & ploh_fraction >= .HRD_PLOH_CUTOFF & aneuploidy_count >= .HRD_ANEU_CUTOFF
  out[pos] <- 1L
  out[known & !pos] <- 0L
  out[!known] <- NA_integer_
  out
}

# Per-sample scoring: one row per sample. pLOH needs only an injected
# denominator; aneuploidy needs both an arm table and a ploidy. Missing
# geometry degrades to NA / 0 (uncertainty reporting, memo section 2) instead
# of fabricating a biological constant.
.hrd_score_samples <- function(segments, geom) {
  samples <- unique(segments$sample)
  n <- length(samples)
  if (n == 0L) {
    return(list(
      sample = character(0), ploh_fraction = numeric(0),
      aneuploidy_count = integer(0), n_windows_scored = integer(0),
      detail = .hrd_empty_detail()
    ))
  }
  ploh_fraction <- if (is.null(geom$chr_size)) rep(NA_real_, n) else
    vapply(samples, function(s)
      hrd_ploh_score(segments[segments$sample == s, , drop = FALSE], geom$chr_size),
      numeric(1))

  if (is.null(geom$arms) || is.null(geom$ploidy)) {
    an <- list(count = integer(n), windows = integer(n), detail = .hrd_empty_detail())
  } else {
    an <- hrd_aneuploidy(segments, geom$arms, geom$ploidy, geom$rm_black_arms)
  }
  list(sample = samples, ploh_fraction = unname(ploh_fraction),
       aneuploidy_count = as.integer(an$count),
       n_windows_scored = as.integer(an$windows), detail = an$detail)
}

.hrd_empty_detail <- function() {
  data.frame(sample = character(0), chrom = character(0),
    arms_covered = integer(0), fraction = numeric(0), flag = integer(0),
    stringsAsFactors = FALSE)
}

.hrd_coverage_note <- function(geom) {
  den <- if (is.null(geom$chr_size)) "denominator=absent" else "denominator=injected"
  aneu <- if (!is.null(geom$arms) && !is.null(geom$ploidy)) "aneuploidy=scored" else
    if (is.null(geom$arms)) "aneuploidy=no-arm-table" else "aneuploidy=no-ploidy"
  paste0("ploidy-source=", geom$ploidy_source, "; ", den, "; ", aneu)
}

# --- public face ---------------------------------------------------------------

#' HRD report from allele-specific segment calls
#'
#' `ms_hrd_report()` scores each sample of an allele-specific segment table
#' with the two Cortes-Castro genomic-scar scores -- the fraction of partial
#' loss of heterozygosity ([pLOH][hrd_ploh_score]) and the autosome-level
#' [aneuploidy][hrd_aneuploidy] count -- and combines them into the composite
#' HRD call. The verbatim scoring expressions are anchored on the
#' cran/SigMiner reference in [R/hrd-reference.R][hrd_ploh_score] and are
#' replayed digit-for-digit against an independent oracle by the fidelity
#' suite.
#'
#' Two hard gates protect the score's provenance (design memo section 2):
#' a `wes` assay needs `experimental = TRUE` (`msuiter_error_hrd-wes-experimental`);
#' a caller outside the five validated allele-specific callers is refused
#' (`msuiter_error_hrd-caller-whitelist`). Reference geometry (the pLOH
#' denominator, the arm table and ploidy) is injected through `...` --
#' msuiter ships no genome-derived default and never fabricates one, so
#' un-supplied geometry is surfaced through the uncertainty columns
#' (`n_windows_scored`, `coverage_note`, `ploidy_source`) rather than invented.
#'
#' @param segments A `data.frame` with columns `sample`, `chromosome`, `start`,
#'   `end`, `state` (integer major copy number), `minor_cn`, `caller` and
#'   `assay`. `start`/`end` are 1-based closed bp and together with
#'   `state`/`minor_cn` must be numeric.
#' @param genome Build label, one of `"GRCh37"` / `"GRCh38"`. Required and
#'   explicit -- there is no silent default. Anything else raises
#'   `msuiter_error_genome`.
#' @param caller The allele-specific caller label to attribute and validate
#'   against the five-name whitelist (`battenberg`, `ascat`, `facets`,
#'   `purple`, `sequenza`); compared case-insensitively. `NULL` or `"auto"`
#'   derives it from the segment table's `caller` column.
#' @param assay Modality, `"wgs"` (default) or `"wes"`. A `"wes"` assay is
#'   refused unless `experimental = TRUE`.
#' @param experimental Single logical (default `FALSE`): the opt-in that lets a
#'   `"wes"` assay through the WGS-only gate; the tier column then reads
#'   `"experimental"`.
#' @param ... Reference-geometry injections: `chr_size` (positive pLOH
#'   denominator), `arms` (`data.frame(chrom, location, arm_start, arm_end)`),
#'   `ploidy` (numeric; `ploidy[1]` is subtracted by the aneuploidy flag) and
#'   `rm_black_arms` (single logical, default `FALSE`; drops the acrocentric
#'   p-arms `{13,14,15,21,22}` from the aneuploidy count). Any other name is
#'   ignored.
#'
#' @return An object of class `MsHrdReport`. Its [as.data.frame()][as.data.frame.MsHrdReport]
#'   face is an all-atomic table with one row per sample and the columns
#'   `sample`, `genome`, `caller`, `assay`, `ploh_fraction`, `aneuploidy_count`,
#'   `hrd_score`, `evidence_tier`, `n_windows_scored`, `coverage_note` and
#'   `ploidy_source`. A `chrom`-level aneuploidy table is carried on the object
#'   as `attr(rep, "aneuploidy_detail")`.
#' @seealso [hrd_ploh_score()] and [hrd_aneuploidy()] for the verbatim scorers.
#'
#' @examples
#' seg <- data.frame(
#'   sample = "S1", chromosome = "chr1",
#'   start = 1L, end = 1000L, state = 2L, minor_cn = 0L,
#'   caller = "ascat", assay = "wgs", stringsAsFactors = FALSE
#' )
#' arms <- data.frame(
#'   chrom = "chr1", location = c("p", "q"),
#'   arm_start = c(1L, 501L), arm_end = c(500L, 1000L),
#'   stringsAsFactors = FALSE
#' )
#' rep1 <- ms_hrd_report(seg, genome = "GRCh37", caller = "ascat", assay = "wgs",
#'   chr_size = 1000, ploidy = 2, arms = arms
#' )
#' as.data.frame(rep1)
#' @export
ms_hrd_report <- function(segments, genome, caller, assay = c("wgs", "wes"),
                          experimental = FALSE, ...) {
  # -- structural input gate (topic: input) --------------------------------
  if (!is.data.frame(segments)) {
    msuiter_abort(
      "input",
      "segments must be a data.frame of allele-specific segment calls",
      i = "ms_hrd_report() scores a per-segment table, not an arbitrary object",
      j = paste0("received: ", class(segments)[[1L]]),
      c = "pass the segment table with columns sample/chromosome/start/end/state/minor_cn/caller/assay"
    )
  }
  missing_cols <- setdiff(.HRD_REQUIRED_COLS, names(segments))
  if (length(missing_cols)) {
    msuiter_abort(
      "input",
      paste0("segments is missing required column(s): ", msuiter_quote_trunc(missing_cols)),
      i = "the verbatim scorers need the full segment column contract",
      j = paste0("required: ", msuiter_quote_trunc(.HRD_REQUIRED_COLS)),
      c = "add the missing column(s) before calling ms_hrd_report()"
    )
  }
  numeric_cols <- c("start", "end", "state", "minor_cn")
  non_numeric <- numeric_cols[!vapply(numeric_cols,
    function(cn) is.numeric(segments[[cn]]), logical(1))]
  if (length(non_numeric)) {
    msuiter_abort(
      "input",
      paste0("coordinate/state column(s) must be numeric: ", msuiter_quote_trunc(non_numeric)),
      i = "start/end/state/minor_cn are read as numbers by the scorers",
      j = paste0("non-numeric: ", msuiter_quote_trunc(non_numeric)),
      c = "coerce the coordinate/state columns to numeric/integer"
    )
  }

  # -- genome gate (topic: genome) -----------------------------------------
  if (!is.character(genome) || length(genome) != 1L || is.na(genome) ||
      !genome %in% .HRD_SUPPORTED_BUILDS) {
    msuiter_abort(
      "genome",
      paste0("unsupported genome build: ", msuiter_quote_trunc(genome)),
      i = "ms_hrd_report() exposes the reference build explicitly",
      j = paste0("supported: ", msuiter_quote_trunc(.HRD_SUPPORTED_BUILDS)),
      c = 'pass genome = "GRCh37" or "GRCh38"'
    )
  }

  # -- assay scalar + choices ----------------------------------------------
  if (length(assay) > 1L) assay <- assay[[1L]] # collapse the choices-style default
  if (!is.character(assay) || length(assay) != 1L || is.na(assay) ||
      !assay %in% .HRD_SUPPORTED_ASSAYS) {
    msuiter_abort(
      "input",
      paste0("assay must be \"wgs\" or \"wes\""),
      i = "the report is defined for the WGS and (opt-in) WES modalities",
      j = paste0("received: ", msuiter_quote_trunc(assay)),
      c = 'pass assay = "wgs" or assay = "wes" (the latter with experimental = TRUE)'
    )
  }

  # -- caller whitelist gate (topic: hrd-caller-whitelist) -----------------
  caller_label <- .hrd_check_caller(caller, segments)

  # -- WGS-only gate (topic: hrd-wes-experimental) -------------------------
  experimental <- isTRUE(experimental)
  if (identical(assay, "wes") && !experimental) {
    msuiter_abort(
      "hrd-wes-experimental",
      "a wes assay is experimental and needs experimental = TRUE",
      i = "the HRD scar scores are validated for WGS; WES is offered only opt-in",
      j = 'received assay = "wes" with experimental = FALSE',
      c = "pass experimental = TRUE to accept the experimental WES tier"
    )
  }

  # -- reference geometry (adjudication section 5) ---------------------------
  geom <- .hrd_resolve_geometry(list(...))

  # -- per-sample scoring + assembly ---------------------------------------
  scored <- .hrd_score_samples(segments, geom)
  n <- length(scored$sample)
  evidence_tier <- if (identical(assay, "wes") && experimental) "experimental" else "standard"
  coverage_note <- .hrd_coverage_note(geom)

  rows <- data.frame(
    sample = scored$sample,
    genome = rep(genome, n),
    caller = rep(caller_label, n),
    assay = rep(assay, n),
    ploh_fraction = scored$ploh_fraction,
    aneuploidy_count = scored$aneuploidy_count,
    hrd_score = .hrd_composite(scored$ploh_fraction, scored$aneuploidy_count),
    evidence_tier = rep(evidence_tier, n),
    n_windows_scored = scored$n_windows_scored,
    coverage_note = rep(coverage_note, n),
    ploidy_source = rep(geom$ploidy_source, n),
    stringsAsFactors = FALSE
  )

  out <- list(rows = rows, genome = genome, caller = caller_label,
              assay = assay, experimental = experimental)
  attr(out, "aneuploidy_detail") <- scored$detail
  class(out) <- "MsHrdReport"
  out
}

# --- S3 face -------------------------------------------------------------------

#' Coerce an HRD report to its per-sample table
#'
#' All-atomic per-sample view of an `MsHrdReport`: one row per sample with the
#' contract columns documented in [ms_hrd_report()].
#'
#' @param x An `MsHrdReport` as returned by [ms_hrd_report()].
#' @param ... Further arguments (unused; compatibility with the generic).
#' @return The report's all-atomic per-sample table.
#' @export
as.data.frame.MsHrdReport <- function(x, ...) x$rows

#' Print an HRD report
#'
#' Compact print of an `MsHrdReport`: the genome/caller/assay provenance line,
#' the sample count and the per-sample score table.
#'
#' @param x An `MsHrdReport` as returned by [ms_hrd_report()].
#' @param ... Further arguments (unused; compatibility with the generic).
#' @return `x`, invisibly.
#' @export
print.MsHrdReport <- function(x, ...) {
  rows <- x$rows
  cat("<msuiter HRD report>\n")
  cat(sprintf("  genome=%s  caller=%s  assay=%s\n", x$genome,
              x$caller %||% "(none)", x$assay))
  cat(sprintf("  samples=%d\n", nrow(rows)))
  if (nrow(rows)) {
    print(rows, row.names = FALSE)
  } else {
    print(rows)
  }
  invisible(x)
}
