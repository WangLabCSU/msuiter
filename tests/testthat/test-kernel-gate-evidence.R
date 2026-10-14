# P1 kernel-extension lane, face (a): mechanical gate over the committed
# evidence of the one-shot bit-equivalence experiment
# (tools/kl-gate-p1/result.md, produced by tools/kl-gate-p1/run_gate.R).
#
# This is NOT the experiment itself and deliberately never runs NMF or the
# kernel (ARCHITECTURE §7.1 / D11 / A8: the ‖ΔW‖F/‖W‖F < 1e-10 comparison
# against R NMF::nmf(brunet) is a one-shot fixed-platform record, not a
# CI-per-run gate). What is CI-enforced is the RECORD: the committed
# result.md must exist, carry the frozen protocol markers, and show every
# measured endpoint ratio strictly below the 1e-10 acceptance criterion.
# A missing, truncated, or numerically-over-budget evidence file is red --
# same "committed attestation, mechanically audited" posture as
# test-docs-sync.R over the ROADMAP checkbox claims and
# test-catalog-currency.R over the golden downloads page.
#
# Repository-only: gated on .ms_root + file presence, never on an
# accidental miss (helper-check-layout.R discipline).

.gate_repo_file <- function(rel) {
  if (is.na(.ms_root)) {
    skip("repository checkout not locatable (R CMD check context)")
  }
  f <- file.path(.ms_root, rel)
  if (!file.exists(f)) {
    # In a locatable repo checkout the evidence is committed content: its
    # absence is a gate failure, never a skip (an unrun experiment must not
    # masquerade as a passing audit).
    stop(paste0("required committed evidence missing: ", rel), call. = FALSE)
  }
  f
}

test_that("P1 bit-equivalence gate result.md carries a green verdict", {
  res <- readLines(.gate_repo_file(file.path("tools", "kl-gate-p1",
    "result.md")), warn = FALSE)
  # Frozen frame markers.
  expect_match(paste(res, collapse = "\n"), "VERDICT: PASS")
  expect_match(paste(res, collapse = "\n"), "protocol=1")
  # The gate criterion, stated verbatim in the evidence header.
  expect_match(paste(res, collapse = "\n"), "1e-10")

  # Every endpoint table row: | case | T | relW | relH | ... | PASS |
  rows <- grep("^\\|[[:space:]]*case[0-9]+", res, value = TRUE)
  expect_gte(length(rows), 6L) # >= 2 endpoints x 3 cases
  for (row in rows) {
    cells <- trimws(strsplit(row, "|", fixed = TRUE)[[1L]])
    cells <- cells[nzchar(cells)]
    expect_gte(length(cells), 5L)
    tval <- suppressWarnings(as.integer(cells[[2L]]))
    relw <- suppressWarnings(as.numeric(cells[[3L]]))
    relh <- suppressWarnings(as.numeric(cells[[4L]]))
    expect_false(is.na(tval) || is.na(relw) || is.na(relh))
    expect_true(tval %in% c(50L, 200L))
    expect_true(relw >= 0 && relw < 1e-10)
    expect_true(relh >= 0 && relh < 1e-10)
    expect_match(row, "PASS")
  }

  # Seeds recorded on the face of the evidence (the fixed-seed contract):
  # three init seeds (401/402/403, the kl-crosscheck record) must appear.
  blob <- paste(res, collapse = "\n")
  for (seed in c("401", "402", "403")) {
    expect_match(blob, paste0("init_seed=", seed))
  }
  # The stable boundary protocol used must be named.
  expect_match(blob, "msuiter-kernel")
})
