# Reference-format assertion: the channel tables must stay identical to the
# SigProfilerPlotting (BSD-2) reference_formats files bundled under
# tools/channel-reference/ (fetched 2026-09-28, provenance in that README).
#
# SBS192 has no upstream reference format; the generator derives it from the
# SBS384 layout (data-raw/build_channels.R), so the SBS384 assertion anchors
# its SBS96 core transitively.
#
# This is a repository-drift guard: it runs in CI on the checkout and skips
# under R CMD check, where the source-tree layout is not reachable (same
# semantics as the channels.rs sync guard).

.ms_reference_labels <- function(name) {
  path <- testthat::test_path(
    file.path("..", "..", "tools", "channel-reference", paste0(name, ".txt"))
  )
  if (!file.exists(path)) {
    skip("tools/channel-reference not available (R CMD check context)")
  }
  labels <- readLines(path, warn = FALSE)
  labels <- trimws(labels)
  labels[nzchar(labels)]
}

test_that("channel tables match the bundled SigProfilerPlotting reference formats", {
  tables <- get("channel_tables", envir = asNamespace("msuiter"))
  for (nm in c("SBS96", "SBS384", "SBS1536", "DBS78")) {
    expect_identical(
      tables[[nm]]$labels,
      .ms_reference_labels(nm),
      info = nm
    )
  }
})
