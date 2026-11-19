# run_cluster_witness.R -- the CS-8 cluster-witness scenario (pillar 3).
#
# Mandate: plant a nine-column SBS96 cohort of EXACT duplicate families
# drawn from the bundled GRCh37 reference bytes (roster SBS1/SBS2/
# SBS13/SBS88, family sizes 3/2/2/2, measured max cross cosine 0.0707),
# and adjudicate the SHIPPED threshold-graph face ms_cluster_signatures
# -- connected components of the cosine >= threshold graph, ascending-root
# labels, mean-cosine medoids -- under five arms: clean, jitter (the
# strict-medoid family), artifakt (channel-rotated family 2), degenerate
# (an all-zero column), and a deterministic corruption ladder blending
# every member toward its rotated twin. Every arm is driven through the
# EXPORTED face alone. The whole scenario is RNG-free -- no seed to pin,
# no draw to re-roll. The committed witness bytes under out/ are the
# verdict; a byte-rerun must reproduce them identically.
#
# Framing law: DECISION RECORD only. What this scenario records is the
# shipped face's documented discriminative behavior on planted truth:
# the clean partition is the planted family map (hard rail share 1), the
# scrambled pair splinters to lawful singletons at every swept threshold,
# the zero column speaks its singleton law, the jittered family wins its
# medoid strictly (margin measured, not tie-won), and the ladder's
# last-full-pass rung is an OBSERVED, COMMITTED fact -- never a
# calibration claim. 0.90 is the face's shipped default, cited from its
# formals, not an anchor; cosine above the threshold remains necessary-
# not-sufficient (R/ms-cluster.R header).

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
SIG <- c("SBS1", "SBS2", "SBS13", "SBS88")
COPIES <- c(3L, 2L, 2L, 2L)                       # planted family sizes
MEMBERS <- c("F1a", "F1b", "F1c", "F2a", "F2b",
             "F3a", "F3b", "F4a", "F4b")
NMEM <- 9L
CITED_LINE <- 0.90        # the face's shipped default: cited, not anchored
ROT_UNIT <- 37L           # channel-rotation scrambler (measured cos <= 0.052)
JIT <- 0.01              # jitter mass on the strict-medoid family
JIT_CH <- c(11L, 59L, 35L, 83L)      # SBS1 peak channels (masses >= 0.110)
ZERO_MEMBER <- 7L         # the all-zero column (F3b)
ART_FAM <- 2L             # the scrambled family
RUNGS <- c(0, 0.10, 0.15, 0.20, 0.23, 0.26, 0.35, 0.50)
# Shared contract of the match bit (runner and law, byte-same meaning):
# a member matches iff its observed cluster label AND its observed
# cluster size both equal the committed roster's. Label equality alone
# deceives -- the ascending-root label law can reissue a survivor's old
# label over a broken structure (the zero-arm witness is that proof).

verdict <- new.env(parent = emptyenv())
verdict$fail <- 0L
.check <- function(label, ok) {
  cat(if (isTRUE(ok)) "  ok   " else "  FAIL ")
  cat(label, "\n")
  if (!isTRUE(ok)) verdict$fail <- verdict$fail + 1L
  invisible(isTRUE(ok))
}

# ---------------------------------------------------------------------------
# the planted cohorts (deterministic: bundled bytes, frozen constants)
# ---------------------------------------------------------------------------
dict <- local({
  refdb <- ms_refdb_bundled(build = "GRCh37")
  mat <- refdb[["SBS_GRCh37"]]@matrices[[1L]]
  d <- mat[, SIG, drop = FALSE]
  sweep(d, 2L, colSums(d), "/")
})
NR <- nrow(dict)

rot <- function(v, r) {
  n <- length(v)
  v[((seq_len(n) + r - 1L) %% n) + 1L]
}

matrix_build <- function() {
  cols <- list()
  for (f in seq_along(SIG)) {
    for (k in seq_len(COPIES[f])) {
      cols[length(cols) + 1L] <- list(dict[, SIG[f], drop = TRUE])
    }
  }
  out <- do.call(cbind, cols)
  dimnames(out) <- list(rownames(dict), MEMBERS)
  out
}

art_matrix <- function() {
  S <- matrix_build()
  base <- dict[, SIG[ART_FAM], drop = TRUE]
  S[, "F2a"] <- rot(base, ROT_UNIT)
  S[, "F2b"] <- rot(base, 2L * ROT_UNIT)
  S
}

jit_matrix <- function() {
  S <- matrix_build()
  base <- dict[, SIG[1L], drop = TRUE]
  shift <- function(v, p, q, sign) {
    v[p] <- v[p] + sign * JIT
    v[q] <- v[q] - sign * JIT
    v
  }
  S[, "F1a"] <- shift(base, JIT_CH[1L], JIT_CH[2L], -1)
  S[, "F1c"] <- shift(base, JIT_CH[3L], JIT_CH[4L], 1)
  S
}

zero_matrix <- function() {
  S <- matrix_build()
  S[, ZERO_MEMBER] <- 0
  S
}

blend <- function(w) {
  S <- matrix_build()
  for (m in seq_len(NMEM)) {
    r <- (ROT_UNIT * m) %% 96L
    S[, m] <- (1 - w) * S[, m] + w * rot(S[, m], r)
  }
  S
}

cos1 <- function(x, y) {
  nx <- sqrt(sum(x * x))
  ny <- sqrt(sum(y * y))
  if (nx == 0 || ny == 0) {
    return(NA_real_)
  }
  sum(x * y) / (nx * ny)
}

face <- function(S, thr) ms_cluster_signatures(S, threshold = thr)

# match bit of a fresh partition against the committed roster, STRUCTURAL:
# a member matches iff its co-membership set (whoever shares its cluster)
# equals the roster's AND its cluster size equals the roster's. Cluster
# LABELS are positionally global -- the ascending-root law renumbers them
# whenever an arm adds or drops a cluster -- so label equality across arms
# is meaningless; co-membership + size is the invariant that survives.
mch <- function(cl, ros) {
  clu <- as.character(cl$cluster)
  rcl <- as.character(ros$cluster)
  k <- length(clu)
  out <- integer(k)
  for (i in seq_len(k)) {
    out[i] <- as.integer(
      identical(which(clu == clu[i]), which(rcl == rcl[i])) &&
        as.integer(cl$cluster_size[i]) == as.integer(ros$cluster_size[i]))
  }
  out
}

per_row <- function(cl, arm, ros) {
  data.frame(
    member = as.character(cl$signature), arm = arm,
    cluster = as.character(cl$cluster),
    is_medoid = as.integer(cl$is_medoid),
    cluster_size = as.integer(cl$cluster_size),
    match = mch(cl, ros),
    stringsAsFactors = FALSE)
}

arm_row <- function(arm, cl, ros) {
  data.frame(
    arm = arm, threshold_line = CITED_LINE,
    n_clusters = length(unique(cl$cluster)),
    n_medoids = as.integer(sum(cl$is_medoid)),
    roster_share = mean(mch(cl, ros)),
    rail_pass = 0L,
    stringsAsFactors = FALSE)
}

# ---------------------------------------------------------------------------
# 1. the clean arm -- the committed roster and its hard rail
# ---------------------------------------------------------------------------
cat("== clean arm (planted duplicate families, cited line) ==\n")
S <- matrix_build()
cl_c <- face(S, CITED_LINE)
ros <- data.frame(
  member = as.character(cl_c$signature),
  cluster = as.character(cl_c$cluster),
  is_medoid = as.integer(cl_c$is_medoid),
  cluster_size = as.integer(cl_c$cluster_size),
  stringsAsFactors = FALSE)

# plant quality first: the roster must be separable below the swept
# threshold floor or the whole adjudication is vacuous (measured floor:
# max cross-family pair 0.0707, runner gate at the 0.10 rung base).
fam <- rep(seq_along(COPIES), COPIES)
worst <- 0
for (i in seq_len(NMEM - 1L)) for (j in (i + 1L):NMEM) {
  if (fam[i] != fam[j]) worst <- max(worst, cos1(S[, i], S[, j]))
}
.check("plant separability: worst cross-family cos under the 0.10 floor",
       worst < 0.10)
.check("clean partition is the planted family map",
       identical(ros$cluster,
                 paste0("C", c(1L, 1L, 1L, 2L, 2L, 3L, 3L, 4L, 4L))) &&
         identical(ros$cluster_size,
                    c(3L, 3L, 3L, 2L, 2L, 2L, 2L, 2L, 2L)))
fam1_medoid <- ros$is_medoid[1L:3L]
.check("exact-duplicate family's medoid is its FIRST member (tie law)",
       identical(fam1_medoid, c(1L, 0L, 0L)))

# ---------------------------------------------------------------------------
# 2. the jitter arm -- the medoid is won, not tie-won
# ---------------------------------------------------------------------------
cat("== jitter arm (strict-medoid family 1) ==\n")
Sj <- jit_matrix()
cl_j <- face(Sj, CITED_LINE)
med_j <- as.integer(cl_j$is_medoid)
.check("jitter medoid is the CENTRE member alone (0,1,0)",
       identical(med_j[1L:3L], c(0L, 1L, 0L)))
cmj <- attr(cl_j, "cosines")
means1 <- vapply(seq_len(3L), function(a) {
  mean(cmj[a, seq_len(3L)[-a]])
}, numeric(1L))
.check("jitter medoid wins strictly (margin measured, not ulp-tied)",
       means1[2L] > max(means1[1L], means1[3L]) + 1e-4)
.check("jitter keeps the other families on the committed roster",
       identical(cl_j$cluster[4L:9L], ros$cluster[4L:9L]) &&
         identical(as.integer(cl_j$cluster_size)[4L:9L],
                   ros$cluster_size[4L:9L]) &&
         identical(med_j[4L:9L], ros$is_medoid[4L:9L]))

# ---------------------------------------------------------------------------
# 3. the artifakt arm -- the scrambled pair splinters at every rung
# ---------------------------------------------------------------------------
cat("== artifakt arm (channel-rotated family 2) ==\n")
Sa <- art_matrix()
cl_a <- face(Sa, CITED_LINE)
.check("scrambled pair are lawful singletons at the cited line",
       identical(as.integer(cl_a$cluster_size[4L:5L]), c(1L, 1L)) &&
         cl_a$cluster[4L] != cl_a$cluster[5L])
.check("scrambled pair match the roster on NEITHER member",
       identical(mch(cl_a, ros)[4L:5L], c(0L, 0L)))
.check("the seven untouched members keep the committed verdict",
       identical(mch(cl_a, ros)[c(1L:3L, 6L:9L)], rep(1L, 7L)))
never_merge <- TRUE
for (thr in c(RUNGS[-1L], CITED_LINE)) {
  ca <- face(Sa, thr)
  never_merge <- never_merge &&
    identical(as.integer(ca$cluster_size[4L:5L]), c(1L, 1L)) &&
    ca$cluster[4L] != ca$cluster[5L] &&
    identical(which(ca$signature == "F2a"), 4L) &&
    identical(which(ca$signature == "F2b"), 5L)
}
.check("splinter rail: singletons and distinct at every swept threshold",
       never_merge)

# ---------------------------------------------------------------------------
# 4. the degenerate arm -- the zero column speaks its singleton law
# ---------------------------------------------------------------------------
cat("== degenerate arm (all-zero column) ==\n")
Sz <- zero_matrix()
cl_z <- face(Sz, CITED_LINE)
.check("zero column is a lawful medoid singleton",
       identical(as.integer(cl_z$cluster_size[ZERO_MEMBER]), 1L) &&
         isTRUE(cl_z$is_medoid[ZERO_MEMBER]))
.check("its former twin becomes a lawful singleton too (family of one)",
       identical(as.integer(cl_z$cluster_size[6L]), 1L) &&
         isTRUE(cl_z$is_medoid[6L]))
nan_cells <- sum(is.nan(attr(cl_z, "cosines")))
.check("zero row/col are exactly the 17 NaN cells (9+9-1)",
       identical(as.integer(nan_cells), 17L))
.check("the seven surviving members keep the committed verdict",
       identical(mch(cl_z, ros)[c(1L:3L, 4L:5L, 8L:9L)], rep(1L, 7L)))
e0 <- tryCatch(face(S, 0), error = identity)
.check("threshold=0 aborts on the input topic",
       inherits(e0, "msuiter_error_input") &&
         grepl("threshold", conditionMessage(e0), fixed = TRUE))

# ---------------------------------------------------------------------------
# 5. the corruption ladder -- blend every member toward its rotated twin
# ---------------------------------------------------------------------------
cat("== ladder (blend rung sweep at the cited line) ==\n")
lad <- do.call(rbind, lapply(seq_along(RUNGS), function(g) {
  w <- RUNGS[g]
  cw <- face(blend(w), CITED_LINE)
  sh <- mean(mch(cw, ros))
  data.frame(rung = w,
             n_clusters = length(unique(cw$cluster)),
             n_medoids = as.integer(sum(cw$is_medoid)),
             share_pass = sh,
             is_pass = as.integer(sh == 1),
             stringsAsFactors = FALSE)
}))
.check("rung 0 is the clean arm byte-for-byte",
       identical(lad$share_pass[1L], 1))
.check("ladder share is monotone non-increasing",
       all(diff(lad$share_pass) <= 0))
last_pass <- if (any(lad$is_pass == 1L)) {
  max(as.numeric(lad$rung[lad$is_pass == 1L]))
} else {
  NA_real_
}
.check("ladder tail rung is all-singletons, share 0",
       identical(lad$n_clusters[8L], NMEM) && identical(lad$share_pass[8L], 0))
cat("  ladder: last full-pass rung ",
    format(if (is.na(last_pass)) NA_real_ else last_pass),
    " (observed, never asserted)\n", sep = "")

# ---------------------------------------------------------------------------
# [attest] -- declined scope rails, made audible
# ---------------------------------------------------------------------------
cat("[attest] DECISION RECORD only: the face's behavior on planted truth is\n")
cat("[attest]   an OBSERVED, COMMITTED record -- no calibration claims, no generalization.\n")
cat("[attest] 0.90 is the face's shipped default, cited from its formals, not an\n")
cat("[attest]   anchor (R/ms-cluster.R header): cosine above it is necessary, not sufficient.\n")
cat("[attest] no estimation machinery added: no bootstrap, no intervals,\n")
cat("[attest]   no conformal framing (paper declined-word), no new faces.\n")
cat("[attest] the M3b sanity harness (R/calibrate-real.R) is NOT touched:\n")
cat("[attest]   sanity bytes never enter calibration standing.\n")
cat("[attest] dictionary from the bundled reference only (no downloads);\n")
cat("[attest]   the exported ms_cluster_signatures face only (no internal-helper reach-in).\n")

# ---------------------------------------------------------------------------
# 6. the committed witnesses (finiteness censused here, pre-write)
# ---------------------------------------------------------------------------
per_rows <- rbind(
  per_row(cl_c, "clean", ros), per_row(cl_j, "jitter", ros),
  per_row(cl_a, "artifakt", ros), per_row(cl_z, "degenerate", ros))
arm_rows <- rbind(
  arm_row("clean", cl_c, ros), arm_row("jitter", cl_j, ros),
  arm_row("artifakt", cl_a, ros), arm_row("degenerate", cl_z, ros))
arm_rows$rail_pass <- c(
  as.integer(identical(mean(mch(cl_c, ros)), 1)),
  as.integer(identical(med_j[1L:3L], c(0L, 1L, 0L))),
  as.integer(never_merge),
  as.integer(identical(as.integer(cl_z$cluster_size[ZERO_MEMBER]), 1L)))

ok_payload <-
  all(per_rows$match %in% 0:1) && all(per_rows$is_medoid %in% 0:1) &&
  all(grepl("^C[1-9][0-9]*$", per_rows$cluster)) &&
  all(is.finite(per_rows$cluster_size) & per_rows$cluster_size >= 1L) &&
  all(is.finite(arm_rows$roster_share) & arm_rows$roster_share >= 0 &
        arm_rows$roster_share <= 1) &&
  all(as.integer(arm_rows$n_clusters) >= 1L) &&
  all(as.integer(arm_rows$n_medoids) >= 1L) &&
  all(arm_rows$threshold_line == CITED_LINE) &&
  all(is.finite(lad$share_pass) & lad$share_pass >= 0 & lad$share_pass <= 1) &&
  all(lad$is_pass %in% 0:1) &&
  all(ros$cluster_size >= 1L) && all(ros$is_medoid %in% 0:1)
if (!ok_payload) {
  cat("  FAIL witness payload census (refusing to commit an unlive column)\n")
  verdict$fail <- verdict$fail + 1L
}

dir.create(OUT, showWarnings = FALSE)
write.csv(ros, file.path(OUT, "cs8_roster.csv"), row.names = FALSE)
write.csv(per_rows, file.path(OUT, "cs8_per_member.csv"), row.names = FALSE)
write.csv(arm_rows, file.path(OUT, "cs8_arms.csv"), row.names = FALSE)
write.csv(lad, file.path(OUT, "cs8_ladder.csv"), row.names = FALSE)
write.csv(data.frame(
  sigs = paste(SIG, collapse = ","),
  copies = paste0(COPIES, collapse = ","),
  members = paste(MEMBERS, collapse = ","),
  cited_line = CITED_LINE,
  rot_unit = ROT_UNIT,
  jit = JIT,
  jit_channels = paste0(JIT_CH, collapse = ","),
  zero_member = ZERO_MEMBER,
  art_fam = ART_FAM,
  rung_values = paste0(RUNGS, collapse = ","),
  n_rows = NR,
  last_full_pass_rung = if (is.na(last_pass)) NA_character_ else format(last_pass),
  stringsAsFactors = FALSE),
  file.path(OUT, "cs8_scalars.csv"), row.names = FALSE)
write.table(data.frame(
  check = c("clean_share_one", "artifakt_never_merge", "jitter_medoid_strict",
            "zero_col_singleton", "zero_nan_cells", "thr_abort_input"),
  value = c(
    as.integer(identical(mean(mch(cl_c, ros)), 1)),
    as.integer(never_merge),
    as.integer(identical(med_j[1L:3L], c(0L, 1L, 0L)) &&
                  means1[2L] > max(means1[1L], means1[3L]) + 1e-4),
    as.integer(identical(as.integer(cl_z$cluster_size[ZERO_MEMBER]), 1L) &&
                  isTRUE(cl_z$is_medoid[ZERO_MEMBER])),
    as.integer(nan_cells),
    as.integer(inherits(e0, "msuiter_error_input"))),
  stringsAsFactors = FALSE),
  file.path(OUT, "cs8_degenerates.tsv"), sep = "\t", quote = FALSE,
  row.names = FALSE, col.names = TRUE)

cat("== cs8 cluster-witness scenario: ",
    if (identical(verdict$fail, 0L)) "OVERALL PASS" else "OVERALL FAIL",
    " == (evidence: ", OUT, ")\n", sep = "")
quit(save = "no", status = if (identical(verdict$fail, 0L)) 0L else 1L)
