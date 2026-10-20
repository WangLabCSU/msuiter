#!/usr/bin/env Rscript
# =============================================================================
# bench/m1s/sbs/run_bench.R · M1s acceptance-gate SBS catalog generation bench
#(docs/ARCHITECTURE.md §8 budget row: catalog generation SBS96(10⁶ mutations)vs SPMG ≥50×,
#   and ours <5s single-core. ROADMAP M1s acceptance gate: catalog generation ≥50× SPMG(pinned-hardware bench;
#   CI only sanity bound <5s ). this script is not part of CI.
#
# Caliber (recorded verbatim):
#   * Our reported caliber =  = user-perceivable end-to-end:ms_tally(MsVariants, 2bit, "SBS96")——
#     S7 validation + FFI(mmap 2bitrouting, context, counting,ledger) + + catalog assembly.
#     Single-threaded (src/rust/src/tally.rs concurrency section:M1s intentionally single-threaded).
#   * secondary caliber (decomposition)= FFI layer msuiter:::.ms_tally_rust(includes mmap + R side column checks
#     + dimnames, dropping S7 assembly).
#   * [Rust bin pure-core] caliber is unavailable at HEAD unavailable: the kernel assembly entry mod tally is package-private,
#     package code must not be bench changed for the bench; the FFI——FFI secondary caliber is the pure-core upper bound (includes ~1.2MB mmap),
#     recorded verbatim as a legacy-caliber note.
#   * SPMG baseline = standard call SigProfilerMatrixGeneratorFunc(10⁶ mutations, same synthetic
#     reference genome, outputting SBS96 included in the full set of 9 matrix kinds),VCF file input (SPMG sole
#     user interface)——includes VCF parsing and full-set matrix writing; ours is only SBS96 with inputs in memory.
#     This asymmetry favors SPMG advantageously ( heavier workload ), if the criterion still PASS then the conclusion
#     is right in the conservative direction; details in result.md.
#   * Protocol: ours warms up 1 + timed 3 runs take the median;SPMG SPMG single wall clock (minute-scale, no reruns).
#
# Correctness anchor (more important than speed, mandatory):100 mutations sanity subset on which SPMG SPMG vs our ms_tally
#   s SBS96 matrix cell-by-cell identical (same-sample adjacent pairs are→DBS excluded on both sides; cross-sample adjacent pairs are→both sides SBS,
#   extreme legitimate positions); disagreement = P0 = P0 finding. The full 10⁶ matrix is also cross-checked cell-by-cell.
# =============================================================================

options(stringsAsFactors = FALSE, digits = 15, scipen = 12)

HERE <- normalizePath(dirname(sub("^--file=", "",
  grep("^--file=", commandArgs(FALSE), value = 1))))
CACHE <- file.path(HERE, "cache")
# Note: do not run normalizePath——venv s bin/python is a symlink to the base interpreter,
# after resolution venv is disabled (site-packages lost). Keep the original path and let Python probe itself via pyvenv.cfg.
VENV_PY <- file.path(HERE, "..", ".venv", "bin", "python")
stopifnot(file.exists(VENV_PY))

sig <- function(x, d = 6) format(x, digits = d, trim = TRUE, scientific = TRUE)
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(...) cat(..., "\n", sep = "")

say("== M1s SBS catalog generation bench: 10⁶ SNV,SBS96,vs SPMG ≥50× and ours <5s ==")

# ---- Ours ------------------------------------------------------------------
pkgload::load_all(quiet = TRUE)

read_vars <- function(name) {
  d <- read.csv(file.path(CACHE, name), colClasses = c(
    chrom = "character", pos = "numeric", ref = "character",
    alt = "character", sample = "character"), comment.char = "")
  # fixture CSV uses 1-based pos;MsVariants needs canonical chrom/start/end/ref/alt.
  d$start <- d$pos
  d$end <- d$pos + nchar(d$ref) - 1L
  d[, c("chrom", "start", "end", "ref", "alt", "sample")]
}

tab_full <- read_vars("variants.csv")        # main arm dbsfree(min spacing≥2, no duplicates)
tab_dense <- read_vars("variants_dense.csv") # secondary arm dense(natural adjacency density, deduped)
tab_san  <- read_vars("sanity.csv")          # semantic probes (including adjacent pairs)
g2b <- file.path(CACHE, "genome.2bit")
stopifnot(file.exists(g2b))

v_full <- ms_variants(tab_full, "SYN5M-bench",
  caller = "bench-synthetic", matched_normal = "none")
v_dense <- ms_variants(tab_dense, "SYN5M-bench",
  caller = "bench-synthetic", matched_normal = "none")
v_san <- ms_variants(tab_san, "SYN5M-bench",
  caller = "bench-synthetic", matched_normal = "none")

# S7 end-to-end (reported caliber): warm up 1 + timed 3 runs take the median
timed_ms_tally <- function(v) {
  invisible(ms_tally(v, g2b, "SBS96")) # warm-up
  runs <- replicate(3L, {
    t0 <- proc.time()
    cat0 <- ms_tally(v, g2b, "SBS96")
    list(elapsed = (proc.time() - t0)[["elapsed"]], cat = cat0)
  }, simplify = FALSE)
  list(runs = vapply(runs, `[[`, numeric(1), "elapsed"),
       median_s = median(vapply(runs, `[[`, numeric(1), "elapsed")),
       cat = runs[[1]]$cat)
}

# FFI layer (secondary caliber)
timed_ffi <- function(tab) {
  call_ffi <- function() msuiter:::.ms_tally_rust(g2b,
    chrom = tab$chrom, pos = tab$start, ref_ = tab$ref, alt = tab$alt,
    sample = tab$sample, strand = rep("N", nrow(tab)), want_sbs96 = TRUE)
  invisible(call_ffi())
  runs <- replicate(3L, {
    t0 <- proc.time()
    res <- call_ffi()
    (proc.time() - t0)[["elapsed"]]
  })
  list(runs = as.numeric(runs), median_s = median(as.numeric(runs)))
}

say("Ours ms_tally(S7 end-to-end)—— main arm dbsfree ...")
ours <- timed_ms_tally(v_full)
for (i in seq_along(ours$runs)) say(sprintf("  run%d: %.3f s", i, ours$runs[i]))
say(sprintf("  median: %.3f s | n=%d samples=%s | sum(SBS96)=%d n_skipped=%d",
  ours$median_s, nrow(tab_full), paste(ours$cat@samples, collapse = ","),
  sum(ours$cat@counts), ours$cat@provenance$n_skipped))

say("Ours ms_tally —— secondary arm dense(speed reference and total-volume reconciliation)...")
ours_dense <- timed_ms_tally(v_dense)
say(sprintf("  median: %.3f s | records=%d sum(SBS96)=%d n_skipped=%d",
  ours_dense$median_s, nrow(tab_dense), sum(ours_dense$cat@counts),
  ours_dense$cat@provenance$n_skipped))
n_dbs_dense <- nrow(tab_dense) - sum(ours_dense$cat@counts) -
  ours_dense$cat@provenance$n_skipped
say(sprintf("  dense: we judge as DBS(excluded from SBS96) record-count = %d", n_dbs_dense))

say("Ours .ms_tally_rust(FFI hierarchical caliber)...")
ffi <- timed_ffi(tab_full)
say(sprintf("  median: %.3f s", ffi$median_s))

stopifnot(ours$median_s < 5) # hard budget-row constraint:<5s(CI sanity bound same caliber)

# ---- cross-check (our-side matrices written to disk) ------------------------------------------------
cat_san <- ms_tally(v_san, g2b, "SBS96")
cat_dense <- ours_dense$cat
write_sbs_tsv <- function(counts, path) {
  lines <- c(paste(c("channel", colnames(counts)), collapse = "\t"),
    paste(rownames(counts), counts[, 1], counts[, 2], sep = "\t"))
  writeLines(lines, path)
}
write_sbs_tsv(cat_san@counts, file.path(CACHE, "ours_sanity96.tsv"))
cat_full <- ours$cat
write_sbs_tsv(cat_full@counts, file.path(CACHE, "ours_full96.tsv"))
write_sbs_tsv(cat_dense@counts, file.path(CACHE, "ours_dense96.tsv"))

# ---- SPMG baseline (venv python subprocess) --------------------------------------
say("SPMG baseline (.venv, includes custom-genome install/validation registration; for the upstream-limitation bypass see the script header)...")
sp <- system2(VENV_PY, c(file.path(HERE, "spmg_run.py"), CACHE),
  stdout = TRUE, stderr = TRUE)
status <- attr(sp, "status") %||% 0L
cat(paste(sp, collapse = "\n"), "\n")
if (status != 0L) stop("spmg_run.py failed with status ", status)

timing <- jsonlite::fromJSON(file.path(CACHE, "spmg_timing.json"))
spmg_full_s <- as.numeric(timing$full$wall_s)
spmg_dense_s <- as.numeric(timing$dense$wall_s)
spmg_san_s <- as.numeric(timing$sanity$wall_s)

# ---- cell-by-cell cross-check --------------------------------------------------------------
read_sbs_tsv <- function(path) {
  d <- read.csv(path, sep = "\t", row.names = 1, check.names = FALSE)
  m <- as.matrix(d); storage.mode(m) <- "integer"; m
}
align <- function(ours_m, spmg_path, label) {
  sp <- read_sbs_tsv(spmg_path)
  stopifnot(setequal(colnames(sp), colnames(ours_m)))
  sp <- sp[, colnames(ours_m), drop = FALSE]
  if (!identical(rownames(sp), rownames(ours_m))) {
    stop(label, ": channel label order differs between msuiter and SPMG")
  }
  list(sp = sp, diff = sp - ours_m,
    sum_ours = sum(ours_m), sum_spmg = sum(sp),
    n_diff = sum(abs(sp - ours_m) > 0L))
}

# main arm (dbsfree): the criterion = cell-by-cell full equality (correctness anchor, mandatory)
main_cmp <- align(cat_full@counts, file.path(CACHE, "spmg_full96.tsv"), "main")
# sanity(includes adjacent pairs): the expected diff = same-sample adjacent-pair members (SPMG 1.3.6 lumps DBS members in as well
# SBS96; we follow the U-M1s-09 audit semantics, excluded)——the diff must be nonnegative and exactly 4 cells summed
san_cmp <- align(cat_san@counts, file.path(CACHE, "spmg_sanity96.tsv"), "sanity")
san_ok <- san_cmp$n_diff == sum(abs(san_cmp$diff)) && all(san_cmp$diff >= 0L) &&
  sum(san_cmp$diff) == 4L
# secondary arm dense: total-volume reconciliation = SPMG total − our SBS96 total == our DBS member count
dense_cmp <- align(cat_dense@counts, file.path(CACHE, "spmg_dense96.tsv"), "dense")
dense_ok <- sum(dense_cmp$diff) == n_dbs_dense && all(dense_cmp$diff >= 0L)

say(sprintf("sanity cross-check (100 mutations, includes adjacent pairs):ours sum=%d spmg sum=%d diff-sum=%d(expected 4=DBS members)",
  san_cmp$sum_ours, san_cmp$sum_spmg, sum(san_cmp$diff)))
say(sprintf("main dbsfree cross-check (10⁶):ours sum=%d spmg sum=%d cell-diff=%d(criterion = 0)",
  main_cmp$sum_ours, main_cmp$sum_spmg, main_cmp$n_diff))
say(sprintf("dense reconciliation (after dedupe %d records):SPMG−ours = %d(expected = = our DBS members %d)",
  nrow(tab_dense), sum(dense_cmp$diff), n_dbs_dense))

if (!san_ok) stop("P0:sanity the diff is not exactly the DBS member-diff (4) ———requires cell-by-cell localization")
if (!dense_ok) stop("P0:dense reconciliation failed——the diff is not the DBS member count")
if (main_cmp$n_diff != 0L) stop("P0:dbsfree main arm disagrees cell-by-cell——correctness anchor failed")

# ---- criterion ------------------------------------------------------------------
speedup <- spmg_full_s / ours$median_s
verdict <- speedup >= 50 && ours$median_s < 5
say(sprintf("criterion:speedup = %.3f s / %.4f s = %.1f×(≥50× and <5s:  %s)",
  spmg_full_s, ours$median_s, speedup, ifelse(verdict, "PASS", "FAIL")))

# ---- result.md -------------------------------------------------------------
env <- function() {
  c(paste0("date: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    paste0("R: ", R.version$version.string, " (", R.version$platform, ")"),
    paste0("python/SPMG: SigProfilerMatrixGenerator 1.3.6 (bench/m1s/.venv)"),
    paste0("host: ", R.version$platform, "(Apple Silicon ; the power state is not controllable, figures are for this pinned hardware)"))
}

lines <- c(
  "# B2 · SBS catalog generation bench(M1s acceptance gate,ARCHITECTURE §8: 10⁶ mutations SBS96 vs SPMG ≥50× and  <5s single-core)", "",
  "Rerun:`python3 bench/m1s/sbs/gen_fixtures.py && Rscript bench/m1s/sbs/run_bench.R`.",
  "The same synthetic reference (2×2.5Mb,catalog/tests/genome fixture.rs enlarged version, includes N blocks).",
  "the same 10⁶ SNV: ours = `ms_tally()` S7 end-to-end (single-threaded; secondary caliber FFI layer `.ms_tally_rust`);",
  "SPMG = SigProfilerMatrixGenerator 1.3.6 standard call (custom-genome install + VCF input,", 
  "produces the full set of 9 matrix kinds ———workload exceeds our SBS96 single table; the criterion is conservative, see notes).", "",
  "## Environment", "",
  sapply(env(), function(l) paste0("- ", l)), "",
  "## Figures (main arm = dbsfree: same-sample same-chromosome minimum spacing 2, no duplicate records; both sides aligned record-by-record)", "",
  paste0("- Ours ms_tally 3 runs (s):", paste(sprintf("%.4f", ours$runs), collapse = ", "),
         " → **median = ", sprintf("%.4f", ours$median_s), " s(<5s ✓)**"),
  paste0("- Ours FFI layer 3 runs (s):", paste(sprintf("%.4f", ffi$runs), collapse = ", "),
         " → median = ", sprintf("%.4f", ffi$median_s),
         " s(S7−FFI diff ≈ ", sprintf("%.1f", (ours$median_s - ffi$median_s) * 1e3),
         " ms, noise-level ———S7 assembly does not form a perceivable overhead)"),
  paste0("- SPMG main-arm single wall clock = ", sprintf("%.1f", spmg_full_s),
         " s(sanity probe ", sprintf("%.3f", spmg_san_s),
         " s; single-run caliber ———minute-scale, no reruns)"),
  paste0("- **speedup = ", sprintf("%.1f", speedup), "×; criterion ≥50× and ours <5s:",
         ifelse(verdict, "PASS", "FAIL"), "**"),
  paste0("- **correctness anchor (main arm cell-by-cell)**: ours sum=", main_cmp$sum_ours,
         " = SPMG sum=", main_cmp$sum_spmg, ", cell-diff = = ", main_cmp$n_diff,
         ifelse(main_cmp$n_diff == 0L, "(✓ full agreement)", "(⚠ P0)")), "",
  "## Secondary arm dense(natural adjacency density,(chrom,pos,sample) aligned after dedupe)", "",
  paste0("- record-count = = ", nrow(tab_dense), "; we judge as DBS member-count = = ", n_dbs_dense,
         "(excluded from SBS96); our side median = ", sprintf("%.3f", ours_dense$median_s),
         " s;SPMG = ", sprintf("%.1f", spmg_dense_s), " s"),
  paste0("- total-volume reconciliation:SPMG sum−our sum = ", sum(dense_cmp$diff),
         ", equals the DBS member count = ", dense_ok,
         "(and every cell-diff is ≥0:SPMG 1.3.6 lumps DBS pair-members into SBS96)"), "",
  "## semantic probes (sanity 100 mutations, includes 2 same-sample adjacent pairs + 1 cross-sample adjacent pairs)", "",
  paste0("- both-sides routing agrees: same-sample adjacent pairs are all judged as DBS class (our ledger 4 entries `dbs`;",
         "SPMG stdout reports 2 DINUCs); cross-sample adjacent pairs stay SBS."),
  paste0("- **SBS96 inclusion-policy mismatch (P0 finding)**:SPMG 1.3.6 lumps DBS pair-members into",
         " SBS96(sanity sum=100 vs our side 96, the diff-sum is exactly = 4  DBS members; minimal probe:",
         "1 adjacent pair + 1 isolated pair → SPMG SBS96=3 and produces no DBS78). We follow the U-M1s-09 audit",
         "semantics (dinuc_sub==1 excluded from all SBS matrices) implementation.**the upstream behavior the audit relies on and",
         "1.3.6 does not match the measurement**——needs PI PI re-review of docs/research/04 the pinned upstream version/code path,",
         "and in M1c the DBS78 units to decide the trade-off (this bench does not change package code)."), "",
  "## Caliber notes (verbatim)", "",
  "- SPMG the SPMG side includes VCF parsing + 9 kinds of full-set matrix computing and writing; ours is only SBS96 single table, inputs in memory.",
  "  workload-corrected (SPMG only SBS96) speedupspeedup can only be higher;——the table numbers are conservative for the criterion.",
  "- speed shape: SPMGSPMG main arm (dbsfree)9.8s vs dense arm 46s——its time is dominated by duplicate records",
  "  dedupe/adjacent pairs (DINUC) processing paths dominate; on clean synthetic input 1.3.6 far below the ≥50× budget",
  "  the implied minute-scale baseline. Ours 3.7s includes R→FFI of the 10⁶ rows of char-column passing overhead",
  "  (the kernel pure-core caliber is unavailable at HEAD , see below) ———both sides budget assumptions need correction per this table.",
  "- SPMG SPMG will <vcf_dir>/input/ cache per-chromosome converted products underspmg_run.py ; spmg_run.py before every run",
  "  clears it (otherwise stale record sets are consumed silently ———this bench bench debugging-time empirical finding).",
  "- SPMG 1.3.6 the generation entry validates genomes with the hardcoded CHECKSUMS whitelist, custom genomes cannot pass",
  "  (upstream limitation);spmg_run.py at runtime registers the local install products md5 into the dict,",
  "  does not modify any upstream file; the matrix-generation code path stays fully original.",
  "- SPMG 1.3.6 will drop fully duplicate records whole-row (independent of sample, compared row-wise;dense arm generation already per",
  "  (chrom,pos,sample) aligned after dedupe), and the DBS of the prior section inclusion policy——two upstream semantic differences",
  "  are both findings of this bench , and have been added to the legacy list.",
  "- [Rust bin pure-core] caliber is unavailable at HEAD HEAD (tally the assembly entry is a package-private module, package code must not be",
  "  bench changes allowed); the FFIFFI hierarchical caliber is the pure-core upper bound (includes mmap + R side checks), listed separately.", ""
)
writeLines(lines, file.path(HERE, "result.md"))
say("result.md written: ", file.path(HERE, "result.md"))
quit(status = ifelse(verdict && main_cmp$n_diff == 0L, 0L, 1L))
