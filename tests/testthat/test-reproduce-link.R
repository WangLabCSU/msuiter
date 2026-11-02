# test-reproduce-link.R: DS-3 US-G3 reproduce-face is link-not-fork law
# (docs/site v3). The paper lane banked the one-command reproduction face at
# docs/paper/reproduce.sh (default --verify: dry-run verification of every
# sealed number against committed bytes; its attestation ledger rides
# docs/paper/reproduction-proof.md). The site must LINK to that face, never
# fork it. This law demands: the navigation docs name the target by path and
# name the --verify face; the target exists and itself names --verify; and
# the repo-wide census sees EXACTLY ONE reproduction script -- no second
# reproduce.sh anywhere, no second *.sh anywhere implementing the --verify
# face, and no top-level tools/*.sh implementing reproduce semantics.
# Firing controls: a planted second reproduce.sh, a planted tools/ verify
# script, an unlinked doc, an unnamed face and a deleted target all redden;
# the constructed-perfect synthetic root greens clean (vacuous-green ban).

.rl_TARGET <- "docs/paper/reproduce.sh"
.rl_PROOF <- "docs/paper/reproduction-proof.md"
.rl_FACE <- "--verify"

# --- the doc-reference audit ----------------------------------------------------------

.rl_audit_doc <- function(doc_text, root) {
  v <- character(0)
  if (!grepl(.rl_TARGET, doc_text, fixed = TRUE)) {
    v <- c(v, paste0("docs do not reference the one-command reproduction face ",
                     "by path: ", .rl_TARGET))
  }
  if (!grepl(.rl_FACE, doc_text, fixed = TRUE)) {
    v <- c(v, paste0("docs do not name the reproduction face ", .rl_FACE))
  }
  if (!grepl(.rl_PROOF, doc_text, fixed = TRUE)) {
    v <- c(v, paste0("docs do not link the reproduction attestation ledger: ",
                     .rl_PROOF))
  }
  tgt <- file.path(root, .rl_TARGET)
  if (!file.exists(tgt)) {
    v <- c(v, paste0("reproduction target absent: ", .rl_TARGET))
  } else {
    tb <- paste0(readLines(tgt, warn = FALSE), collapse = "\n")
    if (!grepl(.rl_FACE, tb, fixed = TRUE)) {
      v <- c(v, paste0("the reproduction target does not name its ", .rl_FACE,
                       " face"))
    }
  }
  if (!file.exists(file.path(root, .rl_PROOF))) {
    v <- c(v, paste0("reproduction attestation ledger absent: ", .rl_PROOF))
  }
  v
}

# --- the no-fork census -------------------------------------------------------------------

.rl_sh_scripts <- function(root) {
  files <- list.files(root, recursive = TRUE, full.names = FALSE,
                       pattern = "[.]sh$")
  files <- files[!endsWith(files, "/")]
  files[!grepl(".git/", files, fixed = TRUE)]
}

.rl_fork_census <- function(root) {
  shs <- .rl_sh_scripts(root)
  v <- character(0)
  named <- shs[basename(shs) == basename(.rl_TARGET)]
  extra_named <- setdiff(named, .rl_TARGET)
  if (length(extra_named)) {
    v <- c(v, paste0("second reproduction script: ",
                     paste0(extra_named, collapse = ", ")))
  }
  verify <- character(0)
  for (f in shs) {
    b <- paste0(readLines(file.path(root, f), warn = FALSE), collapse = "\n")
    if (grepl(.rl_FACE, b, fixed = TRUE)) verify <- c(verify, f)
  }
  extra_verify <- setdiff(verify, .rl_TARGET)
  if (length(extra_verify)) {
    v <- c(v, paste0("second script implements the ", .rl_FACE,
                     " face: ", paste0(extra_verify, collapse = ", ")))
  }
  tools_sh <- list.files(file.path(root, "tools"), pattern = "[.]sh$",
                         include.dirs = FALSE)
  for (f in tools_sh) {
    b <- tolower(paste0(readLines(file.path(root, "tools", f), warn = FALSE),
                        collapse = "\n"))
    if (grepl(.rl_FACE, b, fixed = TRUE) ||
        grepl("reproduc", b, fixed = TRUE)) {
      v <- c(v, paste0("top-level tools/ script implements reproduce ",
                       "semantics: tools/", f))
    }
  }
  list(violations = v, scripts = length(shs), verify_faces = length(verify),
       named = length(named))
}

# --- green halves -------------------------------------------------------------------------

test_that("US-G3 the performance-anchoring page links the one-command face by path and face-name", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  vf <- file.path(.ms_root, "vignettes", "performance-anchoring.Rmd")
  if (!file.exists(vf)) {
    stop("vignettes/performance-anchoring.Rmd missing (US-G3 defect)")
  }
  doc <- paste0(readLines(vf, warn = FALSE), collapse = "\n")
  v <- .rl_audit_doc(doc, .ms_root)
  expect_identical(v, character(0), info = paste0(v, collapse = "\n"))
  cat("US-G3 LINK CENSUS: target=", .rl_TARGET, " face-named=yes violations=0\n",
      sep = "")
})

test_that("US-G3 exactly one reproduction script exists and no tools/ fork rides the verify face", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  r <- .rl_fork_census(.ms_root)
  expect_identical(r$violations, character(0),
                   info = paste0(r$violations, collapse = "\n"))
  expect_identical(r$named, 1L)
  expect_identical(r$verify_faces, 1L)
  expect_gte(r$scripts, 1L)
  cat("US-G3 FORK CENSUS: sh-scripts=", r$scripts, " reproduce-named=", r$named,
      " verify-faced=", r$verify_faces, " forks=0\n", sep = "")
})

# --- red halves: firing controls -------------------------------------------------------------

.rl_fake_root <- function(doc_lines, extra_named = FALSE, extra_tools_sh = FALSE,
                          target = TRUE, target_has_face = TRUE,
                          proof = TRUE) {
  root <- tempfile("rl-fake-")
  dir.create(file.path(root, "docs", "paper"), recursive = TRUE)
  if (target) {
    writeLines(c("#!/usr/bin/env bash",
                 if (target_has_face) "MODE=\"${1:---verify}\"" else "MODE=legacy",
                 "echo face"),
               file.path(root, .rl_TARGET))
  }
  if (proof) {
    writeLines("# reproduction proof ledger",
               file.path(root, .rl_PROOF))
  }
  if (extra_named) {
    dir.create(file.path(root, "scripts", "extra"), recursive = TRUE)
    writeLines(c("#!/usr/bin/env bash", "MODE=\"${1:---verify}\""),
               file.path(root, "scripts", "extra", "reproduce.sh"))
  }
  if (extra_tools_sh) {
    dir.create(file.path(root, "tools"), recursive = TRUE)
    writeLines(c("#!/usr/bin/env bash", ": \"${1:---verify}\"",
                 "# this face reproduces sealed numbers"),
               file.path(root, "tools", "sync.sh"))
  }
  writeLines(c("# navigation", doc_lines), file.path(root, "docs", "NAV.md"))
  root
}

test_that("US-G3 the constructed-perfect synthetic root greens the whole law (live control)", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  doc_lines <- c(paste0("The one-command face: ", .rl_TARGET),
                 "its default --verify face dry-runs sealed numbers",
                 paste0("ledger: ", .rl_PROOF))
  root <- .rl_fake_root(doc_lines)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  doc <- paste0(readLines(file.path(root, "docs", "NAV.md"), warn = FALSE),
                collapse = "\n")
  expect_identical(.rl_audit_doc(doc, root), character(0))
  r <- .rl_fork_census(root)
  expect_identical(r$violations, character(0),
                   info = paste0(r$violations, collapse = "\n"))
  expect_identical(r$named, 1L)
  expect_identical(r$verify_faces, 1L)
})

test_that("US-G3 a planted second reproduce.sh is named by the census", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  root <- .rl_fake_root("quiet", extra_named = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  r <- .rl_fork_census(root)
  expect_true(any(grepl("second reproduction script: scripts/extra/reproduce.sh",
                        r$violations, fixed = TRUE)))
})

test_that("US-G3 a planted tools/ script riding the verify face is named", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  root <- .rl_fake_root("quiet", extra_tools_sh = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  r <- .rl_fork_census(root)
  expect_true(any(grepl("top-level tools/ script implements reproduce",
                        r$violations, fixed = TRUE)))
  expect_true(any(grepl("tools/sync.sh", r$violations, fixed = TRUE)))
})

test_that("US-G3 an unlinked doc, an unnamed face, a faceless target and a lost ledger all redden", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  good <- c(paste0("face: ", .rl_TARGET, " --verify; ledger: ", .rl_PROOF))
  base <- .rl_fake_root(good)
  on.exit(unlink(base, recursive = TRUE), add = TRUE)
  doc_good <- paste0(readLines(file.path(base, "docs", "NAV.md"), warn = FALSE),
                     collapse = "\n")
  expect_identical(.rl_audit_doc(doc_good, base), character(0))
  # unlinked doc
  r1 <- .rl_audit_doc("nothing names the face here", base)
  expect_true(any(grepl("do not reference the one-command reproduction face",
                        r1, fixed = TRUE)))
  # unnamed face
  r2 <- .rl_audit_doc(paste0("face path ", .rl_TARGET, " and ledger ",
                             .rl_PROOF), base)
  expect_true(any(grepl("do not name the reproduction face", r2, fixed = TRUE)))
  # faceless target
  bad <- .rl_fake_root(good, target_has_face = FALSE)
  on.exit(unlink(bad, recursive = TRUE), add = TRUE)
  doc_bad <- paste0(readLines(file.path(bad, "docs", "NAV.md"), warn = FALSE),
                    collapse = "\n")
  r3 <- .rl_audit_doc(doc_bad, bad)
  expect_true(any(grepl("does not name its --verify face", r3, fixed = TRUE)))
  # lost target
  gone <- .rl_fake_root(good, target = FALSE)
  on.exit(unlink(gone, recursive = TRUE), add = TRUE)
  doc_gone <- paste0(readLines(file.path(gone, "docs", "NAV.md"), warn = FALSE),
                     collapse = "\n")
  r4 <- .rl_audit_doc(doc_gone, gone)
  expect_true(any(grepl("reproduction target absent", r4, fixed = TRUE)))
  # lost ledger
  lost <- .rl_fake_root(good, proof = FALSE)
  on.exit(unlink(lost, recursive = TRUE), add = TRUE)
  doc_lost <- paste0(readLines(file.path(lost, "docs", "NAV.md"), warn = FALSE),
                     collapse = "\n")
  r5 <- .rl_audit_doc(doc_lost, lost)
  expect_true(any(grepl("attestation ledger absent", r5, fixed = TRUE)))
})
