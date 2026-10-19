# P2 lane, TDD pair L1 (batch bridge): one kernel process per (rank,
# bootstrap) unit serving the whole unit through the certified batch face,
# V marshalled once per unit, the protocol handshake once per unit, every
# case consumable only through its attested receipt -- and the whole
# redesign must not move a single emitted byte.
#
# The forensics base counted the tax this pair retires: 8000 per-fit
# kernel spawns + 4000 per-fit handshakes = 85.6% of the 712 s rust-tip
# wall (kernel_exec 609.073 s). The redesigned call sites change WHO calls
# the kernel and WHEN, never WHAT it computes -- the frozen constants
# (init nndsvd, the run-i seed law seed + i - 1, nrun, iters, per-rank
# m/n/k, protocol=1) ride the manifest rows verbatim.
#
# WHAT IS GATED HERE versus the container side: B1 compares the batch
# multi-row route against one-row batches on the SAME certified face and
# the SAME staging bytes -- it pins that the bridge's marshalling/seed-law/
# consumption moves no byte. The end-to-end comparison against the legacy
# per-fit route (.rust_fit_kl through sigminer's bridge) is the P2-6
# byte-diff control on the campaign platform (same images, same bytes).
#
# D3: every numeric here is generated from a set seed; the certified
# binary runs only on these synthetic grids.
#
# Units B2..B7 bind the future surface (msuiter:::kp_serve_unit) and are
# red by absence until the GREEN commit lands R/kernel-bridge.R; B1 also
# binds the attested-return extension of the already-green kp_run_batch.

## ---- the small unit scenario -------------------------------------------------

# One unit's synthetic inputs: m x n grid from the seed law, k ranks and a
# replicate count; returns everything a unit run needs (staging roots are
# fresh tempdirs -- the lane writes only under lane stamps).
.kpp_unit_scenario <- function(seed = 31L, m = 8L, n = 6L, k = 2L,
                               iters = 12L, nrun = 3L, tag = "b-unit") {
  V <- .kpp_fixture_v(seed = seed, m = m, n = n)
  list(V = V, m = as.integer(m), n = as.integer(n), k = as.integer(k),
       iters = as.integer(iters), nrun = as.integer(nrun),
       bin = .kpp_bin(),
       root = tempfile("kpp-b-in-"), out.root = tempfile("kpp-b-out-"),
       tag = tag)
}

test_that("B1 batch-vs-single bit-identity: the bridge's batch route
           reproduces the one-row route byte for byte, and consumes only
           attested receipts", {
  kp.serve.unit <- .kpp_surface("kp_serve_unit")   # red by absence
  sc <- .kpp_unit_scenario()
  srv <- kp.serve.unit(bin = sc$bin, V = sc$V, k = sc$k, seed = 5L,
                       nrun = sc$nrun, iters = sc$iters, tag = sc$tag,
                       root = sc$root, out.root = sc$out.root)
  expect_identical(srv$nrun, sc$nrun)
  expect_identical(length(srv$fits), sc$nrun)
  # The one-row reference route: the SAME certified face, one row per call,
  # its own staging -- the run-i seed law verbatim (seed + i - 1).
  ref <- list()
  for (i in seq_len(sc$nrun)) {
    root.i <- tempfile("kpp-b1-in-")
    out.i <- tempfile("kpp-b1-out-")
    case <- paste0("pf-", i)
    .kpp_stage_case(root.i, case, sc$V)
    manifest <- .kpp_write_manifest(
      file.path(root.i, "cases.csv"),
      paste0(case, ",nndsvd,", 5L + i - 1L, ",,", sc$iters, ",",
             sc$m, ",", sc$n, ",", sc$k))
    rb <- kp_run_batch(bin = sc$bin, manifest = manifest, root = root.i,
                       out.root = out.i)
    # attested-return extension of the green kp_run_batch: the consumer
    # gets the validated bytes, not a path it must trust blindly.
    expect_false(is.null(rb$attested),
                 "kp_run_batch must hand the attested bundles upward")
    expect_identical(names(rb$attested)[[1L]], case)
    ref[[i]] <- rb$attested[[case]]
  }
  for (i in seq_len(sc$nrun)) {
    expect_identical(srv$fits[[i]]$W, ref[[i]]$W)
    expect_identical(srv$fits[[i]]$H, ref[[i]]$H)
    expect_identical(srv$fits[[i]]$objective, ref[[i]]$objective)
    expect_identical(srv$fits[[i]]$meta, ref[[i]]$meta)
  }
})

test_that("B2 one process per unit: exactly one batch exec and exactly one
           handshake for a full nrun, never a per-fit contact", {
  kp.serve.unit <- .kpp_surface("kp_serve_unit")   # red by absence
  sc <- .kpp_unit_scenario(nrun = 50L)
  st <- new.env(parent = emptyenv())
  st$calls <- 0L
  st$argv <- list()
  .kpp_with_exec(function(bin, args) {
    # Full recorder (not .kpp_mock): every contact -- the handshake
    # included -- must be countable here.
    st$calls <- st$calls + 1L
    st$argv[[length(st$argv) + 1L]] <- args
    if (any(args == "--version")) return(.kpp_version_result())
    res <- 0L
    attr(res, "stdout") <- character()
    attr(res, "stderr") <- "error: no bytes were produced -- attestation stops"
    res
  }, {
    err <- tryCatch({
      kp.serve.unit(bin = sc$bin, V = sc$V, k = sc$k, seed = 5L,
                    nrun = sc$nrun, iters = sc$iters, tag = sc$tag,
                    root = sc$root, out.root = sc$out.root)
      NULL
    }, error = function(e) conditionMessage(e))
    # The receipt gate must stop the consumer (no attested bytes exist).
    expect_false(is.null(err))
  })
  # Two contacts for the whole unit of 50 fits: the protocol handshake and
  # the single batch invocation. The legacy shape was 50 spawns + 50
  # handshakes for this same unit.
  expect_identical(st$calls, 2L)
  expect_identical(sum(vapply(st$argv, function(a) any(a == "--version"),
                              FUN.VALUE = logical(1L), USE.NAMES = FALSE)),
                   1L)
  batch.argv <- st$argv[[which(!vapply(st$argv, function(a)
                                         any(a == "--version"),
                                       FUN.VALUE = logical(1L),
                                       USE.NAMES = FALSE))[[1L]]]]
  expect_identical(batch.argv[[1L]], "fit-kl")
  expect_identical(sum(batch.argv == "--cases"), 1L)
  expect_identical(sum(batch.argv == "--root"), 1L)
  expect_identical(sum(batch.argv == "--out-root"), 1L)
  manifest.path <- batch.argv[[which(batch.argv == "--cases") + 1L]]
  ml <- readLines(manifest.path, warn = FALSE)
  ml <- ml[nzchar(ml)]
  expect_identical(length(ml), sc$nrun + 1L)  # header + one row per fit
})

test_that("B3 V is marshalled ONCE per unit: one text rendering, the case
           rows are views of the single staged grid", {
  kp.serve.unit <- .kpp_surface("kp_serve_unit")   # red by absence
  sc <- .kpp_unit_scenario(nrun = 3L)
  srv <- kp.serve.unit(bin = sc$bin, V = sc$V, k = sc$k, seed = 5L,
                       nrun = sc$nrun, iters = sc$iters, tag = sc$tag,
                       root = sc$root, out.root = sc$out.root)
  want <- .kpp_grid(sc$V)
  expect_true(file.exists(srv$shared), info = srv$shared)
  for (i in seq_len(sc$nrun)) {
    v.path <- file.path(sc$root, srv$cases[[i]], "V.csv")
    expect_true(file.exists(v.path), info = v.path)
    vl <- readLines(v.path, warn = FALSE)
    expect_identical(vl[nzchar(vl)], want)
  }
  # The sharing law (the manifest §1 marshalling law, platform-portable
  # form): the per-case grids are VIEWS of the one staged rendering, not
  # copies -- a write-through of the shared file is visible in every case
  # view. A copy-based staging would leave the case views frozen and this
  # probe would fail.
  marker <- "#kpp-shared-probe"
  con <- file(srv$shared, open = "a")
  writeLines(marker, con)
  close(con)
  for (i in seq_len(sc$nrun)) {
    vl <- readLines(file.path(sc$root, srv$cases[[i]], "V.csv"),
                    warn = FALSE)
    expect_identical(vl[[length(vl)]], marker)
  }
})

test_that("B4 the frozen seed law rides the manifest verbatim: row i
           carries seed + i - 1, init nndsvd, the per-rank dimensions", {
  kp.serve.unit <- .kpp_surface("kp_serve_unit")   # red by absence
  sc <- .kpp_unit_scenario(nrun = 5L)
  seed <- 1000L
  srv <- kp.serve.unit(bin = sc$bin, V = sc$V, k = sc$k, seed = seed,
                       nrun = sc$nrun, iters = sc$iters, tag = sc$tag,
                       root = sc$root, out.root = sc$out.root)
  ml <- readLines(srv$manifest, warn = FALSE)
  ml <- ml[nzchar(ml)]
  expect_identical(ml[[1L]], .kpp_batch_header)
  rows <- strsplit(ml[-1L], ",", fixed = TRUE)
  expect_identical(length(rows), sc$nrun)
  for (i in seq_len(sc$nrun)) {
    r <- rows[[i]]
    expect_identical(r[[2L]], "nndsvd")
    expect_identical(r[[3L]], as.character(seed + i - 1L))
    expect_identical(r[[4L]], "")                       # no replicate column
    expect_identical(r[[5L]], as.character(sc$iters))    # for this face the
    expect_identical(r[[6L]], as.character(sc$m))        # frozen constants
    expect_identical(r[[7L]], as.character(sc$n))        # ride verbatim
    expect_identical(r[[8L]], as.character(sc$k))
  }
})

test_that("B5 spawn budget: the full 80-unit campaign plan through the
           redesigned bridge costs 160 process contacts, not 12000", {
  kp.serve.unit <- .kpp_surface("kp_serve_unit")   # red by absence
  st <- new.env(parent = emptyenv())
  st$calls <- 0L
  .kpp_with_exec(function(bin, args) {
    # Full recorder: the 160-contact budget counts handshakes too.
    st$calls <- st$calls + 1L
    if (any(args == "--version")) return(.kpp_version_result())
    res <- 0L
    attr(res, "stdout") <- character()
    attr(res, "stderr") <- character()
    res
  }, {
    V <- .kpp_fixture_v(seed = 77L, m = 8L, n = 6L)
    # The frozen campaign shape: 4 ranks x 20 bootstraps, nrun 50 each --
    # but at the small synthetic grids (D3). Every unit's attestation
    # fails closed (no bytes behind the mock) -- that is the honest
    # measurement: the CONTACTS happened, the CONSUMPTION did not.
    for (boots in seq_len(20L)) {
      for (rank in 2L + seq_len(4L)) {
        err <- tryCatch({
          kp.serve.unit(bin = .kpp_bin(), V = V, k = rank, seed = boots,
                        nrun = 50L, iters = 2000L,
                        tag = paste0("p-", boots, "-", rank),
                        root = tempfile("kpp-b5-in-"),
                        out.root = tempfile("kpp-b5-out-"))
          NULL
        }, error = function(e) conditionMessage(e))
        expect_false(is.null(err),
                     "un-attested units must fail closed even at plan scale")
      }
    }
  })
  expect_identical(st$calls, 160L)   # 80 units x (1 handshake + 1 batch)
})

test_that("B6 fail-closed consumption: a batch that exits 0 but leaves one
           case un-attested delivers NOTHING and names the missing case", {
  kp.serve.unit <- .kpp_surface("kp_serve_unit")   # red by absence
  sc <- .kpp_unit_scenario(nrun = 5L)
  # A real, complete serve to harvest valid residue bytes first...
  good <- kp.serve.unit(bin = sc$bin, V = sc$V, k = sc$k, seed = 5L,
                        nrun = sc$nrun, iters = sc$iters, tag = "b6-good",
                        root = tempfile("kpp-b6g-in-"),
                        out.root = tempfile("kpp-b6g-out-"))
  expect_identical(length(good$fits), sc$nrun)
  # ...then the fault injection: the kernel exits 0, the output tree holds
  # every case but the last, and the bridge must refuse the unit whole.
  out.part <- tempfile("kpp-b6-bad-out-")
  dir.create(out.part, recursive = TRUE, showWarnings = FALSE)
  for (i in seq_len(sc$nrun - 1L)) {
    file.copy(file.path(good$out.root, good$cases[[i]]), out.part,
              recursive = TRUE)
  }
  missing.case <- good$cases[[sc$nrun]]
  err <- NULL
  .kpp_with_exec(.kpp_mock(function(bin, args) {
    res <- 0L
    attr(res, "stdout") <- character()
    attr(res, "stderr") <- character()
    res
  }), {
    err <- tryCatch({
      kp.serve.unit(bin = sc$bin, V = sc$V, k = sc$k, seed = 5L,
                    nrun = sc$nrun, iters = sc$iters, tag = "b6-good",
                    root = sc$root, out.root = out.part)
      NULL
    }, error = function(e) conditionMessage(e))
  })
  expect_false(is.null(err), "a half-emitted unit must never be consumable")
  expect_true(grepl(missing.case, err, fixed = TRUE), info = err)
})

test_that("B7 determinism: the same unit inputs twice render the same
           manifest bytes and the same attested fits", {
  kp.serve.unit <- .kpp_surface("kp_serve_unit")   # red by absence
  sc <- .kpp_unit_scenario(nrun = 4L, seed = 99L)
  a <- kp.serve.unit(bin = sc$bin, V = sc$V, k = sc$k, seed = 7L,
                     nrun = sc$nrun, iters = sc$iters, tag = "b7",
                     root = tempfile("kpp-b7a-in-"),
                     out.root = tempfile("kpp-b7a-out-"))
  b <- kp.serve.unit(bin = sc$bin, V = sc$V, k = sc$k, seed = 7L,
                     nrun = sc$nrun, iters = sc$iters, tag = "b7",
                     root = tempfile("kpp-b7b-in-"),
                     out.root = tempfile("kpp-b7b-out-"))
  expect_identical(a$cases, b$cases)
  la <- readLines(a$manifest, warn = FALSE); lb <- readLines(b$manifest,
                                                             warn = FALSE)
  expect_identical(la[nzchar(la)], lb[nzchar(lb)])
  for (i in seq_len(sc$nrun)) {
    expect_identical(a$fits[[i]]$W, b$fits[[i]]$W)
    expect_identical(a$fits[[i]]$H, b$fits[[i]]$H)
    expect_identical(a$fits[[i]]$objective, b$fits[[i]]$objective)
    expect_identical(a$fits[[i]]$meta, b$fits[[i]]$meta)
  }
})
