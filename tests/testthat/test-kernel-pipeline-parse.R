# P2 lane, TDD pair L4 (parse fast path): the vectorized read route whose
# PREDICATE is a bit-exact round-trip against the reference route of
# R/kernel-pipeline.R -- identical() grade, not an aspiration.
#
# The forensics base (§7.2: parse_outputs 63.589 s = 8.9% of the 712 s
# rust-tip wall over 8000 parse calls) makes the parse route a first-class
# target, but a fast reader that drifts even one unit-in-the-last-place from
# the certified bytes would silently corrupt every downstream tally. The
# units below therefore pin the fast route AGAINST the reference readers on
# (a) real bytes emitted by the certified batch face, (b) seeded synthetic
# grids at the %.17e round-trip edges (D3: no COSMIC numerics anywhere), and
# (c) the sharpness control -- a one-digit mutation of a cell must make the
# two routes' results NOT identical(), proving the predicate is byte-grade
# rather than tolerance-grade.
#
# Fault law: whatever the reference route rejects, the fast route must
# reject too (rows out of shape, ragged rows whose FLAT token total happens
# to match, non-finite, negative) -- vectorization may never trade away the
# fail-closed guarantee.
#
# Units L4-1..L4-5 bind the future surface (msuiter:::kp_read_matrix_fast /
# kp_read_trace_fast / kp_parse_case_fast) and are red by absence until the
# GREEN commit lands R/kernel-parse.R.

test_that("L4-1 bit-exactness: the fast route reproduces the reference route
           byte-for-byte on real certified batch bytes", {
  kp.read.matrix.fast <- .kpp_surface("kp_read_matrix_fast")  # red by absence
  kp.read.trace.fast  <- .kpp_surface("kp_read_trace_fast")   # red by absence
  sc <- .kpp_valid_scenario()
  res <- .kpp_exec_real(sc$bin, .kpp_batch_argv(sc$manifest, sc$in.root,
                                                sc$out.root))
  expect_identical(res$rc, 0L)
  od <- sc$case.out
  W.ref <- kp_read_matrix_csv(file.path(od, "W.csv"), sc$m, sc$k, "W.csv")
  H.ref <- kp_read_matrix_csv(file.path(od, "H.csv"), sc$k, sc$n, "H.csv")
  tr.ref <- kp_read_trace_csv(file.path(od, "trace.csv"), sc$iters,
                              "trace.csv")
  expect_identical(kp.read.matrix.fast(file.path(od, "W.csv"), sc$m, sc$k,
                                       "W.csv"), W.ref)
  expect_identical(kp.read.matrix.fast(file.path(od, "H.csv"), sc$k, sc$n,
                                       "H.csv"), H.ref)
  expect_identical(kp.read.trace.fast(file.path(od, "trace.csv"), sc$iters,
                                      "trace.csv"), tr.ref)
  # The reference objects must be real (guard against comparing NULLs).
  expect_true(is.matrix(W.ref) && identical(dim(W.ref), c(sc$m, sc$k)))
  expect_true(is.matrix(H.ref) && identical(dim(H.ref), c(sc$k, sc$n)))
  expect_identical(length(tr.ref), sc$iters + 1L)
})

test_that("L4-2 bit-exactness: seeded synthetic grids at the %.17e
           round-trip edges reproduce exactly", {
  kp.read.matrix.fast <- .kpp_surface("kp_read_matrix_fast")  # red by absence
  kp.read.trace.fast  <- .kpp_surface("kp_read_trace_fast")   # red by absence
  # Deterministic edge magnitudes drawn through the seed law (D3): zero,
  # denormal-class values through the %.17e text route, near-overflow
  # finite values, and plain values whose decimal expansion carries 17
  # significant digits.
  seed <- 101L
  set.seed(seed)
  base <- runif(24) * 4
  edges <- c(0, base[1L], base[2L] * 1e-300, base[3L] * 1e300,
             base[4L], nextafter(base[5L], 2), nextafter(base[6L], 0),
             base[7L], base[8L] * 1e-308, base[9L] * 1e-1,
             base[10L] * 1e12, base[11L], base[12L] * 1e300, 0,
             .Machine$double.xmax, base[13L])
  expect_true(all(is.finite(edges)) && all(edges >= 0))
  # The sixteen edge values lay out exactly as the 4 x 4 grid.
  mat <- matrix(edges, nrow = 4L, ncol = 4L)
  d <- tempfile("kpp-edge-")
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  p <- file.path(d, "W.csv")
  writeLines(.kpp_grid(mat), con = p)
  ref <- kp_read_matrix_csv(p, 4L, 4L, "W.csv")
  fast <- kp.read.matrix.fast(p, 4L, 4L, "W.csv")
  expect_identical(fast, ref)
  # ...and the numbers themselves survive the %.17e text route bit-exactly.
  expect_identical(as.vector(fast), as.vector(mat))
  # trace edge: near-adjacent objectives must round-trip exactly.
  iters <- 8L
  obj <- c(9.5, nextafter(9.5, 0), rep(base[20L] * 1e-300, 6L),
           base[21L] * 1e300, 0)
  obj <- obj[seq_len(iters + 1L)]
  tp <- file.path(d, "trace.csv")
  writeLines(c("t,objective",
               paste0(seq_len(iters + 1L) - 1L, ",", sprintf("%.17e", obj))),
               con = tp)
  tref <- kp_read_trace_csv(tp, iters, "trace.csv")
  tfast <- kp.read.trace.fast(tp, iters, "trace.csv")
  expect_identical(tfast, tref)
  expect_identical(tfast, obj)
})

test_that("L4-3 sharpness: a one-digit byte mutation is not identical() --
           the predicate is byte-grade, not tolerance-grade", {
  kp.read.matrix.fast <- .kpp_surface("kp_read_matrix_fast")  # red by absence
  set.seed(202L)
  mat <- matrix(runif(12) * 4, nrow = 4L, ncol = 3L)
  d <- tempfile("kpp-sharp-")
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  p.a <- file.path(d, "a.csv")
  p.b <- file.path(d, "b.csv")
  lines <- .kpp_grid(mat)
  writeLines(lines, con = p.a)
  # Mutate the LAST digit of the last field of row 1: same magnitude class,
  # a different double. A tolerance-grade fast reader could still call the
  # two files equal; identical() must not.
  fields <- strsplit(lines[[1L]], ",", fixed = TRUE)[[1L]]
  tail <- fields[[length(fields)]]
  mutated <- sub(".$", "1", tail)
  if (identical(mutated, tail)) mutated <- sub(".$", "2", tail)
  expect_false(identical(mutated, tail))
  fields[[length(fields)]] <- mutated
  lines.b <- lines
  lines.b[[1L]] <- paste(fields, collapse = ",")
  writeLines(lines.b, con = p.b)
  fa <- kp.read.matrix.fast(p.a, 4L, 3L, "W.csv")
  fb <- kp.read.matrix.fast(p.b, 4L, 3L, "W.csv")
  expect_identical(fa, kp_read_matrix_csv(p.a, 4L, 3L, "W.csv"))
  expect_false(identical(fa, fb),
                "the byte-grade predicate failed to notice a changed digit")
})

test_that("L4-4 fault equivalence: everything the reference route rejects,
           the fast route rejects too (vectorization never trades away
           fail-closed)", {
  kp.read.matrix.fast <- .kpp_surface("kp_read_matrix_fast")  # red by absence
  kp.read.trace.fast  <- .kpp_surface("kp_read_trace_fast")   # red by absence
  d <- tempfile("kpp-faults-")
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  w <- function(name, lines) {
    p <- file.path(d, name)
    writeLines(lines, con = p)
    p
  }
  # The two ragged cases are the dangerous class: the FLAT token total
  # equals nrows * ncols while the rows are ragged (2+4 and 4+2 fields for
  # a 2 x 3 law). A fast route that only counts the flat total would
  # wrongly accept them; the per-row field-count law must be reconstructed.
  bad.rows <- w("bad-rows.csv", c("1,2,3"))                    # 1 row, want 2
  bad.ragged <- w("bad-ragged.csv", c("1,2", "3,4,5,6"))       # 2+4 = 6
  bad.ragged2 <- w("bad-ragged2.csv", c("1,2,3,4", "5,6"))     # 4+2 = 6
  bad.nonfinite <- w("bad-nonfinite.csv", c("1,NaN,3", "4,5,6"))
  bad.inf <- w("bad-inf.csv", c("1,Inf,3", "4,5,6"))
  bad.negative <- w("bad-negative.csv", c("-1,2,3", "4,5,6"))
  for (p in list(bad.rows, bad.ragged, bad.ragged2, bad.nonfinite,
                 bad.inf, bad.negative)) {
    expect_error(kp_read_matrix_csv(p, 2L, 3L, "x.csv"), info = p)
    expect_error(kp.read.matrix.fast(p, 2L, 3L, "x.csv"), info = p)
  }
  # trace faults: missing header, wrong row count, non-monotone t column,
  # non-finite objective.
  t.bad.hdr <- w("t-hdr.csv", c("t,obj", "0,1", "1,2"))
  t.bad.count <- w("t-count.csv", c("t,objective", "0,1", "1,2", "2,3"))
  t.bad.seq <- w("t-seq.csv", c("t,objective", "0,1", "2,2"))
  t.bad.obj <- w("t-obj.csv", c("t,objective", "0,1", "1,NaN"))
  for (p in list(t.bad.hdr, t.bad.count, t.bad.seq, t.bad.obj)) {
    expect_error(kp_read_trace_csv(p, 1L, "t.csv"), info = p)
    expect_error(kp.read.trace.fast(p, 1L, "t.csv"), info = p)
  }
})

test_that("L4-5 consumer surface: kp_parse_case_fast returns the
           identical()-grade bundle the reference assembly produces", {
  kp.parse.case.fast <- .kpp_surface("kp_parse_case_fast")   # red by absence
  sc <- .kpp_valid_scenario()
  res <- .kpp_exec_real(sc$bin, .kpp_batch_argv(sc$manifest, sc$in.root,
                                                sc$out.root))
  expect_identical(res$rc, 0L)
  ref <- kp_attest_case(case = sc$case, out.dir = sc$case.out,
                        m = sc$m, n = sc$n, k = sc$k, iters = sc$iters,
                        init = "nndsvd", seed = "11", replicate = "")
  fast <- kp.parse.case.fast(sc$case.out, m = sc$m, n = sc$n, k = sc$k,
                             iters = sc$iters)
  expect_identical(fast$W, ref$W)
  expect_identical(fast$H, ref$H)
  expect_identical(fast$objective, ref$objective)
  expect_identical(fast$meta, ref$meta)
})
