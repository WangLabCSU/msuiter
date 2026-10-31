# Lane PERF-P10, P10-A protocol-2 trace-shape law (the committed trace
# procedure of the certified stable entry).
#
# The KL observer never feeds the MM updates, so its per-iteration
# witnesses are pure measurement. The production face therefore records
# the walk's two endpoints (the initializer witness at t = 0, the
# post-loop witness at t = iters), and the full one-witness-per-iteration
# ceremony rides the explicit --full-trace opt-in. The law this file
# pins on real certified bytes (synthetic fixture, seed on the record):
#   U1 the production face is exactly the endpoints ceremony and is
#      self-describing (trace_len 2);
#   U2 the two faces are bit-identical where they must be -- W/H bytes,
#      the obj_init/obj_final meta witnesses, and the endpoints trace
#      rows as a byte-subset of the full walk's rows;
#   U3 the shape-driven readers reject the contradicting face on real
#      bytes, on BOTH routes (fail-closed, not advisory);
#   U4 the .kp_trace_t law table and the shape parameters' presence
#      (red-by-absence idiom: an absent surface stops the lane).
# The full-trace monotonicity property over real geometry rides the
# attestation law in test-kernel-bit-identity.R (same run, same bytes).

.kt_bytes <- function(p) readBin(p, what = "raw", n = file.info(p)$size)

# The two faces of one identical scenario (same staged V, same manifest,
# same seed -- only the face selector differs).
.kt_two_faces <- function() {
  sc <- .kpp_valid_scenario()
  res <- .kpp_exec_real(sc$bin, .kpp_batch_argv(sc$manifest, sc$in.root,
                                                 sc$out.root))
  expect_identical(res$rc, 0L)
  out.full <- tempfile("kt-full-out-")
  resf <- .kpp_exec_real(sc$bin, c(.kpp_batch_argv(sc$manifest,
                                                   sc$in.root, out.full),
                                   "--full-trace"))
  expect_identical(resf$rc, 0L)
  sc$out.full <- out.full
  sc$case.full <- file.path(out.full, sc$case, "out")
  sc
}

test_that("U1 the production face is the endpoints ceremony, self-describing", {
  sc <- .kt_two_faces()
  lines <- readLines(file.path(sc$case.out, "trace.csv"), warn = FALSE)
  lines <- lines[nzchar(lines)]
  expect_identical(lines[[1L]], "t,objective")
  expect_identical(length(lines) - 1L,
                   length(.kp_trace_t(sc$iters, "endpoints", "trace.csv")))
  ts <- vapply(strsplit(lines[-1L], ",", fixed = TRUE),
               function(x) suppressWarnings(as.integer(x[[1L]])),
               integer(1L), USE.NAMES = FALSE)
  expect_identical(ts, .kp_trace_t(sc$iters, "endpoints", "trace.csv"))
  expect_identical(.kbg_meta_field(file.path(sc$case.out, "meta.csv"),
                                   "trace_len"), "2")
})

test_that("U2 the two faces are bit-identical where they must be", {
  sc <- .kt_two_faces()
  # The factors: byte-for-byte across the faces (the observer never
  # feeds the updates).
  for (f in c("W.csv", "H.csv")) {
    expect_identical(.kt_bytes(file.path(sc$case.out, f)),
                     .kt_bytes(file.path(sc$case.full, f)), info = f)
  }
  # The endpoint witnesses of the meta receipt: byte-equal strings.
  for (key in c("obj_init", "obj_final", "protocol", "init", "seed",
                "iterations")) {
    expect_identical(.kbg_meta_field(file.path(sc$case.out, "meta.csv"),
                                     key),
                     .kbg_meta_field(file.path(sc$case.full, "meta.csv"),
                                     key),
                     info = key)
  }
  expect_identical(.kbg_meta_field(file.path(sc$case.full, "meta.csv"),
                                   "trace_len"),
                   as.character(sc$iters + 1L))
  # The endpoints trace rows are a BYTE-SUBSET of the full walk's rows:
  # row one and the row whose t label is iters, verbatim.
  prod <- readLines(file.path(sc$case.out, "trace.csv"), warn = FALSE)
  full <- readLines(file.path(sc$case.full, "trace.csv"), warn = FALSE)
  prod <- prod[nzchar(prod)]
  full <- full[nzchar(full)]
  expect_identical(prod[[2L]], full[[2L]])
  last.full <- full[[length(full)]]
  expect_identical(.kp_split1(last.full)$left, paste0(sc$iters))
  expect_identical(prod[[3L]], last.full)
})

test_that("U3 the shape-driven readers reject the contradicting face on
           real bytes, on both routes", {
  sc <- .kt_two_faces()
  expect_silent(kp_read_trace_csv(file.path(sc$case.out, "trace.csv"),
                                  sc$iters, "trace.csv"))
  expect_silent(kp_read_trace_fast(file.path(sc$case.out, "trace.csv"),
                                   sc$iters, "trace.csv"))
  expect_error(kp_read_trace_csv(file.path(sc$case.out, "trace.csv"),
                                 sc$iters, "trace.csv", shape = "full"))
  expect_error(kp_read_trace_fast(file.path(sc$case.out, "trace.csv"),
                                  sc$iters, "trace.csv", shape = "full"))
  expect_silent(kp_read_trace_csv(file.path(sc$case.full, "trace.csv"),
                                  sc$iters, "trace.csv", shape = "full"))
  expect_error(kp_read_trace_csv(file.path(sc$case.full, "trace.csv"),
                                 sc$iters, "trace.csv"))
  expect_error(kp_read_trace_fast(file.path(sc$case.full, "trace.csv"),
                                  sc$iters, "trace.csv"))
  # The assembly routes carry the same law.
  expect_error(kp_attest_case(case = sc$case, out.dir = sc$case.out,
                               m = sc$m, n = sc$n, k = sc$k,
                               iters = sc$iters, init = "nndsvd",
                               seed = "11", replicate = "",
                               trace.shape = "full"))
  expect_error(kp_attest_case(case = sc$case, out.dir = sc$case.full,
                               m = sc$m, n = sc$n, k = sc$k,
                               iters = sc$iters, init = "nndsvd",
                               seed = "11", replicate = "",
                               trace.shape = "endpoints"))
  expect_error(kp_parse_case_fast(sc$case.out, m = sc$m, n = sc$n,
                                  k = sc$k, iters = sc$iters,
                                  trace.shape = "full"))
})

test_that("U4 the shape law table and the shape parameters are present", {
  # Red-by-absence: an absent .kp_trace_t or an absent shape parameter is
  # a stop through the bare name / NULL default, never a silent pass.
  expect_identical(.kp_trace_t(12L, "endpoints", "t"), c(0L, 12L))
  expect_identical(.kp_trace_t(0L, "endpoints", "t"), 0L)
  expect_identical(.kp_trace_t(3L, "full", "t"), 0:3)
  expect_error(.kp_trace_t(3L, "bogus", "t"))
  for (fn in list(kp_read_trace_csv, kp_read_trace_fast)) {
    expect_identical(eval(formals(fn)$shape), c("endpoints", "full"))
  }
  expect_identical(eval(formals(kp_parse_case_fast)$trace.shape),
                   c("endpoints", "full"))
  expect_identical(eval(formals(kp_attest_case)$trace.shape),
                   c("endpoints", "full"))
})
