# MsSignature: the L3 extraction/fitting result container.
#
# signatures: channels x signatures matrix; exposures: signatures x samples
# matrix; stability / k_evidence: method evidence slots; engine + seed:
# method identity; catalog_summary: the A5 snapshot summary of the source
# catalog (dimensions + channel-table hash + build) -- deliberately NOT an
# embedded MsCatalog, to avoid memory doubling and waldo noise. There is no
# .state property anywhere (D12: stateless FFI).

#' MsSignature: extracted signatures with a catalog snapshot summary
#'
#' An [MsSignature] holds de-novo extracted signatures and their exposures
#' plus the method evidence (stability, K selection), the engine name, the
#' seed and a **snapshot summary** of the source catalog. The summary carries
#' dimensions, the channel-table hash and the build -- never the catalog
#' itself (A5). Violations raise `msuiter_error_signature`.
#'
#' @param signatures numeric matrix (channels x signatures) with rownames =
#'   channel labels, colnames = signature labels.
#' @param exposures numeric matrix (signatures x samples) with rownames
#'   identical to `colnames(signatures)` and colnames = sample labels.
#' @param catalog_summary snapshot summary as built by
#'   [msuiter_catalog_summary()]: list with fields `n_channels`, `n_samples`,
#'   `channel_name`, `channel_hash`, `build`.
#' @param engine single non-empty string naming the engine used.
#' @param seed single finite number: the seed behind the result.
#' @param stability named list of stability evidence (default empty).
#' @param k_evidence data.frame of K-selection evidence with a `k` column
#'   when non-empty (default empty).
#'
#' @export
MsSignature <- S7::new_class(
  "MsSignature",
  package = "msuiter",
  properties = list(
    signatures = S7::new_property(S7::class_any),
    exposures = S7::new_property(S7::class_any),
    stability = S7::new_property(S7::class_list),
    k_evidence = S7::new_property(S7::class_any),
    engine = S7::new_property(S7::class_character),
    seed = S7::new_property(S7::class_numeric),
    catalog_summary = S7::new_property(S7::class_list)
  ),
  validator = function(self) msuiter_validate_signature(self)
)

msuiter_validate_signature <- function(self) {
  sigs <- self@signatures
  msuiter_check_signature_matrix(sigs, "signatures", "signature")
  exp1 <- self@exposures
  msuiter_check_signature_matrix(exp1, "exposures", "signature")

  # Label agreement between signatures and exposures (by label, element-wise).
  if (!identical(colnames(sigs), rownames(exp1))) {
    offenders <- colnames(sigs)[!colnames(sigs) %in% rownames(exp1)]
    msuiter_abort(
      "signature",
      "exposure rows must carry the signature labels of the signatures matrix",
      i = "signatures and exposures are matched by label, element by element",
      j = paste0("signature labels missing from exposures: ",
        msuiter_quote_trunc(offenders)),
      c = "refit the exposures against the exact signature set"
    )
  }

  msuiter_check_catalog_summary(self@catalog_summary, self, sigs, exp1)

  engine <- self@engine
  if (!is.character(engine) || length(engine) != 1L || is.na(engine) || !nzchar(engine)) {
    msuiter_abort(
      "signature",
      "engine must be a single non-empty string",
      i = "the engine name pins the method behind the result",
      j = paste0("received: ", msuiter_quote_trunc(engine)),
      c = "record the engine name used for extraction"
    )
  }
  seed <- self@seed
  if (!is.numeric(seed) || length(seed) != 1L || is.na(seed) || !is.finite(seed)) {
    msuiter_abort(
      "signature",
      "seed must be a single finite number",
      i = "the seed makes the extraction reproducible",
      j = paste0("received: ", msuiter_quote_trunc(seed)),
      c = "record the integer seed used by the engine"
    )
  }
  if (!is.data.frame(self@k_evidence)) {
    msuiter_abort(
      "signature",
      "k_evidence must be a data.frame",
      i = "K-selection evidence is stored as a tidy table",
      j = paste0("received: ", class(self@k_evidence)[1L]),
      c = "pass the K selection table as a data.frame"
    )
  }
  if (nrow(self@k_evidence) > 0L && !"k" %in% names(self@k_evidence)) {
    msuiter_abort(
      "signature",
      "non-empty k_evidence must have a 'k' column",
      i = "the K value is the join key for arbitration (A10)",
      j = paste0("received columns: ", msuiter_quote_trunc(names(self@k_evidence))),
      c = "add the k column to the evidence table"
    )
  }
  if (!is.list(self@stability)) {
    msuiter_abort(
      "signature",
      "stability must be a list",
      i = "stability evidence is a named list of statistics",
      j = paste0("received: ", class(self@stability)[1L]),
      c = "pass stability statistics as a named list"
    )
  }
  NULL
}

# Shared matrix checks for signatures/exposures (and fit exposures).
msuiter_check_signature_matrix <- function(m, what, topic) {
  if (!is.matrix(m) || !is.numeric(m)) {
    msuiter_abort(
      topic,
      sprintf("%s must be a numeric matrix", what),
      i = "matrices carry labels in their dimnames",
      j = paste0("received: ", class(m)[1L]),
      c = "pass a numeric matrix with rownames and colnames"
    )
  }
  if (is.null(rownames(m)) || is.null(colnames(m))) {
    msuiter_abort(
      topic,
      sprintf("%s must carry rownames and colnames", what),
      i = "labels are the only legal matching key (never position)",
      j = sprintf(
        "rownames missing: %s; colnames missing: %s",
        is.null(rownames(m)), is.null(colnames(m))
      ),
      c = "set the matrix dimnames before construction"
    )
  }
  if (anyDuplicated(rownames(m)) != 0L || anyDuplicated(colnames(m)) != 0L) {
    msuiter_abort(
      topic,
      sprintf("%s labels must be unique", what),
      i = "duplicated labels make label matching ambiguous",
      j = paste0(
        "duplicated rows: ",
        msuiter_quote_trunc(rownames(m)[duplicated(rownames(m))]),
        "; duplicated cols: ",
        msuiter_quote_trunc(colnames(m)[duplicated(colnames(m))])
      ),
      c = "de-duplicate or rename labels"
    )
  }
  if (anyNA(m) || any(!is.finite(m))) {
    msuiter_abort(
      topic,
      sprintf("%s must not contain NA or non-finite values", what),
      i = "the FFI contract rejects NA",
      j = paste0("offending cells: ", msuiter_quote_trunc(which(is.na(m) | !is.finite(m)))),
      c = "fix the upstream computation"
    )
  }
  if (any(m < 0)) {
    msuiter_abort(
      topic,
      sprintf("%s must be non-negative", what),
      i = "signatures and exposures are non-negative by definition",
      j = paste0("offending cells: ", msuiter_quote_trunc(which(m < 0))),
      c = "check the engine output for sign errors"
    )
  }
  NULL
}

# Snapshot-summary contract: exact fields, correct types, dimension agreement
# with the matrices (A5).
msuiter_check_catalog_summary <- function(summary1, self, sigs, exp1) {
  required <- c("n_channels", "n_samples", "channel_name", "channel_hash", "build")
  if (!is.list(summary1) || !setequal(names(summary1), required)) {
    msuiter_abort(
      "signature",
      "catalog_summary must be the contracted snapshot summary",
      i = paste0("snapshot fields: ", paste(required, collapse = ", ")),
      j = paste0("received fields: ", msuiter_quote_trunc(names(summary1))),
      c = "build it with msuiter_catalog_summary(catalog)"
    )
  }
  whole <- function(x) is.numeric(x) && length(x) == 1L && !is.na(x) && x == trunc(x)
  if (!whole(summary1$n_channels) || !whole(summary1$n_samples)) {
    msuiter_abort(
      "signature",
      "catalog_summary dimensions must be single whole numbers",
      i = "n_channels/n_samples summarize the catalog dimensions",
      j = sprintf(
        "n_channels = %s, n_samples = %s",
        msuiter_quote_trunc(summary1$n_channels),
        msuiter_quote_trunc(summary1$n_samples)
      ),
      c = "derive the summary from a validated MsCatalog"
    )
  }
  for (nm in c("channel_name", "channel_hash", "build")) {
    v <- summary1[[nm]]
    if (!is.character(v) || length(v) != 1L || is.na(v) || !nzchar(v)) {
      msuiter_abort(
        "signature",
        sprintf("catalog_summary field '%s' must be a single non-empty string", nm),
        i = "the summary pins channel table identity and build",
        j = paste0("received: ", msuiter_quote_trunc(v)),
        c = "derive the summary from a validated MsCatalog"
      )
    }
  }
  if (!grepl("^[0-9a-f]{32}$", summary1$channel_hash)) {
    msuiter_abort(
      "signature",
      "catalog_summary$channel_hash must be an md5 hex digest",
      i = "the hash pins the channel table (A5)",
      j = paste0("received: ", msuiter_quote_trunc(summary1$channel_hash)),
      c = "derive the summary from a validated MsCatalog"
    )
  }
  if (nrow(sigs) != summary1$n_channels) {
    msuiter_abort(
      "signature",
      "signatures rows disagree with the catalog_summary channel count",
      i = "signatures live in the catalog's channel space",
      j = sprintf("nrow(signatures) = %d, summary$n_channels = %d",
        nrow(sigs), summary1$n_channels),
      c = "re-extract signatures in the same channel space as the catalog"
    )
  }
  if (ncol(exp1) != summary1$n_samples) {
    msuiter_abort(
      "signature",
      "exposures columns disagree with the catalog_summary sample count",
      i = "exposures live in the catalog's sample space",
      j = sprintf("ncol(exposures) = %d, summary$n_samples = %d",
        ncol(exp1), summary1$n_samples),
      c = "re-fit exposures on the same samples as the catalog"
    )
  }
  NULL
}

#' Construct an MsSignature object
#'
#' Builds and validates an [MsSignature]. Derive `catalog_summary` with
#' [msuiter_catalog_summary()] from the [MsCatalog] the signatures were
#' extracted from.
#'
#' @inheritParams MsSignature
#' @return An [MsSignature] object.
#' @examples
#' labels <- paste0("CH", 1:4)
#' counts <- matrix(1:8, 4, 2, dimnames = list(labels, c("S1", "S2")))
#' cat1 <- ms_catalog(counts, list(name = "SYN4", labels = labels),
#'   c("S1", "S2"), provenance = list(genome = "GRCh38"))
#' sigs <- matrix(1:8, 4, 2, dimnames = list(labels, c("SIG1", "SIG2")))
#' exp1 <- matrix(1:4, 2, 2,
#'   dimnames = list(c("SIG1", "SIG2"), c("S1", "S2")))
#' # The channel hash is always derived from the catalog's labels — never
#' # forged by hand (see MsCatalog docs).
#' summary1 <- list(
#'   n_channels = 4L, n_samples = 2L, channel_name = cat1@channels$name,
#'   channel_hash = cat1@channels$hash, build = "GRCh38"
#' )
#' ms_signature(sigs, exp1, summary1, engine = "synthetic", seed = 1)
#' @export
ms_signature <- function(signatures, exposures, catalog_summary, engine, seed,
                         stability = list(), k_evidence = data.frame()) {
  out <- MsSignature(
    signatures = signatures, exposures = exposures,
    catalog_summary = catalog_summary, engine = engine, seed = seed,
    stability = stability, k_evidence = k_evidence
  )
  out
}

# One-line print/format: class name / dimensions / method identity.
S7::method(format, MsSignature) <- function(x, ...) {
  sprintf(
    "<MsSignature> %d signatures x %d samples | engine: %s | seed: %s",
    ncol(x@signatures), ncol(x@exposures), x@engine, format(x@seed)
  )
}

S7::method(print, MsSignature) <- function(x, ...) {
  cat(format(x, ...), "\n", sep = "")
  invisible(x)
}
