# U-M4-03b: the viz batch 2 -- four promised faces (design memo
# docs/devlog/2026-10-24-M4-03b-viz-batch2-memo.md):
#   plot_qc_dashboard, plot_pseudosig_contribution,
#   plot_hypermutator_burden, plot_opportunity_distribution
# plus the DBS78/ID83 legend palette freeze against the bundled upstream
# module (tools/channel-reference/sigProfilerPlotting-9be822f.py).
#
# Byte-truth policy: the palette tests PARSE the committed upstream file
# (no re-typed literals on either side) and pin its digest; the data
# fixtures mirror the certified return shapes of the backing faces
# (R/ms-qc-report.R, R/ms-qc-sentries.R, R/stratify.R, R/ms-convert.R).

skip_if_no_ggplot <- function() {
  skip_if_not_installed("ggplot2")
  TRUE
}

.b2_root <- function() {
  has <- function(dir) file.exists(file.path(dir, "DESCRIPTION")) &&
    file.exists(file.path(dir, "NAMESPACE")) &&
    file.exists(file.path(dir, "tools", "channel-reference",
                          "sigProfilerPlotting-9be822f.py"))
  dir <- normalizePath(getwd())
  # check-layout-sim layout: tests ride as a sibling of the expanded tree
  exx_raw <- file.path(dir, "..", "..", "msuiter.Exx")
  if (file.exists(exx_raw)) {
    exx <- normalizePath(exx_raw)
    if (has(exx)) return(exx)
  }
  # The walker RETURNS its verdict -- a decision never lives inside the
  # loop. fail() here used to look like a break but records and continues
  # (this base's expectation semantics), so the exhausted walk spun for
  # hours under covr's installed copy (witnessed 2026-10-24).
  repeat {
    if (has(dir)) return(dir)
    up <- normalizePath(file.path(dir, ".."))
    if (identical(up, dir)) return(NULL)
    dir <- up
  }
}

# Installed copies carry no tools/: the byte-truth block skips there with
# the sanctioned-absence wording (covr-divergences.tsv law) and runs its
# full battery in the repo-mode testthat arms.
.b2_root_or_skip <- function() {
  root <- .b2_root()
  if (is.null(root)) {
    skip("tools/ is not shipped in the installed package; the byte-truth block runs in full in the repo-mode testthat arms")
  }
  root
}

.b2_pyfile <- function() {
  file.path(.b2_root_or_skip(), "tools", "channel-reference",
            "sigProfilerPlotting-9be822f.py")
}

# Parse the `colors = [...]` literal of one make_pickle_file legend branch
# out of the committed upstream module. The upstream stores each color as a
# `[N / 256, N / 256, N / 256]` triple; we parse per line (this renamed-R
# base's gregexpr attr path is unreliable on this pattern class -- the
# line-split face is dependency-free) and hex-normalize. The count is
# pinned by the caller so a vacuous parse can never pass
# (governance-scan-integrity law).
.b2_upstream_palette <- function(context, n) {
  src <- readLines(.b2_pyfile(), warn = FALSE)
  hdr <- paste0("^\\s*elif context == \"", context, "\":\\s*$")
  start <- grep(hdr, src)
  expect_identical(length(start), 1L)
  opens <- grep("^\\s*colors\\s*=\\s*\\[\\s*$", src)
  opens <- opens[opens > start[[1]]]
  expect_gte(length(opens), 1L)
  open <- opens[[1]]
  closes <- grep("^\\s*\\]", src)
  closes <- closes[closes > open]
  expect_lte(min(closes) - open, n + 3L) # a legend palette is one triple per line
  hexes <- character()
  for (i in open:min(closes)) {
    line <- trimws(src[i])
    if (grepl("/ *256", line)) {
      nums <- suppressWarnings(as.integer(strsplit(line, "[^0-9]+")[[1]]))
      nums <- nums[!is.na(nums)]
      expect_identical(length(nums), 6L)
      expect_identical(nums[c(2, 4, 6)], c(256L, 256L, 256L))
      hexes <- c(hexes, toupper(sprintf("#%02X%02X%02X",
                                        nums[1], nums[3], nums[5])))
    }
  }
  expect_identical(length(hexes), n)
  unname(hexes)
}

# Cross-check channel: the mapping-table TSVs (RGB/256 per class) must
# reproduce the same hex vector -- parsing and transcription agree or fail.
.b2_tsv_palette <- function(tsv) {
  tab <- utils::read.table(file.path(.b2_root_or_skip(), "tools", "channel-reference", tsv),
                    sep = "\t", header = TRUE, stringsAsFactors = FALSE,
                    check.names = TRUE)
  toupper(sprintf("#%02X%02X%02X", tab$red, tab$green, tab$blue))
}

test_that("the root walker returns, never spins, when the ancestry holds no root", {
  # The exhausted walk used to record fail() forever inside repeat (fail()
  # continues on this base); witnessed 2026-10-24 as a covr shard stuck for
  # hours. GREEN: from a rootless ancestry the walk comes back NULL in
  # bounded time.
  deep <- file.path(tempdir(), "b2-nowhere", "deeper")
  dir.create(deep, recursive = TRUE, showWarnings = FALSE)
  old <- getwd(); setwd(deep); on.exit(setwd(old), add = TRUE)
  t0 <- proc.time()[["elapsed"]]
  root <- .b2_root()
  expect_true(is.null(root))
  expect_lt(as.numeric(proc.time()[["elapsed"]] - t0), 5)
})

# ---------------------------------------------------------------------------
# Byte-truth anchor: the bundled upstream module
# ---------------------------------------------------------------------------

test_that("the bundled upstream plotting module carries the pinned digest", {
  expect_true(file.exists(.b2_pyfile()))
  expect_identical(as.character(tools::md5sum(.b2_pyfile())[[1]]),
                   "76f970ef1e13684c85548ebbb91ffd9f")
})

test_that("both legend branches parse to their pinned palette widths", {
  dbs <- .b2_upstream_palette("DBS78", 10L)
  id <- .b2_upstream_palette("ID83", 16L)
  expect_true(all(grepl("^#[0-9A-F]{6}$", c(dbs, id))))
  # Channel 2: the mapping-table TSVs (rgb/256 transcription) must agree
  # with the byte parse -- two independent witnesses, one truth.
  expect_identical(.b2_tsv_palette("DBS78.tsv"), dbs)
  expect_identical(.b2_tsv_palette("ID83.tsv"), id)
})

test_that("the R DBS78 palette equals the parsed upstream bytes", {
  consts <- msuiter:::.ms_viz_dbs78_colors()
  expect_identical(as.character(consts),
                   .b2_upstream_palette("DBS78", 10L))
  expect_identical(names(consts),
                   utils::read.table(
                     file.path(.b2_root_or_skip(), "tools", "channel-reference",
                               "DBS78.tsv"),
                     sep = "\t", header = TRUE, stringsAsFactors = FALSE,
                     check.names = TRUE)$class)
})

test_that("the R ID83 palette equals the parsed upstream bytes", {
  consts <- msuiter:::.ms_viz_id83_colors()
  expect_identical(as.character(consts),
                   .b2_upstream_palette("ID83", 16L))
  expect_identical(names(consts),
                   utils::read.table(
                     file.path(.b2_root_or_skip(), "tools", "channel-reference",
                               "ID83.tsv"),
                     sep = "\t", header = TRUE, stringsAsFactors = FALSE,
                     check.names = TRUE)$class)
})

# ---------------------------------------------------------------------------
# plot_qc_dashboard
# ---------------------------------------------------------------------------

# Mirrors the certified ms_qc_report() return (R/ms-qc-report.R:246): the
# nine columns, the burden classes from .ms_qc_burden_class (dead/low/
# standard/high), the qc_flag rules of .ms_qc_flag (artifact_share >= 0.05
# or gt_share >= 0.30 -> artifact; ct_share >= 0.40 or low burden -> watch).
.b2_qc_frame <- function() {
  total <- c(120000, 8000, 45, 3000, 90000, 150, 0)
  df <- data.frame(
    sample = sprintf("T%02d", 1:7),
    total = total,
    log10_total = log10(total),
    burden_class = c("high", "standard", "low", "standard", "high",
                     "standard", "dead"),
    gt_share = c(0.02, 0.05, 0.40, 0.01, 0.02, 0.05, NA),
    ct_share = c(0.35, 0.10, 0.10, 0.05, 0.45, 0.41, NA),
    artifact_share = c(0.02, 0.06, 0.01, 0.00, 0.08, 0.01, NA),
    artifact_sigs = c("S1", "S2;S3", "S1", "", "S2", "", ""),
    qc_flag = c("ok", "artifact", "artifact", "ok", "artifact", "watch",
                "ok"),
    stringsAsFactors = FALSE
  )
  attr(df, "ms_qc_provenance") <- "catalog 52bd0376 | sentries 0.05/0.30/0.40"
  df
}

test_that("plot_qc_dashboard returns the documented two-panel build", {
  skip_if_no_ggplot()
  p <- plot_qc_dashboard(.b2_qc_frame())
  expect_true(inherits(p, "ggplot"))
  panels <- unname(unlist(lapply(p$layers, function(l) {
    if (!is.null(l$data$panel)) as.character(l$data$panel)
  }), use.names = FALSE))
  expect_setequal(unique(panels), c("burden", "sentries"))
  expect_true(any(vapply(p$layers, function(l)
    inherits(l$geom, "GeomBar") || inherits(l$geom, "GeomCol"),
    logical(1L))))
  expect_true(any(vapply(p$layers, function(l)
    inherits(l$geom, "GeomPoint"), logical(1L))))
})

test_that("plot_qc_dashboard draws the stored values, never re-derives them", {
  skip_if_no_ggplot()
  df <- .b2_qc_frame()
  p <- plot_qc_dashboard(df)
  burden <- Filter(function(l) inherits(l$geom, "GeomBar") ||
                      inherits(l$geom, "GeomCol"), p$layers)[[1]]
  expect_equal(burden$data$y, df$log10_total)
  expect_setequal(as.character(burden$data$fill),
                  c("dead", "high", "low", "standard"))
  sentries <- Filter(function(l) inherits(l$geom, "GeomPoint"),
                     p$layers)[[1]]
  expect_true(all(c("ok", "watch", "artifact") %in%
                    unique(as.character(sentries$data$colour))))
  # The provenance attribute rides into the rendered annotations.
  expect_match(p$labels$title, "52bd0376", fixed = TRUE)
})

test_that("plot_qc_dashboard refuses malformed reports loudly", {
  skip_if_no_ggplot()
  bad <- .b2_qc_frame()
  bad$qc_flag <- NULL
  expect_error(plot_qc_dashboard(bad), class = "msuiter_error_input")
  expect_error(plot_qc_dashboard(head(.b2_qc_frame(), 0)),
               class = "msuiter_error_input")
  expect_error(plot_qc_dashboard("not a frame"),
               class = "msuiter_error_input")
})

test_that("plot_qc_dashboard ggsaves a non-empty PNG", {
  skip_if_no_ggplot()
  p <- plot_qc_dashboard(.b2_qc_frame())
  out <- tempfile(fileext = ".png")
  on.exit(unlink(out), add = TRUE)
  suppressMessages(ggplot2::ggsave(out, p, width = 7, height = 4, dpi = 72))
  expect_true(file.exists(out))
  expect_gt(file.size(out), 0)
})

# ---------------------------------------------------------------------------
# plot_pseudosig_contribution
# ---------------------------------------------------------------------------

# Mirrors the certified ms_qc_roster_share() return (R/ms-qc-sentries.R:311,
# frozen order sample/exposure_total/artifact_share/artifact_sigs/
# artifact_flag; artifact_flag from .ms_qc_verdict -> "ok"/"artifact"/"na").
.b2_roster_frame <- function() {
  data.frame(
    sample = c("A", "B", "C", "D"),
    exposure_total = c(4500, 4450, 1200, 0),
    artifact_share = c(0.012, 0.34, 0.071, NA),
    artifact_sigs = c("S1", "S2;S3;S4", "S3", ""),
    artifact_flag = c("ok", "artifact", "artifact", "na"),
    stringsAsFactors = FALSE
  )
}

test_that("plot_pseudosig_contribution ranks bars and colours flags", {
  skip_if_no_ggplot()
  p <- plot_pseudosig_contribution(.b2_roster_frame())
  bars <- Filter(function(l) inherits(l$geom, "GeomBar") ||
                    inherits(l$geom, "GeomCol"), p$layers)[[1]]
  # The contribution ranking is the point of the face: descending share,
  # with the zero-exposure sample adjudicated out at the data layer.
  expect_identical(as.character(bars$data$sample[order(bars$data$x)]),
                   c("B", "C", "A"))
  expect_false("D" %in% as.character(bars$data$sample))
  expect_equal(bars$data$y[order(bars$data$x)], c(0.34, 0.071, 0.012))
  expect_true(any(vapply(p$layers, function(l)
    inherits(l$geom, "GeomText"), logical(1L))))
})

test_that("plot_pseudosig_contribution labels cap at top with overflow", {
  skip_if_no_ggplot()
  p <- plot_pseudosig_contribution(.b2_roster_frame(), top = 2L)
  texts <- Filter(function(l) inherits(l$geom, "GeomText"), p$layers)[[1]]
  lab <- as.character(texts$data$label)
  expect_true(any(grepl("+1", lab, fixed = TRUE)))   # S2;S3;S4 -> two + overflow
  expect_true(any(grepl("S2", lab, fixed = TRUE)))
  expect_false(any(grepl("S4", lab, fixed = TRUE)))  # third name suppressed
})

test_that("plot_pseudosig_contribution refuses malformed rosters", {
  skip_if_no_ggplot()
  bad <- .b2_roster_frame()
  bad$artifact_share <- NULL
  expect_error(plot_pseudosig_contribution(bad),
               class = "msuiter_error_input")
})

test_that("plot_pseudosig_contribution ggsaves a non-empty PNG", {
  skip_if_no_ggplot()
  out <- tempfile(fileext = ".png")
  on.exit(unlink(out), add = TRUE)
  suppressMessages(ggplot2::ggsave(out, plot_pseudosig_contribution(.b2_roster_frame()),
                                   width = 6, height = 4, dpi = 72))
  expect_true(file.exists(out))
  expect_gt(file.size(out), 0)
})

# ---------------------------------------------------------------------------
# plot_hypermutator_burden
# ---------------------------------------------------------------------------

# A legal MsStratification (the S7 validity law in R/stratify.R:52-143
# enforces the partition and the gmm key set, so this fixture cannot drift
# silently).
.b2_strat <- function() {
  totals <- c(S1 = 100, S2 = 20000, S3 = 300, S4 = 25000, S5 = 900,
              S6 = 50)
  msuiter:::MsStratification(
    cutoff = 10000,
    totals = totals,
    hyper = c("S2", "S4"),
    nonhyper = c("S1", "S3", "S5", "S6"),
    n_hyper = 2, n_nonhyper = 4,
    gmm = list(retained_mean = 500, retained_sd = 150, retained_n = 4,
               n_fits = 1, converged = TRUE),
    policy = "exclude_de_novo_then_refit",
    seed = 1
  )
}

test_that("plot_hypermutator_burden draws the stored cutoff as a vline", {
  skip_if_no_ggplot()
  strat <- .b2_strat()
  p <- plot_hypermutator_burden(strat)
  expect_true(any(vapply(p$layers, function(l)
    inherits(l$geom, "GeomVline"), logical(1L))))
  vline <- unlist(lapply(p$layers, function(l) {
    if (inherits(l$geom, "GeomVline")) l$data$xintercept else numeric(0)
  }), use.names = FALSE)
  expect_equal(vline, strat@cutoff)
})

test_that("plot_hypermutator_burden classes bars by the stored partition", {
  skip_if_no_ggplot()
  strat <- .b2_strat()
  hist <- Filter(function(l) inherits(l$geom, "GeomBar"),
                 plot_hypermutator_burden(strat)$layers)[[1]]
  d1 <- hist$data
  expect_setequal(as.character(d1$fill), c("FALSE", "TRUE"))
  hyper <- as.character(d1$fill) == "TRUE"
  expect_setequal(as.character(d1$sample[hyper]), strat@hyper)
  expect_equal(d1$total[hyper], unname(strat@totals[strat@hyper]))
})

test_that("plot_hypermutator_burden annotates the GMM attestation", {
  skip_if_no_ggplot()
  p <- plot_hypermutator_burden(.b2_strat())
  expect_match(p$labels$subtitle, "n_fits 1", fixed = TRUE)
  expect_match(p$labels$subtitle, "converged TRUE", fixed = TRUE)
})

test_that("plot_hypermutator_burden survives the real stratify pipeline", {
  skip_if_no_ggplot()
  totals <- setNames(c(rep(1500, 8), 120000, 140000),
                     sprintf("S%02d", 1:10))
  s <- ms_stratify_hypermutants(totals, manual_cutoff = 0, seed = 7)
  p <- plot_hypermutator_burden(s)
  vline <- unlist(lapply(p$layers, function(l) {
    if (inherits(l$geom, "GeomVline")) l$data$xintercept else numeric(0)
  }), use.names = FALSE)
  expect_equal(vline, s@cutoff)
  expect_identical(s@policy, "exclude_de_novo_then_refit")
})

test_that("plot_hypermutator_burden refuses non-stratifications; empties are validator-sealed", {
  skip_if_no_ggplot()
  expect_error(plot_hypermutator_burden(list(totals = 1:3)),
               class = "msuiter_error_input")
  # A zero-cohort stratification can never reach the face: the certified S7
  # validator (R/stratify.R) seals it at construction, so the face's
  # empties guard is defence-in-depth, witnessed here at the class law.
  expect_error(
    msuiter:::MsStratification(
      cutoff = 10000,
      totals = setNames(numeric(0), character(0)),
      hyper = character(0), nonhyper = character(0),
      n_hyper = 0, n_nonhyper = 0,
      gmm = list(retained_mean = 0, retained_sd = 0, retained_n = 0,
                 n_fits = 0, converged = FALSE),
      policy = "exclude_de_novo_then_refit",
      seed = 1
    ),
    class = "msuiter_error_stratify"
  )
})

test_that("plot_hypermutator_burden ggsaves a non-empty PNG", {
  skip_if_no_ggplot()
  out <- tempfile(fileext = ".png")
  on.exit(unlink(out), add = TRUE)
  suppressMessages(ggplot2::ggsave(out, plot_hypermutator_burden(.b2_strat()),
                                   width = 6, height = 4, dpi = 72))
  expect_true(file.exists(out))
  expect_gt(file.size(out), 0)
})

# ---------------------------------------------------------------------------
# plot_opportunity_distribution
# ---------------------------------------------------------------------------

.b2_opps_class <- function(labels) substr(labels, 3L, 5L) # "[C>A]" core

.b2_bars <- function(p) Filter(function(l) inherits(l$geom, "GeomBar"),
                               p$layers)[[1]]

test_that("plot_opportunity_distribution defaults to the genome table", {
  skip_if_no_ggplot()
  genome <- msuiter:::.ms_convert_opps[["human-genome"]]
  d1 <- .b2_bars(plot_opportunity_distribution())$data
  expect_identical(nrow(d1), 96L)
  expect_equal(d1$y, unname(log10(genome)))
  expect_equal(sum(10^d1$y), 8.505e9) # the test-ms-convert.R pin
  expect_setequal(unique(as.character(d1$fill)),
                  c("C>A", "C>G", "C>T", "T>A", "T>C", "T>G"))
  expect_identical(as.character(d1$fill)[1], .b2_opps_class(names(genome)[1]))
})

test_that("plot_opportunity_distribution resolves the exome selector", {
  skip_if_no_ggplot()
  d1 <- .b2_bars(plot_opportunity_distribution(from = "human-exome"))$data
  expect_equal(sum(10^d1$y), 153221364)
})

test_that("plot_opportunity_distribution takes explicit vectors in canonical order", {
  skip_if_no_ggplot()
  opps <- msuiter:::.ms_convert_opps[["human-exome"]]
  d1 <- .b2_bars(plot_opportunity_distribution(opps = opps))$data
  expect_equal(sum(10^d1$y), 153221364)
})

test_that("plot_opportunity_distribution refuses off-registry or unnamed input", {
  skip_if_no_ggplot()
  opps <- msuiter:::.ms_convert_opps[["human-exome"]]
  expect_error(plot_opportunity_distribution(opps = unname(opps)),
               class = "msuiter_error_input")
  expect_error(plot_opportunity_distribution(opps = opps[reorder(seq_along(opps), opps)]),
               class = "msuiter_error_input")
  expect_error(plot_opportunity_distribution(opps = opps[1:90]),
               class = "msuiter_error_input")
  expect_error(plot_opportunity_distribution(from = "mars"),
               class = "msuiter_error_input")
})

test_that("plot_opportunity_distribution ggsaves a non-empty PNG", {
  skip_if_no_ggplot()
  out <- tempfile(fileext = ".png")
  on.exit(unlink(out), add = TRUE)
  suppressMessages(ggplot2::ggsave(out, plot_opportunity_distribution(),
                                    width = 7, height = 4, dpi = 72))
  expect_true(file.exists(out))
  expect_gt(file.size(out), 0)
})

# ---------------------------------------------------------------------------
# Suggests contract (fires on the Suggests-free CI arm only)
# ---------------------------------------------------------------------------

test_that("all four faces raise the structured package error without ggplot2", {
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    # The ledger phrase "not installed" must ride the reason: this unit is
    # the Suggests-free CI arm's witness and can only speak where ggplot2
    # is not installed.
    skip("ggplot2 is installed here; this arm requires it not installed")
  }
  strat <- .b2_strat()
  for (call in list(
    function() plot_qc_dashboard(.b2_qc_frame()),
    function() plot_pseudosig_contribution(.b2_roster_frame()),
    function() plot_hypermutator_burden(strat),
    function() plot_opportunity_distribution()
  )) {
    expect_error(call(), class = "msuiter_error_package")
  }
})
