# ms-benchmark-driver.R: the M7 grid driver first version (design memo
# docs/devlog/2026-10-05-benchmark-design-memo.md, D1 stage 1 + D2
# defaults -- PROVISIONAL pending PI confirmation).
#
# Scope (v1, honestly bounded):
#   * calibration-layer scenarios only (ms_simulate direct drive) -- the
#     SynSig / PCAWG-anchored generator adapters are M7 units;
#   * engines = the three certified in-house specs (or caller specs);
#     competitor adapters are stage 2+ of D1;
#   * scoring: Hungarian P/R/F1 at 0.90 (the primary metric) + D2
#     paired-L1 (absolute and compositional) on the tau-independent
#     Hungarian assignment + runtime.
#
# Naming note (recorded for PI): the M0 container constructor keeps the
# name ms_benchmark(results, settings); the DRIVER is ms_run_benchmark()
# in this version -- whether the two merge behind one generic is an M7
# polish decision, not a v1 blocker.
#
# The dict comes from the bundled COSMIC v3.6 SBS96 reference (refdb v1
# -- shipped material); truth exposures are per-sample Dirichlet shares
# over the active signatures.

#' Construct one benchmark scenario
#'
#' One calibration-layer scenario: a burden, a sample count, an active
#' signature count, and a generative arm -- all fed to [ms_simulate()]
#' against a seeded draw from the bundled COSMIC v3.6 SBS96 dictionary.
#' A grid is a named list of scenarios.
#'
#' @param name Unique scenario name.
#' @param n_samples Simulated sample count (>= 4).
#' @param burden Per-sample mutation burden (whole number >= 200).
#' @param k_active Active signature count (2 <= k_active <= 20).
#' @param arm Generative arm for [ms_simulate()]: "multinomial",
#'   "poisson" or "nb".
#' @param size NB size kappa (arm = "nb" only).
#'
#' @return A validated scenario list.
#'
#' @export
ms_benchmark_grid <- function(name = "scenario", n_samples = 20,
                              burden = 3000, k_active = 3,
                              arm = "multinomial", size = 8) {
  if (!is.character(name) || length(name) != 1L || is.na(name) ||
      !nzchar(name)) {
    msuiter_abort(
      "input",
      "name must be a single non-empty string",
      i = "scenario names are the .scenario identities of the grid",
      j = paste0("received: ", msuiter_quote_trunc(name)),
      c = "name every scenario"
    )
  }
  for (nm in c("n_samples", "burden", "k_active")) {
    v <- get(nm)
    if (!is.numeric(v) || length(v) != 1L || !is.finite(v) ||
        v < 0 || v != floor(v)) {
      msuiter_abort(
        "input",
        sprintf("%s must be a single non-negative whole number", nm),
        i = "scenario fields feed ms_simulate directly",
        j = paste0(nm, " = ", msuiter_quote_trunc(v)),
        c = "pass a whole number"
      )
    }
  }
  if (n_samples < 4) {
    msuiter_abort(
      "input",
      "n_samples must be at least 4",
      i = "the extraction needs a usable sample matrix",
      j = paste0("received: ", n_samples),
      c = "simulate at least 4 samples"
    )
  }
  if (burden < 200) {
    msuiter_abort(
      "input",
      "burden must be at least 200",
      i = "the benchmark follows the mSigAct fit floor",
      j = paste0("received: ", burden),
      c = "raise the burden"
    )
  }
  if (k_active < 2 || k_active > 20) {
    msuiter_abort(
      "input",
      "k_active must be in [2, 20]",
      i = "the dictionary draw range of the first version",
      j = paste0("received: ", k_active),
      c = "pick 2 to 20 active signatures"
    )
  }
  if (!arm %in% c("multinomial", "poisson", "nb")) {
    msuiter_abort(
      "option",
      "arm must be one of multinomial, poisson, nb",
      i = "the ms_simulate grammar",
      j = paste0("received: ", msuiter_quote_trunc(arm)),
      c = "pick a generative arm from the frozen set"
    )
  }
  if (arm == "nb" && (!is.numeric(size) || length(size) != 1L ||
                      is.na(size) || !is.finite(size) || size <= 0)) {
    msuiter_abort(
      "input",
      "size (kappa) must be a single positive finite number for the nb arm",
      i = "NB variance is mu + mu^2/kappa",
      j = paste0("received: ", msuiter_quote_trunc(size)),
      c = "pass a positive kappa (e.g. 8)"
    )
  }
  list(
    name = name, n_samples = as.integer(n_samples),
    burden = as.numeric(burden), k_active = as.integer(k_active),
    arm = arm, size = size
  )
}

#' Run the benchmark grid
#'
#' Drives every (scenario x engine) cell of the grid through the
#' production extraction face and scores it: Hungarian precision/recall/
#' F1 at the 0.90 line, the D2 paired-L1 (absolute and compositional) on
#' the tau-independent Hungarian assignment, and the extraction runtime.
#' PROVISIONAL defaults per the design memo (D1 stage 1: in-house
#' certified engines; D2: Hungarian-paired L1) -- pending PI
#' confirmation.
#'
#' Single-cell isolation: an extraction failure records a `cell_error`
#' metric for that cell and the grid continues; a scoring failure blanks
#' the paired-L1 metrics only.
#'
#' @param grid A named list of [ms_benchmark_grid()] scenarios.
#' @param engines A named list of extract-mode engine specs (e.g.
#'   `list(nmf = ms_nmf())`); NULL = the three certified in-house
#'   defaults. Non-certified specs warn once through the registry.
#' @param seed Master seed (the scenario dictionary draw and the truth
#'   exposures derive from it deterministically).
#'
#' @return An [MsBenchmark].
#'
#' @export
ms_run_benchmark <- function(grid, engines = NULL, seed = 1) {
  if (!is.list(grid) || length(grid) == 0L ||
      is.null(names(grid)) || any(!nzchar(names(grid)))) {
    msuiter_abort(
      "input",
      "grid must be a named list of ms_benchmark_grid() scenarios",
      i = "scenario names are the grid identities",
      j = paste0("received: ", class(grid)[1L]),
      c = "build it with ms_benchmark_grid(), one list element per scenario"
    )
  }
  for (nm in names(grid)) {
    sc <- grid[[nm]]
    if (!is.list(sc) || is.null(sc$name)) {
      msuiter_abort(
        "input",
        sprintf("grid element '%s' is not a scenario list", nm),
        i = "every element needs the ms_benchmark_grid() fields",
        j = paste0("received: ", class(sc)[1L]),
        c = "build scenarios with ms_benchmark_grid()"
      )
    }
  }
  if (is.null(engines)) {
    engines <- list(nmf = ms_nmf(), ard = ms_ard(), sparse = ms_sparse())
  }
  if (!is.list(engines) || length(engines) == 0L ||
      is.null(names(engines)) || any(!nzchar(names(engines)))) {
    msuiter_abort(
      "input",
      "engines must be a named list of engine specs",
      i = "the names become the .engine identities",
      j = paste0("received: ", class(engines)[1L]),
      c = "e.g. list(nmf = ms_nmf(), sparse = ms_sparse())"
    )
  }

  # The truth dictionary: from the bundled reference (shipped material).
  refdb <- ms_refdb_bundled(build = "GRCh37")
  sigmat <- refdb$SBS_GRCh37@matrices[[1]]

  rows <- list()
  for (sc_name in names(grid)) {
    sc <- grid[[sc_name]]
    k <- sc$k_active
    # Seeded dictionary draw + truth exposures (all-positive gamma
    # shares: no degenerate truth columns in the calibration layer).
    set.seed(seed + 1000L * (match(sc_name, names(grid)) - 1L))
    chosen <- sort(sample(colnames(sigmat), k))
    dict <- sigmat[, chosen, drop = FALSE]
    shares <- matrix(stats::rgamma(k * sc$n_samples, shape = 2),
                     nrow = k)
    shares <- sweep(shares, 2L, colSums(shares), "/")
    rownames(shares) <- chosen

    catalog <- ms_simulate(dict, shares, arm = sc$arm, size = sc$size,
                           seed = seed, burden = sc$burden)
    truth_counts <- sweep(shares, 2L, colSums(catalog@counts), "*")

    for (eng_name in names(engines)) {
      spec <- engines[[eng_name]]
      entry <- tryCatch(match_ms_engine(spec), error = function(e) NULL)
      if (is.null(entry)) {
        msuiter_abort(
          "input",
          sprintf("engine '%s' did not resolve in the registry", eng_name),
          i = "every benchmark engine must be a registered extract-mode spec",
          j = paste0("received: ", class(spec)[1L]),
          c = "pass a factory object (ms_nmf()/ms_ard()/ms_sparse())"
        )
      }
      # ---- ONE extraction attempt per cell; everything else reads it ---
      cell <- tryCatch({
        tt <- system.time({
          fit <- ms_extract(catalog, k, method = spec)
        })
        est_sigs <- fit@signatures
        est_expo <- fit@exposures

        # Primary metric: Hungarian P/R/F1 at 0.90 on share-normalized
        # signatures (ms_compare's protocol semantics, direct face).
        est_shares <- sweep(est_sigs, 2L, colSums(est_sigs), "/")
        truth_shares <- sweep(dict, 2L, colSums(dict), "/")
        sweep_res <- ms_match_solutions_rust(
          estimated = as.numeric(t(est_shares)),
          reference = as.numeric(t(truth_shares)),
          dim = nrow(est_sigs), thresholds = 0.90
        )
        p90 <- sweep_res$tp[1L]
        precision <- if (p90 + sweep_res$fp[1L] > 0) {
          p90 / (p90 + sweep_res$fp[1L])
        } else {
          NA_real_
        }
        recall <- if (p90 + sweep_res$fn[1L] > 0) {
          p90 / (p90 + sweep_res$fn[1L])
        } else {
          NA_real_
        }
        f1 <- if (p90 > 0) {
          2 * p90 / (2 * p90 + sweep_res$fp[1L] + sweep_res$fn[1L])
        } else {
          NA_real_
        }

        # D2 paired L1 on the tau-independent assignment: the tiny
        # threshold makes every Hungarian pair a "match", so the
        # reference_index column IS the assignment.
        raw <- ms_match_solutions_rust(
          estimated = as.numeric(t(est_shares)),
          reference = as.numeric(t(truth_shares)),
          dim = nrow(est_sigs), thresholds = 1e-9
        )
        keep <- raw$threshold == 1e-9 & raw$estimate_index > 0
        ests <- raw$estimate_index[keep]
        refs <- raw$reference_index[keep]
        l1a <- l1c <- NA_real_
        if (length(refs) > 0L) {
          l1a_v <- l1c_v <- numeric(length(refs))
          for (p in seq_along(refs)) {
            a <- ests[p]
            r0 <- refs[p]
            denom_r <- max(sum(truth_counts[r0, ]), 1)
            l1a_v[p] <- sum(abs(est_expo[a, ] - truth_counts[r0, ])) /
              denom_r
            pe <- est_expo[a, ] / max(sum(est_expo[a, ]), 1)
            pt <- truth_counts[r0, ] / max(sum(truth_counts[r0, ]), 1)
            l1c_v[p] <- sum(abs(pe - pt))
          }
          l1a <- mean(l1a_v)
          l1c <- mean(l1c_v)
        }
        c(precision = precision, recall = recall, f1 = f1,
          paired_l1_abs = l1a, paired_l1_comp = l1c,
          runtime_s = unname(tt["elapsed"]))
      }, error = function(e) {
        # The container validator rejects NA estimates: a failed cell
        # reports ONLY its cell_error row (isolation without contract
        # violation).
        c(cell_error = 1)
      })

      for (m in names(cell)) {
        rows[[length(rows) + 1L]] <- data.frame(
          .engine = eng_name, .scenario = sc_name, .metric = m,
          .estimate = unname(cell[m]), stringsAsFactors = FALSE
        )
      }
    }
  }
  results <- do.call(rbind, rows)
  ms_benchmark(
    results = results,
    settings = list(
      seed = seed, scenarios = names(grid),
      engines = names(engines),
      defaults = "PROVISIONAL: D1 stage 1 + D2, pending PI confirmation",
      memo = "docs/devlog/2026-10-05-benchmark-design-memo.md"
    )
  )
}
