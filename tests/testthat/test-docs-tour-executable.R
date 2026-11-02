# test-docs-tour-executable.R: DS-4 US-H1 tour-page executable-promise law
# (docs/site v4). tour.Rmd embeds a synthetic byte-building face (2bit writer,
# packed-bases records, the 96-channel claim, a ledger-documented variant drop)
# and the prose states numbers about what that face produces. The law parses
# the Rmd chunks, evaluates the R face IN-PROCESS in a sandbox over the
# msuiter namespace, and re-derives every prose numeral from the live face:
# channel count, input-record and ledger counts, SNV/sample counts, base-level
# context, the committed geometry of the written bytes, and the error-surface
# classes. A stale hand-edited numeral reddens and is named. The instrument is
# tools/tour-face.R (single re-derivation face; the law stays thin). The audit
# is fail-closed: zero chunks is vacuous-RED, a dropped chunk is named, a
# tampered numeral is named (firing controls below).

# --- instrument access (fail-closed, DS-3 posture) --------------------------------

.te_tool <- function() {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  f <- .ms_src("tools/tour-face.R")
  if (is.na(f) || !file.exists(f)) {
    stop("tools/tour-face.R missing (US-H1 defect)")
  }
  f
}

# Source the tool without running its CLI main: the MSUITER_TOOL_NO_MAIN marker
# is the source-vs-invoke discriminator the tool family honors.
.te_env <- function() {
  f <- .te_tool()
  e <- new.env(parent = globalenv())
  Sys.setenv(MSUITER_TOOL_NO_MAIN = "1")
  on.exit(Sys.unsetenv("MSUITER_TOOL_NO_MAIN"), add = TRUE)
  source(f, local = e)
  need <- c("tf_chunks", "tf_claims", "tf_sandbox", "tf_read2bit", "tf_unpack",
            "tf_fixture_params", "tf_audit")
  for (n in need) {
    if (!exists(n, envir = e, inherits = FALSE)) {
      stop("tour-face tool lost its callable face: ", n)
    }
  }
  e
}

# --- page locator --------------------------------------------------------------------

.te_page <- function() {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  f <- file.path(.ms_root, "vignettes", "tour.Rmd")
  if (!file.exists(f)) stop("vignettes/tour.Rmd missing from the checkout (US-H1 defect)")
  f
}

.te_need_knitr <- function() {
  if (!requireNamespace("knitr", quietly = TRUE)) {
    skip("knitr unavailable for the in-process face evaluation (R CMD check context)")
  }
}

# --- memoized single evaluation of the page face --------------------------------------

.te_state <- new.env()

.te_run <- function() {
  if (exists("res", envir = .te_state, inherits = FALSE)) {
    return(get("res", envir = .te_state))
  }
  e <- .te_env()
  page <- .te_page()
  chunks <- e$tf_chunks(page)
  sb <- e$tf_sandbox(page, .ms_root)
  par <- e$tf_fixture_params(page, chunks)
  res <- list(e = e, page = page, chunks = chunks, sb = sb, par = par)
  assign("res", res, envir = .te_state)
  res
}

# Run the full audit against the real page.
.te_audit <- function(ctx = .te_run()) {
  ctx$e$tf_audit(ctx$page, ctx$sb, ctx$par)
}

# --- green halves ---------------------------------------------------------------------

test_that("US-H1 the tour chunks parse and the embedded face evaluates in-process", {
  .te_need_knitr()
  ctx <- .te_run()
  nrs <- sum(ctx$chunks$lang == "r" & ctx$chunks$eval)
  expect_true(nrs >= 5L, info = "the tour face must carry the fixture/variants/tally/signature/errors chunks")
  for (nm in c("fixture", "variants", "tally", "signature", "errors")) {
    expect_true(nm %in% ctx$chunks$name, info = paste0("chunk missing: ", nm))
  }
  for (nm in c("genome", "v", "tab", "cat1", "sig")) {
    expect_true(exists(nm, envir = ctx$sb$env, inherits = FALSE),
                info = paste0("face variable absent after in-process evaluation: ", nm))
  }
  expect_true(file.exists(ctx$sb$genome_snapshot) &&
                 file.size(ctx$sb$genome_snapshot) > 0L,
               info = "the written fixture genome was not snapshotted before cleanup")
  cat("US-H1 PARSE CENSUS: chunks-r=", nrs, " face-vars-live=5\n", sep = "")
})

test_that("US-H1 every prose numeral about the face re-derives from the live face", {
  .te_need_knitr()
  ctx <- .te_run()
  a <- .te_audit(ctx)
  expect_identical(a$violations, character(0),
                   info = paste0(a$violations, collapse = "\n"))
  expect_true(a$n_claims >= 8L, info = "vacuous: too few claims witnessed")
  cat("US-H1 TOUR-EXEC CENSUS: claims=", a$n_claims,
      " re-derived=", a$n_checked, " violations=0\n", sep = "")
})

test_that("US-H1 the written bytes carry the face's own geometry", {
  .te_need_knitr()
  ctx <- .te_run()
  g <- ctx$e$tf_read2bit(ctx$sb$genome_snapshot)
  expect_identical(as.character(g$magic), "0x1A412743")
  expect_identical(g$nrec, 2L)
  # index walk: stored offsets must be exactly where the walk puts the records
  idx <- g$index
  expect_identical(idx$name, c("chr1", "chr2"))
  walk <- 16L + sum(vapply(seq_along(idx$name),
                           function(i) 1L + nchar(idx$name[i]) + 4L, integer(1)))
  expect_identical(idx$off[1L], walk, info = "first record offset off the index walk")
  expect_true(idx$off[2L] > idx$off[1L], info = "record offsets not increasing")
  expect_identical(as.integer(g$file_size),
                   idx$off[2L] + length(g$rec_bytes[[2L]]),
                   info = "byte size off the geometry: file ends where the last record ends")
  cat("US-H1 BYTES CENSUS: size=", g$file_size, " offsets=", idx$off[1L],
      ",", idx$off[2L], " violations=0\n", sep = "")
})

# --- red halves: firing controls --------------------------------------------------------

test_that("US-H1 a tampered claimed numeral in a copied page is named", {
  .te_need_knitr()
  ctx <- .te_run()
  lines <- readLines(ctx$page, warn = FALSE)
  hit <- grep("96 SBS channels", lines, fixed = TRUE)
  expect_length(hit, 1L)
  bad <- lines
  bad[hit] <- sub("96 SBS channels", "97 SBS channels", bad[hit], fixed = TRUE)
  tmp <- tempfile(fileext = ".Rmd"); writeLines(bad, tmp)
  a <- ctx$e$tf_audit(tmp, ctx$sb, ctx$par)
  expect_true(any(grepl("channel-count", a$violations, fixed = TRUE)),
               info = paste0(a$violations, collapse = "\n"))
  expect_true(any(grepl("97", a$violations, fixed = TRUE)),
               info = "the tampered numeral itself must appear in the violation")
})

test_that("US-H1 dropping the fixture chunk reddens the law and names it", {
  .te_need_knitr()
  ctx <- .te_run()
  lines <- readLines(ctx$page, warn = FALSE)
  ch <- ctx$chunks
  i <- which(ch$name == "fixture")
  expect_length(i, 1L)
  bad <- lines[-(ch$start[i]:ch$end[i])]
  tmp <- tempfile(fileext = ".Rmd"); writeLines(bad, tmp)
  expect_error(ctx$e$tf_claims(tmp), "fixture")
})

test_that("US-H1 a vacuous zero-chunk parse is RED, never empty-green", {
  .te_need_knitr()
  ctx <- .te_run()
  lines <- readLines(ctx$page, warn = FALSE)
  # keep only the prose: strip every fenced block wholesale
  fence <- grep("^```", lines)
  bad <- rep(FALSE, length(lines))
  k <- 1L
  while (k <= length(fence)) {
    a <- fence[k]; b <- if (k + 1L <= length(fence)) fence[k + 1L] else length(lines)
    bad[a:b] <- TRUE; k <- k + 2L
  }
  tmp <- tempfile(fileext = ".Rmd"); writeLines(lines[!bad], tmp)
  expect_error(ctx$e$tf_chunks(tmp), "vacuous")
  # the CLI face refuses too, with a spoken word
  r <- suppressWarnings(system2(.ms_rscript(),
                                c(.te_tool(), paste0("--root=", .ms_root), paste0("--page=", tmp), "--check"),
                                stdout = TRUE, stderr = TRUE))
  st <- attr(r, "status")
  expect_true(!is.null(st) && as.integer(st) != 0L, info = "CLI accepted a vacuous page")
  expect_true(grepl("vacuous", paste0(as.character(r), collapse = "\n"), fixed = TRUE))
})
