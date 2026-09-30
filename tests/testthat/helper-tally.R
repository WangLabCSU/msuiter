# Shared tally fixtures (U-M1s-11, folded onto test-ffi-tally.R by
# U-M1s-13): the hand-derived 22-record golden batch and the little-endian
# 2bit writer. Originally written for the FFI-layer test (test-ffi-tally.R,
# U-M1s-09); the catalog assembly tests (test-catalog-tally.R) and the FFI
# tests now both consume THESE definitions -- the FFI file's private copies
# are gone (single source, byte-identical content preserved).
#
# Fixture genome (identical content to the Rust golden, src/rust/src/tally.rs):
#   chr1: ACAC... (64 bp), N block at 0-based 50..52
#   chr2: GCGC... (40 bp)
# 2bit packing: T=0 C=1 A=2 G=3, first base in the high bits.

.tally_u32le <- function(v) {
  writeBin(as.integer(v), raw(), size = 4L, endian = "little")
}

# 2-bit packing: T=0 C=1 A=2 G=3, first base in the high bits.
.tally_pack_bases <- function(bases) {
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

# Serialize complete chromosome records into little-endian 2bit bytes.
.tally_2bit_bytes <- function(recs) {
  off <- 16L + sum(vapply(recs, function(r) 1L + nchar(r$name) + 4L, 0L))
  index <- raw()
  body <- raw()
  for (r in recs) {
    index <- c(index, as.raw(nchar(r$name)), charToRaw(r$name), .tally_u32le(off))
    rec <- c(
      .tally_u32le(r$size), .tally_u32le(length(r$nb)),
      .tally_u32le(r$nb), .tally_u32le(r$nl), # empty raw() when no N blocks
      .tally_u32le(0L), .tally_u32le(0L), r$dna
    )
    body <- c(body, rec)
    off <- off + length(rec)
  }
  c(.tally_u32le(0x1A412743), .tally_u32le(0L), .tally_u32le(length(recs)),
    .tally_u32le(0L), index, body)
}

.tally_write_bytes <- function(path, bytes) {
  con <- file(path, "wb")
  on.exit(close(con), add = TRUE)
  writeBin(bytes, con)
  invisible(path)
}

.tally_write_2bit <- function(path) {
  chr1 <- rep(c(2L, 1L), 32L) # A C A C ...
  chr1[51L:53L] <- 0L # N block (0-based 50..52), packed as zeros
  chr2 <- rep(c(3L, 1L), 20L) # G C G C ...
  recs <- list(
    list(name = "chr1", size = 64L, dna = .tally_pack_bases(chr1), nb = 50L, nl = 3L),
    list(name = "chr2", size = 40L, dna = .tally_pack_bases(chr2), nb = integer(0), nl = integer(0))
  )
  .tally_write_bytes(path, .tally_2bit_bytes(recs))
}

# Single 48 bp chromosome of C's with an A-run of 2 at 1-based 5..6
# (0-based 4..5) and an A-run of 4 at 1-based 13..16 (0-based 12..15):
# bounded tandem runs so 1 bp indel walks extend mid-table — the
# all-alternating golden genome can never extend a 1 bp walk. Content
# identical to the Rust run fixture (src/rust/src/tally.rs).
.tally_write_2bit_run <- function(path) {
  chrR <- rep(1L, 48L) # C C C C ...
  chrR[5L:6L] <- 2L # A A
  chrR[13L:16L] <- 2L # A A A A
  recs <- list(
    list(name = "chrR", size = 48L, dna = .tally_pack_bases(chrR), nb = integer(0), nl = integer(0))
  )
  .tally_write_bytes(path, .tally_2bit_bytes(recs))
}

# The hand-derived golden batch (0-based positions of the Rust golden + 1):
# plain SNVs in two samples, adjacent DBS pairs on both chromosomes (one
# with reversed input order), strand T/U/B/N records, an adjacent
# insertion+deletion pair that SPMG keeps independent (indels are never
# merged into a block substitution; SPMG pairs SNV records only), a 6 bp
# long MNV, +/-2-window N skips, an N-dinucleotide DBS candidate, a
# REF-vs-genome mismatch, head and tail context-bounds skips, three simple
# indels (records 9/10 counted into ID83; record 15 anchor-mismatched
# against the fixture genome), a complex indel and an unknown chromosome.
# Sample columns: "S2" first appears at record 1, "S1" at record 3 ->
# tally columns c("S2", "S1").
.tally_golden_records <- function() {
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

# The same batch as a canonical MsVariants table: chrom / start / end / ref /
# alt plus the optional passthrough columns `sample` and `strand` (the tally
# layer reads them as annotations on top of the canonical five).
.tally_golden_table <- function() {
  d <- .tally_golden_records()
  data.frame(
    chrom = d$chrom,
    start = d$pos,
    end = d$pos + nchar(d$ref_) - 1L,
    ref = d$ref_,
    alt = d$alt,
    sample = d$sample,
    strand = d$strand,
    stringsAsFactors = FALSE
  )
}

# Byte-exact golden ledger: one "record TAB destination" line per input
# record, in input order (FFI contract; switch-independent).
#
# U-M1c ID83 wiring flip, hand-re-derived record by record (fixture genome
# chr1 = A C A C ..., 0-based even = A):
# * rec 9  (chr1 33 AC>G, anchor A@0-based 32): 1 bp del of C@33; left
#   window [32,33) = "A" and right window [34,35) = "A" both mismatch ->
#   zero walk extension -> key4 = 0 -> 1:Del:C:0 -> destination `id83`;
# * rec 10 (chr1 32 C>TA, anchor C@0-based 31): 1 bp ins of A after the
#   anchor (the anchor is alt's first base T; the inserted base is A);
#   left window [31,32) = "C" mismatches, right window [32,33) = "A"
#   matches -> 1 extension -> key4 = 1 -> 1:Ins:T:1 -> `id83`;
# * rec 15 (chr1 57 CA>C): the record's anchor byte is 'C' but the genome
#   holds 'A' at 0-based 56 (SPMG :1408-1421) -> the interim shim never
#   ran this check; real semantics surface it as
#   skipped:indel_anchor_mismatch (memo §9.1 re-evaluation).
# n_skipped: 11 -> 9 (records 9/10 leave the skip bucket, 15 stays a skip
# under a new code).
.tally_golden_ledger <- function() {
  lines <- paste0(
    c(
      "1\tdbs", "2\tdbs", "3\tsbs", "4\tsbs", "5\tdbs", "6\tdbs",
      "7\tsbs", "8\tsbs", "9\tid83",
      "10\tid83", "11\tskipped:ref_mismatch",
      "12\tlong_mnv", "13\tskipped:n_context", "14\tskipped:n_context",
      "15\tskipped:indel_anchor_mismatch", "16\tcomplex_indel",
      "17\tskipped:context_bounds", "18\tskipped:context_bounds",
      "19\tskipped:unknown_chrom", "20\tsbs", "21\tskipped:n_dinuc",
      "22\tskipped:n_dinuc"
    ),
    collapse = "\n"
  )
  paste0(lines, "\n")
}

.tally_channel_tables <- function() {
  get("channel_tables", envir = asNamespace("msuiter"))
}
