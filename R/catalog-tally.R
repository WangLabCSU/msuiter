# catalog-tally.R: the catalog-layer entry point ms_tally() (U-M1s-11).
#
# ARCHITECTURE.md section 3.1/3.2: ms_tally() is the second link of the
# working grammar (ms_variants() |> ms_tally() |> ...). It dispatches on an
# [MsVariants] object, routes the records through the FFI tally kernel
# (`.ms_tally_rust`, R/ffi-probes.R -- 2bit reference contexts, skip ledger,
# DBS-excluded SBS counting) and assembles the resulting channel matrix into
# an [MsCatalog] via ms_catalog(). The assembly layer adds NO semantics of
# its own: counts are passed through byte-exact, matched by label (canonical
# registry rownames from the R channel registry, D5; sample columns in
# first-appearance order), and every tally fact is recorded in provenance.
#
# Transcription-strand policy (mirrors sbs.rs, documented in
# docs/ffi-surface.md -- NOT a degradation path):
#   * mode "SBS192" REQUIRES a `strand` column on the variant table
#     (structured error without one: B/N-strand records have no SBS192
#     channel, so silently defaulting the annotation would misplace real
#     mutations);
#   * mode "SBS384" defaults missing `strand` to "N" (the 384-channel table
#     has explicit N-prefixed channels);
#   * every other mode ignores strand entirely (the kernel only reads it for
#     the transcription-aware tables).
# An empty variant queue routes cleanly through the assembly into a legal
# all-zero channels x 0 MsCatalog (empty ledger, no strand annotation
# needed): the catalog validator accepts the zero-column matrix because
# base R normalizes character(0) colnames to NULL exactly there
# (R/classes-catalog.R, U-M1s-11 audit P3).
#
# All violations raise msuiter_error_* conditions with the i/j/c payload
# (ARCHITECTURE section 3.5); bare stop() is banned.

#' Tally variants into a channel catalog
#'
#' `ms_tally()` is the second link of the msuiter working grammar
#' (`ms_variants() |> ms_tally() |> ...`): it counts the records of an
#' [MsVariants] object against a 2bit reference genome and returns an
#' [MsCatalog] holding one channel table of the requested modality.
#' Reference contexts, DBS-pair exclusion and the per-record skip ledger are
#' owned by the Rust core; this layer only validates arguments, picks the
#' table and assembles the catalog. All violations raise `msuiter_error_*`
#' conditions.
#'
#' @param variants An [MsVariants] object, as returned by [ms_variants()].
#'   The canonical columns `chrom`, `start`, `ref` and `alt` feed the tally;
#'   an optional `sample` column attributes records to samples (columns of
#'   the count matrix appear in first-appearance order; when the column is
#'   absent, all records are attributed to the single sample id `"sample"`),
#'   and an optional `strand` column carries the transcription annotation
#'   (`T`/`U`/`B`/`N`) for the strand-aware modes.
#' @param genome Path to an (uncompressed) UCSC 2bit reference genome whose
#'   chromosome names match the variant table exactly (no `chr` prefix
#'   normalization; unmatched chromosomes are ledgered as
#'   `skipped:unknown_chrom` rows, never an error).
#' @param mode Channel table to build: `"SBS96"` (default), `"SBS192"`,
#'   `"SBS384"`, `"SBS1536"` or `"DBS78"`. Any other value is an error that
#'   lists every legal mode.
#' @param ... No passthrough arguments: anything arriving in `...` is
#'   rejected as an argument-spelling error (`msuiter_error_input`).
#'
#' @details
#' Strand policy (mirrors the Rust `sbs` module; there is no silent
#' degradation): `"SBS192"` requires a `strand` column on the variant table
#' -- B/N-strand records have no SBS192 channel, so inventing the annotation
#' would misplace real mutations and is a structured error instead;
#' `"SBS384"` defaults a missing `strand` column to `"N"`; all other modes
#' ignore strand.
#'
#' Adjacent doublet-base substitutions are counted in DBS78 and excluded
#' from every SBS matrix; indels, invalid alleles, reference mismatches and
#' context-window violations are skipped into the ledger, never silently
#' coerced (SPMG parity). The ledger is switch-independent: it is written
#' for every input record whatever the mode.
#'
#' The returned catalog's provenance merges the variants' own provenance
#' (caller, matched normal, source, parse statistics, ...) with the tally
#' context: `genome` (build label from the variants), `genome_path` (the 2bit
#' file used), `mode`, `ledger` (one `record TAB destination` line per input
#' record, in input order), `n_skipped` and `n_variants`. On a key collision
#' the tally context wins: the tally-produced keys (`genome`, `genome_path`,
#' `mode`, `ledger`, `n_skipped`, `n_variants`) are written after the merge
#' and overwrite same-named keys coming from the variants' provenance.
#'
#' @return An [MsCatalog] object.
#' @seealso [ms_variants()] for the input container, [ms_catalog()] for the
#'   low-level constructor.
#' @export
ms_tally <- S7::new_generic(
  "ms_tally",
  "variants",
  function(variants, genome, mode = "SBS96", ...) S7::S7_dispatch()
)

# Legal catalog modalities (CAPABILITY-MATRIX L-B row: ms_tally(mode=)
# multimodal) and their FFI table keys / registry snapshot names.
.ms_tally_modes <- c("SBS96", "SBS192", "SBS384", "SBS1536", "DBS78")
.ms_tally_keys <- c(sbs96 = "sbs96", sbs192 = "sbs192", sbs384 = "sbs384",
  sbs1536 = "sbs1536", dbs78 = "dbs78")

# Dots discipline: ms_tally() has no passthrough arguments; anything
# arriving in `...` is an argument-spelling error, never an ignored value.
# (Same rule as ms_variants(); the wording is tally-specific, and the
# io-layer helper is intentionally left untouched.)
.ms_tally_abort_dots <- function(dots) {
  if (length(dots) == 0L) {
    return(invisible(NULL))
  }
  labels <- names(dots)
  if (is.null(labels)) {
    labels <- rep("", length(dots))
  }
  labels[!nzchar(labels)] <- "<positional>"
  msuiter_abort(
    "input",
    "unknown argument passed to ms_tally()",
    i = "ms_tally() has no passthrough arguments",
    j = paste0("unexpected: ", msuiter_quote_trunc(labels)),
    c = "check the argument spelling against ?ms_tally"
  )
}

# Method: MsVariants -> MsCatalog. Single method for M1s; the FFI kernel
# does the counting, this body only validates, dispatches the table switch
# and assembles.
S7::method(ms_tally, MsVariants) <- function(variants, genome, mode = "SBS96",
                                             ...) {
  .ms_tally_abort_dots(list(...))

  # --- mode: one of the legal channel tables, listed on violation.
  if (!is.character(mode) || length(mode) != 1L || is.na(mode) ||
    !mode %in% .ms_tally_modes) {
    msuiter_abort(
      "input",
      paste0(
        "mode must be one of ",
        paste0("'", .ms_tally_modes, "'", collapse = ", ")
      ),
      i = "ms_tally() builds exactly one channel table per call",
      j = paste0("received: ", msuiter_quote_trunc(mode)),
      c = "pick one of SBS96, SBS192, SBS384, SBS1536 or DBS78"
    )
  }

  # --- genome: an existing 2bit file (io-layer concern, io-layer errors).
  if (!is.character(genome) || length(genome) != 1L || is.na(genome) ||
    !nzchar(genome)) {
    msuiter_abort(
      "input",
      "genome must be a single non-empty 2bit file path",
      i = "ms_tally() fetches reference contexts from a 2bit genome",
      j = paste0("received: ", msuiter_quote_trunc(genome)),
      c = "pass the path of an uncompressed UCSC 2bit reference genome"
    )
  }
  if (!file.exists(genome)) {
    msuiter_abort(
      "io",
      "the 2bit reference genome does not exist",
      i = "ms_tally() reads the genome eagerly at call time",
      j = genome,
      c = "check the path spelling and the working directory"
    )
  }
  if (dir.exists(genome)) {
    msuiter_abort(
      "io",
      "the genome path is a directory, not a 2bit file",
      i = "ms_tally() reads a regular 2bit file",
      j = genome,
      c = "pass the path of the .2bit reference genome"
    )
  }

  # --- records: canonical columns plus the optional sample/strand
  #     annotations. Matching downstream is strictly by label.
  table <- variants@table
  n <- nrow(table)
  strand_col <- if ("strand" %in% names(table)) table$strand else NULL
  sample_col <- if ("sample" %in% names(table)) {
    as.character(table$sample)
  } else if (n > 0L) {
    # Single-tumor record-list scenario (io layer does not parse genotype
    # columns yet): one canonical sample id for every record.
    rep("sample", n)
  } else {
    character(0L)
  }

  strand <- if (n == 0L) {
    character(0L) # an empty queue never needs annotation
  } else if (mode %in% c("SBS192", "SBS384")) {
    if (is.null(strand_col)) {
      if (mode == "SBS192") {
        # No degradation: B/N records have no SBS192 channel, so a silently
        # invented annotation would misplace real mutations (sbs.rs policy).
        msuiter_abort(
          "input",
          "mode 'SBS192' requires a transcription strand column",
          i = paste0(
            "SBS192 channels are strand-aware and B/N records have no ",
            "SBS192 channel; the annotation cannot be defaulted"
          ),
          j = "no 'strand' column in the variant table",
          c = paste0(
            "annotate records with strand in T/U/B/N (e.g. from the ",
            "transcript model), or tally mode 'SBS384', which defaults N"
          )
        )
      }
      rep("N", n) # SBS384 has explicit N-prefixed channels
    } else {
      as.character(strand_col) # vocabulary guarded by the FFI validators
    }
  } else {
    rep("N", n) # the kernel only reads strand for the strand-aware tables
  }

  # --- tally: exactly one table switch on; everything else is the kernel's
  #     job (contexts, ledger, DBS exclusion). Errors surface as
  #     msuiter_error_rust / msuiter_error_input from the FFI layer.
  res <- .ms_tally_rust(
    genome,
    chrom = table$chrom, pos = table$start,
    ref_ = table$ref, alt = table$alt,
    sample = sample_col, strand = strand,
    want_sbs96 = mode == "SBS96", want_sbs192 = mode == "SBS192",
    want_sbs384 = mode == "SBS384", want_sbs1536 = mode == "SBS1536",
    want_dbs78 = mode == "DBS78"
  )
  counts <- res[[.ms_tally_keys[[tolower(mode)]]]]

  # --- assemble: rownames are already the canonical registry labels and
  #     colnames the first-appearance sample order (set by the FFI wrapper);
  #     ms_catalog() derives the channel-snapshot hash. Samples come from the
  #     record column (first-appearance order, exactly what the wrapper
  #     wrote into the dimnames): colnames() would return NULL for the
  #     legal empty case (channels x 0 matrix).
  tables <- get("channel_tables", envir = asNamespace("msuiter"))
  provenance <- variants@provenance
  provenance$genome <- variants@genome # build label (validator-required)
  provenance$genome_path <- genome # the 2bit file actually used
  provenance$mode <- mode
  provenance$ledger <- res$ledger # per-record TSV, switch-independent
  provenance$n_skipped <- res$n_skipped
  provenance$n_variants <- res$n_variants

  ms_catalog(
    counts = counts,
    channels = list(name = mode, labels = tables[[mode]]$labels),
    samples = unique(sample_col),
    provenance = provenance
  )
}

# Fallback: anything that is not an MsVariants gets a project error instead
# of the raw S7 dispatch failure.
S7::method(ms_tally, S7::class_any) <- function(variants, genome,
                                                mode = "SBS96", ...) {
  msuiter_abort(
    "input",
    "variants must be an MsVariants object",
    i = "ms_tally() dispatches on MsVariants",
    j = paste0("received: ", class(variants)[1L]),
    c = "read the calls with ms_variants() first (ms_variants() |> ms_tally())"
  )
}
