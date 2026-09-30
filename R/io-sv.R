# io-sv.R: the io-layer entry point ms_sv() (M1c input-layer wiring;
# CAPABILITY-MATRIX L-A row "SV 输入"; consumes the verified SV32
# arithmetic of src/rust/catalog/src/sv32.rs, whose SvRecord carries
# sv_type, size_bp = |start1 - start2| and the clustered flag).
#
# Semantic gold standard: SigProfilerMatrixGenerator (SPMG)
# `SVMatrixGenerator.py`, audited at upstream master `edccbea6` (line
# references are master):
#   * BEDPE fields and format gate: processBEDPE (:1037-1091) and the
#     generateSVMatrix column check (:985-997); the documented contract
#     is the six coordinate columns plus either an `svclass` column or
#     the `strand1`/`strand2` pair (BRASS convention).
#   * svclass derivation from strands (:1100-1128): different
#     chromosomes -> translocation; (+,-)/(-,+) -> inversion;
#     (+,+) -> deletion; (-,-) -> tandem-duplication; anything else is
#     an upstream Exception (:1123-1126). A provided `svclass` column is
#     consumed verbatim (:1129-1130).
#   * size: |start1 - start2| for every event (:1138-1159); the
#     <1 kb non-translocation drop (:1181-1189) is a CATALOG-layer rule
#     here (sv32.rs Sv32Outcome::TooShortNoChannel), so the io layer
#     keeps every record and only reports the count.
#   * kat-region clustering: annotateBedpe (:797-930). Both breakpoints
#     of every rearrangement are pooled per chromosome and sorted by
#     position (:804-821); intermutational distances are computed with
#     the first breakpoint of a chromosome measured from 0 and zero
#     distances clamped to 1 (calcIntermutDist2, :309-341, branch
#     first_chrom_na=False); the threshold is
#     genome_size / n_breakpoints / PEAK_FACTOR with genome_size = 3e9
#     (:824) and PEAK_FACTOR = 10 (:831, :845); gamma = 25 * MAD of the
#     distances (gamma_sdev :830, getMad :349-356 with a zero-padded
#     running median of window 25); chromosomes with more than
#     MIN_BPS = 10 breakpoints (:825-827, :860-862) are segmented by
#     exactPcf with kmin = 10 (:864, exactPcf :359-468); kat regions are
#     extracted and filtered with the fixed annotateBedpe parameter set
#     (extract_kat_regions :625-791; kmin_samples = 1, pvalue_thresh =
#     1, rate_factor_thresh = 1, doMerging = True, kmin_filter = kmin =
#     10, :872-890; the rate_factor >= 1 gate via assignPvalues
#     :485-501); the clustered flag is propagated to every breakpoint
#     inside a flagged region (:893-901) and a rearrangement is
#     clustered when ANY of its two breakpoints is flagged (:916-927).
#
# The exactPcf/extract_kat_regions port below is validated
# breakpoint-for-breakpoint against real upstream annotateBedpe output
# on 34 golden BEDPEs (4 scenario + 30 randomized; identical
# is_clustered vectors, 2026-09-30).
#
# Deliberate divergences (documented, not gaps):
#   * chromosome names are passed through verbatim. Upstream strips a
#     leading "chr" (processBEDPE :1041-1055) because its matrix writer
#     needs plain numerals; msuiter's catalog layer is chromosome-
#     opaque, so the io layer keeps the caller's labels.
#   * the `sample` column is optional (upstream raises without it,
#     :985-997, because one file = one sample there). msuiter reads one
#     sample per call; when a `sample` column is present it is passed
#     through and the kat annotation runs per sample group (upstream
#     runs per file), which reproduces the upstream behaviour for
#     per-sample files.
#   * an `is_clustered` input column is ignored: upstream overwrites it
#     unconditionally (:919-926).
# All failures raise msuiter_error_* conditions with the i/j/c payload
# (ARCHITECTURE.md section 3.5); bare stop() is banned.

msuiter_sv_abort_dots <- function(dots) {
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
    "unknown argument passed to ms_sv()",
    i = "ms_sv() has no passthrough arguments",
    j = paste0("unexpected: ", msuiter_quote_trunc(labels)),
    c = "check the argument spelling against ?ms_sv"
  )
}

#' Read structural-variant calls (BEDPE) into a typed table
#'
#' `ms_sv()` is the SV input link of the msuiter grammar. It is an S7
#' generic: given a file path it reads a BEDPE file (`.bedpe`, optionally
#' `.gz`), derives the rearrangement class and the kat-region clustered
#' flag exactly like SigProfilerMatrixGenerator and returns a typed
#' data.frame; given a data.frame with the same columns it runs the same
#' pipeline directly. All violations raise `msuiter_error_*` conditions.
#'
#' @param x A character string naming one BEDPE file (`.bedpe`,
#'   optionally `.gz`), or a data.frame carrying the six coordinate
#'   columns `chrom1, start1, end1, chrom2, start2, end2` plus either an
#'   `svclass` (or `SVTYPE`) column or the `strand1`/`strand2` pair, and
#'   optionally `sample`.
#' @param ... No passthrough arguments: anything arriving in `...` is
#'   rejected as an argument-spelling error (`msuiter_error_input`).
#'
#' @details
#' Rearrangement classes follow SPMG `SVMatrixGenerator.py` (master
#' `edccbea6`, :1100-1128): a provided `svclass`/`SVTYPE` column is used
#' verbatim and must contain exactly `deletion`, `tandem-duplication`,
#' `inversion` or `translocation` (foreign labels hit a KeyError
#' downstream upstream, :1251, and are rejected here at read time);
#' otherwise the strands decide: different chromosomes ->
#' `translocation`, mixed strands -> `inversion`, `(+,+)` ->
#' `deletion`, `(-,-)` -> `tandem-duplication`, anything else is an
#' error (:1123-1126). The short channel names `del`/`tds`/`inv`/`trans`
#' come from the upstream `svclass_mapping` (:1228-1233) and are applied
#' by the catalog layer (sv32.rs), not here.
#'
#' `size_bp` is `abs(start1 - start2)` for every event (:1138-1159;
#' ignored by SV32 for translocations, :1158-1161). BEDPE coordinates
#' are consumed verbatim (0-based half-open per the BEDPE
#' specification): every downstream quantity is a difference or an
#' ordering, hence offset-invariant. Non-translocation events below
#' 1000 bp are NOT dropped here -- the drop is the catalog layer's
#' ledger rule (:1184-1189); the io layer only reports
#' `n_below_1kb_non_trans` in the parse statistics.
#'
#' The `clustered` flag is the output of upstream `annotateBedpe`
#' (:797-930): breakpoints are pooled per chromosome (both ends of every
#' event), kat regions are segmented by exactPcf (`kmin = 10`,
# :864) on intermutational distances with threshold
#' `3e9 / n_breakpoints / 10` (:824-845) and `gamma = 25 * MAD`
# (:830, :847-851), regions must contain at least 10 breakpoints and a
#' breakpoint rate factor >= 1 (:872-890, assignPvalues :485-501), and a
#' rearrangement is clustered when any of its breakpoints falls in a kat
#' region (:916-927). Chromosomes with 10 or fewer breakpoints are never
#' clustered (:825-827, :860-862). The port is validated against real
#' upstream annotateBedpe goldens (34 BEDPEs, identical flags). Complexity
#' is O(n^2) in the breakpoints of a chromosome, as upstream's exactPcf.
#'
#' Chromosome names are passed through verbatim (upstream strips a
#' leading `chr`, :1041-1055 -- a deliberate divergence: the msuiter
#' catalog layer is chromosome-opaque). An `is_clustered` input column
#' is ignored (upstream overwrites it, :919-926).
#'
#' The returned `provenance` attribute carries `source`/`format`, the
#' `parse` statistics (`n_lines`, `n_records`, `n_derived_svclass`,
#' `n_provided_svclass`, `n_translocation`, `n_below_1kb_non_trans`) and
#' the `kat` parameter block (`kmin`, `min_bps`, `genome_size`,
#' `peak_factor`, `gamma_sdev`, `n_kat_regions`).
#'
#' @return A data.frame with columns `sample` (only when present in the
#'   input), `chrom1, start1, end1, chrom2, start2, end2` (verbatim
#'   coordinates), `svtype` (one of `deletion`, `tandem-duplication`,
#'   `inversion`, `translocation`), `size_bp` and `clustered`, with the
#'   io `provenance` in attribute `"provenance"`.
#' @examples
#' lines <- c(
#'   "chrom1\tstart1\tend1\tchrom2\tstart2\tend2\tstrand1\tstrand2",
#'   "19\t21268384\t21268385\t19\t21327858\t21327859\t+\t+",
#'   "19\t30000000\t30000001\t19\t31000000\t31000001\t+\t-",
#'   "3\t1000000\t1000001\t7\t2000000\t2000001\t+\t+"
#' )
#' path <- tempfile(fileext = ".bedpe")
#' writeLines(lines, path)
#' sv <- ms_sv(path)
#' sv$svtype
#' sv$clustered # sparse input: no chromosome exceeds the 10-breakpoint gate
#' unlink(path)
#' @export
ms_sv <- S7::new_generic(
  "ms_sv",
  "x",
  function(x, ...) S7::S7_dispatch()
)

# Method: read one BEDPE file.
S7::method(ms_sv, S7::class_character) <- function(x, ...) {
  msuiter_sv_abort_dots(list(...))
  if (length(x) != 1L || is.na(x) || !nzchar(x)) {
    msuiter_abort(
      "input",
      "x must be a single non-empty file path",
      i = "the character method of ms_sv() reads exactly one file",
      j = paste0("received a character vector of length ", length(x)),
      c = "pass the path of one .bedpe file (optionally .gz)"
    )
  }
  if (!file.exists(x)) {
    msuiter_abort(
      "io",
      "the BEDPE file does not exist",
      i = "the io layer reads the file eagerly at call time",
      j = x,
      c = "check the path spelling and the working directory"
    )
  }
  if (dir.exists(x)) {
    msuiter_abort(
      "io",
      "the BEDPE path is a directory, not a file",
      i = "the io layer reads regular files only",
      j = x,
      c = "pass the path of one BEDPE file"
    )
  }
  compressed <- msuiter_sv_format(x)
  tab <- msuiter_read_tsv_table(x, compressed, "BEDPE")
  table <- msuiter_sv_from_table(tab, x)
  attr(table, "provenance") <- utils::modifyList(
    list(source = x, format = "bedpe"),
    list(parse = attr(table, "parse_stats"), kat = attr(table, "kat_stats"))
  )
  attr(table, "parse_stats") <- NULL
  attr(table, "kat_stats") <- NULL
  table
}

# Method: direct construction from a BEDPE-like data.frame; the same
# derivation and annotation pipeline runs, minus the file reading.
S7::method(ms_sv, S7::class_data.frame) <- function(x, ...) {
  msuiter_sv_abort_dots(list(...))
  table <- msuiter_sv_from_table(x, NULL)
  attr(table, "provenance") <- list(
    format = "bedpe",
    parse = attr(table, "parse_stats"),
    kat = attr(table, "kat_stats")
  )
  attr(table, "parse_stats") <- NULL
  attr(table, "kat_stats") <- NULL
  table
}

# Fallback: structured project error instead of the raw S7 dispatch
# failure.
S7::method(ms_sv, S7::class_any) <- function(x, ...) {
  msuiter_sv_abort_dots(list(...))
  msuiter_abort(
    "input",
    "x must be a BEDPE file path or a BEDPE-like table",
    i = "ms_sv() dispatches on character paths and data.frames",
    j = paste0("received: ", class(x)[1L]),
    c = paste0(
      "pass a .bedpe path or a data.frame with columns ",
      "chrom1/start1/end1/chrom2/start2/end2 plus svclass or strand1/strand2"
    )
  )
}

# ---------------------------------------------------------------------------
# Format resolution and the shared mapping pipeline
# ---------------------------------------------------------------------------

# BEDPE files only, optionally gzip-compressed.
msuiter_sv_format <- function(path) {
  m <- regmatches(
    tolower(basename(path)),
    regexec("\\.bedpe(\\.gz)?$", tolower(basename(path)))
  )[[1L]]
  if (length(m) == 0L) {
    msuiter_abort(
      "unsupported",
      "unrecognized structural-variant file extension",
      i = "ms_sv() reads BEDPE: .bedpe (optionally .gz)",
      j = basename(path),
      c = "re-export the caller output as BEDPE"
    )
  }
  nzchar(m[2L])
}

# Integer column parser: non-negative integers, anyNA rejected (BEDPE
# coordinates are consumed verbatim -- 0-based half-open per the BEDPE
# specification -- so 0 is a legal start; every downstream quantity is a
# difference or an ordering, hence offset-invariant).
msuiter_sv_parse_int <- function(x, col, src) {
  x <- trimws(as.character(x))
  na_idx <- which(is.na(x) | !nzchar(x) | x %in% c("NA", "NaN"))
  bad <- setdiff(seq_along(x), na_idx)
  bad <- bad[!grepl("^[0-9]+$", x[bad])]
  if (length(bad) > 0L || length(na_idx) > 0L) {
    offenders <- union(bad, na_idx)
    msuiter_abort(
      "io",
      "the BEDPE coordinate column must contain non-negative integers",
      i = "BEDPE coordinates are integer positions; missing values are rejected",
      j = paste0(
        "column '", col, "' in ",
        if (is.null(src)) "the input table" else basename(src),
        ", offending rows: ", msuiter_quote_trunc(offenders)
      ),
      c = "write coordinates as plain non-negative integers"
    )
  }
  as.numeric(x)
}

# The whole mapping pipeline: validate columns, derive svtype, annotate
# kat clustering, assemble the typed table. `src` is the file path (for
# error locations) or NULL for the direct data.frame path.
msuiter_sv_from_table <- function(tab, src) {
  if (nrow(tab) == 0L) {
    msuiter_abort(
      "io",
      "no structural-variant records could be parsed",
      i = "the input has a header but no data rows (upstream skips such files in batch mode, :982-984; the single-sample io call surfaces it instead)",
      j = if (is.null(src)) "the input table has no rows" else basename(src),
      c = "check that the file is the intended caller output"
    )
  }
  where <- function(idx) {
    paste0(
      if (is.null(src)) "input row(s) " else paste0(basename(src), ", data row(s) "),
      msuiter_quote_trunc(idx)
    )
  }
  required <- c("chrom1", "start1", "end1", "chrom2", "start2", "end2")
  absent <- setdiff(required, names(tab))
  if (length(absent) > 0L) {
    msuiter_abort(
      "io",
      "the BEDPE input is missing required columns",
      i = paste0("required columns: ", paste(required, collapse = ", ")),
      j = paste0("missing: ", msuiter_quote_trunc(absent)),
      c = "check the BEDPE header, or re-export the caller output"
    )
  }

  chrom1 <- trimws(as.character(tab$chrom1))
  chrom2 <- trimws(as.character(tab$chrom2))
  start1 <- msuiter_sv_parse_int(tab$start1, "start1", src)
  end1 <- msuiter_sv_parse_int(tab$end1, "end1", src)
  start2 <- msuiter_sv_parse_int(tab$start2, "start2", src)
  end2 <- msuiter_sv_parse_int(tab$end2, "end2", src)

  bad_chrom <- which(is.na(chrom1) | !nzchar(chrom1) | is.na(chrom2) | !nzchar(chrom2))
  if (length(bad_chrom) > 0L) {
    msuiter_abort(
      "sv",
      "the chromosome columns must contain non-empty labels",
      i = "chromosome names are passed through verbatim into the typed record",
      j = where(bad_chrom),
      c = "fill in the chromosome labels"
    )
  }
  bad_span <- which(end1 < start1 | end2 < start2)
  if (length(bad_span) > 0L) {
    msuiter_abort(
      "sv",
      "a breakend end coordinate must not precede its start",
      i = "BEDPE intervals are half-open [start, end)",
      j = where(bad_span),
      c = "repair the coordinates"
    )
  }

  # svtype: provided svclass/SVTYPE column verbatim, or derived from the
  # strand pair (SVMatrixGenerator.py:1100-1128). NOTE: the `SVTYPE` alias is
  # an msuiter extension (upstream greps 0 hits); upstream reads `svclass`
  # only (:1129-1130) — recorded as a deliberate divergence.
  class_col <- intersect(c("svclass", "SVTYPE"), names(tab))[1L]
  if (!is.na(class_col)) {
    svclass <- trimws(as.character(tab[[class_col]]))
    provided <- rep(TRUE, nrow(tab))
  } else {
    missing_strands <- setdiff(c("strand1", "strand2"), names(tab))
    if (length(missing_strands) > 0L) {
      msuiter_abort(
        "io",
        "cannot classify rearrangements",
        i = paste0(
          "the svclass column is missing, and the strand pair is ",
          "incomplete (upstream :1101-1104)"
        ),
        j = paste0("missing: ", msuiter_quote_trunc(missing_strands)),
        c = "add strand1/strand2 (BRASS convention), or an svclass column"
      )
    }
    svclass <- rep(NA_character_, nrow(tab))
    provided <- rep(FALSE, nrow(tab))
  }

  if (!all(provided)) {
    strand1 <- trimws(as.character(tab$strand1))
    strand2 <- trimws(as.character(tab$strand2))
    # Missing strand values fail every strand test below and surface in
    # the strand-format error with their row numbers.
    strand1[is.na(strand1)] <- ""
    strand2[is.na(strand2)] <- ""
    todo <- which(!provided)
    derived <- character(length(todo))
    trans <- chrom1[todo] != chrom2[todo]
    derived[trans] <- "translocation" # :1108-1110
    inv <- !trans & ((strand1[todo] == "+" & strand2[todo] == "-") |
      (strand1[todo] == "-" & strand2[todo] == "+"))
    derived[inv] <- "inversion" # :1112-1116
    del <- !trans & !inv & strand1[todo] == "+" & strand2[todo] == "+"
    derived[del] <- "deletion" # :1117-1119
    tds <- !trans & !inv & !del & strand1[todo] == "-" & strand2[todo] == "-"
    derived[tds] <- "tandem-duplication" # :1120-1122
    bad_strand <- which(!trans & !inv & !del & !tds)
    if (length(bad_strand) > 0L) {
      msuiter_abort(
        "sv",
        "cannot classify rearrangements: strand values are not in the proper format",
        i = paste0(
          "same-chromosome events need strand1/strand2 in {+, -} ",
          "(upstream raises on anything else, :1123-1126)"
        ),
        j = where(todo[bad_strand]),
        c = "write strands as + or - (BRASS convention)"
      )
    }
    svclass[todo] <- derived
  }

  bad_class <- which(!svclass %in% c(
    "deletion", "tandem-duplication", "inversion", "translocation"
  ))
  if (length(bad_class) > 0L) {
    msuiter_abort(
      "sv",
      "the svclass column contains unsupported rearrangement classes",
      i = paste0(
        "supported classes: deletion, tandem-duplication, inversion, ",
        "translocation (upstream svclass_mapping :1228-1233; a foreign ",
        "label would KeyError at :1251)"
      ),
      j = where(bad_class),
      c = "relabel the rows with the supported class names"
    )
  }

  # size_bp = |start1 - start2| for every event (:1138-1159); SV32
  # ignores it for translocations (:1158-1161). The <1 kb drop
  # (:1184-1189) is the catalog layer's ledger rule -- reported, not
  # applied.
  size_bp <- abs(start1 - start2)
  if (any(size_bp > .Machine$integer.max)) {
    msuiter_abort(
      "sv",
      "the event size exceeds the integer range",
      i = "size_bp = |start1 - start2| is an integer quantity",
      j = where(which(size_bp > .Machine$integer.max)),
      c = "check the coordinates for corrupted values"
    )
  }

  # kat-region clustering (annotateBedpe :797-930), per sample group
  # when the sample column is present (upstream runs per sample file).
  sample <- if ("sample" %in% names(tab)) trimws(as.character(tab$sample)) else NULL
  if (!is.null(sample)) {
    bad_sample <- which(is.na(sample) | !nzchar(sample))
    if (length(bad_sample) > 0L) {
      msuiter_abort(
        "sv",
        "the sample column must contain non-empty labels",
        i = "sample labels group the kat annotation and pass through to the output",
        j = where(bad_sample),
        c = "fill in the sample label"
      )
    }
  }
  groups <- if (is.null(sample)) {
    rep(1L, nrow(tab))
  } else {
    match(sample, unique(sample))
  }
  clustered <- logical(nrow(tab))
  n_kat_regions <- 0L
  for (g in unique(groups)) {
    idx <- which(groups == g)
    kat <- msuiter_annotate_bedpe(
      chrom1[idx], start1[idx], chrom2[idx], start2[idx]
    )
    clustered[idx] <- kat$clustered
    n_kat_regions <- n_kat_regions + kat$n_kat_regions
  }

  out <- data.frame(
    svtype = svclass,
    size_bp = as.integer(size_bp),
    clustered = clustered,
    stringsAsFactors = FALSE
  )
  coords <- data.frame(
    chrom1 = chrom1, start1 = start1, end1 = end1,
    chrom2 = chrom2, start2 = start2, end2 = end2,
    stringsAsFactors = FALSE
  )
  out <- cbind(coords, out)
  if (!is.null(sample)) {
    out <- cbind(sample = sample, out)
  }
  rownames(out) <- NULL

  attr(out, "parse_stats") <- list(
    n_lines = nrow(tab),
    n_records = nrow(out),
    n_derived_svclass = sum(!provided),
    n_provided_svclass = sum(provided),
    n_translocation = sum(svclass == "translocation"),
    n_below_1kb_non_trans = sum(svclass != "translocation" & size_bp < 1000)
  )
  attr(out, "kat_stats") <- list(
    kmin = 10L,
    min_bps = 10L,
    genome_size = 3e9,
    peak_factor = 10,
    gamma_sdev = 25,
    n_kat_regions = n_kat_regions
  )
  out
}

# ---------------------------------------------------------------------------
# kat-region clustering: the annotateBedpe port (:797-930)
# ---------------------------------------------------------------------------

# Zero-padded running median, scipy.signal.medfilt(x, k) with the fixed
# window 25 that getMad uses (:349-356). The window centred on element i
# is zero-padded at the boundaries and its median (13th of 25 sorted) is
# the output.
msuiter_medfilt <- function(x, k = 25) {
  n <- length(x)
  if (n == 0L) {
    return(numeric(0L))
  }
  half <- k %/% 2L
  pad <- c(numeric(half), x, numeric(half))
  idx <- seq_len(n)
  vapply(idx, function(i) {
    sort(pad[i:(i + k - 1L)], method = "radix")[half + 1L]
  }, numeric(1L))
}

# getMad (:349-356): drop zero observations, subtract the running
# median, take the median absolute deviation of the residuals.
msuiter_kat_get_mad <- function(x) {
  x <- x[x != 0]
  if (length(x) == 0L) {
    return(0)
  }
  dif <- x - msuiter_medfilt(x, 25)
  med <- stats::median(dif)
  stats::median(abs(dif - med))
}

# Sequential left-to-right float64 accumulation, matching Python's
# builtin sum() over a numpy array; R's sum() may accumulate in extended
# precision, which would change low-order bits.
msuiter_seq_sum <- function(y) {
  acc <- 0
  for (v in y) acc <- acc + v
  acc
}

# exactPcf (:359-468) with flag = TRUE (the only call shape annotateBedpe
# uses, :865): piecewise-constant fit of the distance profile with
# segments at least `kmin` points long, penalised by `gamma`.
#
# Numerics note: upstream accumulates the builtin sum() over int64
# distances; this port accumulates float64. Distance sums are exact below
# 2^53; the kvad square terms exceed 2^53 for gaps beyond ~94 Mb (possible
# on sparse chromosomes) — immaterial: upstream re-accumulates the same
# squares in float64 every run, so any ULP difference sits in init_kvad on
# both sides. The golden sweep (34 BEDPEs) shows no divergence. The
# N < 2 * kmin branch returns the
# mean fill (:366-378); np.mean's pairwise summation may differ from the
# sequential sum by an ULP with the same practical conclusion.
msuiter_exact_pcf <- function(y, kmin = 10, gamma = 0) {
  n <- length(y)
  yhat <- numeric(n)
  if (n < 2 * kmin) {
    return(rep(msuiter_seq_sum(y) / n, n))
  }
  init_sum <- msuiter_seq_sum(y[seq_len(kmin)])
  init_kvad <- msuiter_seq_sum(y[seq_len(kmin)]^2)
  init_ave <- init_sum / kmin
  best_cost <- numeric(n)
  best_cost[kmin] <- init_kvad - init_sum * init_ave # :384
  best_split <- integer(n)
  best_aver <- numeric(n)
  best_aver[kmin] <- init_ave # :387
  sum_v <- numeric(n)
  kvad <- numeric(n)
  aver <- numeric(n)
  cost <- numeric(n)
  kmin_p1 <- kmin + 1L
  # Warm-up loop (:393-398): numpy slices [kminP1-1, k) -> R kminP1:k.
  for (k in (kmin + 1L):(2 * kmin - 1L)) {
    sl <- kmin_p1:max(kmin_p1, k)
    sum_v[sl] <- sum_v[sl] + y[k]
    aver[sl] <- sum_v[sl] / rev(seq_len(k - kmin))
    kvad[sl] <- kvad[sl] + y[k]^2
    best_aver[k] <- (init_sum + sum_v[kmin_p1]) / k
    best_cost[k] <- (init_kvad + kvad[kmin_p1]) - (k * best_aver[k]^2)
  }
  # Main dynamic program (:400-426).
  for (nn in (2 * kmin):n) {
    sl <- kmin_p1:nn
    sum_v[sl] <- sum_v[sl] + y[nn]
    aver[sl] <- sum_v[sl] / rev(seq_len(nn - kmin))
    kvad[sl] <- kvad[sl] + y[nn]^2
    n_mkmin_p1 <- nn - kmin + 1L
    sl2 <- kmin_p1:n_mkmin_p1
    cost[sl2] <- best_cost[kmin:(nn - kmin)] +
      kvad[sl2] - sum_v[sl2] * aver[sl2] + gamma
    pos <- which.min(cost[sl2]) - 1L + kmin # 0-based argmin + kmin (:413)
    cost_v <- cost[pos + 1L]
    aver_v <- aver[pos + 1L]
    tot_aver <- (sum_v[kmin_p1] + init_sum) / nn
    tot_cost <- (kvad[kmin_p1] + init_kvad) - nn * tot_aver * tot_aver
    if (tot_cost < cost_v) {
      pos <- 1L # the no-split root (:420-423)
      cost_v <- tot_cost
      aver_v <- tot_aver
    }
    best_cost[nn] <- cost_v
    best_aver[nn] <- aver_v
    best_split[nn] <- pos
  }
  # Backtrack through the splits (:432-436); the sp = 0 / sp = nn edge
  # cases reproduce upstream's empty/zero-filled slices exactly.
  nn <- n
  while (nn > 0L) {
    sp <- best_split[nn]
    if (sp + 1L <= nn) {
      yhat[(sp + 1L):nn] <- best_aver[nn]
    }
    nn <- sp
  }
  yhat
}

# extract_kat_regions (:625-791) specialised to the fixed annotateBedpe
# parameter set (:872-890: kmin_samples = 1, pvalue_thresh = 1,
# rate_factor_thresh = 1, doMerging = TRUE, kmin_filter = kmin = 10,
# bp_rate = NaN -> recomputed from the data, assignPvalues :485-501).
#
# The region boundary indices keep upstream's mixed 0/1-based
# bookkeeping verbatim: start values are np.where(...) + 1 ranks
# (:644-655), end values are bare np.where ranks (:658-666), the
# katLoci[0] / katLoci[-1] prepends append 0 and n - 1 (:656-668), and
# the special-case block (:671-687) rebalances unmatched ends. The
# flag propagation in annotateBedpe (:894-901) slices [firstBp,
# lastBp + 1] 0-based, which is the R range (first + 1):(last + 1).
#
# `hot()` is hotspotInfo2 (:571-606) reduced to the fields the
# clustering consumes (start_bp, end_bp, number_bps).
msuiter_kat_regions <- function(yhat, thresh, pos, kmin_filter = 10) {
  n <- length(yhat)
  if (n < 2L) {
    return(NULL) # unreachable behind the MIN_BPS gate; defensive only
  }
  kat <- yhat <= thresh # katLoci (:640-642)
  if (!any(kat)) {
    return(NULL)
  }
  j <- 2L:n
  neq <- yhat[j] != yhat[j - 1L] # float equality on segment means (:650)
  start_v <- (j - 1L)[kat[j] & (!kat[j - 1L] | (kat[j - 1L] & neq))]
  end_v <- (j - 2L)[(!kat[j] & kat[j - 1L]) |
    ((kat[j] & kat[j - 1L]) & neq)]
  if (kat[1L]) start_v <- c(0, start_v) # :656-657
  if (kat[n]) end_v <- c(end_v, n - 1L) # :667-668
  if (length(end_v) + length(start_v) > 0L) {
    if (length(end_v) == 1L && length(start_v) == 0L) {
      start_v <- 0
    } else if (length(end_v) == 0L && length(start_v) == 1L) {
      end_v <- n - 1L
    } else if (end_v[1L] < start_v[1L] &&
      start_v[length(start_v)] > end_v[length(end_v)]) {
      start_v <- c(0, start_v)
      end_v <- c(end_v, n - 1L)
    } else if (end_v[1L] < start_v[1L]) {
      start_v <- c(0, start_v)
    } else if (start_v[length(start_v)] > end_v[length(end_v)]) {
      end_v <- c(end_v, n - 1L)
    }
  }
  if (length(start_v) == 0L) {
    return(NULL)
  }
  first_bp <- as.numeric(start_v)
  last_bp <- as.numeric(end_v)
  hot <- function(first_bp, last_bp) {
    m <- length(first_bp)
    start_bp <- numeric(m)
    end_bp <- numeric(m)
    number_bps <- integer(m)
    for (r in seq_len(m)) {
      sl <- (first_bp[r] + 1L):(last_bp[r] + 1L)
      start_bp[r] <- min(pos[sl])
      end_bp[r] <- max(pos[sl])
      number_bps[r] <- length(sl)
    }
    list(start_bp = start_bp, end_bp = end_bp, number_bps = number_bps)
  }
  h <- hot(first_bp, last_bp)
  # kmin_samples = 1 is vacuous (single sample); the breakpoint-count
  # filter (:745-748) bites with kmin_filter = 10.
  keep <- h$number_bps >= kmin_filter
  if (!any(keep)) {
    return(NULL)
  }
  first_bp <- first_bp[keep]
  last_bp <- last_bp[keep]
  h <- hot(first_bp, last_bp)
  # assignPvalues (:485-501): bp_rate recomputed from the data (the
  # annotateBedpe call passes NaN, :879); pvalue = 1 - binom.cdf lies in
  # [0, 1] so the pvalue <= 1 gate is vacuous -- only rate_factor >= 1
  # bites (:756-757).
  bp_rate <- length(pos) / (max(pos) - min(pos))
  d_seg <- h$number_bps / (h$end_bp - h$start_bp)
  rate_factor <- d_seg / bp_rate
  keep <- !is.na(rate_factor) & rate_factor >= 1
  if (!any(keep)) {
    return(NULL)
  }
  first_bp <- first_bp[keep]
  last_bp <- last_bp[keep]
  # doMerging (:760-788): adjacent regions share a boundary and fuse.
  m <- length(first_bp)
  if (m > 1L) {
    for (r in 2L:m) {
      if (!is.na(last_bp[r - 1L]) && last_bp[r - 1L] == first_bp[r] - 1) {
        first_bp[r] <- first_bp[r - 1L]
        first_bp[r - 1L] <- NaN
        last_bp[r - 1L] <- NaN
      }
    }
    keep <- !is.na(first_bp) & !is.na(last_bp)
    if (!any(keep)) {
      return(NULL)
    }
    first_bp <- first_bp[keep]
    last_bp <- last_bp[keep]
    h <- hot(first_bp, last_bp) # re-run after merge (:789-790)
  }
  list(
    first_bp = first_bp, last_bp = last_bp, start_bp = h$start_bp,
    end_bp = h$end_bp, number_bps = h$number_bps
  )
}

# annotateBedpe (:797-930) for one sample: returns the per-rearrangement
# clustered flag and the number of kat regions found.
msuiter_annotate_bedpe <- function(chrom1, start1, chrom2, start2) {
  n_events <- length(chrom1)
  id <- seq_len(n_events)
  # Breakpoint table: every left end then every right end, in appearance
  # order (:804-813).
  bp <- data.frame(
    id = c(id, id),
    chrom = c(as.character(chrom1), as.character(chrom2)),
    pos = c(as.numeric(start1), as.numeric(start2)),
    stringsAsFactors = FALSE
  )
  # Chromosomes in appearance order; stable sort by position within a
  # chromosome (:816-823, sort_values kind="mergesort").
  chrom_order <- unique(bp$chrom)
  ord <- unlist(lapply(chrom_order, function(cc) {
    idx <- which(bp$chrom == cc)
    idx[order(bp$pos[idx], method = "radix")]
  }), use.names = FALSE)
  bp <- bp[ord, , drop = FALSE]
  n <- nrow(bp)
  # Intermutational distances (calcIntermutDist2 :309-341,
  # first_chrom_na=False): the first breakpoint of a chromosome measures
  # from 0 and zero distances clamp to 1 (:329-331).
  dist <- numeric(n)
  for (cc in chrom_order) {
    idx <- which(bp$chrom == cc)
    dist[idx] <- c(bp$pos[idx[1L]], diff(bp$pos[idx]))
  }
  dist[dist == 0] <- 1
  # Threshold and penalty over the FULL breakpoint list (:824-851).
  thresh <- (3 * 10^9) / n / 10 # exp_dist / PEAK_FACTOR (:829, :845)
  gamma <- 25 * msuiter_kat_get_mad(dist) # gamma_sdev * getMad (:830, :847-851)
  flag <- logical(n)
  n_kat_regions <- 0L
  for (cc in chrom_order) {
    idx <- which(bp$chrom == cc)
    if (length(idx) <= 10) { # MIN_BPS gate (:825-827, :860-862)
      next
    }
    yhat <- msuiter_exact_pcf(dist[idx], 10, gamma) # kmin = 10 (:864-866)
    reg <- msuiter_kat_regions(yhat, thresh, bp$pos[idx], 10) # :872-890
    if (is.null(reg)) {
      next
    }
    n_kat_regions <- n_kat_regions + length(reg$first_bp)
    # Propagate the flag to every breakpoint inside a flagged region
    # (:893-901; the +1 label arithmetic there resolves to these
    # positions).
    temp <- flag[idx]
    for (r in seq_along(reg$first_bp)) {
      temp[(reg$first_bp[r] + 1L):(reg$last_bp[r] + 1L)] <- TRUE
    }
    flag[idx[temp]] <- TRUE
  }
  # A rearrangement is clustered when any of its breakpoints is flagged
  # (:916-927).
  list(
    clustered = id %in% bp$id[flag],
    n_kat_regions = n_kat_regions
  )
}
