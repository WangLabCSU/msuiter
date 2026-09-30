# io layer: ms_segments() caller mappings + validated direct construction
# (M1c input-layer wiring). The column-mapping gold standard is SPMG
# CNVMatrixGenerator.py at master edccbea6; the per-branch anchors cited
# below live in R/io-segments.R. All fixtures are self-made with
# writeLines into the session temp dir -- no committed binary fixtures,
# no network.

# One-row tabular fixture builder: header + single data line.
.seg_fixture <- function(header, row, ext = ".tsv", gz = FALSE) {
  .io_write_fixture(c(header, row), ext, gz)
}

# ---------------------------------------------------------------------
# Per-caller mappings (caller = "auto" everywhere: the signatures are
# part of the contract)
# ---------------------------------------------------------------------

test_that("ASCAT maps nMajor/nMinor onto the ordered typed pair", {
  path <- .seg_fixture(
    "sample\tchr\tstartpos\tendpos\tnMajor\tnMinor",
    "TUMOR1\tchr7\t100000\t9000000\t3\t1"
  )
  on.exit(unlink(path))
  seg <- ms_segments(path)
  expect_identical(names(seg), c("sample", "chrom", "start", "end", "minor", "major"))
  expect_identical(seg$sample, "TUMOR1")
  expect_identical(seg$chrom, "chr7") # verbatim passthrough
  expect_identical(seg$start, 100000)
  expect_identical(seg$end, 9000000)
  expect_identical(seg$minor, 1L) # declared roles, validated not reordered
  expect_identical(seg$major, 3L)
  prov <- attr(seg, "provenance")
  expect_identical(prov$caller, "ASCAT")
  expect_identical(prov$source, path)
  expect_identical(prov$format, "segments")
  expect_identical(prov$parse$n_lines, 1L)
  expect_identical(prov$parse$n_records, 1L)
  expect_identical(prov$parse$n_skipped, 0L)
})

test_that("ASCAT_NGS derives the minor allele from Tumour TCN - Tumour BCN", {
  # SPMA :215-221: Tumour ACN = TCN - BCN; the pair is unordered
  # upstream (zero-test :226-232), so the smaller value becomes minor.
  path <- .seg_fixture(
    paste0(
      "sample\tChromosome\tStart Position\tEnd Position\tNormal TCN\t",
      "Normal BCN\tTumour TCN\tTumour BCN"
    ),
    "TUMOR1\t1\t100\t900\t2\t1\t4\t3"
  )
  on.exit(unlink(path))
  seg <- ms_segments(path)
  expect_identical(attr(seg, "provenance")$caller, "ASCAT_NGS")
  expect_identical(seg$minor, 1L) # acn = 4 - 3 < bcn = 3
  expect_identical(seg$major, 3L)
})

test_that("ABSOLUTE canonicalizes the unordered Modal_HSCN pair", {
  # :117-129, :234-242: upstream only sums and zero-tests the pair.
  path <- .seg_fixture(
    "sample\tChromosome\tStart\tEnd\tModal_HSCN_1\tModal_HSCN_2",
    "TUMOR1\t1\t100\t900\t2\t1"
  )
  on.exit(unlink(path))
  seg <- ms_segments(path)
  expect_identical(attr(seg, "provenance")$caller, "ABSOLUTE")
  expect_identical(seg$minor, 1L)
  expect_identical(seg$major, 2L)
})

test_that("PCAWG derives allele states from copy_number and mutation_type", {
  # :130-141 (total CN), :243-258 (zygosity). The allele split is a
  # documented convention for het rows (minor = 1): it preserves the
  # total CN and the het zygosity, hence the exact CN48 channel.
  header <- paste0(
    "sample\tchromosome\tchromosome_start\tchromosome_end\tcopy_number\t",
    "mutation_type"
  )
  rows <- c(
    c("TUMOR1\t1\t100\t900\t2\tcopy neutral LOH"), # -> (0, 2)
    c("TUMOR1\t1\t100\t900\t0\tloss"), # homdel -> (0, 0)
    c("TUMOR1\t1\t100\t900\t1\tloss"), # LOH -> (0, 1)
    c("TUMOR1\t1\t100\t900\t3\tgain"), # het convention -> (1, 2)
    c("TUMOR1\t1\t100\t900\t2\tcopy neutral"), # -> (1, 1)
    c("TUMOR1\t1\t100\t900\t6\tamp LOH"), # -> (0, 6)
    c("TUMOR1\t1\t100\t900\t1\themizygous del LOH") # -> (0, 1)
  )
  expected_minor <- c(0L, 0L, 0L, 1L, 1L, 0L, 0L)
  expected_major <- c(2L, 0L, 1L, 2L, 1L, 6L, 1L)
  for (i in seq_along(rows)) {
    path <- .seg_fixture(header, rows[i])
    seg <- ms_segments(path)
    expect_identical(attr(seg, "provenance")$caller, "PCAWG")
    expect_identical(seg$minor, expected_minor[i], info = rows[i])
    expect_identical(seg$major, expected_major[i], info = rows[i])
    unlink(path)
  }
})

test_that("PCAWG rows without a faithful upstream mapping are rejected", {
  header <- paste0(
    "sample\tchromosome\tchromosome_start\tchromosome_end\tcopy_number\t",
    "mutation_type"
  )
  # 'loss' with total CN >= 2 desynchronises the upstream LOH list
  # (:255-259, :304); het labels with total CN < 2 would target the
  # nonexistent '1:het' channel; anything else is an unhandled
  # mutation_type.
  bad <- list(
    c("TUMOR1\t1\t100\t900\t3\tloss"),
    c("TUMOR1\t1\t100\t900\t1\tgain"),
    c("TUMOR1\t1\t100\t900\t2\tcomplex")
  )
  for (row in bad) {
    path <- .seg_fixture(header, row)
    expect_ms_error(ms_segments(path), "segments")
    unlink(path)
  }
})

test_that("FACETS maps a missing lcn.em onto the LOH branch", {
  # :262-271: t >= 1 with a missing/NA lcn.em is LOH upstream, so the
  # typed pair carries minor = 0; lcn = 0 is the same pair.
  path <- .seg_fixture(
    "chrom\tstart\tend\ttcn.em\tlcn.em",
    "1\t100\t900\t3\tNA"
  )
  on.exit(unlink(path))
  seg <- ms_segments(path)
  expect_identical(attr(seg, "provenance")$caller, "FACETS")
  expect_identical(seg$minor, 0L)
  expect_identical(seg$major, 3L)
})

test_that("FACETS lcn above half of tcn is rejected", {
  # lcn.em is the LESS-copy allele: lcn > tcn/2 contradicts FACETS'
  # own semantics and cannot be ordered without changing the channel.
  path <- .seg_fixture(
    "chrom\tstart\tend\ttcn.em\tlcn.em",
    "1\t100\t900\t4\t3"
  )
  on.exit(unlink(path))
  expect_ms_error(ms_segments(path), "segments", regexp = "minor copy number")
})

test_that("Battenberg expands clonal and subclonal blocks into records", {
  # :401-425: both blocks tally as separate events; a block with
  # missing values is dropped upstream (dropna, :404-405) and counted
  # into the ledger here (A11).
  path <- .io_write_fixture(
    c(
      paste0(
        "sample\tchr\tstartpos\tendpos\tnMaj1_A\tnMin1_A\t",
        "nMaj2_A\tnMin2_A"
      ),
      "TUMOR1\t1\t100\t900\t1\t1\t2\t0", # clonal + subclonal -> 2 records
      "TUMOR1\t2\t200\t950\t2\t1\tNA\tNA" # clonal only -> 1 record
    ),
    ".tsv"
  )
  on.exit(unlink(path))
  seg <- ms_segments(path)
  expect_identical(nrow(seg), 3L)
  expect_identical(seg$chrom, c("1", "2", "1"))
  expect_identical(seg$start, c(100, 200, 100))
  expect_identical(seg$end, c(900, 950, 900))
  expect_identical(seg$minor, c(1L, 1L, 0L))
  expect_identical(seg$major, c(1L, 2L, 2L))
  prov <- attr(seg, "provenance")
  expect_identical(prov$parse$n_lines, 2L)
  expect_identical(prov$parse$n_records, 3L)
  expect_identical(prov$parse$n_expanded, 1L)
  expect_identical(prov$parse$n_skipped, 1L)
  expect_identical(names(prov$parse$skip_reasons), "missing_cn_block")
  expect_identical(as.integer(prov$parse$skip_reasons), 1L)
})

test_that("Battenberg without subclonal columns emits one record per row", {
  path <- .seg_fixture(
    "sample\tchr\tstartpos\tendpos\tnMaj1_A\tnMin1_A",
    "TUMOR1\t19\t90407080\t91002641\t1\t0"
  )
  on.exit(unlink(path))
  seg <- ms_segments(path)
  expect_identical(nrow(seg), 1L)
  expect_identical(seg$minor, 0L)
  expect_identical(seg$major, 1L)
  expect_identical(attr(seg, "provenance")$parse$n_expanded, 0L)
})

test_that("PURPLE validates the declared allele roles", {
  good <- .seg_fixture(
    "chromosome\tstart\tend\tminorAlleleCopyNumber\tmajorAlleleCopyNumber",
    "1\t100\t900\t1\t3"
  )
  on.exit(unlink(good))
  seg <- ms_segments(good)
  expect_identical(attr(seg, "provenance")$caller, "PURPLE")
  expect_identical(seg$minor, 1L)
  expect_identical(seg$major, 3L)

  # Declared roles with minor > major are rejected, not reordered.
  bad <- .seg_fixture(
    "chromosome\tstart\tend\tminorAlleleCopyNumber\tmajorAlleleCopyNumber",
    "1\t100\t900\t3\t1"
  )
  on.exit(unlink(bad), add = TRUE)
  expect_ms_error(ms_segments(bad), "segments", regexp = "minor copy number")
})

test_that("SEQUENZA requires A + B == CNt and orders the pair", {
  good <- .seg_fixture(
    "chromosome\tstart.pos\tend.pos\tCNt\tA\tB",
    "1\t100\t900\t3\t1\t2"
  )
  on.exit(unlink(good))
  seg <- ms_segments(good)
  expect_identical(attr(seg, "provenance")$caller, "SEQUENZA")
  expect_identical(seg$minor, 1L)
  expect_identical(seg$major, 2L)

  bad <- .seg_fixture(
    "chromosome\tstart.pos\tend.pos\tCNt\tA\tB",
    "1\t100\t900\t5\t1\t2"
  )
  on.exit(unlink(bad), add = TRUE)
  expect_ms_error(ms_segments(bad), "io", regexp = "A \\+ B")
})

test_that("auto-detection resolves each caller from its column signature", {
  fixtures <- list(
    ASCAT = c("sample\tchr\tstartpos\tendpos\tnMajor\tnMinor", "T\t1\t1\t2\t1\t1"),
    ASCAT_NGS = c(
      paste0(
        "sample\tChromosome\tStart Position\tEnd Position\tNormal TCN\t",
        "Normal BCN\tTumour TCN\tTumour BCN"
      ),
      "T\t1\t1\t2\t2\t1\t2\t1"
    ),
    ABSOLUTE = c(
      "sample\tChromosome\tStart\tEnd\tModal_HSCN_1\tModal_HSCN_2",
      "T\t1\t1\t2\t1\t1"
    ),
    PCAWG = c(
      paste0(
        "sample\tchromosome\tchromosome_start\tchromosome_end\tcopy_number\t",
        "mutation_type"
      ),
      "T\t1\t1\t2\t2\tcopy neutral"
    ),
    FACETS = c("chrom\tstart\tend\ttcn.em\tlcn.em", "1\t1\t2\t2\t1"),
    BATTENBERG = c(
      "sample\tchr\tstartpos\tendpos\tnMaj1_A\tnMin1_A",
      "T\t1\t1\t2\t1\t1"
    ),
    PURPLE = c(
      "chromosome\tstart\tend\tminorAlleleCopyNumber\tmajorAlleleCopyNumber",
      "1\t1\t2\t1\t1"
    ),
    SEQUENZA = c("chromosome\tstart.pos\tend.pos\tCNt\tA\tB", "1\t1\t2\t2\t1\t1")
  )
  for (caller in names(fixtures)) {
    path <- .io_write_fixture(fixtures[[caller]], ".tsv")
    seg <- ms_segments(path) # caller defaults to "auto"
    expect_identical(
      attr(seg, "provenance")$caller, caller,
      info = paste0("auto-detection failed for ", caller)
    )
    unlink(path)
  }
})

test_that("caller labels are case-insensitive; CNVkit is documented-limited", {
  path <- .seg_fixture(
    "sample\tchr\tstartpos\tendpos\tnMajor\tnMinor",
    "T\t1\t1\t2\t1\t1"
  )
  on.exit(unlink(path))
  seg <- ms_segments(path, caller = "ascat")
  expect_identical(attr(seg, "provenance")$caller, "ASCAT")

  cnvkit <- .seg_fixture(
    "chromosome\tstart\tend\tgene\tlog2",
    "1\t1\t2\tGENE\t0.5"
  )
  on.exit(unlink(cnvkit), add = TRUE)
  # SPMG has no CNVkit branch and .cns/.cnr output is not
  # allele-specific: documented-limited rejection, not a force-fit.
  err <- expect_ms_error(ms_segments(cnvkit, caller = "CNVkit"), "input")
  expect_match(conditionMessage(err), "CNVkit", fixed = TRUE)

  expect_ms_error(ms_segments(path, caller = "not_a_caller"), "input")
})

# ---------------------------------------------------------------------
# Direct data.frame construction
# ---------------------------------------------------------------------

test_that("canonical data.frames construct directly with caller provenance", {
  seg <- ms_segments(
    data.frame(
      chrom = "chr7", start = 100000, end = 9000000, minor = 1L, major = 1L
    ),
    caller = "synthetic"
  )
  expect_identical(names(seg), c("chrom", "start", "end", "minor", "major"))
  expect_identical(seg$minor, 1L)
  prov <- attr(seg, "provenance")
  expect_identical(prov$caller, "synthetic")
  expect_identical(prov$parse$n_records, 1L)
  expect_false("source" %in% names(prov))
})

test_that("direct construction rejects contract violations", {
  good <- data.frame(
    chrom = "chr7", start = 100000, end = 9000000, minor = 1L, major = 1L
  )
  expect_ms_error(ms_segments(good), "input") # caller missing
  expect_ms_error(ms_segments(good, caller = "auto"), "input")
  expect_ms_error(
    ms_segments(good, caller = "x", chrom_col = "chr"), "input"
  )
  expect_ms_error(ms_segments(good, caller = "x", oops = 1), "input")
  expect_ms_error(
    ms_segments(transform(good, minor = 3L), caller = "x"),
    "segments", regexp = "minor copy number"
  )
  expect_ms_error(
    ms_segments(transform(good, end = 100L), caller = "x"),
    "segments", regexp = "end"
  )
  expect_ms_error(
    ms_segments(transform(good, start = 100.5), caller = "x"),
    "segments", regexp = "integer"
  )
  expect_ms_error(
    ms_segments(transform(good, minor = -1L), caller = "x"),
    "segments", regexp = "integer"
  )
  expect_ms_error(
    ms_segments(rbind(good, NA), caller = "x"), "segments"
  )
  expect_ms_error(
    ms_segments(good[, c("chrom", "start", "end", "minor")], caller = "x"),
    "input", regexp = "missing required columns"
  )
})

# ---------------------------------------------------------------------
# File-level error discipline
# ---------------------------------------------------------------------

test_that("file-path errors follow the msuiter_error_* protocol", {
  expect_ms_error(ms_segments(tempfile(fileext = ".tsv")), "io")

  dir <- tempfile()
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE))
  expect_ms_error(ms_segments(dir), "io")

  expect_ms_error(ms_segments(42), "input")
  path <- .seg_fixture(
    "sample\tchr\tstartpos\tendpos\tnMajor\tnMinor",
    "T\t1\t1\t2\t1\t1"
  )
  on.exit(unlink(path), add = TRUE)
  expect_ms_error(ms_segments(path, caller = "x", oops = 1), "input")
  bad_ext <- .io_write_fixture(c("a\tb", "1\t2"), ".txtx")
  on.exit(unlink(bad_ext), add = TRUE)
  expect_ms_error(ms_segments(bad_ext), "unsupported", regexp = "extension")

  # A forced caller whose required columns are absent.
  wrong <- .io_write_fixture(c("a\tb\tc", "1\t2\t3"), ".tsv")
  on.exit(unlink(wrong), add = TRUE)
  expect_ms_error(ms_segments(wrong, caller = "ASCAT"), "io")
  expect_ms_error(ms_segments(wrong), "io") # no signature matches

  # Ragged table -> msuiter_error_parse, never a bare error.
  ragged <- .io_write_fixture(
    c("sample\tchr\tstartpos\tendpos\tnMajor\tnMinor", "T\t1\t1\t2\t1\t1\tEXTRA"),
    ".tsv"
  )
  on.exit(unlink(ragged), add = TRUE)
  expect_ms_error(ms_segments(ragged), "parse")

  # A file whose EVERY data line is one field wider than the header
  # would make read.table silently shift the first data column into the
  # row names; the strict field-count check catches it.
  all_wide <- .io_write_fixture(
    c(
      "sample\tchr\tstartpos\tendpos\tnMajor\tnMinor",
      "T\t1\t1\t2\t1\t1\tEXTRA",
      "T\t2\t3\t4\t1\t1\tEXTRA"
    ),
    ".tsv"
  )
  on.exit(unlink(all_wide), add = TRUE)
  expect_ms_error(ms_segments(all_wide), "parse", regexp = "ragged")
})

test_that("segment coordinates must be positive integers with end >= start", {
  header <- "sample\tchr\tstartpos\tendpos\tnMajor\tnMinor"
  zero <- .seg_fixture(header, "T\t1\t0\t9\t1\t1")
  on.exit(unlink(zero))
  expect_ms_error(ms_segments(zero), "io", regexp = "integers >= 1")

  negative <- .seg_fixture(header, "T\t1\t-5\t9\t1\t1")
  on.exit(unlink(negative), add = TRUE)
  expect_ms_error(ms_segments(negative), "io")

  na <- .seg_fixture(header, "T\t1\tNA\t9\t1\t1")
  on.exit(unlink(na), add = TRUE)
  expect_ms_error(ms_segments(na), "io", regexp = "missing values")

  frac <- .seg_fixture(header, "T\t1\t1.5\t9\t1\t1")
  on.exit(unlink(frac), add = TRUE)
  expect_ms_error(ms_segments(frac), "io")

  span <- .seg_fixture(header, "T\t1\t900\t100\t1\t1")
  on.exit(unlink(span), add = TRUE)
  expect_ms_error(ms_segments(span), "segments", regexp = "end")
})

test_that("gzip-compressed segmentation files read transparently", {
  gz <- .seg_fixture(
    "sample\tchr\tstartpos\tendpos\tnMajor\tnMinor",
    "T\t1\t1\t2\t1\t1",
    gz = TRUE
  )
  on.exit(unlink(gz))
  seg <- ms_segments(gz)
  expect_identical(seg$minor, 1L)
  expect_identical(attr(seg, "provenance")$parse$n_records, 1L)
})
