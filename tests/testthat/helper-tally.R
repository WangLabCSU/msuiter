# Shared tally fixtures (U-M1s-11): the hand-derived 22-record golden batch
# and the little-endian 2bit writer, originally written for the FFI-layer
# test (test-ffi-tally.R, U-M1s-09). That file keeps its private copy (it is
# outside the U-M1s-11 edit scope); this helper is the version the catalog
# assembly tests build on. The two copies must stay byte-compatible until a
# later dedupe pass folds test-ffi-tally.R onto this helper.
#
# Fixture genome (identical content to the Rust golden, src/rust/src/tally.rs):
#   chr1: ACAC... (64 bp), N block at 0-based 50..52
#   chr2: GCGC... (40 bp)
# 2bit packing: T=0 C=1 A=2 G=3, first base in the high bits.

.tally_write_2bit <- function(path) {
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
# with reversed input order), strand T/U/B/N records, a split 3 bp block
# substitution reconnected from two pieces, a 6 bp long MNV, +/-2-window N
# skips, an N-dinucleotide DBS candidate, a REF-vs-genome mismatch, head
# and tail context-bounds skips, a simple indel, a complex indel and an
# unknown chromosome. Sample columns: "S2" first appears at record 1, "S1"
# at record 3 -> tally columns c("S2", "S1").
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
.tally_golden_ledger <- function() {
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

.tally_channel_tables <- function() {
  get("channel_tables", envir = asNamespace("msuiter"))
}
