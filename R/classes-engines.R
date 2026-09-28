# MsEngine: the abstract engine spec (parsnip/filtro-style).
#
# Concrete engine specs (ms_nmf(), ms_ard(), ...) are S7 subclasses of
# MsEngine and are registered by the engine registry (U-M0-04). A spec is
# small, serializable and metadata rich: method = spec object (A14, the
# object is the first-class citizen; strings are only sugar resolved by
# match_ms_engine() later). No .state, no handles (D12).

#' MsEngine: abstract engine specification
#'
#' [MsEngine] is the abstract base class for engine specs. It cannot be
#' instantiated directly; engines create concrete subclasses via
#' `S7::new_class(parent = MsEngine)`. The spec fields are `name`, `mode`
#' (`"extract"` or `"fit"`), `params` (named list), `deterministic`,
#' `packages` (required R packages) and `label` (optional human-readable
#' name; printing falls back to `name`). Violations raise
#' `msuiter_error_engine`.
#'
#' @param name single lower-case snake_case engine name (the registry key).
#' @param mode one of `"extract"` (signature discovery) or `"fit"`
#'   (reference-based fitting).
#' @param params named list of hyper-parameters.
#' @param deterministic single TRUE or FALSE: seeded and thread invariant.
#' @param packages character vector of required R packages (may be empty).
#' @param label optional human-readable engine label; printing falls back to
#'   `name` when empty.
#'
#' @export
MsEngine <- S7::new_class(
  "MsEngine",
  package = "msuiter",
  abstract = TRUE,
  properties = list(
    name = S7::new_property(S7::class_character),
    mode = S7::new_property(S7::class_character),
    params = S7::new_property(S7::class_list, default = list()),
    deterministic = S7::new_property(S7::class_logical),
    packages = S7::new_property(S7::class_character, default = character(0)),
    label = S7::new_property(S7::class_character, default = "")
  ),
  validator = function(self) msuiter_validate_engine(self)
)

msuiter_validate_engine <- function(self) {
  name <- self@name
  if (!is.character(name) || length(name) != 1L || is.na(name) ||
    !grepl("^[a-z][a-z0-9_]*$", name)) {
    msuiter_abort(
      "engine",
      "engine name must be a single lower-case snake_case string",
      i = "engine names are registry keys (D9)",
      j = paste0("received: ", msuiter_quote_trunc(name)),
      c = "use e.g. name = \"nmf_kl\""
    )
  }
  mode <- self@mode
  known_modes <- c("extract", "fit")
  if (!is.character(mode) || length(mode) != 1L || is.na(mode) ||
    !mode %in% known_modes) {
    msuiter_abort(
      "engine",
      "engine mode must be one of the known modes",
      i = paste0("known modes: ", paste(known_modes, collapse = ", ")),
      j = paste0("received: ", msuiter_quote_trunc(mode)),
      c = "declare whether the engine extracts signatures or fits exposures"
    )
  }
  params <- self@params
  if (!is.list(params) || (!is.null(names(params)) && any(!nzchar(names(params))))) {
    msuiter_abort(
      "engine",
      "engine params must be a (named) list",
      i = "params carry the hyper-parameters of the spec",
      j = paste0("received: ", class(params)[1L]),
      c = "pass hyper-parameters as a named list"
    )
  }
  det <- self@deterministic
  if (!is.logical(det) || length(det) != 1L || is.na(det)) {
    msuiter_abort(
      "engine",
      "deterministic must be a single TRUE or FALSE",
      i = "determinism is part of the engine contract (thread invariance)",
      j = paste0("received: ", msuiter_quote_trunc(det)),
      c = "declare whether the engine is seeded and thread invariant"
    )
  }
  packages <- self@packages
  if (!is.character(packages) || anyNA(packages) || any(!nzchar(packages))) {
    msuiter_abort(
      "engine",
      "packages must be a character vector of package names without NA",
      i = "required_pkgs() reports these before an engine runs",
      j = paste0("received: ", msuiter_quote_trunc(packages)),
      c = "list package names, or pass character(0)"
    )
  }
  label <- self@label
  if (!is.character(label) || length(label) != 1L || is.na(label)) {
    msuiter_abort(
      "engine",
      "label must be a single string (empty allowed)",
      i = "the label is an optional human-readable engine name",
      j = paste0("received: ", msuiter_quote_trunc(label)),
      c = "pass a short label, or leave it empty"
    )
  }
  NULL
}

# One-line print/format: class name / identity / mode / determinism.
S7::method(format, MsEngine) <- function(x, ...) {
  shown <- if (nzchar(x@label)) x@label else x@name
  det <- if (isTRUE(x@deterministic)) "deterministic" else "stochastic"
  sprintf(
    "<MsEngine> %s (%s) | mode: %s | %s",
    shown, x@name, x@mode, det
  )
}

S7::method(print, MsEngine) <- function(x, ...) {
  cat(format(x, ...), "\n", sep = "")
  invisible(x)
}
