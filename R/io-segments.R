# io-segments.R: the io-layer entry point ms_segments() (M1c input-layer
# wiring; CAPABILITY-MATRIX L-A row "CN 输入"; consumes the verified CN48
# arithmetic of src/rust/catalog/src/cn48.rs, whose CnSegment carries
# seg_len_bp = end - start (raw difference) and the ordered pair
# minor_cn <= major_cn).
#
# Semantic gold standard: SigProfilerMatrixGenerator (SPMG)
# `CNVMatrixGenerator.py`, function `annotateSegFile`, audited at
# upstream master `edccbea6`. Every supported caller is a pure
# column-name mapping of the quantities CN48 consumes; the per-caller
# column anchors (line references are master edccbea6):
#
#   caller      total CN / allele columns                     coords
#   ASCAT       nMajor + nMinor (:104-116, :196-204)          startpos/endpos (:318-320)
#   ASCAT_NGS   Tumour TCN, Tumour BCN (:79-90, :215-221;     Start Position/End
#               minor allele = TCN - BCN, the "Tumour ACN")   Position (:309-311)
#   ABSOLUTE    Modal_HSCN_1 + Modal_HSCN_2 (:117-129,        Start/End (:315-317)
#               :234-242)
#   PCAWG       copy_number + mutation_type (:130-141,        chromosome_start/
#               :243-258)                                     chromosome_end (:321-323)
#   FACETS      tcn.em, lcn.em (:142-153, :260-271; minor     start/end (:324-326)
#               = lcn.em, NA minor -> LOH per :262-271)
#   BATTENBERG  nMaj1_A/nMin1_A clonal + nMaj2_A/nMin2_A      startpos/endpos
#               subclonal counted as separate events          (:327-329); chrom "chr"
#               (:401-425)                                    (:402)
#   PURPLE      minorAlleleCopyNumber/majorAlleleCopyNumber   start/end (:324-326)
#               (:167-183, :282-295)
#   SEQUENZA    CNt with alleles A, B (:92-103, :206-213)     start.pos/end.pos
#                                                             (:312-314)
#
# SPMG has NO CNVkit branch (grep over the whole edccbea6 tree: zero
# hits) and CNVkit .cns/.cnr output carries total log2 copy number, not
# allele-specific states -- CNVkit is therefore documented-limited and
# rejected with an actionable message, not force-fitted.
#
# Division of labor (mirrors io-variants.R, ARCHITECTURE.md section 3.1):
#   * the io layer owns FORMAT repair -- per-caller column mapping,
#     allele-pair canonicalization for the callers whose upstream
#     zero-test is order-insensitive (ASCAT_NGS/ABSOLUTE/SEQUENZA test
#     sums and zero alleles, :196-204/:234-242/:273-281/:282-295), the
#     Battenberg clonal/subclonal expansion (:401-425) and the skip
#     ledger (A11: every dropped block is counted into provenance);
#   * record-level legality (positive coordinates, end >= start,
#     minor <= major, anyNA) is checked here too, because the output is
#     a typed data.frame -- the S7 segment class arrives with the M2
#     cnv_features unit. All failures raise msuiter_error_* conditions
#     with the i/j/c payload (section 3.5); bare stop() is banned.

# ---------------------------------------------------------------------------
# Caller profiles (column mappings + auto-detection signatures)
# ---------------------------------------------------------------------------

# The chrom column SPMG never reads for matrix generation (the CN48
# tally is chromosome-agnostic); verified where the source touches it
# (BATTENBERG "chr", CNVMatrixGenerator.py:402; ASCAT_NGS "Chromosome",
# the upstream fixture references/CNV/example_input/
# all.breast.ascat.summary.sample.tsv). The remaining names are the
# callers' standard segment-file headers -- documented-limited, always
# overridable via `chrom_col`.
msuiter_segment_profiles <- list(
  ASCAT = list(
    chrom = "chr", start = "startpos", end = "endpos",
    signature = c("nMajor", "nMinor")
  ),
  ASCAT_NGS = list(
    chrom = "Chromosome", start = "Start Position", end = "End Position",
    signature = c("Tumour TCN", "Tumour BCN")
  ),
  ABSOLUTE = list(
    chrom = "Chromosome", start = "Start", end = "End",
    signature = c("Modal_HSCN_1", "Modal_HSCN_2")
  ),
  PCAWG = list(
    chrom = "chromosome", start = "chromosome_start", end = "chromosome_end",
    signature = c("copy_number", "mutation_type")
  ),
  FACETS = list(
    chrom = "chrom", start = "start", end = "end",
    signature = c("tcn.em", "lcn.em")
  ),
  BATTENBERG = list(
    chrom = "chr", start = "startpos", end = "endpos",
    signature = c("nMaj1_A", "nMin1_A")
  ),
  PURPLE = list(
    chrom = "chromosome", start = "start", end = "end",
    signature = c("minorAlleleCopyNumber", "majorAlleleCopyNumber")
  ),
  SEQUENZA = list(
    chrom = "chromosome", start = "start.pos", end = "end.pos",
    signature = c("CNt", "A", "B")
  )
)

# Dots discipline shared with ms_variants(): no passthrough arguments.
msuiter_segments_abort_dots <- function(dots) {
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
    "unknown argument passed to ms_segments()",
    i = "ms_segments() has no passthrough arguments",
    j = paste0("unexpected: ", msuiter_quote_trunc(labels)),
    c = "check the argument spelling against ?ms_segments"
  )
}

#' Read allele-specific copy-number segments into a typed table
#'
#' `ms_segments()` is the CN input link of the msuiter grammar. It is an
#' S7 generic: given a file path it reads a segmentation file from one of
#' the eight SigProfilerMatrixGenerator CN callers, maps the caller's
#' columns onto the canonical allele-specific segment record and returns
#' a typed data.frame; given a canonical data.frame it validates and
#' returns it directly. All violations raise `msuiter_error_*`
#' conditions.
#'
#' @param x A character string naming one segmentation file (`.tsv` or
#'   `.txt`, optionally `.gz`), or a data.frame in canonical form
#'   (columns `chrom`, `start`, `end`, `minor`, `major`, plus optional
#'   `sample`).
#' @param caller The CN caller label. Defaults to `"auto"`: the caller
#'   is identified from the file's copy-number column signature (each of
#'   the eight signatures is distinct). An explicit label
#'   (`"ASCAT"`, `"ASCAT_NGS"`, `"ABSOLUTE"`, `"PCAWG"`, `"FACETS"`,
#'   `"BATTENBERG"`, `"PURPLE"`, `"SEQUENZA"`, case-insensitive) forces
#'   the mapping. For a canonical data.frame, `caller` is required
#'   provenance (`"auto"` is rejected there). CNVkit is not an SPMG
#'   input branch and its `.cns`/`.cnr` output is not allele-specific;
#'   it is rejected as documented-limited.
#' @param chrom_col Optional name of the chromosome column, overriding
#'   the per-caller default (file input only). SPMG's matrix generation
#'   never reads the chromosome column, so the defaults for ASCAT,
#'   ABSOLUTE, PCAWG, FACETS, PURPLE and SEQUENZA follow the callers'
#'   standard segment-file headers and are documented-limited;
#'   BATTENBERG (`chr`, upstream :402) and ASCAT_NGS (`Chromosome`,
#'   upstream example fixture) are source-verified.
#' @param ... No passthrough arguments: anything arriving in `...` is
#'   rejected as an argument-spelling error (`msuiter_error_input`).
#'
#' @details
#' The canonical record mirrors the verified CN48 input
#' (`src/rust/catalog/src/cn48.rs`, `CnSegment`): `chrom` is passed
#' through verbatim, `start`/`end` are 1-based closed bp coordinates and
#' `minor`/`major` are the ordered allele-specific copy numbers
#' (`minor <= major`; the total copy number is their sum). The segment
#' length CN48 bins is the raw difference `end - start` (upstream
#' divides `end - start` by 1e6, :310-329 -- NOT `end - start + 1`).
#'
#' Per-caller derivations (SPMG `CNVMatrixGenerator.py`, master
#' `edccbea6`): ASCAT reads `nMajor`/`nMinor` directly (:104-116,
#' :196-204). ASCAT_NGS derives the minor allele as
#' `Tumour TCN - Tumour BCN` (:215-221); upstream only zero-tests the
#' pair, so the smaller value becomes `minor`. ABSOLUTE's
#' `Modal_HSCN_1`/`Modal_HSCN_2` are likewise an unordered pair
#' (:117-129, :234-242). SEQUENZA requires `A + B == CNt` (:92-103,
#' :206-213) and orders the pair. FACETS takes `minor = lcn.em` (a
#' missing `lcn.em` means LOH upstream, :262-271, and maps to
#' `minor = 0`) and `major = tcn.em - minor`; `lcn.em` above half of
#' `tcn.em` contradicts FACETS' own "less-copy number" semantics and is
#' rejected. PURPLE reads `minorAlleleCopyNumber`/`majorAlleleCopyNumber`
#' (:167-183, :282-295). Battenberg rows expand to one record per
#' present clone block (`nMaj1_A`/`nMin1_A` clonal, `nMaj2_A`/`nMin2_A`
#' subclonal), exactly as upstream tallies both blocks as separate
#' events (:401-425); a block with any missing value is counted into the
#' provenance skip ledger instead of silently dropped (upstream `dropna`
#' :404-405 drops the same rows, but also silently drops rows with missing
#' coordinates/samples where msuiter hard-rejects -- stricter by design).
#'
#' PCAWG files carry no allele split -- upstream consumes only
#' `copy_number` and `mutation_type` (:130-141, :243-258). The mapping
#' is: `copy neutral LOH` / `amp LOH` / `hemizygous del LOH` ->
#' `minor = 0`, `major = copy_number`; `loss` with `copy_number` 0/1
#' -> homdel (0, 0) / LOH (0, 1); `copy neutral` and `gain` -> the
#' documented convention `minor = 1`, `major = copy_number - 1`, which
#' preserves the total copy number and het zygosity and therefore the
#' exact CN48 channel (the true allele split is unrecoverable from the
#' format). Rows outside these shapes (`loss` with total CN >= 2,
#' het-labelled rows with total CN < 2, any other `mutation_type`) have
#' no faithful upstream behaviour -- upstream desynchronises its LOH
#' list (:304) or targets the nonexistent `1:het` channel -- and are
#' rejected with the offending row numbers.
#'
#' Deliberate divergences from upstream (documented, not gaps): NaN
#' copy numbers are rejected instead of silently classifying into
#' `9+`/het; declared-role callers (ASCAT, BATTENBERG, FACETS, PURPLE)
#' with `minor > major` are rejected instead of tallied; `sample` is
#' optional passthrough (single-sample tool), not a hard requirement.
#'
#' The returned `provenance` attribute carries `caller` (resolved
#' label), `source`/`format` and the `parse` statistics (`n_lines`,
#' `n_records`, `n_expanded` for Battenberg subclonal records,
#' `n_skipped`, `skip_reasons`).
#'
#' @return A data.frame with columns `sample` (only when present in the
#'   input), `chrom` (character), `start`, `end` (1-based closed bp) and
#'   `minor`, `major` (integer), with the io `provenance` in attribute
#'   `"provenance"`.
#' @examples
#' lines <- c(
#'   "sample\tchr\tstartpos\tendpos\tnMajor\tnMinor",
#'   "TUMOR1\tchr7\t100000\t9000000\t1\t1",
#'   "TUMOR1\tchr7\t9000000\t20000000\t3\t0"
#' )
#' path <- tempfile(fileext = ".tsv")
#' writeLines(lines, path)
#' seg <- ms_segments(path, caller = "ASCAT")
#' seg
#' attr(seg, "provenance")$caller
#' unlink(path)
#'
#' # Canonical data.frame: validated direct construction
#' ms_segments(
#'   data.frame(chrom = "chr7", start = 100000, end = 9000000,
#'              minor = 1L, major = 1L),
#'   caller = "synthetic"
#' )
#' @export
ms_segments <- S7::new_generic(
  "ms_segments",
  "x",
  function(x, caller = "auto", chrom_col = NULL, ...) S7::S7_dispatch()
)

# Method: read one segmentation file. Dispatch by `caller`, map columns,
# validate, attach provenance.
S7::method(ms_segments, S7::class_character) <- function(
    x, caller = "auto", chrom_col = NULL, ...) {
  msuiter_segments_abort_dots(list(...))
  if (length(x) != 1L || is.na(x) || !nzchar(x)) {
    msuiter_abort(
      "input",
      "x must be a single non-empty file path",
      i = "the character method of ms_segments() reads exactly one file",
      j = paste0("received a character vector of length ", length(x)),
      c = "pass the path of one segmentation file (optionally .gz)"
    )
  }
  if (!file.exists(x)) {
    msuiter_abort(
      "io",
      "the segmentation file does not exist",
      i = "the io layer reads the file eagerly at call time",
      j = x,
      c = "check the path spelling and the working directory"
    )
  }
  if (dir.exists(x)) {
    msuiter_abort(
      "io",
      "the segmentation path is a directory, not a file",
      i = "the io layer reads regular files only",
      j = x,
      c = "pass the path of one segmentation file"
    )
  }
  fmt <- msuiter_segment_format(x)
  tab <- msuiter_read_tsv_table(x, fmt$compressed, "segmentation")
  caller <- msuiter_segment_caller_label(caller, names(tab))
  table <- msuiter_segments_from_caller(tab, caller, chrom_col, x)
  attr(table, "provenance") <- list(
    caller = caller,
    source = x,
    format = "segments",
    parse = attr(table, "parse_stats")
  )
  attr(table, "parse_stats") <- NULL
  table
}

# Method: canonical data.frame, validated direct construction. File-only
# column-mapping arguments are rejected instead of silently ignored.
S7::method(ms_segments, S7::class_data.frame) <- function(
    x, caller = "auto", chrom_col = NULL, ...) {
  msuiter_segments_abort_dots(list(...))
  if (!is.null(chrom_col)) {
    msuiter_abort(
      "input",
      "the chrom_col mapping applies only when reading a file",
      i = "a canonical data.frame already names its chromosome column 'chrom'",
      j = "chrom_col is set on the direct-construction path",
      c = "drop chrom_col, or pass a file path instead"
    )
  }
  if (missing(caller) || !is.character(caller) || length(caller) != 1L ||
    is.na(caller) || !nzchar(caller) || identical(toupper(caller), "AUTO")) {
    msuiter_abort(
      "input",
      "the caller label is required for direct construction",
      i = "a canonical table carries no per-caller columns to auto-detect from",
      j = if (missing(caller)) "argument 'caller' is missing" else
        paste0("received: ", msuiter_quote_trunc(caller)),
      c = 'record the calling tool, e.g. caller = "ASCAT"'
    )
  }
  table <- msuiter_segments_canonical(x)
  attr(table, "provenance") <- list(
    caller = caller,
    format = "segments",
    parse = attr(table, "parse_stats")
  )
  attr(table, "parse_stats") <- NULL
  table
}

# Fallback: anything that is neither a path nor a table gets a project
# error instead of the raw S7 dispatch failure.
S7::method(ms_segments, S7::class_any) <- function(
    x, caller = "auto", chrom_col = NULL, ...) {
  msuiter_segments_abort_dots(list(...))
  msuiter_abort(
    "input",
    "x must be a segmentation file path or a canonical segment table",
    i = "ms_segments() dispatches on character paths and data.frames",
    j = paste0("received: ", class(x)[1L]),
    c = paste0(
      "pass a segmentation file path or a data.frame with columns ",
      "chrom/start/end/minor/major"
    )
  )
}

# ---------------------------------------------------------------------------
# Format resolution and table reading (TSV only, like upstream
# pd.read_csv(sep="\t"), CNVMatrixGenerator.py:400)
# ---------------------------------------------------------------------------

msuiter_segment_format <- function(path) {
  m <- regmatches(
    tolower(basename(path)),
    regexec("\\.(tsv|txt)(\\.gz)?$", tolower(basename(path)))
  )[[1L]]
  if (length(m) == 0L) {
    msuiter_abort(
      "unsupported",
      "unrecognized segmentation file extension",
      i = "ms_segments() reads tab-separated segmentation files: .tsv, .txt (optionally .gz)",
      j = basename(path),
      c = "re-export the caller output as a tab-separated file"
    )
  }
  list(compressed = nzchar(m[3L]))
}

# Parse a tabular table with a header row, strictly: every line must
# match the header's field count (the pre-check below), and read.table's
# residual bare errors are captured and re-raised as msuiter_error_parse
# (ARCHITECTURE section 3.5 bans bare errors on user input).
msuiter_read_tsv_table <- function(path, compressed, what) {
  lines <- msuiter_read_file_lines(path, compressed)
  if (length(lines) == 0L) {
    msuiter_abort(
      "io",
      paste0("the ", what, " file is empty"),
      i = "a tabular input needs a header line and at least one record",
      j = basename(path),
      c = "check that the file is the intended input"
    )
  }
  lines <- lines[nzchar(lines)]
  # Strict field-count check BEFORE read.table: a data line wider than
  # the header makes read.table silently shift the first data column
  # into the row names (its headerless-input convention), which would
  # mis-parse plausible-looking output. Every line must match the
  # header's tab-separated field count.
  counts <- vapply(lines, function(l) {
    length(strsplit(l, "\t", fixed = TRUE)[[1L]])
  }, integer(1L))
  if (length(unique(counts)) != 1L) {
    offenders <- which(counts != counts[1L])
    msuiter_abort(
      "parse",
      paste0("the ", what, " file has ragged data line(s)"),
      i = paste0(
        "the header declares ", counts[1L],
        " tab-separated fields; every data line must match"
      ),
      j = paste0(
        basename(path), ", offending file line(s): ",
        msuiter_quote_trunc(offenders)
      ),
      c = "repair the ragged data line(s), or re-export the file"
    )
  }
  tryCatch(
    utils::read.table(
      text = paste(lines, collapse = "\n"),
      sep = "\t", header = TRUE, quote = "", comment.char = "",
      check.names = FALSE, colClasses = "character", stringsAsFactors = FALSE
    ),
    error = function(e) {
      msg <- conditionMessage(e)
      line <- regmatches(msg, regexec("line ([0-9]+)", msg))[[1L]]
      msuiter_abort(
        "parse",
        paste0("the ", what, " file could not be parsed as a tabular table"),
        i = if (length(line) == 2L) {
          paste0("offending data line: ", line[2L])
        } else {
          "a data line does not match the header's tab-separated field count"
        },
        j = paste0(basename(path), ": ", msg),
        c = "repair the ragged data line(s), or re-export the file"
      )
    }
  )
}

# Resolve the caller argument: "auto" detects from the column signature,
# an explicit label forces the mapping. Unknown labels get an actionable
# rejection that names the documented-limited CNVkit case.
msuiter_segment_caller_label <- function(caller, tab_names) {
  if (!is.character(caller) || length(caller) != 1L || is.na(caller) ||
    !nzchar(caller)) {
    msuiter_abort(
      "input",
      "caller must be a single non-empty string",
      i = "caller names the copy-number caller whose columns are mapped",
      j = paste0("received: ", msuiter_quote_trunc(caller)),
      c = "use \"auto\" or one of the eight supported caller labels"
    )
  }
  label <- toupper(caller)
  if (identical(label, "AUTO")) {
    hits <- names(msuiter_segment_profiles)[vapply(
      msuiter_segment_profiles,
      function(p) all(p$signature %in% tab_names),
      logical(1L)
    )]
    if (length(hits) != 1L) {
      msuiter_abort(
        "io",
        'caller = "auto" could not identify the copy-number caller',
        i = "auto-detection matches the caller's copy-number column signature",
        j = if (length(hits) == 0L) "no caller signature matched the file's columns" else
          paste0(
            "ambiguous signatures: ", msuiter_quote_trunc(hits)
          ),
        c = paste0(
          "pass caller explicitly: ",
          paste(names(msuiter_segment_profiles), collapse = ", ")
        )
      )
    }
    return(hits)
  }
  if (!label %in% names(msuiter_segment_profiles)) {
    msuiter_abort(
      "input",
      "unsupported copy-number caller",
      i = paste0(
        "supported callers: ",
        paste(names(msuiter_segment_profiles), collapse = ", ")
      ),
      j = msuiter_quote_trunc(caller),
      c = if (grepl("cnvkit", label, ignore.case = TRUE)) {
        paste0(
          "CNVkit is documented-limited: SPMG has no CNVkit branch and ",
          ".cns/.cnr output is total-CN (log2), not allele-specific; ",
          "run an allele-specific caller"
        )
      } else {
        "check the caller spelling against ?ms_segments"
      }
    )
  }
  label
}

# ---------------------------------------------------------------------------
# Column parsing and record validation
# ---------------------------------------------------------------------------

# Parse an integer-valued column. `na_allowed` covers the two callers
# whose upstream semantics treat missing values meaningfully (FACETS
# lcn.em -> LOH, :262-271; Battenberg clone blocks -> dropped rows,
# :404-405); everywhere else anyNA is rejected.
msuiter_segment_parse_int <- function(x, col, src, min_value,
                                      na_allowed = FALSE) {
  x <- trimws(as.character(x))
  na_idx <- which(is.na(x) | !nzchar(x) | x %in% c("NA", "NaN", "na"))
  bad <- setdiff(seq_along(x), na_idx)
  bad <- bad[!grepl("^[0-9]+$", x[bad])]
  if (length(bad) > 0L) {
    msuiter_abort(
      "io",
      "the column must contain non-negative integers",
      i = "copy numbers and segment coordinates are non-negative integer states",
      j = paste0(
        "column '", col, "' in ", basename(src),
        ", offending rows: ", msuiter_quote_trunc(bad)
      ),
      c = "write values as plain integers"
    )
  }
  vals <- as.numeric(x)
  if (!na_allowed && length(na_idx) > 0L) {
    msuiter_abort(
      "io",
      "the copy-number column must not contain missing values",
      i = paste0(
        "missing values have no faithful upstream behaviour for this ",
        "caller (upstream silently classifies NaN copy numbers into ",
        "the 9+/het branches)"
      ),
      j = paste0(
        "column '", col, "' in ", basename(src),
        ", offending rows: ", msuiter_quote_trunc(na_idx)
      ),
      c = "impute or drop the affected rows before reading"
    )
  }
  small <- which(!is.na(vals) & vals < min_value)
  if (length(small) > 0L) {
    msuiter_abort(
      "io",
      paste0("values must be integers >= ", min_value),
      i = "canonical segment coordinates are positive 1-based integers",
      j = paste0(
        "column '", col, "' in ", basename(src),
        ", offending rows: ", msuiter_quote_trunc(small)
      ),
      c = "write coordinates as positive integers (1-based closed intervals)"
    )
  }
  vals
}

# Post-mapping record validation shared by every caller path: positive
# coordinates, end >= start, ordered allele pair, usable chromosome and
# sample labels. `rows` maps typed records back to their source rows for
# error locations.
msuiter_segments_validate <- function(table, rows, src) {
  where <- function(idx) {
    loc <- if (is.null(src)) "row(s) " else paste0(basename(src), ", source row(s) ")
    paste0(loc, msuiter_quote_trunc(unique(rows[idx])))
  }
  bad_chrom <- which(is.na(table$chrom) | !nzchar(table$chrom))
  if (length(bad_chrom) > 0L) {
    msuiter_abort(
      "segments",
      "the chromosome column must contain non-empty labels",
      i = "chromosome names are passed through verbatim into the typed record",
      j = where(bad_chrom),
      c = "fill in the chromosome label"
    )
  }
  bad_end <- which(table$end < table$start)
  if (length(bad_end) > 0L) {
    msuiter_abort(
      "segments",
      "segment end must not precede segment start",
      i = "canonical segments are closed intervals [start, end]",
      j = where(bad_end),
      c = "swap or repair the coordinates"
    )
  }
  bad_pair <- which(table$minor > table$major)
  if (length(bad_pair) > 0L) {
    msuiter_abort(
      "segments",
      "minor copy number exceeds major copy number",
      i = paste0(
        "the typed pair is ordered minor <= major (CnSegment contract, ",
        "src/rust/catalog/src/cn48.rs); the callers with declared roles ",
        "(ASCAT, BATTENBERG, FACETS, PURPLE) are rejected instead of ",
        "reordered"
      ),
      j = where(bad_pair),
      c = "swap the allele columns, or repair the caller output"
    )
  }
  if (!is.null(table$sample)) {
    bad_sample <- which(is.na(table$sample) | !nzchar(table$sample))
    if (length(bad_sample) > 0L) {
      msuiter_abort(
        "segments",
        "the sample column must contain non-empty labels",
        i = "sample labels are passed through for per-sample tallying",
        j = where(bad_sample),
        c = "fill in the sample label"
      )
    }
  }
  table
}

# Assemble the typed table from parsed columns; integer-valued doubles
# are coerced to integer after the range check (segments are far below
# the 2^31 boundary).
msuiter_segments_assemble <- function(sample, chrom, start, end, minor,
                                      major, rows) {
  to_int <- function(v, col) {
    if (any(!is.finite(v)) || any(v > .Machine$integer.max)) {
      msuiter_abort(
        "segments",
        paste0("column '", col, "' is out of the integer range"),
        i = "copy numbers and coordinates are small integers",
        j = paste0("offending rows: ", msuiter_quote_trunc(which(!is.finite(v) | v > .Machine$integer.max))),
        c = "check the caller output for corrupted values"
      )
    }
    as.integer(v)
  }
  out <- data.frame(
    chrom = as.character(chrom), start = start, end = end,
    minor = to_int(minor, "minor"), major = to_int(major, "major"),
    stringsAsFactors = FALSE
  )
  if (!is.null(sample)) {
    out <- cbind(sample = as.character(sample), out)
  }
  rownames(out) <- NULL
  out
}

# Canonical-form validation for the direct data.frame path: the five
# canonical columns plus optional sample, integer-valued, no missing
# values anywhere.
msuiter_segments_canonical <- function(x) {
  if (nrow(x) == 0L) {
    msuiter_abort(
      "input",
      "the canonical segment table has no rows",
      i = "a direct-construction input must carry at least one segment",
      j = "the table has 0 rows",
      c = "check the table upstream of ms_segments()"
    )
  }
  required <- c("chrom", "start", "end", "minor", "major")
  absent <- setdiff(required, names(x))
  if (length(absent) > 0L) {
    msuiter_abort(
      "input",
      "the canonical segment table is missing required columns",
      i = paste0("required columns: ", paste(required, collapse = ", ")),
      j = paste0("missing: ", msuiter_quote_trunc(absent)),
      c = "pass chrom/start/end/minor/major, or read a caller file"
    )
  }
  sample <- if ("sample" %in% names(x)) x$sample else NULL
  chrom <- trimws(as.character(x$chrom))
  parse_num <- function(v, col, min_value) {
    v <- suppressWarnings(as.numeric(v))
    bad <- which(is.na(v) | !is.finite(v) | v != floor(v) | v < min_value)
    if (length(bad) > 0L) {
      msuiter_abort(
        "segments",
        paste0(
          "the canonical column '", col,
          "' must contain integer values >= ", min_value
        ),
        i = "canonical segments carry integer coordinates and copy numbers",
        j = paste0("offending rows: ", msuiter_quote_trunc(bad)),
        c = "write plain integers, or read a caller file for column repair"
      )
    }
    v
  }
  start <- parse_num(x$start, "start", 1)
  end <- parse_num(x$end, "end", 1)
  minor <- parse_num(x$minor, "minor", 0)
  major <- parse_num(x$major, "major", 0)
  rows <- seq_len(nrow(x))
  table <- msuiter_segments_assemble(sample, chrom, start, end, minor, major,
    rows = rows
  )
  msuiter_segments_validate(table, rows, NULL)
  attr(table, "parse_stats") <- list(
    n_lines = nrow(table),
    n_records = nrow(table),
    n_expanded = 0L,
    n_skipped = 0L,
    skip_reasons = table(character(0L))
  )
  table
}

# ---------------------------------------------------------------------------
# Per-caller column mapping (the SPMG anchors live at the top of the file)
# ---------------------------------------------------------------------------

msuiter_segments_from_caller <- function(tab, caller, chrom_col, src) {
  if (nrow(tab) == 0L) {
    msuiter_abort(
      "io",
      "no segment records could be parsed",
      i = "the segmentation file has a header but no data rows",
      j = basename(src),
      c = "check that the file is the intended caller output"
    )
  }
  profile <- msuiter_segment_profiles[[caller]]
  chrom_name <- if (is.null(chrom_col)) profile$chrom else chrom_col
  if (!is.null(chrom_col) && !chrom_col %in% names(tab)) {
    msuiter_abort(
      "io",
      "the requested chromosome column does not exist in the file",
      i = "chrom_col overrides the caller's default chromosome column",
      j = paste0("'", chrom_col, "' not found in ", basename(src)),
      c = "use the exact column name, or omit chrom_col"
    )
  }
  need <- c(
    chrom_name, profile$start, profile$end,
    switch(caller,
      ASCAT = c("nMajor", "nMinor"),
      ASCAT_NGS = c("Tumour TCN", "Tumour BCN"),
      ABSOLUTE = c("Modal_HSCN_1", "Modal_HSCN_2"),
      PCAWG = c("copy_number", "mutation_type"),
      FACETS = c("tcn.em", "lcn.em"),
      BATTENBERG = c("nMaj1_A", "nMin1_A"),
      PURPLE = c("minorAlleleCopyNumber", "majorAlleleCopyNumber"),
      SEQUENZA = c("CNt", "A", "B")
    )
  )
  absent <- setdiff(need, names(tab))
  if (length(absent) > 0L) {
    msuiter_abort(
      "io",
      paste0("the ", caller, " segmentation file is missing required columns"),
      i = paste0("required columns: ", paste(need, collapse = ", ")),
      j = paste0("missing: ", msuiter_quote_trunc(absent)),
      c = paste0(
        "check the caller label (auto-detection may have mismatched), ",
        "or re-export the caller output"
      )
    )
  }

  sample <- if ("sample" %in% names(tab)) trimws(tab$sample) else NULL
  chrom <- trimws(tab[[chrom_name]])
  start <- msuiter_segment_parse_int(tab[[profile$start]], profile$start,
    src, min_value = 1L
  )
  end <- msuiter_segment_parse_int(tab[[profile$end]], profile$end, src,
    min_value = 1L
  )
  rows <- seq_len(nrow(tab))

  # Derive the ordered (minor, major) pair per caller. Upstream's CN
  # class and LOH status consume the SUM and a zero-test of the pair
  # (:104-295), so for the callers whose columns have no declared
  # order (ASCAT_NGS, ABSOLUTE, SEQUENZA) reordering the pair cannot
  # change the CN48 channel; declared-role callers are validated, not
  # reordered.
  minor <- major <- NULL
  n_records <- nrow(tab)
  skip_reasons <- table(character(0L))
  n_skipped <- 0L
  n_expanded <- 0L

  if (caller == "ASCAT") {
    # nMajor/nMinor declared (:104-116, :196-204).
    minor <- msuiter_segment_parse_int(tab$nMinor, "nMinor", src, 0)
    major <- msuiter_segment_parse_int(tab$nMajor, "nMajor", src, 0)
  } else if (caller == "ASCAT_NGS") {
    # minor allele = Tumour TCN - Tumour BCN (the "Tumour ACN", :215-221);
    # the pair is unordered upstream (zero-test :226-232) -> canonicalize.
    tcn <- msuiter_segment_parse_int(tab[["Tumour TCN"]], "Tumour TCN", src, 0)
    bcn <- msuiter_segment_parse_int(tab[["Tumour BCN"]], "Tumour BCN", src, 0)
    acn <- tcn - bcn
    neg <- which(acn < 0L)
    if (length(neg) > 0L) {
      msuiter_abort(
        "io",
        "Tumour BCN exceeds Tumour TCN",
        i = "the B-allele copy number cannot exceed the total copy number",
        j = paste0(basename(src), ", offending rows: ", msuiter_quote_trunc(neg)),
        c = "repair the caller output"
      )
    }
    minor <- pmin(acn, bcn)
    major <- pmax(acn, bcn)
  } else if (caller == "ABSOLUTE") {
    # Modal_HSCN_1/2: unordered haploid allele states (:117-129, :234-242).
    a <- msuiter_segment_parse_int(tab$Modal_HSCN_1, "Modal_HSCN_1", src, 0)
    b <- msuiter_segment_parse_int(tab$Modal_HSCN_2, "Modal_HSCN_2", src, 0)
    minor <- pmin(a, b)
    major <- pmax(a, b)
  } else if (caller == "PCAWG") {
    # No allele split in the format: derive (minor, major) from
    # copy_number + mutation_type (:130-141, :243-258).
    tcn <- msuiter_segment_parse_int(tab$copy_number, "copy_number", src, 0)
    mtype <- trimws(tab$mutation_type)
    mtype[is.na(mtype)] <- "" # NA labels land in the unsupported-value error
    minor <- rep(NA_real_, length(tcn))
    major <- rep(NA_real_, length(tcn))
    loh <- mtype %in% c("copy neutral LOH", "amp LOH", "hemizygous del LOH")
    zero <- !loh & mtype == "loss" & tcn == 0
    one <- !loh & mtype == "loss" & tcn == 1
    het <- mtype %in% c("copy neutral", "gain")
    minor[loh] <- 0
    major[loh] <- tcn[loh]
    minor[zero] <- 0
    major[zero] <- 0
    minor[one] <- 0
    major[one] <- 1
    minor[het] <- 1
    major[het] <- tcn[het] - 1
    bad_tcn_loh <- which(loh & tcn == 0)
    bad_tcn_het <- which(het & tcn < 2)
    bad_loss <- which(!loh & mtype == "loss" & tcn >= 2)
    bad_type <- which(!loh & !zero & !one & !het &
      mtype != "loss")
    problems <- list(
      list(bad_tcn_loh, "LOH-labelled PCAWG row with total copy number 0",
        "upstream would tally it as LOH (mutation_type test :243-252) while the total says homdel",
        "repair the copy_number/mutation_type pair"),
      list(bad_tcn_het, "het-labelled PCAWG row with total copy number below 2",
        "upstream would target the nonexistent '1:het' channel (:253-254)",
        "repair the copy_number/mutation_type pair"),
      list(bad_loss, "'loss' PCAWG row with total copy number >= 2",
        "upstream leaves its LOH list unsynchronised and crashes on the assignment (:255-259, :304)",
        "reclassify the segment with the proper mutation_type"),
      list(bad_type, "unsupported PCAWG mutation_type",
        paste0(
          "handled values: copy neutral LOH, amp LOH, hemizygous del LOH, ",
          "loss (total CN 0/1), copy neutral, gain (:243-258)"
        ),
        "reclassify the segment with a handled mutation_type")
    )
    for (p in problems) {
      if (length(p[[1L]]) > 0L) {
        msuiter_abort(
          "segments",
          p[[2L]],
          i = p[[3L]],
          j = paste0(basename(src), ", offending rows: ", msuiter_quote_trunc(p[[1L]])),
          c = p[[4L]]
        )
      }
    }
  } else if (caller == "FACETS") {
    # minor = lcn.em; a missing lcn.em is meaningful upstream (LOH,
    # :262-271) and maps to minor = 0. lcn.em above half of tcn.em
    # contradicts the "less-copy number" semantics and is rejected.
    tcn <- msuiter_segment_parse_int(tab[["tcn.em"]], "tcn.em", src, 0)
    lcn <- msuiter_segment_parse_int(tab[["lcn.em"]], "lcn.em", src, 0,
      na_allowed = TRUE
    )
    lcn[is.na(lcn)] <- 0
    minor <- lcn
    major <- tcn - lcn
  } else if (caller == "BATTENBERG") {
    # Clonal (nMaj1_A/nMin1_A) plus optional subclonal (nMaj2_A/nMin2_A)
    # blocks; both present blocks tally as separate events upstream
    # (:401-425). A block whose values are missing is counted into the
    # ledger (upstream dropna, :404-405), never silently dropped.
    if (any(c("nMaj2_A", "nMin2_A") %in% names(tab)) &&
      !all(c("nMaj2_A", "nMin2_A") %in% names(tab))) {
      msuiter_abort(
        "io",
        "the Battenberg subclonal block is incomplete",
        i = "the subclonal block needs both nMaj2_A and nMin2_A",
        j = basename(src),
        c = "export both subclonal columns, or neither"
      )
    }
    maj1 <- msuiter_segment_parse_int(tab$nMaj1_A, "nMaj1_A", src, 0,
      na_allowed = TRUE
    )
    min1 <- msuiter_segment_parse_int(tab$nMin1_A, "nMin1_A", src, 0,
      na_allowed = TRUE
    )
    keep1 <- !(is.na(maj1) | is.na(min1))
    blocks <- list(list(
      rows = which(keep1), minor = min1[keep1], major = maj1[keep1]
    ))
    n_dropped <- sum(!keep1)
    if (all(c("nMaj2_A", "nMin2_A") %in% names(tab))) {
      maj2 <- msuiter_segment_parse_int(tab$nMaj2_A, "nMaj2_A", src, 0,
        na_allowed = TRUE
      )
      min2 <- msuiter_segment_parse_int(tab$nMin2_A, "nMin2_A", src, 0,
        na_allowed = TRUE
      )
      keep2 <- !(is.na(maj2) | is.na(min2))
      blocks <- c(blocks, list(list(
        rows = which(keep2), minor = min2[keep2], major = maj2[keep2]
      )))
      n_dropped <- n_dropped + sum(!keep2)
    }
    n_expanded <- if (length(blocks) > 1L) length(blocks[[2L]]$rows) else 0L
    # Expand chrom/coords/sample per record: each kept block repeats its
    # source row's position fields (:402-403 selects them per block).
    idx_all <- unlist(lapply(blocks, `[[`, "rows"), use.names = FALSE)
    rows <- idx_all
    chrom <- chrom[idx_all]
    start <- start[idx_all]
    end <- end[idx_all]
    if (!is.null(sample)) {
      sample <- sample[idx_all]
    }
    minor <- unlist(lapply(blocks, `[[`, "minor"), use.names = FALSE)
    major <- unlist(lapply(blocks, `[[`, "major"), use.names = FALSE)
    n_skipped <- n_dropped
    if (n_dropped > 0L) {
      skip_reasons <- table(rep("missing_cn_block", n_dropped))
    }
    n_records <- length(minor)
    table <- msuiter_segments_assemble(sample, chrom, start, end, minor,
      major, rows = rows
    )
    msuiter_segments_validate(table, rows, src)
    attr(table, "parse_stats") <- list(
      n_lines = nrow(tab),
      n_records = n_records,
      n_expanded = n_expanded,
      n_skipped = n_skipped,
      skip_reasons = skip_reasons
    )
    return(table)
  } else if (caller == "PURPLE") {
    # Declared roles (:167-183, :282-295): validate, do not reorder.
    minor <- msuiter_segment_parse_int(
      tab[["minorAlleleCopyNumber"]], "minorAlleleCopyNumber", src, 0
    )
    major <- msuiter_segment_parse_int(
      tab[["majorAlleleCopyNumber"]], "majorAlleleCopyNumber", src, 0
    )
  } else if (caller == "SEQUENZA") {
    # CNt total with alleles A, B (:92-103, :206-213); the pair is
    # unordered upstream (zero-test :207-213) -> canonicalize.
    cnt <- msuiter_segment_parse_int(tab$CNt, "CNt", src, 0)
    a <- msuiter_segment_parse_int(tab$A, "A", src, 0)
    b <- msuiter_segment_parse_int(tab$B, "B", src, 0)
    bad <- which(a + b != cnt)
    if (length(bad) > 0L) {
      msuiter_abort(
        "io",
        "Sequenza alleles A + B do not sum to CNt (msuiter io-layer legality rule; upstream :92-103/:206-213 does not validate and would count inconsistent rows)",
        i = "the allele copy numbers must reconstruct the total copy number",
        j = paste0(basename(src), ", offending rows: ", msuiter_quote_trunc(bad)),
        c = "repair the caller output"
      )
    }
    minor <- pmin(a, b)
    major <- pmax(a, b)
  }

  table <- msuiter_segments_assemble(sample, chrom, start, end, minor, major,
    rows = rows
  )
  msuiter_segments_validate(table, rows, src)
  attr(table, "parse_stats") <- list(
    n_lines = nrow(tab),
    n_records = nrow(table),
    n_expanded = 0L,
    n_skipped = 0L,
    skip_reasons = table(character(0L))
  )
  table
}
