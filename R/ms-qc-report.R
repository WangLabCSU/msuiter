# ms-qc-report.R: the sample-level QC report (U-M4-02b; design memo
# docs/devlog/2026-10-04-M4-02b-qc-memo.md).
#
# This is the M4 first version: burden distribution + mechanism-level
# artifact sentinels + (with exposures) the COSMIC artifact-signature
# share. The Degasperi amber/red fit-level tiering is deliberately NOT
# claimed here (v1.x): no verifiable per-sample thresholds were
# obtainable, and unverified protocols do not ship ([V] discipline, memo
# §1). The qc_flag constants below are OUR initial defaults, declared as
# a divergence, not upstream reproductions.

# The COSMIC artifact roster, verified verbatim against the COSMIC SBS
# index (cancer.sanger.ac.uk/cosmic/signatures/SBS, 2026-10-04): every
# signature listed under "Possible sequencing artefacts" (aetiology
# "Artefact"). The test layer pins this vector literally — keep it in
# sync with the upstream page.
.ms_qc_artifact_sbs <- c(
  "SBS27", "SBS43",
  paste0("SBS", 45:60),
  "SBS95"
)

# Frozen initial-version constants (memo §3; declared divergence).
.ms_qc_defaults <- list(
  burden_low = 100, # mSigAct's fit floor, borrowed as the low-burden line
  burden_high = 1e4,
  artifact_share_flag = 0.05,
  gt_share_flag = 0.30,
  ct_share_watch = 0.40
)

# The SBS96 registry is pyrimidine-normalized (C/T reference, exactly 16
# channels per substitution class). The oxoG artifact reads as G>T on the
# damaged strand, i.e. C>A in this space — the sentinel share is the
# total C>A channel share. FFPE deamination reads C>T in both views.
.ms_qc_gt_channels <- function(labels) {
  grep("C>A", labels, value = TRUE)
}

.ms_qc_ct_channels <- function(labels) {
  grep("C>T", labels, value = TRUE)
}

#' Per-sample QC report
#'
#' Builds the M4 first-version QC table: per-sample mutation burden
#' (total, log10, burden class), mechanism-level artifact sentinels
#' (G>T share as the oxoG sentinel, C>T share as the FFPE deamination
#' sentinel) and, when a fitted exposure matrix is supplied, the share of
#' exposure carried by the 20 COSMIC artifact signatures. The Degasperi
#' amber/red tiering is not implemented (v1.x); `qc_flag` applies our
#' declared initial-version constants.
#'
#' @param catalog An [MsCatalog] in the SBS96 channel space.
#' @param signatures Optional signature matrix (m x k, SBS96 labels) —
#'   with `exposures`, enables the artifact-share block.
#' @param exposures Optional k x n count-scale exposure matrix matching
#'   `signatures` and the catalog's samples.
#'
#' @return A data.frame, one row per sample.
#'
#' @references
#' COSMIC artifact roster: cancer.sanger.ac.uk/cosmic/signatures/SBS
#' (SBS27, SBS43, SBS45–60, SBS95). oxoG sentinel: Costello et al., NAR
#' 2013 (doi:10.1093/nar/gkt085). FFPE sentinel: Guo et al., Nat Commun
#' 2022 (doi:10.1038/s41467-022-32721-0).
#'
#' @export
ms_qc_report <- function(catalog, signatures = NULL, exposures = NULL) {
  if (!S7::S7_inherits(catalog, MsCatalog)) {
    msuiter_abort(
      "input",
      "catalog must be an MsCatalog",
      i = "ms_qc_report() reads cataloged mutation counts",
      j = paste0("received: ", class(catalog)[1L]),
      c = "pass the object returned by ms_catalog() / ms_tally()"
    )
  }
  counts <- catalog@counts
  labels <- as.character(catalog@channels$labels)
  n_channels <- nrow(counts)
  gtx <- msuiter:::.ms_qc_gt_channels(labels)
  ctx <- msuiter:::.ms_qc_ct_channels(labels)
  if (length(gtx) != 16L || length(ctx) != 16L) {
    msuiter_abort(
      "input",
      "ms_qc_report() needs an SBS96 channel space",
      i = "the artifact sentinels and the COSMIC artifact roster are SBS96-native",
      j = sprintf("G>T channels: %d; C>T channels: %d (need 16 each)",
                  length(gtx), length(ctx)),
      c = "tally the catalog with mode = \"SBS96\""
    )
  }

  totals <- colSums(counts)
  # Fixed-order per-column sums (no reassociation): the sentinel shares
  # are honest even for zero-total samples (NA, not NaN).
  gt <- colSums(counts[labels %in% gtx, , drop = FALSE])
  ct <- colSums(counts[labels %in% ctx, , drop = FALSE])
  gt_share <- ifelse(totals > 0, gt / totals, NA_real_)
  ct_share <- ifelse(totals > 0, ct / totals, NA_real_)

  burden_class <- ifelse(totals == 0, "dead",
    ifelse(totals < .ms_qc_defaults$burden_low, "low",
      ifelse(totals < .ms_qc_defaults$burden_high, "standard", "high")))

  out <- data.frame(
    sample = catalog@samples,
    total = totals,
    log10_total = ifelse(totals > 0, log10(totals), NA_real_),
    burden_class = burden_class,
    gt_share = gt_share,
    ct_share = ct_share,
    stringsAsFactors = FALSE
  )

  # --- artifact-share block (needs the fitted exposures) ------------------
  artifact_share <- rep(NA_real_, ncol(counts))
  artifact_sigs <- rep(NA_character_, ncol(counts))
  have_fit <- !is.null(signatures) && !is.null(exposures)
  if (have_fit) {
    signatures <- as.matrix(signatures)
    exposures <- as.matrix(exposures)
    if (ncol(exposures) != ncol(counts)) {
      msuiter_abort(
        "input",
        "exposures must have one column per catalog sample",
        i = "the artifact share reads per-sample exposure columns",
        j = sprintf("exposures columns: %d; samples: %d",
                    ncol(exposures), ncol(counts)),
        c = "pass the refit run on this very catalog"
      )
    }
    if (nrow(signatures) != n_channels ||
        !setequal(rownames(signatures), labels)) {
      msuiter_abort(
        "input",
        "signatures must live in the catalog's SBS96 channel space",
        i = "the COSMIC artifact roster is matched by signature NAME, the fit by channel labels",
        j = sprintf("signature rows: %d; catalog channels: %d",
                    nrow(signatures), n_channels),
        c = "pass the SBS96-space dictionary used for the refit"
      )
    }
    if (nrow(exposures) != ncol(signatures)) {
      msuiter_abort(
        "input",
        "exposures rows must match the signature columns",
        i = "exposures are matched to signatures by label/position",
        j = sprintf("exposures rows: %d; signatures: %d",
                    nrow(exposures), ncol(signatures)),
        c = "pass the exposure matrix produced with this dictionary"
      )
    }
    # Match the artifact roster by SIGNATURE NAME stem (dictionaries
    # write SBS43, sometimes suffixed SBS45a — the roster pin is the
    # numeric stem).
    sig_names <- colnames(signatures)
    if (is.null(sig_names)) {
      sig_names <- paste0("sig", seq_len(ncol(signatures)))
    }
    stems <- toupper(sub("^(SBS[0-9]+).*$", "\\1", sig_names))
    is_artifact <- stems %in% .ms_qc_artifact_sbs
    col_tot <- colSums(exposures)
    for (j in seq_len(ncol(exposures))) {
      tj <- col_tot[j]
      if (!is.finite(tj) || tj <= 0) {
        next
      }
      a <- sum(exposures[is_artifact, j])
      artifact_share[j] <- a / tj
      if (a > 0) {
        artifact_sigs[j] <- paste(sort(sig_names[is_artifact][
          exposures[is_artifact, j] > 0]), collapse = ",")
      }
    }
  }
  out$artifact_share <- artifact_share
  out$artifact_sigs <- artifact_sigs

  # --- the declared initial-version flag (memo §3) ------------------------
  out$qc_flag <- ifelse(
    (!is.na(out$artifact_share) & out$artifact_share >= .ms_qc_defaults$artifact_share_flag) |
      (!is.na(out$gt_share) & out$gt_share >= .ms_qc_defaults$gt_share_flag),
    "artifact",
    ifelse((!is.na(out$ct_share) & out$ct_share >= .ms_qc_defaults$ct_share_watch) |
             out$burden_class == "low",
           "watch", "ok")
  )
  out
}
