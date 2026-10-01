# ms_ard(): the ARD engine spec (U-M2-04; M2 registry integration).
#
# MsArd is an S7 subclass of the abstract MsEngine wrapping the
# SignatureAnalyzer-semantics ARD kernel (engine/ard.rs; semantic source
# pinned at sigminer bayesianNMF.R, line-level — see the kernel module
# docs). Automatic rank determination: the kernel prunes dead components
# (beta_k > beta_cut or a zero column), so the returned k_est may be
# smaller than the requested k0 — the signature/exposure faces come back
# at k_est and `active` records the survival mask.
#
# Registration follows R/engines-nmf.R verbatim (certified row; idempotent
# helper for registry resets).
#
# Budget divergence (D13 discipline, recorded): the upstream ARD driver
# allows n.iter = 2,000,000 with tol = 1e-5; the ms_ard() default cap is
# max_iter = 2000 (reaching upstream-scale iteration counts is a workload
# decision — raise max_iter explicitly). Recorded per the Delta discipline
# (same pattern as replicates = 8).

#' MsArd: ARD engine specification
#'
#' [MsArd] is the concrete [MsEngine] spec for automatic-relevance-
#' determination NMF extraction (U-M2-04; SignatureAnalyzer semantics:
#' KL likelihood with an ARD prior on component precisions, automatic
#' rank pruning). Build one with [ms_ard()]. Violations raise
#' `msuiter_error_engine`.
#'
#' @param name registry key; fixed to `"ard"`.
#' @param mode spec mode; fixed to `"extract"`.
#' @param params named list of hyper-parameters (empty: the ARD
#'   hyper-parameters live in the dedicated properties below).
#' @param deterministic always TRUE: the kernel is seeded and
#'   deterministic.
#' @param packages character vector of required R packages; none.
#' @param label human-readable engine label.
#' @param a0 ARD prior shape (upstream default 10).
#' @param b0 ARD prior rate (upstream default 5).
#' @param tol convergence tolerance on the max relative beta change
#'   (upstream default 1e-5).
#' @param max_iter single positive whole number of update iterations.
#' @param seed single whole number in `[0, 2^31 - 1]` seeding the in-house
#'   PCG64 stream of the initializer.
#'
#' @export
MsArd <- S7::new_class(
  "MsArd",
  package = "msuiter",
  parent = MsEngine,
  properties = list(
    name = S7::new_property(S7::class_character, default = "ard"),
    mode = S7::new_property(S7::class_character, default = "extract"),
    params = S7::new_property(S7::class_list, default = list()),
    deterministic = S7::new_property(S7::class_logical, default = TRUE),
    packages = S7::new_property(S7::class_character, default = character(0)),
    label = S7::new_property(
      S7::class_character, default = "ARD-NMF (SignatureAnalyzer semantics)"
    ),
    a0 = S7::new_property(S7::class_numeric, default = 10),
    b0 = S7::new_property(S7::class_numeric, default = 5),
    tol = S7::new_property(S7::class_numeric, default = 1e-5),
    max_iter = S7::new_property(S7::class_numeric, default = 2000),
    seed = S7::new_property(S7::class_numeric, default = 1)
  ),
  validator = function(self) msuiter_validate_ard(self)
)

msuiter_validate_ard <- function(self) {
  msuiter_validate_engine(self)
  for (nm in c("a0", "b0")) {
    v <- switch(nm, a0 = self@a0, b0 = self@b0)
    if (!is.numeric(v) || length(v) != 1L || !is.finite(v) || v <= 0) {
      msuiter_abort(
        "engine",
        sprintf("`%s` must be a single finite number > 0", nm),
        i = paste0("got: ", format(v)),
        j = paste0("the ARD prior property `", nm, "`"),
        c = "construct with ms_ard(a0 = , b0 = ) using positive values"
      )
    }
  }
  v <- self@tol
  if (!is.numeric(v) || length(v) != 1L || !is.finite(v) || v < 0) {
    msuiter_abort(
      "engine",
      "`tol` must be a single finite number >= 0",
      i = paste0("got: ", format(v)),
      j = "the ARD convergence-tolerance property `tol`",
      c = "construct with a finite non-negative tolerance"
    )
  }
  v <- self@max_iter
  if (!is.numeric(v) || length(v) != 1L || !is.finite(v) || v < 1 ||
    v != floor(v)) {
    msuiter_abort(
      "engine",
      "`max_iter` must be a single positive whole number",
      i = paste0("got: ", format(v)),
      j = "the ARD iteration-cap property `max_iter`",
      c = "construct with a positive whole-number max_iter"
    )
  }
  v <- self@seed
  if (!is.numeric(v) || length(v) != 1L || !is.finite(v) || v < 0 ||
    v != floor(v) || v > 2^31 - 1) {
    msuiter_abort(
      "engine",
      "`seed` must be a single whole number in [0, 2^31 - 1]",
      i = paste0("got: ", format(v)),
      j = "the ARD initializer-seed property `seed`",
      c = "construct with a whole-number seed in range"
    )
  }
  invisible(NULL)
}

#' ms_ard(): ARD-NMF engine factory
#'
#' Build an [MsArd] spec for [ms_extract(method =)]: KL likelihood with an
#' ARD prior over component precisions (SignatureAnalyzer semantics) and
#' automatic rank pruning — the returned fit reports `k_est <= k0` active
#' components.
#'
#' @param a0,b0 ARD prior shape and rate (upstream defaults 10 / 5).
#' @param tol convergence tolerance (max relative beta change).
#' @param max_iter iteration cap.
#' @param seed initializer seed (in-house PCG64 stream).
#'
#' @return an [MsArd] spec object.
#' @export
ms_ard <- function(a0 = 10, b0 = 5, tol = 1e-5, max_iter = 2000, seed = 1) {
  MsArd(a0 = a0, b0 = b0, tol = tol, max_iter = max_iter, seed = seed)
}

#' ARD extraction kernel wrapper (internal, U-M2-04 batch C).
#'
#' @param counts channel × sample count matrix (the MsCatalog slot).
#' @param k0 requested rank; the kernel may prune to k_est < k0.
#' @noRd
.ms_ard_rust <- function(counts, k0, max_iter, tol, a0, b0, seed) {
  if (!is.matrix(counts) || !is.numeric(counts)) {
    msuiter_abort(
      "input",
      "counts must be a numeric matrix",
      i = "the ARD kernel consumes the MsCatalog counts slot (transposed to t(counts) for the FFI)"
    )
  }
  if (!is.numeric(k0) || length(k0) != 1L || is.na(k0) || k0 < 1 ||
    k0 != floor(k0)) {
    msuiter_abort(
      "input",
      "`k0` must be a single positive whole number",
      i = paste0("got: ", format(k0))
    )
  }
  ms_ard_rust(
  # Layout contract (extract.rs docs): the FFI consumes t(counts) --
  # n_samples x m_channels, whose column-major flat buffer is the kernel's
  # row-major m x n V. Signatures return at m x k_est.
    counts = t(counts),
    k0 = as.integer(k0),
    max_iter = as.integer(max_iter),
    tol = as.double(tol),
    a0 = as.double(a0),
    b0 = as.double(b0),
    seed = as.integer(seed),
    n_threads = 0L
  )
}

.ms_ard_fit_fn <- function(engine, catalog, k, ...) {
  if (!S7::S7_inherits(catalog, MsCatalog)) {
    msuiter_abort(
      "input",
      "catalog must be an MsCatalog object",
      i = "the ARD engine factorizes a channel x sample count matrix",
      j = paste0("received: ", class(catalog)[1L]),
      c = "tally variants with ms_tally() first"
    )
  }
  .ms_ard_rust(
    counts = catalog@counts,
    k0 = k,
    max_iter = engine@max_iter,
    tol = engine@tol,
    a0 = engine@a0,
    b0 = engine@b0,
    seed = engine@seed
  )
}

msuiter_register_ard_engine <- function() {
  if (exists("ard", envir = .ms_registry, inherits = FALSE)) {
    return(invisible(NULL))
  }
  register_ms_engine(
    name = "ard",
    mode = "extract",
    engine_class = MsArd,
    fit_fn = .ms_ard_fit_fn,
    packages = character(0),
    tags = c("extract", "ard", "auto-rank"),
    engine_version = "0.0.0.9000",
    contract_version = "1",
    certified = "certified"
  )
  invisible("ard")
}

msuiter_register_ard_engine()
