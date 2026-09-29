# io-variants.R: the io-layer entry point ms_variants() (U-M1s-10).
#
# ARCHITECTURE.md section 3.1: the io layer is the only place that touches
# external formats; it reads VCF/TSV/MAF (optionally gzip-compressed, via
# the native gzfile connection) and funnels the canonical table plus the
# somaticness provenance into the MsVariants constructor. Division of
# labor (reading-time validation):
#   * io layer owns FORMAT repair -- column mapping, integer POS checks,
#     upper-casing alleles, multiallelic expansion, and the skip ledger
#     (A11: every skipped record is counted into provenance, never
#     silently dropped);
#   * the class validator (classes-variants.R) owns SEMANTIC checks --
#     required columns, coordinate legality, anyNA rejection, somaticness
#     signal. It runs on every path (second line of defense).
# TSV and data.frame inputs pass through strictly (no skip ledger): a
# broken user-authored row surfaces end to end as msuiter_error_variants.
# Binary BCF is rejected with msuiter_error_unsupported ("convert to VCF
# with bcftools view"). All failures raise msuiter_error_* conditions
# with the i/j/c payload (section 3.5); bare stop() is banned.
#
# Scope note (documented, not a gap): sample genotype columns of a VCF are
# NOT parsed in this unit -- the target scenario is filtered somatic
# caller output (sites-only or one-tumor VCFs used as a record list).
# VAF/FILTER passthrough comes from the fixed columns only.

# Somaticness provenance assembly shared by both methods: convert missing
# required arguments into project errors (the MsVariants validator would
# otherwise see an unevaluated missing value). Value types are checked by
# the validator; this helper only guards against missingness.
msuiter_variants_provenance <- function(genome, caller, matched_normal,
                                        vaf_floor) {
  if (missing(genome)) {
    msuiter_abort(
      "input",
      "the genome build is required",
      i = "MsVariants carries the genome build end to end",
      j = "argument 'genome' is missing",
      c = 'pass e.g. genome = "GRCh38"'
    )
  }
  if (missing(caller)) {
    msuiter_abort(
      "input",
      "the variant caller is required",
      i = "the caller labels the somaticness signal source",
      j = "argument 'caller' is missing",
      c = 'record the calling tool, e.g. caller = "mutect2"'
    )
  }
  if (missing(matched_normal)) {
    msuiter_abort(
      "input",
      "the matched normal status is required",
      i = 'matched-normal provenance is required ("none" for tumor-only)',
      j = "argument 'matched_normal' is missing",
      c = 'pass the matched normal sample id, or "none"'
    )
  }
  provenance <- list(caller = caller, matched_normal = matched_normal)
  if (!is.null(vaf_floor)) {
    provenance$vaf_floor <- vaf_floor
  }
  provenance
}

#' Read variant calls into an MsVariants object
#'
#' `ms_variants()` is the first link of the msuiter working grammar
#' (`ms_variants() |> ms_tally() |> ...`). It is an S7 generic: given a
#' file path it reads and validates VCF, TSV or MAF input (optionally
#' gzip-compressed) at load time and returns an [MsVariants]; given a
#' canonical data.frame it validates and constructs directly. All
#' violations raise `msuiter_error_*` conditions.
#'
#' @param x A character string naming one variant file (`.vcf`, `.tsv` or
#'   `.maf`, optionally `.gz`; `.bcf` is rejected with an actionable
#'   message), or a data.frame in canonical form (columns `chrom`,
#'   `start`, `end`, `ref`, `alt`, plus optional `vaf` and `filter`).
#' @param genome Genome build label, e.g. `"GRCh38"`.
#' @param caller Variant caller label; required somaticness provenance.
#' @param matched_normal Matched normal sample id, or `"none"` for
#'   tumor-only calls; required somaticness provenance.
#' @param vaf_floor Optional single numeric in `[0, 1]`; somaticness VAF
#'   floor recorded in provenance.
#' @param format Force the input format: `"vcf"`, `"tsv"` or `"maf"`.
#'   Defaults to the file extension. `format = "bcf"` is an error.
#' @param chrom_col,pos_col,end_col,ref_col,alt_col Input column names for
#'   the canonical columns (file input only). Defaults per format: TSV
#'   `chrom/pos/ref/alt` plus an optional `end` column (when absent, `end`
#'   is derived as `pos + nchar(ref) - 1`); MAF standard names
#'   `Chromosome/Start_Position/Reference_Allele/Tumor_Seq_Allele2` with
#'   optional `End_Position`. Applies to TSV and MAF.
#' @param filter_col Optional name of a FILTER-like column passed through
#'   untouched into the canonical `filter` column (file input only).
#' @param vaf_col Optional name of a numeric VAF-like column passed
#'   through into the canonical `vaf` column (file input only).
#' @param ... No passthrough arguments: anything arriving in `...` is
#'   rejected as an argument-spelling error (`msuiter_error_input`).
#'
#' @details
#' VCF parsing is minimally sufficient for filtered somatic caller output:
#' the `##fileformat` line is kept as provenance, the `#CHROM` header names
#' the columns, fixed columns `CHROM/POS/REF/ALT` are required and
#' `FILTER` is passed through (`. ` kept verbatim). Multi-allelic ALT
#' fields expand to one record per allele; symbolic (`<NON_REF>`),
#' breakend, missing (`.`) and spanning (`*`) alleles are skipped into the
#' provenance skip ledger. Sample genotype columns are not parsed in this
#' unit. MAF rows whose `Variant_Classification` is not SBS-eligible
#' (frame-shift/in-frame indels and structural variation) are counted into
#' the skip ledger, not routed -- routing arrives with the catalog layer.
#'
#' The returned `provenance` carries the somaticness signal fields plus
#' `source` (path), `format`, the `##fileformat` note (VCF) and `parse`
#' statistics (`n_lines`, `n_records`, `n_multiallelic_sites`,
#' `n_skipped`, `skip_reasons`, `skip_classifications`).
#'
#' @return An [MsVariants] object.
#' @examples
#' lines <- c(
#'   "##fileformat=VCFv4.2",
#'   "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO",
#'   "chr7\t55191822\t.\tC\tT\t.\tPASS\t.",
#'   "chr17\t7676594\t.\tCA\tC\t.\t.\t."
#' )
#' path <- tempfile(fileext = ".vcf")
#' writeLines(lines, path)
#' v <- ms_variants(path, "GRCh38",
#'   caller = "synthetic", matched_normal = "none")
#' v
#' unlink(path)
#'
#' # Canonical data.frame: validated direct construction
#' tab <- data.frame(chrom = "chr7", start = 55191822, end = 55191822,
#'   ref = "C", alt = "T")
#' ms_variants(tab, "GRCh38", caller = "synthetic", matched_normal = "none")
#' @export
ms_variants <- S7::new_generic(
  "ms_variants",
  "x",
  function(x, genome, caller, matched_normal, vaf_floor = NULL,
           format = NULL, chrom_col = NULL, pos_col = NULL, end_col = NULL,
           ref_col = NULL, alt_col = NULL, filter_col = NULL,
           vaf_col = NULL, ...) S7::S7_dispatch()
)

# Dots discipline: ms_variants() has no passthrough arguments; anything
# arriving in `...` is an argument-spelling error, never an ignored value.
msuiter_abort_dots <- function(dots) {
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
    "unknown argument passed to ms_variants()",
    i = "ms_variants() has no passthrough arguments",
    j = paste0("unexpected: ", msuiter_quote_trunc(labels)),
    c = "check the argument spelling against ?ms_variants"
  )
}

# Method: read one variant file. Dispatch by extension (or forced
# `format`), then funnel the canonical table + io provenance through the
# internal constructor.
S7::method(ms_variants, S7::class_character) <- function(
    x, genome, caller, matched_normal, vaf_floor = NULL,
    format = NULL, chrom_col = NULL, pos_col = NULL, end_col = NULL,
    ref_col = NULL, alt_col = NULL, filter_col = NULL, vaf_col = NULL,
    ...) {
  msuiter_abort_dots(list(...))
  provenance <- msuiter_variants_provenance(
    genome, caller, matched_normal, vaf_floor
  )
  if (length(x) != 1L || is.na(x) || !nzchar(x)) {
    msuiter_abort(
      "input",
      "x must be a single non-empty file path",
      i = "the character method of ms_variants() reads exactly one file",
      j = paste0("received a character vector of length ", length(x)),
      c = "pass the path of one .vcf/.tsv/.maf file (optionally .gz)"
    )
  }
  if (!file.exists(x)) {
    msuiter_abort(
      "io",
      "the variant file does not exist",
      i = "the io layer reads the file eagerly at call time",
      j = x,
      c = "check the path spelling and the working directory"
    )
  }
  if (dir.exists(x)) {
    msuiter_abort(
      "io",
      "the variant path is a directory, not a file",
      i = "the io layer reads regular files only",
      j = x,
      c = "pass the path of one variant file"
    )
  }

  fmt <- msuiter_variant_format(x, format)
  cols <- list(
    chrom = chrom_col, pos = pos_col, end = end_col, ref = ref_col,
    alt = alt_col, filter = filter_col, vaf = vaf_col
  )
  parsed <- switch(fmt$format,
    vcf = msuiter_read_vcf(x, fmt$compressed),
    tsv = msuiter_read_tabular(x, fmt$compressed, "tsv", cols),
    maf = msuiter_read_tabular(x, fmt$compressed, "maf", cols),
    # Unreachable: msuiter_variant_format() rejects everything else.
    msuiter_abort(
      "unsupported",
      "unsupported variant format",
      i = "supported formats are vcf, tsv and maf",
      j = paste0("resolved format: ", fmt$format),
      c = "convert to VCF with bcftools view"
    )
  )

  provenance$source <- x
  provenance$format <- fmt$format
  provenance$parse <- parsed$parse
  if (length(parsed$fileformat) > 0L) {
    provenance$fileformat <- parsed$fileformat
  }
  ms_variants_from_table(parsed$table, genome, provenance)
}

# Method: canonical data.frame, validated direct construction. File-only
# column-mapping arguments are rejected instead of silently ignored.
S7::method(ms_variants, S7::class_data.frame) <- function(
    x, genome, caller, matched_normal, vaf_floor = NULL,
    format = NULL, chrom_col = NULL, pos_col = NULL, end_col = NULL,
    ref_col = NULL, alt_col = NULL, filter_col = NULL, vaf_col = NULL,
    ...) {
  msuiter_abort_dots(list(...))
  provenance <- msuiter_variants_provenance(
    genome, caller, matched_normal, vaf_floor
  )
  file_only <- list(
    format = format, chrom_col = chrom_col, pos_col = pos_col,
    end_col = end_col, ref_col = ref_col, alt_col = alt_col,
    filter_col = filter_col, vaf_col = vaf_col
  )
  given <- file_only[!vapply(file_only, is.null, logical(1L))]
  if (length(given) > 0L) {
    msuiter_abort(
      "input",
      "file-mapping arguments apply only when reading a file",
      i = "a data.frame is already canonical: only validation happens",
      j = paste0("unexpected arguments: ", paste(names(given), collapse = ", ")),
      c = "drop these arguments, or pass a file path instead"
    )
  }
  ms_variants_from_table(x, genome, provenance)
}

# Fallback: anything that is neither a path nor a table gets a project
# error instead of the raw S7 dispatch failure.
S7::method(ms_variants, S7::class_any) <- function(
    x, genome, caller, matched_normal, vaf_floor = NULL,
    format = NULL, chrom_col = NULL, pos_col = NULL, end_col = NULL,
    ref_col = NULL, alt_col = NULL, filter_col = NULL, vaf_col = NULL,
    ...) {
  msuiter_abort(
    "input",
    "x must be a variant file path or a canonical variant table",
    i = "ms_variants() dispatches on character paths and data.frames",
    j = paste0("received: ", class(x)[1L]),
    c = paste0(
      "pass a .vcf/.tsv/.maf path or a data.frame with columns ",
      "chrom/start/end/ref/alt"
    )
  )
}

# ---------------------------------------------------------------------------
# Format resolution
# ---------------------------------------------------------------------------

# Resolve the input format and compression from the file name, or honor a
# forced `format` (compression always comes from a `.gz` suffix). BCF and
# unrecognized extensions are rejected (msuiter_error_unsupported).
msuiter_variant_format <- function(path, format) {
  forced <- !is.null(format)
  if (forced &&
    (!is.character(format) || length(format) != 1L || is.na(format) ||
      !format %in% c("vcf", "tsv", "maf", "bcf"))) {
    msuiter_abort(
      "input",
      "format must be one of 'vcf', 'tsv', 'maf' or 'bcf'",
      i = "ms_variants() reads VCF, TSV and MAF; BCF is rejected",
      j = paste0("received: ", msuiter_quote_trunc(format)),
      c = "omit format to derive it from the file extension"
    )
  }
  m <- regmatches(
    tolower(basename(path)),
    regexec("\\.(vcf|tsv|maf|bcf)(\\.gz)?$", tolower(basename(path)))
  )[[1L]]
  if (forced) {
    if (format == "bcf") {
      msuiter_abort_bcf(path)
    }
    if (length(m) == 0L) {
      return(list(format = format, compressed = FALSE))
    }
    list(format = format, compressed = nzchar(m[3L]))
  } else {
    if (length(m) == 0L) {
      msuiter_abort(
        "unsupported",
        "unrecognized variant file extension",
        i = "supported extensions: .vcf, .tsv, .maf (optionally .gz)",
        j = basename(path),
        c = 'rename the file, or force the format with format = "tsv"'
      )
    }
    if (m[2L] == "bcf") {
      msuiter_abort_bcf(path)
    }
    list(format = m[2L], compressed = nzchar(m[3L]))
  }
}

msuiter_abort_bcf <- function(path) {
  msuiter_abort(
    "unsupported",
    "BCF input is not supported by ms_variants()",
    i = paste0(
      "the binary BCF container needs a codec stack the io layer ",
      "does not bundle"
    ),
    j = path,
    c = "convert to VCF with bcftools view and read the .vcf(.gz) output"
  )
}

# ---------------------------------------------------------------------------
# Shared low-level reading
# ---------------------------------------------------------------------------

# Read all lines of a plain or gzip-compressed text file through a native
# connection (base R; zero extra dependencies). Read failures (missing
# permission, corrupt gzip stream) are wrapped into msuiter_error_io.
msuiter_read_file_lines <- function(path, compressed) {
  con <- if (isTRUE(compressed)) gzfile(path, "rt") else file(path, "rt")
  on.exit(close(con), add = TRUE)
  tryCatch(
    readLines(con, warn = FALSE),
    error = function(e) {
      msuiter_abort(
        "io",
        "the variant file could not be read",
        i = "the io layer reads the file eagerly at call time",
        j = paste0(path, ": ", conditionMessage(e)),
        c = "check file permissions and integrity"
      )
    }
  )
}

# Coordinate column parser: the io layer enforces integer syntax; the
# `start >= 1` semantics stay with the class validator (so a zero
# coordinate surfaces end to end as msuiter_error_variants).
msuiter_parse_pos <- function(x, col, path) {
  bad <- which(is.na(x) | !grepl("^[0-9]+$", x))
  if (length(bad) > 0L) {
    msuiter_abort(
      "io",
      "the coordinate column must contain non-negative integers",
      i = "canonical coordinates are 1-based closed integers",
      j = paste0(
        "column '", col, "' in ", basename(path),
        ", offending rows: ", msuiter_quote_trunc(bad)
      ),
      c = "write coordinates as plain integers"
    )
  }
  as.numeric(x)
}

# ---------------------------------------------------------------------------
# VCF reader (minimally sufficient, base R)
# ---------------------------------------------------------------------------

msuiter_read_vcf <- function(path, compressed) {
  lines <- msuiter_read_file_lines(path, compressed)

  # Keep the ##fileformat meta line as a provenance note; all other meta
  # lines are skipped.
  meta <- lines[startsWith(lines, "##")]
  fileformat <- meta[startsWith(meta, "##fileformat=")]

  hdr <- which(startsWith(lines, "#CHROM"))
  if (length(hdr) != 1L) {
    msuiter_abort(
      "io",
      "could not find a unique #CHROM header line",
      i = "VCF files must declare their columns in a #CHROM line",
      j = basename(path),
      c = "read a valid VCF, or convert with bcftools view -Ov"
    )
  }
  cols <- sub("^#", "", strsplit(lines[hdr], "\t", fixed = TRUE)[[1L]])
  at <- function(nm) match(nm, cols)
  req <- c("CHROM", "POS", "REF", "ALT")
  absent <- req[vapply(req, function(nm) is.na(at(nm)), logical(1L))]
  if (length(absent) > 0L) {
    msuiter_abort(
      "io",
      "the VCF header is missing required fixed columns",
      i = paste0("required fixed columns: ", paste(req, collapse = ", ")),
      j = paste0("missing: ", msuiter_quote_trunc(absent)),
      c = "export the sites with bcftools view -Ov (CHROM POS REF ALT are mandatory)"
    )
  }
  f_at <- at("FILTER")

  body <- if (hdr < length(lines)) lines[(hdr + 1L):length(lines)] else character(0L)
  body <- body[nzchar(body)]
  if (length(body) == 0L) {
    msuiter_abort(
      "io",
      "no variant records could be parsed from the file",
      i = "the VCF has a header but no data lines",
      j = basename(path),
      c = "check that the file is the intended caller output"
    )
  }

  fields <- strsplit(body, "\t", fixed = TRUE)
  width <- vapply(fields, length, integer(1L))
  need <- max(c(vapply(req, at, integer(1L)), if (is.na(f_at)) 0L else f_at))
  short <- which(width < need)
  if (length(short) > 0L) {
    msuiter_abort(
      "io",
      "malformed VCF data line(s): too few tab-separated fields",
      i = paste0("the header declares ", length(cols), " columns"),
      j = paste0("offending lines: ", msuiter_quote_trunc(short)),
      c = "re-export the VCF; truncated records cannot be repaired"
    )
  }
  grab <- function(idx) vapply(fields, `[`, character(1L), idx)

  chrom <- trimws(grab(at("CHROM")))
  pos <- msuiter_parse_pos(trimws(grab(at("POS"))), "POS", path)
  ref <- toupper(trimws(grab(at("REF"))))
  alts <- strsplit(toupper(trimws(grab(at("ALT")))), ",", fixed = TRUE)
  # An empty ALT field splits to length zero: normalize to the missing
  # marker so the ledger accounts for it.
  alts <- lapply(alts, function(a) if (length(a) == 0L) "." else a)
  filt <- if (!is.na(f_at)) trimws(grab(f_at)) else NULL

  # Multiallelic expansion: one canonical record per ALT allele. Symbolic
  # (<...>, breakends), missing (.) and spanning (*) alleles are skipped
  # into the ledger (A11), never silently dropped.
  row_of <- rep(seq_along(alts), vapply(alts, length, integer(1L)))
  allele <- unlist(alts, use.names = FALSE)
  ref_of <- ref[row_of]
  reason <- rep("", length(allele))
  reason[allele == "."] <- "missing_alt"
  reason[allele == "*"] <- "spanning_star"
  reason[startsWith(allele, "<") | grepl("[][]", allele)] <- "symbolic_alt"
  reason[reason == "" & !grepl("^[ACGTN]+$", ref_of)] <- "invalid_ref"
  reason[reason == "" & !grepl("^[ACGTN]+$", allele)] <- "invalid_alt"
  keep <- reason == ""

  parse <- list(
    format = "vcf",
    n_lines = length(body),
    n_records = sum(keep),
    n_multiallelic_sites = sum(vapply(alts, length, integer(1L)) > 1L),
    n_skipped = sum(!keep),
    skip_reasons = table(reason[!keep])
  )
  if (parse$n_records == 0L) {
    msuiter_abort(
      "io",
      "no variant records could be parsed from the file",
      i = "every ALT allele was skipped as symbolic, missing or invalid",
      j = basename(path),
      c = "check the ALT encoding, or export plain alleles with bcftools"
    )
  }

  table <- data.frame(
    chrom = chrom[row_of][keep],
    start = pos[row_of][keep],
    end = pos[row_of][keep] + nchar(ref_of[keep]) - 1L,
    ref = ref_of[keep],
    alt = allele[keep],
    stringsAsFactors = FALSE
  )
  if (!is.null(filt)) {
    table$filter <- filt[row_of][keep] # FILTER confidence passthrough
  }
  list(
    table = table,
    parse = parse,
    fileformat = if (length(fileformat) > 0L) fileformat[1L] else character(0L)
  )
}

# ---------------------------------------------------------------------------
# TSV / MAF reader (tabular formats share one code path)
# ---------------------------------------------------------------------------

# MAF Variant_Classification values that are NOT single-base-substitution
# events. In this unit they are only counted into the skip ledger (no
# routing to DBS/ID pipelines yet -- that lands with the catalog layer).
msuiter_maf_non_sbs_classes <- c(
  "Frame_Shift_Del", "Frame_Shift_Ins", "In_Frame_Del", "In_Frame_Ins",
  "De_novo_Start_InFrame", "De_novo_Start_OutOfFrame",
  "Structural_Variation"
)

msuiter_read_tabular <- function(path, compressed, format, cols) {
  lines <- msuiter_read_file_lines(path, compressed)
  if (format == "maf") {
    # GDC-style MAFs carry a '#' preamble block; plain TSVs do not, and
    # their content passes through untouched.
    lines <- lines[!startsWith(lines, "#")]
  }
  if (length(lines) == 0L) {
    msuiter_abort(
      "io",
      "the variant file is empty",
      i = "a tabular input needs a header line and at least one record",
      j = basename(path),
      c = "check that the file is the intended input"
    )
  }
  tab <- utils::read.table(
    text = paste(lines, collapse = "\n"),
    sep = "\t", header = TRUE, quote = "", comment.char = "",
    check.names = FALSE, colClasses = "character", stringsAsFactors = FALSE
  )

  defaults <- if (format == "maf") {
    list(
      chrom = "Chromosome", pos = "Start_Position", end = "End_Position",
      ref = "Reference_Allele", alt = "Tumor_Seq_Allele2"
    )
  } else {
    list(chrom = "chrom", pos = "pos", end = "end", ref = "ref", alt = "alt")
  }
  nm_of <- function(user, def) if (is.null(user)) def else user
  chrom_col <- nm_of(cols$chrom, defaults$chrom)
  pos_col <- nm_of(cols$pos, defaults$pos)
  end_col <- nm_of(cols$end, defaults$end)
  ref_col <- nm_of(cols$ref, defaults$ref)
  alt_col <- nm_of(cols$alt, defaults$alt)

  needed <- c(chrom_col, pos_col, ref_col, alt_col)
  absent <- setdiff(needed, names(tab))
  if (length(absent) > 0L) {
    msuiter_abort(
      "io",
      "the input table is missing required columns",
      i = paste0("required columns: ", paste(needed, collapse = ", ")),
      j = paste0("missing: ", msuiter_quote_trunc(absent)),
      c = "map the file's column names with chrom_col/pos_col/ref_col/alt_col"
    )
  }
  for (opt in list(c("filter_col", cols$filter), c("vaf_col", cols$vaf))) {
    # c("x", NULL) collapses to length one: only a genuinely named column
    # must exist in the file.
    if (length(opt) == 2L && !opt[2L] %in% names(tab)) {
      msuiter_abort(
        "io",
        "the requested passthrough column does not exist in the file",
        i = paste0("passthrough column requested via ", opt[1L]),
        j = paste0("'", opt[2L], "' not found in ", basename(path)),
        c = "use the exact column name, or omit the argument"
      )
    }
  }

  # MAF skip ledger (A11): rows that cannot become SBS records in this
  # unit are counted, never silently dropped. Non-SBS classifications
  # first; unusable allele fields (MAF writes "-" for missing alleles)
  # and length-mismatched pairs second. This unit only counts; routing
  # arrives with the catalog layer. TSV inputs pass through strictly: a
  # broken user-authored row surfaces end to end through the class
  # validator as msuiter_error_variants.
  parse <- list(
    format = format,
    n_lines = nrow(tab),
    n_records = nrow(tab),
    n_skipped = 0L,
    skip_reasons = table(character(0L))
  )
  keep <- rep(TRUE, nrow(tab))
  if (format == "maf") {
    reason <- rep("", nrow(tab))
    has_cls <- "Variant_Classification" %in% names(tab)
    if (has_cls) {
      non_sbs <- tab$Variant_Classification %in% msuiter_maf_non_sbs_classes
      keep <- !non_sbs
      reason[non_sbs] <- "classification"
    }
    ref_all <- toupper(trimws(tab[[ref_col]]))
    alt_all <- toupper(trimws(tab[[alt_col]]))
    unusable <- !grepl("^[ACGTN]+$", ref_all) |
      !grepl("^[ACGTN]+$", alt_all) |
      nchar(ref_all) != nchar(alt_all)
    drop_allele <- keep & unusable
    reason[drop_allele] <- "allele"
    keep <- keep & !unusable

    parse$n_records <- sum(keep)
    parse$n_skipped <- sum(!keep)
    parse$skip_reasons <- table(reason[!keep])
    if (has_cls) {
      # Ledger by the file's own classification labels, whatever they are.
      parse$skip_classifications <- table(tab$Variant_Classification[!keep])
    }
  }
  if (parse$n_records == 0L) {
    msuiter_abort(
      "io",
      "no variant records could be parsed from the file",
      i = "every record was skipped as non-SBS or allele-unusable",
      j = basename(path),
      c = "check the allele columns and Variant_Classification values"
    )
  }

  tab <- tab[keep, , drop = FALSE]
  chrom <- trimws(tab[[chrom_col]])
  pos <- msuiter_parse_pos(trimws(tab[[pos_col]]), pos_col, path)
  ref <- toupper(trimws(tab[[ref_col]]))
  alt <- toupper(trimws(tab[[alt_col]]))

  if (end_col %in% names(tab)) {
    end <- msuiter_parse_pos(trimws(tab[[end_col]]), end_col, path)
  } else {
    # 1-based closed span of the reference allele.
    end <- pos + nchar(ref) - 1L
  }

  table <- data.frame(
    chrom = chrom, start = pos, end = end, ref = ref, alt = alt,
    stringsAsFactors = FALSE
  )
  if (!is.null(cols$filter)) {
    table$filter <- trimws(tab[[cols$filter]])
  }
  if (!is.null(cols$vaf)) {
    vaf <- suppressWarnings(as.numeric(trimws(tab[[cols$vaf]])))
    if (anyNA(vaf)) {
      msuiter_abort(
        "io",
        "the vaf passthrough column must contain numeric values",
        i = "vaf is a somaticness signal passthrough in [0, 1]",
        j = paste0(
          "column '", cols$vaf, "' in ", basename(path),
          ", offending rows: ", msuiter_quote_trunc(which(is.na(vaf)))
        ),
        c = "write vaf as decimal numbers, or omit vaf_col"
      )
    }
    table$vaf <- vaf
  }
  list(table = table, parse = parse, fileformat = character(0L))
}
