# ms-qc-sentries.R: the P4 QC sentries sibling surfaces (parity plan
# docs/research/09-sigminer-v3-parity-plan.md §5 row P4: burden
# distribution, gt/ct mechanism sentries, artifact-roster exposure share,
# plus the provenance checklist carried by ms_qc_report()).
#
# EXPOSURE, NOT INVENTION. Every number spoken here comes from the
# certified computation core in R/ms-qc-report.R (the .ms_qc_* helpers)
# or from the frozen house constants it owns; no threshold, share
# definition or mechanism reading is added by this file. The certified
# backing per surface is cited in the @references blocks below (design
# memo docs/devlog/2026-10-04-M4-02b-qc-memo.md sections 1, 3 and 4).
#
# Declined for lack of certified backing (recorded in the lane report):
# the "garbage-tracking / cellular-toxicity" reading of gt/ct (no such
# mechanism exists anywhere in this repo -- the certified pair is oxoG
# G>T / FFPE deamination, memo section 1); a channel-level artifact-roster
# share (the COSMIC roster names SIGNATURES, there is no channel-to-roster
# mapping to share against); the Degasperi amber/red tiering (memo
# section 1, plan section 6.4); the TSB strand-bias p-value (needs the
# SBS192 face -- held as NA in the report contract).

# --- shared print furniture (the house idiom is print.MsHrdReport, ------
# R/hrd-report.R:350-362; floor-safe: no above-floor operators) -------------
# --------------------------------------------------------------------------
.ms_qc_print_surface <- function(header, x, context = character(0)) {
  cat(sprintf("<%s>\n", header))
  for (line in context) {
    cat(sprintf("  %s\n", line))
  }
  plain <- x
  class(plain) <- "data.frame"
  if (nrow(plain)) {
    print(plain, row.names = FALSE)
  } else {
    print(plain)
  }
  invisible(x)
}

.ms_qc_attr_or <- function(x, nm, default = "(unknown)") {
  v <- attr(x, nm, exact = TRUE)
  if (is.null(v)) default else as.character(v)[1L]
}

# --- 1. the burden distribution surface --------------------------------------

#' Per-sample burden distribution table
#'
#' The burden block of the certified QC report (design memo
#' `docs/devlog/2026-10-04-M4-02b-qc-memo.md` section 3, as implemented in
#' `R/ms-qc-report.R:95-105` at the time this surface was factored out),
#' exposed as its own addressable surface: one row per sample with the
#' total burden, its base-10 log and the house-declared burden class
#' (dead/low/standard/high over the frozen `.ms_qc_defaults` constants).
#' The values delegate to the same computation core as
#' [ms_qc_report()] -- column-for-column identical, never a second
#' implementation.
#'
#' @param catalog An [MsCatalog] in the SBS96 channel space.
#'
#' @return An `MsQcBurden` data.frame, one row per sample, columns in the
#'   frozen order `sample`, `total`, `log10_total`, `burden_class`.
#'
#' @references
#' Design memo `docs/devlog/2026-10-04-M4-02b-qc-memo.md` section 3
#' (burden block, house-declared classes with the divergence note);
#' computation core `R/ms-qc-report.R` (.ms_qc_shares, .ms_qc_log10,
#' .ms_qc_burden_class, .ms_qc_defaults).
#'
#' @export
ms_qc_burden <- function(catalog) {
  core <- .ms_qc_surface_core(catalog)
  out <- data.frame(
    sample = catalog@samples,
    total = core$shares$totals,
    log10_total = .ms_qc_log10(core$shares$totals),
    burden_class = core$burden_class,
    stringsAsFactors = FALSE
  )
  attr(out, "genome") <- core$genome
  class(out) <- c("MsQcBurden", "data.frame")
  out
}

#' Print a burden distribution table
#'
#' @param x An `MsQcBurden` as returned by [ms_qc_burden()].
#' @param ... Further arguments (unused; compatibility with the generic).
#' @return `x`, invisibly.
#' @export
print.MsQcBurden <- function(x, ...) {
  .ms_qc_print_surface("msuiter QC burden", x,
    sprintf("genome=%s  samples=%d", .ms_qc_attr_or(x, "genome"), nrow(x)))
}

# --- 2. the gt/ct mechanism sentries ------------------------------------------

#' Per-sample gt/ct mechanism sentries
#'
#' The mechanism-level artifact sentinels of the certified QC report: the
#' oxoG sentinel share (C>A channel mass in the pyrimidine-normalized
#' SBS96 space, where the damaged-strand G>T of oxoG reads) and the FFPE
#' sentinel share (C>T deamination mass), each with its frozen house
#' verdict clause spoken per mechanism -- `gt_verdict` "hit" at
#' `gt_share >= gt_share_flag` (the artifact clause of the certified
#' `qc_flag`), `ct_verdict` "watch" at `ct_share >= ct_share_watch` (the
#' watch clause), "na" for zero-total samples whose shares are NA. The
#' overall `qc_flag` column is the certified report verdict itself.
#'
#' @param catalog An [MsCatalog] in the SBS96 channel space.
#'
#' @return An `MsQcSentries` data.frame, one row per sample, columns in
#'   the frozen order `sample`, `gt_share`, `ct_share`, `gt_verdict`,
#'   `ct_verdict`, `qc_flag`.
#'
#' @references
#' Design memo `docs/devlog/2026-10-04-M4-02b-qc-memo.md` section 1
#' (mechanism labels, verified against the Excerno/FFPEsig records) and
#' section 3 (frozen shares and the declared flag constants). oxoG:
#' Costello et al., NAR 2013 (doi:10.1093/nar/gks1443); FFPE deamination:
#' Guo et al., Nat Commun 2022 (doi:10.1038/s41467-022-32041-5).
#' Computation core `R/ms-qc-report.R` (.ms_qc_gt_channels,
#' .ms_qc_ct_channels, .ms_qc_shares, .ms_qc_defaults, .ms_qc_flag).
#'
#' @export
ms_qc_sentries <- function(catalog) {
  core <- .ms_qc_surface_core(catalog)
  sh <- core$shares
  out <- data.frame(
    sample = catalog@samples,
    gt_share = sh$gt_share,
    ct_share = sh$ct_share,
    gt_verdict = .ms_qc_verdict(sh$gt_share,
      .ms_qc_defaults$gt_share_flag, "hit"),
    ct_verdict = .ms_qc_verdict(sh$ct_share,
      .ms_qc_defaults$ct_share_watch, "watch"),
    qc_flag = .ms_qc_flag(rep(NA_real_, core$n_samples),
      sh$gt_share, sh$ct_share, core$burden_class),
    stringsAsFactors = FALSE
  )
  attr(out, "genome") <- core$genome
  class(out) <- c("MsQcSentries", "data.frame")
  out
}

#' Print a gt/ct sentries table
#'
#' @param x An `MsQcSentries` as returned by [ms_qc_sentries()].
#' @param ... Further arguments (unused; compatibility with the generic).
#' @return `x`, invisibly.
#' @export
print.MsQcSentries <- function(x, ...) {
  .ms_qc_print_surface("msuiter QC sentries", x,
    sprintf("genome=%s  samples=%d  gt_share_flag=%s  ct_share_watch=%s",
      .ms_qc_attr_or(x, "genome"), nrow(x),
      format(.ms_qc_defaults$gt_share_flag),
      format(.ms_qc_defaults$ct_share_watch)))
}

# --- 3. the certified channel roster of the two mechanisms -------------------

#' The SBS96 mechanism-channel roster
#'
#' The channel membership of the two certified mechanism sentinels: the
#' 16 C>A channels carrying the oxoG reading and the 16 C>T channels
#' carrying the FFPE deamination reading, exactly as the certified channel
#' helpers derive them from the SBS96 registry. This is the channel side
#' of the sentries surface -- which specific channels a per-sample
#' sentinel share counts.
#'
#' @return An `MsQcMechanismChannels` data.frame of 32 rows in SBS96
#'   registry order, columns in the frozen order `label`, `mechanism`
#'   ("oxoG" / "ffpe"), `citation`.
#'
#' @references
#' Design memo `docs/devlog/2026-10-04-M4-02b-qc-memo.md` section 1 and
#' section 3 (the two mechanism families); computation core
#' `R/ms-qc-report.R` (.ms_qc_gt_channels / .ms_qc_ct_channels and their
#' header note on the pyrimidine view). oxoG: Costello et al., NAR 2013
#' (doi:10.1093/nar/gks1443); FFPE: Guo et al., Nat Commun 2022
#' (doi:10.1038/s41467-022-32041-5).
#'
#' @export
ms_qc_mechanism_channels <- function() {
  labels <- as.character(.ms_io_channel_tables()$SBS96)
  gtx <- .ms_qc_gt_channels(labels)
  ctx <- .ms_qc_ct_channels(labels)
  hit <- labels %in% c(gtx, ctx)
  lab <- labels[hit]
  is_gt <- lab %in% gtx
  out <- data.frame(
    label = lab,
    mechanism = ifelse(is_gt, "oxoG", "ffpe"),
    citation = ifelse(is_gt,
      "Costello et al., NAR 2013 (doi:10.1093/nar/gks1443)",
      "Guo et al., Nat Commun 2022 (doi:10.1038/s41467-022-32041-5)"),
    stringsAsFactors = FALSE
  )
  class(out) <- c("MsQcMechanismChannels", "data.frame")
  out
}

#' Print a mechanism-channel roster
#'
#' @param x An `MsQcMechanismChannels` as returned by
#'   [ms_qc_mechanism_channels()].
#' @param ... Further arguments (unused; compatibility with the generic).
#' @return `x`, invisibly.
#' @export
print.MsQcMechanismChannels <- function(x, ...) {
  .ms_qc_print_surface("msuiter QC mechanism channels", x,
    sprintf("SBS96  oxoG=%d  ffpe=%d",
      sum(x$mechanism == "oxoG"), sum(x$mechanism == "ffpe")))
}

# --- 4. the COSMIC artifact roster surface -----------------------------------

#' The cataloged COSMIC artifact roster
#'
#' The 19 COSMIC signatures whose aetiology is "Artefact" (SBS27, SBS43,
#' SBS45-SBS60, SBS95), verified verbatim against the COSMIC SBS index
#' page on 2026-10-04 and pinned by test literal: the roster the
#' artifact-share surfaces count against.
#'
#' @return An `MsQcArtifactRoster` data.frame of 19 rows in the pinned
#'   enumeration order, one column `name`.
#'
#' @references
#' Design memo `docs/devlog/2026-10-04-M4-02b-qc-memo.md` section 1
#' (the live-verified 19-entry enumeration; the page prose said "20
#' total" -- the enumeration is the pin); roster constant
#' `R/ms-qc-report.R` (.ms_qc_artifact_sbs); literal pin
#' `tests/testthat/test-ms-qc-report.R` (the roster-pinned unit).
#' COSMIC: cancer.sanger.ac.uk/cosmic/signatures/SBS.
#'
#' @export
ms_qc_artifact_roster <- function() {
  out <- data.frame(name = .ms_qc_artifact_sbs, stringsAsFactors = FALSE)
  class(out) <- c("MsQcArtifactRoster", "data.frame")
  out
}

#' Print an artifact roster
#'
#' @param x An `MsQcArtifactRoster` as returned by [ms_qc_artifact_roster()].
#' @param ... Further arguments (unused; compatibility with the generic).
#' @return `x`, invisibly.
#' @export
print.MsQcArtifactRoster <- function(x, ...) {
  .ms_qc_print_surface("msuiter QC artifact roster", x,
    sprintf("%d COSMIC Artefact signatures (2026-10-04 verification)",
      nrow(x)))
}

# --- 5. the artifact-roster exposure share surface ----------------------------

#' Per-sample artifact-roster exposure share
#'
#' The certified artifact-share face of the QC report as its own
#' addressable surface: per sample the share of the fitted exposure
#' carried by the cataloged COSMIC artifact roster (sum of the
#' roster-signed exposures over the dictionary total, the memo section 3
#' share formula), the positively loaded roster names, the shared
#' denominator, and the frozen `artifact_share_flag` verdict clause
#' ("hit" at `artifact_share >= artifact_share_flag`, "na" when the
#' share is NA). The computation delegates to the same certified block
#' [ms_qc_report()] uses, including the full label-protocol validation
#' (exposure row labels must equal the signature column labels -- labels
#' are the only legal matching key, never position).
#'
#' @param catalog An [MsCatalog] in the SBS96 channel space.
#' @param signatures A signature matrix (m x k) in the catalog's SBS96
#'   channel space; required here (this surface has no NA-only mode --
#'   use [ms_qc_report()] for the optional share block).
#' @param exposures A k x n count-scale exposure matrix matching
#'   `signatures` and the catalog's samples; required.
#'
#' @return An `MsQcRosterShare` data.frame, one row per sample, columns
#'   in the frozen order `sample`, `exposure_total`, `artifact_share`,
#'   `artifact_sigs`, `artifact_flag`.
#'
#' @references
#' Design memo `docs/devlog/2026-10-04-M4-02b-qc-memo.md` section 1
#' (roster) and section 3 (share formula and the declared flag);
#' computation core `R/ms-qc-report.R` (.ms_qc_roster_block: the
#' certified validation face and share loop, and .ms_qc_defaults).
#'
#' @export
ms_qc_roster_share <- function(catalog, signatures, exposures) {
  .ms_qc_check_catalog(catalog)
  # missing() first: is.null() on an argument with no call value would
  # itself error with "argument is missing" instead of speaking the
  # structured clause.
  sig_given <- !missing(signatures) && !is.null(signatures)
  exp_given <- !missing(exposures) && !is.null(exposures)
  if (!sig_given || !exp_given) {
    msuiter_abort(
      "input",
      "ms_qc_roster_share() requires the fitted signatures and exposures",
      i = "the roster share is computed against a refit in this catalog's channel space",
      j = paste0("signatures: ", if (sig_given) "given" else "missing",
        "; exposures: ", if (exp_given) "given" else "missing"),
      c = "pass the refit pair, or use ms_qc_report() for the optional share block"
    )
  }
  counts <- catalog@counts
  labels <- as.character(catalog@channels$labels)
  plan <- .ms_qc_channel_plan(labels, nrow(counts))
  rb <- .ms_qc_roster_block(counts, labels, nrow(counts),
                            signatures, exposures)
  out <- data.frame(
    sample = catalog@samples,
    exposure_total = rb$total,
    artifact_share = rb$share,
    artifact_sigs = rb$sigs,
    artifact_flag = .ms_qc_verdict(rb$share,
      .ms_qc_defaults$artifact_share_flag, "hit"),
    stringsAsFactors = FALSE
  )
  attr(out, "genome") <- catalog@provenance$genome
  class(out) <- c("MsQcRosterShare", "data.frame")
  out
}

#' Print a roster exposure-share table
#'
#' @param x An `MsQcRosterShare` as returned by [ms_qc_roster_share()].
#' @param ... Further arguments (unused; compatibility with the generic).
#' @return `x`, invisibly.
#' @export
print.MsQcRosterShare <- function(x, ...) {
  .ms_qc_print_surface("msuiter QC roster exposure share", x,
    sprintf("genome=%s  samples=%d  artifact_share_flag=%s",
      .ms_qc_attr_or(x, "genome"), nrow(x),
      format(.ms_qc_defaults$artifact_share_flag)))
}

# --- 6. the provenance checklist ----------------------------------------------

#' The QC provenance checklist
#'
#' The audit checklist the QC report carries (parity plan P4 acceptance:
#' the report carries a provenance checklist): the input class and
#' channel-space facts, the catalog's own provenance keys (the tally /
#' simulator generation params of the house idiom), the bundled reference
#' database pin re-read from the governance manifest, the artifact-roster
#' pin, the declared QC thresholds in force, and the generating package
#' version. Rows speak "pass" / "fail" / "na" ("na" = not recorded for
#' this input, e.g. a hand-built catalog carries no simulation
#' parameters). Unlike the computed surfaces this AUDIT face never aborts
#' on a bad channel space -- it records it as "fail".
#'
#' @param catalog An [MsCatalog].
#'
#' @return An `MsQcProvenance` data.frame, the frozen checklist rows in
#'   the fixed order (`catalog.class`, `channel.space`,
#'   `provenance.genome`, `provenance.keys`, `refdb.pin`, `roster.pin`,
#'   `thresholds.declared`, `msuiter.version`), columns `check`,
#'   `status`, `value`.
#'
#' @references
#' House provenance idiom: `R/classes-catalog.R:218-236` (the
#' catalog@provenance validator), `R/catalog-tally.R:238-250` (the tally
#' key set), `R/ms-simulate.R:157-166` (the simulation generation
#' params), `R/refdb.R:357-373` (the governance manifest, "every field
#' is safe to embed in a provenance record").
#'
#' @export
ms_qc_provenance <- function(catalog) {
  .ms_qc_provenance_rows(catalog)
}

#' Print a provenance checklist
#'
#' @param x An `MsQcProvenance` as returned by [ms_qc_provenance()].
#' @param ... Further arguments (unused; compatibility with the generic).
#' @return `x`, invisibly.
#' @export
print.MsQcProvenance <- function(x, ...) {
  .ms_qc_print_surface("msuiter QC provenance", x,
    sprintf("genome=%s  checks=%d", .ms_qc_attr_or(x, "genome"), nrow(x)))
}
