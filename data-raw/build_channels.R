#!/usr/bin/env Rscript
# Single source of truth for the msuiter channel registry (U-M0-05).
#
# Generates two artifacts from the same in-memory derivation, in one pass:
#   1. R/sysdata.rda          internal data object `channel_tables`
#   2. src/rust/catalog/src/channels.rs  Rust `pub const` label arrays
#
# Both must stay bit-identical in canonical order. R/Rust sync is asserted by
# tests/testthat/test-channels-sync.R; Rust-side structure by
# src/rust/catalog/tests/channels.rs.
#
# Run:  Rscript data-raw/build_channels.R
# The script is deterministic and idempotent: no timestamps, no randomness,
# no network. Re-running it on a clean tree must produce byte-identical
# outputs.
#
# Canonical order provenance
# --------------------------
# docs/research/04 section 1 (SigProfilerMatrixGenerator audit) is the gold
# standard for SPMG channel semantics; docs/research/05 section 2 fixes the
# canonical label lists. The audited rules, verified against
# SigProfilerMatrixGeneratorFunc.py (master index construction, tsb /
# bias_sort) and the shipped BRCA_bench example matrices:
#
#   * SBS96    flank5 (A,C,G,T) x 6 substitution classes
#              (C>A, C>G, C>T, T>A, T>C, T>G) x flank3 (A,C,G,T), i.e.
#              ASCII lexicographic order of the label "F5[REF>ALT]F3" with
#              pyrimidine (C/T) reference bases. First "A[C>A]A",
#              last "T[T>G]T".
#   * SBS192   96 x {T, U} transcriptional strand states (transcribed /
#              untranscribed), label "<S>:<SBS96 label>", T block first
#              (docs/research/05 section 2, "SBS192 = 96 x {T,U}").
#   * SBS384   96 x {T, U, B, N} in SPMG bias_sort order
#              (bias_sort = {T:0, U:1, B:2, N:3}), same label grammar.
#   * SBS1536  pentanucleotide labels "O1I5[REF>ALT]I3O2", ASCII
#              lexicographic; first "AA[C>A]AA", last "TT[T>G]TT".
#   * DBS78    10 canonical reference dinucleotides
#              {AC, AT, CC, CG, CT, GC, TA, TC, TG, TT} x fixed alt sets,
#              ASCII lexicographic overall; first "AC>CA", last "TT>GG".
#              Pyrimidine-start refs (CC/CT/TC/TT) and mixed refs (AC/TG)
#              carry 9 alts (both positions change); self-reverse-complement
#              refs (AT/CG/GC/TA) carry 6 alts after SPMG's alt folding
#              (fold choices pinned below to the upstream constants).
#
# Licensing note
# --------------
# No COSMIC or SigProfiler data files are downloaded, cached or bundled by
# this script (data-raw/reference/ is intentionally absent). COSMIC terms
# formally prohibit redistribution of COSMIC data and the residual gap is
# flagged as legally ambiguous in docs/research/05 section 1; per project
# policy we err on the conservative side. All labels are generated
# programmatically from the audited structural rules above and validated by
# in-script structural assertions.

# ---------------------------------------------------------------------------
# Repo paths (script is location-independent when run via Rscript)
# ---------------------------------------------------------------------------
.script_path <- local({
  a <- commandArgs(FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f) > 0L) normalizePath(f[1]) else ""
})
.repo_root <- if (nzchar(.script_path)) {
  dirname(dirname(.script_path))
} else {
  normalizePath(".")
}

# ---------------------------------------------------------------------------
# Shared alphabet and SPMG strand semantics
# ---------------------------------------------------------------------------
.bases <- c("A", "C", "G", "T")

.sbs_classes <- c("C>A", "C>G", "C>T", "T>A", "T>C", "T>G")

# SPMG transcription-strand encoding (SigProfilerMatrixGeneratorFunc.py):
# bias_sort = {T:0, U:1, N:3, B:2, Q:4}; sorted strand order is T, U, B, N.
.strand_states <- c(
  T = "transcribed",
  U = "untranscribed",
  B = "bidirectional",
  N = "non-transcribed"
)
.strand_order_192 <- c("T", "U")
.strand_order_384 <- c("T", "U", "B", "N")

# Reverse complement of a two-base string.
.revcompl_dinuc <- function(d) {
  comp <- c(A = "T", C = "G", G = "C", T = "A")
  paste0(comp[substr(d, 2L, 2L)], comp[substr(d, 1L, 1L)])
}

# ---------------------------------------------------------------------------
# Structural assertions (fail the build loudly; D5: zero silent drift)
# ---------------------------------------------------------------------------
.assert <- function(condition, msg) {
  if (!isTRUE(condition)) {
    stop("build_channels.R structural assertion failed: ", msg, call. = FALSE)
  }
  invisible(TRUE)
}

.assert_labels <- function(labels, n, pattern, what) {
  .assert(is.character(labels) && length(labels) == n,
          sprintf("%s: expected %d labels, got %d", what, n, length(labels)))
  .assert(!anyNA(labels) && all(nzchar(labels)),
          sprintf("%s: empty or NA labels", what))
  .assert(anyDuplicated(labels) == 0L, sprintf("%s: duplicate labels", what))
  .assert(all(grepl(pattern, labels)), sprintf("%s: pattern mismatch", what))
}

# ---------------------------------------------------------------------------
# SBS96 (flank-major, ASCII lexicographic == flank5 x class x flank3)
# ---------------------------------------------------------------------------
.build_sbs96 <- function() {
  grid <- expand.grid(flank3 = .bases, class = .sbs_classes, flank5 = .bases,
                      stringsAsFactors = FALSE)
  grid <- grid[order(grid$flank5, grid$class, grid$flank3), ]
  labels <- with(grid, paste0(flank5, "[", class, "]", flank3))
  labels <- sort(labels) # canonical order == ASCII lexicographic of label

  .assert_labels(labels, 96L, "^[ACGT]\\[[ACGT]>[ACGT]\\][ACGT]$", "SBS96")
  .assert(labels[1] == "A[C>A]A" && labels[96] == "T[T>G]T",
          "SBS96 anchor labels drifted")

  dec <- data.frame(
    label = labels,
    flank5 = substr(labels, 1L, 1L),
    ref = substr(labels, 3L, 3L),
    alt = substr(labels, 5L, 5L),
    flank3 = substr(labels, 7L, 7L),
    stringsAsFactors = FALSE
  )
  .assert(all(dec$ref %in% c("C", "T")), "SBS96: non-pyrimidine reference")
  .assert(all(table(paste(dec$flank5, dec$ref, dec$alt, sep = "|")) == 4L),
          "SBS96: expected 4 flank3 per (flank5, class)")
  list(name = "SBS96", labels = labels, n = 96L,
       pattern = "^[ACGT]\\[[ACGT]>[ACGT]\\][ACGT]$",
       strand_states = NULL, decomposition = dec)
}

# ---------------------------------------------------------------------------
# SBS192 / SBS384 (stranded SBS96 blocks in SPMG bias_sort order)
# ---------------------------------------------------------------------------
.build_sbs_tsb <- function(strands, what) {
  sbs96 <- .build_sbs96()
  labels <- unlist(lapply(strands, function(s) paste0(s, ":", sbs96$labels)),
                   use.names = FALSE)
  n <- 96L * length(strands)
  pattern <- "^[TUNB]:[ACGT]\\[[ACGT]>[ACGT]\\][ACGT]$"
  .assert_labels(labels, n, pattern, what)

  dec <- data.frame(
    label = labels,
    strand = substr(labels, 1L, 1L),
    strand_state = unname(.strand_states[substr(labels, 1L, 1L)]),
    flank5 = substr(labels, 3L, 3L),
    ref = substr(labels, 5L, 5L),
    alt = substr(labels, 7L, 7L),
    flank3 = substr(labels, 9L, 9L),
    stringsAsFactors = FALSE
  )
  .assert(all(dec$strand %in% strands), sprintf("%s: strand block drift", what))
  .assert(all(vapply(strands, function(s) {
    idx <- dec$strand == s
    identical(substr(dec$label[idx], 3L, nchar(dec$label[idx])), sbs96$labels)
  }, logical(1))), sprintf("%s: strand blocks must repeat SBS96 order", what))

  list(name = what, labels = labels, n = n, pattern = pattern,
       strand_states = unname(.strand_states[strands]), decomposition = dec)
}

# ---------------------------------------------------------------------------
# SBS1536 (pentanucleotide, ASCII lexicographic; projects onto SBS96)
# ---------------------------------------------------------------------------
.build_sbs1536 <- function() {
  grid <- expand.grid(outer3 = .bases, inner3 = .bases, alt = .bases,
                      ref = c("C", "T"), inner5 = .bases, outer5 = .bases,
                      stringsAsFactors = FALSE)
  grid <- grid[grid$alt != grid$ref, ]
  labels <- with(grid, paste0(outer5, inner5, "[", ref, ">", alt, "]",
                              inner3, outer3))
  labels <- sort(labels) # canonical order == ASCII lexicographic of label

  .assert_labels(labels, 1536L,
                 "^[ACGT]{2}\\[[ACGT]>[ACGT]\\][ACGT]{2}$", "SBS1536")
  .assert(labels[1] == "AA[C>A]AA" && labels[1536] == "TT[T>G]TT",
          "SBS1536 anchor labels drifted")

  dec <- data.frame(
    label = labels,
    outer5 = substr(labels, 1L, 1L),
    inner5 = substr(labels, 2L, 2L),
    ref = substr(labels, 4L, 4L),
    alt = substr(labels, 6L, 6L),
    inner3 = substr(labels, 8L, 8L),
    outer3 = substr(labels, 9L, 9L),
    stringsAsFactors = FALSE
  )
  # Lossless coarse-graining: dropping the outer bases recovers SBS96.
  projection <- sort(unique(substr(labels, 2L, 8L)))
  .assert(identical(projection, .build_sbs96()$labels),
          "SBS1536: projection onto SBS96 is not the SBS96 label set")
  list(name = "SBS1536", labels = labels, n = 1536L,
       pattern = "^[ACGT]{2}\\[[ACGT]>[ACGT]\\][ACGT]{2}$",
       strand_states = NULL, decomposition = dec)
}

# ---------------------------------------------------------------------------
# DBS78 (10 canonical refs x SPMG alt sets, ASCII lexicographic)
# ---------------------------------------------------------------------------
# Canonical reference dinucleotides (docs/research/05 section 2): the
# pyrimidine-start refs (CC/CT/TC/TT, strand-unambiguous), the two mixed
# refs (AC/TG, chosen from the revcompl pairs {AC,GT}/{CA,TG}) and the four
# self-reverse-complement refs (AT/CG/GC/TA, SPMG "Q" strand-ambiguous
# family; docs/research/04 section 1, dinuc_tsb_ref normalization).
.dbs_refs <- c("AC", "AT", "CC", "CG", "CT", "GC", "TA", "TC", "TG", "TT")

# SPMG-pinned fold choices for Q-type refs: within each alt pair
# {NZ, revcompl(NZ)} the upstream constant list keeps exactly the alt below
# (SigProfilerMatrixGeneratorFunc.py, mutation_types_non_tsb). Self-revcomp
# alts are always kept.
.dbs_fold_keep <- list(
  AT = c("CA", "CC", "GA"),
  CG = c("TT", "GT", "TC"),
  GC = c("AA", "AG", "CA"),
  TA = c("GT", "CT", "GG")
)

# Upstream SPMG constants (SigProfilerMatrixGeneratorFunc.py lines 200-276:
# mutation_types + mutation_types_non_tsb). Used only as an assertion target
# for the derivation below; not the generation source.
.dbs78_upstream_expected <- c(
  "CC>AA", "CC>AG", "CC>AT", "CC>GA", "CC>GG", "CC>GT", "CC>TA", "CC>TG", "CC>TT",
  "CT>AA", "CT>AC", "CT>AG", "CT>GA", "CT>GC", "CT>GG", "CT>TA", "CT>TC", "CT>TG",
  "TC>AA", "TC>AG", "TC>AT", "TC>CA", "TC>CG", "TC>CT", "TC>GA", "TC>GG", "TC>GT",
  "TT>AA", "TT>AC", "TT>AG", "TT>CA", "TT>CC", "TT>CG", "TT>GA", "TT>GC", "TT>GG",
  "AC>CA", "AC>CG", "AC>CT", "AC>GA", "AC>GG", "AC>GT", "AC>TA", "AC>TG", "AC>TT",
  "AT>CA", "AT>CC", "AT>CG", "AT>GA", "AT>GC", "AT>TA",
  "CG>AT", "CG>GC", "CG>GT", "CG>TA", "CG>TC", "CG>TT",
  "GC>AA", "GC>AG", "GC>AT", "GC>CA", "GC>CG", "GC>TA",
  "TA>AT", "TA>CG", "TA>CT", "TA>GC", "TA>GG", "TA>GT",
  "TG>AA", "TG>AC", "TG>AT", "TG>CA", "TG>CC", "TG>CT", "TG>GA", "TG>GC", "TG>GT"
)

.build_dbs78 <- function() {
  labels <- character(0)
  for (ref in .dbs_refs) {
    x <- substr(ref, 1L, 1L)
    y <- substr(ref, 2L, 2L)
    grid <- expand.grid(z = .bases, n = .bases, stringsAsFactors = FALSE)
    grid <- grid[grid$n != x & grid$z != y, ] # both positions must change
    alts <- paste0(grid$n, grid$z)
    if (identical(.revcompl_dinuc(ref), ref)) {
      # Q-type ref: fold revcompl-equivalent alts, keeping SPMG's pinned choice.
      keep <- .dbs_fold_keep[[ref]]
      .assert(!is.null(keep), sprintf("DBS78: no fold table for ref %s", ref))
      alts <- alts[alts %in% keep | .revcompl_dinuc(alts) == alts]
      .assert(length(alts) == 6L,
              sprintf("DBS78: ref %s must fold to 6 alts", ref))
    } else {
      .assert(length(alts) == 9L,
              sprintf("DBS78: ref %s must have 9 alts", ref))
    }
    labels <- c(labels, paste0(ref, ">", alts))
  }
  labels <- sort(labels) # canonical order == ASCII lexicographic of label

  .assert_labels(labels, 78L, "^[ACGT]{2}>[ACGT]{2}$", "DBS78")
  .assert(labels[1] == "AC>CA" && labels[78] == "TT>GG",
          "DBS78 anchor labels drifted")
  # Derivation must reproduce the audited upstream constant list exactly.
  .assert(setequal(labels, .dbs78_upstream_expected),
          "DBS78 derivation diverges from the SPMG constant list")

  dec <- data.frame(
    label = labels,
    ref = substr(labels, 1L, 2L),
    alt = substr(labels, 4L, 5L),
    ref_group = ifelse(.revcompl_dinuc(substr(labels, 1L, 2L)) ==
                         substr(labels, 1L, 2L), "q", "tsb"),
    stringsAsFactors = FALSE
  )
  .assert(all(substr(dec$alt, 1L, 1L) != substr(dec$ref, 1L, 1L) &
                substr(dec$alt, 2L, 2L) != substr(dec$ref, 2L, 2L)),
          "DBS78: channel with an unchanged position")

  # Coverage contract: over the 144 doublet mutations where both positions
  # change, exactly one of each revcompl pair is a channel.
  refs_g <- expand.grid(y = .bases, x = .bases, stringsAsFactors = FALSE)
  refs_g$ref <- paste0(refs_g$x, refs_g$y)
  alts_g <- expand.grid(z = .bases, n = .bases, stringsAsFactors = FALSE)
  alts_g$alt <- paste0(alts_g$n, alts_g$z)
  uni <- merge(refs_g["ref"], alts_g["alt"], by = NULL)
  uni <- uni[substr(uni$alt, 1L, 1L) != substr(uni$ref, 1L, 1L) &
               substr(uni$alt, 2L, 2L) != substr(uni$ref, 2L, 2L), ]
  muts <- paste0(uni$ref, ">", uni$alt)
  .assert(length(muts) == 144L, "DBS78: expected 144 doublet mutations")
  hit <- muts %in% labels
  mirror <- paste0(.revcompl_dinuc(uni$ref), ">", .revcompl_dinuc(uni$alt)) %in% labels
  selfeq <- muts == paste0(.revcompl_dinuc(uni$ref), ">", .revcompl_dinuc(uni$alt))
  .assert(all(hit[selfeq]),
          "DBS78: self-revcompl mutation missing from the channel set")
  .assert(all(xor(hit[!selfeq], mirror[!selfeq])),
          "DBS78: revcompl-pair coverage contract violated")

  list(name = "DBS78", labels = labels, n = 78L,
       pattern = "^[ACGT]{2}>[ACGT]{2}$",
       strand_states = NULL, decomposition = dec)
}

# ---------------------------------------------------------------------------
# Assemble the registry (single in-memory derivation for both artifacts)
# ---------------------------------------------------------------------------
channel_tables <- list(
  SBS96 = .build_sbs96(),
  SBS192 = .build_sbs_tsb(.strand_order_192, "SBS192"),
  SBS384 = .build_sbs_tsb(.strand_order_384, "SBS384"),
  SBS1536 = .build_sbs1536(),
  DBS78 = .build_dbs78()
)

attr(channel_tables, "provenance") <- list(
  generator = "data-raw/build_channels.R",
  rule = paste(
    "canonical order: ASCII lexicographic of label (A<C<G<T) for",
    "SBS96/SBS1536/DBS78; SBS192/SBS384 = strand blocks T,U / T,U,B,N in",
    "SPMG bias_sort order over SBS96 order"
  ),
  semantics = "docs/research/04 section 1 (SPMG audit); docs/research/05 section 2",
  license_note = paste(
    "no COSMIC/SigProfiler data files bundled or cached; labels generated",
    "programmatically and validated by structural assertions (conservative",
    "reading of docs/research/05 section 1)"
  )
)

# ---------------------------------------------------------------------------
# Writers
# ---------------------------------------------------------------------------
.write_sysdata <- function() {
  out <- file.path(.repo_root, "R", "sysdata.rda")
  save(channel_tables, file = out, compress = "xz", version = 3)
  invisible(out)
}

.write_channels_rs <- function() {
  fmt <- function(labels, name, n, doc) {
    body <- paste0('    "', labels, '",', collapse = "\n")
    paste0(
      "/// ", doc, "\n",
      "#[rustfmt::skip]\n",
      "pub static ", name, "_CHANNELS: [&str; ", n, "] = [\n",
      body, "\n",
      "];\n"
    )
  }
  docs <- c(
    SBS96 = paste0(
      "SBS96 single-base substitution channels in canonical order: ",
      "flank5 x 6 substitution classes x flank3 (ASCII lexicographic)."
    ),
    SBS192 = paste0(
      "SBS192 transcriptional-strand channels: {T, U} blocks over SBS96 ",
      "in SPMG bias_sort order."
    ),
    SBS384 = paste0(
      "SBS384 transcriptional-strand channels: {T, U, B, N} blocks over ",
      "SBS96 in SPMG bias_sort order."
    ),
    SBS1536 = paste0(
      "SBS1536 pentanucleotide channels in canonical order (ASCII ",
      "lexicographic; projects losslessly onto SBS96)."
    ),
    DBS78 = paste0(
      "DBS78 doublet-substitution channels in canonical order: 10 ",
      "canonical refs x SPMG alt sets (Q-type refs revcompl-folded)."
    )
  )
  header <- paste0(
    "//! Channel label constants in canonical order (GENERATED FILE).\n",
    "//!\n",
    "//! Source of truth: `data-raw/build_channels.R` -- regenerate with\n",
    "//! `Rscript data-raw/build_channels.R`; do not edit by hand.\n",
    "//! Canonical-order provenance: `docs/research/04` section 1 (SPMG\n",
    "//! semantics) and `docs/research/05` section 2. These arrays must stay\n",
    "//! bit-identical to `R/sysdata.rda` (`channel_tables`), enforced by\n",
    "//! `tests/testthat/test-channels-sync.R`; structural contract pinned by\n",
    "//! `src/rust/catalog/tests/channels.rs`.\n",
    "//!\n",
    "//! `static` (not `const`) keeps one shared instance in memory\n",
    "//! (clippy::large_const_arrays); `#[rustfmt::skip]` keeps the\n",
    "//! one-label-per-line layout stable across regenerations.\n\n"
  )
  parts <- vapply(names(channel_tables), function(nm) {
    tbl <- channel_tables[[nm]]
    fmt(tbl$labels, nm, tbl$n, docs[[nm]])
  }, character(1))
  out <- file.path(.repo_root, "src", "rust", "catalog", "src", "channels.rs")
  content <- paste0(header, paste(parts, collapse = "\n"))
  # writeLines appends one final newline; drop the trailing one from `content`
  # so the file ends with exactly "];\n" (rustfmt-stable EOF).
  writeLines(sub("\n$", "", content), out, useBytes = TRUE)
  invisible(out)
}

sysdata_file <- .write_sysdata()
channels_rs_file <- .write_channels_rs()
message("wrote: ", sysdata_file)
message("wrote: ", channels_rs_file)
message("tables: ", paste(
  vapply(channel_tables, function(x) sprintf("%s=%d", x$name, x$n), character(1)),
  collapse = " "
))
