# run_sparse_spec_witness.R -- the CS-12 sparse-spec-witness scenario
# (pillar 3).
#
# Mandate: plant scalar engine-spec arguments (the D3 law: hand-picked
# rationals only -- zero COSMIC numeric matrices, zero real-data bytes, zero
# downloads, zero data objects) and adjudicate the EXPORTED factory
# ms_sparse() under six arms: the degenerate-default headline (the
# documented default variant fails its own validator while the certified
# variant accepts), the variant enum and the validator's loop-before-law
# precedence, the symmetric penalty ladder, the integer ladders at max_iter
# and the seed window, the volume-carries-mu / delta-sentinel argument-face
# gaps, and the typed property gates. Every arm is driven through the
# EXPORTED factory alone -- the accepted echoes, the abort classes and the
# fired bullets are the factory's own; the internal validator is never
# reached directly and no hand-rolled re-validation is invoked here. The
# whole scenario is RNG-free and network-free: the plant is closed-form
# scalar arguments and there is no seed to pin; the R-bound benchmark runner,
# the FFI shim and the declined calibration family are DECLINED scope and are
# never invoked here.
#
# Framing law: DECISION RECORD only. What this scenario records is the
# shipped factory's documented contract behavior on planted truth: the
# accepted property echoes, the observed abort classes, the fired clause
# bullets, the measured precedence -- an OBSERVED, COMMITTED fact, never an
# extraction, benchmark or convergence claim. Float posture: the committed
# witnesses byte-freeze integers and labels (property echoes as their fixed
# format() renderings, class labels and clause keys as observed bytes); no
# ill-conditioned float rendering is ever committed. The plant checksum
# re-hashes through BOTH governed SHA-256 kernels -- the canonical pure-R one
# and the digest accelerator -- so a silent byte-rot in what was measured
# reddens the run. The witness bytes under out/ are the verdict; a
# byte-rerun must reproduce them identically.

.script_dir <- local({
  a <- grep("^--file=(.*)$", commandArgs(FALSE), perl = TRUE, value = TRUE)
  if (length(a) == 0L) return(getwd())
  f <- sub("^--file=", "", a[1L])
  if (!grepl("/", f, fixed = TRUE)) return(getwd())
  dirname(f)
})
ROOT <- normalizePath(file.path(.script_dir, "..", ".."), mustWork = TRUE)
OUT <- file.path(ROOT, "bench", "scenarios", "out")

if (requireNamespace("pkgload", quietly = TRUE) &&
    file.exists(file.path(ROOT, "DESCRIPTION"))) {
  suppressWarnings(suppressMessages(
    pkgload::load_all(ROOT, quiet = TRUE, export_all = TRUE)))
} else {
  library(msuiter)
}

# -- frozen scenario constants (mirrored byte-identically in the law test) --
CLASS_OBJ <- "msuiter::MsSparse"
CLASS_ENGINE <- "msuiter_error_engine"
CLASS_GATE <- "simpleError"

CLAUSE_L1 <- paste0("the l1 variant requires mu > 0 ",
                    "(mu = 0 degenerates the exposure scale)")
CLAUSE_VARIANT <- paste0('`variant` must be "volume" or "l1"')
CLAUSE_MAXITER <- paste0("`max_iter` must be a single positive ",
                         "whole number")
CLAUSE_SEED <- paste0("`seed` must be a single whole number in ",
                      "[0, 2^31 - 1]")
GATE_PREFIX <- "object properties are invalid"
ge0 <- function(nm) paste0("`", nm, "` must be a single finite ",
                          "number >= 0")

SPECS <- list(
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

law <- function(args, cls, clause) list(args = args, cls = cls, clause = clause)
LAWS <- list(
  `default-noargs`         = law(list(), CLASS_ENGINE, CLAUSE_L1),
  `l1-default-mu0`         = law(list(variant = "l1"), CLASS_ENGINE, CLAUSE_L1),
  `l1-mu-zero`             = law(list(variant = "l1", mu = 0), CLASS_ENGINE,
                                  CLAUSE_L1),
  `variant-elastic`        = law(list(variant = "elastic"), CLASS_ENGINE,
                                  CLAUSE_VARIANT),
  `prec-l1-mu-neg`         = law(list(variant = "l1", mu = -1), CLASS_ENGINE,
                                  ge0("mu")),
  `lambda-neg`             = law(list(variant = "volume", lambda = -1),
                                  CLASS_ENGINE, ge0("lambda")),
  `lambda-nan`             = law(list(variant = "volume", lambda = NaN),
                                  CLASS_ENGINE, ge0("lambda")),
  `lambda-inf`             = law(list(variant = "volume", lambda = Inf),
                                  CLASS_ENGINE, ge0("lambda")),
  `mu-neg`                 = law(list(variant = "volume", mu = -1),
                                  CLASS_ENGINE, ge0("mu")),
  `mu-nan`                 = law(list(variant = "volume", mu = NaN),
                                  CLASS_ENGINE, ge0("mu")),
  `mu-inf`                 = law(list(variant = "volume", mu = Inf),
                                  CLASS_ENGINE, ge0("mu")),
  `delta-neg`              = law(list(variant = "volume", delta = -1),
                                  CLASS_ENGINE, ge0("delta")),
  `delta-nan`              = law(list(variant = "volume", delta = NaN),
                                  CLASS_ENGINE, ge0("delta")),
  `delta-inf`              = law(list(variant = "volume", delta = Inf),
                                  CLASS_ENGINE, ge0("delta")),
  `tol-neg`                = law(list(variant = "volume", tol = -1),
                                  CLASS_ENGINE, ge0("tol")),
  `tol-nan`                = law(list(variant = "volume", tol = NaN),
                                  CLASS_ENGINE, ge0("tol")),
  `tol-inf`                = law(list(variant = "volume", tol = Inf),
                                  CLASS_ENGINE, ge0("tol")),
  `tol-na-real`            = law(list(variant = "volume", tol = NA_real_),
                                  CLASS_ENGINE, ge0("tol")),
  `maxiter-0`              = law(list(variant = "volume", max_iter = 0),
                                  CLASS_ENGINE, CLAUSE_MAXITER),
  `maxiter-half`           = law(list(variant = "volume", max_iter = 0.5),
                                  CLASS_ENGINE, CLAUSE_MAXITER),
  `seed-neg`               = law(list(variant = "volume", seed = -1),
                                  CLASS_ENGINE, CLAUSE_SEED),
  `seed-max-plus`          = law(list(variant = "volume", seed = 2^31),
                                  CLASS_ENGINE, CLAUSE_SEED),
  `seed-half`              = law(list(variant = "volume", seed = 1.5),
                                  CLASS_ENGINE, CLAUSE_SEED),
  `seed-inf`               = law(list(variant = "volume", seed = Inf),
                                  CLASS_ENGINE, CLAUSE_SEED),
  `tol-na`                 = law(list(variant = "volume", tol = NA), CLASS_GATE,
                                  paste0("@tol must be <integer> or <double>, ",
                                          "not <logical>")),
  `variant-numeric-typed`  = law(list(variant = 1), CLASS_GATE,
                                  paste0("@variant must be <character>, ",
                                          "not <double>")),
  `lambda-character-typed`  = law(list(variant = "volume", lambda = "a"),
                                  CLASS_GATE,
                                  paste0("@lambda must be <integer> or <double>, ",
                                          "not <character>")))

PREC <- list(
  `volume-mu-neg` = list(args = list(variant = "volume", mu = -1),
                          fired = "generic-ge0", clause = ge0("mu")),
  `l1-mu-neg`    = list(args = list(variant = "l1", mu = -1),
                          fired = "generic-ge0", clause = ge0("mu")),
  `l1-mu-zero`   = list(args = list(variant = "l1", mu = 0),
                          fired = "l1-mu-law", clause = CLAUSE_L1))

SEED_HI <- 2147483647
SEED_REJECT <- 2147483648

plant_text <- paste0(vapply(names(SPECS), function(nm) {
  paste0(nm, "|", paste0(SPECS[[nm]]$echo, collapse = "|"))
}, character(1L)), collapse = ";")

# -- adjudication machinery --------------------------------------------------
n_rails <- 0L
n_fail <- 0L
.check <- function(label, cond) {
  n_rails <<- n_rails + 1L
  if (isTRUE(cond)) {
    cat("  ok   ", label, "\n", sep = "")
  } else {
    n_fail <<- n_fail + 1L
    cat("  FAIL ", label, "\n", sep = "")
  }
  invisible(isTRUE(cond))
}

ask <- function(args) tryCatch(do.call("ms_sparse", args), error = function(e) e)
echo_of <- function(o) c(as.character(o@variant), format(o@lambda),
                         format(o@mu), format(o@delta), format(o@tol),
                         format(o@max_iter), format(o@seed))
msg_of <- function(e) gsub("\n", " ", paste(conditionMessage(e)))

# Pre-write payload census (witness-finiteness law): every committed cell a
# non-empty, NA-free, delimiter-free single line; no field opens a quote.
.census <- function(dat, sep) {
  if (length(dat) == 0L || nrow(dat) == 0L) return(FALSE)
  for (col in dat) {
    if (!is.character(col)) return(FALSE)
    if (any(is.na(col)) || !all(nzchar(col))) return(FALSE)
    if (any(grepl(sep, col, fixed = TRUE))) return(FALSE)
    if (any(grepl("\n", col, fixed = TRUE))) return(FALSE)
    if (any(substr(col, 1L, 1L) == "\"")) return(FALSE)
  }
  TRUE
}
.writetab <- function(fname, dat, sep) {
  write.table(dat, file = file.path(OUT, fname), row.names = FALSE,
              col.names = TRUE, quote = FALSE, sep = sep)
}

dir.create(OUT, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. the headline quirk, the certified face, and the purity rails
# ---------------------------------------------------------------------------
cat("== cs12 sparse-spec-witness: headline quirk and purity rails ==\n")
rng_before <- exists(".Random.seed", inherits = TRUE)
.check("RNG untouched before the plant (no seed to pin)", !rng_before)

e_default <- ask(list())
default_abort <- inherits(e_default, "error") &&
  identical(paste0(class(e_default)[1L]), CLASS_ENGINE) &&
  grepl(CLAUSE_L1, msg_of(e_default), fixed = TRUE)
.check("headline: the documented default aborts on the l1 clause",
       default_abort)

o_cert <- ask(SPECS[["volume-certified"]]$args)
cert_ok <- !inherits(o_cert, "error") &&
  identical(paste0(class(o_cert)[1L]), CLASS_OBJ) &&
  identical(echo_of(o_cert), SPECS[["volume-certified"]]$echo)
.check("certified: the volume variant accepts and echoes its contract",
       cert_ok)

gap <- ask(SPECS[["volume-mu-gap"]]$args)
gap_ok <- !inherits(gap, "error") && identical(format(gap@mu), "0.5")
.check("argument gap: the certified variant accepts-and-echoes a mu the\n\
         kernel-side posture never consults -- an OBSERVED acceptance",
       gap_ok)

sent <- ask(SPECS[["volume-delta-sentinel"]]$args)
sent_ok <- !inherits(sent, "error") && identical(format(sent@delta), "0")
.check("sentinel: delta = 0 is accepted and echoed as the committed sentinel",
       sent_ok)

# ---------------------------------------------------------------------------
# 2. the ten accepted arms: live echoes byte-match the frozen table
# ---------------------------------------------------------------------------
cat("== cs12 sparse-spec-witness: accepted arms ==\n")
spec_rows <- lapply(names(SPECS), function(nm) {
  o <- ask(SPECS[[nm]]$args)
  ok <- !inherits(o, "error") &&
    identical(paste0(class(o)[1L]), CLASS_OBJ) &&
    identical(echo_of(o), SPECS[[nm]]$echo)
  .check(paste0("accept + echo byte-exact: ", nm), ok)
  as.list(c(SPECS[[nm]]$echo, CLASS_OBJ))
})
names(spec_rows) <- NULL
specs_dat <- data.frame(
  arm = names(SPECS),
  variant = vapply(spec_rows, function(r) r[[1L]], character(1L)),
  lambda  = vapply(spec_rows, function(r) r[[2L]], character(1L)),
  mu      = vapply(spec_rows, function(r) r[[3L]], character(1L)),
  delta   = vapply(spec_rows, function(r) r[[4L]], character(1L)),
  tol     = vapply(spec_rows, function(r) r[[5L]], character(1L)),
  max_iter = vapply(spec_rows, function(r) r[[6L]], character(1L)),
  seed    = vapply(spec_rows, function(r) r[[7L]], character(1L)),
  cls     = vapply(spec_rows, function(r) r[[8L]], character(1L)),
  stringsAsFactors = FALSE)
.check("specs payload census (non-empty, NA-free, delimiter-free cells)",
       .census(specs_dat, ","))

# ---------------------------------------------------------------------------
# 3. the twenty-seven rejected arms: observed classes and fired clauses
# ---------------------------------------------------------------------------
cat("== cs12 sparse-spec-witness: rejected arms ==\n")
law_rows <- lapply(names(LAWS), function(nm) {
  l <- LAWS[[nm]]
  e <- ask(l$args)
  spoke <- inherits(e, "error") &&
    identical(paste0(class(e)[1L]), l$cls) &&
    grepl(l$clause, msg_of(e), fixed = TRUE) &&
    (l$cls != CLASS_GATE || grepl(GATE_PREFIX, msg_of(e), fixed = TRUE))
  .check(paste0("reject speaks committed class + clause: ", nm), spoke)
  list(arm = nm, cls = paste0(class(e)[1L]), clause = l$clause)
})
laws_dat <- data.frame(
  arm    = vapply(law_rows, function(r) r$arm, character(1L)),
  cls    = vapply(law_rows, function(r) r$cls, character(1L)),
  clause = vapply(law_rows, function(r) r$clause, character(1L)),
  stringsAsFactors = FALSE)
n_engine <- sum(laws_dat$cls == CLASS_ENGINE)
n_gate <- sum(laws_dat$cls == CLASS_GATE)
.check("class split as measured: 24 validator rejects + 3 typed-gate rejects",
       n_engine == 24L && n_gate == 3L)
.check("laws payload census", .census(laws_dat, "\t"))

# ---------------------------------------------------------------------------
# 4. the precedence witness: loop-before-law, discriminated both ways
# ---------------------------------------------------------------------------
cat("== cs12 sparse-spec-witness: precedence ==\n")
prec_rows <- lapply(names(PREC), function(nm) {
  p <- PREC[[nm]]
  e <- ask(p$args)
  msg <- if (inherits(e, "error")) msg_of(e) else ""
  other <- if (identical(p$fired, "generic-ge0")) CLAUSE_L1 else ge0("mu")
  fired_ok <- inherits(e, "error") &&
    identical(paste0(class(e)[1L]), CLASS_ENGINE) &&
    grepl(p$clause, msg, fixed = TRUE) &&
    !grepl(other, msg, fixed = TRUE)
  .check(paste0("fires ONLY its own bullet (", p$fired, "): ", nm), fired_ok)
  list(arm = nm, variant = as.character(p$args$variant),
       mu = format(p$args$mu), fired = p$fired, clause = p$clause)
})
prec_dat <- data.frame(
  arm     = vapply(prec_rows, function(r) r$arm, character(1L)),
  variant = vapply(prec_rows, function(r) r$variant, character(1L)),
  mu      = vapply(prec_rows, function(r) r$mu, character(1L)),
  fired   = vapply(prec_rows, function(r) r$fired, character(1L)),
  clause  = vapply(prec_rows, function(r) r$clause, character(1L)),
  stringsAsFactors = FALSE)
.check("precedence payload census", .census(prec_dat, ","))

# ---------------------------------------------------------------------------
# 5. the degenerates ledger and the closing purity rail
# ---------------------------------------------------------------------------
cat("== cs12 sparse-spec-witness: degenerates ==\n")
rng_after <- exists(".Random.seed", inherits = TRUE)
.check("RNG untouched after the whole plant (purity rail, both ends)",
       !rng_before && !rng_after)
deg <- data.frame(
  name = c("default_noargs_abort", "default_noargs_class",
           "default_noargs_clause", "volume_certified_ok", "certified_class",
           "volume_mu_gap_ok", "volume_mu_gap_echo", "delta_sentinel_ok",
           "delta_sentinel_echo", "precedence_generic_wins",
           "precedence_l1_law_alive", "typed_variant_gate", "typed_lambda_gate",
           "tol_na_gate", "tol_na_real_engine", "rng_before", "rng_after"),
  value = c("1", CLASS_ENGINE, CLAUSE_L1, "1", CLASS_OBJ, "1", "0.5", "1",
            "0", "1", "1", "1", "1", "1", "1", "FALSE", "FALSE"),
  stringsAsFactors = FALSE)
.check("degenerates payload census", .census(deg, "\t"))

# ---------------------------------------------------------------------------
# 6. the scalars ledger with the dual-kernel plant checksum
# ---------------------------------------------------------------------------
cat("== cs12 sparse-spec-witness: scalars + dual-kernel checksum ==\n")
bytes <- charToRaw(plant_text)
h_canonical <- .ms_fit_sha256(bytes)
have_accel <- requireNamespace("digest", quietly = TRUE)
h_accel <- if (have_accel) {
  asNamespace("digest")$digest(bytes, algo = "sha256", serialize = FALSE)
} else {
  NA_character_
}
.check("the digest accelerator (where installed) agrees with the canonical kernel",
       identical(h_canonical, h_accel) || !have_accel)
.check("the plant checksum is a 64-hex scalar",
       is.character(h_canonical) && nchar(h_canonical) == 64L &&
         length(grep("^[0-9a-f]{64}$", h_canonical, perl = TRUE)) == 1L)
.check("the seed window boundaries are the measured pair",
       identical(SEED_HI, 2^31 - 1) && identical(SEED_REJECT, SEED_HI + 1))
scal <- data.frame(
  key = c("scenario_shape", "face", "default_variant", "certified_variant",
          "default_tol", "default_max_iter", "default_seed", "seed_hi",
          "seed_reject", "accept_count", "reject_count", "engine_count",
          "gate_count", "precedence_rows", "plant_checksum"),
  value = c("cs12-sparse-spec-witness", "ms_sparse", "l1", "volume",
            "1e-07", "2000", "1", "2147483647", "2147483648", "10", "27",
            "24", "3", "3", h_canonical),
  stringsAsFactors = FALSE)
.check("scalars payload census", .census(scal, ","))

# ---------------------------------------------------------------------------
# 7. [attest] -- declined scope rails, made audible
# ---------------------------------------------------------------------------
cat("[attest] DECISION RECORD only: the factory's contract behavior on planted\n")
cat("[attest]   truth is an OBSERVED, COMMITTED record -- no extraction claim,\n")
cat("[attest]   no benchmark claim, no convergence claim of any kind.\n")
cat("[attest] NETWORK: never attempted -- the plant is closed-form scalar\n")
cat("[attest]   arguments; no download face, no live registry, no external\n")
cat("[attest]   byte is read.\n")
cat("[attest] D3 law: hand-picked scalar rationals only; zero COSMIC numeric\n")
cat("[attest]   matrices, zero real-data bytes, zero data objects.\n")
cat("[attest] RNG-free executed path: measured at both ends; no seed to pin,\n")
cat("[attest]   no draw to re-roll.\n")
cat("[attest] FACE-only adjudication: the echoes, the abort classes and the\n")
cat("[attest]   fired bullets are the exported factory's own; the internal\n")
cat("[attest]   validator is never reached and no hand-rolled re-validation\n")
cat("[attest]   is invoked. The R-bound benchmark runner, the FFI shim and\n")
cat("[attest]   the DECLINED calibration estimators are never invoked here.\n")
cat("[attest]   The plant-checksum rail reaches the two governed SHA-256\n")
cat("[attest]   kernels by name (infrastructure equality, adjudication-\n")
cat("[attest]   independent).\n")
cat("[attest] D11 posture: the witnesses byte-freeze integer and label verdicts\n")
cat("[attest]   (property echoes as fixed format() renderings, observed class\n")
cat("[attest]   labels and clause keys); no ill-conditioned float rendering is\n")
cat("[attest]   committed.\n")

# -- commit the witnesses (all censuses spoke first) -------------------------
ok_payload <- all(.census(specs_dat, ","), .census(laws_dat, "\t"),
                  .census(prec_dat, ","), .census(deg, "\t"),
                  .census(scal, ","))
if (!ok_payload) {
  cat("OVERALL FAIL -- payload census refused a witness write\n")
  quit(status = 1L)
}
.writetab("cs12_specs.csv", specs_dat, ",")
.writetab("cs12_laws.tsv", laws_dat, "\t")
.writetab("cs12_precedence.csv", prec_dat, ",")
.writetab("cs12_degenerates.tsv", deg, "\t")
.writetab("cs12_scalars.csv", scal, ",")

cat("\n", if (identical(n_fail, 0L)) "OVERALL PASS" else "OVERALL FAIL",
    " (", n_rails, " adjudications, ", n_fail, " failed)\n", sep = "")
quit(status = if (identical(n_fail, 0L)) 0L else 1L)
