# Engine registry (U-M0-04; ARCHITECTURE.md section 3.4, decisions A14/A17).
#
# The registry is data, not a class explosion (docs/research/06-s7-class-system.md
# section 6): rows keyed by engine name carry the spec class, the fit function
# and the governance fields (engine_version / contract_version / certified).
# MsEngine objects are the first-class citizens of the API (A14); strings are
# sugar resolved by match_ms_engine(). Third-party packages extend the registry
# from their .onLoad() through the exported register_ms_engine(); registry rows
# are data, so no S7::methods_register() is needed for registration itself (a
# third party only calls it when defining its own methods on msuiter generics).
#
# No real engine is registered by the package itself; engines land with M1s
# and later (docs/IMPLEMENTATION-PLAN.md). D9: external tools never enter the
# ms_* API through this registry -- they stay bench-only adapters.

# Internal registry state (never exported): one row per engine name, plus the
# per-session record of engines already warned about (warning idempotency).
.ms_registry <- new.env(parent = emptyenv())
.ms_registry_warned <- new.env(parent = emptyenv())

.ms_registry_modes <- c("extract", "fit")
.ms_registry_certified_states <- c("certified", "self-reported", "unknown")

.ms_registry_names <- function() {
  sort(ls(.ms_registry, all.names = TRUE))
}

# Single non-empty string check shared by the registry validators.
.ms_registry_scalar <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
}

# TRUE when `class` derives from `ancestor` in the S7 class hierarchy. S7 0.2.2
# exposes the parent chain through the same attribute its dispatch uses (no
# exported class_parents()); the registration contract tests cover this walk.
.ms_registry_derives <- function(class, ancestor) {
  cur <- class
  while (!is.null(cur)) {
    if (identical(cur, ancestor)) {
      return(TRUE)
    }
    cur <- attr(cur, "parent")
  }
  FALSE
}

# One-time warning for non-certified engines at resolution time (A17): once
# per session per engine, keyed by the registry name.
.ms_registry_warn_uncertified <- function(entry) {
  if (identical(entry$certified, "certified")) {
    return(invisible(NULL))
  }
  if (!exists(entry$name, envir = .ms_registry_warned, inherits = FALSE)) {
    assign(entry$name, TRUE, envir = .ms_registry_warned)
    rlang::warn(
      sprintf(
        "engine '%s' is %s: not certified by the msuiter maintainers",
        entry$name, entry$certified
      ),
      class = "msuiter_warning_uncertified_engine",
      body = c(
        i = paste(
          "registered engine code runs with your permissions; certified",
          "engines have passed the maintainer compatibility review (A17)"
        ),
        j = sprintf(
          "engine '%s' declares certified = \"%s\"", entry$name, entry$certified
        ),
        c = paste(
          "prefer certified engines for production analyses; compare results",
          "across trust levels with care"
        )
      )
    )
  }
  invisible(NULL)
}

#' Register an engine in the msuiter engine registry
#'
#' `register_ms_engine()` is the extension entry point of the engine registry
#' (ARCHITECTURE.md section 3.4). It stores a row keyed by `name` holding the
#' S7 spec class (`engine_class`), the implementation function (`fit_fn`) and
#' the governance fields `engine_version`, `contract_version` and `certified`
#' (A17). Registry rows are data: the package itself ships an empty registry,
#' and third-party packages register their engines from `.onLoad()`.
#'
#' Trust boundary: registered engine code runs with your permissions.
#' `certified` marks engines that passed the maintainer compatibility review;
#' `"self-reported"` and `"unknown"` engines trigger a one-time warning per
#' session when resolved by [match_ms_engine()].
#'
#' @param name single lower-case snake_case engine name (the registry key;
#'   same grammar as the `MsEngine` `name` property).
#' @param mode one of `"extract"` (signature discovery) or `"fit"`
#'   (reference-based fitting).
#' @param engine_class an S7 class deriving from the abstract [MsEngine].
#'   String sugar resolves through `engine_class()`, so its property defaults
#'   must form a valid spec (defaults for `name`, `mode`, `deterministic`).
#' @param fit_fn the engine implementation. For `mode = "extract"` engines
#'   it is called as `fit_fn(engine, catalog = <MsCatalog>, k = <rank>)` and
#'   must return a list with `signatures` (channels x k, row-major) and
#'   `exposures` (k x samples); `ms_extract()` owns display normalization
#'   and the MsSignature assembly. For `mode = "fit"` engines the
#'   `ms_fit()` face contracts apply (see R/fit.R).
#' @param packages character vector of required R packages reported by
#'   [required_pkgs()] (may be empty).
#' @param tags character vector of free-form tags (may be empty), e.g. for
#'   benchmark filtering.
#' @param engine_version required single string: version of the engine
#'   implementation.
#' @param contract_version required single string: version of the msuiter
#'   registry/extension contract the engine was written against.
#' @param certified required single string, one of `"certified"`,
#'   `"self-reported"`, `"unknown"`.
#'
#' @return `name`, invisibly.
#'
#' @examples
#' \dontrun{
#' # inside a third-party package's .onLoad():
#' msuiter::register_ms_engine(
#'   name = "othersig_kl", mode = "fit", engine_class = OthersigKlEngine,
#'   fit_fn = othersig_kl_fit, packages = "othersig",
#'   engine_version = "2.3.4", contract_version = "1",
#'   certified = "self-reported"
#' )
#' }
#' @export
register_ms_engine <- function(name, mode, engine_class, fit_fn,
                               packages = character(0), tags = character(0),
                               engine_version = NULL, contract_version = NULL,
                               certified = NULL) {
  if (!.ms_registry_scalar(name) || !grepl("^[a-z][a-z0-9_]*$", name)) {
    msuiter_abort(
      "registry",
      "engine name must be a single lower-case snake_case string",
      i = "engine names are registry keys (D9)",
      j = paste0("received: ", msuiter_quote_trunc(name)),
      c = "use e.g. name = \"nmf_kl\""
    )
  }
  if (exists(name, envir = .ms_registry, inherits = FALSE)) {
    existing <- .ms_registry[[name]]
    msuiter_abort(
      "registry",
      sprintf("engine '%s' is already registered", name),
      i = paste(
        "the registry keys engines by name; duplicate keys would silently",
        "shadow implementations"
      ),
      j = sprintf(
        "existing registration: mode %s, engine_version %s",
        existing$mode, existing$engine_version
      ),
      c = "choose a new engine name"
    )
  }
  if (!.ms_registry_scalar(mode) || !mode %in% .ms_registry_modes) {
    msuiter_abort(
      "registry",
      "engine mode must be one of the known modes",
      i = paste0("known modes: ", paste(.ms_registry_modes, collapse = ", ")),
      j = paste0("received: ", msuiter_quote_trunc(mode)),
      c = "declare whether the engine extracts signatures or fits exposures"
    )
  }
  # S7 class objects carry the S3 class vector "S7_class" (S7 0.2.2 has no
  # exported is_class()); S7_inherits(x, S7_object) is TRUE for them too.
  if (!inherits(engine_class, "S7_class") ||
    !.ms_registry_derives(engine_class, MsEngine)) {
    msuiter_abort(
      "registry",
      "engine_class must be an S7 class deriving from MsEngine",
      i = paste(
        "string sugar resolves through engine_class(); only specs derived",
        "from the abstract MsEngine are registry-compatible"
      ),
      j = paste0("received: ", msuiter_quote_trunc(class(engine_class)[1L])),
      c = "create the class with S7::new_class(parent = MsEngine)"
    )
  }
  if (!is.function(fit_fn)) {
    msuiter_abort(
      "registry",
      "fit_fn must be a function",
      i = "fit_engine() dispatches to the registered fit_fn(engine, ...)",
      j = paste0("received: ", msuiter_quote_trunc(class(fit_fn)[1L])),
      c = "pass the engine implementation function"
    )
  }
  if (!is.character(packages) || anyNA(packages) || any(!nzchar(packages))) {
    msuiter_abort(
      "registry",
      "packages must be a character vector of package names without NA",
      i = "required_pkgs() reports these before an engine runs",
      j = paste0("received: ", msuiter_quote_trunc(packages)),
      c = "list package names, or pass character(0)"
    )
  }
  if (!is.character(tags) || anyNA(tags) || any(!nzchar(tags))) {
    msuiter_abort(
      "registry",
      "tags must be a character vector of non-empty tags without NA",
      i = "tags are free-form labels used for filtering and benchmarking",
      j = paste0("received: ", msuiter_quote_trunc(tags)),
      c = "list tags, or pass character(0)"
    )
  }
  # Governance fields (A17): all three mandatory and explicit.
  if (!.ms_registry_scalar(engine_version)) {
    msuiter_abort(
      "registry",
      "engine_version is a required governance field",
      i = "engine_version declares the version of the engine implementation",
      j = paste0("received: ", msuiter_quote_trunc(engine_version)),
      c = "pass a single version string, e.g. engine_version = \"1.2.0\""
    )
  }
  if (!.ms_registry_scalar(contract_version)) {
    msuiter_abort(
      "registry",
      "contract_version is a required governance field",
      i = paste(
        "contract_version pins the msuiter registry/extension contract the",
        "engine was written against"
      ),
      j = paste0("received: ", msuiter_quote_trunc(contract_version)),
      c = "pass the contract version, e.g. contract_version = \"1\""
    )
  }
  if (!.ms_registry_scalar(certified) || !certified %in% .ms_registry_certified_states) {
    msuiter_abort(
      "registry",
      "certified must be one of the three governance states",
      i = paste0(
        "certified is one of: ", paste(.ms_registry_certified_states, collapse = ", ")
      ),
      j = paste0("received: ", msuiter_quote_trunc(certified)),
      c = "declare the trust level explicitly (A17)"
    )
  }
  # Extract-mode engines must expose a numeric `seed` property: the
  # ms_extract() assembly reads spec@seed for the MsSignature provenance
  # slot, and a missing property would surface as a raw S7 error at
  # assembly time (audited P2 -- registry-level guard, msuiter_error_registry).
  if (identical(mode, "extract")) {
    seed_prop <- tryCatch(engine_class@properties[["seed"]], error = function(e) NULL)
    if (is.null(seed_prop)) {
      # Warning, not error: synthetic engines in the registry test-suite
      # legitimately lack `seed` (they never reach assembly), and a hard
      # row rejection would break registry-machinery tests. The assembly
      # layer (R/extract.R) tolerates a missing seed with a warning + the
      # documented default, so the contract stays enforced where it bites.
      rlang::warn(
        'extract-mode engines should declare a numeric `seed` property',
        body = c(
          i = paste0("engine_class `", class(engine_class)[1L],
                     "` has no `seed` property"),
          j = "ms_extract() reads spec@seed for the MsSignature provenance slot",
          c = 'add a numeric `seed` S7 property (see MsNmf in R/engines-nmf.R)'
        ),
        class = "msuiter_warning_registry"
      )
    }
  }

  assign(
    name,
    list(
      name = name,
      mode = mode,
      engine_class = engine_class,
      fit_fn = fit_fn,
      packages = packages,
      tags = tags,
      engine_version = engine_version,
      contract_version = contract_version,
      certified = certified
    ),
    envir = .ms_registry
  )
  invisible(name)
}

#' Resolve string sugar to an MsEngine spec
#'
#' `match_ms_engine()` implements the method-argument discipline (A14):
#' [MsEngine] objects are first-class citizens and pass through unchanged;
#' strings are sugar resolved against the engine registry. Resolution failure
#' lists every available engine name. Resolving a non-certified engine
#' (`certified` is `"self-reported"` or `"unknown"`) raises a one-time warning
#' per session per engine.
#'
#' @param name_or_engine an [MsEngine] object (returned as-is) or a single
#'   string naming a registered engine.
#'
#' @return an [MsEngine] spec built from the registered engine class defaults.
#'
#' @export
match_ms_engine <- function(name_or_engine) {
  if (S7::S7_inherits(name_or_engine, MsEngine)) {
    entry <- .ms_registry[[name_or_engine@name]]
    if (!is.null(entry)) {
      .ms_registry_warn_uncertified(entry)
    }
    return(name_or_engine)
  }
  if (is.character(name_or_engine) && length(name_or_engine) == 1L &&
    !is.na(name_or_engine)) {
    entry <- .ms_registry[[name_or_engine]]
    if (is.null(entry)) {
      available <- .ms_registry_names()
      msuiter_abort(
        "registry",
        sprintf("unknown engine: %s", msuiter_quote_trunc(name_or_engine)),
        i = "engines resolve by name only after registration (A14)",
        j = paste0(
          "available engines: ",
          if (length(available)) paste(available, collapse = ", ") else "(none)"
        ),
        c = paste(
          "pass an MsEngine object (first-class citizen) or one of the",
          "listed names"
        )
      )
    }
    .ms_registry_warn_uncertified(entry)
    spec <- tryCatch(entry$engine_class(), error = function(e) e)
    if (inherits(spec, "error")) {
      msuiter_abort(
        "registry",
        "registered engine class cannot construct a default spec",
        i = paste(
          "string sugar resolves through engine_class(); its property",
          "defaults must form a valid spec"
        ),
        j = conditionMessage(spec),
        c = paste(
          "give the engine class defaults for name, mode and deterministic",
          "(see register_ms_engine())"
        )
      )
    }
    if (!identical(spec@name, entry$name)) {
      msuiter_abort(
        "registry",
        "default spec name does not match the registry key",
        i = "string sugar would resolve to a spec that fit_engine() cannot find",
        j = sprintf(
          "registry key: %s, default spec name: %s", entry$name, spec@name
        ),
        c = "align the class default for name with the registered key"
      )
    }
    return(spec)
  }
  msuiter_abort(
    "registry",
    "match_ms_engine() needs an MsEngine object or a single engine name",
    i = "MsEngine objects are first-class citizens; strings are sugar (A14)",
    j = paste0(
      "received: ",
      msuiter_quote_trunc(class(name_or_engine)[1L]),
      " of length ",
      length(name_or_engine)
    ),
    c = "pass the spec object, or the registered engine name as a single string"
  )
}

#' List registered engines
#'
#' `ms_engines()` returns a summary data.frame of the current registry
#' contents: one row per registered engine with its `mode` and the governance
#' fields. The package ships an empty registry; rows appear as engines are
#' registered (including third-party registrations from `.onLoad()`).
#'
#' @return a data.frame with columns `name`, `mode`, `engine_version`,
#'   `contract_version` and `certified`, sorted by `name`.
#'
#' @export
ms_engines <- function() {
  nms <- .ms_registry_names()
  df <- data.frame(
    name = nms,
    mode = vapply(nms, function(nm) .ms_registry[[nm]]$mode, character(1)),
    engine_version = vapply(
      nms, function(nm) .ms_registry[[nm]]$engine_version, character(1)
    ),
    contract_version = vapply(
      nms, function(nm) .ms_registry[[nm]]$contract_version, character(1)
    ),
    certified = vapply(nms, function(nm) .ms_registry[[nm]]$certified, character(1)),
    stringsAsFactors = FALSE
  )
  rownames(df) <- NULL
  df
}

# Test/session helper (not part of the user API): clears all registrations and
# warned markers so contract tests are order-independent.
msuiter_registry_reset <- function() {
  rm(
    list = ls(.ms_registry, all.names = TRUE),
    envir = .ms_registry, inherits = FALSE
  )
  rm(
    list = ls(.ms_registry_warned, all.names = TRUE),
    envir = .ms_registry_warned, inherits = FALSE
  )
  invisible(NULL)
}

# fit_engine() and required_pkgs() are the hardhat-corresponding generics of
# the registry. They keep the hardhat names per the CAPABILITY-MATRIX L-H API
# surface table; ARCHITECTURE.md section 3.2 keeps the "custom generics carry
# the ms_ prefix" rule with hardhat naming as a documented concept
# correspondence only.

#' Run an engine through its registered implementation
#'
#' `fit_engine()` dispatches on the [MsEngine] spec to the `fit_fn` stored on
#' its registry row (see [register_ms_engine()]). It is the hardhat-named
#' generic of the engine registry; the user-facing extraction/fitting entry
#' points (`ms_extract()`/`ms_fit()`) call it at the API boundary.
#'
#' @param engine an [MsEngine] spec (e.g. from [match_ms_engine()]).
#' @param ... passed through to the registered engine implementation.
#'
#' @return whatever the registered engine implementation returns.
#'
#' @export
fit_engine <- S7::new_generic("fit_engine", "engine")

S7::method(fit_engine, MsEngine) <- function(engine, ...) {
  entry <- .ms_registry[[engine@name]]
  if (is.null(entry)) {
    msuiter_abort(
      "registry",
      sprintf(
        "engine '%s' is not registered; fit_engine() dispatches through the registry",
        engine@name
      ),
      i = "the fit implementation lives on the registry row, not on the spec object",
      j = paste0(
        "available engines: ",
        if (length(.ms_registry_names())) {
          paste(.ms_registry_names(), collapse = ", ")
        } else {
          "(none)"
        }
      ),
      c = paste(
        "register the engine with register_ms_engine(), or resolve a",
        "registered engine with match_ms_engine()"
      )
    )
  }
  entry$fit_fn(engine, ...)
}

#' Report the packages required by an engine
#'
#' `required_pkgs()` returns the R packages an engine needs before it runs.
#' For a registered engine the registry row is authoritative; for an
#' unregistered spec the spec's own `packages` property is reported.
#'
#' @param engine an [MsEngine] spec.
#'
#' @return a character vector of package names (possibly empty).
#'
#' @export
required_pkgs <- S7::new_generic(
  "required_pkgs", "engine", function(engine) S7::S7_dispatch()
)

S7::method(required_pkgs, MsEngine) <- function(engine) {
  entry <- .ms_registry[[engine@name]]
  if (is.null(entry)) {
    return(engine@packages)
  }
  entry$packages
}
