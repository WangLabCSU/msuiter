# Third-party extension contract tests (U-M2-04 closeout; ARCHITECTURE.md
# sections 3.4/3.5): the extraction-assembly side of the extension surface,
# complementing test-engines-registry.R (which covers the registry itself).
# Everything here is synthetic: a base-R Frobenius-NMF engine registered from
# a fake .onLoad() and driven through the full ms_extract() pipeline -- the
# executable twin of vignettes/extending.Rmd. The extension contract for an
# extract engine: fit_fn(engine, catalog = , k = ) returns RAW factors
# (channels x k, k x samples); the engine class carries a `seed` property for
# the assembly provenance; violations raise msuiter_error_* with the i/j/c
# payload; non-certified rows warn exactly once per session per engine.

# Planted truth: three signatures with disjoint 16-channel blocks (seeded
# per-channel weights), same construction as the extending.Rmd tutorial.
.make_extend_truth <- function(seed = 11) {
  ch <- 48L
  k <- 3L
  withr::with_seed(seed, {
    t(vapply(seq_len(k) - 1L, function(s) {
      v <- numeric(ch)
      v[(s * 16L + 1L):((s + 1L) * 16L)] <- 0.5 + stats::runif(16L)
      v / sum(v)
    }, numeric(ch)))
  })
}

# Synthetic catalog: 48 channels x 8 samples built from the planted truth
# (dominant + small background per sample group).
.make_extend_catalog <- function(seed = 11) {
  ch <- 48L
  ns <- 8L
  k <- 3L
  planted <- .make_extend_truth(seed)
  H_true <- matrix(2, k, ns)
  for (j in seq_len(ns)) H_true[(j - 1L) %% k + 1L, j] <- 60
  counts <- round(100 * crossprod(planted, H_true))
  dimnames(counts) <- list(paste0("C", seq_len(ch)), paste0("S", seq_len(ns)))
  ms_catalog(
    counts = counts,
    channels = list(name = "SYN48", labels = paste0("C", seq_len(ch))),
    samples = paste0("S", seq_len(ns)),
    provenance = list(genome = "SYN")
  )
}

# Engine spec class with defaults valid for string sugar (name/mode/
# deterministic) plus the assembly-required `seed` property.
.make_extend_class <- function(name = "tut_eu", mode = "extract",
                               with_seed = TRUE) {
  props <- list(
    name = S7::new_property(S7::class_character, default = name),
    mode = S7::new_property(S7::class_character, default = mode),
    deterministic = S7::new_property(S7::class_logical, default = TRUE),
    packages = S7::new_property(S7::class_character, default = character(0)),
    label = S7::new_property(S7::class_character, default = "Tutorial EU-NMF"),
    max_iter = S7::new_property(S7::class_numeric, default = 200)
  )
  if (with_seed) {
    props$seed <- S7::new_property(S7::class_numeric, default = 1)
  }
  S7::new_class(
    paste0("TutEngine_", name), package = "fake.othersig",
    parent = MsEngine, properties = props
  )
}

# Base-R Frobenius ("eu") NMF multiplicative updates: deterministic (own
# seeded stream, caller's .Random.seed preserved) and thread invariant.
.make_extend_fit_fn <- function() {
  function(engine, catalog, k, ...) {
    if (!S7::S7_inherits(catalog, MsCatalog)) {
      rlang::abort(
        "catalog must be an MsCatalog object",
        class = "msuiter_error_input",
        msuiter_error = list(
          topic = "input",
          i = "the tutorial engine factorizes a channel x sample count matrix",
          j = paste0("received: ", class(catalog)[1L]),
          c = "build the catalog with ms_catalog() first"
        )
      )
    }
    k <- as.integer(k)
    counts <- catalog@counts
    m <- nrow(counts)
    n <- ncol(counts)
    eps <- 1e-12
    had_seed <- exists(".Random.seed", envir = globalenv())
    if (had_seed) old_seed <- get(".Random.seed", envir = globalenv())
    on.exit(
      if (had_seed) assign(".Random.seed", old_seed, envir = globalenv()),
      add = TRUE
    )
    set.seed(tryCatch(engine@seed, error = function(e) 1))
    block <- rep(seq_len(k), each = ceiling(m / k))[seq_len(m)]
    W <- matrix(1 / m, m, k)
    W[cbind(seq_len(m), block)] <- 1 / k
    W <- W * (1 + 0.1 * stats::runif(m * k))
    W <- sweep(W, 2, colSums(W), "/")
    H <- matrix(mean(counts), k, n) * (0.5 + stats::runif(k * n))
    for (iter in seq_len(engine@max_iter)) {
      H <- H * (crossprod(W, counts) + eps) / (crossprod(W, W %*% H) + eps)
      W <- W * (tcrossprod(counts, H) + eps) / (W %*% tcrossprod(H, H) + eps)
    }
    list(signatures = W, exposures = H)
  }
}

.register_extend_engine <- function(name = "tut_eu", mode = "extract",
                                   certified = "self-reported",
                                   with_seed = TRUE, fit_fn = NULL) {
  register_ms_engine(
    name = name,
    mode = mode,
    engine_class = .make_extend_class(name, mode = mode, with_seed = with_seed),
    fit_fn = if (is.null(fit_fn)) .make_extend_fit_fn() else fit_fn,
    packages = character(0),
    tags = c("third-party", "synthetic"),
    engine_version = "0.1.0",
    contract_version = "1",
    certified = certified
  )
  invisible(name)
}

test_that("third-party .onLoad engine runs through the full ms_extract assembly", {
  msuiter_registry_reset()
  .register_extend_engine("tut_eu", certified = "self-reported")

  # self-reported: first resolution warns, and the warning carries the trust
  # boundary message (A17)
  expect_warning(
    fit <- ms_extract(.make_extend_catalog(), k = 3, method = "tut_eu"),
    class = "msuiter_warning_uncertified_engine"
  )
  # idempotent: object path and repeat sugar never warn again
  expect_no_warning(
    ms_extract(.make_extend_catalog(), 3, .make_extend_class("tut_eu")())
  )
  expect_no_warning(ms_extract(.make_extend_catalog(), 3, "tut_eu"))

  # assembled MsSignature: engine + seed provenance, dims and labels
  expect_is_ms(fit, "MsSignature")
  expect_identical(fit@engine, "tut_eu")
  expect_identical(fit@seed, 1)
  ch <- 48L
  expect_identical(dim(fit@signatures), c(ch, 3L))
  expect_identical(dim(fit@exposures), c(3L, 8L))
  expect_identical(colnames(fit@signatures), c("Sig1", "Sig2", "Sig3"))
  expect_identical(colnames(fit@exposures), paste0("S", seq_len(8)))

  # recovery: each planted signature matches a recovered one > 0.95 cosine
  # (best match per planted row, disjoint supports by construction; both
  # sides L2-normalized; truth carries seeded per-channel weights)
  planted <- .make_extend_truth()
  planted_n <- sweep(planted, 1, sqrt(rowSums(planted^2)), "/")
  rec_n <- sweep(fit@signatures, 2, sqrt(colSums(fit@signatures^2)), "/")
  cos <- as.vector(planted_n %*% rec_n)
  best <- tapply(cos, rep(seq_len(3), each = 3), max)
  expect_true(all(best > 0.95), info = paste(round(best, 4), collapse = ", "))
})

test_that("a certified third-party engine resolves and runs without warning", {
  msuiter_registry_reset()
  .register_extend_engine("tut_cert", certified = "certified")
  expect_no_warning(fit <- ms_extract(.make_extend_catalog(), 3, "tut_cert"))
  expect_identical(fit@engine, "tut_cert")
})

test_that("degenerate raw factors abort with msuiter_error_signature", {
  msuiter_registry_reset()
  # a fit that collapses one signature column to zero mass: the assembly's
  # display normalization guard must catch it (numerical contract, ARCH 3.5)
  degenerate <- function(engine, catalog, k, ...) {
    raw <- .make_extend_fit_fn()(engine, catalog, k)
    raw$signatures[, 2] <- 0
    raw
  }
  .register_extend_engine("tut_degen", fit_fn = degenerate,
                          certified = "certified")
  expect_ms_error(
    ms_extract(.make_extend_catalog(), 3, "tut_degen"),
    "signature", regexp = "degenerated"
  )
})

test_that("engine failures surface with their own msuiter_error_* class", {
  msuiter_registry_reset()
  failing <- function(engine, catalog, k, ...) {
    rlang::abort(
      "third-party kernel failed",
      class = "msuiter_error_engine",
      msuiter_error = list(
        topic = "engine",
        i = "the synthetic kernel refuses to run",
        j = "synthetic failure",
        c = "this is a test double"
      )
    )
  }
  .register_extend_engine("tut_fail", fit_fn = failing,
                          certified = "certified")
  # ms_extract() propagates engine-side conditions as-is (no re-wrapping)
  expect_ms_error(
    ms_extract(.make_extend_catalog(), 3, "tut_fail"),
    "engine", regexp = "third-party kernel failed"
  )
})

test_that("ms_extract rejects fit-mode third-party engines", {
  msuiter_registry_reset()
  .register_extend_engine("tut_fitmode", mode = "fit",
                          certified = "certified")
  expect_ms_error(
    ms_extract(.make_extend_catalog(), 3, "tut_fitmode"),
    "input", regexp = "mode"
  )
})

test_that("spec classes without a seed property warn and default to seed = 1", {
  msuiter_registry_reset()
  # audited P2 fallback: the ms_extract assembly reads spec@seed for
  # provenance; a third-party class that omits the property degrades to a
  # registry warning plus the seed = 1 default instead of failing the
  # assembly (the registration path already warns about such specs).
  expect_warning(
    .register_extend_engine("tut_noseed", with_seed = FALSE,
                            certified = "certified"),
    class = "msuiter_warning_registry"
  )
  expect_warning(
    fit <- ms_extract(.make_extend_catalog(), 3, "tut_noseed"),
    class = "msuiter_warning_registry"
  )
  expect_identical(fit@seed, 1)
})
