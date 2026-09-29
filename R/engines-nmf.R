# ms_nmf(): the first real engine spec (U-M1s-12; ARCHITECTURE.md sections
# 3.2/3.4, decisions A14/D6).
#
# MsNmf is an S7 subclass of the abstract MsEngine with the NMF
# hyper-parameters frozen at factory time ("params 固化"): the spec object
# is the first-class citizen of ms_extract(method =), strings are only
# sugar resolved by match_ms_engine(). The spec stays small, serializable
# and metadata rich; no .state, no handles (D12).
#
# Engine choice (D6): "kl" (beta = 1 multiplicative updates = the Poisson
# MLE of a multinomial catalog model) is the default; "eu" (beta = 2,
# Frobenius) is the optional variant. Both run on the same Rust kernel
# face (engine::nmf) through the single-method extraction FFI
# (ms_extract_rust, U-M1s-12); replicates/consensus are M2 and absent.
#
# Registration: the package itself registers this one engine as certified
# (A17 governance fields filled); the registration helper is idempotent so
# that msuiter_registry_reset() (tests / third-party exploration) can
# re-arm it. Everything here respects the registry contract of
# R/engines-registry.R verbatim.

#' MsNmf: NMF engine specification
#'
#' [MsNmf] is the concrete [MsEngine] spec for non-negative matrix
#' factorization extraction (U-M1s-12). Build one with [ms_nmf()]; the
#' hyper-parameters are frozen on the spec object and the object is the
#' first-class `method` citizen of [ms_extract()]. The Rust kernel runs one
#' seeded fit (canonical zero stream): results are deterministic and
#' thread-invariant. Violations raise `msuiter_error_engine`.
#'
#' @param name single lower-case snake_case engine name; the MsNmf class
#'   fixes it to `"nmf"` (the registry key).
#' @param mode spec mode; the MsNmf class fixes it to `"extract"`.
#' @param params named list of hyper-parameters (empty: the NMF
#'   hyper-parameters live in the dedicated `variant`/`max_iter`/`seed`
#'   properties below, mirroring the atomic property defaults of
#'   [MsEngine]).
#' @param deterministic always TRUE: the kernel is seeded and
#'   thread-invariant (A7).
#' @param packages character vector of required R packages; the msuiter
#'   kernel needs none.
#' @param label human-readable engine label.
#' @param variant single string, one of `"kl"` (generalized KL divergence,
#'   the D6 default: the multiplicative updates are the Poisson MLE of the
#'   multinomial catalog model) or `"eu"` (squared Frobenius).
#' @param max_iter single positive whole number of multiplicative-update
#'   iterations (no early stopping: a run is a pure function of its inputs).
#' @param seed single whole number in `[0, 2^31 - 1]` seeding the in-house
#'   PCG64 stream of the initializer.
#'
#' @export
MsNmf <- S7::new_class(
  "MsNmf",
  package = "msuiter",
  parent = MsEngine,
  properties = list(
    name = S7::new_property(S7::class_character, default = "nmf"),
    mode = S7::new_property(S7::class_character, default = "extract"),
    params = S7::new_property(S7::class_list, default = list()),
    deterministic = S7::new_property(S7::class_logical, default = TRUE),
    packages = S7::new_property(S7::class_character, default = character(0)),
    label = S7::new_property(
      S7::class_character, default = "NMF multiplicative updates"
    ),
    variant = S7::new_property(S7::class_character, default = "kl"),
    max_iter = S7::new_property(S7::class_numeric, default = 500),
    seed = S7::new_property(S7::class_numeric, default = 1)
  ),
  validator = function(self) msuiter_validate_nmf(self)
)

# Legal NMF variants (kernel faces of engine::nmf reachable through the
# single-method extraction FFI).
.ms_nmf_variants <- c("kl", "eu")

msuiter_validate_nmf <- function(self) {
  # The abstract-engine contract first (name/mode/params-shape/
  # deterministic/packages/label); S7 does not run parent validators.
  msuiter_validate_engine(self)

  variant <- self@variant
  if (!is.character(variant) || length(variant) != 1L || is.na(variant) ||
    !variant %in% .ms_nmf_variants) {
    msuiter_abort(
      "engine",
      paste0(
        "NMF engine variant must be one of ",
        paste0("'", .ms_nmf_variants, "'", collapse = ", ")
      ),
      i = paste(
        "'kl' is the D6 default (Poisson MLE of the multinomial catalog",
        "model); 'eu' minimizes the squared Frobenius error"
      ),
      j = paste0("received: ", msuiter_quote_trunc(variant)),
      c = "call ms_nmf(engine = \"kl\") or ms_nmf(engine = \"eu\")"
    )
  }

  max_iter <- self@max_iter
  if (!is.numeric(max_iter) || length(max_iter) != 1L || is.na(max_iter) ||
    !is.finite(max_iter) || max_iter != trunc(max_iter) || max_iter < 1) {
    msuiter_abort(
      "engine",
      "max_iter must be a single positive whole number",
      i = "the kernel runs a fixed iteration count (no early stopping)",
      j = paste0("received: ", msuiter_quote_trunc(max_iter)),
      c = "pass e.g. max_iter = 500 (the factory default)"
    )
  }

  seed <- self@seed
  if (!is.numeric(seed) || length(seed) != 1L || is.na(seed) ||
    !is.finite(seed) || seed != trunc(seed) || seed < 0 || seed > 2^31 - 1) {
    msuiter_abort(
      "engine",
      "seed must be a single whole number in [0, 2^31 - 1]",
      i = "the seed selects the PCG64 stream of the seeded initializer",
      j = paste0("received: ", msuiter_quote_trunc(seed)),
      c = "pass an integer seed, e.g. seed = 1 (the factory default)"
    )
  }
  NULL
}

#' Create an NMF engine specification
#'
#' `ms_nmf()` builds an [MsNmf] spec for [ms_extract()]: non-negative
#' matrix factorization on the Rust kernel (`engine::nmf`, U-M1s-02) with
#' the hyper-parameters frozen at factory time. The returned object is the
#' first-class `method` citizen (A14); the string `"nmf"` is sugar that
#' resolves to the registered factory defaults via [match_ms_engine()].
#'
#' @param engine one of `"kl"` (generalized KL divergence, the D6 default:
#'   the multiplicative updates are the Poisson MLE of the multinomial
#'   catalog model) or `"eu"` (squared Frobenius). Stored on the spec's
#'   `variant` property.
#' @param max_iter single positive whole number of multiplicative-update
#'   iterations (no early stopping: a run is a pure function of its inputs).
#' @param seed single whole number in `[0, 2^31 - 1]` seeding the in-house
#'   PCG64 stream of the initializer.
#'
#' @return An [MsNmf] object (an [MsEngine] subclass).
#' @examples
#' ms_nmf()                       # D6 default: KL, 500 iterations, seed 1
#' ms_nmf(engine = "eu", seed = 42)
#' @export
ms_nmf <- function(engine = "kl", max_iter = 500, seed = 1) {
  MsNmf(variant = engine, max_iter = max_iter, seed = seed)
}

# One-line print/format refinement over the MsEngine fallback: show the
# frozen hyper-parameters (print() is inherited from MsEngine and renders
# whatever format() returns).
S7::method(format, MsNmf) <- function(x, ...) {
  det <- if (isTRUE(x@deterministic)) "deterministic" else "stochastic"
  sprintf(
    "<MsNmf> %s [%s] | mode: %s | %s | max_iter: %s, seed: %s",
    x@name, x@variant, x@mode, det,
    format(x@max_iter), format(x@seed)
  )
}

# Engine implementation behind the registry row (called as
# fit_fn(engine, catalog = , k = ) through fit_engine() at the API
# boundary): run the single seeded NMF extraction over the catalog counts
# and return the RAW kernel factors. Assembly into an MsSignature
# (labels, display normalization, snapshot summary) is ms_extract()'s job.
.ms_nmf_fit_fn <- function(engine, catalog, k, ...) {
  if (!S7::S7_inherits(catalog, MsCatalog)) {
    msuiter_abort(
      "input",
      "catalog must be an MsCatalog object",
      i = "the NMF engine factorizes a channel x sample count matrix",
      j = paste0("received: ", class(catalog)[1L]),
      c = "tally variants with ms_tally() first"
    )
  }
  .ms_extract_rust(
    counts = catalog@counts,
    k = k,
    max_iter = engine@max_iter,
    seed = engine@seed,
    engine = engine@variant
  )
}

# Idempotent registration of the package's own engine (the registry ships
# empty by design; this is the first certified row). Tests may reset the
# registry and call this helper to re-arm the row.
msuiter_register_nmf_engine <- function() {
  if (exists("nmf", envir = .ms_registry, inherits = FALSE)) {
    return(invisible(NULL))
  }
  register_ms_engine(
    name = "nmf",
    mode = "extract",
    engine_class = MsNmf,
    fit_fn = .ms_nmf_fit_fn,
    packages = character(0),
    tags = c("extract", "nmf", "kl"),
    engine_version = "0.0.0.9000",
    contract_version = "1",
    certified = "certified"
  )
  invisible("nmf")
}

msuiter_register_nmf_engine()
