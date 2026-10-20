#!/usr/bin/env Rscript
# GO-05 campaign harness — the single launcher for the bootstrap-vs-sigminer
# measurement (U-M7-04 GO-05 SCOPE B; protocol:
# docs/devlog/2026-10-10-m7-bootstrap-campaign.md). The harness MEASURES and
# RECORDS; every decision (tier, floor gate, anchor gates, reader verdict) is
# adjudicated by bench/m7/tools/verify_campaign.py — one source of laws, so
# the writing side and the reading side can never drift apart.
#
# Usage:
#   Rscript --vanilla run_campaign.R -- --outdir DIR --mode full
#   Rscript --vanilla run_campaign.R -- --outdir /tmp/... --mode pilot --smoke
#   Rscript --vanilla run_campaign.R -- --outdir /tmp/... --mode full --anchor-probe
#     (GO-05: the RB-10-safe anchor-gate calibration at the full shape table.
#      It runs data bytes, census and the anchor stage only -- no probes, no
#      tier, no timed arms -- and its ledger entry is a non-shot calibration
#      record, so the single authoritative full shot stays unspent.)
# The frozen campaign profile (M7_HW_PROFILE) must be exported verbatim; the
# harness refuses otherwise (hardware-pin law, same shape as the docker
# authority gate). Heavy arms are single authoritative shots (RB-10): a second
# full launch into an adjudicated dir is refused by the ledger law, never
# silently rerun.
suppressWarnings(RNGkind("Mersenne-Twister", normal.kind = "Inversion",
  sample.kind = "Rejection"))

SEED <- 20260928L            # G0 master seed — frozen, zero runtime touch
CAMPAIGN_HW_PIN <- paste0(
  "host-R campaign | Apple Silicon | 10 cores | ",
  "hw.ncpu=10 hw.memsize=25769803776 | R 4.5.2")
MEASUREMENT_IMAGE_TOKENS <- c("msuiter-sigminer", "m7-sigprofiler",
  "sigminer/", "sigprofiler/", "signalgym")   # docker-ps census veto list
N_THREADS_POOL <- 10L

args <- commandArgs(TRUE)
flag <- function(name, required = TRUE, default = NA_character_) {
  i <- match(name, args)
  if (is.na(i)) {
    if (required) stop("missing required --", name, " argument")
    return(default)
  }
  args[[i + 1L]]
}
outdir <- flag("--outdir")
mode <- flag("--mode")                            # full | pilot
smoke <- !is.na(match("--smoke", args))            # valueless switch
anchorProbe <- !is.na(match("--anchor-probe", args))  # valueless switch (GO-05)
tierProbe <- !is.na(match("--tier-probe", args))      # valueless switch (GO-05)
tierOverride <- flag("--tier", required = FALSE)
capArg <- flag("--cap", required = FALSE)
stopifnot(mode %in% c("full", "pilot"))
if (smoke) stopifnot(mode == "pilot")

# -- shape table (frozen by protocol §2; smoke is a rehearsal, never a claim) --
if (smoke) {
  K <- 80L; S <- 12L; N_SIG <- 8L
  S_PROBE <- 4L; R_PROBE <- c(4L, 8L); R_FULL <- 24L
  S_ANCHOR <- 4L; R_ANCHOR <- 20L
} else {
  K <- 1000L; S <- 1000L; N_SIG <- 50L
  S_PROBE <- 5L; R_PROBE <- c(10L, 20L); R_ANCHOR <- 200L
  S_ANCHOR <- 25L
}

# system2 status normalizer: file-capture runs report NULL or an integer
# exit code depending on the call shape; both spellings of zero are success.
ok_rc <- function(st) is.null(st) ||
  (length(st) == 1L && identical(as.integer(st), 0L))
say <- function(...) cat(paste0(...), "\n", sep = "")
abort <- function(...) {
  cat("[campaign] HALT: ", paste0(...), "\n", sep = "")
  quit(status = 2L)
}

# The probe calibrates the anchor gate AT the authoritative shape, so it must
# ride the full table: --mode full, never --smoke (smoke numbers would say
# nothing about the shot it exists to protect).
if (anchorProbe && (smoke || mode != "full")) abort(
  "--anchor-probe rides the full shape table: pair --mode full only, ",
  "never --smoke or --mode pilot")

# The tier-probe rehearses the decision path (census, sealed data, probes,
# decide) at the authoritative shape, so it rides the same law: --mode full,
# never --smoke (smoke probe bytes would rehearse nothing the shot depends on).
if (tierProbe && (smoke || mode != "full")) abort(
  "--tier-probe rides the full shape table: pair --mode full only, ",
  "never --smoke or --mode pilot")

# -- the oracle (single source of laws) --------------------------------------
dashes <- commandArgs(trailing = FALSE)
self <- grep("^--file=", dashes, value = TRUE)
stopifnot(length(self) == 1L)
HERE <- dirname(sub("^--file=([^ ]+).*", "\\1", self[1L]))
ORACLE <- normalizePath(file.path(HERE, "..", "m7", "tools",
  "verify_campaign.py"))
GEN <- normalizePath(file.path(HERE, "gen_campaign.R"))
EMITTER <- normalizePath(file.path(HERE, "emit_campaign_table.py"))
stopifnot(all(file.exists(c(ORACLE, GEN, EMITTER))))
call_oracle_rc <- function(extra) {
  # M7_HW_PROFILE rides by inheritance: the harness has already attested it
  # equals the pinned string, and system2(env=) would interpolate the pin's
  # pipes through the shell unquoted (witnessed live-failure; never again).
  tf <- tempfile("oracle")
  st <- system2("python3", c(ORACLE, "--campaign", outdir, extra),
    stdout = tf, stderr = tf)
  txt <- if (file.exists(tf)) readLines(tf, warn = FALSE) else character(0)
  list(rc = if (ok_rc(st)) 0L else as.integer(st),
    text = paste(txt, collapse = "\n"))
}
oj <- function(text, key) {                   # tiny fixed-schema scalar pull
  # Capture goes through gregexpr: regmatches on this host is (x, m, invert)
  # and returns matched text only -- it has no capture groups and no perl
  # argument (the perl = TRUE shape died live in smoke rehearsal with
  # "unused argument"). No-match renders as -1 here, witnessed by probe.
  pat <- sprintf('"%s": *"?([A-Za-z0-9._+-]*)"?', key)
  mm <- gregexpr(pat, text, perl = TRUE)[[1L]]
  if (is.na(mm[[1L]]) || mm[[1L]] < 0L) return(NA_character_)
  cs <- attr(mm, "capture.start"); cl <- attr(mm, "capture.length")
  if (is.null(cs) || length(cs) < 1L || is.na(cs[[1L]])) return(NA_character_)
  substring(text, cs[[1L]], cs[[1L]] + cl[[1L]] - 1L)
}

# -- environment attestation ---------------------------------------------------
profile <- Sys.getenv("M7_HW_PROFILE")
if (!identical(profile, CAMPAIGN_HW_PIN)) abort(
  "M7_HW_PROFILE must equal the pinned campaign string verbatim (got: '",
  profile, "'); the hardware-pin law binds this lane as it binds the docker ",
  "authority pass")
if (!grepl("^R version 4\\.5\\.", R.version$version.string)) abort(
  "the campaign attests R 4.5.x (the pin's tail); found ",
  R.version$version.string)

if (smoke && dir.exists(outdir) && length(list.files(outdir, all.files = TRUE))) abort(
  "--smoke needs a fresh/empty outdir (rehearsals never inherit bytes)")
if (anchorProbe && dir.exists(outdir) && length(list.files(outdir, all.files = TRUE))) abort(
  "--anchor-probe needs a fresh/empty outdir (calibrations never inherit bytes)")
if (tierProbe && dir.exists(outdir) && length(list.files(outdir, all.files = TRUE))) abort(
  "--tier-probe needs a fresh/empty outdir (rehearsals never inherit bytes)")
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
wit <- file.path(outdir, "witnesses")
dir.create(wit, showWarnings = FALSE)
utc <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S", tz = "UTC")
host_name <- function() {
  hn <- try(system2("hostname", stdout = TRUE, stderr = FALSE), silent = TRUE)
  if (is.character(hn) && length(hn)) trimws(hn[[1L]]) else "unknown-host"
}

# writeLines carries NO append argument: handing it one is an
# unused-argument hard error (witnessed live when the first smoke rehearsal
# died at the ledger write after a clean census pass). Every appending write
# therefore goes through an append-mode connection.
append_line <- function(path, lines) {
  con <- file(path, open = "a")
  on.exit(close(con))
  writeLines(lines, con)
}

# -- census gate (protocol §3): no live measurement container -------------------
# Status arrives via the file-capture form ONLY: system2(stdout=TRUE) reports
# a failed command as a warning plus empty text, which would let a broken
# census pass vacuously (witnessed live; never again).
census_tf <- tempfile("census")
cst <- system2("docker", c("ps", "--format",
  shQuote("{{.Names}} {{.Image}}", type = "sh")),
  stdout = census_tf, stderr = census_tf)
if (!ok_rc(cst)) abort("docker ps census failed (status ", as.integer(cst),
  ") — the co-tenancy gate cannot attest")
ps <- if (file.exists(census_tf)) readLines(census_tf, warn = FALSE) else character(0)
# The token census tests every token explicitly: this host's grepl/regexpr
# only vectorize the text side (witnessed twice — a vector pattern silently
# degrades to its first element, which would under-flag sigprofiler rows).
is_measurement <- function(line) {
  for (tok in MEASUREMENT_IMAGE_TOKENS)
    if (grepl(tok, line, fixed = TRUE)) return(TRUE)
  FALSE
}
live <- ps[unlist(lapply(ps, is_measurement))]
if (length(live)) abort("live measurement container(s) present — the campaign ",
  "launch is refused while the matrix domain is busy: ",
  paste(live, collapse = "; "))
writeLines(sprintf('{"kind":"census","ts":"%s","live_measurement":[],"ps":[%s]}',
  utc(), paste(sprintf('"%s"', gsub('"', "'", ps)), collapse = ",")),
  file.path(wit, "host_census.jsonl"))
say("[campaign] census OK (", length(ps), " container line(s), none measurement)")

# -- launch ledger ---------------------------------------------------------------
append_ledger <- function(mode_name) append_line(
  file.path(outdir, "campaign_launches.jsonl"),
  sprintf('{"kind":"launch","mode":"%s","ts":"%s"}', mode_name, utc()))
# The probe's ledger entry: deliberately NO mode key -- the reader's shot
# counter counts e["mode"] == "full" only, so this entry is invisible to the
# single-full-shot law (pinned by tests/test_anchor_probe.py) while still
# recording that a calibration pass ran here.
append_probe_ledger <- function() append_line(
  file.path(outdir, "campaign_launches.jsonl"),
  sprintf('{"kind":"anchor-probe","grade":"calibration","ts":"%s"}', utc()))
# The tier-probe's ledger entry: the same non-shot discipline -- a calibration
# record with NO mode key, invisible to the reader's shot counter (pinned by
# tests/test_tier_probe.py) while recording that the decision path was
# rehearsed here against the frozen shape.
append_tier_probe_ledger <- function() append_line(
  file.path(outdir, "campaign_launches.jsonl"),
  sprintf('{"kind":"tier-probe","grade":"calibration","ts":"%s"}', utc()))
if (!anchorProbe) {
  gate <- call_oracle_rc(c("--launch-gate", "--mode", "pilot"))
  if (gate$rc != 0L) abort("launch-gate refused (rc ", gate$rc, "): ", gate$text)
  # A tier rehearsal is calibration, not a launch: like the anchor probe it
  # writes its own no-mode ledger entry and never touches the shot ledger.
  if (!tierProbe) append_ledger(if (smoke) "pilot" else "probe")
}
arms_present <- all(file.exists(file.path(wit,
  sprintf("arm_%s.jsonl", c("A1", "A2", "A3")))))
if (mode == "full" && !smoke && arms_present) abort(
  "arm witnesses already present — this campaign dir is adjudicated; ",
  "single authoritative shot (RB-10)")

# -- data bytes (frozen generator, sealed) ---------------------------------------
if (!file.exists(file.path(outdir, "campaign.rds"))) {
  gen_tf <- tempfile("gen")
  gst <- system2("Rscript", c("--vanilla", GEN, "--", "--out", outdir,
    "--k", K, "--s", S, "--sig", N_SIG, "--seed", SEED),
    stdout = gen_tf, stderr = gen_tf)
  if (!ok_rc(gst)) abort("generator failed (status ", as.integer(gst),
    "): ", paste(readLines(gen_tf, warn = FALSE), collapse = " | "))
}
d <- readRDS(file.path(outdir, "campaign.rds"))
counts <- d$counts; sigs <- d$signatures
stopifnot(identical(dim(counts), c(K, S)))
samples <- d$samples; labels <- d$labels
probe_samples <- head(samples, S_PROBE)
anchor_samples <- head(samples, S_ANCHOR)

suppressMessages({library(sigminer); library(msuiter)})

build_catalog <- function(mat, smp) msuiter::ms_catalog(counts = mat,
  channels = list(name = "cam", labels = labels), samples = smp,
  provenance = list(genome = "hg38-synthetic-go05"))
# Catalog construction is harness glue on the msuiter side — built outside the
# timed regions and disclosed in result.md (the timed object is the documented
# entry point called with its arguments, symmetric to the R side).

# -- measurement primitives --------------------------------------------------------
loadavg <- function() {
  out <- try(system2("/usr/sbin/sysctl", c("-n", "vm.loadavg"),
    stdout = TRUE, stderr = FALSE), silent = TRUE)
  if (!is.character(out) || !length(out)) return(rep(NA_real_, 3L))
  # This host's sysctl wraps the triple in braces ({ 3.98 3.86 3.81 }) —
  # strip non-numeric decoration before splitting (witnessed live: the
  # naive split made the first token '{', turning the first load element
  # into NA: lb=NA,3.80,3.79).
  txt <- gsub("[^0-9.,[:space:]]", "", out[[1L]])
  tok <- strsplit(txt, "[[:space:],]+")[[1L]]
  tok <- tok[nzchar(tok)]
  v <- suppressWarnings(as.numeric(tok))
  v <- v[!is.na(v)]
  if (length(v) < 3L) return(rep(NA_real_, 3L))
  head(v, 3L)
}

# A witness must stay json.loads-able: sprintf('%.3g', NA) would write a
# bare NA inside a JSON array. Load vectors render through this helper.
json_load3 <- function(v) {
  stopifnot(length(v) == 3L)
  s <- character(3L)
  for (i in seq_len(3L))
    s[i] <- if (is.na(v[i])) 'null' else sprintf('%.3g', v[i])
  paste0('[', paste(s, collapse = ','), ']')
}
timed <- function(expr) {
  invisible(gc(verbose = FALSE)); invisible(gc(verbose = FALSE))
  # proc.time() on the target interpreter carries the RAW rusage names
  # (witnessed: user.self / sys.self / elapsed / user.child / sys.child;
  # the translated print headers are print-method localisation, names() is
  # the authority). One coherent snapshot per observation point.
  c0 <- proc.time(); w0 <- c0[["elapsed"]]
  v <- force(expr)
  c1 <- proc.time()
  list(value = v, wall = c1[["elapsed"]] - w0,
    cpu = (c1[["user.self"]] - c0[["user.self"]]) +
          (c1[["sys.self"]] - c0[["sys.self"]]),
    load_before = loadavg(), load_after = loadavg())
}
arm_call <- function(arm, counts_sub, cat_sub, reps, threads = N_THREADS_POOL) {
  if (arm == "A1") {
    # Package-documented contract (sigminer roxygen usage, verbatim:
    #   sig_fit_bootstrap_batch(V, sig = W, n = 10)): sig is not a formal --
    # it reaches sig_fit through the dots, where sig_fit discovers it by
    # match.call() stack introspection (sig_fit.R:185). Omitting it while
    # sig_index stays NULL is a witnessed death, not a style choice:
    # send_error("'sig' cannot be found...") + send_stop("Exit.") at
    # sig_fit.R:186-187 -- observed live when a repair pass stripped this
    # actual, with the error surfacing only as an empty-message condition.
    # The batch is also forbidden from any worker knob here: use_parallel
    # stays FALSE and job_id NULL (no result-dir writes).
    suppressWarnings(suppressMessages(sigminer::sig_fit_bootstrap_batch(
      counts_sub, sig = sigs, methods = "NNLS", n = reps,
      use_parallel = FALSE, seed = SEED, job_id = NULL)))
  } else {
    suppressMessages(msuiter::ms_fit_bootstrap(cat_sub, sigs,
      method = "nnls", n_boot = reps, seed = SEED, n_threads = threads))
  }
}

# -- probes: measure, never adjudicate (witnesses carry no verdict fields) ---------
probe_once <- function(arm, reps, threads) {
  sub <- counts[, probe_samples, drop = FALSE]
  cs <- if (arm == "A1") NULL else build_catalog(sub, probe_samples)
  invisible(arm_call(arm, sub, cs, reps, threads))          # warmup, untimed
  for (rep in seq_len(3L)) {
    t <- timed(arm_call(arm, sub, cs, reps, threads))
    append_line(file.path(wit, sprintf("probe_%s_1.jsonl", arm)),
      sprintf(paste0('{',
        '"kind":"probe","arm":"%s","shape":{"S":%d,"R":%d},',
        '"wall":%.9g,"cpu":%.9g,"rep":%d,"loadavg":%s}'),
        arm, length(probe_samples), reps, t$wall, t$cpu, rep,
        json_load3(t$load_after)))
    cat(".")
  }
}
# -- correctness anchor (share-normalized, protocol §5 + addendum) --------------------
qcell <- function(x) stats::quantile(x, c(.025, .5, .975), names = FALSE)
write_anchor <- function(path, recs) writeLines(vapply(seq_len(nrow(recs)),
  function(i) sprintf(paste0('{', '"sample":"%s","sig":"%s",',
    '"lo":%.12g,"hi":%.12g,"median":%.12g}'),
    recs$sample[i], recs$sig[i], recs$lo[i], recs$hi[i], recs$median[i]),
    character(1L), USE.NAMES = FALSE), path)
anchor_a1 <- function() {
  set.seed(SEED, kind = "Mersenne-Twister", normal.kind = "Inversion",
    sample.kind = "Rejection")
  rows <- lapply(anchor_samples, function(sm) {
    o <- suppressWarnings(suppressMessages(sigminer::sig_fit_bootstrap(
      counts[, sm, drop = TRUE], sig = sigs, n = R_ANCHOR,
      method = "NNLS")))
    e <- o$expo                                  # signatures x replicates
    q <- vapply(seq_len(nrow(e)), function(i) qcell(as.numeric(e[i, ])),
      numeric(3L), USE.NAMES = FALSE)             # 3 x signatures
    scale <- if (sum(q[2L, ]) > 0) sum(q[2L, ]) else 1
    data.frame(sample = sm, sig = rownames(e), lo = q[1L, ] / scale,
      hi = q[3L, ] / scale, median = q[2L, ] / scale)
  })
  do.call(rbind, rows)
}
anchor_a2 <- function() {
  sub <- counts[, anchor_samples, drop = FALSE]
  f <- suppressMessages(msuiter::ms_fit_bootstrap(
    build_catalog(sub, anchor_samples), sigs, method = "nnls",
    n_boot = R_ANCHOR, seed = SEED, n_threads = N_THREADS_POOL,
    return_draws = TRUE))
  dr <- attr(f@exposures, "boot_draws")          # signatures x samples x boot
  rows <- lapply(anchor_samples, function(sm) {
    d <- dr[, sm, , drop = FALSE]
    dim(d) <- c(N_SIG, R_ANCHOR)
    q <- vapply(seq_len(N_SIG), function(i) qcell(as.numeric(d[i, ])),
      numeric(3L), USE.NAMES = FALSE)            # 3 x signatures
    scale <- if (sum(q[2L, ]) > 0) sum(q[2L, ]) else 1
    data.frame(sample = sm, sig = colnames(sigs), lo = q[1L, ] / scale,
      hi = q[3L, ] / scale, median = q[2L, ] / scale)
  })
  do.call(rbind, rows)
}

# -- anchor-probe mode (GO-05): the RB-10-safe calibration lens -------------------------
# The probe-grade result.md: it names the shape and the oracle verbatim and
# speaks no verdict, no tier, no ratio -- a file the reader can only read as
# non-claiming (pinned both ways by tests/test_anchor_probe.py).
write_probe_result <- function(anch_text) {
  seal <- paste(readLines(file.path(outdir, "seal.json"), warn = FALSE),
    collapse = " ")
  writeLines(c(
    "# bootstrap-vs-sigminer campaign — anchor-probe (not a claim)", "",
    "- grade: anchor-probe — the anchor gate observed at the full shape;",
    "  no probes, no tier, no timed arms ran in this dir, and no RB-10 shot",
    "  was consumed: it supports no measurement of any kind",
    sprintf("- shape: K=%d S=%d n_sig=%d | anchor: S_ANCHOR=%d R_ANCHOR=%d",
      K, S, N_SIG, S_ANCHOR, R_ANCHOR),
    "- anchor witnesses: witnesses/anchor_A1.jsonl witnesses/anchor_A2.jsonl",
    paste0("- anchor oracle (verbatim): ", anch_text),
    paste0("- seed: ", SEED, " (G0 master) | data seal: ", seal),
    paste0("- host: ", host_name(), "  R: ", R.version.string,
      "  hw_profile: ", CAMPAIGN_HW_PIN),
    "- co-tenancy census: witnesses/host_census.jsonl (verbatim docker ps)"),
    con = file.path(outdir, "result.md"))
}

# Every law above this point (attestation, census, generator+seal, anchor
# defs) is shared with the authoritative path; everything below it is left
# unrun. The reader pass adjudicates the probe dir; the run exits zero so a
# red anchor gate stays REPORTABLE (it is information, not a harness fault).
if (anchorProbe) {
  append_probe_ledger()
  say("[campaign] ANCHOR-PROBE (full shape K=", K, " S=", S, " n_sig=", N_SIG,
    "; anchor gate observation only — the RB-10 shot stays unspent)")
  write_anchor(file.path(wit, "anchor_A1.jsonl"), anchor_a1())
  write_anchor(file.path(wit, "anchor_A2.jsonl"), anchor_a2())
  anch <- call_oracle_rc("--anchor-check")
  say("[campaign] anchor oracle rc=", anch$rc, " ", anch$text)
  write_probe_result(anch$text)
  rc <- call_oracle_rc(character(0))
  say("[campaign] reader verifier rc=", rc$rc, " ", rc$text)
  if (rc$rc != 0L) quit(status = 1L)
  say("[campaign] PROBE-COMPLETE outdir=", outdir,
    " anchor-ok=", identical(anch$rc, 0L))
  quit(status = 0L)
}

say("[campaign] probes (S=", S_PROBE, ", R=", paste(R_PROBE, collapse = "/"),
  ", warmup + 3 timed; medians adjudicated by the oracle):")
for (arm in c("A1", "A2", "A3")) for (rp in R_PROBE) probe_once(arm, rp,
  threads = if (arm == "A3") 1L else N_THREADS_POOL)
say("\n[campaign] probes done")

# -- tier decision (oracle-only) -----------------------------------------------------
dec <- call_oracle_rc(c("--decide",
  if (!is.na(capArg)) c("--cap", capArg) else NULL))
if (dec$rc != 0L) abort("tier oracle failed (rc ", dec$rc, "): ", dec$text)
tier <- oj(dec$text, "tier")
if (!is.na(tierOverride)) tier <- tierOverride
writeLines(dec$text, file.path(wit, "tier_decision.json"))
say("[campaign] tier decision: ", tier)

# -- tier-probe mode (GO-05): the decision-path rehearsal, zero claim bytes -------------
# Tonight's halt was the safety system working: the tier oracle refused, and
# the shot stayed unspent. This rehearsal rides the exact death path --
# census, sealed generator bytes, probes, decide -- at the FULL frozen shape,
# then quits before any timed arm, before the full-shot ledger gate, and
# before a single claim-bearing artifact. The probe-grade result.md names the
# shape and the decide oracle VERBATIM and speaks no verdict, no ratio, no
# tier of its own -- a file the reader can only read as non-claiming (pinned
# both ways by tests/test_tier_probe.py). The reader pass adjudicates the
# rehearsal dir; the exit is zero whatever the oracle reports about the
# probe fits, because a report is information, not a harness fault.
write_tier_result <- function(dec_text) {
  seal <- paste(readLines(file.path(outdir, "seal.json"), warn = FALSE),
    collapse = " ")
  writeLines(c(
    "# bootstrap-vs-sigminer campaign — tier-probe (not a claim)", "",
    "- grade: tier-probe — the decision path rehearsed at the full shape;",
    "  the probe witnesses are real measurements at the frozen probe shape,",
    "  but no timed arm ran here, no floor gate was adjudicated, and no",
    "  RB-10 shot was consumed: this dir supports no measurement of any kind",
    sprintf("- shape: K=%d S=%d n_sig=%d | probe: S_PROBE=%d R_PROBE=%s",
      K, S, N_SIG, S_PROBE, paste(R_PROBE, collapse = "/")),
    "- probe witnesses: witnesses/probe_A1_*.jsonl (the consumed leg) and the",
    "  report-only A2/A3 legs, adjudicated by the oracle line below",
    paste0("- decide oracle (verbatim): ", dec_text),
    paste0("- seed: ", SEED, " (G0 master) | data seal: ", seal),
    paste0("- host: ", host_name(), "  R: ", R.version.string,
      "  hw_profile: ", CAMPAIGN_HW_PIN),
    "- co-tenancy census: witnesses/host_census.jsonl (verbatim docker ps)"),
    con = file.path(outdir, "result.md"))
}
if (tierProbe) {
  append_tier_probe_ledger()
  say("[campaign] TIER-PROBE (full shape K=", K, " S=", S, " n_sig=", N_SIG,
    "; decision-path observation only — the RB-10 shot stays unspent)")
  write_tier_result(dec$text)
  rv <- call_oracle_rc(character(0))
  say("[campaign] reader verifier rc=", rv$rc, " ", rv$text)
  if (rv$rc != 0L) quit(status = 1L)
  say("[campaign] TIER-PROBE-COMPLETE outdir=", outdir,
    " tier=", tier, " decision-ok=", identical(dec$rc, 0L))
  quit(status = 0L)
}

result_md <- file.path(outdir, "result.md")
write_result <- function(verdict, tier, ratio_line = NULL, extra = character(0)) {
  seal <- paste(readLines(file.path(outdir, "seal.json"), warn = FALSE),
    collapse = " ")
  writeLines(c(
    "# bootstrap-vs-sigminer campaign — result", "",
    sprintf("- tier: %s", tier),
    if (!is.null(ratio_line)) sprintf("- ratio(A1/A2) = %.12e", ratio_line),
    sprintf("- verdict: %s", verdict), "",
    "## Disclosure",
    paste0("- seed: ", SEED, " (G0 master; the arms carry it into their own ",
      "RNG regimes; RNG-stream equality is NOT claimed — data bytes carry ",
      "identity)"),
    paste0("- shape: K=", K, " S=", S, " n_sig=", N_SIG),
    "- heavy arms: single authoritative timed shot each (RB-10); repeatability ",
    "  evidence lives in the probe witnesses (warmup + 3 timed, median)",
    "- msuiter catalog construction happens outside the timed regions ",
    "  (harness glue); both arms are timed on their documented entry point",
    paste0("- host: ", host_name(), "  R: ", R.version.string,
      "  hw_profile: ", CAMPAIGN_HW_PIN),
    paste0("- data seal: ", seal),
    "- co-tenancy census: witnesses/host_census.jsonl (verbatim docker ps)",
    if (smoke) paste0("- SMOKE REHEARSAL: small shapes, disposable numbers; ",
      "this dir supports no measurement claim"),
    extra), con = result_md)   # writeLines is (text, con, sep, useBytes) -- no file=
}

if (identical(tier, "C")) {
  write_result(paste0("UNMEASURED-with-pilot (Tier-C: the budget cap breaches ",
    "at every tier — the number is not manufactured)"), tier = tier,
    extra = "- see witnesses/tier_decision.json and the probe_* witnesses")
  rc <- call_oracle_rc(character(0))
  say("[campaign] reader verifier rc=", rc$rc, " ", rc$text)
  if (rc$rc != 0L) quit(status = 1L)
  say("[campaign] CAMPAIGN-COMPLETE outdir=", outdir,
    " tier=", tier, " verdict=UNMEASURED-with-pilot")
  quit(status = 0L)
}

reps_taken <- if (identical(tier, "A")) 1000L else 200L
if (smoke) reps_taken <- R_FULL

# -- full shot: ledger-gated, single authoritative pass ------------------------------
if (!smoke) {
  g2 <- call_oracle_rc(c("--launch-gate", "--mode", "full"))
  if (g2$rc != 0L) abort("full shot refused by the ledger (rc ", g2$rc,
    "): ", g2$text)
  append_ledger("full")
}
say("[campaign] full arms (R=", reps_taken, "):")

# -- the UNMEASURABLE floor leg (controller ruling @12:50, laws (1)-(2)) --------------
# A probe fit that is usable bytes yet provably non-identifiable at the probe
# scale cannot ground the pre-registered 3x floor: the same sealed data gave
# A2's rate opposite signs across two same-seed observations. The leg is
# neither pass nor breach -- it records. The only numbers it owns are the
# ones actually timed; floor_projection/floor_ratio are null, because there
# is no number and none is invented here.
write_unmeasurable_gate <- function(arm, tier, K, S, N_SIG, reps, t, reason) {
  writeLines(sprintf(paste0('{', '"kind":"arm","arm":"%s","tier":"%s",',
    '"shape":{"K":%d,"S":%d,"n_sig":%d,"R":%d},',
    '"wall":%.9g,"cpu":%.9g,"load_before":%s,',
    '"load_after":%s,',
    '"floor_projection":null,"floor_ratio":null,',
    '"gate":"UNMEASURED(probe-fit non-identifiable)","gate_reason":"%s"}'),
    arm, tier, K, S, N_SIG, reps, t$wall, t$cpu,
    json_load3(t$load_before), json_load3(t$load_after), reason),
    file.path(wit, sprintf("arm_%s.jsonl", arm)))
}
unmeasured <- c()                     # arms whose floor leg the oracle declared UNMEASURABLE
fits <- list()
cs_full <- NULL                       # built once, shared by the pool arms
for (arm in c("A1", "A2", "A3")) {
  threads <- if (arm == "A3") 1L else N_THREADS_POOL
  if (arm != "A1" && is.null(cs_full)) cs_full <- build_catalog(counts, samples)
  say("  [", arm, "] ...")
  t <- timed(arm_call(arm, counts, cs_full, reps_taken, threads))
  fc <- call_oracle_rc(c("--floor-check", "--arm", arm,
    "--observed", sprintf("%.9g", t$wall), "--reps", reps_taken))
  if (!fc$rc %in% c(0L, 3L, 4L)) abort("floor oracle failed (rc ", fc$rc, "): ",
    fc$text)
  if (fc$rc == 3L) {
    # Ruling @12:50: an UNMEASURABLE floor leg the oracle has declared -- the
    # probe fit is provably non-identifiable at the probe scale, so any 3x
    # floor built on it would be a coin flip. The gate loses its say on this
    # arm; it may not borrow a veto over the one lawful shot (that would be
    # the decide defect transplanted into the timed path). Record and continue.
    unmeasured <- c(unmeasured, arm)
    write_unmeasurable_gate(arm, tier, K, S, N_SIG, reps_taken, t,
      oj(fc$text, "reason"))
  } else {
    gate_str <- oj(fc$text, "gate")
    if (is.na(gate_str)) gate_str <- if (fc$rc == 0L) "pass" else "breach"
    writeLines(sprintf(paste0('{', '"kind":"arm","arm":"%s","tier":"%s",',
      '"shape":{"K":%d,"S":%d,"n_sig":%d,"R":%d},',
      '"wall":%.9g,"cpu":%.9g,"load_before":%s,',
      '"load_after":%s,',
      '"floor_projection":%.9g,"floor_ratio":%.3g,"gate":"%s"}'),
      arm, tier, K, S, N_SIG, reps_taken, t$wall, t$cpu,
      json_load3(t$load_before), json_load3(t$load_after),
      as.numeric(oj(fc$text, "projection")),
      as.numeric(oj(fc$text, "floor_ratio")), gate_str),
      file.path(wit, sprintf("arm_%s.jsonl", arm)))
  }
  fits[[arm]] <- t$value
  if (fc$rc == 4L) {
    # HALT-AND-REPORT: no rerun, no floor refit, no averaging away (RB-10).
    write_result(sprintf(paste0("UNMEASURED-with-pilot (HALT-AND-REPORT: %s ",
      "tripped the pre-registered 3x-floor gate: observed %gs vs floor %gs)"),
      arm, t$wall, as.numeric(oj(fc$text, "floor"))), tier = tier,
      extra = "- see witnesses/ and witnesses/tier_decision.json")
    rc <- call_oracle_rc(character(0))
    say("[campaign] reader verifier rc=", rc$rc, " ", rc$text)
    quit(status = 3L)
  }
}

# -- thread-count invariance witness (A2 vs A3, the package law re-used) -----------
e2 <- fits$A2@exposures; e3 <- fits$A3@exposures
inv <- list(point = identical(as.numeric(e2), as.numeric(e3)),
  ci_lower = identical(as.numeric(attr(e2, "ci_lower")),
    as.numeric(attr(e3, "ci_lower"))),
  ci_upper = identical(as.numeric(attr(e2, "ci_upper")),
    as.numeric(attr(e3, "ci_upper"))))
inv_ok <- all(unlist(inv))
writeLines(sprintf(paste0('{', '"kind":"invariance","point":%s,',
  '"ci_lower":%s,"ci_upper":%s,"ok":%s}'), inv$point, inv$ci_lower,
  inv$ci_upper, inv_ok), file.path(wit, "invariance_A2_A3.jsonl"))
say("[campaign] thread-invariance witness: ok=", inv_ok)

# -- correctness anchor (share-normalized, protocol §5 + addendum) -------------------
# (the anchor defs are hoisted above the anchor-probe dispatch: both the
# authoritative path and the calibration probe share the same anchor code --
# the probe exists to measure THIS gate at THIS shape, not a lookalike)
say("[campaign] anchor (", S_ANCHOR, " samples x R=", R_ANCHOR,
  ", share-normalized per the §5 addendum): ")
write_anchor(file.path(wit, "anchor_A1.jsonl"), anchor_a1())
write_anchor(file.path(wit, "anchor_A2.jsonl"), anchor_a2())
anch <- call_oracle_rc("--anchor-check")
anchor_ok <- anch$rc == 0L
say("[campaign] anchor oracle rc=", anch$rc, " ", anch$text)

# -- the pinned campaign table, the claim, then the reader pass ----------------------
emit_tf <- tempfile("emit")
est <- system2("python3", c(EMITTER, "--campaign", outdir),
  stdout = emit_tf, stderr = emit_tf)
if (!ok_rc(est)) abort("table emitter failed (status ", as.integer(est),
  "): ", paste(readLines(emit_tf, warn = FALSE), collapse = " | "))

arm_wall <- function(arm) as.numeric(oj(
  paste(readLines(file.path(wit, sprintf("arm_%s.jsonl", arm)),
    warn = FALSE), collapse = ""), "wall"))
ratio <- arm_wall("A1") / arm_wall("A2")
secondary <- arm_wall("A1") / arm_wall("A3")
claimable <- anchor_ok && inv_ok && !smoke
verdict <- if (!anchor_ok || !inv_ok) {
  sprintf("UNMEASURED-with-pilot (%s)", paste0(collapse = "; ",
    if (!anchor_ok) "anchor gate failed" else NULL,
    if (!inv_ok) "thread-count invariance broken" else NULL))
} else if (smoke) {
  "UNMEASURED-with-pilot (smoke rehearsal — disposable numbers)"
} else if (ratio >= 100) {
  "MEASURED-true ≥100x"
} else {
  sprintf("MEASURED-false %.4gx", ratio)
}
write_result(verdict, tier = tier,
  ratio_line = if (claimable) ratio else NULL,
  extra = c(
    sprintf("- secondary A1/A3 (pool-scaling isolation): %.6g", secondary),
    if (!anchor_ok) paste0("- the anchor witness is committed with the ",
      "failure named: witnesses/anchor_A*.jsonl; the oracle said ",
      anch$text),
    if (!inv_ok) "- witnesses/invariance_A2_A3.jsonl names the broken leg",
    if (length(unmeasured)) paste0(
      "- floor gate UNMEASURED on: ", paste(unmeasured, collapse = ", "),
      " (probe-fit non-identifiable at probe scale, the pre-registered leg; ",
      "the arm witness carries the marker and the oracle reason verbatim)")))
rc <- call_oracle_rc(character(0))
say("[campaign] reader verifier rc=", rc$rc, " ", rc$text)
if (rc$rc != 0L) quit(status = 1L)
say("[campaign] CAMPAIGN-COMPLETE outdir=", outdir, " tier=", tier,
  " verdict=", verdict, " ratio=", sprintf("%.6g", ratio))
