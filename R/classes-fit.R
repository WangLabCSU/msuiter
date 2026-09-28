# MsFit: the L3 reference-based fitting result container.
#
# exposures: signatures x samples matrix; support / tests: tidy evidence
# tables (support statistics, hypothesis tests); reference_summary: A5
# snapshot summary of the MsRefDb used (version/class/build/schema_version/
# sha256/n_signatures) -- never an embedded MsRefDb; engine: method identity.

#' MsFit: reference-fitted exposures with a reference snapshot summary
#'
#' An [MsFit] holds fitted exposures plus support and test evidence tables,
#' the engine name and a **snapshot summary** of the reference database used.
#' Violations raise `msuiter_error_fit`.
#'
#' @param exposures numeric matrix (signatures x samples) with full labels.
#' @param engine single non-empty string naming the fitting engine.
#' @param reference_summary snapshot summary as built by
#'   [msuiter_refdb_summary()]: list with fields `version`, `class`, `build`,
#'   `schema_version`, `sha256`, `n_signatures`.
#' @param support data.frame of support statistics (default empty).
#' @param tests data.frame of test statistics (default empty).
#'
#' @export
MsFit <- S7::new_class(
  "MsFit",
  package = "msuiter",
  properties = list(
    exposures = S7::new_property(S7::class_any),
    support = S7::new_property(S7::class_any),
    tests = S7::new_property(S7::class_any),
    reference_summary = S7::new_property(S7::class_list),
    engine = S7::new_property(S7::class_character)
  ),
  validator = function(self) msuiter_validate_fit(self)
)

msuiter_validate_fit <- function(self) {
  exp1 <- self@exposures
  msuiter_check_signature_matrix(exp1, "exposures", "fit")

  for (nm in c("support", "tests")) {
    v <- S7::prop(self, nm)
    if (!is.data.frame(v)) {
      msuiter_abort(
        "fit",
        sprintf("%s must be a data.frame", nm),
        i = "evidence is stored as tidy tables",
        j = paste0("received: ", class(v)[1L]),
        c = "pass the evidence as a data.frame, or leave it empty"
      )
    }
  }

  summary1 <- self@reference_summary
  required <- c("version", "class", "build", "schema_version", "sha256",
    "n_signatures")
  if (!is.list(summary1) || !all(required %in% names(summary1))) {
    msuiter_abort(
      "fit",
      "reference_summary must carry the contracted snapshot fields",
      i = paste0("required fields: ", paste(required, collapse = ", ")),
      j = paste0("received fields: ", msuiter_quote_trunc(names(summary1))),
      c = "build it with msuiter_refdb_summary(refdb)"
    )
  }
  for (nm in c("version", "class", "schema_version")) {
    v <- summary1[[nm]]
    if (!is.character(v) || length(v) != 1L || is.na(v) || !nzchar(v)) {
      msuiter_abort(
        "fit",
        sprintf("reference_summary field '%s' must be a single non-empty string", nm),
        i = "the summary pins the reference database identity",
        j = paste0("received: ", msuiter_quote_trunc(v)),
        c = "derive the summary from a validated MsRefDb"
      )
    }
  }
  # The build may legitimately be NA for build-independent reference sets.
  build <- summary1$build
  if (!is.character(build) || length(build) != 1L || (!is.na(build) && !nzchar(build))) {
    msuiter_abort(
      "fit",
      "reference_summary field 'build' must be a single string (NA allowed)",
      i = "NA build is legal only with the build_independent declaration",
      j = paste0("received: ", msuiter_quote_trunc(build)),
      c = "derive the summary from a validated MsRefDb"
    )
  }
  if (!is.character(summary1$sha256) || length(summary1$sha256) != 1L ||
    is.na(summary1$sha256) || !grepl("^[0-9a-f]{64}$", summary1$sha256)) {
    msuiter_abort(
      "fit",
      "reference_summary field 'sha256' must be a sha256 hex digest",
      i = "the digest pins the reference database content (A13)",
      j = paste0("received: ", msuiter_quote_trunc(summary1$sha256)),
      c = "derive the summary from a validated MsRefDb"
    )
  }
  n_sig <- summary1$n_signatures
  if (!is.numeric(n_sig) || length(n_sig) != 1L || is.na(n_sig) || n_sig != trunc(n_sig)) {
    msuiter_abort(
      "fit",
      "reference_summary field 'n_signatures' must be a single whole number",
      i = "the count summarizes the reference signature space",
      j = paste0("received: ", msuiter_quote_trunc(n_sig)),
      c = "derive the summary from a validated MsRefDb"
    )
  }

  engine <- self@engine
  if (!is.character(engine) || length(engine) != 1L || is.na(engine) || !nzchar(engine)) {
    msuiter_abort(
      "fit",
      "engine must be a single non-empty string",
      i = "the engine name pins the method behind the result",
      j = paste0("received: ", msuiter_quote_trunc(engine)),
      c = "record the engine name used for fitting"
    )
  }
  NULL
}

#' Construct an MsFit object
#'
#' Builds and validates an [MsFit]. Derive `reference_summary` with
#' [msuiter_refdb_summary()] from the [MsRefDb] used for fitting.
#'
#' @inheritParams MsFit
#' @return An [MsFit] object.
#' @examples
#' labels <- paste0("CH", 1:4)
#' exp1 <- matrix(1:8, 2, 4,
#'   dimnames = list(c("SIG1", "SIG2"), c("S1", "S2", "S3", "S4")))
#' ref_summary <- list(
#'   version = "1", class = "SYN", build = "GRCh38", schema_version = "1",
#'   sha256 = paste0(rep("a", 64), collapse = ""), n_signatures = 2L
#' )
#' ms_fit(exp1, engine = "msu-fit", reference_summary = ref_summary)
#' @export
ms_fit <- function(exposures, engine, reference_summary, support = data.frame(),
                   tests = data.frame()) {
  out <- MsFit(
    exposures = exposures, engine = engine,
    reference_summary = reference_summary, support = support, tests = tests
  )
  out
}

# One-line print/format: class name / dimensions / method identity.
S7::method(format, MsFit) <- function(x, ...) {
  sprintf(
    "<MsFit> %d signatures x %d samples | engine: %s | refdb: %s",
    nrow(x@exposures), ncol(x@exposures), x@engine,
    x@reference_summary$version
  )
}

S7::method(print, MsFit) <- function(x, ...) {
  cat(format(x, ...), "\n", sep = "")
  invisible(x)
}
