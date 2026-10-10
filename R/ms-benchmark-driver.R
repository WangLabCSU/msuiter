# ms-benchmark-driver.R: the M7 grid driver first version (design memo
# docs/devlog/2026-10-05-benchmark-design-memo.md, D1 stage 1 + D2
# defaults -- PI-confirmed 2026-10-05).
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
# Naming note (settled by the U-M7-04 slice-B ergonomics ruling): the trio
# keeps three explicit roles -- ms_benchmark_grid() builds the scenario
# specs, ms_run_benchmark() executes them, ms_benchmark(results, settings)
# is the S7 container constructor; NO generic merge (YAGNI). Decision
# record: docs/devlog/2026-10-10-m7-benchmark-ergonomics.md; the three
# help topics cross-link via @family benchmark.
#
# The dict comes from the bundled COSMIC v3.6 SBS96 reference (refdb v1
# -- shipped material); truth exposures are per-sample Dirichlet shares
# over the active signatures.

#' Construct one benchmark scenario
#'
#' One calibration-layer scenario: a burden, a sample count, an active
#' signature count, and a generative arm -- all fed to [ms_simulate()]
#' against a seeded draw from the bundled COSMIC v3.6 SBS96 dictionary.
#' A grid is a named list of scenarios. Create specs with
#' `ms_benchmark_grid()`, execute with [ms_run_benchmark()], store via
#' [ms_benchmark()] -- the trio stays three separate functions by the
#' U-M7-04 ergonomics ruling (no generic merge).
#'
#' @family benchmark
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
#' Single-cell isolation: extraction AND scoring live in one guarded
#' block -- a failure in either records a `cell_error` metric for that
#' cell and the grid continues. Scenario-level generation failures
#' (ms_simulate / the dictionary draw) abort the run: the v1 isolation
#' boundary is the cell, not the scenario.
#'
#' Create specs with [ms_benchmark_grid()], execute with
#' `ms_run_benchmark()`, store via [ms_benchmark()] -- the trio stays
#' three separate functions by the U-M7-04 ergonomics ruling (no generic
#' merge).
#'
#' @family benchmark
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
  if (anyDuplicated(names(grid)) != 0L) {
    # R named-list semantics would silently keep only the FIRST element
    # of a duplicated name (the audited v1 skipped the second scenario
    # entirely); refuse instead.
    msuiter_abort(
      "input",
      "grid scenario names must be unique",
      i = "R named lists silently drop duplicated-name duplicates",
      j = paste0("duplicated: ",
                 msuiter_quote_trunc(names(grid)[duplicated(names(grid))])),
      c = "give every scenario a distinct name"
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
  if (!is.numeric(seed) || length(seed) != 1L || is.na(seed) ||
      !is.finite(seed) || seed < 0) {
    msuiter_abort(
      "input",
      "seed must be a single non-negative finite number",
      i = "the seed derives the scenario dictionaries and truth exposures",
      j = paste0("received: ", msuiter_quote_trunc(seed)),
      c = "record the integer seed used for the grid"
    )
  }
  if (is.null(engines)) {
    # The sparse factory's l1 default (mu = 0) fails its own validator;
    # the volume variant is the penalty-free certified default.
    engines <- list(nmf = ms_nmf(), ard = ms_ard(),
                    sparse = ms_sparse(variant = "volume"))
  }
  # Resolve every engine BEFORE any scenario burns work (contract 4:
  # errors before compute; the audited v1 resolved per-cell and could
  # abort mid-run on an unresolvable spec).
  for (eng_name in names(engines)) {
    entry <- tryCatch(match_ms_engine(engines[[eng_name]]),
                      error = identity)
    if (inherits(entry, "error") || is.null(entry)) {
      msuiter_abort(
        "input",
        sprintf("engine '%s' did not resolve in the registry", eng_name),
        i = "every benchmark engine must be a registered extract-mode spec",
        j = if (inherits(entry, "error")) {
          paste0("reason: ", conditionMessage(entry))
        } else {
          paste0("received: ", class(engines[[eng_name]])[1L])
        },
        c = "pass a factory object (ms_nmf()/ms_ard()/ms_sparse())"
      )
    }
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

    gen <- tryCatch({
      catalog <- ms_simulate(dict, shares, arm = sc$arm, size = sc$size,
                             seed = seed, burden = sc$burden)
      truth_counts <- sweep(shares, 2L, colSums(catalog@counts), "*")
      list(catalog = catalog, truth_counts = truth_counts)
    }, error = function(e) NULL)
    if (is.null(gen)) {
      # Scenario-level generation failure: every engine of THIS scenario
      # records cell_error (the isolation boundary extended to the
      # scenario axis); other scenarios continue.
      for (eng_name in names(engines)) {
        rows[[length(rows) + 1L]] <- data.frame(
          .engine = eng_name, .scenario = sc_name, .metric = "cell_error",
          .estimate = 1, stringsAsFactors = FALSE
        )
      }
      next
    }
    catalog <- gen$catalog
    truth_counts <- gen$truth_counts

    for (eng_name in names(engines)) {
      spec <- engines[[eng_name]]
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
        # No NA ever reaches the container (the audited v1 emitted an
        # NA f1 when no pair crossed 0.90, which aborted the WHOLE run
        # at assembly): zero-TP cells score 0, degenerate empty cells
        # score 0 across the board.
        p90 <- sweep_res$tp[1L]
        precision <- if (p90 + sweep_res$fp[1L] > 0) {
          p90 / (p90 + sweep_res$fp[1L])
        } else {
          0
        }
        recall <- if (p90 + sweep_res$fn[1L] > 0) {
          p90 / (p90 + sweep_res$fn[1L])
        } else {
          0
        }
        f1 <- if (p90 > 0) {
          2 * p90 / (2 * p90 + sweep_res$fp[1L] + sweep_res$fn[1L])
        } else {
          0
        }

        # D2 paired L1 (frozen memo semantics): ONLY the pairs that
        # crossed the 0.90 match line enter the mean -- a garbage
        # estimate force-paired by Hungarian would dilute the L1 (the
        # audit measured 17% dilution favoring garbage signatures), and
        # its FP identity is already penalized by the primary metric.
        # The estimate_index filter was always-true (it is s+1 by
        # construction); the reference_index = 0 (Novel) filter is the
        # real one.
        keep90 <- sweep_res$threshold == 0.90 & sweep_res$reference_index > 0
        ests <- sweep_res$estimate_index[keep90]
        refs <- sweep_res$reference_index[keep90]
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
        # No 0.90 pair -> the L1 rows are OMITTED (NA is a container
        # contract violation), leaving precision/recall/f1 to carry the
        # zero-signal verdict.
        out <- c(precision = precision, recall = recall, f1 = f1)
        if (length(refs) > 0L) {
          out <- c(out, paired_l1_abs = l1a, paired_l1_comp = l1c)
        }
        c(out, runtime_s = unname(tt["elapsed"]))
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
      defaults = "CONFIRMED: D1 stage 1 + D2 + TP-only (PI 2026-10-05)",
      memo = "docs/devlog/2026-10-05-benchmark-design-memo.md"
    )
  )
}
