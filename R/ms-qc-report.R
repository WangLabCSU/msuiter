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
#
# P4 (parity plan docs/research/09-sigminer-v3-parity-plan.md §5 row P4):
# the computation core is factored into the .ms_qc_* private helpers here
# so the sibling surfaces in R/ms-qc-sentries.R EXPRESS the certified
# numbers by delegation -- one implementation, never a second opinion --
# and the report carries the provenance checklist built by
# .ms_qc_provenance_rows().

# The COSMIC artifact roster, verified verbatim against the COSMIC SBS
# index (cancer.sanger.ac.uk/cosmic/signatures/SBS, 2026-10-04): every
# signature listed under "Possible sequencing artefacts" (aetiology
# "Artefact"). The test layer pins this vector literally -- keep it in
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
# damaged strand, i.e. C>A in this space -- the sentinel share is the
# total C>A channel share. FFPE deamination reads C>T in both views.
.ms_qc_gt_channels <- function(labels) {
  grep("C>A", labels, value = TRUE)
}

.ms_qc_ct_channels <- function(labels) {
  grep("C>T", labels, value = TRUE)
}

# --- the shared computation core (single source for every QC surface) ----

# The catalog input gate (ms_qc_report's original structured check).
.ms_qc_check_catalog <- function(catalog) {
  if (!S7::S7_inherits(catalog, MsCatalog)) {
    msuiter_abort(
      "input",
      "catalog must be an MsCatalog",
      i = "the QC report surfaces read cataloged mutation counts",
      j = paste0("received: ", class(catalog)[1L]),
      c = "pass the object returned by ms_catalog() / ms_tally()"
    )
  }
  invisible(catalog)
}

# The SBS96 channel gate: the sentinel families must have exactly 16
# channels each (memo §2 -- the sentinels and the roster are SBS96-native).
.ms_qc_channel_plan <- function(labels, n_channels) {
  gtx <- .ms_qc_gt_channels(labels)
  ctx <- .ms_qc_ct_channels(labels)
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
  list(gt = gtx, ct = ctx)
}

# The certified shares (memo §3): fixed-order per-column sums, no
# reassociation; honest NA (never NaN) for zero-total samples.
.ms_qc_shares <- function(counts, labels, gtx, ctx) {
  totals <- colSums(counts)
  gt <- colSums(counts[labels %in% gtx, , drop = FALSE])
  ct <- colSums(counts[labels %in% ctx, , drop = FALSE])
  list(
    totals = totals,
    gt_share = ifelse(totals > 0, gt / totals, NA_real_),
    ct_share = ifelse(totals > 0, ct / totals, NA_real_)
  )
}

.ms_qc_log10 <- function(totals) {
  ifelse(totals > 0, log10(totals), NA_real_)
}

# The house-declared burden classes (memo §3: our constants, divergence
# declared; mSigAct's <100 drop is a fit floor, not a QC tier).
.ms_qc_burden_class <- function(totals) {
  ifelse(totals == 0, "dead",
    ifelse(totals < .ms_qc_defaults$burden_low, "low",
      ifelse(totals < .ms_qc_defaults$burden_high, "standard", "high")))
}

# The declared initial-version flag (memo §3 / §4 acceptance rules):
# artifact_share >= artifact_share_flag OR gt_share >= gt_share_flag
#   => artifact;  ct_share >= ct_share_watch OR burden_class == "low"
#   => watch;  otherwise ok.
.ms_qc_flag <- function(artifact_share, gt_share, ct_share, burden_class) {
  ifelse(
    (!is.na(artifact_share) & artifact_share >= .ms_qc_defaults$artifact_share_flag) |
      (!is.na(gt_share) & gt_share >= .ms_qc_defaults$gt_share_flag),
    "artifact",
    ifelse((!is.na(ct_share) & ct_share >= .ms_qc_defaults$ct_share_watch) |
             burden_class == "low",
           "watch", "ok")
  )
}

# The certified roster block (memo §1 roster + §3 share formula): the
# full input-validation face plus the per-sample roster exposure share.
# Returns the frozen column values plus the shared denominator.
.ms_qc_roster_block <- function(counts, labels, n_channels, signatures,
                                exposures) {
  n_samples <- ncol(counts)
  artifact_share <- rep(NA_real_, n_samples)
  artifact_sigs <- rep(NA_character_, n_samples)
  signatures <- as.matrix(signatures)
  exposures <- as.matrix(exposures)
  if (ncol(exposures) != n_samples) {
    msuiter_abort(
      "input",
      "exposures must have one column per catalog sample",
      i = "the artifact share reads per-sample exposure columns",
      j = sprintf("exposures columns: %d; samples: %d",
                  ncol(exposures), n_samples),
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
  # The label protocol: exposure rows carry the signature labels --
  # positional acceptance of mislabeled rows would silently misassign
  # artifact shares.
  if (!is.null(rownames(exposures)) && !is.null(colnames(signatures)) &&
      !identical(rownames(exposures), colnames(signatures))) {
    msuiter_abort(
      "input",
      "exposure row labels must equal the signature column labels",
      i = "labels are the only legal matching key (never position)",
      j = sprintf("exposure rows: %s",
                  msuiter_quote_trunc(utils::head(rownames(exposures), 3L))),
      c = "pass the exposure matrix produced with this dictionary"
    )
  }
  # Match the artifact roster by SIGNATURE NAME stem (dictionaries
  # write SBS43, sometimes suffixed SBS45a -- the roster pin is the
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
  list(share = artifact_share, sigs = artifact_sigs, total = col_tot)
}

# --- the provenance checklist -------------------------------------------------
# Card contract: inputs + catalog refdb pin + generation params. The house
# provenance idiom is the catalog@provenance validator face
# (R/classes-catalog.R:218-236) and the tally builders' key set
# (R/catalog-tally.R:238-250); the refdb pin re-reads the bundled
# governance manifest (R/refdb.R:357-373, "every field is safe to embed
# in a provenance record"). As an AUDIT face this records a failing
# channel space instead of aborting on it.
# -------------------------------------------------------------------------------
.ms_qc_provenance_rows <- function(catalog) {
  .ms_qc_check_catalog(catalog)
  labels <- as.character(catalog@channels$labels)
  n_gt <- length(.ms_qc_gt_channels(labels))
  n_ct <- length(.ms_qc_ct_channels(labels))
  prov <- catalog@provenance
  genome <- prov$genome
  # The recognized input/generation keys of the house provenance idiom:
  # the tally builders (R/catalog-tally.R:238-243) and the simulator
  # (R/ms-simulate.R:157-166).
  recognized <- c("mode", "genome_path", "n_variants", "n_skipped",
                  "arm", "size", "seed", "burden", "exposure_scale")
  have <- recognized[!vapply(recognized,
    function(k) is.null(prov[[k]]), logical(1))]
  key_text <- paste0(have, "=",
    vapply(have, function(k) as.character(prov[[k]])[1L], character(1)),
    collapse = ", ")
  mf <- tryCatch(
    {
      m <- ms_refdb_manifest()
      list(version = m$version, schema = m$schema_version)
    },
    error = function(e) NULL
  )
  def <- .ms_qc_defaults
  roster <- .ms_qc_artifact_sbs
  pkg_version <- tryCatch(
    as.character(utils::packageVersion("msuiter")),
    error = function(e) "dev"
  )
  genome_ok <- is.character(genome) && length(genome) == 1L &&
    !is.na(genome) && nzchar(genome)
  rows <- data.frame(
    check = c("catalog.class", "channel.space", "provenance.genome",
              "provenance.keys", "refdb.pin", "roster.pin",
              "thresholds.declared", "msuiter.version"),
    status = c(
      "pass",
      if (n_gt == 16L && n_ct == 16L) "pass" else "fail",
      if (genome_ok) "pass" else "fail",
      if (length(have)) "pass" else "na",
      if (!is.null(mf)) "pass" else "fail",
      if (length(roster) == 19L && !any(duplicated(roster)) &&
          all(nzchar(roster))) "pass" else "fail",
      if (identical(names(def), c("burden_low", "burden_high",
            "artifact_share_flag", "gt_share_flag", "ct_share_watch")) &&
          all(vapply(def, is.numeric, logical(1)))) "pass" else "fail",
      "pass"
    ),
    value = c(
      "MsCatalog",
      sprintf("channels=%d; C>A=%d; C>T=%d", length(labels), n_gt, n_ct),
      if (genome_ok) genome else "(missing)",
      if (length(have)) key_text else "(none recorded)",
      if (!is.null(mf)) paste0("v", mf$version, " schema ", mf$schema)
      else "(unavailable)",
      paste0(length(roster), " entries: ", paste0(roster, collapse = ",")),
      paste0(names(def), "=",
        vapply(def, format, character(1)), collapse = ", "),
      pkg_version
    ),
    stringsAsFactors = FALSE
  )
  # The MsQcProvenance stamp lives here so the report-carried attribute and
  # the standalone ms_qc_provenance() surface are one and the same object.
  class(rows) <- c("MsQcProvenance", "data.frame")
  attr(rows, "genome") <- if (genome_ok) genome else "(unknown)"
  rows
}

# The verdict split of a certified share under a frozen house constant:
# the two-clause membership of the .ms_qc_flag rules, spoken per
# mechanism with an explicit "na" for zero-total (NA-share) samples.
.ms_qc_verdict <- function(share, line, hit_label) {
  ifelse(is.na(share), "na",
    ifelse(share >= line, hit_label, "ok"))
}

# Per-surface construction helper: the validated shares + classes from a
# catalog, for the sibling surfaces (never a re-implementation).
.ms_qc_surface_core <- function(catalog) {
  .ms_qc_check_catalog(catalog)
  counts <- catalog@counts
  labels <- as.character(catalog@channels$labels)
  plan <- .ms_qc_channel_plan(labels, nrow(counts))
  sh <- .ms_qc_shares(counts, labels, plan$gt, plan$ct)
  list(shares = sh, burden_class = .ms_qc_burden_class(sh$totals),
       genome = catalog@provenance$genome, n_samples = ncol(counts))
}

# --- the report itself --------------------------------------------------------

#' Per-sample QC report
#'
#' Builds the M4 first-version QC table: per-sample mutation burden
#' (total, log10, burden class), mechanism-level artifact sentinels
#' (G>T share as the oxoG sentinel, C>T share as the FFPE deamination
#' sentinel) and, when a fitted exposure matrix is supplied, the share of
#' exposure carried by the 19 COSMIC artifact signatures (SBS27, SBS43, SBS45–60, SBS95). The Degasperi
#' amber/red tiering is not implemented (v1.x); `qc_flag` applies our
#' declared initial-version constants. The returned table carries the
#' P4 provenance checklist as the `ms_qc_provenance` attribute (see
#' [ms_qc_provenance()]).
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
#' 2013 (doi:10.1093/nar/gks1443). FFPE sentinel: Guo et al., Nat Commun
#' 2022 (doi:10.1038/s41467-022-32041-5). Design memo:
#' `docs/devlog/2026-10-04-M4-02b-qc-memo.md` sections 1, 3 and 4.
#'
#' @export
ms_qc_report <- function(catalog, signatures = NULL, exposures = NULL) {
  core <- .ms_qc_surface_core(catalog)
  counts <- catalog@counts
  labels <- as.character(catalog@channels$labels)
  sh <- core$shares

  out <- data.frame(
    sample = catalog@samples,
    total = sh$totals,
    log10_total = .ms_qc_log10(sh$totals),
    burden_class = core$burden_class,
    gt_share = sh$gt_share,
    ct_share = sh$ct_share,
    # The TSB strand-bias sentinel needs the SBS192 catalog face — the
    # memo §3 contract holds its place as NA in this batch.
    strand_bias_p = rep(NA_real_, ncol(counts)),
    stringsAsFactors = FALSE
  )

  # --- artifact-share block (needs the fitted exposures) ------------------
  artifact_share <- rep(NA_real_, ncol(counts))
  artifact_sigs <- rep(NA_character_, ncol(counts))
  have_fit <- !is.null(signatures) && !is.null(exposures)
  if (have_fit) {
    rb <- .ms_qc_roster_block(counts, labels, nrow(counts),
                              signatures, exposures)
    artifact_share <- rb$share
    artifact_sigs <- rb$sigs
  }
  out$artifact_share <- artifact_share
  out$artifact_sigs <- artifact_sigs

  # --- the declared initial-version flag (memo §3) ------------------------
  out$qc_flag <- .ms_qc_flag(artifact_share, sh$gt_share, sh$ct_share,
                             out$burden_class)
  attr(out, "ms_qc_provenance") <- .ms_qc_provenance_rows(catalog)
  out
}
