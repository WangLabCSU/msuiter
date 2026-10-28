# msuiter atlas-mode scenario -- CS-1 law units (03-applications section 1).
# The synthetic cohort is produced by helper-atlas.R's three-layer generator;
# these units adjudicate the pipeline against the A-PRIORI generator truth:
# class ingestion, count contracts, de novo recovery (hungarian recall),
# mixed refit purity (PBR), common/rare classification and the clinical-style
# feature association. No novel metrics: recall/PBR/prevalence are the
# scenario's declared contracts.

.atlas_fx <- function() {
  if (is.null(.GlobalEnv$msuiter_atlas_fixture)) {
    .GlobalEnv$msuiter_atlas_fixture <- .atlas_cohort()
  }
  .GlobalEnv$msuiter_atlas_fixture
}

# Signature matrices arrive channels x k; channel labels are the only legal
# key, so the truth's label order drives the alignment.
.atlas_align <- function(S, labels) S[labels, , drop = FALSE]

.atlas_decocs <- function() {
  refdb <- ms_refdb_bundled(build = "GRCh37")
  roster <- colnames(refdb[["SBS_GRCh37"]]@matrices[[1L]])
  utils::head(setdiff(roster, .ATLAS_PLANTED), 8L)
}

.atlas_variants <- function(fx) {
  ms_variants(fx$variants, genome = "synth", caller = "atlas-synth",
              matched_normal = "none")
}

.atlas_catalog <- function(fx) {
  if (is.null(.GlobalEnv$msuiter_atlas_catalog)) {
    .GlobalEnv$msuiter_atlas_catalog <-
      ms_tally(.atlas_variants(fx), genome = fx$twobit, mode = "SBS96")
  }
  .GlobalEnv$msuiter_atlas_catalog
}

test_that("five variant classes ingest through the public face", {
  fx <- .atlas_fx()
  mv <- .atlas_variants(fx)
  expect_true(S7::S7_inherits(mv, MsVariants))
  expect_identical(nrow(mv@table), nrow(fx$variants))
  # The ID carriers ride the same validator (no public ID83 tally exists).
  with_id <- rbind(fx$variants, fx$id_records)
  mv_id <- ms_variants(with_id, genome = "synth", caller = "atlas-synth",
                       matched_normal = "none")
  expect_identical(nrow(mv_id@table), nrow(with_id))
  expect_false("ID83" %in% msuiter:::.ms_tally_modes)
  cn_path <- file.path(tempdir(), "atlas-cn.tsv")
  write.table(fx$cn_table, cn_path, sep = "\t", quote = FALSE,
              row.names = FALSE, col.names = TRUE)
  segs <- ms_segments(cn_path, caller = "PCAWG")
  expect_identical(nrow(segs), 2L * length(fx$truth$samples))
  expect_true(all(c("chrom", "start", "end", "minor", "major") %in% names(segs)))
  sv <- ms_sv(fx$sv_table)
  expect_identical(nrow(sv), length(fx$truth$samples))
  expect_true("svtype" %in% names(sv))
  expect_true(all(sv$svtype == "deletion"))
})

test_that("count contracts: the tallies equal the emitted plan", {
  fx <- .atlas_fx()
  cat_sbs <- .atlas_catalog(fx)
  expect_true(S7::S7_inherits(cat_sbs, MsCatalog))
  expect_identical(cat_sbs@channels$name, "SBS96")
  expect_identical(cat_sbs@samples, fx$truth$samples)
  expect_identical(dim(cat_sbs@counts),
                   c(length(fx$truth$sbs_labels), length(fx$truth$samples)))
  expect_identical(rowSums(cat_sbs@counts)[fx$truth$sbs_labels],
                   colSums(fx$truth$sbs_plan))
  expect_identical(colSums(cat_sbs@counts)[fx$truth$samples],
                   rowSums(fx$truth$sbs_plan))
  cat_dbs <- ms_tally(.atlas_variants(fx), genome = fx$twobit, mode = "DBS78")
  expect_identical(cat_dbs@channels$name, "DBS78")
  expect_identical(rowSums(cat_dbs@counts)[fx$truth$dbs_labels],
                   colSums(fx$truth$dbs_plan))
  # The cold roster tail must be structurally zero in the DBS plan.
  cold <- setdiff(fx$truth$dbs_labels, fx$truth$dbs_labels[seq_len(12L)])
  expect_true(all(colSums(cat_dbs@counts[cold, , drop = FALSE]) == 0))
})

test_that("QC speaks only the sanctioned vocabularies", {
  fx <- .atlas_fx()
  qc <- ms_qc_report(.atlas_catalog(fx))
  expect_identical(nrow(qc), length(fx$truth$samples))
  expect_true(all(qc$burden_class %in% c("dead", "low", "standard", "high")))
  expect_true(all(qc$qc_flag %in% c("ok", "watch", "artifact")))
})

test_that("de novo extraction recalls every planted signature", {
  fx <- .atlas_fx()
  ex <- ms_extract(.atlas_catalog(fx), k = length(.ATLAS_PLANTED))
  expect_true(S7::S7_inherits(ex, MsSignature))
  S <- .atlas_align(ex@signatures, fx$truth$sbs_labels)
  expect_identical(dim(S), c(length(fx$truth$sbs_labels), length(.ATLAS_PLANTED)))
  refdb <- ms_refdb_bundled(build = "GRCh37")
  mat <- refdb[["SBS_GRCh37"]]@matrices[[1L]]
  truth_mat <- mat[, .ATLAS_PLANTED, drop = FALSE]
  cmp <- ms_compare(estimated = S, reference = truth_mat,
                     protocol = "hungarian", thresholds = 0.8)
  expect_true(S7::S7_inherits(cmp, MsComparison))
  sw <- cmp@hungarian
  expect_true(nrow(sw) == 1L && sw$tau == 0.8)
  expect_identical(sw$recall, 1)
  cls <- attr(sw, "classes")
  matches <- cls[cls$estimated_class == "matched", , drop = FALSE]
  expect_identical(nrow(matches), length(.ATLAS_PLANTED))
  expect_setequal(matches$reference_index, seq_along(.ATLAS_PLANTED))
})

test_that("mixed refit against decoys keeps the planted purity high", {
  fx <- .atlas_fx()
  refdb <- ms_refdb_bundled(build = "GRCh37")
  mat <- refdb[["SBS_GRCh37"]]@matrices[[1L]]
  wide <- mat[, c(.ATLAS_PLANTED, .atlas_decocs()), drop = FALSE]
  fit <- ms_fit(.atlas_catalog(fx), wide, method = "nnls")
  E <- fit@exposures
  planted <- colSums(E[.ATLAS_PLANTED, , drop = FALSE])
  total <- colSums(E)
  pbr <- planted / total
  expect_true(all(total > 0))
  expect_true(all(pbr >= 0.90))
})

test_that("prevalence separates the common and rare legs", {
  fx <- .atlas_fx()
  refdb <- ms_refdb_bundled(build = "GRCh37")
  mat <- refdb[["SBS_GRCh37"]]@matrices[[1L]]
  wide <- mat[, c(.ATLAS_PLANTED, .atlas_decocs()), drop = FALSE]
  fit <- ms_fit(.atlas_catalog(fx), wide, method = "nnls")
  E <- fit@exposures
  prevalence <- rowSums(E > 0) / ncol(E)
  common_hits <- which(prevalence > 0.5)
  expect_true(all(.ATLAS_COMMON %in% names(prevalence)[common_hits]))
  expect_false(any(.ATLAS_RARE %in% names(prevalence)[common_hits]))
  rare_share <- rowSums(E[.ATLAS_RARE, , drop = FALSE] > 0)
  expect_true(all(rare_share <= 3))
})

test_that("the clinical-style feature association finds the planted arm", {
  fx <- .atlas_fx()
  refdb <- ms_refdb_bundled(build = "GRCh37")
  mat <- refdb[["SBS_GRCh37"]]@matrices[[1L]]
  wide <- mat[, c(.ATLAS_PLANTED, .atlas_decocs()), drop = FALSE]
  fit <- ms_fit(.atlas_catalog(fx), wide, method = "nnls")
  tst <- ms_exposure_test(fit@exposures, groups = fx$truth$arm, alpha = 0.05)
  expect_true("pass_bh" %in% names(tst))
  row <- function(sig) tst[tst$signature == sig, , drop = FALSE]
  expect_true(row("SBS5")$pass_bh)
  control <- row(.atlas_decocs()[[1L]])
  expect_false(control$pass_bh)
  expect_true(control$p_raw > 0.05)
})

test_that("the generator is deterministic across rebuilds", {
  a <- .atlas_fx()
  b <- .atlas_cohort(dir = file.path(tempdir(), "msuiter-atlas-fixture-b"))
  expect_identical(a$variants, b$variants)
  expect_identical(a$truth$sbs_plan, b$truth$sbs_plan)
  expect_identical(a$truth$dbs_plan, b$truth$dbs_plan)
})
