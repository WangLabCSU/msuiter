# GO-04F regression unit (windows arms, /tmp/m7probe/win-oldrel1.log):
# [ FAIL 2 ] exclusively at test-check-layout-sim.R:31/:34 -- the generated
# runner died at PARSE time ("Error: '\c' is an unrecognized escape in
# character string (<input>:1:70)") because its first line embeds the
# config-file path as an R string literal and Windows tempfile() hands back
# backslashed paths (C:\Users\runneradmin\AppData\Local\Temp\...): the
# backslash is consumed as an escape introducer at parse, before the sim
# body ever runs. mac/linux arms are immune (forward-slash paths), which is
# exactly why only a Windows-shaped feed can guard this class locally.
#
# The units drive the REAL generator (.runner_lines, extracted verbatim so
# the emitted vector is testable) with a synthetic Windows path and require
# the emitted vector to parse; the emitter contract (.r_str) is pinned
# separately: backslash doubling round-trips through eval, and inputs whose
# shape cannot be represented fail CLOSED (stop, not silent corruption).

# Source-level extraction of the harness's top-level function definitions:
# the harness script executes on source, so the generator is reached by
# parsing the file and evaluating only the targeted assignment expressions
# in a clean base-env child.
.sim_defs <- function(file, names) {
  env <- new.env(parent = baseenv())
  found <- character()
  for (e in parse(file = file)) {
    if (is.call(e) && identical(as.character(e[[1L]]), "<-") &&
        is.name(e[[2L]]) && as.character(e[[2L]]) %in% names) {
      eval(e, envir = env)
      found <- unique(c(found, as.character(e[[2L]])))
    }
  }
  miss <- setdiff(names, found)
  if (length(miss)) {
    stop(paste0("harness generator symbols not extractable: ",
                paste(miss, collapse = ", ")))
  }
  env
}

# The measured windows-shape: segments whose leading characters are
# invalid escape introducers (\U \A \c), mirroring the real arm's path.
.WINPATH <- "C:\\Users\\runneradmin\\AppData\\Local\\Temp\\Rtmp7f3a\\ccfg\\sim-env.txt"

test_that("check-layout-sim: generated runner parses under a Windows-shaped config path", {
  sim <- .ms_src("tools/check-layout-sim.R")
  if (is.na(sim)) {
    skip("tools/check-layout-sim.R not locatable (R CMD check context)")
  }
  # the generator CLOSES OVER the emitter (.r_str): both are extracted into
  # the same base-env child so the cross-reference resolves as it does in
  # the harness itself.
  env <- .sim_defs(sim, c(".runner_lines", ".r_str"))
  lns <- get(".runner_lines", envir = env)(.WINPATH)
  expect_match(lns[1L], "^envf <- ")
  err <- tryCatch({
    parse(text = paste(lns, collapse = "\n"))
    NULL
  }, error = function(e) conditionMessage(e))
  expect_identical(err, NULL,
    info = paste0("the emitted runner must parse exactly as written; R said: ", err))
})

test_that("check-layout-sim: .r_str emits parse-stable literals and fails closed", {
  sim <- .ms_src("tools/check-layout-sim.R")
  if (is.na(sim)) {
    skip("tools/check-layout-sim.R not locatable (R CMD check context)")
  }
  env <- .sim_defs(sim, ".r_str")
  f <- get(".r_str", envir = env)
  # unix paths pass through the doubling unchanged
  expect_identical(f("/tmp/x/y"), "'/tmp/x/y'")
  # the windows path round-trips: what parses back IS the real path
  expect_identical(eval(parse(text = f(.WINPATH)))[[1L]], .WINPATH)
  # shapes outside the doubling model fail CLOSED
  m1 <- tryCatch({ f("a'b"); NA_character_ }, error = function(e) conditionMessage(e))
  expect_true(grepl("quote", m1, fixed = TRUE))
  m2 <- tryCatch({ f('a"b'); NA_character_ }, error = function(e) conditionMessage(e))
  expect_true(grepl("quote", m2, fixed = TRUE))
  m3 <- tryCatch({ f(NA_character_); NA_character_ },
                  error = function(e) conditionMessage(e))
  expect_true(grepl("scalar", m3, fixed = TRUE))
})
