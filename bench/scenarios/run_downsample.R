# run_downsample.R -- the CS-6 downsample-frontier scenario (pillar 3).
#
# Mandate: plant a seeded SBS96 cohort through the package's own generator
# (ms_simulate, count-scale exposures -- deterministic column totals under
# the multinomial arm), thin it across a FROZEN depth ladder with
# ms_downsample, and adjudicate the pooled presence face (ms_test_presence:
# per-signature LRT over all samples, BH over the planted dictionary)
# against the planted truth. The committed witness bytes under out/ are the
# verdict; a byte-rerun must reproduce them identically.
#
# Framing law: DECISION RECORD only. The frontier shape -- where the
# borderline signature's pooled verdict flips along the ladder -- is an
# OBSERVED, COMMITTED fact, never a generalization about downsample
# behavior at large. The hard rails are the planted extremes (strong
# signatures at recall 1, the planted-zero control at census 0), the
# monotone law on the borderline bit, and the byte laws of the thinning
# itself (verbatim-keep, total-clamp, dead-stays-dead, seed reproducible).

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
SIG <- c("SBS1", "SBS2", "SBS5", "SBS18")          # SBS18: planted-zero control
STRONG <- c("SBS1", "SBS5")
BORD <- "SBS2"
T_STRONG <- c(3000, 3200, 2800, 3400, 3000, 2600)   # S01..S06
T_BORD <- c(900, 1100)                                  # S07..S08
T_SUB <- c(300, 500)                                    # S09..S10
SAMPLES <- paste0("S", formatC(1:10, width = 2L, flag = "0"))
DEPTHS <- c(400, 800, 1200, 1600, 2400, 3200)
PLANT_SEED <- 7L
LADDER_SEED <- 3L
SEED_RUNG <- 1200
SEEDS <- 1:8
BOUND_TOT <- c(1000, 1001, 999, 0, 1000)
BOUND_DEPTH <- 1000
BOUND_SEED <- 11L
BOUND_SAMPLES <- paste0("B", formatC(1:5, width = 2L, flag = "0"))
BH_ALPHA <- 0.05
NB_SIZE <- 8L

verdict <- new.env(parent = emptyenv())
verdict$fail <- 0L
.check <- function(label, ok) {
  cat(if (isTRUE(ok)) "  ok   " else "  FAIL ")
  cat(label, "\n")
  if (!isTRUE(ok)) verdict$fail <- verdict$fail + 1L
  invisible(isTRUE(ok))
}
quiet <- new.env(parent = emptyenv())
quiet$n <- 0L
.watch_quiet <- function(expr) {
  withCallingHandlers(
    eval.parent(substitute(expr)),
    warning = function(w) {
      quiet$n <- quiet$n + 1L
      invokeRestart("muffleWarning", TRUE)
    },
    message = function(m) {
      quiet$n <- quiet$n + 1L
      invokeRestart("muffleMessage", TRUE)
    }
  )
}

dict <- local({
  refdb <- ms_refdb_bundled(build = "GRCh37")
  mat <- refdb[["SBS_GRCh37"]]@matrices[[1L]]
  sweep(mat[, SIG, drop = FALSE], 2L, colSums(mat[, SIG, drop = FALSE]), "/")
})
exposures <- local({
  E <- matrix(0, nrow = length(SIG), ncol = 10L,
              dimnames = list(SIG, SAMPLES))
  sbs1 <- round(T_STRONG * 0.8)
  E["SBS1", seq_len(6L)] <- as.numeric(sbs1)
  E["SBS5", seq_len(6L)] <- T_STRONG - sbs1
  E["SBS2", 7:8] <- T_BORD
  E["SBS2", 9:10] <- T_SUB
  E
})
hand_catalog <- function(totals, samples) {
  registry <- get("channel_tables", envir = asNamespace("msuiter"))
  labels <- as.character(registry[["SBS96"]]$labels)
  counts <- matrix(0, nrow = 96L, ncol = length(totals),
                   dimnames = list(labels, samples))
  for (j in seq_along(totals)) {
    if (totals[j] > 0) {
      counts[1L, j] <- totals[j] - 94L
      counts[2:95, j] <- 1
    }
  }
  ms_catalog(counts = counts,
             channels = list(name = "SBS96", labels = labels),
             samples = samples, provenance = list(genome = "hand"))
}

cat("== cs6 downsample-frontier scenario: start ==\n")

# ---------------------------------------------------------------------------
# 1. the seeded plant: deterministic totals under the count-scale contract
# ---------------------------------------------------------------------------
plant_cat <- ms_simulate(signatures = dict, exposures = exposures, seed = PLANT_SEED)
plant_totals <- unname(colSums(plant_cat@counts))
.check("plant carries the frozen ten-sample count-scale roster",
       identical(colnames(plant_cat@counts), SAMPLES) &&
         identical(dim(plant_cat@counts), c(96L, 10L)))
.check("plant totals are the frozen arithmetic (deterministic multinomial)",
       identical(as.integer(plant_totals),
                 as.integer(c(T_STRONG, T_BORD, T_SUB))))
# witness-finiteness census BEFORE any write ([[witness-finiteness-census-law]])
.check("plant counts are finite on every cell (pre-write census)",
       all(is.finite(plant_cat@counts)))

# ---------------------------------------------------------------------------
# 2. the depth ladder: pooled presence verdicts, thinning byte laws
# ---------------------------------------------------------------------------
rungs <- lapply(DEPTHS, function(d) {
  ds <- .watch_quiet(ms_downsample(plant_cat, depth = d, seed = LADDER_SEED))
  pres <- ms_test_presence(ds, signatures = dict, nb_size = NB_SIZE)
  list(depth = d, ds = ds, pres = pres)
})
ladder <- data.frame(
  depth = unlist(lapply(rungs, function(r) rep(r$depth, length(r$pres$signature))),
                  use.names = FALSE, recursive = FALSE),
  signature = unlist(lapply(rungs, function(r) r$pres$signature),
                     use.names = FALSE, recursive = FALSE),
  stat = unlist(lapply(rungs, function(r) r$pres$stat),
                use.names = FALSE, recursive = FALSE),
  p_bh = unlist(lapply(rungs, function(r) r$pres$p_bh),
                use.names = FALSE, recursive = FALSE),
  pass_bh = unlist(lapply(rungs, function(r) as.integer(r$pres$pass_bh)),
                   use.names = FALSE, recursive = FALSE),
  stringsAsFactors = FALSE
)
.check("ladder speaks the frozen roster at every rung",
       identical(ladder$signature, rep(SIG, length(DEPTHS))))
strong_bits <- ladder$pass_bh[ladder$signature %in% STRONG]
.check("strong signatures hold pooled recall 1 across the whole ladder",
       identical(strong_bits, rep(1L, 2L * length(DEPTHS))))
ctrl <- ladder[ladder$signature == "SBS18", , drop = FALSE]
.check("planted-zero control speaks census 0 across the whole ladder",
       identical(ctrl$pass_bh, rep(0L, length(DEPTHS))) &&
         all(ctrl$p_bh > BH_ALPHA))
bord_bits <- ladder$pass_bh[ladder$signature == BORD]
.check("borderline bit is monotone non-decreasing along the ladder",
       all(diff(bord_bits) >= 0))
bord_last <- if (any(bord_bits == 1L)) max(DEPTHS[bord_bits == 1L]) else NA_real_()
cat(sprintf("  obs  borderline %s last passing depth: %s\n", BORD,
            if (is.na(bord_last)) "none" else format(bord_last)))
.check("ladder floats are finite on every row (pre-write census)",
       all(is.finite(ladder$stat)) && all(is.finite(ladder$p_bh)))
.check("rung provenance records the frozen depth and seed",
       all(vapply(rungs, function(r) {
         pv <- r$ds@provenance$downsample
         identical(as.numeric(pv$depth), as.numeric(r$depth)) &&
           identical(as.numeric(pv$seed), as.numeric(LADDER_SEED))
       }, logical(1))))

# ---------------------------------------------------------------------------
# 3. the boundary cohort: verbatim-keep, clamp, dead-stays-dead, provenance
# ---------------------------------------------------------------------------
bound_cat <- hand_catalog(BOUND_TOT, BOUND_SAMPLES)
bound <- ms_downsample(bound_cat, depth = BOUND_DEPTH, seed = BOUND_SEED)
.check("verbatim columns keep their bytes at the boundary",
       all(vapply(c(1L, 3L, 5L), function(j)
         identical(as.integer(bound@counts[, j]),
                   as.integer(bound_cat@counts[, j])), logical(1))))
.check("the above-boundary column clamps to exactly the depth",
       identical(sum(bound@counts[, 2L]), as.numeric(BOUND_DEPTH)))
.check("the dead column stays dead",
       all(bound@counts[, 4L] == 0))
.check("boundary provenance is honest (kept 3, thinned 1)",
       identical(as.integer(bound@provenance$downsample$n_kept_verbatim), 3L) &&
         identical(as.integer(bound@provenance$downsample$n_downsampled), 1L))

# ---------------------------------------------------------------------------
# 4. the seed leg: laws are seed-free, bytes are not
# ---------------------------------------------------------------------------
clamped <- as.integer(pmin(c(T_STRONG, T_BORD, T_SUB), SEED_RUNG))
seed_ok <- all(vapply(SEEDS, function(s) {
  ds <- ms_downsample(plant_cat, depth = SEED_RUNG, seed = s)
  identical(as.integer(unname(colSums(ds@counts))), clamped) &&
    identical(as.integer(ds@counts[, 7L]), as.integer(plant_cat@counts[, 7L]))
}, logical(1)))
.check("clamp-and-keep laws hold seed-invariantly (seeds 1..8)", seed_ok)
a1 <- ms_downsample(plant_cat, depth = SEED_RUNG, seed = 1)
a1b <- ms_downsample(plant_cat, depth = SEED_RUNG, seed = 1)
a2 <- ms_downsample(plant_cat, depth = SEED_RUNG, seed = 2)
same_seed <- identical(a1@counts, a1b@counts)
cross_seed <- !identical(a1@counts[, 1L], a2@counts[, 1L])
.check("same seed replays byte-identically; a second seed thins differently",
       same_seed && cross_seed)

# ---------------------------------------------------------------------------
# 5. min-depth, the all-dead right-reason abort, certified silence
# ---------------------------------------------------------------------------
minleg <- ms_downsample(bound_cat, depth = "min", seed = BOUND_SEED)
min_prov <- minleg@provenance$downsample
.min_ok <- identical(as.numeric(min_prov$depth), as.numeric(min(BOUND_TOT[-4L]))) &&
  identical(as.integer(min_prov$n_downsampled), 3L) &&
  identical(as.integer(min_prov$n_kept_verbatim), 1L)
dead_cat <- hand_catalog(c(0, 0), c("D1", "D2"))
abort_msg <- tryCatch({
  ms_downsample(dead_cat, depth = "min", seed = 1L)
  ""
}, error = function(e) paste(conditionMessage(e), collapse = " "))
.abort_ok <- grepl("at least one live sample", abort_msg, fixed = TRUE)
quiet_before <- quiet$n
invisible(.watch_quiet({
  ds <- ms_downsample(plant_cat, depth = SEED_RUNG, seed = LADDER_SEED)
  ms_test_presence(ds, signatures = dict, nb_size = NB_SIZE)
}))
silence_ok <- identical(quiet$n, quiet_before)
.check("min-depth uses the smallest live total and thins the rest", .min_ok)
.check("the all-dead min-abort speaks its right reason", .abort_ok)
.check("the face chain runs certified-silent", silence_ok)

# ---------------------------------------------------------------------------
# [attest] -- declined scope rails, made audible
# ---------------------------------------------------------------------------
cat("[attest] decision-record only: the frontier flip depth is an OBSERVED,\n")
cat("[attest]   COMMITTED fact -- no generalization about thinning at large.\n")
cat("[attest] no estimation machinery added: no bootstrap, no intervals,\n")
cat("[attest]   no conformal framing (paper declined-word), no new faces.\n")
cat("[attest] the M3b sanity harness (R/calibrate-real.R) is NOT touched:\n")
cat("[attest]   sanity bytes never enter calibration standing.\n")
cat("[attest] dictionary from the bundled reference only (no downloads).\n")

# ---------------------------------------------------------------------------
# 6. the committed witnesses (finiteness censused above, pre-write)
# ---------------------------------------------------------------------------
dir.create(OUT, showWarnings = FALSE)
plant_df <- cbind(channel = as.character(rownames(plant_cat@counts)),
                  as.data.frame(plant_cat@counts))
write.csv(plant_df, file.path(OUT, "cs6_plant.csv"), row.names = FALSE)
write.csv(ladder, file.path(OUT, "cs6_ladder.csv"), row.names = FALSE)
write.csv(data.frame(sample = BOUND_SAMPLES,
                     total = as.integer(BOUND_TOT),
                     is_verbatim = as.integer(BOUND_TOT > 0 & BOUND_TOT <= BOUND_DEPTH),
                     is_dead = as.integer(BOUND_TOT == 0),
                     post_total = as.integer(pmin(BOUND_TOT, BOUND_DEPTH)),
                     stringsAsFactors = FALSE),
          file.path(OUT, "cs6_boundary.csv"), row.names = FALSE)
write.csv(data.frame(depths = paste0(DEPTHS, collapse = ","),
                     plant_seed = as.integer(PLANT_SEED),
                     ladder_seed = as.integer(LADDER_SEED),
                     bound_depth = as.integer(BOUND_DEPTH),
                     bound_seed = as.integer(BOUND_SEED),
                     dict_roster = paste(SIG, collapse = ","),
                     bh_alpha = BH_ALPHA, nb_size = as.integer(NB_SIZE),
                     sbs2_last_pass_depth = bord_last,
                     plant_min_total = as.integer(min(plant_totals)),
                     stringsAsFactors = FALSE),
          file.path(OUT, "cs6_scalars.csv"), row.names = FALSE)
write.table(data.frame(check = c("min_depth", "min_n_downsampled",
                                 "min_n_kept_verbatim", "alldead_abort_right_reason",
                                 "same_seed_reproducible",
                                 "cross_seed_thinning_differs", "certified_silence"),
                      value = c(as.integer(min_prov$depth),
                                as.integer(min_prov$n_downsampled),
                                as.integer(min_prov$n_kept_verbatim),
                                as.integer(.abort_ok), as.integer(same_seed),
                                as.integer(cross_seed), as.integer(silence_ok)),
                      stringsAsFactors = FALSE),
            file.path(OUT, "cs6_degenerates.tsv"), sep = "\t", quote = FALSE,
            row.names = FALSE, col.names = TRUE)

cat("== cs6 downsample-frontier scenario: ",
    if (identical(verdict$fail, 0L)) "OVERALL PASS" else "OVERALL FAIL",
    " == (evidence: ", OUT, ")\n", sep = "")
quit(save = "no", status = if (identical(verdict$fail, 0L)) 0L else 1L)
