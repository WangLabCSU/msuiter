# ms_treatment_report() -- the treatment-forensics reporting module
# (Phase-8 CS-3; design memo docs/devlog/2026-10-28-p8-treatment-forensics-
# design.md). Law units: governed dictionary, planted-fidelity association
# with bootstrap CIs, delegation-truthful point columns, clonal/subclonal
# timing split, honest degraded attestation, determinism, error paths.

.ms_trt_expect_err <- function(expr, class) {
  expect_error(expr, class = paste0("msuiter_error_", class))
}

test_that("the governed default map is the frozen trio and rides the refdb", {
  expect_identical(msuiter:::.ms_treatment_exposure_map, .MS_TRT_MAP)
  ref <- colnames(ms_refdb_bundled(build = "GRCh37")$SBS_GRCh37@matrices[[1]])
  missing <- setdiff(unlist(.MS_TRT_MAP, use.names = FALSE), ref)
  expect_identical(missing, character(0))
})

test_that("the report face delivers the pinned table contract", {
  fx <- .ms_trt_cohort()
  rep1 <- ms_treatment_report(fx$catalog, fx$treatments, n_boot = 99, seed = 7)
  expect_s3_class(rep1, "MsTreatmentReport")
  tab <- as.data.frame(rep1)
  expect_s3_class(tab, "data.frame")
  expect_named(tab, c("treatment", "signature", "n_exposed", "n_unexposed",
                      "prevalence_exposed", "prevalence_unexposed",
                      "mean_exposed", "mean_unexposed", "contrast",
                      "contrast_lower", "contrast_upper", "is_associated"))
  expect_identical(nrow(tab), 12L) # three treatments x four governed signatures
  expect_identical(sort(unique(tab$signature)),
                   sort(unique(unlist(.MS_TRT_MAP, use.names = FALSE))))
  expect_setequal(unique(tab$treatment), names(.MS_TRT_MAP))
})

test_that("planted fidelity: exactly the planted cells associate", {
  fx <- .ms_trt_cohort()
  rep1 <- ms_treatment_report(fx$catalog, fx$treatments, n_boot = 99, seed = 7)
  tab <- as.data.frame(rep1)
  truth <- vapply(seq_len(nrow(tab)), function(i)
    fx$planted_truth(tab$treatment[i], tab$signature[i]), logical(1))
  expect_identical(tab$is_associated, truth)
  # CI discipline: bounds bracket the point estimate wherever finite.
  ok <- !is.na(tab$contrast_lower)
  expect_true(all(tab$contrast_lower[ok] <= tab$contrast[ok]))
  expect_true(all(tab$contrast[ok] <= tab$contrast_upper[ok]))
  # Planted cells must separate with margin (a-priori: 600 vs 20 activity).
  planted_rows <- which(truth)
  expect_true(all(tab$contrast_lower[planted_rows] > 50))
})

test_that("point columns delegate truthfully to the public fit face", {
  fx <- .ms_trt_cohort()
  rep1 <- ms_treatment_report(fx$catalog, fx$treatments, n_boot = 20, seed = 7)
  fit <- ms_fit(fx$catalog, fx$dict, method = "nnls")
  tab <- as.data.frame(rep1)
  E <- fit@exposures
  for (i in seq_len(nrow(tab))) {
    idx <- which(fx$samples %in%
                   fx$treatments$sample[!is.na(fx$treatments$treatment) &
                                          fx$treatments$treatment == tab$treatment[i]])
    other <- which(!(fx$samples %in%
                       fx$treatments$sample[!is.na(fx$treatments$treatment)]))
    expect_equal(tab$mean_exposed[i], mean(E[tab$signature[i], idx]),
                 tolerance = 1e-12)
    expect_equal(tab$mean_unexposed[i], mean(E[tab$signature[i], other]),
                 tolerance = 1e-12)
    expect_equal(tab$contrast[i],
                 tab$mean_exposed[i] - tab$mean_unexposed[i], tolerance = 1e-12)
  }
})

test_that("clonality injection splits the activity additively", {
  fx <- .ms_trt_cohort()
  sigs <- sort(unique(unlist(.MS_TRT_MAP, use.names = FALSE)))
  set.seed(11)
  clon <- expand.grid(sample = fx$samples, signature = sigs)
  clon <- clon[c("sample", "signature")]
  clon$clonal_fraction <- runif(nrow(clon), 0.1, 0.9)
  rep1 <- ms_treatment_report(fx$catalog, fx$treatments, clonality = clon,
                              n_boot = 20, seed = 7)
  tim <- attr(rep1, "timing")
  expect_s3_class(tim, "data.frame")
  expect_named(tim, c("treatment", "signature", "n_exposed", "exposure_pre",
                      "exposure_post", "pre_lower", "pre_upper",
                      "post_lower", "post_upper"))
  tab <- as.data.frame(rep1)
  key <- paste(tab$treatment, tab$signature)
  expect_identical(sort(paste(tim$treatment, tim$signature)), sort(key))
  m <- match(paste(tim$treatment, tim$signature), key)
  expect_equal(tim$exposure_pre + tim$exposure_post, tab$mean_exposed[m],
               tolerance = 1e-12)
})

test_that("degraded modes attest instead of fabricating", {
  fx <- .ms_trt_cohort()
  rep1 <- ms_treatment_report(fx$catalog, treatments = NULL, n_boot = 20,
                              seed = 7)
  expect_identical(nrow(as.data.frame(rep1)), 0L)
  att <- attr(rep1, "attestation")
  expect_s3_class(att, "data.frame")
  expect_named(att, c("face", "status", "detail"))
  expect_true(any(att$face == "association" & att$status == "degraded" &
                     grepl("no-treatment-records", att$detail, fixed = TRUE)))
  # No clonality table: the timing face degrades, association stays full.
  rep2 <- ms_treatment_report(fx$catalog, fx$treatments, n_boot = 20, seed = 7)
  att2 <- attr(rep2, "attestation")
  expect_true(any(att2$face == "timing" & att2$status == "degraded" &
                     grepl("no-clonality-records", att2$detail, fixed = TRUE)))
  expect_identical(nrow(attr(rep2, "timing")), 0L)
})

test_that("the print face speaks the provenance, attestation and tables", {
  fx <- .ms_trt_cohort()
  rep1 <- ms_treatment_report(fx$catalog, fx$treatments, n_boot = 20, seed = 7)
  out <- paste(capture.output(print(rep1)), collapse = "\n")
  expect_match(out, "<msuiter treatment report>", fixed = TRUE)
  expect_match(out, "refdb=v3.6", fixed = TRUE)
  expect_match(out, "n_boot=20", fixed = TRUE)
  expect_match(out, "seed=7", fixed = TRUE)
  expect_match(out, "association=full", fixed = TRUE)
  expect_match(out, "timing=degraded", fixed = TRUE)
  expect_match(out, "temozolomide", fixed = TRUE)
  invisible(rep1)
})

test_that("reruns with the same seed are byte-identical", {
  fx <- .ms_trt_cohort()
  a <- ms_treatment_report(fx$catalog, fx$treatments, n_boot = 40, seed = 42)
  b <- ms_treatment_report(fx$catalog, fx$treatments, n_boot = 40, seed = 42)
  expect_identical(as.data.frame(a), as.data.frame(b))
  expect_identical(attr(a, "timing"), attr(b, "timing"))
  expect_identical(attr(a, "provenance"), attr(b, "provenance"))
  c <- ms_treatment_report(fx$catalog, fx$treatments, n_boot = 40, seed = 43)
  expect_false(identical(as.data.frame(a)$contrast_lower,
                         as.data.frame(c)$contrast_lower))
})

test_that("provenance rides the sealed refdb and the run parameters", {
  fx <- .ms_trt_cohort()
  rep1 <- ms_treatment_report(fx$catalog, fx$treatments, n_boot = 20, seed = 7)
  prov <- attr(rep1, "provenance")
  expect_identical(prov$refdb_version, "v3.6")
  expect_identical(prov$build, "GRCh37")
  expect_identical(prov$method, "nnls")
  expect_identical(prov$n_boot, 20L)
  expect_identical(prov$seed, 7L)
  expect_identical(prov$dictionary,
                   sort(unique(unlist(.MS_TRT_MAP, use.names = FALSE))))
  expect_match(prov$dictionary_sha256, "^[0-9a-f]{64}$")
})

test_that("error paths speak structured conditions", {
  fx <- .ms_trt_cohort()
  .ms_trt_expect_err(ms_treatment_report("junk", fx$treatments), "input")
  .ms_trt_expect_err(
    ms_treatment_report(fx$catalog, data.frame(sample = "NOPE",
                                               treatment = "platinum")),
    "input")
  .ms_trt_expect_err(
    ms_treatment_report(fx$catalog,
                        data.frame(sample = fx$samples[1], treatment = "radiotherapy")),
    "input")
  # SBS40 is not a bundled label (the bundle carries SBS40a/b/c): governance
  # must fail closed against the refdb roster.
  .ms_trt_expect_err(
    ms_treatment_report(fx$catalog, fx$treatments,
                        exposure_map = list(mydrug = "SBS40")),
    "refdb")
  .ms_trt_expect_err(ms_treatment_report(fx$catalog, fx$treatments, build = "hg38"),
                     "refdb")
  .ms_trt_expect_err(ms_treatment_report(fx$catalog, fx$treatments, n_boot = 0),
                     "input")
  .ms_trt_expect_err(ms_treatment_report(fx$catalog, fx$treatments, seed = -1),
                     "input")
})

test_that("clonality validation is fail-closed", {
  fx <- .ms_trt_cohort()
  sigs <- sort(unique(unlist(.MS_TRT_MAP, use.names = FALSE)))
  clon <- expand.grid(sample = fx$samples, signature = sigs)
  clon <- clon[c("sample", "signature")]
  bad <- clon
  bad$clonal_fraction <- 1.5
  .ms_trt_expect_err(
    ms_treatment_report(fx$catalog, fx$treatments, clonality = bad,
                        n_boot = 10), "input")
  clon$clonal_fraction <- 0.5
  .ms_trt_expect_err(
    ms_treatment_report(fx$catalog, fx$treatments,
                        clonality = clon[-1L, , drop = FALSE], n_boot = 10),
    "input")
})

test_that("a full-clonality cohort puts the whole activity pre-treatment", {
  fx <- .ms_trt_cohort()
  sigs <- sort(unique(unlist(.MS_TRT_MAP, use.names = FALSE)))
  clon <- expand.grid(sample = fx$samples, signature = sigs)
  clon <- clon[c("sample", "signature")]
  clon$clonal_fraction <- 1
  rep1 <- ms_treatment_report(fx$catalog, fx$treatments, clonality = clon,
                              n_boot = 20, seed = 7)
  tim <- attr(rep1, "timing")
  tab <- as.data.frame(rep1)
  m <- match(paste(tim$treatment, tim$signature), paste(tab$treatment, tab$signature))
  expect_equal(tim$exposure_pre, tab$mean_exposed[m], tolerance = 1e-12)
  expect_equal(tim$exposure_post, rep(0, nrow(tim)), tolerance = 1e-12)
})
