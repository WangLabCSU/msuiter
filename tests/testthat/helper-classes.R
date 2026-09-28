# Shared fixtures and assertion helpers for the S7 class skeleton tests
# (U-M0-03). Everything here is synthetic: no BSgenome, no network, no
# dependency on the channel registry shipped by U-M0-05.

# Portable S7 class assertion: S7 objects are S3 objects whose class vector
# starts with "pkg::Class", so expect_s3_class works on any testthat edition.
expect_is_ms <- function(object, class) {
  expect_s3_class(object, sprintf("msuiter::%s", class))
}

# Expect an error of class `msuiter_error_<topic>` whose condition carries the
# i/j/c three-part information payload (ARCHITECTURE.md section 3.5).
expect_ms_error <- function(expr, topic, regexp = NULL) {
  class <- paste0("msuiter_error_", topic)
  cnd <- tryCatch(
    {
      force(expr)
      NULL
    },
    error = function(e) e
  )
  expect_s3_class(cnd, class)
  parts <- cnd$msuiter_error
  expect_false(is.null(parts), info = "condition must carry the i/j/c payload")
  expect_named(parts, c("topic", "i", "j", "c"))
  expect_true(all(vapply(parts, function(p) is.character(p) && nzchar(p), logical(1))))
  if (!is.null(regexp)) {
    expect_match(conditionMessage(cnd), regexp, all = FALSE)
  }
  invisible(cnd)
}

.make_variants_table <- function(n = 5L) {
  base <- data.frame(
    chrom = c("chr1", "chr1", "chr2", "chrX", "chrM"),
    start = c(100, 200, 300, 400, 500),
    end = c(100, 201, 300, 401, 500),
    ref = c("C", "CA", "T", "G", "A"),
    alt = c("T", "C", "A", "C", "G"),
    stringsAsFactors = FALSE
  )
  base[seq_len(min(n, nrow(base))), , drop = FALSE]
}

.make_variants_provenance <- function() {
  list(caller = "synthetic-caller", matched_normal = "none")
}

.make_catalog_labels <- function(n = 6L) {
  sprintf("CH%02d", seq_len(n))
}

.make_counts <- function(labels = .make_catalog_labels(), samples = c("S1", "S2", "S3")) {
  counts <- matrix(
    as.numeric(rep(seq_along(labels), times = length(samples))),
    nrow = length(labels), ncol = length(samples),
    dimnames = list(labels, samples)
  )
  counts[1, 1] <- 0 # make sure zero counts are exercised
  counts
}

.make_catalog_channels <- function(labels = .make_catalog_labels()) {
  list(name = "SYN", labels = labels)
}

.make_catalog <- function() {
  ms_catalog(
    counts = .make_counts(),
    channels = .make_catalog_channels(),
    samples = c("S1", "S2", "S3"),
    provenance = list(genome = "GRCh38", caller = "synthetic-caller")
  )
}

.make_signatures <- function(labels = .make_catalog_labels(), sigs = c("SIG1", "SIG2")) {
  m <- matrix(
    as.numeric(seq_len(length(labels) * length(sigs))),
    nrow = length(labels), ncol = length(sigs),
    dimnames = list(labels, sigs)
  )
  m
}

.make_exposures <- function(sigs = c("SIG1", "SIG2"), samples = c("S1", "S2", "S3")) {
  m <- matrix(
    as.numeric(seq_len(length(sigs) * length(samples))),
    nrow = length(sigs), ncol = length(samples),
    dimnames = list(sigs, samples)
  )
  m
}

.make_signature <- function() {
  catalog <- .make_catalog()
  ms_signature(
    signatures = .make_signatures(),
    exposures = .make_exposures(),
    catalog_summary = msuiter_catalog_summary(catalog),
    engine = "synthetic-engine",
    seed = 1234
  )
}

.make_refdb <- function() {
  labels <- .make_catalog_labels()
  matrices <- list(
    ref_a = matrix(
      as.numeric(seq_len(length(labels) * 2L)),
      nrow = length(labels), ncol = 2L,
      dimnames = list(labels, c("REF1", "REF2"))
    )
  )
  metadata <- list(
    version = "1.0.0",
    class = "SYN",
    build = "GRCh38",
    schema_version = "1",
    sha256 = paste0(rep("a", 64), collapse = ""),
    license = "CC0-1.0",
    build_independent = FALSE,
    availability = c("GRCh37", "GRCh38")
  )
  ms_refdb(matrices = matrices, metadata = metadata)
}

.make_benchmark_results <- function() {
  data.frame(
    .engine = c("e1", "e1", "e2"),
    .scenario = c("sc1", "sc2", "sc1"),
    .metric = c("f1", "f1", "f1"),
    .estimate = c(0.9, 0.8, 0.7),
    stringsAsFactors = FALSE
  )
}

# saveRDS -> readRDS round trip (RDS safety, D12/A5: no handles to reconnect).
.roundtrip <- function(x) {
  path <- tempfile(fileext = ".rds")
  on.exit(unlink(path), add = TRUE)
  saveRDS(x, path)
  readRDS(path)
}
