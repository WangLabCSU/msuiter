# test-scenario-sparse-spec-witness.R -- the CS-12 sparse-spec-witness law
# units (pillar 3). The scenario plants scalar engine-spec arguments and
# adjudicates the EXPORTED factory ms_sparse() under six arms: the
# degenerate-default headline (the documented l1 default fails its own
# validator while the volume variant is the certified default -- the
# in-house benchmark driver's own concession), the variant enum and the
# validator's loop-before-law precedence, the symmetric penalty ladder, the
# integer ladders at max_iter and the [0, 2^31 - 1] seed window, the
# volume-carries-mu / delta-sentinel argument-face gaps, and the S7 typed
# gates. The witness bytes under bench/scenarios/out/ (cs12_specs.csv,
# cs12_laws.tsv, cs12_precedence.csv, cs12_scalars.csv,
# cs12_degenerates.tsv) are the committed verdict: a drift in the validator
# clauses, the observed error classes, the echoes or the precedence order
# reddens here before print. The plant is scalar rationals -- no RNG, no
# network, no data objects, no COSMIC bytes; the lane NEVER calls the
# benchmark runner (RNG-bound), the FFI (.ms_sparse_rust) or any face of the
# declined calibration family (banned words, grepped).
# Framing law: DECISION RECORD only. What the factory says on planted truth
# -- the accepted echoes, the abort classes, the fired bullets -- is an
# OBSERVED, COMMITTED record, never an extraction, benchmark or convergence
# claim. The error classes (msuiter_error_engine vs the S7 simpleError gate)
# and the object class label ("msuiter::MsSparse") are committed as OBSERVED
# bytes, never re-typed design claims. The pillar-2 idiom of reaching the
# package namespace directly (msuiter:::) is BANNED here and grepped away.

.rs_out12 <- function(fname) {
  file.path(.ms_root, "bench", "scenarios", "out", fname)
}

# The committed tables are written quote-free; quote = "" keeps the double
# quotes inside the variant clause (and every other byte) literal on read.
.rs_csv12 <- function(fname) {
  read.csv(.rs_out12(fname), header = TRUE, stringsAsFactors = FALSE,
           na.strings = "", colClasses = "character", quote = "")
}

.rs_tsv12 <- function(fname) {
  read.csv(.rs_out12(fname), header = TRUE, sep = "\t",
           stringsAsFactors = FALSE, na.strings = "", colClasses = "character",
           quote = "")
}

# ---------------------------------------------------------------------------
# Frozen constants -- mirrored byte-identically in
# bench/scenarios/run_sparse_spec_witness.R (single source of truth).
# Every value MEASURED through the exported face (probes cs12-probe1/2,
# EXIT-0); none derived.

.CS12_CLASS_OBJ <- "msuiter::MsSparse"          # observed class(o)[1] print
.CS12_CLASS_ENGINE <- "msuiter_error_engine"    # observed validator class
.CS12_CLASS_GATE <- "simpleError"                # observed S7 property gate

.CS12_CLAUSE_L1 <- paste0("the l1 variant requires mu > 0 ",
                          "(mu = 0 degenerates the exposure scale)")
.CS12_CLAUSE_VARIANT <- paste0('`variant` must be "volume" or "l1"')
.CS12_CLAUSE_MAXITER <- paste0("`max_iter` must be a single positive ",
                               "whole number")
.CS12_CLAUSE_SEED <- paste0("`seed` must be a single whole number in ",
                            "[0, 2^31 - 1]")
.CS12_GATE_PREFIX <- "object properties are invalid"
.cs12_ge0 <- function(nm) paste0("`", nm, "` must be a single finite ",
                                 "number >= 0")

# The ten accepted arms: the explicit call arguments and the MEASURED echo
# bytes of all seven properties (format() rendering as printed by the probe).
.CS12_SPECS <- list(
  `volume-certified`        = list(args = list(variant = "volume"),
    echo = c("volume", "0", "0", "0", "1e-07", "2000", "1")),
  `l1-with-mu`              = list(args = list(variant = "l1", mu = 0.5),
    echo = c("l1", "0", "0.5", "0", "1e-07", "2000", "1")),
  `volume-mu-gap`           = list(args = list(variant = "volume", mu = 0.5),
    echo = c("volume", "0", "0.5", "0", "1e-07", "2000", "1")),
  `volume-delta-sentinel`   = list(args = list(variant = "volume", delta = 0),
    echo = c("volume", "0", "0", "0", "1e-07", "2000", "1")),
  `volume-delta-val`        = list(args = list(variant = "volume", delta = 0.5),
    echo = c("volume", "0", "0", "0.5", "1e-07", "2000", "1")),
  `lambda-zero`             = list(args = list(variant = "volume", lambda = 0),
    echo = c("volume", "0", "0", "0", "1e-07", "2000", "1")),
  `l1-mu-rational`          = list(args = list(variant = "l1", mu = 0.25),
    echo = c("l1", "0", "0.25", "0", "1e-07", "2000", "1")),
  `maxiter-1`               = list(args = list(variant = "volume", max_iter = 1),
    echo = c("volume", "0", "0", "0", "1e-07", "1", "1")),
  `seed-0`                  = list(args = list(variant = "volume", seed = 0),
    echo = c("volume", "0", "0", "0", "1e-07", "2000", "0")),
  `seed-max-ok`             = list(args = list(variant = "volume",
                                               seed = 2^31 - 1),
    echo = c("volume", "0", "0", "0", "1e-07", "2000", "2147483647")))

# The twenty-seven rejected arms: the call, the OBSERVED first class token
# and the committed key clause (verbatim; the cli bullet glyph is condition
# rendering, not part of the committed bytes). Twenty-four validator rejects
# and the three S7 typed-gate rejects (measured classes: simpleError).
.cs12_law <- function(args, cls, clause) list(args = args, cls = cls,
                                              clause = clause)
.CS12_LAWS <- list(
  `default-noargs`        = .cs12_law(list(), .CS12_CLASS_ENGINE, .CS12_CLAUSE_L1),
  `l1-default-mu0`        = .cs12_law(list(variant = "l1"), .CS12_CLASS_ENGINE,
                                       .CS12_CLAUSE_L1),
  `l1-mu-zero`            = .cs12_law(list(variant = "l1", mu = 0),
                                       .CS12_CLASS_ENGINE, .CS12_CLAUSE_L1),
  `variant-elastic`       = .cs12_law(list(variant = "elastic"), .CS12_CLASS_ENGINE,
                                       .CS12_CLAUSE_VARIANT),
  `prec-l1-mu-neg`        = .cs12_law(list(variant = "l1", mu = -1), .CS12_CLASS_ENGINE,
                                       .cs12_ge0("mu")),
  `lambda-neg`            = .cs12_law(list(variant = "volume", lambda = -1),
                                       .CS12_CLASS_ENGINE, .cs12_ge0("lambda")),
  `lambda-nan`            = .cs12_law(list(variant = "volume", lambda = NaN),
                                       .CS12_CLASS_ENGINE, .cs12_ge0("lambda")),
  `lambda-inf`            = .cs12_law(list(variant = "volume", lambda = Inf),
                                       .CS12_CLASS_ENGINE, .cs12_ge0("lambda")),
  `mu-neg`                = .cs12_law(list(variant = "volume", mu = -1),
                                       .CS12_CLASS_ENGINE, .cs12_ge0("mu")),
  `mu-nan`                = .cs12_law(list(variant = "volume", mu = NaN),
                                       .CS12_CLASS_ENGINE, .cs12_ge0("mu")),
  `mu-inf`                = .cs12_law(list(variant = "volume", mu = Inf),
                                       .CS12_CLASS_ENGINE, .cs12_ge0("mu")),
  `delta-neg`             = .cs12_law(list(variant = "volume", delta = -1),
                                       .CS12_CLASS_ENGINE, .cs12_ge0("delta")),
  `delta-nan`             = .cs12_law(list(variant = "volume", delta = NaN),
                                       .CS12_CLASS_ENGINE, .cs12_ge0("delta")),
  `delta-inf`             = .cs12_law(list(variant = "volume", delta = Inf),
                                       .CS12_CLASS_ENGINE, .cs12_ge0("delta")),
  `tol-neg`               = .cs12_law(list(variant = "volume", tol = -1),
                                       .CS12_CLASS_ENGINE, .cs12_ge0("tol")),
  `tol-nan`               = .cs12_law(list(variant = "volume", tol = NaN),
                                       .CS12_CLASS_ENGINE, .cs12_ge0("tol")),
  `tol-inf`               = .cs12_law(list(variant = "volume", tol = Inf),
                                       .CS12_CLASS_ENGINE, .cs12_ge0("tol")),
  `tol-na-real`           = .cs12_law(list(variant = "volume", tol = NA_real_),
                                       .CS12_CLASS_ENGINE, .cs12_ge0("tol")),
  `maxiter-0`             = .cs12_law(list(variant = "volume", max_iter = 0),
                                       .CS12_CLASS_ENGINE, .CS12_CLAUSE_MAXITER),
  `maxiter-half`          = .cs12_law(list(variant = "volume", max_iter = 0.5),
                                       .CS12_CLASS_ENGINE, .CS12_CLAUSE_MAXITER),
  `seed-neg`              = .cs12_law(list(variant = "volume", seed = -1),
                                       .CS12_CLASS_ENGINE, .CS12_CLAUSE_SEED),
  `seed-max-plus`         = .cs12_law(list(variant = "volume", seed = 2^31),
                                       .CS12_CLASS_ENGINE, .CS12_CLAUSE_SEED),
  `seed-half`             = .cs12_law(list(variant = "volume", seed = 1.5),
                                       .CS12_CLASS_ENGINE, .CS12_CLAUSE_SEED),
  `seed-inf`              = .cs12_law(list(variant = "volume", seed = Inf),
                                       .CS12_CLASS_ENGINE, .CS12_CLAUSE_SEED),
  `tol-na`                = .cs12_law(list(variant = "volume", tol = NA),
                                       .CS12_CLASS_GATE,
                                       paste0("@tol must be <integer> or <double>, ",
                                              "not <logical>")),
  `variant-numeric-typed` = .cs12_law(list(variant = 1), .CS12_CLASS_GATE,
                                       paste0("@variant must be <character>, ",
                                              "not <double>")),
  `lambda-character-typed` = .cs12_law(list(variant = "volume", lambda = "a"),
                                        .CS12_CLASS_GATE,
                                        paste0("@lambda must be <integer> or <double>, ",
                                               "not <character>")))

# The precedence witness: when BOTH the generic >=0 bullet and the l1-mu
# law are triggered (l1, mu = -1), the generic bullet FIRES (loop-before-law
# order). The mu = 0 probe proves the l1 bullet is alive and sits after the
# loop (the generic bullet passes 0; the l1 law then fires).
.CS12_PREC <- list(
  `volume-mu-neg` = list(args = list(variant = "volume", mu = -1),
                         fired = "generic-ge0", clause = .cs12_ge0("mu")),
  `l1-mu-neg`    = list(args = list(variant = "l1", mu = -1),
                         fired = "generic-ge0", clause = .cs12_ge0("mu")),
  `l1-mu-zero`   = list(args = list(variant = "l1", mu = 0),
                         fired = "l1-mu-law", clause = .CS12_CLAUSE_L1))

# Seed window boundaries as MEASURED (2^31 renders 2147483648).
.CS12_SEED_HI <- 2147483647
.CS12_SEED_REJECT <- 2147483648

# The plant checksum text: the ten accepted arms as frozen echo rows, joined.
.cs12_plant <- function() {
  paste0(vapply(names(.CS12_SPECS), function(nm) {
    paste0(nm, "|", paste0(.CS12_SPECS[[nm]]$echo, collapse = "|"))
  }, character(1L)), collapse = ";")
}

.cs12_call <- function(args) {
  tryCatch(do.call("ms_sparse", args), error = function(e) e)
}

# ---------------------------------------------------------------------------
test_that("the CS-12 runner speaks the committed scenario shape", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  f <- file.path(.ms_root, "bench", "scenarios", "run_sparse_spec_witness.R")
  expect_true(file.exists(f))
  src <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_true(grepl("--file=", src, fixed = TRUE))
  expect_true(grepl("quit(", src, fixed = TRUE))
  expect_true(grepl("OVERALL PASS", src, fixed = TRUE))
  expect_true(grepl("[attest]", src, fixed = TRUE))
  expect_true(grepl("ms_sparse", src, fixed = TRUE))
  expect_true(grepl("DECISION RECORD", src, fixed = TRUE))
  expect_true(grepl("cs12_", src, fixed = TRUE))
  # Hand-engine ban: the verdicts come from the FACTORY, never a re-validated
  # mirror -- the runner must not reach the internal validator directly.
  expect_false(grepl("msuiter_validate_sparse", src, fixed = TRUE))
  expect_false(grepl("expect_", src, fixed = TRUE))
  # The declined/impure family must never ride the runner.
  expect_false(grepl("ms_calibration_grid", src, fixed = TRUE))
  expect_false(grepl("ms_fit_bootstrap", src, fixed = TRUE))
  expect_false(grepl("ms_calibration_sanity", src, fixed = TRUE))
  expect_false(grepl("ms_run_benchmark", src, fixed = TRUE))
  expect_false(grepl(".ms_sparse_rust", src, fixed = TRUE))
  # No JSON face here -- the runner must not lean on a JSON dependency.
  expect_false(grepl("jsonlite", src, fixed = TRUE))
  # The network and the seed are spoken for by absence.
  expect_false(grepl("download.file", src, fixed = TRUE))
  expect_false(grepl("url(", src, fixed = TRUE))
  expect_false(grepl("set.seed", src, fixed = TRUE))
  expect_false(grepl("Sys.time", src, fixed = TRUE))
  # Rail spoken by absence: the pillar-2 namespace-reach idiom is banned.
  expect_false(grepl("msuiter:::", src, fixed = TRUE))
})

test_that("the plant tables are self-consistent before the face is asked", {
  expect_length(.CS12_SPECS, 10L)
  expect_length(.CS12_LAWS, 27L)
  expect_length(.CS12_PREC, 3L)
  for (nm in names(.CS12_SPECS)) {
    spec <- .CS12_SPECS[[nm]]
    expect_length(spec$echo, 7L)
    expect_true(all(nzchar(spec$echo)))
    expect_true(is.list(spec$args) && all(nzchar(names(spec$args))))
  }
  cls <- vapply(.CS12_LAWS, function(l) l$cls, character(1L))
  expect_equal(sum(cls == .CS12_CLASS_ENGINE), 24L)
  expect_equal(sum(cls == .CS12_CLASS_GATE), 3L)
  expect_true(all(vapply(.CS12_LAWS, function(l) nzchar(l$clause),
                         logical(1L))))
  # No arm is in two tables at once.
  expect_length(intersect(names(.CS12_SPECS), names(.CS12_LAWS)), 0L)
  # The precedence discriminator: the two bullets are DISTINCT clauses.
  expect_false(identical(.CS12_CLAUSE_L1, .cs12_ge0("mu")))
  fired <- vapply(.CS12_PREC, function(p) p$fired, character(1L))
  expect_equal(sum(fired == "generic-ge0"), 2L)
  expect_equal(sum(fired == "l1-mu-law"), 1L)
  # The seed window is exactly the measured half-open-closed face.
  expect_equal(.CS12_SEED_HI, 2^31 - 1)
  expect_equal(.CS12_SEED_REJECT, .CS12_SEED_HI + 1)
  expect_true(.CS12_SEED_HI %% 1 == 0 && is.finite(.CS12_SEED_HI))
  # Every spec arg is a scalar the factory can take.
  for (nm in names(.CS12_SPECS)) {
    for (a in .CS12_SPECS[[nm]]$args) {
      expect_length(a, 1L)
      expect_true(is.character(a) || (is.numeric(a) && is.finite(a)))
    }
  }
})

test_that("the five committed witnesses exist with live rows", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  for (f in c("cs12_specs.csv", "cs12_laws.tsv", "cs12_precedence.csv",
               "cs12_scalars.csv", "cs12_degenerates.tsv")) {
    expect_true(file.exists(.rs_out12(f)), label = paste0("witness exists: ", f))
    expect_gt(file.info(.rs_out12(f))$size, 0L, label = paste0("witness non-empty: ", f))
  }
  s <- .rs_csv12("cs12_specs.csv")
  expect_equal(nrow(s), 10L)
  expect_true(all(c("arm", "variant", "lambda", "mu", "delta", "tol",
                     "max_iter", "seed", "cls") %in% names(s)))
  l <- .rs_tsv12("cs12_laws.tsv")
  expect_equal(nrow(l), 27L)
  expect_true(all(c("arm", "cls", "clause") %in% names(l)))
  p <- .rs_csv12("cs12_precedence.csv")
  expect_equal(nrow(p), 3L)
  expect_true(all(c("arm", "variant", "mu", "fired", "clause") %in% names(p)))
  k <- .rs_csv12("cs12_scalars.csv")
  expect_true(all(c("key", "value") %in% names(k)))
  d <- .rs_tsv12("cs12_degenerates.tsv")
  expect_true(all(c("name", "value") %in% names(d)))
})

test_that("the specs witness byte-matches the frozen echoes", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  s <- .rs_csv12("cs12_specs.csv")
  expect_equal(as.character(s$arm), names(.CS12_SPECS))
  for (i in seq_along(names(.CS12_SPECS))) {
    nm <- names(.CS12_SPECS)[i]
    row <- s[i, , drop = FALSE]
    cols <- c("variant", "lambda", "mu", "delta", "tol", "max_iter", "seed")
    expect_equal(as.character(unlist(row[, cols], use.names = FALSE)),
                 .CS12_SPECS[[nm]]$echo,
                 label = paste0("spec echoes byte-exact: ", nm))
    expect_equal(as.character(row$cls), .CS12_CLASS_OBJ,
                 label = paste0("spec class label observed: ", nm))
  }
})

test_that("the accepted arms re-derive live through the factory", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  s <- .rs_csv12("cs12_specs.csv")
  props <- c("variant", "lambda", "mu", "delta", "tol", "max_iter", "seed")
  for (i in seq_along(names(.CS12_SPECS))) {
    nm <- names(.CS12_SPECS)[i]
    o <- .cs12_call(.CS12_SPECS[[nm]]$args)
    expect_false(inherits(o, "error"), label = paste0("accept: ", nm))
    live <- c(as.character(o@variant), format(o@lambda), format(o@mu),
              format(o@delta), format(o@tol), format(o@max_iter),
              format(o@seed))
    expect_equal(live, .CS12_SPECS[[nm]]$echo, label = paste0("live echoes: ", nm))
    expect_equal(live, as.character(unlist(s[i, props], use.names = FALSE)),
                 label = paste0("witness echoes: ", nm))
    expect_equal(paste0(class(o)[1L]), .CS12_CLASS_OBJ,
                 label = paste0("live class label: ", nm))
  }
})

test_that("the rejected arms fire the committed classes and clauses", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  l <- .rs_tsv12("cs12_laws.tsv")
  expect_equal(as.character(l$arm), names(.CS12_LAWS))
  for (nm in names(.CS12_LAWS)) {
    law <- .CS12_LAWS[[nm]]
    e <- .cs12_call(law$args)
    expect_true(inherits(e, "error"), label = paste0("rejects: ", nm))
    expect_equal(paste0(class(e)[1L]), law$cls, label = paste0("class: ", nm))
    msg <- gsub("\n", " ", paste(conditionMessage(e)))
    expect_true(grepl(law$clause, msg, fixed = TRUE),
                 label = paste0(nm, " speaks the committed clause"))
    if (law$cls == .CS12_CLASS_GATE) {
      expect_true(grepl(.CS12_GATE_PREFIX, msg, fixed = TRUE),
                  label = paste0(nm, " rides the S7 property gate"))
    }
  }
  # The committed witness rows carry the same classes as the frozen table.
  expect_equal(as.character(l$cls),
               unname(vapply(.CS12_LAWS, function(x) x$cls, character(1L))))
})

test_that("the precedence witness proves loop-before-law both directions", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  p <- .rs_csv12("cs12_precedence.csv")
  expect_equal(as.character(p$arm), names(.CS12_PREC))
  expect_equal(as.character(p$fired),
               unname(vapply(.CS12_PREC, function(x) x$fired, character(1L))))
  for (nm in names(.CS12_PREC)) {
    row <- p[as.character(p$arm) == nm, , drop = FALSE]
    e <- .cs12_call(.CS12_PREC[[nm]]$args)
    expect_true(inherits(e, "error"), label = paste0("prec rejects: ", nm))
    expect_equal(paste0(class(e)[1L]), .CS12_CLASS_ENGINE,
                 label = paste0("prec class: ", nm))
    msg <- gsub("\n", " ", paste(conditionMessage(e)))
    expect_true(grepl(.CS12_PREC[[nm]]$clause, msg, fixed = TRUE),
                 label = paste0(nm, " fires the committed bullet"))
    expect_true(grepl(.CS12_PREC[[nm]]$clause,
                      as.character(row$clause[1L]), fixed = TRUE),
                label = paste0(nm, " witness row agrees"))
    # The discriminator: a generic-ge0 firing must NOT speak the l1 clause,
    # and the l1-law firing must NOT speak the generic bullet.
    other <- if (identical(as.character(row$fired[1L]), "generic-ge0"))
      .CS12_CLAUSE_L1 else .cs12_ge0("mu")
    expect_false(grepl(other, msg, fixed = TRUE),
                 label = paste0(nm, " fires ONLY its own bullet"))
  }
})

test_that("the degenerates witness pins the headline quirk and the purity rails", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  d <- .rs_tsv12("cs12_degenerates.tsv")
  dv <- setNames(as.character(d$value), as.character(d$name))
  # The headline: the documented default aborts on the l1 clause; the
  # certified variant accepts and echoes.
  expect_equal(dv[["default_noargs_abort"]], "1")
  expect_equal(dv[["default_noargs_class"]], .CS12_CLASS_ENGINE)
  expect_equal(dv[["default_noargs_clause"]], .CS12_CLAUSE_L1)
  expect_equal(dv[["volume_certified_ok"]], "1")
  expect_equal(dv[["certified_class"]], .CS12_CLASS_OBJ)
  # The argument-face gaps ride accepted.
  expect_equal(dv[["volume_mu_gap_ok"]], "1")
  expect_equal(dv[["volume_mu_gap_echo"]], "0.5")
  expect_equal(dv[["delta_sentinel_ok"]], "1")
  expect_equal(dv[["delta_sentinel_echo"]], "0")
  # The precedence and the typed gates.
  expect_equal(dv[["precedence_generic_wins"]], "1")
  expect_equal(dv[["precedence_l1_law_alive"]], "1")
  expect_equal(dv[["typed_variant_gate"]], "1")
  expect_equal(dv[["typed_lambda_gate"]], "1")
  expect_equal(dv[["tol_na_gate"]], "1")
  expect_equal(dv[["tol_na_real_engine"]], "1")
  # The purity rails as committed by the runner's own process.
  expect_equal(dv[["rng_before"]], "FALSE")
  expect_equal(dv[["rng_after"]], "FALSE")
})

test_that("the scalars witness pins the frozen constants and the plant checksum", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  k <- .rs_csv12("cs12_scalars.csv")
  kv <- setNames(as.character(k$value), as.character(k$key))
  expect_equal(kv[["scenario_shape"]], "cs12-sparse-spec-witness")
  expect_equal(kv[["face"]], "ms_sparse")
  expect_equal(kv[["default_variant"]], "l1")     # observed: noargs aborts on l1 clause
  expect_equal(kv[["certified_variant"]], "volume")
  expect_equal(kv[["default_tol"]], "1e-07")
  expect_equal(kv[["default_max_iter"]], "2000")
  expect_equal(kv[["default_seed"]], "1")
  expect_equal(kv[["seed_hi"]], "2147483647")
  expect_equal(kv[["seed_reject"]], "2147483648")
  expect_equal(kv[["accept_count"]], "10")
  expect_equal(kv[["reject_count"]], "27")
  expect_equal(kv[["engine_count"]], "24")
  expect_equal(kv[["gate_count"]], "3")
  expect_equal(kv[["precedence_rows"]], "3")
  # The plant checksum rides over the frozen echo rows -- dual-kernel proof
  # lives in the runner; here it re-derives from the SAME frozen text.
  expect_equal(kv[["plant_checksum"]],
               digest::digest(charToRaw(.cs12_plant()), algo = "sha256",
                              serialize = FALSE))
})

test_that("the double-gate law separates NA-logical from NA-real on the tol face", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  # NA (logical) is caught by the S7 property gate; NA_real_ passes the gate
  # and dies on the validator's finite bullet. Observed, committed, distinct.
  e_logical <- .cs12_call(list(variant = "volume", tol = NA))
  e_real <- .cs12_call(list(variant = "volume", tol = NA_real_))
  expect_true(inherits(e_logical, "error") && inherits(e_real, "error"))
  expect_equal(paste0(class(e_logical)[1L]), .CS12_CLASS_GATE)
  expect_equal(paste0(class(e_real)[1L]), .CS12_CLASS_ENGINE)
  expect_false(identical(paste0(class(e_logical)[1L]),
                         paste0(class(e_real)[1L])))
  msg_logical <- gsub("\n", " ", paste(conditionMessage(e_logical)))
  expect_true(grepl(.CS12_GATE_PREFIX, msg_logical, fixed = TRUE))
  expect_true(grepl("@tol must be <integer> or <double>, not <logical>",
                     msg_logical, fixed = TRUE))
  msg_real <- gsub("\n", " ", paste(conditionMessage(e_real)))
  expect_true(grepl(.cs12_ge0("tol"), msg_real, fixed = TRUE))
})
