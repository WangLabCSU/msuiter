# ms_sparse(): penalized sparse NMF engine specs (U-M2-05; M2 registry
# integration).
#
# MsSparse wraps the engine/sparse.rs kernels: "volume" = KL + lambda *
# log-det volume regularization on W (Leplat-Gillis-Ang; mvnmf.py, MIT)
# and "l1" = KL + lambda * sum(H) + mu * sum(W) (Hoyer/Cichocki KL-L1L1
# MU; SparseSignatures itself is least-squares + LASSO — attribution
# erratum in engine/sparse.rs).
# The l1 variant needs BOTH penalties: with mu = 0 the exposure scale is
# absorbed into W and the sparsity degenerates (documented derivation in
# the kernel module docs).
#
# Registration follows R/engines-nmf.R verbatim (certified row; idempotent
# helper for registry resets).

#' MsSparse: penalized sparse NMF engine specification
#'
#' [MsSparse] is the concrete [MsEngine] spec for penalized sparse NMF
#' extraction (U-M2-05): `"volume"` = KL likelihood with a log-det volume
#' regularizer on W (Leplat-Gillis-Ang), `"l1"` = KL with L1 penalties on
#' both factors (Hoyer/Cichocki KL-L1L1 MU; SparseSignatures itself is
#' least-squares + LASSO — attribution erratum in engine/sparse.rs).
#' mu = 0 degenerates). Build one
#' with [ms_sparse()]. Violations raise `msuiter_error_engine`.
#'
#' @param name registry key; fixed to `"sparse"`.
#' @param mode spec mode; fixed to `"extract"`.
#' @param params named list of hyper-parameters (empty: the sparse
#'   hyper-parameters live in the dedicated properties below).
#' @param deterministic always TRUE: the kernel is seeded and
#'   deterministic.
#' @param packages character vector of required R packages; none.
#' @param label human-readable engine label.
#' @param variant `"volume"` or `"l1"`.
#' @param lambda penalty on the signatures (volume strength / H-row L1).
#' @param mu W-column L1 penalty (l1 variant only; must be > 0 there —
#'   mu = 0 degenerates the exposure scale).
#' @param delta volume regularizer ridge (volume variant only; 0 picks the
#'   kernel default 1).
#' @param tol convergence tolerance on the relative objective change.
#' @param max_iter single positive whole number of update iterations.
#' @param seed single whole number in `[0, 2^31 - 1]`.
#'
#' @export
MsSparse <- S7::new_class(
  "MsSparse",
  package = "msuiter",
  parent = MsEngine,
  properties = list(
    name = S7::new_property(S7::class_character, default = "sparse"),
    mode = S7::new_property(S7::class_character, default = "extract"),
    params = S7::new_property(S7::class_list, default = list()),
    deterministic = S7::new_property(S7::class_logical, default = TRUE),
    packages = S7::new_property(S7::class_character, default = character(0)),
    label = S7::new_property(
      S7::class_character, default = "penalized sparse NMF"
    ),
    variant = S7::new_property(S7::class_character, default = "l1"),
    lambda = S7::new_property(S7::class_numeric, default = 0),
    mu = S7::new_property(S7::class_numeric, default = 0),
    delta = S7::new_property(S7::class_numeric, default = 0),
    tol = S7::new_property(S7::class_numeric, default = 1e-7),
    max_iter = S7::new_property(S7::class_numeric, default = 2000),
    seed = S7::new_property(S7::class_numeric, default = 1)
  ),
  validator = function(self) msuiter_validate_sparse(self)
)

msuiter_validate_sparse <- function(self) {
  msuiter_validate_engine(self)
  if (!self@variant %in% c("volume", "l1")) {
    msuiter_abort(
      "engine",
      '`variant` must be "volume" or "l1"',
      i = paste0("got: ", self@variant),
      j = "the MsSparse variant property",
      c = "construct with ms_sparse(variant = ...)"
    )
  }
  for (nm in c("lambda", "mu", "delta", "tol")) {
    v <- switch(nm,
      lambda = self@lambda, mu = self@mu,
      delta = self@delta, tol = self@tol
    )
    if (!is.numeric(v) || length(v) != 1L || !is.finite(v) || v < 0) {
      msuiter_abort(
        "engine",
        sprintf("`%s` must be a single finite number >= 0", nm),
        i = paste0("got: ", format(v)),
        j = paste0("the sparse penalty/tolerance property `", nm, "`"),
        c = "construct with ms_sparse(...) using non-negative values"
      )
    }
  }
  if (self@variant == "l1" && self@mu <= 0) {
    msuiter_abort(
      "engine",
      "the l1 variant requires mu > 0 (mu = 0 degenerates the exposure scale)",
      i = paste0("got mu: ", format(self@mu)),
      j = "the MsSparse l1-variant `mu` property",
      c = "use the volume variant for a single-penalty form"
    )
  }
  v <- self@max_iter
  if (!is.numeric(v) || length(v) != 1L || !is.finite(v) || v < 1 ||
    v != floor(v)) {
    msuiter_abort(
      "engine",
      "`max_iter` must be a single positive whole number",
      i = paste0("got: ", format(v)),
      j = "the sparse iteration-cap property `max_iter`",
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
      j = "the sparse initializer-seed property `seed`",
      c = "construct with a whole-number seed in range"
    )
  }
  invisible(NULL)
}

#' ms_sparse(): penalized sparse NMF engine factory
#'
#' Build an [MsSparse] spec for [ms_extract(method =)].
#'
#' @param variant `"l1"` (KL + L1 penalties on both factors; default) or
#'   `"volume"` (KL + log-det volume regularizer on W).
#' @param lambda signatures penalty (volume strength / H-row L1).
#' @param mu W-column L1 penalty (l1 variant; must be > 0).
#' @param delta volume ridge (volume variant; 0 = kernel default 1).
#' @param tol convergence tolerance (relative objective change).
#' @param max_iter iteration cap.
#' @param seed initializer seed (in-house PCG64 stream).
#'
#' @return an [MsSparse] spec object.
#' @export
ms_sparse <- function(variant = "l1", lambda = 0, mu = 0,
  delta = 0, tol = 1e-7, max_iter = 2000, seed = 1) {
  # No match.arg(): an invalid variant must surface as msuiter_error_engine
  # (the class validator), not base R's selection error (error protocol,
  # ARCHITECTURE section 3.5).
  MsSparse(
    variant = variant, lambda = lambda, mu = mu, delta = delta,
    tol = tol, max_iter = max_iter, seed = seed
  )
}

#' Sparse extraction kernel wrapper (internal, U-M2-05 batch C).
#'
#' @param counts channel × sample count matrix (the MsCatalog slot).
#' @param k requested rank.
#' @noRd
.ms_sparse_rust <- function(counts, k, max_iter, variant, lambda, mu,
  delta, tol, seed) {
  if (!is.matrix(counts) || !is.numeric(counts)) {
    msuiter_abort(
      "input",
      "counts must be a numeric matrix",
      i = "the sparse kernel consumes the MsCatalog counts slot (transposed to t(counts) for the FFI)"
    )
  }
  if (!is.numeric(k) || length(k) != 1L || is.na(k) || k < 1 ||
    k != floor(k)) {
    msuiter_abort(
      "input",
      "`k` must be a single positive whole number",
      i = paste0("got: ", format(k))
    )
  }
  ms_sparse_rust(
  # Layout contract (extract.rs docs): the FFI consumes t(counts) --
  # n_samples x m_channels, whose column-major flat buffer is the kernel's
  # row-major m x n V. Signatures return at m x k_est.
    counts = t(counts),
    k = as.integer(k),
    max_iter = as.integer(max_iter),
    variant = variant,
    lambda = as.double(lambda),
    mu = as.double(mu),
    delta = as.double(delta),
    tol = as.double(tol),
    seed = as.integer(seed),
    n_threads = 0L
  )
}

.ms_sparse_fit_fn <- function(engine, catalog, k, ...) {
  if (!S7::S7_inherits(catalog, MsCatalog)) {
    msuiter_abort(
      "input",
      "catalog must be an MsCatalog object",
      i = "the sparse engine factorizes a channel x sample count matrix",
      j = paste0("received: ", class(catalog)[1L]),
      c = "tally variants with ms_tally() first"
    )
  }
  .ms_sparse_rust(
    counts = catalog@counts,
    k = k,
    max_iter = engine@max_iter,
    variant = engine@variant,
    lambda = engine@lambda,
    mu = engine@mu,
    delta = engine@delta,
    tol = engine@tol,
    seed = engine@seed
  )
}

msuiter_register_sparse_engine <- function() {
  if (exists("sparse", envir = .ms_registry, inherits = FALSE)) {
    return(invisible(NULL))
  }
  register_ms_engine(
    name = "sparse",
    mode = "extract",
    engine_class = MsSparse,
    fit_fn = .ms_sparse_fit_fn,
    packages = character(0),
    tags = c("extract", "sparse", "volume", "l1"),
    engine_version = "0.0.0.9000",
    contract_version = "1",
    certified = "certified"
  )
  invisible("sparse")
}

msuiter_register_sparse_engine()
