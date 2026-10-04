# ms-convert.R: opportunity conversion between mutational opportunity
# representations (U-M4-02c; design memo
# docs/devlog/2026-10-04-M4-02c-convert-memo.md).
#
# The sigfit convert_signatures semantics (research/02 §文献): a
# signature is divided by the source opportunities and multiplied by the
# target ones, then re-normalized per column. The bundled frequency
# tables come from the COSMIC v2/v3 signature database via
# sigfit -> sigminer (the verification anchor is the maintainer's own
# sigminer source, R/sig_convert.R:103; total-magnitude sanity anchors:
# genome 8.505e9, exome 1.53e8). The upstream tables are stored in the
# SigProfiler label order, which differs from our registry order — the
# values are matched BY LABEL, never by position.
#
# data-raw/opps_trinuc_freqs.tsv pins the table in OUR registry order
# with the full provenance. The test layer re-reads it and pins anchor
# values literally.
#
# The likelihood-native opportunity treatment (sigfit's per-sample
# opportunity inside the likelihood) is v1.x — this face is the
# standalone converter.

# The frozen opportunity tables in OUR registry order (COSMIC v2/v3 via
# sigminer human_trinuc_freqs; see data-raw/opps_trinuc_freqs.tsv).
.ms_convert_opps <- local({
  path <- system.file("extdata", "opps_trinuc_freqs.tsv", package = "msuiter")
  if (!nzchar(path)) {
    # Source-layout fallback for the dev tree (the file ships in
    # inst/extdata for the built package).
    path <- file.path("data-raw", "opps_trinuc_freqs.tsv")
  }
  tab <- utils::read.delim(path, sep = "\t", header = TRUE,
                           stringsAsFactors = FALSE)
  list(
    `human-genome` = stats::setNames(tab$genome, tab$label),
    `human-exome` = stats::setNames(tab$exome, tab$label)
  )
})

#' Convert signatures between mutational opportunity representations
#'
#' Re-expresses SBS96 signatures relative to a different mutation
#' opportunity vector (whole-genome vs whole-exome trinucleotide
#' frequencies, or a custom vector): divide by the source opportunities,
#' multiply by the target ones, re-normalize each column (the sigfit
#' `convert_signatures` semantics). The bundled tables come from the
#' COSMIC v2/v3 signature database (via sigfit/sigminer); custom
#' opportunity vectors are accepted for panel targets.
#'
#' @param signatures A 96 x k numeric matrix with SBS96 registry rownames
#'   (columns sum to 1 after conversion), or an [MsSignature].
#' @param from Source opportunity: `"human-genome"`, `"human-exome"`, or
#'   a numeric vector of 96 positive finite frequencies (named by the
#'   registry labels, or matching the signature rownames).
#' @param to Target opportunity: same forms as `from`.
#'
#' @return A matrix of the converted signatures (or a new [MsSignature]
#'   for the MsSignature method, with the exposures untouched — exposure
#'   shares are opportunity-agnostic under this semantics).
#'
#' @references
#' \itemize{
#'   \item{Opportunity tables: COSMIC signature database v2/v3; sigfit
#'     `convert_signatures` (bioRxiv 2021 (doi:10.1101/372896)).}
#' }
#'
#' @export
ms_convert <- S7::new_generic(
  "ms_convert",
  "signatures",
  function(signatures, from = "human-genome", to = "human-exome")
    S7::S7_dispatch()
)

# Resolve an opportunity argument into a named 96-vector in registry order.
.ms_convert_resolve_opps <- function(opps, labels, arg_nm) {
  if (is.character(opps) && length(opps) == 1L) {
    if (!opps %in% names(.ms_convert_opps)) {
      msuiter_abort(
        "option",
        sprintf("%s must be a bundled table or a custom frequency vector", arg_nm),
        i = "panel opportunities are expected as a custom 96-vector ([V] discipline: no bundled panel table)",
        j = paste0("received: ", msuiter_quote_trunc(opps),
                   "; bundled: ", paste(names(.ms_convert_opps), collapse = ", ")),
        c = "pass a named numeric vector for custom opportunities"
      )
    }
    return(.ms_convert_opps[[opps]])
  }
  if (is.numeric(opps) && is.matrix(opps)) {
    if (ncol(opps) == 1L) {
      opps <- drop(opps)
    } else {
      msuiter_abort(
        "input",
        sprintf("%s matrix must have exactly one frequency column", arg_nm),
        i = "the opportunity is a single 96-vector, not per-signature",
        j = paste0("received: ", ncol(opps), " columns"),
        c = "repeat the column yourself for per-signature opportunities"
      )
    }
  }
  if (!is.numeric(opps) || length(opps) != length(labels)) {
    msuiter_abort(
      "input",
      sprintf("%s must be a frequency vector over the 96 channels", arg_nm),
      j = sprintf("received length: %d", length(opps)),
      c = "name it by the registry labels or pass a bundled table name"
    )
  }
  nm <- names(opps)
  if (!is.null(nm) && setequal(nm, labels)) {
    opps <- opps[match(labels, nm)]
  } else if (!is.null(nm) && length(nm) == length(labels) &&
             identical(nm, as.character(labels))) {
    # already aligned
  } else if (!is.null(nm)) {
    msuiter_abort(
      "input",
      sprintf("%s names must equal the SBS96 registry labels", arg_nm),
      i = "opportunities are matched by label, never by position",
      j = sprintf("first names: %s", msuiter_quote_trunc(utils::head(nm, 3L))),
      c = "set names(opps) to the registry labels"
    )
  }
  if (any(!is.finite(opps)) || any(opps <= 0)) {
    msuiter_abort(
      "input",
      sprintf("%s must be positive and finite", arg_nm),
      i = "an opportunity of 0 makes the division undefined",
      j = sprintf("offending entries: %d", sum(!is.finite(opps) | opps <= 0)),
      c = "opportunity tables are strictly positive frequencies"
    )
  }
  stats::setNames(as.numeric(opps), as.character(labels))
}

# The kernel: divide, multiply, re-normalize; zero columns stay zero.
.ms_convert_kernel <- function(sig, o_from, o_to) {
  out <- sig * (o_to / o_from)
  totals <- colSums(out)
  keep <- totals > 0
  out[, keep] <- sweep(out[, keep, drop = FALSE], 2L, totals[keep], "/")
  out
}

# Method: matrices.
S7::method(ms_convert, S7::class_any) <- function(signatures,
                                                  from = "human-genome",
                                                  to = "human-exome") {
  if (S7::S7_inherits(signatures, MsSignature)) {
    sig <- signatures@signatures
    out_mat <- .ms_convert_dispatch_matrix(sig, from, to)
    out <- signatures
    out@signatures <- out_mat
    return(out)
  }
  .ms_convert_dispatch_matrix(signatures, from, to)
}

.ms_convert_dispatch_matrix <- function(sig, from, to) {
  if (!is.numeric(sig) || !is.matrix(sig)) {
    msuiter_abort(
      "input",
      "signatures must be a numeric matrix",
      i = "ms_convert() re-expresses SBS96 signatures between opportunities",
      j = paste0("received: ", class(sig)[1L]),
      c = "pass 96 x k with registry rownames (or an MsSignature)"
    )
  }
  labels <- rownames(sig)
  reg <- get("channel_tables", envir = asNamespace("msuiter"))$SBS96$labels
  if (is.null(labels) || !identical(as.character(labels), reg)) {
    msuiter_abort(
      "input",
      "signatures must carry the SBS96 registry rownames in canonical order",
      i = "the opportunity tables are matched by label, never by position",
      j = if (is.null(labels)) "rownames missing" else
        sprintf("first rownames: %s", msuiter_quote_trunc(utils::head(labels, 3L))),
      c = "order the matrix by the registry labels"
    )
  }
  o_from <- .ms_convert_resolve_opps(from, labels, "from")
  o_to <- .ms_convert_resolve_opps(to, labels, "to")
  .ms_convert_kernel(sig, o_from, o_to)
}
