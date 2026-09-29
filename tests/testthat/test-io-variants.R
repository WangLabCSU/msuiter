# io layer: ms_variants() file reading + validated direct construction
# (U-M1s-10; ARCHITECTURE.md section 3.1: the io layer is the only place
# touching external formats). All fixtures are self-made with writeLines
# into the session temp dir -- no committed binary fixtures, no network.

# Sites-only 8-column VCF scaffold.
.vcf_fixture_lines <- function(records, fileformat = "##fileformat=VCFv4.2") {
  c(
    fileformat,
    "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO",
    records
  )
}

# Write fixture lines to a temp file, plain or gzip-compressed; returns
# the path (caller unlinks).
.write_io_fixture <- function(lines, ext, gz = FALSE) {
  path <- tempfile(fileext = paste0(ext, if (gz) ".gz" else ""))
  con <- if (gz) gzfile(path, "wt") else file(path, "wt")
  writeLines(lines, con)
  close(con)
  path
}

# ---------------------------------------------------------------------
# VCF
# ---------------------------------------------------------------------

test_that("ms_variants reads a sites-only VCF with FILTER passthrough", {
  path <- .write_io_fixture(.vcf_fixture_lines(c(
    "chr7\t55191822\t.\tC\tT\t.\tPASS\t.",
    "chr17\t7676594\t.\tCA\tC\t.\t.\t."
  )), ".vcf")
  on.exit(unlink(path))

  v <- ms_variants(path, "GRCh38",
    caller = "mutect2", matched_normal = "tumor-normal-N1")
  expect_is_ms(v, "MsVariants")
  expect_identical(nrow(v@table), 2L)
  expect_identical(v@table$chrom, c("chr7", "chr17"))
  expect_identical(v@table$start, c(55191822, 7676594))
  expect_identical(v@table$end, c(55191822, 7676595)) # ref CA spans 2 bases
  expect_identical(v@table$ref, c("C", "CA"))
  expect_identical(v@table$alt, c("T", "C"))
  expect_identical(v@table$filter, c("PASS", ".")) # verbatim passthrough
  expect_identical(v@provenance$caller, "mutect2")
  expect_identical(v@provenance$matched_normal, "tumor-normal-N1")
  expect_identical(v@provenance$source, path)
  expect_identical(v@provenance$format, "vcf")
  expect_identical(
    v@provenance$fileformat,
    "##fileformat=VCFv4.2"
  )
  expect_identical(v@provenance$parse$n_lines, 2L)
  expect_identical(v@provenance$parse$n_records, 2L)
  expect_identical(v@provenance$parse$n_skipped, 0L)
  expect_no_error(S7::validate(v))
})

test_that("gzip-compressed VCF reads through the native gzfile connection", {
  plain <- .write_io_fixture(.vcf_fixture_lines(
    "chr1\t100\t.\tA\tT\t.\tPASS\t."
  ), ".vcf")
  on.exit(unlink(plain))
  v_plain <- ms_variants(plain, "GRCh38",
    caller = "c", matched_normal = "none")

  gz <- .write_io_fixture(.vcf_fixture_lines(
    "chr1\t100\t.\tA\tT\t.\tPASS\t."
  ), ".vcf", gz = TRUE)
  v_gz <- ms_variants(gz, "GRCh38", caller = "c", matched_normal = "none")

  expect_identical(v_gz@table, v_plain@table)
  expect_identical(v_gz@provenance$format, "vcf")
})

test_that("multiallelic ALT expands per allele with a skip ledger", {
  path <- .write_io_fixture(.vcf_fixture_lines(c(
    "chr1\t100\t.\tA\tT,C\t.\tPASS\t.", # expansion: two records
    "chr1\t200\t.\tG\tT\t.\tq10\t.",
    "chr2\t300\t.\tA\t<NON_REF>,.\t.\tPASS\t." # symbolic + missing: skip
  )), ".vcf", gz = TRUE)
  on.exit(unlink(path))

  v <- ms_variants(path, "GRCh38", caller = "gatk", matched_normal = "none")
  expect_identical(nrow(v@table), 3L)
  expect_identical(v@table$alt, c("T", "C", "T"))
  expect_identical(v@table$chrom, c("chr1", "chr1", "chr1"))
  p <- v@provenance$parse
  expect_identical(p$n_records, 3L)
  expect_identical(p$n_multiallelic_sites, 2L) # rows 1 and 3 carry two ALTs
  expect_identical(p$n_skipped, 2L)
  expect_identical(p$skip_reasons[["symbolic_alt"]], 1L)
  expect_identical(p$skip_reasons[["missing_alt"]], 1L)
  expect_identical(v@provenance$caller, "gatk")
})

test_that("VCF coordinate and column failures raise project errors", {
  # non-integer POS: io-layer format check
  path <- .write_io_fixture(.vcf_fixture_lines(
    "chr1\t12.5\t.\tA\tT\t.\tPASS\t."
  ), ".vcf")
  expect_ms_error(
    ms_variants(path, "GRCh38", caller = "c", matched_normal = "none"),
    "io", regexp = "integer"
  )
  # zero POS passes the io syntax check and is rejected by the class
  # validator end to end (start >= 1 semantics live in the class layer)
  path0 <- .write_io_fixture(.vcf_fixture_lines(
    "chr1\t0\t.\tA\tT\t.\tPASS\t."
  ), ".vcf")
  expect_ms_error(
    ms_variants(path0, "GRCh38", caller = "c", matched_normal = "none"),
    "variants", regexp = "coordinate"
  )
  # missing ALT fixed column in the header
  path2 <- .write_io_fixture(c(
    "##fileformat=VCFv4.2",
    "#CHROM\tPOS\tID\tREF\tQUAL\tFILTER\tINFO",
    "chr1\t100\t.\tA\t.\tPASS\t."
  ), ".vcf")
  expect_ms_error(
    ms_variants(path2, "GRCh38", caller = "c", matched_normal = "none"),
    "io", regexp = "ALT"
  )
  # no #CHROM header at all
  path3 <- .write_io_fixture(c("##fileformat=VCFv4.2", "chr1\t100\t.\tA\tT"), ".vcf")
  expect_ms_error(
    ms_variants(path3, "GRCh38", caller = "c", matched_normal = "none"),
    "io", regexp = "#CHROM"
  )
  # truncated data line
  path4 <- .write_io_fixture(.vcf_fixture_lines(
    "chr1\t100\t.\tA"
  ), ".vcf")
  expect_ms_error(
    ms_variants(path4, "GRCh38", caller = "c", matched_normal = "none"),
    "io", regexp = "malformed"
  )
  # header-only VCF (no data lines)
  path5 <- .write_io_fixture(.vcf_fixture_lines(character(0)), ".vcf")
  expect_ms_error(
    ms_variants(path5, "GRCh38", caller = "c", matched_normal = "none"),
    "io", regexp = "no variant records"
  )
  # every allele skipped (symbolic only)
  path6 <- .write_io_fixture(.vcf_fixture_lines(
    "chr1\t100\t.\tA\t<NON_REF>\t.\tPASS\t."
  ), ".vcf")
  expect_ms_error(
    ms_variants(path6, "GRCh38", caller = "c", matched_normal = "none"),
    "io", regexp = "no variant records"
  )
})

test_that("BCF is rejected with an actionable message", {
  p1 <- .write_io_fixture(c("BCF\\2", "junk"), ".bcf")
  p2 <- .write_io_fixture(c("BCF\\2", "junk"), ".bcf", gz = TRUE)
  p3 <- .write_io_fixture(.vcf_fixture_lines(
    "chr1\t100\t.\tA\tT\t.\tPASS\t."
  ), ".vcf")
  on.exit(unlink(c(p1, p2, p3)))
  expect_ms_error(
    ms_variants(p1, "GRCh38", caller = "c", matched_normal = "none"),
    "unsupported", regexp = "bcftools"
  )
  expect_ms_error(
    ms_variants(p2, "GRCh38", caller = "c", matched_normal = "none"),
    "unsupported"
  )
  # explicit format = "bcf" on a VCF file is rejected the same way
  expect_ms_error(
    ms_variants(p3, "GRCh38",
      caller = "c", matched_normal = "none", format = "bcf"),
    "unsupported", regexp = "bcftools"
  )
})

# ---------------------------------------------------------------------
# TSV
# ---------------------------------------------------------------------

test_that("TSV reads with default column names and an explicit end column", {
  path <- .write_io_fixture(c(
    "chrom\tpos\tend\tref\talt",
    "chr1\t100\t100\tA\tT",
    "chr1\t200\t201\tCA\tC"
  ), ".tsv")
  on.exit(unlink(path))

  v <- ms_variants(path, "GRCh38", caller = "c", matched_normal = "none")
  expect_identical(v@table$start, c(100, 200))
  expect_identical(v@table$end, c(100, 201)) # from the file, not derived
  expect_null(v@table$filter)
})

test_that("TSV derives end from the reference width when absent", {
  path <- .write_io_fixture(c(
    "chrom\tpos\tref\talt",
    "chr1\t100\tA\tT"
  ), ".tsv")
  on.exit(unlink(path))
  v <- ms_variants(path, "GRCh38", caller = "c", matched_normal = "none")
  expect_identical(v@table$end, 100)
})

test_that("TSV column names are overridable and passthroughs map", {
  path <- .write_io_fixture(c(
    "seqnames\tposition\treference\talternative\tFILTER\ttumor_vaf",
    "chr7\t55191822\tC\tT\tPASS\t0.31",
    "chr17\t7676594\tCA\tC\t.\t0.12"
  ), ".tsv")
  on.exit(unlink(path))

  v <- ms_variants(path, "GRCh38",
    caller = "mutect2", matched_normal = "none",
    chrom_col = "seqnames", pos_col = "position",
    ref_col = "reference", alt_col = "alternative",
    filter_col = "FILTER", vaf_col = "tumor_vaf",
    vaf_floor = 0.05)
  expect_identical(v@table$chrom, c("chr7", "chr17"))
  expect_identical(v@table$end, c(55191822, 7676595))
  expect_identical(v@table$filter, c("PASS", "."))
  expect_identical(v@table$vaf, c(0.31, 0.12))
  expect_identical(v@provenance$vaf_floor, 0.05)
})

test_that("TSV uppercase repair happens at the io layer, bad alleles fail in the validator", {
  ok <- .write_io_fixture(c(
    "chrom\tpos\tref\talt",
    "chr1\t100\ta\tt"
  ), ".tsv")
  on.exit(unlink(ok))
  v <- ms_variants(ok, "GRCh38", caller = "c", matched_normal = "none")
  expect_identical(v@table$ref, "A")
  expect_identical(v@table$alt, "T")

  bad <- .write_io_fixture(c(
    "chrom\tpos\tref\talt",
    "chr1\t100\tA\tXYZ"
  ), ".tsv")
  expect_ms_error(
    ms_variants(bad, "GRCh38", caller = "c", matched_normal = "none"),
    "variants", regexp = "allele"
  )
  # NA coordinate: io-layer syntax check
  bad2 <- .write_io_fixture(c(
    "chrom\tpos\tref\talt",
    "chr1\tNA\tA\tT"
  ), ".tsv")
  expect_ms_error(
    ms_variants(bad2, "GRCh38", caller = "c", matched_normal = "none"),
    "io", regexp = "integer"
  )
  # missing required column with the default mapping
  bad3 <- .write_io_fixture(c(
    "chrom\tposition\tref\talt",
    "chr1\t100\tA\tT"
  ), ".tsv")
  expect_ms_error(
    ms_variants(bad3, "GRCh38", caller = "c", matched_normal = "none"),
    "io", regexp = "pos_col"
  )
  # requested passthrough column absent
  bad4 <- .write_io_fixture(c(
    "chrom\tpos\tref\talt",
    "chr1\t100\tA\tT"
  ), ".tsv")
  expect_ms_error(
    ms_variants(bad4, "GRCh38",
      caller = "c", matched_normal = "none", filter_col = "FILTER"),
    "io", regexp = "FILTER"
  )
  # header-only TSV
  bad5 <- .write_io_fixture("chrom\tpos\tref\talt", ".tsv")
  expect_ms_error(
    ms_variants(bad5, "GRCh38", caller = "c", matched_normal = "none"),
    "io", regexp = "no variant records"
  )
})

# ---------------------------------------------------------------------
# Ragged tables: msuiter_error_parse, never a bare simpleError
# ---------------------------------------------------------------------

test_that("a ragged TSV row is a structured msuiter_error_parse with the line number", {
  # A data line wider than the header: read.table fails before any ledger
  # logic runs; the error protocol (ARCH 3.5) requires msuiter_error_parse
  # instead of the bare simpleError read.table throws. The exact scan
  # message varies with the ragged shape (and across R versions), so only
  # the class, the payload and the file location are pinned here.
  wide <- .write_io_fixture(c(
    "chrom\tpos\tref\talt",
    "chr2\t200\tC\tG\textra",
    "chr1\t100\tA\tT"
  ), ".tsv")
  on.exit(unlink(wide), add = TRUE)
  err <- expect_ms_error(
    ms_variants(wide, "GRCh38", caller = "c", matched_normal = "none"),
    "parse"
  )
  expect_match(err$msuiter_error$j, basename(wide), fixed = TRUE)

  # A narrower data line: read.table reports a line number, which the
  # condition must surface in `i` ("offending data line: N").
  narrow <- .write_io_fixture(c(
    "chrom\tpos\tref\talt",
    "chr1\t100\tA"
  ), ".tsv")
  err2 <- expect_ms_error(
    ms_variants(narrow, "GRCh38", caller = "c", matched_normal = "none"),
    "parse", regexp = "offending data line"
  )
  expect_match(err2$msuiter_error$i, "[0-9]")

  # The same guard covers MAF tabular input.
  maf <- .write_io_fixture(c(
    "Chromosome\tStart_Position\tReference_Allele\tTumor_Seq_Allele2",
    "chr1\t100\tA\tT",
    "chr2\t200\tC\tG\tT\tExtra_Cols"
  ), ".maf")
  expect_ms_error(
    ms_variants(maf, "GRCh38", caller = "c", matched_normal = "none"),
    "parse"
  )
})

# ---------------------------------------------------------------------
# MAF
# ---------------------------------------------------------------------

test_that("MAF column mapping works and the skip ledger counts non-SBS rows", {
  path <- .write_io_fixture(c(
    "#version 2.4.1", # GDC-style preamble is dropped
    paste(c(
      "Chromosome", "Start_Position", "End_Position", "Reference_Allele",
      "Tumor_Seq_Allele2", "Variant_Classification"
    ), collapse = "\t"),
    "chr7\t55191822\t55191822\tC\tT\tMissense_Mutation",
    "chr13\t32316405\t32316406\tGA\tG\tFrame_Shift_Del",
    "chr17\t7676594\t7676594\t.\tA\tSilent",
    "chr1\t100\t100\tA\tT\tSplice_Site",
    "chr1\t200\t200\tC\tG\tMissense_Mutation"
  ), ".maf")
  on.exit(unlink(path))

  v <- ms_variants(path, "GRCh38", caller = "maf-caller", matched_normal = "none")
  expect_is_ms(v, "MsVariants")
  expect_identical(nrow(v@table), 2L)
  expect_identical(v@table$chrom, c("chr7", "chr1"))
  expect_identical(v@table$ref, c("C", "C"))
  expect_identical(v@table$alt, c("T", "G"))
  expect_identical(v@table$end, c(55191822, 200)) # End_Position honored

  p <- v@provenance$parse
  expect_identical(p$n_lines, 5L)
  expect_identical(p$n_records, 2L)
  expect_identical(p$n_skipped, 3L)
  # SPMG-aligned default filter: Silent and Splice_Site are classification
  # skips even when their allele fields would be usable (the chr17 row's
  # "." reference makes the point double: classification wins first).
  expect_identical(p$skip_reasons[["classification"]], 3L)
  expect_false("allele" %in% names(p$skip_reasons))
  expect_identical(p$skip_classifications[["Frame_Shift_Del"]], 1L)
  expect_identical(p$skip_classifications[["Silent"]], 1L)
  expect_identical(p$skip_classifications[["Splice_Site"]], 1L)
  expect_identical(v@provenance$format, "maf")
  expect_null(v@provenance$fileformat)
})

test_that("gzip-compressed MAF reads like its plain twin", {
  lines <- c(
    paste(c(
      "Chromosome", "Start_Position", "End_Position", "Reference_Allele",
      "Tumor_Seq_Allele2", "Variant_Classification"
    ), collapse = "\t"),
    "chr1\t100\t100\tA\tT\tMissense_Mutation"
  )
  plain <- .write_io_fixture(lines, ".maf")
  gz <- .write_io_fixture(lines, ".maf", gz = TRUE)
  on.exit(unlink(c(plain, gz)))
  v1 <- ms_variants(plain, "GRCh38", caller = "c", matched_normal = "none")
  v2 <- ms_variants(gz, "GRCh38", caller = "c", matched_normal = "none")
  expect_identical(v2@table, v1@table)
  expect_identical(v2@provenance$format, "maf")
})

# ---------------------------------------------------------------------
# Unrecognized files and unreadable paths
# ---------------------------------------------------------------------

test_that("unknown extensions are rejected, but format override rescues them", {
  p <- .write_io_fixture(c(
    "chrom\tpos\tref\talt",
    "chr1\t100\tA\tT"
  ), ".txt")
  on.exit(unlink(p))
  expect_ms_error(
    ms_variants(p, "GRCh38", caller = "c", matched_normal = "none"),
    "unsupported", regexp = "extension"
  )
  v <- ms_variants(p, "GRCh38",
    caller = "c", matched_normal = "none", format = "tsv")
  expect_identical(nrow(v@table), 1L)
})

test_that("missing files and directories raise io errors", {
  missing_path <- tempfile(fileext = ".vcf")
  expect_ms_error(
    ms_variants(missing_path, "GRCh38", caller = "c", matched_normal = "none"),
    "io", regexp = "does not exist"
  )
  expect_ms_error(
    ms_variants(tempdir(), "GRCh38", caller = "c", matched_normal = "none"),
    "io", regexp = "directory"
  )
})

test_that("corrupt gzip streams are wrapped into io errors", {
  p <- tempfile(fileext = ".vcf.gz")
  con <- file(p, "wb")
  writeLines(c("this is not gzip"), con, useBytes = TRUE)
  close(con)
  on.exit(unlink(p))
  expect_ms_error(
    ms_variants(p, "GRCh38", caller = "c", matched_normal = "none"),
    "io"
  )
})

# ---------------------------------------------------------------------
# data.frame direct construction + argument discipline
# ---------------------------------------------------------------------

test_that("data.frame path validates and carries somaticness provenance", {
  v <- ms_variants(.make_variants_table(), "GRCh38",
    caller = "synthetic-caller", matched_normal = "none")
  expect_is_ms(v, "MsVariants")
  expect_identical(v@provenance$caller, "synthetic-caller")
  expect_null(v@provenance$vaf_floor)

  v2 <- ms_variants(.make_variants_table(), "GRCh38",
    caller = "c", matched_normal = "N1", vaf_floor = 0.02)
  expect_identical(v2@provenance$vaf_floor, 0.02)

  # validator fires end to end on the direct path
  bad <- .make_variants_table()
  bad$alt[1] <- "X"
  expect_ms_error(
    ms_variants(bad, "GRCh38", caller = "c", matched_normal = "none"),
    "variants", regexp = "allele"
  )
  # optional passthrough columns survive on the direct path
  tab <- .make_variants_table()
  tab$filter <- c("PASS", ".", "PASS", ".", ".")
  tab$vaf <- c(0.1, 0.2, 0.3, 0.4, 0.5)
  v3 <- ms_variants(tab, "GRCh38", caller = "c", matched_normal = "none")
  expect_identical(v3@table$filter, tab$filter)
  expect_identical(v3@table$vaf, tab$vaf)
})

test_that("file-only arguments are rejected on the data.frame path", {
  expect_ms_error(
    ms_variants(.make_variants_table(), "GRCh38",
      caller = "c", matched_normal = "none", format = "vcf"),
    "input", regexp = "file"
  )
  expect_ms_error(
    ms_variants(.make_variants_table(), "GRCh38",
      caller = "c", matched_normal = "none", chrom_col = "chr"),
    "input", regexp = "chrom_col"
  )
})

test_that("missing required arguments and bad x dispatch raise input errors", {
  p <- .write_io_fixture(.vcf_fixture_lines(
    "chr1\t100\t.\tA\tT\t.\tPASS\t."
  ), ".vcf")
  on.exit(unlink(p))
  # dots discipline: no passthrough arguments, typos are rejected.
  # (R partial matching still applies before dispatch, so a misspelling
  # that is a prefix of a real formal -- e.g. `genom` -- is matched to
  # that formal by R itself; anything unmatched lands in `...` here.)
  expect_ms_error(
    ms_variants(p, "GRCh38",
      caller = "c", matched_normal = "none", unknown_arg = "x"),
    "input", regexp = "unknown_arg"
  )
  expect_ms_error(
    ms_variants(.make_variants_table(), "GRCh38",
      caller = "c", matched_normal = "none", junk = 1),
    "input", regexp = "junk"
  )
  expect_ms_error(ms_variants(p), "input", regexp = "genome")
  expect_ms_error(ms_variants(p, "GRCh38"), "input", regexp = "caller")
  expect_ms_error(
    ms_variants(p, "GRCh38", caller = "c"),
    "input", regexp = "matched"
  )
  expect_ms_error(
    ms_variants(c(p, p), "GRCh38", caller = "c", matched_normal = "none"),
    "input", regexp = "length"
  )
  expect_ms_error(
    ms_variants(matrix(1), "GRCh38", caller = "c", matched_normal = "none"),
    "input", regexp = "path"
  )
  expect_ms_error(
    ms_variants(1.5, "GRCh38", caller = "c", matched_normal = "none"),
    "input"
  )
})
