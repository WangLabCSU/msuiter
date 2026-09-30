# Islam 2022 protocol reproduction (ROADMAP M2 acceptance item): the
# greedy max-cosine >= 0.90 evaluation semantics, driven through the
# match_solutions sweep (consensus.rs, memo section 1.5) on a constructed
# truth with known matched / split / merge / novel estimates.
#
# The estimates are built from orthogonal unit bases so every cosine is
# exactly designable in-test (no numerical surprises at the 0.90
# boundary), and the classification vectors are asserted per threshold —
# a semantic regression in split/merge/novel logic cannot hide.

test_that("Islam greedy protocol reproduces on a designed truth", {
  ch <- 96L
  unit_vec <- function(idx) {
    v <- numeric(ch)
    v[idx] <- 1
    v / sqrt(sum(v^2))
  }
  # T1 and T2 are CORRELATED (cos = 0.8, the SBS5/40 flat-pair structure):
  # a non-negative merge of two unit references with both cosines >= 0.90
  # is only reachable when the references themselves correlate (with
  # orthogonal references, cos(m,T1)^2 + cos(m,T2)^2 <= 1 makes the merge
  # class unreachable). T3 is orthogonal to both.
  e2 <- unit_vec(33:64)
  t1 <- unit_vec(1:32)
  t2 <- 0.8 * t1 + 0.6 * e2
  t3 <- unit_vec(65:96)

  # Estimates: three exact copies (matched), one 0.92 fragment of T1
  # (top-1 = 0.92 >= tau, top-2 = 0.736 < tau -> split), one merge of
  # T1+T2 (cosines 0.978 / 0.908, both >= tau -> merge), one orthogonal
  # novel vector.
  f <- 0.92 * t1 + 0.426 * unit_vec(90:96)
  m <- t1 + 0.5 * t2
  m <- m / sqrt(sum(m^2))
  n <- unit_vec(90:96)
  est <- cbind(t1, t2, t3, f, m, n)
  ref <- cbind(t1, t2, t3)

  taus <- c(0.80, 0.85, 0.90, 0.95)
  res <- ms_match_solutions_rust(
    estimated = as.numeric(t(est)),
    reference = as.numeric(t(ref)),
    dim = ch,
    thresholds = taus
  )

  # Sweep rows: 4 thresholds x 6 estimates = 24 classification rows.
  expect_identical(length(res$estimated_class), 24L)

  # Slice helper: the flat classification vectors are p_per_threshold rows
  # per threshold, in sweep order.
  block <- function(tau) {
    i <- which(res$threshold == tau)
    from <- if (i == 1L) 1L else sum(res$p_per_threshold[seq_len(i - 1L)]) + 1L
    to <- from + res$p_per_threshold[i] - 1L
    seq.int(from, to)
  }
  expect_class <- function(tau, want) {
    rows <- block(tau)
    got <- res$estimated_class[rows]
    expect_identical(got, want)
    invisible(res$reference_index[rows])
  }

  # tau = 0.90: copies matched, fragment splits, merge merges, novel.
  refs <- expect_class(
    0.90,
    c("matched", "matched", "matched", "split", "merge", "novel")
  )
  # Split target = T1 (estimate 4 -> reference 1); merge argmax = T1
  # (estimate 5 -> reference 1); novel carries no reference (0).
  expect_identical(refs[4L], 1L)
  expect_identical(refs[5L], 1L)
  expect_identical(refs[6L], 0L)

  # tau = 0.80/0.85: same classes (fragment 0.92 and merge 0.978/0.908
  # clear both thresholds).
  invisible(expect_class(
    0.80,
    c("matched", "matched", "matched", "split", "merge", "novel")
  ))
  invisible(expect_class(
    0.85,
    c("matched", "matched", "matched", "split", "merge", "novel")
  ))

  # tau = 0.95: the fragment (top-1 = 0.92) and the merge (top-1 = 0.978,
  # top-2 = 0.908) drop below tau on their top-1/top-2 respectively: the
  # fragment turns novel, while the merge degrades to a split of T1
  # (top-1 still >= tau); the three exact copies stay matched.
  invisible(expect_class(
    0.95,
    c("matched", "matched", "matched", "novel", "split", "novel")
  ))

  # Count semantics: tau = 0.90 gives tp = 3, fp = 3 (split+merge+novel),
  # fn = 0 (every reference matched).
  r90 <- which(res$threshold == 0.90)[1L]
  expect_identical(res$tp[[r90]], 3L)
  expect_identical(res$fp[[r90]], 3L)
  expect_identical(res$fn[[r90]], 0L)

  # Greedy-protocol cross-check (Islam compatibility): the greedy
  # max-cosine labels recomputed in R must map 1:1 onto the kernel
  # reference indices for this designed truth.
  est_units <- sweep(est, 2L, sqrt(colSums(est^2)), "/")
  cos_mat <- crossprod(est_units, ref)
  greedy <- apply(cos_mat, 1L, function(row) {
    mx <- max(row)
    if (mx >= 0.90) which(row == mx)[1L] else 0L
  })
  rows90 <- block(0.90)
  expect_identical(res$reference_index[rows90], as.integer(unname(greedy)))
})
