# Lane PERF-P10, P10-A BIT-IDENTITY ATTESTATION LAW.
#
# The observer elimination may move the ceremony, never the numbers: for
# the attested-geometry set -- the frozen fa2 bytes (raw counts face plus
# the VERBATIM sigminer bootstrapped inputs, the whole PF census grid:
# 4 bootstraps x ranks k 2:5 = 16 true-geometry tasks, plus the raw face
# per k) -- the fit results of the protocol-1 era and of the two
# protocol-2 faces must be byte-identical where the contract says so.
#
# Faces (identical argv, only binary/flag differ):
#   F1  the banked BEFORE binary, its default face (protocol-1 bytes:
#       the full walk; the binary is re-hashed against the banked digest
#       before use -- evidence drift is a gate failure, never a pass);
#   F2  the working-tree binary with --full-trace (the opted-in ceremony);
#   F3  the working-tree binary's production face (the endpoints pair).
# Law per task, all digests code-produced through the governed sha256
# kernel (never hand-typed):
#   sha256(W.csv) and sha256(H.csv) equal across F1 = F2 = F3;
#   F1/F2 trace.csv bytes equal; F3 trace.csv is the header plus F2's
#   row at t = 0 and F2's last row;
#   the meta witnesses protocol/init/seed/iterations/obj_init/obj_final
#   are the same strings on all faces, trace_len self-describing
#   (2001 / 2001 / 2 at the attested iteration count);
#   the full walk is monotone non-increasing under the committed
#   convention (slack 1e-9 * (1 + |previous|) -- the nmf.rs assert_monotone
#   idiom, the g2_zero_lock twin).
# Dead-metric controls: a faithful rerun reproduces every digest (the
# census speaks true on perfect bytes); a one-observation V mutation
# breaks the W equality (the census speaks false on broken bytes).
#
# Gate: the local attestation evidence (banked before-binary + digest,
# frozen fa2 bytes + banked digest). Absent -- the CI context -- the
# unit skips with a spoken reason; present -- drift stops the lane.

test_that("P10-A the attested-geometry faces are byte-identical, with the
           census controls firing", {
  ev <- .kbg_ev()
  if (is.null(ev)) .kbg_skip()
  expect_identical(.kbg_sha(ev$before), .kbg_banked_digest(ev$digest))
  bin <- .kpp_bin()
  hs <- .kpp_exec_real(bin, "--version")
  expect_identical(hs$rc, 0L)
  expect_match(paste(hs$stdout, collapse = " "), "protocol=1")
  ITERS <- 2000L                            # the attested face's scale
  X <- .kbg_X(ev)
  tasks <- list()
  for (k in 2:5L) {
    tasks[[length(tasks) + 1L]] <- list(tag = paste0("fa2-k", k), V = X,
                                        seed = 123L, k = as.integer(k))
  }
  for (b in 1:4L) {
    V <- .kbg_boot(ev, b)
    for (k in 2:5L) {
      tasks[[length(tasks) + 1L]] <- list(tag = paste0("boot", b, "-k", k),
                                          V = V, seed = 123L + b - 1L,
                                          k = as.integer(k))
    }
  }
  expect_gte(length(tasks), 20L)
  # The bootstrap is live: the bootstrapped face is not the raw face and
  # the per-boot seed law keeps the boots apart (an inert replication
  # would collapse these before any digest is ever read).
  expect_false(identical(.kbg_boot(ev, 1L), X))
  expect_false(identical(.kbg_boot(ev, 1L), .kbg_boot(ev, 2L)))
  boot.fractions <- vapply(1:4L, function(b) .kbg_zero_frac(.kbg_boot(ev, b)),
                            numeric(1L), USE.NAMES = FALSE)
  expect_true(all(boot.fractions > 0.9 & boot.fractions < 1))
  n.attest <- 0L
  for (t in tasks) {
    in.dir <- .kbg_stage_single(tempfile(paste0("bi-", t$tag, "-in-")), t$V)
    fit <- function(binary, out.dir, extra = character(0)) {
      res <- .kpp_exec_real(binary, c(.kbg_single_argv(in.dir, out.dir,
                                                       96L, 100L, t$k,
                                                       ITERS, t$seed),
                                       extra))
      if (!identical(res$rc, 0L)) {
        stop("attestation fit died: ", t$tag, " rc=", res$rc, ": ",
             paste(res$stderr, collapse = " | "), call. = FALSE)
      }
      out.dir
    }
    d1 <- fit(ev$before, tempfile("bi-f1-"))
    d2 <- fit(bin, tempfile("bi-f2-"), "--full-trace")
    d3 <- fit(bin, tempfile("bi-f3-"))
    # W/H: the factors are the fact.
    for (f in c("W.csv", "H.csv")) {
      s1 <- .kbg_sha(file.path(d1, f))
      s2 <- .kbg_sha(file.path(d2, f))
      s3 <- .kbg_sha(file.path(d3, f))
      expect_identical(s2, s1, info = paste(t$tag, f, "full-vs-before"))
      expect_identical(s3, s1, info = paste(t$tag, f, "ends-vs-before"))
    }
    n.attest <- n.attest + 2L
    # Trace bytes: F1 = F2 verbatim; F3 = header + the two endpoint rows.
    tr1 <- readLines(file.path(d1, "trace.csv"), warn = FALSE)
    tr2 <- readLines(file.path(d2, "trace.csv"), warn = FALSE)
    tr3 <- readLines(file.path(d3, "trace.csv"), warn = FALSE)
    tr1 <- tr1[nzchar(tr1)]; tr2 <- tr2[nzchar(tr2)]; tr3 <- tr3[nzchar(tr3)]
    expect_identical(tr2, tr1, info = paste(t$tag, "trace-bytes"))
    expect_identical(tr3, tr1[c(1L, 2L, length(tr1))],
                     info = paste(t$tag, "trace-endpoints"))
    expect_false(identical(tr3, tr1), info = paste(t$tag, "faces-trivial"))
    n.attest <- n.attest + 1L
    # Meta witnesses: the same strings on all faces; trace_len speaks.
    for (key in c("protocol", "init", "seed", "iterations", "obj_init",
                  "obj_final")) {
      v1 <- .kbg_meta_field(file.path(d1, "meta.csv"), key)
      v2 <- .kbg_meta_field(file.path(d2, "meta.csv"), key)
      v3 <- .kbg_meta_field(file.path(d3, "meta.csv"), key)
      expect_identical(v2, v1, info = paste(t$tag, key, "-full"))
      expect_identical(v3, v1, info = paste(t$tag, key, "-ends"))
    }
    expect_identical(.kbg_meta_field(file.path(d3, "meta.csv"),
                                     "trace_len"), "2")
    expect_identical(.kbg_meta_field(file.path(d1, "meta.csv"),
                                     "trace_len"),
                     as.character(ITERS + 1L))
    n.attest <- n.attest + 1L
    # The full walk is monotone under the committed convention (the
    # assert_monotone slack of src/rust/engine/src/nmf.rs, banked twin
    # tests/g2_zero_lock.rs).
    obj <- suppressWarnings(as.numeric(vapply(tr2[-1L],
                                               function(r) .kp_split1(r)$right,
                                               character(1L),
                                               USE.NAMES = FALSE)))
    expect_identical(length(obj), ITERS + 1L)
    prev <- obj[-length(obj)]
    viol <- which(obj[-1L] > prev + 1e-9 * (1 + abs(prev)))
    expect_identical(length(viol), 0L,
                     info = paste(t$tag, "monotonicity violations at t",
                                  paste(viol - 1L, collapse = ",")))
    n.attest <- n.attest + 1L
  }
  # ---- census controls ------------------------------------------------
  # Constructed perfect: a faithful rerun reproduces every digest -- the
  # equality census must speak TRUE on faithful bytes.
  t1 <- tasks[[1L]]
  in1 <- .kbg_stage_single(tempfile("bi-ctl-in-"), t1$V)
  c1 <- tempfile("bi-ctl-a-"); c2 <- tempfile("bi-ctl-b-")
  for (d in c(c1, c2)) {
    res <- .kpp_exec_real(bin, .kbg_single_argv(in1, d, 96L, 100L, t1$k,
                                                ITERS, t1$seed))
    expect_identical(res$rc, 0L)
  }
  expect_identical(.kbg_sha(file.path(c1, "W.csv")),
                   .kbg_sha(file.path(c2, "W.csv")))
  expect_identical(.kbg_sha(file.path(c1, "H.csv")),
                   .kbg_sha(file.path(c2, "H.csv")))
  expect_identical(readLines(file.path(c1, "trace.csv"), warn = FALSE),
                   readLines(file.path(c2, "trace.csv"), warn = FALSE))
  # Constructed broken: one observation added to the grid must move the
  # factors -- the census must speak FALSE on corrupted bytes (a digest
  # column blind to this is a dead metric).
  Vm <- t1$V
  Vm[[1L, 1L]] <- Vm[[1L, 1L]] + 1
  in2 <- .kbg_stage_single(tempfile("bi-brk-in-"), Vm)
  db <- tempfile("bi-brk-out-")
  res <- .kpp_exec_real(bin, .kbg_single_argv(in2, db, 96L, 100L, t1$k,
                                              ITERS, t1$seed))
  expect_identical(res$rc, 0L)
  expect_false(identical(.kbg_sha(file.path(db, "W.csv")),
                         .kbg_sha(file.path(c1, "W.csv"))))
  expect_false(identical(.kbg_sha(file.path(db, "H.csv")),
                         .kbg_sha(file.path(c1, "H.csv"))))
  n.attest <- n.attest + 5L
  cat("P10-A ATTESTATION CENSUS: tasks=", length(tasks),
      " attested-groups=", n.attest, " (controls included)\n", sep = "")
  expect_gte(n.attest, 20L * 5L + 5L)
})
