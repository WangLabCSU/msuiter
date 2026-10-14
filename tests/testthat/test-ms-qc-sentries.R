# test-ms-qc-sentries.R -- the P4 QC sentries surfaces (parity plan P4 row).
#
# Exposure, not invention: every surface here must agree with the certified
# ms_qc_report() computation column-for-column (delegation identity checks),
# the verdicts are the frozen .ms_qc_defaults clauses spoken per-mechanism
# (docs/devlog/2026-10-04-M4-02b-qc-memo.md section 3-4), and the artifact
# roster is the 19-entry COSMIC enumeration pinned by test literal. Fixtures
# are synthetic only (D3): hand-built catalogs and the house ms_simulate()
# with pinned seeds; injections spike known artifact-roster channels and
# gt-like pattern matrices.
#
# Acceptance (lane card): injected-artifact recall = 1 per family; the FP
# ceiling is MEASURED on the clean synthetic cohorts and pinned here (the
# measurement script is tools-side logging, /tmp/p4lane); the provenance
# checklist is asserted present, complete and delegation-backed.

# --- fixtures ----------------------------------------------------------------

.p4_labels <- function() msuiter:::.ms_io_channel_tables()$SBS96

.p4_gt_idx <- function() which(grepl("C>A", .p4_labels(), fixed = TRUE))
.p4_ct_idx <- function() which(grepl("C>T", .p4_labels(), fixed = TRUE))

# Clean non-artifact dictionary: three shapes whose mass avoids the two
# guarded channel families (C>A / C>T stay <= 0.25 of every column), so a
# sentinel hit on the clean cohort is a genuine false positive. Names are
# real COSMIC references that are NOT on the artifact roster (SBS30/36/18
# lesson, memo section 1 -- and none here is SBS27/43/45-60/95).
.p4_clean_sigs <- function() {
  labels <- .p4_labels()
  fam <- sub("^[ACGT]\\[([AC]>[ACGT])\\][ACGT]$", "\\1", labels)
  base <- rep(1, 96)
  sig <- function(mults) {
    v <- base
    for (f in names(mults)) v[fam == f] <- mults[[f]]
    v / sum(v)
  }
  m <- cbind(
    sig(c("C>A" = 3, "C>G" = 3, "C>T" = 3, "T>A" = 3, "T>C" = 3, "T>G" = 3)),
    sig(c("C>G" = 6)),   # C>G-heavy: guarded families stay at the floor share
    sig(c("T>G" = 6))
  )
  dimnames(m) <- list(labels, c("SBS1", "SBS5", "SBS13"))
  m
}

# 12 clean samples: twelve pinned share-profile columns (each sums to 1,
# so every sample lands at the standard burden 1200), pinned seed
# (D3: house simulator, multinomial arm conserves the total exactly).
.p4_clean_catalog <- function() {
  pats <- rbind(
    c(1, 0, 0), c(0, 1, 0), c(0, 0, 1), c(1 / 3, 1 / 3, 1 / 3),
    c(0.8, 0.1, 0.1), c(0.1, 0.8, 0.1), c(0.1, 0.1, 0.8),
    c(0.5, 0.5, 0), c(0.5, 0, 0.5), c(0, 0.5, 0.5),
    c(0.6, 0.2, 0.2), c(0.2, 0.6, 0.2)
  )
  ms_simulate(.p4_clean_sigs(), t(pats),
    arm = "multinomial", burden = 1200, seed = 4242L)
}

# The roster-injection dictionary: two real shapes + roster-named columns,
# one plain (SBS43) and one suffixed (SBS45b -- exercises the stem match).
.p4_roster_sigs <- function() {
  labels <- .p4_labels()
  m <- matrix(0, nrow = 96, ncol = 4, dimnames = list(labels,
    c("SBS1", "SBS5", "SBS43", "SBS45b")))
  fam <- sub("^[ACGT]\\[([AC]>[ACGT])\\][ACGT]$", "\\1", labels)
  m[fam == "C>G", 1] <- 6
  m[fam == "T>G", 2] <- 6
  m[fam == "C>A", 3] <- 6   # roster signature shape
  m[fam == "T>A", 4] <- 6   # roster signature shape (stem SBS45)
  sweep(m, 2L, colSums(m), "/")
}

# Exposures: samples 1-6 carry roster shares >= 0.05 (injected);
# samples 7-10 carry 0.02 (sub-threshold controls); 11-12 carry zero.
.p4_roster_exposures <- function() {
  roster_share <- c(0.50, 0.25, 0.10, 0.06, 0.055, 0.05,
                    0.02, 0.02, 0.02, 0.02, 0, 0)
  other <- 1 - roster_share
  rbind(
    SBS1 = other * 0.6, SBS5 = other * 0.4,
    SBS43 = roster_share * 0.6, `SBS45b` = roster_share * 0.4
  )
}

# Control-only exposures for the clean-cohort FP-ceiling unit: every one
# of the twelve samples carries the SUB-THRESHOLD roster share (0.02,
# far below the frozen 0.05 line), so a roster hit on this fixture is a
# genuine false positive -- measuring the ceiling, not flattering it.
.p4_roster_exposures_control <- function() {
  ctl <- rep(0.02, 12L)
  other <- 1 - ctl
  rbind(
    SBS1 = other * 0.6, SBS5 = other * 0.4,
    SBS43 = ctl * 0.6, `SBS45b` = ctl * 0.4
  )
}

# Hand-spiked sentinel catalogs over the clean simulated counts: samples
# 1-6 get C>A mass (oxoG-like), 7-12 get C>T mass (FFPE-like). Multinomial
# conserved the totals at 1200, so a +1600 spike on the 16 family channels
# drives the family share to roughly (g + 1600)/2800 >= 0.5 -- far above
# the frozen 0.30 / 0.40 lines.
.p4_spiked_catalog <- function() {
  cat1 <- .p4_clean_catalog()
  counts <- cat1@counts
  gt <- .p4_gt_idx()
  ct <- .p4_ct_idx()
  for (j in 1:6) counts[gt, j] <- counts[gt, j] + 100L
  for (j in 7:12) counts[ct, j] <- counts[ct, j] + 100L
  prov <- cat1@provenance
  prov$injected <- "p4-spike"
  ms_catalog(counts, cat1@channels, cat1@samples, provenance = prov)
}

# --- surface shapes -----------------------------------------------------------

test_that("the roster and channel-roster surfaces expose the certified constants", {
  ros <- ms_qc_artifact_roster()
  expect_true(inherits(ros, "MsQcArtifactRoster"))
  expect_identical(names(ros), "name")
  expect_identical(ros$name, msuiter:::.ms_qc_artifact_sbs)
  # The memo section 1 pin: 19 enumerated entries; SBS30/36/18 are real.
  expect_identical(nrow(ros), 19L)
  expect_false(any(c("SBS30", "SBS36", "SBS18") %in% ros$name))

  ch <- ms_qc_mechanism_channels()
  expect_true(inherits(ch, "MsQcMechanismChannels"))
  expect_identical(names(ch), c("label", "mechanism", "citation"))
  expect_identical(nrow(ch), 32L)
  expect_identical(sum(ch$mechanism == "oxoG"), 16L)
  expect_identical(sum(ch$mechanism == "ffpe"), 16L)
  # The delegation: exactly the two certified channel helpers' sets.
  expect_identical(unname(sort(ch$label[ch$mechanism == "oxoG"])),
    sort(msuiter:::.ms_qc_gt_channels(.p4_labels())))
  expect_identical(unname(sort(ch$label[ch$mechanism == "ffpe"])),
    sort(msuiter:::.ms_qc_ct_channels(.p4_labels())))
  # Per-row citations cite the two mechanism papers of the memo section 1.
  expect_true(all(grepl("1093/nar", ch$citation[ch$mechanism == "oxoG"],
    fixed = TRUE)))
  expect_true(all(grepl("1038/s41467", ch$citation[ch$mechanism == "ffpe"],
    fixed = TRUE)))
})

test_that("the burden surface delegates column-for-column to the certified block", {
  cat1 <- .p4_clean_catalog()
  bur <- ms_qc_burden(cat1)
  rep1 <- ms_qc_report(cat1)
  expect_true(inherits(bur, "MsQcBurden"))
  expect_identical(names(bur),
    c("sample", "total", "log10_total", "burden_class"))
  expect_identical(bur$sample, rep1$sample)
  expect_identical(bur$total, rep1$total)
  expect_identical(bur$log10_total, rep1$log10_total)
  expect_identical(bur$burden_class, rep1$burden_class)
  # House-declared classes (memo section 3): the simulated burden 1200 is
  # standard; a dead sample classes dead with an NA log10.
  expect_identical(unique(bur$burden_class), "standard")
  labels <- .p4_labels()
  dead <- ms_catalog(matrix(0L, 96, 1, dimnames = list(labels, "dead1")),
    list(name = "SBS96", labels = labels), "dead1",
    provenance = list(genome = "GRCh37"))
  bur2 <- ms_qc_burden(dead)
  expect_identical(bur2$burden_class, "dead")
  expect_true(is.na(bur2$log10_total))
  # Structured input error on a non-catalog.
  expect_ms_error(ms_qc_burden("junk"), "input")
  # A non-SBS96 space is refused by the certified channel gate.
  labels8 <- sprintf("CH%02d", 1:8)
  cat8 <- ms_catalog(matrix(1, 8, 1, dimnames = list(labels8, "S")),
    list(name = "SYN8", labels = labels8), "S",
    provenance = list(genome = "SYN-true"))
  expect_ms_error(ms_qc_burden(cat8), "input")
})

test_that("the sentries surface speaks the frozen clauses per mechanism", {
  cat1 <- .p4_spiked_catalog()
  sen <- ms_qc_sentries(cat1)
  rep1 <- ms_qc_report(cat1)
  expect_true(inherits(sen, "MsQcSentries"))
  expect_identical(names(sen), c("sample", "gt_share", "ct_share",
    "gt_verdict", "ct_verdict", "qc_flag"))
  # Delegation identity: the shares and the overall flag match the report.
  expect_identical(sen$gt_share, rep1$gt_share)
  expect_identical(sen$ct_share, rep1$ct_share)
  expect_identical(sen$qc_flag, rep1$qc_flag)
  # Verdict vocabulary is exactly the certified clause set.
  expect_true(all(sen$gt_verdict %in% c("ok", "hit", "na")))
  expect_true(all(sen$ct_verdict %in% c("ok", "watch", "na")))
  # Spiked gt samples (1-6) hit the 0.30 line; the clean ones do not.
  expect_identical(sen$gt_verdict, c(rep("hit", 6), rep("ok", 6)))
  expect_identical(sen$ct_verdict, c(rep("ok", 6), rep("watch", 6)))
  # Dead catalog: shares NA speak na verdicts.
  labels <- .p4_labels()
  dead <- ms_catalog(matrix(0L, 96, 1, dimnames = list(labels, "dead1")),
    list(name = "SBS96", labels = labels), "dead1",
    provenance = list(genome = "GRCh37"))
  sen2 <- ms_qc_sentries(dead)
  expect_identical(sen2$gt_verdict, "na")
  expect_identical(sen2$ct_verdict, "na")
  expect_true(is.na(sen2$gt_share) && is.na(sen2$ct_share))
  expect_ms_error(ms_qc_sentries("junk"), "input")
})

test_that("the roster-share surface delegates and flags the certified clause", {
  cat1 <- .p4_clean_catalog()
  sigs <- .p4_roster_sigs()
  expo <- .p4_roster_exposures()
  rs <- ms_qc_roster_share(cat1, sigs, expo)
  rep1 <- ms_qc_report(cat1, signatures = sigs, exposures = expo)
  expect_true(inherits(rs, "MsQcRosterShare"))
  expect_identical(names(rs), c("sample", "exposure_total", "artifact_share",
    "artifact_sigs", "artifact_flag"))
  # Delegation identity against the certified artifact block.
  expect_identical(rs$artifact_share, rep1$artifact_share)
  expect_identical(rs$artifact_sigs, rep1$artifact_sigs)
  # The denominator of the certified share formula (memo section 3).
  expect_identical(rs$exposure_total, unname(colSums(expo)))
  # The frozen artifact_share_flag clause (>= 0.05): the six injected
  # samples speak hit (smallest share is exactly 0.05), the 0.02
  # controls and the zero columns do not.
  expect_identical(rs$artifact_flag,
    c(rep("hit", 6), rep("ok", 4), "ok", "ok"))
  expect_identical(rs$artifact_share[1], 0.5)
  # artifact_sigs lists only positively-loaded roster names (stem match).
  expect_identical(rs$artifact_sigs[1], "SBS43,SBS45b")
  # The certified block names positively loaded roster signatures
  # independently of the flag line: the 0.02 controls speak the names too
  # (this is the names column, not the flag).
  expect_identical(rs$artifact_sigs[7], "SBS43,SBS45b")
  # Only the all-zero-roster samples speak NA names.
  expect_identical(rs$artifact_sigs[11], NA_character_)
  # Error paths: the fit is required (this surface has no NA-only mode),
  # the certified label protocol and shapes stay enforced.
  expect_ms_error(ms_qc_roster_share(cat1), "input")
  expect_ms_error(ms_qc_roster_share(cat1, signatures = sigs), "input")
  expect_ms_error(ms_qc_roster_share(cat1, exposures = expo), "input")
  expect_ms_error(ms_qc_roster_share(cat1, sigs, expo[, 1:5]), "input")
  expect_ms_error(ms_qc_roster_share(cat1, sigs[1:95, ],
    rbind(expo, `X` = rep(0, 12))), "input")
})

test_that("the provenance checklist is complete, audited and delegation-backed", {
  cat1 <- .p4_clean_catalog()
  prov <- ms_qc_provenance(cat1)
  expect_true(inherits(prov, "MsQcProvenance"))
  expect_identical(names(prov), c("check", "status", "value"))
  want_checks <- c("catalog.class", "channel.space", "provenance.genome",
    "provenance.keys", "refdb.pin", "roster.pin", "thresholds.declared",
    "msuiter.version")
  expect_identical(prov$check, want_checks)
  expect_true(all(prov$status %in% c("pass", "fail", "na")))
  # On a well-formed simulated catalog the audit rows all pass ...
  expect_identical(prov$status[prov$check %in%
    c("catalog.class", "channel.space", "provenance.genome",
      "provenance.keys", "refdb.pin", "roster.pin", "thresholds.declared",
      "msuiter.version")],
    rep("pass", 8L))
  # ... with the delegated values, not hardcodes: the refdb pin re-reads
  # the bundled manifest, the thresholds row speaks .ms_qc_defaults.
  mf <- ms_refdb_manifest()
  expect_identical(prov$value[prov$check == "refdb.pin"],
    paste0("v", mf$version, " schema ", mf$schema_version))
  def <- msuiter:::.ms_qc_defaults
  expect_identical(prov$value[prov$check == "thresholds.declared"],
    paste0(names(def), "=", unname(vapply(def, format, character(1))),
      collapse = ", "))
  # Generation params of the house simulator (card: inputs + pin + params).
  expect_true(grepl("seed=4242", prov$value[prov$check == "provenance.keys"],
    fixed = TRUE))
  expect_true(grepl("arm=multinomial",
    prov$value[prov$check == "provenance.keys"], fixed = TRUE))
  # Hand-built catalogs legitimately record no generation params -> "na".
  labels <- .p4_labels()
  hand <- ms_catalog(matrix(1L, 96, 1, dimnames = list(labels, "s1")),
    list(name = "SBS96", labels = labels), "s1",
    provenance = list(genome = "GRCh37"))
  prov2 <- ms_qc_provenance(hand)
  expect_identical(prov2$status[prov2$check == "provenance.keys"], "na")
  # The auditor does not abort on a broken channel space: it reports fail.
  labels8 <- sprintf("CH%02d", 1:8)
  cat8 <- ms_catalog(matrix(1, 8, 1, dimnames = list(labels8, "S")),
    list(name = "SYN8", labels = labels8), "S",
    provenance = list(genome = "SYN-true"))
  prov3 <- ms_qc_provenance(cat8)
  expect_identical(prov3$status[prov3$check == "channel.space"], "fail")
  expect_ms_error(ms_qc_provenance("junk"), "input")
  # The report carries the checklist (plan acceptance: the report carries
  # a provenance checklist), identical to the standalone surface.
  rep1 <- ms_qc_report(cat1)
  carried <- attr(rep1, "ms_qc_provenance", exact = TRUE)
  expect_true(inherits(carried, "MsQcProvenance"))
  expect_identical(unname(carried), unname(prov))
})

# --- acceptance: recall = 1 and the measured FP ceiling ----------------------

test_that("ACCEPTANCE gt-sentry recall is 1 on injected oxoG-pattern spikes", {
  sen <- ms_qc_sentries(.p4_spiked_catalog())
  # Positions are the canonical index into the certified column order;
  # the sample-name round trip is pinned so the positional choice stays
  # honest (names unique and in catalog order).
  expect_identical(match(sen$sample[1:6], sen$sample), 1:6)
  injected <- 1:6
  hits <- sum(sen$gt_verdict[injected] == "hit")
  cat(sprintf("P4-RECALL gt: %d/%d\n", hits, length(injected)))
  expect_identical(hits / length(injected), 1)
  # The overall artifact flag fires for every injected sample too.
  expect_identical(unique(sen$qc_flag[injected]), "artifact")
})

test_that("ACCEPTANCE ffpe-sentry recall is 1 on injected deamination spikes", {
  sen <- ms_qc_sentries(.p4_spiked_catalog())
  expect_identical(match(sen$sample[7:12], sen$sample), 7:12)
  injected <- 7:12
  hits <- sum(sen$ct_verdict[injected] == "watch")
  cat(sprintf("P4-RECALL ct: %d/%d\n", hits, length(injected)))
  expect_identical(hits / length(injected), 1)
})

test_that("ACCEPTANCE artifact-roster recall is 1 on injected roster exposures", {
  rs <- ms_qc_roster_share(.p4_clean_catalog(), .p4_roster_sigs(),
    .p4_roster_exposures())
  expect_identical(match(rs$sample[1:6], rs$sample), 1:6)
  injected <- 1:6
  hits <- sum(rs$artifact_flag[injected] == "hit")
  cat(sprintf("P4-RECALL roster: %d/%d\n", hits, length(injected)))
  expect_identical(hits / length(injected), 1)
})

test_that("ACCEPTANCE measured false-positive ceiling on clean synthetic cohorts", {
  # Pinned measurement (D3, seed 4242): zero hits on the clean cohorts.
  # The lane card demands the ceiling be measured and documented, not a
  # flattering threshold chosen -- these pins are the documented ceiling
  # (0/12 per family at this fixture scale; thresholds are the frozen
  # house constants, never retuned here).
  sen <- ms_qc_sentries(.p4_clean_catalog())
  fp_gt <- sum(sen$gt_verdict == "hit")
  fp_ct <- sum(sen$ct_verdict == "watch")
  rs <- ms_qc_roster_share(.p4_clean_catalog(), .p4_roster_sigs(),
    .p4_roster_exposures_control())
  fp_roster <- sum(rs$artifact_flag == "hit")
  cat(sprintf("P4-FP gt=%d ct=%d roster=%d (n=12 each)\n",
    fp_gt, fp_ct, fp_roster))
  expect_identical(c(fp_gt, fp_ct, fp_roster), c(0L, 0L, 0L))
  expect_identical(unique(sen$qc_flag), "ok")
})

# --- tidy print methods (house idiom, floor-safe) -----------------------------

test_that("the surfaces print in the house idiom and return invisibly", {
  cat1 <- .p4_clean_catalog()
  expect_output(print(ms_qc_burden(cat1)), "msuiter QC burden", fixed = TRUE)
  expect_invisible(print(ms_qc_burden(cat1)))
  expect_output(print(ms_qc_sentries(cat1)), "msuiter QC sentries", fixed = TRUE)
  expect_invisible(print(ms_qc_sentries(cat1)))
  expect_output(print(ms_qc_mechanism_channels()), "mechanism channel", fixed = TRUE)
  expect_invisible(print(ms_qc_mechanism_channels()))
  expect_output(print(ms_qc_artifact_roster()), "artifact roster", fixed = TRUE)
  expect_invisible(print(ms_qc_artifact_roster()))
  expect_output(print(ms_qc_provenance(cat1)), "QC provenance", fixed = TRUE)
  expect_invisible(print(ms_qc_provenance(cat1)))
  expect_output(
    print(ms_qc_roster_share(cat1, .p4_roster_sigs(), .p4_roster_exposures())),
    "roster exposure share", fixed = TRUE)
})
