# MsVariants: the L2 input container.
#
# table: a canonical variant table (chrom / start / end / ref / alt);
# genome: genome build label (e.g. "GRCh38");
# provenance: somaticness signal fields (caller + matched-normal status),
#   per ARCHITECTURE.md section 3.2 (caller and matched-normal provenance are
#   required, optional VAF floor, FILTER passthrough column).

#' MsVariants: validated variant calls with somaticness provenance
#'
#' An [MsVariants] object holds a canonical variant table plus the genome
#' build and the somaticness signal provenance. It is the input container
#' for [ms_catalog()] and the tally step. Channel/label matching everywhere
#' in msuiter is by label, never by position.
#'
#' @details
#' Required columns of `table`: `chrom`, `start`, `end`, `ref`, `alt`.
#' Optional columns: `vaf` (numeric in [0, 1]) and `filter` (character,
#' FILTER confidence passthrough). Coordinates are 1-based and closed
#' (`start >= 1`, `end >= start`); alleles are uppercase `A/C/G/T/N`.
#'
#' Required `provenance` fields: `caller` (non-empty character) and
#' `matched_normal` (single character, `"none"` for tumor-only calls).
#' Optional field: `vaf_floor` (numeric in [0, 1]).
#'
#' @param table data.frame with the canonical variant columns.
#' @param genome single non-empty string naming the genome build.
#' @param provenance named list with the somaticness signal fields.
#'
#' @export
MsVariants <- S7::new_class(
  "MsVariants",
  package = "msuiter",
  properties = list(
    table = S7::new_property(S7::class_any),
    genome = S7::new_property(S7::class_character),
    provenance = S7::new_property(S7::class_list)
  ),
  validator = function(self) msuiter_validate_variants(self)
)

# Validator for MsVariants. Aborts (instead of returning problem strings) so
# that every violation path -- construction, `@<-` mutation, validate() --
# raises the project error class `msuiter_error_variants`.
msuiter_validate_variants <- function(self) {
  table <- self@table

  if (!is.data.frame(table)) {
    msuiter_abort(
      "variants",
      "the variant table must be a data.frame",
      i = "MsVariants stores a canonical variant table",
      j = paste0("received: ", class(table)[1L]),
      c = "parse calls through the io layer (ms_variants())"
    )
  }

  required <- c("chrom", "start", "end", "ref", "alt")
  absent <- setdiff(required, names(table))
  if (length(absent) > 0L) {
    msuiter_abort(
      "variants",
      "the variant table is missing required columns",
      i = paste0("required columns: ", paste(required, collapse = ", ")),
      j = paste0("missing: ", msuiter_quote_trunc(absent)),
      c = "map the caller output onto the canonical column names"
    )
  }

  if (anyNA(table)) {
    bad_cols <- vapply(table, anyNA, logical(1))
    msuiter_abort(
      "variants",
      "the variant table must not contain NA values",
      i = "NA coordinates or alleles cannot be tallied (FFI contract)",
      j = paste0("columns with NA: ", msuiter_quote_trunc(names(bad_cols)[bad_cols])),
      c = "drop or impute offending records before building MsVariants"
    )
  }

  if (!is.numeric(table$start) || !is.numeric(table$end)) {
    msuiter_abort(
      "variants",
      "variant coordinates must be numeric",
      i = "start/end are 1-based closed coordinates",
      j = paste0(
        "start is ", class(table$start)[1L],
        ", end is ", class(table$end)[1L]
      ),
      c = "coerce coordinate columns to double or integer"
    )
  }

  bad_coord <- which(table$start < 1 | table$end < table$start)
  if (length(bad_coord) > 0L) {
    msuiter_abort(
      "variants",
      "variant coordinates are illegal",
      i = "coordinates must satisfy start >= 1 and end >= start",
      j = paste0("offending rows: ", msuiter_quote_trunc(bad_coord)),
      c = "fix the coordinate system at the io layer"
    )
  }

  bad_chrom <- which(!is.character(table$chrom) | is.na(table$chrom) | !nzchar(table$chrom))
  if (length(bad_chrom) > 0L) {
    msuiter_abort(
      "variants",
      "chrom must be a non-empty character column",
      i = "contig labels are identities and are matched by label",
      j = paste0("offending rows: ", msuiter_quote_trunc(bad_chrom)),
      c = "fill in the contig label for every record"
    )
  }

  allele_pattern <- "^[ACGTN]+$"
  for (col in c("ref", "alt")) {
    x <- table[[col]]
    bad <- if (!is.character(x)) {
      seq_along(x)
    } else {
      which(!nzchar(x) | !grepl(allele_pattern, x))
    }
    if (length(bad) > 0L) {
      msuiter_abort(
        "variants",
        paste0("allele column '", col, "' contains invalid alleles"),
        i = "alleles must be uppercase A/C/G/T/N strings",
        j = paste0("offending rows: ", msuiter_quote_trunc(bad)),
        c = "normalize alleles (upper-case, symbol-free) before tallying"
      )
    }
  }

  if ("vaf" %in% names(table)) {
    if (!is.numeric(table$vaf) || any(table$vaf < 0 | table$vaf > 1)) {
      msuiter_abort(
        "variants",
        "the optional 'vaf' column must be numeric in [0, 1]",
        i = "vaf is a somaticness signal passthrough",
        j = paste0("offending rows: ",
          msuiter_quote_trunc(which(!is.numeric(table$vaf) |
            table$vaf < 0 | table$vaf > 1))),
        c = "recompute vaf or drop the column"
      )
    }
  }
  if ("filter" %in% names(table) && !is.character(table$filter)) {
    msuiter_abort(
      "variants",
      "the optional 'filter' column must be character (FILTER passthrough)",
      i = "FILTER classifications are passed through untouched",
      j = paste0("received: ", class(table$filter)[1L]),
      c = "keep filter labels as characters"
    )
  }

  # genome must be a single non-empty string.
  genome <- self@genome
  if (!is.character(genome) || length(genome) != 1L || is.na(genome) || !nzchar(genome)) {
    msuiter_abort(
      "variants",
      "genome must be a single non-empty string",
      i = "the genome build is carried through provenance end to end",
      j = paste0("received: ", if (length(genome) == 0L) "empty" else paste(genome, collapse = ", ")),
      c = 'pass e.g. genome = "GRCh38"'
    )
  }

  msuiter_validate_somaticness(self@provenance)
  NULL
}

# Somaticness signal fields (first ctDNA/CHIP failure-mode defense): caller
# and matched-normal status are required, optional VAF floor.
msuiter_validate_somaticness <- function(provenance) {
  if (!is.list(provenance) || !is.character(names(provenance)) || any(!nzchar(names(provenance)))) {
    msuiter_abort(
      "variants",
      "provenance must be a named list",
      i = "somaticness signals are carried as named provenance fields",
      j = paste0("received: ", class(provenance)[1L], " with names: ",
        msuiter_quote_trunc(names(provenance))),
      c = "provide at least caller and matched_normal"
    )
  }
  if (!"caller" %in% names(provenance)) {
    msuiter_abort(
      "variants",
      "provenance is missing the somaticness signal field 'caller'",
      i = "the calling tool is required to judge somaticness",
      j = paste0("present fields: ", msuiter_quote_trunc(names(provenance))),
      c = "record the variant caller, e.g. caller = \"mutect2\""
    )
  }
  if (!"matched_normal" %in% names(provenance)) {
    msuiter_abort(
      "variants",
      "provenance is missing the somaticness signal field 'matched_normal'",
      i = "matched-normal status is required (use \"none\" for tumor-only)",
      j = paste0("present fields: ", msuiter_quote_trunc(names(provenance))),
      c = 'record the matched normal id or "none"'
    )
  }
  caller <- provenance$caller
  if (!is.character(caller) || anyNA(caller) || any(!nzchar(caller))) {
    msuiter_abort(
      "variants",
      "provenance$caller must be a non-empty character value",
      i = "the caller labels the somaticness signal source",
      j = paste0("received: ", msuiter_quote_trunc(caller)),
      c = "record the calling tool name"
    )
  }
  matched <- provenance$matched_normal
  if (!is.character(matched) || length(matched) != 1L || is.na(matched) || !nzchar(matched)) {
    msuiter_abort(
      "variants",
      "provenance$matched_normal must be a single non-empty string",
      i = "matched-normal status is required for the somaticness signal",
      j = paste0("received: ", msuiter_quote_trunc(matched)),
      c = 'use the sample id of the matched normal, or "none"'
    )
  }
  if ("vaf_floor" %in% names(provenance)) {
    floor1 <- provenance$vaf_floor
    if (!is.numeric(floor1) || length(floor1) != 1L || is.na(floor1) ||
      floor1 < 0 || floor1 > 1) {
      msuiter_abort(
        "variants",
        "provenance$vaf_floor must be a single numeric in [0, 1]",
        i = "vaf_floor is the optional somaticness VAF floor",
        j = paste0("received: ", msuiter_quote_trunc(floor1)),
        c = "set vaf_floor to a probability, or omit it"
      )
    }
  }
  NULL
}

# Internal constructor: the single validation sink shared by the
# `ms_variants()` methods (R/io-variants.R, U-M1s-10). The user-facing
# entry point `ms_variants()` is an S7 generic dispatching on `x`
# (character file path or canonical data.frame); both paths funnel their
# table plus somaticness provenance through this constructor, so the
# MsVariants validator (required columns, coordinate legality, anyNA
# rejection, somaticness signal) runs on every entry. All violations
# raise errors of class `msuiter_error_variants`.
ms_variants_from_table <- function(table, genome, provenance) {
  out <- MsVariants(table = table, genome = genome, provenance = provenance)
  out
}

# One-line print/format: class name / dimensions / genome build.
S7::method(format, MsVariants) <- function(x, ...) {
  sprintf(
    "<MsVariants> %d variants | genome: %s",
    nrow(x@table), x@genome
  )
}

S7::method(print, MsVariants) <- function(x, ...) {
  cat(format(x, ...), "\n", sep = "")
  invisible(x)
}
