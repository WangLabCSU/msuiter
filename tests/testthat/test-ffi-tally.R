# Catalog tally kernel over the FFI (U-M1s-09): ms_tally_rust end to end.
#
# Rust-side goldens (src/rust/src/tally.rs) pin the assembly semantics with
# a hand-derived 22-record batch; this file replays THE SAME batch through
# the real FFI (memory-mapped 2bit fixture written from R, LE layout) and
# pins the matrix layout, the R-side channel labels (sysdata channel
# tables, D5) and the error paths.

# ---------------------------------------------------------------------------
# Fixture: a little-endian 2bit genome, same content as the Rust golden
#   chr1: ACAC... (64 bp), N block at 0-based 50..52
#   chr2: GCGC... (40 bp)
# 2bit packing: T=0 C=1 A=2 G=3, first base in the high bits.
# ---------------------------------------------------------------------------

.ms_tally_write_2bit <- function(path) {
  u32 <- function(v) writeBin(as.integer(v), raw(), size = 4L, endian = "little")
  pack <- function(bases) {
    out <- raw((length(bases) + 3L) %/% 4L)
    acc <- 0L
    filled <- 0L
    k <- 0L
    for (b in bases) {
      acc <- bitwOr(bitwShiftL(acc, 2L), b)
      filled <- filled + 1L
      if (filled == 4L) {
        k <- k + 1L
        out[k] <- as.raw(acc)
        acc <- 0L
        filled <- 0L
      }
    }
    if (filled > 0L) {
      out[k + 1L] <- as.raw(bitwShiftL(acc, 2L * (4L - filled)))
    }
    out
  }
  chr1 <- rep(c(2L, 1L), 32L) # A C A C ...
  chr1[51L:53L] <- 0L # N block (0-based 50..52), packed as zeros
  chr2 <- rep(c(3L, 1L), 20L) # G C G C ...
  recs <- list(
    list(name = "chr1", size = 64L, dna = pack(chr1), nb = 50L, nl = 3L),
    list(name = "chr2", size = 40L, dna = pack(chr2), nb = integer(0), nl = integer(0))
  )
  off <- 16L + sum(vapply(recs, function(r) 1L + nchar(r$name) + 4L, 0L))
  index <- raw()
  body <- raw()
  for (r in recs) {
    index <- c(index, as.raw(nchar(r$name)), charToRaw(r$name), u32(off))
    rec <- c(
      u32(r$size), u32(length(r$nb)),
      u32(r$nb), u32(r$nl), # empty raw() when no N blocks
      u32(0L), u32(0L), r$dna
    )
    body <- c(body, rec)
    off <- off + length(rec)
  }
  con <- file(path, "wb")
  on.exit(close(con), add = TRUE)
  writeBin(c(u32(0x1A412743), u32(0L), u32(length(recs)), u32(0L), index, body), con)
  invisible(path)
}

# The hand-derived golden batch (0-based positions of the Rust golden + 1):
# plain SNVs in two samples, adjacent DBS pairs on both chromosomes (one
# with reversed input order), strand N / B records, a split 3 bp block
# substitution reconnected from two pieces, a 6 bp long MNV, +/-2-window N
# skips, an N-dinucleotide DBS candidate, a REF-vs-genome mismatch, head
# and tail context-bounds skips, a simple indel, a complex indel and an
# unknown chromosome. Sample columns: "S2" first appears at record 1, "S1"
# at record 3 -> columns c("S2", "S1").
.ms_tally_golden_frame <- function() {
  data.frame(
    chrom = c(
      "chr2", "chr2", "chr1", "chr1", "chr1", "chr1", "chr1", "chr1",
      "chr1", "chr1", "chr1", "chr1", "chr1", "chr1", "chr1", "chr1",
      "chr1", "chr1", "chrZ", "chr2", "chr1", "chr1"
    ),
    pos = c(
      34, 35, 12, 17, 23, 22, 25, 28, 33, 32, 44, 37,
      50, 54, 57, 61, 64, 2, 11, 26, 52, 53
    ),
    ref_ = c(
      "C", "G", "C", "A", "A", "C", "A", "C", "AC", "C", "T", "ACACAC",
      "C", "C", "CA", "AC", "C", "C", "A", "C", "C", "C"
    ),
    alt = c(
      "A", "T", "A", "G", "G", "T", "T", "G", "G", "TA", "G", "TTTTTT",
      "A", "A", "C", "TTT", "A", "A", "T", "A", "A", "T"
    ),
    sample = c(
      "S2", "S2", "S1", "S2", "S1", "S1", "S2", "S2", "S2", "S2", "S1",
      "S1", "S1", "S1", "S1", "S1", "S1", "S1", "S1", "S2", "S1", "S1"
    ),
    strand = c(
      "T", "T", "T", "U", "T", "T", "N", "B", "N", "N", "N", "N",
      "N", "N", "N", "N", "N", "N", "N", "T", "N", "N"
    ),
    stringsAsFactors = FALSE
  )
}

.ms_tally_golden_ledger <- function() {
  lines <- paste0(
    c(
      "1\tdbs", "2\tdbs", "3\tsbs", "4\tsbs", "5\tdbs", "6\tdbs",
      "7\tsbs", "8\tsbs", "9\tmnv", "10\tmnv", "11\tskipped:ref_mismatch",
      "12\tlong_mnv", "13\tskipped:n_context", "14\tskipped:n_context",
      "15\tskipped:simple_indel", "16\tcomplex_indel",
      "17\tskipped:context_bounds", "18\tskipped:context_bounds",
      "19\tskipped:unknown_chrom", "20\tsbs", "21\tskipped:n_dinuc",
      "22\tskipped:n_dinuc"
    ),
    collapse = "\n"
  )
  paste0(lines, "\n")
}
.ms_tally_channel_tables <- function() {
  get("channel_tables", envir = asNamespace("msuiter"))
}

# ---------------------------------------------------------------------------
# Golden end-to-end run
# ---------------------------------------------------------------------------

test_that("ms_tally_rust replays the hand-derived golden batch", {
  path <- .ms_tally_write_2bit(file.path(tempdir(), "tally-golden.2bit"))
  on.exit(unlink(path), add = TRUE)
  d <- .ms_tally_golden_frame()
  res <- .ms_tally_rust(path,
    chrom = d$chrom, pos = d$pos, ref_ = d$ref_, alt = d$alt,
    sample = d$sample, strand = d$strand,
    want_sbs96 = TRUE, want_sbs192 = TRUE, want_sbs384 = TRUE,
    want_sbs1536 = TRUE, want_dbs78 = TRUE
  )

  # Matrix dimensions and labels (canonical rows from the R registry).
  tables <- .ms_tally_channel_tables()
  expect_identical(dim(res$sbs96), c(96L, 2L))
  expect_identical(dim(res$sbs192), c(192L, 2L))
  expect_identical(dim(res$sbs384), c(384L, 2L))
  expect_identical(dim(res$sbs1536), c(1536L, 2L))
  expect_identical(dim(res$dbs78), c(78L, 2L))
  expect_identical(rownames(res$sbs96), tables$SBS96$labels)
  expect_identical(rownames(res$sbs192), tables$SBS192$labels)
  expect_identical(rownames(res$sbs384), tables$SBS384$labels)
  expect_identical(rownames(res$sbs1536), tables$SBS1536$labels)
  expect_identical(rownames(res$dbs78), tables$DBS78$labels)
  # Column order: first appearance of `sample` in the input rows.
  expect_identical(colnames(res$sbs96), c("S2", "S1"))

  # Hand-derived count cells (labelled access doubles as a layout probe:
  # rows are channels, columns are samples, never transposed).
  expect_identical(sum(res$sbs96), 5L)
  expect_identical(res$sbs96["A[C>A]A", "S1"], 1L) # chr1 11 C>A
  expect_identical(res$sbs96["G[T>C]G", "S2"], 1L) # chr1 16 A>G (U flip)
  expect_identical(res$sbs96["G[T>A]G", "S2"], 1L) # chr1 24 A>T (N strand)
  expect_identical(res$sbs96["A[C>G]A", "S2"], 1L) # chr1 27 C>G (B strand)
  expect_identical(res$sbs96["G[C>A]G", "S2"], 1L) # chr2 25 C>A

  expect_identical(sum(res$sbs192), 3L) # N/B strands have no 192 channel
  expect_identical(res$sbs192["T:A[C>A]A", "S1"], 1L)
  expect_identical(res$sbs192["T:G[T>C]G", "S2"], 1L)
  expect_identical(res$sbs192["T:G[C>A]G", "S2"], 1L)

  expect_identical(sum(res$sbs384), 5L)
  expect_identical(res$sbs384["N:G[T>A]G", "S2"], 1L)
  expect_identical(res$sbs384["B:A[C>G]A", "S2"], 1L)

  expect_identical(sum(res$sbs1536), 5L)
  expect_identical(res$sbs1536["CA[C>A]AC", "S1"], 1L)
  expect_identical(res$sbs1536["TG[T>C]GT", "S2"], 1L)

  # Adjacent DBS pairs: counted in DBS78, excluded from every SBS matrix.
  expect_identical(sum(res$dbs78), 2L)
  expect_identical(res$dbs78["CG>AT", "S2"], 1L) # chr2 33/34
  expect_identical(res$dbs78["TG>CA", "S1"], 1L) # chr1 21/22 (reversed input)
  expect_identical(res$sbs96["A[C>T]A", "S1"], 0L) # chr1 21 never in SBS

  # Ledger, byte-exact; every record lands in exactly one destination.
  expect_identical(res$ledger, .ms_tally_golden_ledger())
  expect_identical(res$n_skipped, 9L)
  expect_identical(res$n_variants, 22L)
})

test_that("cross-sample adjacent SNVs never pair into a DBS (U-M1s-09 audit P1)", {
  path <- .ms_tally_write_2bit(file.path(tempdir(), "tally-xs.2bit"))
  on.exit(unlink(path), add = TRUE)
  # chr1 1-based 12 C>A (S1) and 13 A>T (S2): coordinate-adjacent on the
  # chromosome, different samples. SPMG's dinuc_sub == 1 detection is a
  # SINGLE-SAMPLE criterion, so both records stay SBS and no DBS78 count
  # may appear (the pre-fix router paired them into one DBS and dropped
  # both from the SBS matrices).
  res <- .ms_tally_rust(path,
    chrom = c("chr1", "chr1"), pos = c(12, 13),
    ref_ = c("C", "A"), alt = c("A", "T"),
    sample = c("S1", "S2"), strand = c("N", "N"),
    want_sbs96 = TRUE, want_dbs78 = TRUE
  )
  expect_identical(res$ledger, "1\tsbs\n2\tsbs\n")
  expect_identical(res$n_skipped, 0L)
  expect_identical(sum(res$dbs78), 0L)
  expect_identical(sum(res$sbs96), 2L)
  expect_identical(res$sbs96["A[C>A]A", "S1"], 1L)
  expect_identical(res$sbs96["G[T>A]G", "S2"], 1L) # A>T purine mirror

  # Mirrored input order does not change the routing decision.
  res2 <- .ms_tally_rust(path,
    chrom = c("chr1", "chr1"), pos = c(13, 12),
    ref_ = c("A", "C"), alt = c("T", "A"),
    sample = c("S2", "S1"), strand = c("N", "N"),
    want_sbs96 = TRUE, want_dbs78 = TRUE
  )
  expect_identical(res2$ledger, "1\tsbs\n2\tsbs\n")
  expect_identical(sum(res2$dbs78), 0L)
})

test_that("disabled tables come back as table x 0 matrices, ledger unchanged", {
  path <- .ms_tally_write_2bit(file.path(tempdir(), "tally-off.2bit"))
  on.exit(unlink(path), add = TRUE)
  d <- .ms_tally_golden_frame()
  res <- .ms_tally_rust(path,
    chrom = d$chrom, pos = d$pos, ref_ = d$ref_, alt = d$alt,
    sample = d$sample, strand = d$strand,
    want_sbs96 = FALSE, want_sbs192 = FALSE, want_sbs384 = FALSE,
    want_sbs1536 = FALSE, want_dbs78 = FALSE
  )
  expect_identical(dim(res$sbs96), c(96L, 0L))
  expect_identical(dim(res$dbs78), c(78L, 0L))
  expect_identical(rownames(res$sbs96), .ms_tally_channel_tables()$SBS96$labels)
  # Switch-independent ledger (context checks always run).
  expect_identical(res$ledger, .ms_tally_golden_ledger())
  expect_identical(res$n_skipped, 9L)
})

test_that("empty input yields empty matrices and an empty ledger", {
  path <- .ms_tally_write_2bit(file.path(tempdir(), "tally-empty.2bit"))
  on.exit(unlink(path), add = TRUE)
  res <- .ms_tally_rust(path,
    chrom = character(0), pos = numeric(0), ref_ = character(0),
    alt = character(0), sample = character(0), strand = character(0)
  )
  expect_identical(dim(res$sbs96), c(96L, 0L))
  expect_identical(res$ledger, "")
  expect_identical(res$n_skipped, 0L)
  expect_identical(res$n_variants, 0L)
})

test_that("lowercase or IUPAC alleles are ledgered, never coerced", {
  path <- .ms_tally_write_2bit(file.path(tempdir(), "tally-lower.2bit"))
  on.exit(unlink(path), add = TRUE)
  res <- .ms_tally_rust(path,
    chrom = "chr1", pos = 12, ref_ = "a", alt = "T", sample = "S1", strand = "N"
  )
  expect_identical(res$ledger, "1\tskipped:invalid_base\n")
  expect_identical(res$n_skipped, 1L)
})

# ---------------------------------------------------------------------------
# Error paths (contract 5: whole call fails, no partial results)
# ---------------------------------------------------------------------------

test_that("missing genome file maps to msuiter_error_rust (io)", {
  err <- tryCatch(
    .ms_tally_rust(file.path(tempdir(), "does-not-exist.2bit"),
      chrom = "chr1", pos = 12, ref_ = "C", alt = "A",
      sample = "S1", strand = "N"
    ),
    error = identity
  )
  expect_s3_class(err, "msuiter_error_rust")
  expect_identical(err$topic, "io")
})

test_that("bad magic maps to msuiter_error_rust (format)", {
  path <- file.path(tempdir(), "tally-bad-magic.2bit")
  con <- file(path, "wb")
  writeBin(as.raw(c(0x0a, 0x41, 0x27, 0x43, rep(0, 32))), con)
  close(con)
  on.exit(unlink(path), add = TRUE)
  err <- tryCatch(
    .ms_tally_rust(path,
      chrom = "chr1", pos = 12, ref_ = "C", alt = "A",
      sample = "S1", strand = "N"
    ),
    error = identity
  )
  expect_s3_class(err, "msuiter_error_rust")
  expect_identical(err$topic, "format")
})

test_that("R validators reject malformed columns before the FFI", {
  path <- .ms_tally_write_2bit(file.path(tempdir(), "tally-bad.2bit"))
  on.exit(unlink(path), add = TRUE)
  ok <- function(...) .ms_tally_rust(path, ...)

  err <- tryCatch(ok(chrom = c("chr1", "chr1"), pos = 12, ref_ = "C", alt = "A",
                     sample = "S", strand = "N"), error = identity)
  expect_s3_class(err, "msuiter_error_input") # column length mismatch

  err <- tryCatch(ok(chrom = "chr1", pos = NA_real_, ref_ = "C", alt = "A",
                     sample = "S", strand = "N"), error = identity)
  expect_s3_class(err, "msuiter_error_na") # contract 3, first layer

  err <- tryCatch(ok(chrom = "chr1", pos = 0, ref_ = "C", alt = "A",
                     sample = "S", strand = "N"), error = identity)
  expect_s3_class(err, "msuiter_error_input") # pos must be 1-based

  err <- tryCatch(ok(chrom = "chr1", pos = 12.5, ref_ = "C", alt = "A",
                     sample = "S", strand = "N"), error = identity)
  expect_s3_class(err, "msuiter_error_input") # pos must be integer-valued

  err <- tryCatch(ok(chrom = "chr1", pos = 12, ref_ = "C", alt = "A",
                     sample = "S", strand = "X"), error = identity)
  expect_s3_class(err, "msuiter_error_input") # strand vocabulary

  err <- tryCatch(ok(chrom = NA_character_, pos = 12, ref_ = "C", alt = "A",
                     sample = "S", strand = "N"), error = identity)
  expect_s3_class(err, "msuiter_error_input") # NA in a character column

  err <- tryCatch(ok(chrom = "chr1", pos = 12, ref_ = "C", alt = "A",
                     sample = "S", strand = "N", want_dbs78 = "yes"),
                  error = identity)
  expect_s3_class(err, "msuiter_error_input") # switch must be logical

  # Second layer: the Rust-side strand guard via the raw passthrough.
  err2 <- tryCatch(
    ms_tally_rust(path, "chr1", 12, "C", "A", "S", "X", TRUE, FALSE, FALSE, FALSE, FALSE),
    error = identity
  )
  expect_s3_class(err2, "msuiter_error_rust")
  expect_identical(err2$topic, "argument")
  expect_identical(err2$i, 1L)
})

test_that("unknown chromosomes are ledger rows, not errors", {
  path <- .ms_tally_write_2bit(file.path(tempdir(), "tally-chrz.2bit"))
  on.exit(unlink(path), add = TRUE)
  res <- .ms_tally_rust(path,
    chrom = c("chrZ", "chr1"), pos = c(11, 12), ref_ = c("A", "C"),
    alt = c("T", "A"), sample = c("S1", "S1"), strand = c("N", "N")
  )
  expect_match(res$ledger, "1\tskipped:unknown_chrom\n", fixed = TRUE)
  expect_match(res$ledger, "2\tsbs\n", fixed = TRUE)
  expect_identical(res$n_skipped, 1L)
})
