# Catalog assembly over the FFI (U-M1s-11): ms_tally() end to end.
#
# The Rust-side semantics are pinned byte-exactly at the FFI layer
# (test-ffi-tally.R); this file pins the ASSEMBLY layer: the MsVariants ->
# `.ms_tally_rust` -> MsCatalog pipeline must be lossless (counts identical,
# label-matched dimnames), the strand policy must match sbs.rs (SBS192 never
# degrades, SBS384 defaults to N, other modes ignore strand), and the
# provenance must carry the genome path, mode, ledger and counters plus the
# variants' own somaticness fields.

# ---------------------------------------------------------------------------
# Golden batch, end to end
# ---------------------------------------------------------------------------

test_that("ms_tally replays the golden batch losslessly for every mode", {
  path <- .tally_write_2bit(file.path(tempdir(), "cat-tally-golden.2bit"))
  on.exit(unlink(path), add = TRUE)
  v <- ms_variants(.tally_golden_table(), "GRCh38-test",
    caller = "synthetic", matched_normal = "none"
  )
  d <- .tally_golden_records()

  for (mode in c("SBS96", "SBS192", "SBS384", "SBS1536", "DBS78")) {
    cat1 <- ms_tally(v, path, mode = mode)
    expect_is_ms(cat1, "MsCatalog")

    # Assembly must be lossless: identical to a direct FFI call with the
    # same records and the strand the layer passes for this mode (the real
    # codes for the transcription modes, N otherwise).
    ref <- .ms_tally_rust(path,
      chrom = d$chrom, pos = d$pos, ref_ = d$ref_, alt = d$alt,
      sample = d$sample,
      strand = if (mode %in% c("SBS192", "SBS384")) d$strand else rep("N", nrow(d)),
      want_sbs96 = mode == "SBS96", want_sbs192 = mode == "SBS192",
      want_sbs384 = mode == "SBS384", want_sbs1536 = mode == "SBS1536",
      want_dbs78 = mode == "DBS78"
    )
    key <- switch(mode,
      SBS96 = "sbs96", SBS192 = "sbs192", SBS384 = "sbs384",
      SBS1536 = "sbs1536", DBS78 = "dbs78"
    )
    expect_identical(cat1@counts, ref[[key]])

    # Dimnames: rows in canonical registry order, columns in first-appearance
    # sample order -- matched by label, never by position.
    expect_identical(rownames(cat1@counts), .tally_channel_tables()[[mode]]$labels)
    expect_identical(colnames(cat1@counts), c("S2", "S1"))
    expect_identical(cat1@samples, c("S2", "S1"))
    expect_identical(cat1@channels$name, mode)
    expect_identical(cat1@channels$labels, .tally_channel_tables()[[mode]]$labels)
  }
})

test_that("hand-derived count cells survive the assembly (SBS96/SBS192/DBS78)", {
  path <- .tally_write_2bit(file.path(tempdir(), "cat-tally-cells.2bit"))
  on.exit(unlink(path), add = TRUE)
  v <- ms_variants(.tally_golden_table(), "GRCh38-test",
    caller = "synthetic", matched_normal = "none"
  )
  sbs96 <- ms_tally(v, path, mode = "SBS96")@counts
  expect_identical(sum(sbs96), 5L)
  expect_identical(sbs96["A[C>A]A", "S1"], 1L) # chr1 11 C>A
  expect_identical(sbs96["G[T>C]G", "S2"], 1L) # chr1 16 A>G (U flip)
  expect_identical(sbs96["A[C>G]A", "S2"], 1L) # chr1 27 C>G (B strand)
  expect_identical(sbs96["A[C>T]A", "S1"], 0L) # DBS pair never in SBS

  sbs192 <- ms_tally(v, path, mode = "SBS192")@counts
  expect_identical(sum(sbs192), 3L) # N/B strands have no 192 channel
  expect_identical(sbs192["T:A[C>A]A", "S1"], 1L)
  expect_identical(sbs192["T:G[T>C]G", "S2"], 1L)

  dbs78 <- ms_tally(v, path, mode = "DBS78")@counts
  expect_identical(sum(dbs78), 2L)
  expect_identical(dbs78["CG>AT", "S2"], 1L) # chr2 33/34
  expect_identical(dbs78["TG>CA", "S1"], 1L) # chr1 21/22 (reversed input)
})

# ---------------------------------------------------------------------------
# Strand policy (sbs.rs: SBS192 never degrades)
# ---------------------------------------------------------------------------

test_that("SBS192 without a strand column is a structured error, not a fallback", {
  path <- .tally_write_2bit(file.path(tempdir(), "cat-tally-192.2bit"))
  on.exit(unlink(path), add = TRUE)
  tab <- .tally_golden_table()[, c("chrom", "start", "end", "ref", "alt", "sample")]
  v <- ms_variants(tab, "GRCh38-test",
    caller = "synthetic", matched_normal = "none"
  )
  expect_ms_error(ms_tally(v, path, mode = "SBS192"), "input", regexp = "strand")
})

test_that("SBS384 without a strand column defaults to N (documented)", {
  path <- .tally_write_2bit(file.path(tempdir(), "cat-tally-384.2bit"))
  on.exit(unlink(path), add = TRUE)
  tab <- .tally_golden_table()[, c("chrom", "start", "end", "ref", "alt", "sample")]
  v <- ms_variants(tab, "GRCh38-test",
    caller = "synthetic", matched_normal = "none"
  )
  cat1 <- ms_tally(v, path, mode = "SBS384")
  d <- .tally_golden_records()
  ref <- .ms_tally_rust(path,
    chrom = d$chrom, pos = d$pos, ref_ = d$ref_, alt = d$alt,
    sample = d$sample, strand = rep("N", nrow(d)),
    want_sbs384 = TRUE
  )
  expect_identical(cat1@counts, ref$sbs384)
  expect_identical(cat1@provenance$ledger, ref$ledger)
  expect_identical(cat1@provenance$n_skipped, 11L)
  expect_identical(sum(cat1@counts), 5L)
})

test_that("non-transcription modes ignore the strand column", {
  path <- .tally_write_2bit(file.path(tempdir(), "cat-tally-ignore.2bit"))
  on.exit(unlink(path), add = TRUE)
  v <- ms_variants(.tally_golden_table(), "GRCh38-test",
    caller = "synthetic", matched_normal = "none"
  )
  d <- .tally_golden_records()
  ref <- .ms_tally_rust(path,
    chrom = d$chrom, pos = d$pos, ref_ = d$ref_, alt = d$alt,
    sample = d$sample, strand = rep("N", nrow(d)),
    want_sbs96 = TRUE
  )
  cat1 <- ms_tally(v, path, mode = "SBS96") # strand column present, ignored
  expect_identical(cat1@counts, ref$sbs96)
  expect_identical(cat1@provenance$ledger, .tally_golden_ledger())
})

# ---------------------------------------------------------------------------
# Mode validation
# ---------------------------------------------------------------------------

test_that("an illegal mode lists every legal value", {
  path <- .tally_write_2bit(file.path(tempdir(), "cat-tally-mode.2bit"))
  on.exit(unlink(path), add = TRUE)
  v <- ms_variants(.tally_golden_table(), "GRCh38-test",
    caller = "synthetic", matched_normal = "none"
  )
  expect_ms_error(
    ms_tally(v, path, mode = "SBS288"),
    "input"
  ) |>
    (\(err) {
      msg <- conditionMessage(err)
      for (legal in c("SBS96", "SBS192", "SBS384", "SBS1536", "DBS78")) {
        expect_match(msg, legal, fixed = TRUE, info = "illegal mode must list every legal value")
      }
    })()
})

# ---------------------------------------------------------------------------
# Empty input: a legal, all-zero catalog
# ---------------------------------------------------------------------------

test_that("empty variants: a legal all-zero MsCatalog, SBS192 needs no strand", {
  path <- .tally_write_2bit(file.path(tempdir(), "cat-tally-empty.2bit"))
  on.exit(unlink(path), add = TRUE)
  empty <- .tally_golden_table()[0L, , drop = FALSE]
  v <- ms_variants(empty, "GRCh38-test",
    caller = "synthetic", matched_normal = "none"
  )

  # The assembly layer routes an empty queue cleanly: the FFI returns the
  # all-zero channels x 0 matrix and ms_tally() hands it to ms_catalog()
  # with samples = character(0).
  d0 <- list(chrom = character(0), pos = numeric(0), ref_ = character(0),
    alt = character(0), sample = character(0))
  res <- .ms_tally_rust(path,
    chrom = d0$chrom, pos = d0$pos, ref_ = d0$ref_, alt = d0$alt,
    sample = d0$sample, strand = character(0), want_sbs96 = TRUE
  )
  expect_identical(dim(res$sbs96), c(96L, 0L))
  expect_identical(res$ledger, "")

  # Flipped (U-M1s-11 audit P3): the catalog validator now treats the
  # zero-column matrix's inevitable NULL colnames as character(0), so the
  # empty queue CONSTRUCTS an all-zero MsCatalog instead of erroring.
  cat0 <- ms_tally(v, path, mode = "SBS96")
  expect_is_ms(cat0, "MsCatalog")
  expect_identical(dim(cat0@counts), c(96L, 0L))
  expect_identical(rownames(cat0@counts), .tally_channel_tables()$SBS96$labels)
  expect_identical(colnames(cat0@counts), NULL) # base R: NULL == character(0)
  expect_identical(cat0@samples, character(0))
  expect_identical(cat0@channels$name, "SBS96")
  expect_identical(cat0@provenance$ledger, "")
  expect_identical(cat0@provenance$n_variants, 0L)
  expect_identical(cat0@provenance$n_skipped, 0L)

  # The strand-exemption branch is reachable: an empty queue carries no
  # annotation, so SBS192 must NOT demand a strand column (n == 0 short-
  # circuits the mode policy) and lands as the 192 x 0 all-zero catalog.
  cat192 <- ms_tally(v, path, mode = "SBS192")
  expect_is_ms(cat192, "MsCatalog")
  expect_identical(dim(cat192@counts), c(192L, 0L))
  expect_identical(rownames(cat192@counts), .tally_channel_tables()$SBS192$labels)
  expect_identical(cat192@samples, character(0))
})

# ---------------------------------------------------------------------------
# Provenance: genome path, mode, ledger, counters, variants passthrough
# ---------------------------------------------------------------------------

test_that("provenance carries tally context and the variants' somaticness fields", {
  path <- .tally_write_2bit(file.path(tempdir(), "cat-tally-prov.2bit"))
  on.exit(unlink(path), add = TRUE)
  v <- ms_variants(.tally_golden_table(), "GRCh38-test",
    caller = "mutect2-synthetic", matched_normal = "NORMAL1", vaf_floor = 0.05
  )
  cat1 <- ms_tally(v, path, mode = "SBS96")

  expect_identical(cat1@provenance$genome, "GRCh38-test") # build label
  expect_identical(cat1@provenance$genome_path, path) # 2bit reference used
  expect_identical(cat1@provenance$mode, "SBS96")
  expect_identical(cat1@provenance$caller, "mutect2-synthetic") # passthrough
  expect_identical(cat1@provenance$matched_normal, "NORMAL1") # passthrough
  expect_identical(cat1@provenance$vaf_floor, 0.05) # passthrough
  expect_identical(cat1@provenance$n_variants, 22L)
  expect_identical(cat1@provenance$n_skipped, 11L)

  # Ledger is the byte-exact per-record TSV (one line per input record,
  # switch-independent); its `skipped:` destinations account for n_skipped.
  expect_identical(cat1@provenance$ledger, .tally_golden_ledger())
  ledger_lines <- strsplit(cat1@provenance$ledger, "\n", fixed = TRUE)[[1L]]
  expect_identical(length(ledger_lines), cat1@provenance$n_variants)
  expect_identical(sum(grepl("\tskipped:", ledger_lines, fixed = TRUE)), 11L)
})

test_that("two tallies of the same input agree on the derived channel hash", {
  path <- .tally_write_2bit(file.path(tempdir(), "cat-tally-hash.2bit"))
  on.exit(unlink(path), add = TRUE)
  v <- ms_variants(.tally_golden_table(), "GRCh38-test",
    caller = "synthetic", matched_normal = "none"
  )
  a <- ms_tally(v, path, mode = "SBS96")
  b <- ms_tally(v, path, mode = "SBS96")
  expect_identical(a@channels$hash, b@channels$hash)
  expect_identical(a@channels$hash, msuiter_hash_labels(a@channels$labels))
  expect_true(grepl("^[0-9a-f]{32}$", a@channels$hash))
})

# U-M1s-11 audit P3: the hash pins the channel table, so two tallies of the
# SAME input under DIFFERENT modes must never share one (dimension + label
# digest differ; a collision here would let a DBS78 catalog pass an SBS96
# snapshot check).
test_that("different labels across modes give different channel hashes", {
  path <- .tally_write_2bit(file.path(tempdir(), "cat-tally-hash-xmode.2bit"))
  on.exit(unlink(path), add = TRUE)
  v <- ms_variants(.tally_golden_table(), "GRCh38-test",
    caller = "synthetic", matched_normal = "none"
  )
  sbs96 <- ms_tally(v, path, mode = "SBS96")
  dbs78 <- ms_tally(v, path, mode = "DBS78")
  expect_false(identical(sbs96@channels$labels, dbs78@channels$labels))
  expect_false(identical(sbs96@channels$hash, dbs78@channels$hash))
})

# ---------------------------------------------------------------------------
# Argument discipline
# ---------------------------------------------------------------------------

test_that("unknown arguments are spelling errors, never ignored values", {
  path <- .tally_write_2bit(file.path(tempdir(), "cat-tally-dots.2bit"))
  on.exit(unlink(path), add = TRUE)
  v <- ms_variants(.tally_golden_table(), "GRCh38-test",
    caller = "synthetic", matched_normal = "none"
  )
  expect_ms_error(ms_tally(v, path, mode = "SBS96", motif = 1L), "input")
})

test_that("variants must be an MsVariants object (structured fallback)", {
  path <- .tally_write_2bit(file.path(tempdir(), "cat-tally-fallback.2bit"))
  on.exit(unlink(path), add = TRUE)
  expect_ms_error(ms_tally(.tally_golden_table(), path), "input", regexp = "MsVariants")
  expect_ms_error(ms_tally(42, path), "input")
})

test_that("the genome path must be an existing 2bit file", {
  v <- ms_variants(.tally_golden_table(), "GRCh38-test",
    caller = "synthetic", matched_normal = "none"
  )
  expect_ms_error(ms_tally(v, file.path(tempdir(), "no-such.2bit")), "io")
  expect_ms_error(ms_tally(v, NA_character_), "input")
  expect_ms_error(ms_tally(v, c("a.2bit", "b.2bit")), "input")
})

# ---------------------------------------------------------------------------
# Default sample attribution
# ---------------------------------------------------------------------------

test_that("a table without a sample column lands in one canonical sample", {
  path <- .tally_write_2bit(file.path(tempdir(), "cat-tally-sample.2bit"))
  on.exit(unlink(path), add = TRUE)
  tab <- .tally_golden_table()[, c("chrom", "start", "end", "ref", "alt")]
  v <- ms_variants(tab, "GRCh38-test",
    caller = "synthetic", matched_normal = "none"
  )
  cat1 <- ms_tally(v, path, mode = "SBS96")
  expect_identical(cat1@samples, "sample")
  expect_identical(colnames(cat1@counts), "sample")

  d <- .tally_golden_records()
  ref <- .ms_tally_rust(path,
    chrom = d$chrom, pos = d$pos, ref_ = d$ref_, alt = d$alt,
    sample = rep("sample", nrow(d)), strand = rep("N", nrow(d)),
    want_sbs96 = TRUE
  )
  expect_identical(cat1@counts, ref$sbs96)
})
