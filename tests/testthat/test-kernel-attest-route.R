# P3 lane, attest-route TDD pair (parity plan lane 3: the R-side share of
# the batch consumption tax).
#
# The forensics decomposition (P3-RSIDE, banked) measured the per-case
# receipt attestation at 0.695 s of R wall per 50-restart unit through the
# reference readers, versus 0.287 s through the P2 L4 vectorized readers
# whose identical-grade equivalence to the reference route is pinned by
# test-kernel-pipeline-parse.R (L4 family, identical() not tolerance). The
# attestation loop is therefore the next honest gram on the R side, and it
# moves ONLY under a byte-identity predicate: this file pins that the
# route switch exists, that the fast route is really consulted (mechanism
# sentinel -- a silent fallback to the reference route would be the
# fake-green failure mode), that both routes hand back identical() receipt
# bundles over real certified batch bytes, and that an unknown route is
# fail-closed.
#
# Units A-1, A-2 and A-4 are red by absence until the GREEN commit adds
# the `route` argument to kp_attest_case in R/kernel-pipeline.R. The
# subject names are taken through .kpp_surface, so an unreachable surface
# is an explicit TDD-red stop, never a silent pass.

.kar_scenario <- local({
  cached <- new.env(parent = emptyenv())
  function() {
    if (!is.null(cached$sc)) return(cached$sc)
    sc <- .kpp_valid_scenario()
    res <- .kpp_exec_real(sc$bin, .kpp_batch_argv(sc$manifest, sc$in.root,
                                                  sc$out.root))
    expect_identical(res$rc, 0L)
    cached$sc <- sc
    sc
  }
})

# The attest call this file drives, mirroring kp_run_batch's argument
# positionally (manifest raw strings for seed/replicate).
.kar_attest <- function(sc, route) {
  kp_attest_case(case = sc$case, out.dir = sc$case.out, m = sc$m,
                 n = sc$n, k = sc$k, iters = sc$iters, init = "nndsvd",
                 seed = "11", replicate = "", route = route)
}

# Swap one namespace binding for the duration of expr (the house
# assignInNamespace idiom, generalized from .kpp_with_exec).
.kar_with <- function(name, fn, expr) {
  expr <- substitute(expr)
  env <- parent.frame(1L)
  ns <- tryCatch(asNamespace("msuiter"), error = function(e) NULL)
  if (is.null(ns)) stop("msuiter namespace not loaded", call. = FALSE)
  if (!exists(name, envir = ns, inherits = FALSE)) {
    stop(paste0("TDD red: pipeline surface '", name,
                "' is not implemented yet"), call. = FALSE)
  }
  old <- get(name, envir = ns)
  unlockBinding(name, env = ns)
  on.exit({
    assign(name, old, envir = ns)
    lockBinding(name, env = ns)
  }, add = TRUE)
  on.exit(eval(expr, envir = env), add = TRUE)
  assign(name, fn, envir = ns)
  invisible(NULL)
}

test_that("A-1 the attest face carries a route argument defaulting to fast", {
  fmls <- names(formals(kp_attest_case))
  expect_true("route" %in% fmls)
  expect_identical(eval(formals(kp_attest_case)$route), c("fast", "reference"))
})

test_that("A-2 mechanism: the fast route really consults the fast readers
           and the reference route never does", {
  sc <- .kar_scenario()
  boom <- function(...) stop("FAST-CONSULTED", domain = NA)
  # Reference route under the sentinel: must never reach the fast readers.
  .kar_with("kp_read_trace_fast", boom, {
    r <- .kar_attest(sc, "reference")
    expect_true(is.matrix(r$W) && identical(dim(r$W), c(sc$m, sc$k)))
    expect_identical(length(r$objective), sc$iters + 1L)
  })
  # Fast route under the sentinel: must reach it, or the switch is a no-op.
  .kar_with("kp_read_trace_fast", boom, {
    expect_error(.kar_attest(sc, "fast"), "FAST-CONSULTED")
  })
})

test_that("A-3 identity: both routes hand back identical() receipt bundles
           over real certified batch bytes", {
  sc <- .kar_scenario()
  a <- .kar_attest(sc, "reference")
  b <- .kar_attest(sc, "fast")
  expect_identical(b, a)
  # Guard against comparing two NULLs: the payload must be real.
  expect_true(is.matrix(a$W) && is.matrix(a$H) && is.finite(a$objective[1L]))
})

test_that("A-4 unknown routes are fail-closed and named", {
  sc <- .kar_scenario()
  # The pattern is the post-green fault law verbatim; the pre-green
  # "unused argument" error must NOT satisfy it (vacuous-red guard).
  expect_error(.kar_attest(sc, "both"), "expected 'fast' or 'reference'")
  expect_error(.kar_attest(sc, "fast-or-reference"),
               "expected 'fast' or 'reference'")
})

test_that("A-5 the fast route keeps the fail-closed receipt law: a mutated
           W grid still faults, naming the file", {
  sc <- .kar_scenario()
  w.path <- file.path(sc$case.out, "W.csv")
  original <- readLines(w.path, warn = FALSE)
  on.exit(writeLines(original, con = w.path), add = TRUE)
  # Drop one column's worth of tokens from row 1: the shape law must fire.
  first <- strsplit(original[[1L]], ",", fixed = TRUE)[[1L]]
  writeLines(c(paste(first[-1L], collapse = ","), original[-1L]),
             con = w.path)
  expect_error(.kar_attest(sc, "fast"), "W.csv")
  # Same bytes through the reference route: the same law, the same fault.
  expect_error(.kar_attest(sc, "reference"), "W.csv")
})
