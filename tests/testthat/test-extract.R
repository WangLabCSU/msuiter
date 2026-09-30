# ms_extract() single-method extraction end to end (U-M1s-12).
#
# The Rust side pins the kernel plumbing (src/rust/src/extract.rs: bit
# equality with fit_kl on the zero stream, k <= min(m, n) shape rule,
# objective descent). This file replays the acceptance smoke through the
# real FFI and the full R assembly: a separable 96 x 12 truth (ASYMMETRIC
# -- the transposition guard of the t(counts) layout contract) must
# reconstruct to cosine >= 0.99 and assemble into a fully labelled
# MsSignature with the catalog_summary snapshot (A5).

# ---------------------------------------------------------------------------
# Engine factory: ms_nmf() / MsNmf
# ---------------------------------------------------------------------------

test_that("ms_nmf() builds a frozen, registry-compatible spec", {
  .ms_ensure_nmf()
  spec <- ms_nmf()
  expect_is_ms(spec, "MsNmf")
  expect_true(S7::S7_inherits(spec, MsEngine))
  expect_identical(spec@name, "nmf")
  expect_identical(spec@mode, "extract")
  expect_true(spec@deterministic)
  expect_identical(spec@variant, "kl")
  expect_identical(spec@max_iter, 500)
  expect_identical(spec@seed, 1)

  eu <- ms_nmf(engine = "eu", max_iter = 100, seed = 7)
  expect_identical(eu@variant, "eu")
  expect_identical(eu@max_iter, 100)
  expect_identical(eu@seed, 7)
  # format/print show the frozen hyper-parameters
  expect_match(format(eu), "eu")
  expect_match(format(eu), "seed: 7")
  expect_output(print(eu), "MsNmf")
})

test_that("string sugar resolves to the same default spec (A14)", {
  .ms_ensure_nmf()
  expect_identical(match_ms_engine("nmf"), ms_nmf())
  # the registry row is certified: no A17 warning on resolution
  expect_no_warning(match_ms_engine("nmf"))
})

test_that("ms_nmf() rejects bad hyper-parameters with msuiter_error_engine", {
  expect_ms_error(ms_nmf(engine = "hals"), "engine", regexp = "kl")
  expect_ms_error(ms_nmf(max_iter = 0), "engine", regexp = "max_iter")
  expect_ms_error(ms_nmf(max_iter = 2.5), "engine", regexp = "max_iter")
  expect_ms_error(ms_nmf(seed = -1), "engine", regexp = "seed")
  expect_ms_error(ms_nmf(seed = 1.5), "engine", regexp = "seed")
  expect_ms_error(ms_nmf(seed = 2^31), "engine", regexp = "seed")
})

test_that("the package registers 'nmf' as a certified extract engine", {
  .ms_ensure_nmf()
  df <- ms_engines()
  row <- df[df$name == "nmf", ]
  expect_identical(nrow(row), 1L)
  expect_identical(row$mode, "extract")
  expect_identical(row$certified, "certified")
  expect_identical(row$contract_version, "1")
  expect_identical(required_pkgs(ms_nmf()), character(0))
})

# ---------------------------------------------------------------------------
# End-to-end smoke: separable 96 x 12 truth -> MsSignature
# ---------------------------------------------------------------------------

test_that("ms_extract() recovers a separable truth (cosine >= 0.99)", {
  fixture <- .ms_extract_fixture()
  cat1 <- fixture
  sig <- ms_extract(cat1, 3)

  expect_is_ms(sig, "MsSignature")
  # reconstruction gate (the transposition trap: an m<->n handoff cannot
  # pass this on the asymmetric 96 x 12 catalog)
  recon <- sig@signatures %*% sig@exposures
  expect_true(.ms_cos(recon, cat1@counts) >= 0.99)

  # display normalization: W columns on the simplex, exposures rescaled so
  # the per-sample mass is preserved
  expect_true(all(abs(colSums(sig@signatures) - 1) < 1e-9))
  expect_true(all(sig@exposures >= 0))
  mass_ratio <- colSums(sig@exposures) / colSums(cat1@counts)
  expect_true(all(abs(mass_ratio - 1) < 0.05))
})

test_that("MsSignature fields, labels and the catalog snapshot are complete", {
  cat1 <- .ms_extract_fixture()
  # Single-method path: the M1s shape (empty M2 evidence slots).
  sig <- ms_extract(cat1, 3, ms_nmf())

  expect_identical(dim(sig@signatures), c(96L, 3L))
  expect_identical(dim(sig@exposures), c(3L, 12L))
  expect_identical(rownames(sig@signatures), rownames(cat1@counts))
  expect_identical(colnames(sig@signatures), c("Sig1", "Sig2", "Sig3"))
  expect_identical(rownames(sig@exposures), c("Sig1", "Sig2", "Sig3"))
  expect_identical(colnames(sig@exposures), cat1@samples)

  # A5 snapshot summary: exact field set, no catalog embedded
  summary1 <- sig@catalog_summary
  expect_setequal(
    names(summary1),
    c("n_channels", "n_samples", "channel_name", "channel_hash", "build")
  )
  expect_identical(summary1$n_channels, 96L)
  expect_identical(summary1$n_samples, 12L)
  expect_identical(summary1$channel_name, "SYN96")
  expect_identical(summary1$channel_hash, cat1@channels$hash)
  expect_identical(summary1$build, "SYN-true")
  expect_false("counts" %in% names(summary1))

  # method identity + empty M2 evidence slots
  expect_identical(sig@engine, "nmf")
  expect_identical(sig@seed, 1)
  expect_identical(sig@stability, list())
  expect_identical(nrow(sig@k_evidence), 0L)
  expect_match(format(sig), "nmf")
})

test_that("extraction is deterministic across calls (same spec, same bits)", {
  cat1 <- .ms_extract_fixture()
  a <- ms_extract(cat1, 3, ms_nmf())
  b <- ms_extract(cat1, 3, ms_nmf())
  expect_identical(a, b)
})

test_that("string sugar and spec object agree; NULL is the D16 pipeline default", {
  cat1 <- .ms_extract_fixture()
  by_string <- ms_extract(cat1, 3, "nmf")
  by_object <- ms_extract(cat1, 3, ms_nmf())
  expect_identical(by_string, by_object)
  # method = NULL is the U-M2-03 consensus-CV pipeline (a different path,
  # a different engine label -- never silently re-resolved to the single
  # method).
  by_default <- suppressWarnings(ms_extract(cat1, 3))
  expect_false(identical(by_default, by_string))
  expect_identical(by_default@engine, "nmf-pipeline")
  expect_true(length(by_default@stability) > 0L)
  expect_identical(nrow(by_default@k_evidence), 1L)
})

test_that("the eu variant runs on the same face and differs from kl", {
  cat1 <- .ms_extract_fixture()
  kl <- ms_extract(cat1, 3, ms_nmf(engine = "kl", max_iter = 300, seed = 7))
  eu <- ms_extract(cat1, 3, ms_nmf(engine = "eu", max_iter = 300, seed = 7))
  expect_identical(eu@engine, "nmf")
  expect_identical(eu@seed, 7)
  expect_false(identical(kl, eu))
  # deterministic on its own terms
  expect_identical(eu, ms_extract(cat1, 3, ms_nmf(engine = "eu", max_iter = 300, seed = 7)))
})

test_that("k at the min(channels, samples) boundary is legal", {
  cat1 <- .ms_extract_fixture()
  sig <- ms_extract(cat1, 12, ms_nmf(max_iter = 100))
  expect_identical(dim(sig@signatures), c(96L, 12L))
  expect_identical(dim(sig@exposures), c(12L, 12L))
})

test_that("fit_engine() exposes the raw kernel factors to the registry", {
  cat1 <- .ms_extract_fixture()
  raw <- fit_engine(ms_nmf(max_iter = 20), catalog = cat1, k = 3)
  expect_setequal(names(raw), c("signatures", "exposures", "objective", "iterations"))
  expect_identical(dim(raw$signatures), c(96L, 3L)) # channels x signatures
  expect_identical(dim(raw$exposures), c(3L, 12L)) # signatures x samples
  expect_length(raw$objective, 21L) # max_iter + 1 trace entries
  expect_identical(raw$iterations, 20L)
  # raw factors: no labels yet (assembly is ms_extract()'s job)
  expect_null(colnames(raw$signatures))
})

# ---------------------------------------------------------------------------
# Error paths
# ---------------------------------------------------------------------------

test_that("rank k is validated with structured input errors", {
  cat1 <- .ms_extract_fixture()
  expect_ms_error(ms_extract(cat1, 13), "input", regexp = "min\\(channels, samples\\)")
  expect_ms_error(ms_extract(cat1, 0), "input", regexp = "k must be")
  expect_ms_error(ms_extract(cat1, 2.5), "input", regexp = "k must be")
  expect_ms_error(ms_extract(cat1, "3"), "input", regexp = "k must be")
  expect_ms_error(ms_extract(cat1, NA_integer_), "input", regexp = "k must be")
})

test_that("non-catalog input falls back to a structured input error", {
  expect_ms_error(ms_extract(data.frame(), 1), "input", regexp = "MsCatalog")
})

test_that("method resolution errors list the available engines (A14)", {
  .ms_ensure_nmf()
  cat1 <- .ms_extract_fixture()
  cnd <- expect_ms_error(ms_extract(cat1, 3, "nope"), "registry")
  expect_match(conditionMessage(cnd), "nmf", fixed = TRUE)
  expect_ms_error(ms_extract(cat1, 3, 1), "registry")
  expect_ms_error(ms_extract(cat1, 3, c("nmf", "nmf")), "registry")
})

test_that("fit-mode engines are rejected at the extract boundary", {
  .ms_ensure_nmf()
  cat1 <- .ms_extract_fixture()
  # register a synthetic fit-mode engine (third-party pattern, unique name)
  cls <- S7::new_class(
    "SynthFitEngine_m1s", package = "msuiter.test", parent = MsEngine,
    properties = list(
      name = S7::new_property(S7::class_character, default = "synthfit_m1s"),
      mode = S7::new_property(S7::class_character, default = "fit"),
      deterministic = S7::new_property(S7::class_logical, default = TRUE)
    )
  )
  register_ms_engine(
    name = "synthfit_m1s", mode = "fit", engine_class = cls,
    fit_fn = function(engine, ...) NULL, packages = character(0),
    tags = character(0), engine_version = "0.1.0", contract_version = "1",
    certified = "certified"
  )
  expect_ms_error(
    ms_extract(cat1, 3, "synthfit_m1s"),
    "input",
    regexp = "mode must be 'extract'"
  )
})

test_that("dots are rejected as argument-spelling errors", {
  cat1 <- .ms_extract_fixture()
  expect_ms_error(ms_extract(cat1, 3, foo = 1), "input", regexp = "unknown argument")
})

test_that("a degenerate all-zero catalog fails the single fit with a signature error", {
  .ms_ensure_nmf()
  labels <- sprintf("CH%03d", seq_len(96L))
  samples <- sprintf("T%02d", seq_len(12L))
  counts <- matrix(0, 96L, 12L, dimnames = list(labels, samples))
  zero <- ms_catalog(
    counts = counts,
    channels = list(name = "SYN96", labels = labels),
    samples = samples,
    provenance = list(genome = "SYN-true")
  )
  expect_ms_error(ms_extract(zero, 3, ms_nmf(max_iter = 20)), "signature", regexp = "degenerated")
  # The default pipeline path fails the same display-normalization gate on
  # the same degenerate input (the min.value floor imputation lets the kernel
  # finish, but every consensus column has zero mass) -- the structured
  # signature error, never a panic and never partial output.
  expect_ms_error(ms_extract(zero, 3), "signature", regexp = "degenerated")
})

test_that("kernel-level content errors surface as msuiter_error_rust", {
  .ms_ensure_nmf()
  cat1 <- .ms_extract_fixture()
  bad <- cat1@counts
  bad[4, 7] <- -1 # negative entry: passes the R matrix validator by design
  cnd <- tryCatch(
    {
      .ms_extract_rust(bad, k = 3, max_iter = 5, seed = 1)
      NULL
    },
    error = function(e) e
  )
  expect_s3_class(cnd, "msuiter_error_rust")
  expect_identical(cnd$topic, "argument")
  expect_identical(cnd$i, 4L) # channel row (V is row-major m x n)
  expect_identical(cnd$j, 7L) # sample column
})

test_that("the FFI wrapper validates scalars before crossing the boundary", {
  cat1 <- .ms_extract_fixture()
  counts <- cat1@counts
  expect_error(.ms_extract_rust(counts, k = 0, max_iter = 5, seed = 1),
    class = "msuiter_error_input"
  )
  expect_error(.ms_extract_rust(counts, k = 3, max_iter = -1, seed = 1),
    class = "msuiter_error_input"
  )
  expect_error(.ms_extract_rust(counts, k = 3, max_iter = 5, seed = 2^31),
    class = "msuiter_error_input"
  )
  expect_error(.ms_extract_rust(counts * NA_real_, k = 3, max_iter = 5, seed = 1),
    class = "msuiter_error_na"
  )
})
