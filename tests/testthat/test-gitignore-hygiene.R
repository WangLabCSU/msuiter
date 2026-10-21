# test-gitignore-hygiene.R: the check-ignore unit for the Python bytecode
# hygiene rules (#28 gate family: /bench/**/__pycache__/, /tools/**/__pycache__/,
# /tools/**/.pytest_cache/). The campaign tooling's byte-classes keep
# re-appearing as lane dirt when a rule is silently absent or shadowed --
# check-ignore --no-index -v is the only oracle that reports WHICH rule won,
# so this unit pins the report (source : line : pattern) to the declared
# rule forms: a rule that does not fire, or fires from an unexpected shape,
# fails the gate. A green reading is worthless without discrimination, so
# the probe is proven against negative controls (unignored siblings) and
# the rule-form half is exercised as a red/green pair in a scratch repo
# (TDD: the red half shows the assertions are live before the rules ship).

# Shared capability probe: the rules live in the checkout's .gitignore and
# the oracle is git itself; installed-package check layouts skip on the
# sanctioned ledger phrase (Skip Law).
.ms_hyg_root <- function() {
  root <- normalizePath(testthat::test_path("../.."), mustWork = FALSE)
  if (!file.exists(file.path(root, "DESCRIPTION")) ||
      system2("git", c("-C", root, "rev-parse", "--git-dir"),
              stdout = NULL, stderr = NULL) != 0L) {
    return(NULL)
  }
  root
}

# system2 on this base returns the captured output vector with the exit
# status in attr(res, "status"), and warns on any nonzero status (house
# idiom, test-kernel-cli.R .kernel_status).
.ms_hyg_status <- function(res) {
  st <- attr(res, "status")
  if (is.null(st)) 0L else as.integer(st)
}

# git check-ignore -v --stdin oracle. Report: one line per IGNORED probe
# ("<source>:<linenum>:<pattern>\t<path>"); non-ignored probes stay silent.
# Exit law (git man check-ignore): 0 when EVERY given path is excluded, 1
# when any given path is NOT excluded, 128+ for real errors -- the status is
# itself load-bearing evidence, asserted by every caller. This base's
# system2(stdin=) is a file redirect, so the probes travel in a tempfile.
.ms_check_ignore <- function(root, probes, excl = NULL) {
  pf <- tempfile("hyg-probes-")
  writeLines(probes, pf, useBytes = TRUE)
  args <- c("-C", root, "check-ignore", "--no-index", "-v", "--stdin")
  if (!is.null(excl)) args <- c("-c", excl, args)
  res <- suppressWarnings(system2("git", args, stdin = pf,
    stdout = TRUE, stderr = TRUE))
  st <- .ms_hyg_status(res)
  if (!st %in% c(0L, 1L)) {
    stop("git check-ignore errored with status ", st, ": ",
         paste0(as.character(res), collapse = " | "))
  }
  # The check-ignore report arrives with the runner's native line/report
  # shape; .ms_hyg_norm brings it to the form the suffix law is authored for.
  list(status = st, out = .ms_hyg_norm(as.character(res)))
}

.ms_hyg_norm <- function(out) {
  # Transport-layer report normalization only (never the law's semantics):
  # native path separators, and carriage-return tails from a process pipe the
  # line splitter left standing. Bytes beyond THESE surface as the length
  # probe's numbers, naming the residue exactly.
  x <- gsub("\\", "/", as.character(out), fixed = TRUE)
  gsub("[\r]+$", "", x)
}

# The report suffix a firing rule must produce (exact -- the pattern text
# and the tab-separated path, so a shadowing rule with a different shape
# cannot masquerade).
.ms_expect_fires <- function(out, i, probe, pattern) {
  suffix <- paste0(pattern, "\t", probe)
  tail <- substring(out[i], nchar(out[i]) - nchar(suffix) + 1L)
  # Length first: a bytes-mismatch alone leaves the residue uncounted, and a
  # delta of one is a standing \r, of two a \r\n pair, of a path length a
  # separator class the normalization does not yet know.
  expect_identical(nchar(tail), nchar(suffix))
  # Equal lengths with unequal bytes name a character-class substitution; the
  # raw bytes ride info= because the test context sinks stdout/stderr and
  # swallows message() (measured) -- the failure message is the only way out.
  expect_identical(tail, suffix,
                   info = paste0("tail-bytes: ",
                                 paste0(as.integer(charToRaw(tail, type = "single")), collapse = ","),
                                 " suffix-bytes: ",
                                 paste0(as.integer(charToRaw(suffix, type = "single")), collapse = ",")))
}

test_that("the shipped .gitignore rules FIRE for their declared classes", {
  root <- .ms_hyg_root()
  if (is.null(root)) {
    skip("requires the source checkout (installed-package check context)")
  }
  spec <- c(
    "tools/hyg_probe/__pycache__/w.pyc"               = "/tools/**/__pycache__/",
    "bench/hyg_probe/__pycache__/w.pyc"               = "/bench/**/__pycache__/",
    "tools/hyg_probe/deep/__pycache__/w.pyc"          = "/tools/**/__pycache__/",
    "tools/__pycache__/w.pyc"                         = "/tools/**/__pycache__/",
    "tools/hyg_probe/.pytest_cache/cache"             = "/tools/**/.pytest_cache/"
  )
  r <- .ms_check_ignore(root, names(spec))
  expect_identical(r$status, 0L)                      # 0 == every given path excluded
  expect_identical(length(r$out), length(spec))      # every probe reported -> all fire
  for (i in seq_along(spec)) {
    .ms_expect_fires(r$out, i, names(spec)[i], unname(spec[[i]]))
  }
})

test_that("the probe discriminates: siblings of the ignored classes stay tracked", {
  root <- .ms_hyg_root()
  if (is.null(root)) {
    skip("requires the source checkout (installed-package check context)")
  }
  negatives <- c(
    "scripts/__pycache__/w.pyc",           # outside both anchored roots
    "docs/__pycache__/w.pyc",
    "tools/hyg_probe/__pycache_x/w.pyc",   # near-miss directory names
    "tools/hyg_probe/__pycacheX/w.pyc",
    "tools/hyg_probe/w.pyc"                # bare file next to a cache dir
  )
  r <- .ms_check_ignore(root, negatives)
  expect_identical(r$status, 1L)           # 1 == at least one given path not excluded
  expect_identical(length(r$out), 0L)      # silence == NONE ignored == probe is live
})

test_that("rule form is attested red/green in a scratch repo (no shadowing oracle drift)", {
  root <- .ms_hyg_root()
  if (is.null(root)) {
    skip("requires the source checkout (installed-package check context)")
  }
  td <- tempfile("hyg-ign-")
  probe <- "tools/pkg/__pycache__/w.pyc"
  if (!dir.create(td, recursive = TRUE) ||
      !dir.create(file.path(td, "tools", "pkg", "__pycache__"), recursive = TRUE) ||
      !file.create(file.path(td, "tools", "pkg", "__pycache__", "w.pyc"))) {
    stop("scratch tree not creatable")
  }
  ini <- suppressWarnings(system2("git", c("-C", td, "init", "-q", "."),
                                  stdout = TRUE, stderr = TRUE))
  if (!identical(.ms_hyg_status(ini), 0L)) {
    # git init is unavailable in this environment: the oracle itself cannot be
    # exercised -- that is a real loss of attestation, not a skip.
    stop("git init failed in the scratch dir (status ", .ms_hyg_status(ini),
         "): ", paste0(as.character(ini), collapse = " | "))
  }
  ign <- file.path(td, ".gitignore")
  # RED: no rules shipped -> the identical probe stays silent (assertions live).
  writeLines("# empty during the red half", ign)
  r <- .ms_check_ignore(td, probe, excl = "core.excludesFile=/dev/null")
  expect_identical(r$status, 1L)           # not ignored without the rules
  expect_identical(length(r$out), 0L)
  # GREEN: ship the rule forms verbatim from the repo's own .gitignore so the
  # scratch attestation exercises the shipped text, not a hand-retyped twin.
  # The probed rule leads the file, pinning the reported source line to 1.
  shipped <- readLines(file.path(root, ".gitignore"), warn = FALSE)
  rules <- shipped[grepl("^/(tools|bench)/\\*\\*/(__pycache__|\\.pytest_cache)/$",
                         shipped)]
  expect_true(length(rules) >= 3L)
  tools_rule <- "/tools/**/__pycache__/"
  if (!tools_rule %in% rules) {
    stop("shipped tools rule form drifted: ", paste0(rules, collapse = ", "))
  }
  writeLines(c(tools_rule, setdiff(rules, tools_rule)), ign)
  r <- .ms_check_ignore(td, probe, excl = "core.excludesFile=/dev/null")
  expect_identical(r$status, 0L)           # the given path is now excluded
  # source is reported relative to the invoking context, so pin the load-
  # bearing suffix: the shipped rule fired from .gitignore line 1 on the probe.
  expect_true(length(r$out) == 1L && endsWith(r$out,
    paste0(".gitignore:1:", tools_rule, "\t", probe)),
    info = paste0("rows=", length(r$out), ": ",
                  paste0(vapply(r$out, function(z) paste0("[", z, "]"),
                               character(1L)), collapse = " | ")))
})

test_that("the windows report shape normalizes (synthetic backslash oracle, no git needed)", {
  # The normalization above exists for a platform this runner cannot reach:
  # fire it from the native shape directly. The control is LIVE by
  # construction -- the same tail assertion must FAIL on the un-normalized
  # bytes, proving the discrimination is real and not a vacuous pass.
  probe <- "tools/hyg_probe/__pycache__/w.pyc"
  rule <- "/tools/**/__pycache__/"
  win <- paste0("D:/a/msuiter/.gitignore:1:", rule, "\t",
                gsub("/", "\\", probe, fixed = TRUE))
  suffix <- paste0(rule, "\t", probe)
  tail_norm <- substring(.ms_hyg_norm(win),
                         nchar(.ms_hyg_norm(win)) - nchar(suffix) + 1L)
  tail_raw <- substring(win, nchar(win) - nchar(suffix) + 1L)
  expect_identical(tail_norm, suffix)      # normalized: the law matches
  expect_false(identical(tail_raw, suffix))# native shape: law must NOT match
})
