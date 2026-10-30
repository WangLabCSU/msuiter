# Lane PERF-P10, P10-B batch-bridge law: the unit path through
# kp_serve_unit (R/kernel-bridge.R) is ONE handshake and ONE batch
# invocation per unit, V is staged once per unit under the hard-link law,
# the frozen per-case seed law (run i rides seed + i - 1) is echoed by
# every case receipt, and the batch route is bit-identical to the
# per-run route across the 16-task bootstrapped true-geometry grid.
#
# Units BB1-BB3 are committed procedure (synthetic fixture, seed on the
# record -- they run wherever the kernel builds). BB4 is the attested
# cross-route census and rides the local evidence gate (see
# helper-kernel-geometry.R): absent, it skips with a spoken reason.
# Every census reports its inspected-row count; zero is red.

test_that("BB1 the 50-run unit issues exactly one handshake and one batch
           invocation, and returns 50 attested receipts", {
  bin <- .kpp_bin()
  V <- .kpp_fixture_v(seed = 7L, m = 8L, n = 6L)
  count <- 0L
  argvs <- character()
  mock <- function(bin, args) {
    count <<- count + 1L
    argvs[[length(argvs) + 1L]] <<- paste0(as.character(args),
                                           collapse = " ")
    res <- .kpp_exec_real(bin, args)
    out <- res$rc                                  # status travels by VALUE
    attr(out, "stdout") <- res$stdout
    attr(out, "stderr") <- res$stderr
    out
  }
  unit <- NULL
  .kpp_with_exec(mock, {
    unit <- kp_serve_unit(bin = bin, V = V, k = 2L, seed = 7L,
                          nrun = 50L, iters = 12L, init = "nndsvd",
                          tag = "bb-unit")
  })
  expect_identical(count, 2L)
  hand <- sum(vapply(argvs, function(a) grepl("--version", a),
                     integer(1L), USE.NAMES = FALSE))
  batch <- sum(vapply(argvs, function(a) grepl("--cases", a),
                      integer(1L), USE.NAMES = FALSE))
  single <- sum(vapply(argvs, function(a) grepl("--in ", a),
                       integer(1L), USE.NAMES = FALSE))
  expect_identical(hand, 1L)
  expect_identical(batch, 1L)
  expect_identical(single, 0L)
  expect_identical(length(unit$cases), 50L)
  expect_identical(length(unit$fits), 50L)
  cat("BB1 CENSUS: kernel invocations=", count, " (handshake ", hand,
      ", batch ", batch, ", single-face ", single, "), receipts=",
      length(unit$fits), "\n", sep = "")
})

test_that("BB2 V is staged ONCE per unit under the hard-link law: all 50
           case grids are VIEWS of the single shared rendering (the
           platform-portable write-through census), controls firing", {
  bin <- .kpp_bin()
  V <- .kpp_fixture_v(seed = 7L, m = 8L, n = 6L)
  unit <- kp_serve_unit(bin = bin, V = V, k = 2L, seed = 7L,
                        nrun = 50L, iters = 12L, init = "nndsvd",
                        tag = "bb-links")
  in.root <- dirname(unit$manifest)
  vpaths <- file.path(in.root, unit$cases, "V.csv")
  expect_true(all(file.exists(c(vpaths, unit$shared))))
  # The sharing law of the committed B3 unit, at the 50-run face: a
  # write-through of the shared rendering must surface in EVERY case
  # view -- the hardlink identity probed the way this fleet's file.info
  # columns can carry portably (this base exposes neither inode nor
  # nlink), and the broken control below constructs the copy farm the
  # census must catch.
  marker <- "#p10-shared-probe"
  con <- file(unit$shared, open = "a")
  writeLines(marker, con = con)
  close(con)
  inspected <- 0L
  for (p in vpaths) {
    vl <- readLines(p, warn = FALSE)
    expect_identical(vl[[length(vl)]], marker, info = p)
    inspected <- inspected + 1L
  }
  cat("BB2 CENSUS: shared-view rows inspected=", inspected, " of 50\n",
      sep = "")
  expect_gte(inspected, 50L)
  # ---- census controls ------------------------------------------------
  # Constructed perfect: a hand-built hard-link chain passes the same
  # write-through census (the census speaks true on faithful staging).
  d <- tempfile("bb2-ctl-")
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  a <- file.path(d, "a"); b <- file.path(d, "b"); cc <- file.path(d, "cc")
  writeLines("1,2", con = a)
  .kp_hard_link(a, b)
  .kp_hard_link(a, cc)
  m2 <- "#p10-ctl-perfect"
  con <- file(a, open = "a"); writeLines(m2, con = con); close(con)
  lb <- readLines(b, warn = FALSE)
  expect_identical(lb[[length(lb)]], m2)
  lc <- readLines(cc, warn = FALSE)
  expect_identical(lc[[length(lc)]], m2)
  # Constructed broken: replacing one view with a COPY must freeze it --
  # a census that still called a copy farm shared is a dead metric.
  unlink(cc)
  expect_true(isTRUE(suppressWarnings(file.copy(a, cc))))
  m3 <- "#p10-ctl-broken"
  con <- file(a, open = "a"); writeLines(m3, con = con); close(con)
  lc2 <- readLines(cc, warn = FALSE)
  expect_false(identical(lc2[[length(lc2)]], m3))
})

test_that("BB3 every case receipt echoes the frozen per-case seed law
           (run i rides seed + i - 1), 50 for 50, and the census is live", {
  bin <- .kpp_bin()
  V <- .kpp_fixture_v(seed = 7L, m = 8L, n = 6L)
  seed <- 7L
  unit <- kp_serve_unit(bin = bin, V = V, k = 2L, seed = seed,
                        nrun = 50L, iters = 12L, init = "nndsvd",
                        tag = "bb-seed")
  inspected <- 0L
  for (i in seq_along(unit$cases)) {
    meta <- file.path(unit$out.root, unit$cases[[i]], "out", "meta.csv")
    expect_identical(.kbg_meta_field(meta, "seed"),
                     as.character(seed + as.integer(i) - 1L),
                     info = unit$cases[[i]])
    expect_identical(.kbg_meta_field(meta, "init"), "nndsvd",
                     info = unit$cases[[i]])
    expect_identical(.kbg_meta_field(meta, "trace_len"), "2",
                     info = unit$cases[[i]])
    inspected <- inspected + 3L
  }
  cat("BB3 CENSUS: meta fields inspected=", inspected, " over ",
      length(unit$cases), " cases\n", sep = "")
  expect_gte(inspected, 150L)
  # Liveness control: shifting the unit seed shifts every echo -- a
  # census reading stale bytes would miss it.
  unit2 <- kp_serve_unit(bin = bin, V = V, k = 2L, seed = 8L,
                         nrun = 2L, iters = 12L, init = "nndsvd",
                         tag = "bb-seed2")
  echo2 <- vapply(unit2$cases, function(cs)
    .kbg_meta_field(file.path(unit2$out.root, cs, "out", "meta.csv"),
                    "seed"), character(1L), USE.NAMES = FALSE)
  expect_identical(unname(echo2), c("8", "9"))
})

test_that("BB4 the batch route is bit-identical to the per-run route
           across the 16-task bootstrapped grid, with the census controls
           firing", {
  ev <- .kbg_ev()
  if (is.null(ev)) .kbg_skip()
  bin <- .kpp_bin()
  inspected <- 0L
  for (b in 1:4L) {
    V <- .kbg_boot(ev, b)
    seed.base <- 123L + b - 1L
    for (k in 2:5L) {
      unit.b <- kp_serve_unit(bin = bin, V = V, k = as.integer(k),
                              seed = seed.base, nrun = 4L, iters = 2000L,
                              init = "nndsvd",
                              tag = paste0("bb4b-", b, "-", k))
      for (i in seq_along(unit.b$cases)) {
        unit.p <- kp_serve_unit(bin = bin, V = V, k = as.integer(k),
                                seed = seed.base + as.integer(i) - 1L,
                                nrun = 1L, iters = 2000L, init = "nndsvd",
                                tag = paste0("bb4p-", b, "-", k, "-", i))
        dir.b <- file.path(unit.b$out.root, unit.b$cases[[i]], "out")
        dir.p <- file.path(unit.p$out.root, unit.p$cases[[1L]], "out")
        for (f in c("W.csv", "H.csv")) {
          expect_identical(.kbg_sha(file.path(dir.b, f)),
                           .kbg_sha(file.path(dir.p, f)),
                           info = paste0("boot", b, " k", k, " run", i,
                                         " ", f))
          inspected <- inspected + 1L
        }
      }
    }
  }
  cat("BB4 CENSUS: cross-route digest pairs inspected=", inspected,
      " (16 tasks x 4 runs x 2 factors)\n", sep = "")
  expect_gte(inspected, 128L)
  # ---- census controls ------------------------------------------------
  # Constructed perfect: a faithful rerun of one batch unit reproduces
  # every digest (the census speaks true on faithful bytes).
  V1 <- .kbg_boot(ev, 1L)
  again <- kp_serve_unit(bin = bin, V = V1, k = 2L, seed = 123L,
                         nrun = 1L, iters = 2000L, init = "nndsvd",
                         tag = "bb4-ctl")
  dir.a <- file.path(again$out.root, again$cases[[1L]], "out")
  first <- kp_serve_unit(bin = bin, V = V1, k = 2L, seed = 123L,
                         nrun = 1L, iters = 2000L, init = "nndsvd",
                         tag = "bb4-ctl2")
  dir.b <- file.path(first$out.root, first$cases[[1L]], "out")
  for (f in c("W.csv", "H.csv")) {
    expect_identical(.kbg_sha(file.path(dir.a, f)),
                     .kbg_sha(file.path(dir.b, f)))
  }
  # Constructed broken: a seed OUTSIDE the frozen law (the law only ever
  # issues seed + i - 1 for the unit's own i) must land outside the
  # attested digest set -- a census blind to this is a dead metric.
  rogue <- kp_serve_unit(bin = bin, V = V1, k = 2L, seed = 999L,
                         nrun = 1L, iters = 2000L, init = "nndsvd",
                         tag = "bb4-brk")
  dir.r <- file.path(rogue$out.root, rogue$cases[[1L]], "out")
  expect_false(identical(.kbg_sha(file.path(dir.r, "W.csv")),
                         .kbg_sha(file.path(dir.b, "W.csv"))))
})
