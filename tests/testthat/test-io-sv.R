# io layer: ms_sv() BEDPE parsing, svtype derivation and kat-region
# clustering (M1c input-layer wiring). The gold standard is SPMG
# SVMatrixGenerator.py at master edccbea6 (strands -> svclass :1100-1128;
# size :1138-1159; annotateBedpe :797-930); the kat port in R/io-sv.R is
# validated against real upstream annotateBedpe goldens. All fixtures
# are self-made with writeLines into the session temp dir.

.sv_fixture <- function(lines, gz = FALSE) {
  .io_write_fixture(lines, ".bedpe", gz)
}

.sv_header <- "chrom1\tstart1\tend1\tchrom2\tstart2\tend2\tstrand1\tstrand2"

# The 22-event kataegis scenario of the upstream golden sweep (SPMG
# annotateBedpe at edccbea6): 8 tightly spaced deletions on chr "1"
# (rows 1-9 flag clustered, including the first scattered event whose
# pcf segment dips below the threshold), 5 scattered chr-1 events, 2
# inversions, 1 tandem duplication, 1 translocation on chr "2"/"3", and
# 4 sparse chr-4 events whose 8 breakpoints sit below the MIN_BPS gate.
.kat_lines <- c(
  paste0(
    "sample\tchrom1\tstart1\tend1\tchrom2\tstart2\tend2\tstrand1\t",
    "strand2"
  ),
  "TUMOR1\t1\t30000000\t30000200\t1\t30040200\t30040400\t+\t+",
  "TUMOR1\t1\t30012000\t30012200\t1\t30055200\t30055400\t+\t+",
  "TUMOR1\t1\t30024000\t30024200\t1\t30070200\t30070400\t+\t+",
  "TUMOR1\t1\t30036000\t30036200\t1\t30085200\t30085400\t+\t+",
  "TUMOR1\t1\t30048000\t30048200\t1\t30100200\t30100400\t+\t+",
  "TUMOR1\t1\t30060000\t30060200\t1\t30115200\t30115400\t+\t+",
  "TUMOR1\t1\t30072000\t30072200\t1\t30130200\t30130400\t+\t+",
  "TUMOR1\t1\t30084000\t30084200\t1\t30145200\t30145400\t+\t+",
  "TUMOR1\t1\t5000000\t5000300\t1\t10000000\t10000300\t+\t+",
  "TUMOR1\t1\t60000000\t60000300\t1\t65000000\t65000300\t+\t+",
  "TUMOR1\t1\t120000000\t120000300\t1\t125000000\t125000300\t+\t+",
  "TUMOR1\t1\t180000000\t180000300\t1\t185000000\t185000300\t+\t+",
  "TUMOR1\t1\t200000000\t200000300\t1\t205000000\t205000300\t+\t+",
  "TUMOR1\t1\t220000000\t220000300\t1\t225000000\t225000300\t+\t+",
  "TUMOR1\t2\t10000000\t10000400\t2\t40000000\t40000400\t+\t-",
  "TUMOR1\t2\t12000000\t12000400\t2\t44000000\t44000400\t+\t-",
  "TUMOR1\t2\t20000000\t20000400\t2\t20400000\t20400400\t-\t-",
  "TUMOR1\t2\t30000000\t30000400\t3\t15000000\t15000400\t+\t+",
  "TUMOR1\t4\t1000000\t1000300\t4\t10000000\t10000300\t+\t+",
  "TUMOR1\t4\t50000000\t50000300\t4\t59000000\t59000300\t+\t+",
  "TUMOR1\t4\t100000000\t100000300\t4\t109000000\t109000300\t+\t+",
  "TUMOR1\t4\t150000000\t150000300\t4\t159000000\t159000300\t+\t+"
)

# ---------------------------------------------------------------------
# svtype derivation and size
# ---------------------------------------------------------------------

test_that("BEDPE strands derive all four svtype classes", {
  path <- .sv_fixture(c(
    .sv_header,
    "1\t100\t200\t1\t500000\t500100\t+\t+", # deletion
    "1\t1000\t1100\t1\t1500000\t1500100\t-\t-", # tandem-duplication
    "1\t2000\t2100\t1\t2500000\t2500100\t+\t-", # inversion
    "1\t3000\t3100\t1\t3500000\t3500100\t-\t+", # inversion (other mix)
    "1\t4000\t4100\t2\t4500000\t4500100\t+\t+" # translocation
  ))
  on.exit(unlink(path))
  sv <- ms_sv(path)
  expect_identical(
    names(sv),
    c(
      "chrom1", "start1", "end1", "chrom2", "start2", "end2",
      "svtype", "size_bp", "clustered"
    )
  )
  expect_identical(
    sv$svtype,
    c("deletion", "tandem-duplication", "inversion", "inversion",
      "translocation")
  )
  expect_identical(sv$size_bp, c(499900L, 1499000L, 2498000L, 3497000L, 4496000L))
  # Sparse input: no chromosome crosses the MIN_BPS gate.
  expect_identical(sv$clustered, rep(FALSE, 5L))
  expect_false("sample" %in% names(sv))
  prov <- attr(sv, "provenance")
  expect_identical(prov$format, "bedpe")
  expect_identical(prov$parse$n_records, 5L)
  expect_identical(prov$parse$n_derived_svclass, 5L)
  expect_identical(prov$parse$n_provided_svclass, 0L)
  expect_identical(prov$parse$n_translocation, 1L)
  expect_identical(prov$kat$kmin, 10L)
  expect_identical(prov$kat$min_bps, 10L)
  expect_identical(prov$kat$genome_size, 3e9)
  expect_identical(prov$kat$peak_factor, 10)
  expect_identical(prov$kat$gamma_sdev, 25)
  expect_identical(prov$kat$n_kat_regions, 0L)
})

test_that("a provided svclass column is consumed verbatim; SVTYPE is accepted", {
  path <- .sv_fixture(c(
    "chrom1\tstart1\tend1\tchrom2\tstart2\tend2\tsvclass",
    "1\t100\t200\t1\t500000\t500100\tdeletion",
    "1\t1000\t1100\t2\t1500000\t1500100\ttranslocation"
  ))
  on.exit(unlink(path))
  sv <- ms_sv(path)
  expect_identical(sv$svtype, c("deletion", "translocation"))
  prov <- attr(sv, "provenance")
  expect_identical(prov$parse$n_provided_svclass, 2L)
  expect_identical(prov$parse$n_derived_svclass, 0L)

  svtype <- .sv_fixture(c(
    "chrom1\tstart1\tend1\tchrom2\tstart2\tend2\tSVTYPE",
    "1\t100\t200\t1\t500000\t500100\ttandem-duplication"
  ))
  on.exit(unlink(svtype), add = TRUE)
  expect_identical(ms_sv(svtype)$svtype, "tandem-duplication")
})

test_that("foreign svclass labels are rejected at read time", {
  # Upstream would KeyError at the svclass_mapping (:1251); the io layer
  # rejects with the offending row instead.
  path <- .sv_fixture(c(
    "chrom1\tstart1\tend1\tchrom2\tstart2\tend2\tsvclass",
    "1\t100\t200\t1\t500000\t500100\ttransloc"
  ))
  on.exit(unlink(path))
  expect_ms_error(ms_sv(path), "sv", regexp = "svclass")
})

test_that("missing svclass AND strands is an io error; bad strands are sv", {
  no_class <- .sv_fixture(c(
    "chrom1\tstart1\tend1\tchrom2\tstart2\tend2",
    "1\t100\t200\t1\t500000\t500100"
  ))
  on.exit(unlink(no_class))
  expect_ms_error(ms_sv(no_class), "io", regexp = "cannot classify")

  bad_strand <- .sv_fixture(c(
    .sv_header,
    "1\t100\t200\t1\t500000\t500100\tx\t+"
  ))
  on.exit(unlink(bad_strand), add = TRUE)
  expect_ms_error(ms_sv(bad_strand), "sv", regexp = "strand")

  # Cross-chromosome events classify as translocation before the strands
  # are inspected (:1108-1110), so garbage strands there stay admissible
  # -- faithful to upstream.
  loose <- .sv_fixture(c(
    .sv_header,
    "1\t100\t200\t2\t500000\t500100\tx\ty"
  ))
  on.exit(unlink(loose), add = TRUE)
  expect_identical(ms_sv(loose)$svtype, "translocation")
})

# ---------------------------------------------------------------------
# kat-region clustering
# ---------------------------------------------------------------------

test_that("kat clustering triggers on the upstream kataegis scenario", {
  path <- .sv_fixture(.kat_lines)
  on.exit(unlink(path))
  sv <- ms_sv(path)
  # Golden result (SPMG annotateBedpe at edccbea6): the 8 clustered
  # deletions plus the first scattered event flag clustered.
  expect_identical(sv$clustered, rep(c(TRUE, FALSE), c(9L, 13L)))
  expect_identical(sv$svtype[1:8], rep("deletion", 8L))
  expect_identical(sv$svtype[15:16], c("inversion", "inversion"))
  expect_identical(sv$svtype[17], "tandem-duplication")
  expect_identical(sv$svtype[18], "translocation")
  prov <- attr(sv, "provenance")
  expect_identical(prov$kat$n_kat_regions, 1L)
})

test_that("kat clustering never triggers at or below the MIN_BPS gate", {
  # 5 events on chr1 = exactly 10 breakpoints: the gate is strict
  # (:860-862 runs pcf only above 10), so no chromosome can cluster.
  path <- .sv_fixture(c(
    .sv_header,
    "1\t1000000\t1000100\t1\t1100000\t1100100\t+\t+",
    "1\t2000000\t2000100\t1\t2100000\t2100100\t+\t+",
    "1\t3000000\t3000100\t1\t3100000\t3100100\t+\t+",
    "1\t4000000\t4000100\t1\t4100000\t4100100\t+\t+",
    "1\t5000000\t5000100\t1\t5100000\t5100100\t+\t+"
  ))
  on.exit(unlink(path))
  sv <- ms_sv(path)
  expect_identical(sv$clustered, rep(FALSE, 5L))
  expect_identical(attr(sv, "provenance")$kat$n_kat_regions, 0L)
})

test_that("multi-sample BEDPE annotates kat per sample group", {
  # Upstream annotates one file (= one sample) at a time (:978-1018);
  # with a sample column the same isolation holds per group. Sample S1
  # carries the kataegis scenario (identical flags to the single-sample
  # run, since the threshold depends only on the group's breakpoints);
  # sample S2 has exactly 10 chr-9 breakpoints -> gate -> never
  # clustered.
  lines <- .kat_lines
  lines[-1L] <- sub("^TUMOR1", "S1", lines[-1L])
  s2 <- c(
    "S2\t9\t1000000\t1000100\t9\t1100000\t1100100\t+\t+",
    "S2\t9\t2000000\t2000100\t9\t2100000\t2100100\t+\t+",
    "S2\t9\t3000000\t3000100\t9\t3100000\t3100100\t+\t+",
    "S2\t9\t4000000\t4000100\t9\t4100000\t4100100\t+\t+",
    "S2\t9\t5000000\t5000100\t9\t5100000\t5100100\t+\t+"
  )
  path <- .sv_fixture(c(lines, s2))
  on.exit(unlink(path))
  sv <- ms_sv(path)
  expect_identical(sv$sample, c(rep("S1", 22L), rep("S2", 5L)))
  expect_identical(sv$clustered, c(rep(c(TRUE, FALSE), c(9L, 13L)), rep(FALSE, 5L)))
})

test_that("an input is_clustered column is ignored and recomputed", {
  path <- .sv_fixture(c(
    paste0(
      "chrom1\tstart1\tend1\tchrom2\tstart2\tend2\tstrand1\tstrand2\t",
      "is_clustered"
    ),
    "1\t1000000\t1000100\t1\t1100000\t1100100\t+\t+\tTrue",
    "1\t2000000\t2000100\t1\t2100000\t2100100\t+\t+\tTrue"
  ))
  on.exit(unlink(path))
  # Upstream overwrites the column unconditionally (:919-926); the
  # recomputed flag for this gate-blocked input is FALSE.
  expect_identical(ms_sv(path)$clustered, c(FALSE, FALSE))
})

test_that("chromosome names pass through verbatim", {
  # Deliberate divergence from upstream's chr-stripping
  # (processBEDPE :1041-1055): the msuiter catalog layer is
  # chromosome-opaque.
  path <- .sv_fixture(c(
    .sv_header,
    "chr7\t100\t200\tchr7\t500000\t500100\t+\t+"
  ))
  on.exit(unlink(path))
  sv <- ms_sv(path)
  expect_identical(sv$chrom1, "chr7")
  expect_identical(sv$chrom2, "chr7")
})

# ---------------------------------------------------------------------
# Sizes, provenance statistics and the <1 kb contract
# ---------------------------------------------------------------------

test_that("sub-kilobase non-translocation events are counted, not dropped", {
  # The <1 kb drop (:1184-1189) is the catalog layer's ledger rule
  # (sv32.rs Sv32Outcome::TooShortNoChannel); the io layer keeps every
  # record and reports the count.
  path <- .sv_fixture(c(
    .sv_header,
    "1\t100\t200\t1\t600\t700\t+\t+", # 500 bp deletion
    "1\t1000\t1100\t1\t1500000\t1500100\t+\t+" # 1,499,000 bp deletion
  ))
  on.exit(unlink(path))
  sv <- ms_sv(path)
  expect_identical(nrow(sv), 2L)
  expect_identical(sv$size_bp, c(500L, 1499000L))
  expect_identical(
    attr(sv, "provenance")$parse$n_below_1kb_non_trans, 1L
  )
})

# ---------------------------------------------------------------------
# Direct data.frame construction
# ---------------------------------------------------------------------

test_that("BEDPE-like data.frames run the same pipeline directly", {
  sv <- ms_sv(data.frame(
    chrom1 = "1", start1 = 100L, end1 = 200L,
    chrom2 = "1", start2 = 500000L, end2 = 500100L,
    strand1 = "+", strand2 = "+"
  ))
  expect_identical(sv$svtype, "deletion")
  expect_identical(sv$size_bp, 499900L)
  expect_false(sv$clustered)
  prov <- attr(sv, "provenance")
  expect_false("source" %in% names(prov))
  expect_identical(prov$format, "bedpe")

  # ... including the kat annotation.
  kat <- .io_write_fixture(.kat_lines, ".bedpe")
  on.exit(unlink(kat), add = TRUE)
  tab <- utils::read.delim(kat, stringsAsFactors = FALSE)
  expect_identical(
    ms_sv(tab)$clustered, rep(c(TRUE, FALSE), c(9L, 13L))
  )
})

# ---------------------------------------------------------------------
# File-level error discipline
# ---------------------------------------------------------------------

test_that("BEDPE file-path errors follow the msuiter_error_* protocol", {
  expect_ms_error(ms_sv(tempfile(fileext = ".bedpe")), "io")

  dir <- tempfile()
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE))
  expect_ms_error(ms_sv(dir), "io")

  expect_ms_error(ms_sv(42), "input")
  good <- .sv_fixture(c(
    .sv_header,
    "1\t100\t200\t1\t500000\t500100\t+\t+"
  ))
  on.exit(unlink(good), add = TRUE)
  expect_ms_error(ms_sv(good, oops = 1), "input")
  bad_ext <- .io_write_fixture(c("a\tb", "1\t2"), ".tsv")
  on.exit(unlink(bad_ext), add = TRUE)
  expect_ms_error(ms_sv(bad_ext), "unsupported", regexp = "BEDPE")

  ragged <- .sv_fixture(c(
    .sv_header,
    "1\t100\t200\t1\t500000\t500100\t+\t+\tEXTRA"
  ))
  on.exit(unlink(ragged), add = TRUE)
  expect_ms_error(ms_sv(ragged), "parse")})

test_that("BEDPE coordinates must be non-negative integers with end >= start", {
  negative <- .sv_fixture(c(
    .sv_header,
    "1\t100\t-5\t1\t500000\t500100\t+\t+"
  ))
  on.exit(unlink(negative))
  expect_ms_error(ms_sv(negative), "io", regexp = "non-negative integers")

  na <- .sv_fixture(c(
    .sv_header,
    "1\t100\tNA\t1\t500000\t500100\t+\t+"
  ))
  on.exit(unlink(na), add = TRUE)
  expect_ms_error(ms_sv(na), "io")

  span <- .sv_fixture(c(
    .sv_header,
    "1\t500000\t500100\t1\t100\t200\t+\t+" # end1 < start1 is fine as a
    # pair of breakends, but each interval must satisfy end >= start
  ))
  on.exit(unlink(span), add = TRUE)
  # end1 = 500100 >= start1 = 500000, end2 = 200 >= start2 = 100: valid.
  expect_no_error(ms_sv(span))

  inverted <- .sv_fixture(c(
    .sv_header,
    "1\t500100\t500000\t1\t100\t200\t+\t+"
  ))
  on.exit(unlink(inverted), add = TRUE)
  expect_ms_error(ms_sv(inverted), "sv", regexp = "end")

  bad_chrom <- .sv_fixture(c(
    .sv_header,
    "1\t100\t200\tNA\t500000\t500100\t+\t+"
  ))
  on.exit(unlink(bad_chrom), add = TRUE)
  expect_ms_error(ms_sv(bad_chrom), "sv", regexp = "chromosome")
})

test_that("gzip-compressed BEDPE reads transparently", {
  gz <- .sv_fixture(c(
    .sv_header,
    "1\t100\t200\t1\t500000\t500100\t+\t+"
  ), gz = TRUE)
  on.exit(unlink(gz))
  sv <- ms_sv(gz)
  expect_identical(sv$svtype, "deletion")
  expect_identical(attr(sv, "provenance")$parse$n_records, 1L)
})
