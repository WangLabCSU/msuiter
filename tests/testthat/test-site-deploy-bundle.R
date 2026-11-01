# test-site-deploy-bundle.R: DS-2 US-4 deployable-bundle + dormant-deploy laws
# (docs/site v2). Two committed tools ride this law:
#   tools/site-bundle.R  --site=<dir> --out=<dir> [--rev=<sha>]
#       emits manifest.tsv (sha256 TAB relpath, sorted, byte-reproducible) and
#       PROVENANCE.tsv (trunk-sha stamp + file count). Re-derivation must
#       reproduce; a tampered file must be named; an empty site is vacuous-red.
#   tools/site-deploy.R  (--pages-json=<fixture> | --live) --bundle-dir=<dir>
#       reads the MEASURED Pages state and stays a no-op unless enabled: the
#       dormant path is proven by its log line, not by narration. The 404
#       fixture is the verbatim byte capture of the API probe banked by the
#       lane (byte-true fixtures law).
# Every rule carries a firing control; nothing here touches repo settings.

.sbd_root <- function() {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  b <- file.path(.ms_root, "tools", "site-bundle.R")
  d <- file.path(.ms_root, "tools", "site-deploy.R")
  if (!file.exists(b)) stop("tools/site-bundle.R missing (US-4 defect)")
  if (!file.exists(d)) stop("tools/site-deploy.R missing (US-4 defect)")
  list(bundle = b, deploy = d)
}

.sbd_run <- function(tool, args) {
  res <- suppressWarnings(system2(.ms_rscript(), c(tool, args),
                                   stdout = TRUE, stderr = TRUE))
  st <- attr(res, "status")
  list(status = if (is.null(st)) 0L else as.integer(st),
       out = paste0(as.character(res), collapse = "\n"))
}

.sbd_fixture <- function(name) {
  f <- testthat::test_path("fixtures", "site-deploy", name)
  if (!file.exists(f)) stop("committed Pages fixture missing: ", name)
  f
}

.sbd_make_site <- function() {
  site <- tempfile("ctl-site-")
  dir.create(site, recursive = TRUE)
  dir.create(file.path(site, "reference"), recursive = TRUE)
  dir.create(file.path(site, "articles"), recursive = TRUE)
  writeLines("<html><body>reference index</body></html>",
             file.path(site, "reference", "index.html"))
  writeLines("<html><body>a page</body></html>",
             file.path(site, "reference", "ms_fit.html"))
  writeLines("<html><body>welcome</body></html>",
             file.path(site, "articles", "get-started.html"))
  site
}

.sbd_make_bundle <- function(site) {
  out <- tempfile("ctl-bundle-")
  dir.create(out, recursive = TRUE)
  r <- .sbd_run(.sbd_root()$bundle,
                c(paste0("--site=", site), paste0("--out=", out),
                  "--rev=abc123def456"))
  if (!identical(r$status, 0L)) {
    stop("site-bundle tool failed on the happy path: ", r$out)
  }
  out
}

# --- green halves --------------------------------------------------------------------

test_that("US-4 the bundle manifest is re-derivable byte-for-byte (repro stamp)", {
  root <- .sbd_root()
  site <- .sbd_make_site()
  on.exit(unlink(c(site), recursive = TRUE), add = TRUE)
  o1 <- tempfile("ctl-b1-"); o2 <- tempfile("ctl-b2-")
  r1 <- .sbd_run(root$bundle, c(paste0("--site=", site), paste0("--out=", o1),
                                "--rev=abc123def456"))
  r2 <- .sbd_run(root$bundle, c(paste0("--site=", site), paste0("--out=", o2),
                                "--rev=999000feedface"))
  expect_identical(r1$status, 0L, info = r1$out)
  expect_identical(r2$status, 0L, info = r2$out)
  m1 <- readLines(file.path(o1, "manifest.tsv"), warn = FALSE)
  m2 <- readLines(file.path(o2, "manifest.tsv"), warn = FALSE)
  expect_identical(m1, m2)                      # rev does not ride the manifest
  expect_length(m1, 3L)                          # exactly the three site files
  expect_true(all(grepl("\t", m1, fixed = TRUE)))
  rel <- sub("^[^\t]*\t", "", m1)                 # canonical order: by rel path
  expect_identical(rel, sort(rel))
  prov <- readLines(file.path(o1, "PROVENANCE.tsv"), warn = FALSE)
  expect_true(any(grepl("trunk_sha\tabc123def456", prov, fixed = TRUE)))
  expect_true(any(grepl("files\t3", prov, fixed = TRUE)))
  unlink(c(o1, o2), recursive = TRUE)
})

test_that("US-4 manifest hashing is in-process: a stripped PATH cannot starve the bundle", {
  root <- .sbd_root()
  site <- .sbd_make_site()
  out <- tempfile("ctl-b6-")
  old <- Sys.getenv("PATH")
  Sys.setenv(PATH = "nonexistent-path-for-hashing-law")
  on.exit({
    Sys.setenv(PATH = old)
    unlink(c(site, out), recursive = TRUE)
  }, add = TRUE)
  r <- .sbd_run(root$bundle, c(paste0("--site=", site), paste0("--out=", out),
                                "--rev=abc123def456"))
  expect_identical(r$status, 0L, info = r$out)
  man <- readLines(file.path(out, "manifest.tsv"), warn = FALSE)
  expect_length(man, 3L)
  hex <- strsplit("0123456789abcdef", "")[[1L]]
  for (m in man) {
    p <- strsplit(m, "\t", fixed = TRUE)[[1L]]
    expect_identical(nchar(p[1L]), 64L)
    expect_true(all(strsplit(p[1L], "")[[1L]] %in% hex))
  }
})

test_that("US-4 the dormant deploy path speaks its proof line on the measured 404", {
  root <- .sbd_root()
  site <- .sbd_make_site()
  bundle <- .sbd_make_bundle(site)
  r <- .sbd_run(root$deploy, c(paste0("--pages-json=",
                                      .sbd_fixture("pages-404.json")),
                               paste0("--bundle-dir=", bundle)))
  expect_identical(r$status, 0L, info = r$out)
  expect_true(grepl("DEPLOY DORMANT", r$out, fixed = TRUE))
  expect_true(grepl("Pages not enabled", r$out, fixed = TRUE))
  unlink(c(site, bundle), recursive = TRUE)
})

# --- red halves: controls that must fire ------------------------------------------------

test_that("US-4 tampering a site file reddens manifest reproducibility and names it", {
  root <- .sbd_root()
  site <- .sbd_make_site()
  o1 <- tempfile("ctl-b3-"); o2 <- tempfile("ctl-b4-")
  r1 <- .sbd_run(root$bundle, c(paste0("--site=", site), paste0("--out=", o1),
                                "--rev=abc123"))
  expect_identical(r1$status, 0L, info = r1$out)
  writeLines("<html><body>reference index TAMPERED</body></html>",
             file.path(site, "reference", "index.html"))
  r2 <- .sbd_run(root$bundle, c(paste0("--site=", site), paste0("--out=", o2),
                                "--rev=abc123"))
  expect_identical(r2$status, 0L, info = r2$out)
  d <- setdiff(readLines(file.path(o2, "manifest.tsv"), warn = FALSE),
               readLines(file.path(o1, "manifest.tsv"), warn = FALSE))
  expect_true(any(grepl("reference/index.html", d, fixed = TRUE)))
  unlink(c(site, o1, o2), recursive = TRUE)
})

test_that("US-4 an empty site tree can not bundle (vacuous guard)", {
  root <- .sbd_root()
  site <- tempfile("ctl-empty-")
  dir.create(site, recursive = TRUE)
  out <- tempfile("ctl-b5-")
  r <- .sbd_run(root$bundle, c(paste0("--site=", site), paste0("--out=", out),
                               "--rev=abc123"))
  expect_true(r$status != 0L)
  expect_true(grepl("vacuous", r$out, fixed = TRUE))
  unlink(c(site, out), recursive = TRUE)
})

test_that("US-4 the deploy guard arms only on an enabled measurement", {
  root <- .sbd_root()
  site <- .sbd_make_site()
  bundle <- .sbd_make_bundle(site)
  r <- .sbd_run(root$deploy, c(paste0("--pages-json=",
                                      .sbd_fixture("pages-enabled-synthetic.json")),
                               paste0("--bundle-dir=", bundle)))
  expect_identical(r$status, 0L, info = r$out)
  expect_true(grepl("DEPLOY ARMED", r$out, fixed = TRUE))
  expect_true(grepl("controller dispatch", r$out, fixed = TRUE))
  unlink(c(site, bundle), recursive = TRUE)
})

test_that("US-4 a missing measurement source or incomplete bundle is refused", {
  root <- .sbd_root()
  site <- .sbd_make_site()
  bundle <- .sbd_make_bundle(site)
  r1 <- .sbd_run(root$deploy, paste0("--bundle-dir=", bundle))
  expect_true(r1$status != 0L)
  expect_true(grepl("no Pages state", r1$out, fixed = TRUE))
  empty <- tempfile("ctl-bundle-empty-")
  dir.create(empty, recursive = TRUE)
  r2 <- .sbd_run(root$deploy, c(paste0("--pages-json=",
                                        .sbd_fixture("pages-404.json")),
                                 paste0("--bundle-dir=", empty)))
  expect_true(r2$status != 0L)
  expect_true(grepl("bundle incomplete", r2$out, fixed = TRUE))
  unlink(c(site, bundle, empty), recursive = TRUE)
})
