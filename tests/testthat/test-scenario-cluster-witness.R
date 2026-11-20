# test-scenario-cluster-witness.R -- the CS-8 cluster-witness law units
# (pillar 3). The scenario plants a nine-column SBS96 cohort of exact
# duplicate families drawn from the bundled GRCh37 bytes and adjudicates
# the EXPORTED threshold-graph face ms_cluster_signatures -- connected
# components of the cosine->= threshold graph with size-descending relabel
# and mean-cosine medoids -- under five arms (clean, jitter, artifakt,
# degenerate, ladder). The witness bytes under bench/scenarios/out/ are the
# committed verdict: a drift in the generator, the union-find pass, the
# relabel law, or the medoid rule reddens here before print. The whole
# scenario is RNG-free -- there is no seed to pin and no draw to re-roll.
# Framing law: DECISION RECORD only. The face's documented discriminative
# behavior (the clean partition survives the rung sweep, the planted
# corruption splinters the family, the ladder's committed last-pass rung)
# is an OBSERVED, COMMITTED fact -- never a calibration claim: 0.90 is the
# face's shipped default cited from its documentation, not an anchor, and
# cosine above it remains necessary-not-sufficient (R/ms-cluster.R header).
# The hard rails are the two share rails (clean arm share == 1, the
# untouched members of the artifakt arm keep it), the splinter rail (the
# scrambled pair never shares a cluster at any rung), the singleton law of
# the zero column, and the monotone law on the ladder. No new estimation
# machinery, no sanity harness, no bootstrap, no intervals -- the declined
# rails are spoken by the runner itself ([attest] rails) and grepped here.
# The pillar-2 idiom of reaching the internal helper directly (msuiter:::)
# is BANNED here and grepped away; the shipped default is pinned straight
# off the exported formals surface, so this law never reaches inside.

.rs_out <- function(fname) {
  file.path(.ms_root, "bench", "scenarios", "out", fname)
}

.rs_csv <- function(fname) {
  read.csv(.rs_out(fname), header = TRUE, stringsAsFactors = FALSE)
}

.rs_tsv <- function(fname) {
  read.csv(.rs_out(fname), header = TRUE, sep = "\t", stringsAsFactors = FALSE)
}

# Frozen scenario constants -- mirrored byte-identically in
# bench/scenarios/run_cluster_witness.R (single source of truth is the
# pair of files; a drift reddens the scalars unit below).
.CS8_SIG <- c("SBS1", "SBS2", "SBS13", "SBS88")
.CS8_COPIES <- c(3L, 2L, 2L, 2L)                    # planted family sizes
.CS8_MEMBERS <- c("F1a", "F1b", "F1c", "F2a", "F2b",
                  "F3a", "F3b", "F4a", "F4b")
.CS8_NMEM <- 9L
.CS8_CITED_LINE <- 0.90        # the face's shipped default: cited, not anchored
.CS8_ROT_UNIT <- 37L           # channel-rotation scrambler (measured cos <= 0.052)
.CS8_JIT <- 0.01              # jitter mass on the strict-medoid family
.CS8_JIT_CH <- c(11L, 59L, 35L, 83L)  # SBS1 peak channels (masses >= 0.110)
.CS8_ZERO_MEMBER <- 7L         # the all-zero column (F3b)
.CS8_ART_FAM <- 2L             # the scrambled family
.CS8_RUNGS <- c(0, 0.10, 0.15, 0.20, 0.23, 0.26, 0.35, 0.50)
# Shared contract of the match bit (runner and law, byte-same meaning):
# a member matches iff its observed cluster label AND its observed
# cluster size both equal the committed roster's. Label equality alone
# deceives -- the ascending-root label law can reissue a survivor's old
# label over a broken structure (the zero-arm witness is that proof).

# The dictionary: bundled bytes only (never downloaded), columns
# normalized to sum 1 in the canonical channel order.
.cs8_dict <- function() {
  refdb <- ms_refdb_bundled(build = "GRCh37")
  mat <- refdb[["SBS_GRCh37"]]@matrices[[1L]]
  dict <- mat[, .CS8_SIG, drop = FALSE]
  sweep(dict, 2L, colSums(dict), "/")
}

# The cyclic channel rotation used by the scrambler and the ladder.
.cs8_rot <- function(v, rot) {
  n <- length(v)
  v[((seq_len(n) + rot - 1L) %% n) + 1L]
}

# The planted clean cohort: each family is COPIES[f] exact copies of its
# dictionary column, so the known-truth partition is the family map.
.cs8_matrix <- function() {
  dict <- .cs8_dict()
  cols <- list()
  for (f in seq_along(.CS8_SIG)) {
    for (k in seq_len(.CS8_COPIES[f])) {
      cols[length(cols) + 1L] <- list(dict[, .CS8_SIG[f], drop = TRUE])
    }
  }
  out <- do.call(cbind, cols)
  dimnames(out) <- list(rownames(.cs8_dict()), .CS8_MEMBERS)
  out
}

# The artifakt cohort: family 2's two columns replaced by channel-rotated
# twins (37 and 2*37 places) -- near-orthogonal to every clean column and
# to each other (measured worst cross 0.0114 at the pre-write gate).
.cs8_art_matrix <- function() {
  S <- .cs8_matrix()
  base <- .cs8_dict()[, .CS8_SIG[.CS8_ART_FAM], drop = TRUE]
  S[, "F2a"] <- .cs8_rot(base, .CS8_ROT_UNIT)
  S[, "F2b"] <- .cs8_rot(base, 2L * .CS8_ROT_UNIT)
  S
}

# The jitter cohort: family 1's three copies get opposed channel shifts so
# the CENTRE member (F1b, the untouched base) is the strict mean-cosine
# winner -- the medoid is won, not tie-won.
.cs8_jit_matrix <- function() {
  S <- .cs8_matrix()
  base <- .cs8_dict()[, .CS8_SIG[1L], drop = TRUE]
  shift <- function(v, p, q, sign) {
    v[p] <- v[p] + sign * .CS8_JIT
    v[q] <- v[q] - sign * .CS8_JIT
    v
  }
  S[, "F1a"] <- shift(base, .CS8_JIT_CH[1L], .CS8_JIT_CH[2L], -1)
  S[, "F1c"] <- shift(base, .CS8_JIT_CH[3L], .CS8_JIT_CH[4L], 1)
  S
}

# The degenerate cohort: member 7 (F3b) zeroed -- the face's finite guard
# must hold it out of every graph edge, making it a lawful singleton.
.cs8_zero_matrix <- function() {
  S <- .cs8_matrix()
  S[, .CS8_ZERO_MEMBER] <- 0
  S
}

# The ladder cohort: every member blended toward its own rotated twin by
# rung w; family twin cosines decay smoothly past the cited line.
.cs8_blend <- function(w) {
  S <- .cs8_matrix()
  for (m in seq_len(.CS8_NMEM)) {
    rot <- (.CS8_ROT_UNIT * m) %% 96L
    S[, m] <- (1 - w) * S[, m] + w * .cs8_rot(S[, m], rot)
  }
  S
}

# Hand-written cosine (the dual-derivation leg): plain portable arithmetic
# only, mirroring the shipped scalar's mathematics, not its code.
.cs8_cos <- function(x, y) {
  nx <- sqrt(sum(x * x))
  ny <- sqrt(sum(y * y))
  if (nx == 0 || ny == 0) {
    return(NA_real_)
  }
  sum(x * y) / (nx * ny)
}

# Hand-computed connected-component partition with the face's MEASURED
# labeling behaviour (the shipped pass's size-sort round-trips to labels
# C1.. in ascending-root order -- the zero-arm witness proves it: the two
# size-1 singletons of the split family take labels ahead of the size-2
# pair; measured, and this engine mirrors R/ms-cluster.R:116-156's
# structure, not its header comment). Medoid = max mean within-cluster
# cosine SELF-EXCLUSIVE (mirrors :149-152), ties by which.max = first
# member. Independent re-derivation of the shipped algorithm from its
# measured contract -- the dual-derivation engine.
.cs8_cc <- function(S, threshold) {
  k <- ncol(S)
  hand <- matrix(NA_real_, nrow = k, ncol = k)
  for (i in seq_len(k)) for (j in seq_len(k)) {
    hand[i, j] <- .cs8_cos(S[, i], S[, j])
  }
  parent <- seq_len(k)
  find <- function(x) {
    while (parent[x] != x) {
      parent[x] <- parent[parent[x]]
      x <- parent[x]
    }
    x
  }
  for (i in seq_len(k - 1L)) for (j in (i + 1L):k) {
    if (is.finite(hand[i, j]) && hand[i, j] >= threshold) {
      ri <- find(i)
      rj <- find(j)
      if (ri != rj) parent[rj] <- ri
    }
  }
  roots <- unname(vapply(seq_len(k), find, integer(1L)))
  labs <- paste0("C", as.integer(factor(roots)))   # ascending-root labels
  medoid <- rep(FALSE, k)
  for (cl in unique(labs)) {
    members <- which(labs == cl)
    if (length(members) == 1L) {
      medoid[members] <- TRUE
      next
    }
    means <- vapply(members, function(a) {
      mean(hand[a, setdiff(members, a)])
    }, numeric(1L))
    medoid[members[which.max(means)]] <- TRUE
  }
  list(cluster = unname(labs), is_medoid = medoid,
       cluster_size = as.integer(table(labs)[as.character(labs)]))
}

test_that("the CS-8 runner speaks the committed scenario shape", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  f <- file.path(.ms_root, "bench", "scenarios", "run_cluster_witness.R")
  expect_true(file.exists(f))
  src <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_true(grepl("--file=", src, fixed = TRUE))
  expect_true(grepl("quit(", src, fixed = TRUE))
  expect_true(grepl("OVERALL PASS", src, fixed = TRUE))
  expect_true(grepl("[attest]", src, fixed = TRUE))
  expect_true(grepl("ms_cluster_signatures", src, fixed = TRUE))
  expect_true(grepl("ms_refdb_bundled", src, fixed = TRUE))
  expect_true(grepl("DECISION RECORD", src, fixed = TRUE))
  # Rail 2, spoken by absence: the pillar-2 internal-helper idiom is
  # banned from the scenario and its law alike.
  expect_false(grepl("msuiter:::", src, fixed = TRUE))
  # Declined rails made audible in the runner itself.
  expect_true(grepl("conformal", src, fixed = TRUE))
  expect_true(grepl("calibrate-real", src, fixed = TRUE))
})

test_that("the scalars witness pins the frozen scenario constants", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  scal <- .rs_csv("cs8_scalars.csv")
  expect_identical(nrow(scal), 1L)
  expect_identical(as.character(scal$sigs), paste(.CS8_SIG, collapse = ","))
  expect_identical(as.character(scal$copies),
                   paste0(.CS8_COPIES, collapse = ","))
  expect_identical(as.character(scal$members),
                   paste(.CS8_MEMBERS, collapse = ","))
  expect_identical(as.numeric(scal$cited_line), .CS8_CITED_LINE)
  expect_identical(as.integer(scal$rot_unit), as.integer(.CS8_ROT_UNIT))
  expect_identical(as.numeric(scal$jit), .CS8_JIT)
  expect_identical(as.character(scal$jit_channels),
                   paste0(.CS8_JIT_CH, collapse = ","))
  expect_identical(as.integer(scal$zero_member), as.integer(.CS8_ZERO_MEMBER))
  expect_identical(as.integer(scal$art_fam), as.integer(.CS8_ART_FAM))
  expect_identical(as.character(scal$rung_values),
                   paste0(.CS8_RUNGS, collapse = ","))
  expect_identical(as.integer(scal$n_rows), 96L)
  # the shipped line itself, straight from the exported face's formals
  expect_identical(eval(formals(ms_cluster_signatures)$threshold),
                    .CS8_CITED_LINE)
})

test_that("the planted cohort re-derives byte-exactly, dual-derivation EXACT", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  ros <- .rs_csv("cs8_roster.csv")
  expect_identical(names(ros),
                   c("member", "cluster", "is_medoid", "cluster_size"))
  expect_identical(as.character(ros$member), .CS8_MEMBERS)
  S <- .cs8_matrix()
  fresh <- ms_cluster_signatures(S, threshold = .CS8_CITED_LINE)
  # leg one: a fresh call through the exported face against the bytes
  expect_identical(as.character(fresh$cluster), as.character(ros$cluster))
  expect_identical(as.integer(fresh$is_medoid),
                   as.integer(ros$is_medoid))
  expect_identical(as.integer(fresh$cluster_size),
                   as.integer(ros$cluster_size))
  # leg two: the hand-computed partition (independent implementation)
  hand <- .cs8_cc(S, .CS8_CITED_LINE)
  expect_identical(hand$cluster, as.character(ros$cluster))
  expect_identical(as.integer(hand$is_medoid), as.integer(ros$is_medoid))
  expect_identical(as.integer(hand$cluster_size),
                   as.integer(ros$cluster_size))
  # the family map IS the planted truth: same family iff same cluster
  fam <- rep(seq_along(.CS8_SIG), .CS8_COPIES)
  same_fam <- outer(fam, fam, "==")
  same_clu <- outer(as.character(ros$cluster), as.character(ros$cluster), "==")
  expect_identical(same_clu, same_fam)
})

test_that("the clean arm holds its hard rail: every member matches the roster", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  per <- .rs_csv("cs8_per_member.csv")
  arms <- .rs_csv("cs8_arms.csv")
  clean <- per[per$arm == "clean", , drop = FALSE]
  expect_identical(as.character(clean$member), .CS8_MEMBERS)
  # hard rail: an honest cohort censuses every member on the committed
  # partition -- share == 1 admits no slack
  expect_identical(as.integer(clean$match), rep(1L, .CS8_NMEM))
  ros <- .rs_csv("cs8_roster.csv")
  expect_identical(as.character(clean$cluster), as.character(ros$cluster))
  clean_row <- arms[arms$arm == "clean", , drop = FALSE]
  expect_identical(as.integer(clean_row$roster_share), 1L)
  expect_identical(as.integer(clean_row$rail_pass), 1L)
  expect_identical(as.integer(clean_row$n_clusters), 4L)
  expect_identical(as.integer(clean_row$n_medoids), 4L)
  # the tie law on display: the exact-duplicate family's medoid is its
  # FIRST member (observed committed fact, re-derived by hand above)
  fam1 <- clean[substr(clean$member, 1L, 2L) == "F1", , drop = FALSE]
  expect_identical(as.integer(fam1$is_medoid), c(1L, 0L, 0L))
})

test_that("the jitter arm wins its medoid strictly, not by tie", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  per <- .rs_csv("cs8_per_member.csv")
  jit <- per[per$arm == "jitter", , drop = FALSE]
  expect_identical(as.character(jit$member), .CS8_MEMBERS)
  ros <- .rs_csv("cs8_roster.csv")
  fam1 <- jit[substr(jit$member, 1L, 2L) == "F1", , drop = FALSE]
  # the CENTRE member (base, index 2 of the family) is the sole medoid:
  # the mean-cosine computation adjudicates, not the first-member tie law
  expect_identical(as.integer(fam1$is_medoid), c(0L, 1L, 0L))
  # the family stays one cluster and keeps its committed label
  expect_identical(as.character(fam1$cluster),
                   as.character(ros$cluster[substr(ros$member, 1L, 2L) == "F1"]))
  # the other families keep the committed roster exactly
  rest <- jit[substr(jit$member, 1L, 2L) != "F1", , drop = FALSE]
  ros_rest <- ros[substr(ros$member, 1L, 2L) != "F1", , drop = FALSE]
  expect_identical(as.character(rest$cluster), as.character(ros_rest$cluster))
  expect_identical(as.integer(rest$is_medoid), as.integer(ros_rest$is_medoid))
  # fresh re-derivation: the strict winner stands and the margin is real
  fresh <- ms_cluster_signatures(.cs8_jit_matrix(), threshold = .CS8_CITED_LINE)
  expect_identical(as.integer(fresh$is_medoid[fresh$signature %in%
                                              c("F1a", "F1b", "F1c")]),
                   c(0L, 1L, 0L))
  S <- .cs8_jit_matrix()
  m1 <- .cs8_cos(S[, 1], S[, 2]); m1b <- .cs8_cos(S[, 1], S[, 3])
  m2 <- .cs8_cos(S[, 2], S[, 3])
  mean1 <- (m1 + m1b) / 2
  mean2 <- (m1 + m2) / 2
  mean3 <- (m1b + m2) / 2
  expect_true(mean2 > max(mean1, mean3))          # strict, measured margin
})

test_that("the artifakt arm splinters its family at every rung", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  per <- .rs_csv("cs8_per_member.csv")
  arms <- .rs_csv("cs8_arms.csv")
  art <- per[per$arm == "artifakt", , drop = FALSE]
  expect_identical(as.character(art$member), .CS8_MEMBERS)
  ros <- .rs_csv("cs8_roster.csv")
  # the scrambled pair matches the committed roster on NEITHER member
  art2 <- art[art$member %in% c("F2a", "F2b"), , drop = FALSE]
  expect_identical(as.integer(art2$match), c(0L, 0L))
  # ... and the seven untouched members keep it all (the rail's bite)
  art7 <- art[!art$member %in% c("F2a", "F2b"), , drop = FALSE]
  ros7 <- ros[!ros$member %in% c("F2a", "F2b"), , drop = FALSE]
  expect_identical(as.integer(art7$match), rep(1L, 7L))
  # cluster LABELS renumber globally when a family splinters (ascending-
  # root law), so structural equality is the size + co-membership, not the
  # label string -- assert the invariant that survives relabeling.
  expect_identical(as.integer(art7$cluster_size),
                   as.integer(ros7$cluster_size))
  # splinter rail: the scrambled pair is lawful singletons at every
  # swept threshold (0.10 .. cited line) -- never each other, never the
  # bulk of any family -- fresh re-derivation through the exported face
  A <- .cs8_art_matrix()
  for (thr in c(.CS8_RUNGS[-1L], .CS8_CITED_LINE)) {
    ca <- ms_cluster_signatures(A, threshold = thr)
    ia <- which(ca$signature == "F2a")
    ib <- which(ca$signature == "F2b")
    expect_identical(ia, 4L)
    expect_identical(ib, 5L)
    expect_identical(as.integer(ca$cluster_size[c(ia, ib)]), c(1L, 1L))
    expect_false(ca$cluster[ia] == ca$cluster[ib])
  }
  art_row <- arms[arms$arm == "artifakt", , drop = FALSE]
  expect_identical(as.integer(art_row$n_medoids), 5L)
  expect_identical(as.integer(art_row$rail_pass), 1L)
})

test_that("the zero column speaks its singleton law", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  per <- .rs_csv("cs8_per_member.csv")
  arms <- .rs_csv("cs8_arms.csv")
  deg <- per[per$arm == "degenerate", , drop = FALSE]
  expect_identical(as.character(deg$member), .CS8_MEMBERS)
  zero_row <- deg[deg$member == .CS8_MEMBERS[.CS8_ZERO_MEMBER], , drop = FALSE]
  expect_identical(as.integer(zero_row$cluster_size), 1L)
  expect_identical(as.integer(zero_row$is_medoid), 1L)
  expect_identical(as.integer(zero_row$match), 0L)
  # its former family twin keeps a lawful singleton too (the family of one)
  twin_row <- deg[deg$member == "F3a", , drop = FALSE]
  expect_identical(as.integer(twin_row$cluster_size), 1L)
  expect_identical(as.integer(twin_row$is_medoid), 1L)
  expect_identical(as.integer(twin_row$match), 0L)   # size broke: structural
  # the seven surviving members keep the committed verdict -- structural
  # equality (size + match bit), never label strings: the two lawful
  # singletons renumber every downstream label (ascending-root law)
  deg7 <- deg[!deg$member %in% c("F3a", "F3b"), , drop = FALSE]
  ros <- .rs_csv("cs8_roster.csv")
  ros7 <- ros[!ros$member %in% c("F3a", "F3b"), , drop = FALSE]
  expect_identical(as.integer(deg7$cluster_size),
                   as.integer(ros7$cluster_size))
  expect_identical(as.integer(deg7$match), rep(1L, 7L))
  # fresh re-derivation: the zero column is a lawful singleton and its
  # cosine rows/cols are exactly the 17 NaN cells (9+9-1)
  fresh <- ms_cluster_signatures(.cs8_zero_matrix(), threshold = .CS8_CITED_LINE)
  zi <- which(fresh$signature == .CS8_MEMBERS[.CS8_ZERO_MEMBER])
  expect_identical(zi, .CS8_ZERO_MEMBER)
  expect_true(unname(fresh$is_medoid[zi]))
  cm <- attr(fresh, "cosines")
  expect_identical(sum(is.nan(cm)), 17L)
  deg_row <- arms[arms$arm == "degenerate", , drop = FALSE]
  expect_identical(as.integer(deg_row$n_medoids), 5L)
})

test_that("the corruption ladder is monotone and its last-pass rung is committed", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  lad <- .rs_csv("cs8_ladder.csv")
  expect_identical(names(lad),
                   c("rung", "n_clusters", "n_medoids", "share_pass", "is_pass"))
  expect_identical(as.numeric(lad$rung), .CS8_RUNGS)
  shares <- as.numeric(lad$share_pass)
  expect_true(all(diff(shares) <= 0))                        # non-increasing
  expect_identical(shares[1L], 1)                            # rung 0 is clean
  expect_identical(as.integer(lad$is_pass), as.integer(shares == 1))
  last_pass <- max(as.numeric(lad$rung[lad$is_pass == 1L]))
  scal <- .rs_csv("cs8_scalars.csv")
  expect_identical(as.numeric(scal$last_full_pass_rung), last_pass)
  expect_true(last_pass > 0 && last_pass < .CS8_RUNGS[length(.CS8_RUNGS)])
  # dual-derivation at the two decisive rungs: rung 0 re-derives the whole
  # committed roster (hand engine), the tail censuses all-singletons/share-0
  hand0 <- .cs8_cc(.cs8_blend(0), .CS8_CITED_LINE)
  ros <- .rs_csv("cs8_roster.csv")
  expect_identical(hand0$cluster, as.character(ros$cluster))
  tail_cl <- ms_cluster_signatures(.cs8_blend(.CS8_RUNGS[8L]),
                                   threshold = .CS8_CITED_LINE)
  expect_identical(length(unique(tail_cl$cluster)), .CS8_NMEM)
  tail_row <- lad[abs(as.numeric(lad$rung) - .CS8_RUNGS[8L]) < 1e-12, , drop = FALSE]
  expect_identical(as.integer(tail_row$n_clusters), .CS8_NMEM)
  expect_identical(as.integer(tail_row$share_pass), 0L)
})

test_that("the witness payload census: every column alive and in-domain", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  per <- .rs_csv("cs8_per_member.csv")
  expect_identical(names(per),
                   c("member", "arm", "cluster", "is_medoid",
                     "cluster_size", "match"))
  expect_true(all(as.character(per$is_medoid) %in% c("0", "1")))
  expect_true(all(as.character(per$match) %in% c("0", "1")))
  expect_true(all(grepl("^C[1-9][0-9]*$", as.character(per$cluster))))
  expect_true(all(is.finite(as.numeric(per$cluster_size))))
  expect_true(all(as.numeric(per$cluster_size) >= 1L))
  expect_false(any(is.na(as.numeric(per$is_medoid))))
  expect_false(any(is.na(as.numeric(per$match))))
  arms <- .rs_csv("cs8_arms.csv")
  expect_identical(names(arms),
                   c("arm", "threshold_line", "n_clusters", "n_medoids",
                     "roster_share", "rail_pass"))
  expect_true(all(as.numeric(arms$threshold_line) == .CS8_CITED_LINE))
  expect_true(all(is.finite(as.numeric(arms$n_clusters)) &
                    as.numeric(arms$n_clusters) >= 1L))
  expect_true(all(is.finite(as.numeric(arms$n_medoids)) &
                    as.numeric(arms$n_medoids) >= 1L))
  expect_true(all(as.numeric(arms$roster_share) >= 0 &
                    as.numeric(arms$roster_share) <= 1))
  expect_true(all(as.character(arms$rail_pass) %in% c("0", "1")))
  lad <- .rs_csv("cs8_ladder.csv")
  expect_true(all(is.finite(as.numeric(lad$share_pass))))
  expect_true(all(as.numeric(lad$share_pass) >= 0 &
                    as.numeric(lad$share_pass) <= 1))
  expect_true(all(as.character(lad$is_pass) %in% c("0", "1")))
})

test_that("the degenerate side facts speak", {
  if (is.na(.ms_root)) skip("repository checkout not locatable")
  deg <- .rs_tsv("cs8_degenerates.tsv")
  expect_identical(names(deg), c("check", "value"))
  vals <- setNames(deg$value, deg$check)
  expect_identical(as.integer(vals[["clean_share_one"]]), 1L)
  expect_identical(as.integer(vals[["artifakt_never_merge"]]), 1L)
  expect_identical(as.integer(vals[["jitter_medoid_strict"]]), 1L)
  expect_identical(as.integer(vals[["zero_col_singleton"]]), 1L)
  expect_identical(as.integer(vals[["zero_nan_cells"]]), 17L)
  expect_identical(as.integer(vals[["thr_abort_input"]]), 1L)
})
