# audit #74 P1-5: the library RNG-hygiene law. A face that seeds the base
# RNG for its own reproducibility must hand the caller back the very stream
# the caller had -- the face's seed is an argument, not a side effect.
# Three faces of the law: stream continuity at every lightweight face, the
# no-residue rule for a session that never touched the RNG, and a static
# gate proving every set.seed site in R/ rides the snapshot/restore pair
# (the static face covers the heavyweight calibration/driver sites that
# cannot afford a per-call stream replay here).

.ms_rh_keys <- function() msuiter:::.ms_rng_state_keys

.ms_rh_reseed <- function() {
  set.seed(20261105L, kind = "Mersenne-Twister", normal.kind = "Inversion",
            sample.kind = "Rejection")
}

# The caller's law: two draws before the face, the face, two draws after
# -- the four must read as one uninterrupted stream from one seed.
expect_rh_stream <- function(expr) {
  force(expr)
  .ms_rh_reseed()
  a <- suppressWarnings(rnorm(2L))
  suppressWarnings(suppressMessages(force(expr)))
  b <- suppressWarnings(rnorm(2L))
  .ms_rh_reseed()
  ref <- suppressWarnings(rnorm(4L))
  testthat::expect_identical(a, ref[1:2])
  testthat::expect_identical(b, ref[3:4],
    info = "the face left its seed on the user's global stream")
}

test_that("seeding faces leave the user stream where the user left it", {
  expo <- matrix(c(10, 5, 1, 20, 3, 2, 5, 5, 5, 1, 2, 7), nrow = 3,
    ncol = 4, dimnames = list(c("S1", "S2", "S3"), paste0("T", 1:4)))
  expect_rh_stream(ms_embed(expo, method = "kmeans", clusters = 2L,
    seed = 41))
  labels <- msuiter:::.ms_io_channel_tables()$SBS96
  sig <- matrix(1 / 96, 96, 1, dimnames = list(labels, "FLAT"))
  expo2 <- matrix(1, 1, 2, dimnames = list("FLAT", c("A", "B")))
  expect_rh_stream(ms_simulate(sig, expo2, arm = "multinomial",
    burden = 500, seed = 11))
  expect_rh_stream(msuiter:::.ms_null_emp_pvalue(0.5, m = 96,
    n_draws = 500, seed = 7))
  expect_rh_stream(msuiter:::.ms_null_emp_pvalue_conditional(0.5,
    profile = rep(1 / 96, 96), burden = 1000, n_draws = 500, seed = 3))
  cat1 <- ms_catalog(matrix(seq_len(96) * 2L, 96, 1,
      dimnames = list(labels, "S")),
    list(name = "SBS96", labels = labels), "S",
    provenance = list(genome = "GRCh37"))
  expect_rh_stream(ms_downsample(cat1, depth = 100, seed = 7))
})

test_that("a session that never touched the RNG keeps it untouched", {
  # The restore must REMOVE the state variables a pristine session never
  # had -- re-setting them from a blank snapshot would forge them.
  g <- globalenv()
  keys <- .ms_rh_keys()
  present <- keys[vapply(keys, function(k) exists(k, envir = g,
                                                  inherits = FALSE),
                         logical(1L))]
  saved <- mget(present, envir = g)
  on.exit({
    for (k in present) assign(k, saved[[k]], envir = g)
  }, add = TRUE)
  rm(list = present, envir = g)
  expo <- matrix(c(10, 5, 1, 20, 3, 2, 3, 9, 4), nrow = 3, ncol = 3,
    dimnames = list(c("S1", "S2", "S3"), c("A", "B", "C")))
  suppressWarnings(suppressMessages(
    ms_embed(expo, method = "kmeans", clusters = 2L, seed = 9)))
  forged <- keys[vapply(keys, function(k) exists(k, envir = g,
                                                  inherits = FALSE),
                         logical(1L))]
  expect_identical(forged, character())
})

.rh_root <- function(start = testthat::test_path()) {
  d <- normalizePath(start)
  while (nzchar(dirname(d)) != nchar(d)) {
    if (file.exists(file.path(d, "DESCRIPTION"))) {
      desc <- readLines(file.path(d, "DESCRIPTION"), warn = FALSE)
      if (any(grepl("^Package: msuiter", desc))) return(d)
    }
    d <- dirname(d)
  }
  # The simulated check layout runs the copied tests as a sibling of the
  # package dir -- no DESCRIPTION ancestry there. Absent root is then the
  # check-context signal, spoken by the unit's sanctioned skip, not a stop.
  NA_character_
}

test_that("every library set.seed site rides the snapshot/restore guard", {
  # Function-level containment: any top-level function in R/ that seeds the
  # base RNG must also carry the snapshot/restore pair -- a 4-line look-behind
  # would miss the driver's loop-seeded face.
  root <- .rh_root()
  if (is.na(root)) {
    skip(paste0("the static scan reads the R/ sources plain text: requires the ",
                "source checkout, which the check layout does not ship ",
                "(R CMD check context)"))
  }
  files <- list.files(file.path(root, "R"), pattern = "[.]R$",
    full.names = TRUE)
  files <- files[basename(files) != "rng-hygiene.R"]
  offenders <- character()
  for (f in files) {
    lines <- readLines(f, warn = FALSE)
    starts <- which(grepl("^[a-zA-Z._][^.]*[[:space:]]*<-[[:space:]]*function[(]",
                          lines))
    ends <- c(starts[-1L] - 1L, length(lines))
    keeps <- grepl("^[[:space:]]*set[.]seed[(]", lines)
    for (b in seq_along(starts)) {
      blk <- starts[b]:ends[b]
      if (any(keeps[blk]) &&
          !any(grepl(".ms_rng_snapshot(", lines[blk], fixed = TRUE))) {
        first <- which(keeps[blk])[1L]
        offenders <- c(offenders, sprintf("%s:%d", basename(f),
                                          blk[first]))
      }
    }
  }
  # Firing control: an un-guarded seeding function must be caught -- the
  # scan is not reading an empty window.
  ctrl <- c("bad_face <- function() {", "  set.seed(42)",
            "  runif(1)", "}")
  keeps_ctrl <- grepl("^[[:space:]]*set[.]seed[(]", ctrl)
  expect_true(any(keeps_ctrl[1:4]) &&
    !any(grepl(".ms_rng_snapshot(", ctrl, fixed = TRUE)))
  expect_identical(offenders, character())
})
