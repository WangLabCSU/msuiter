# P2 kernel bridge: the redesigned call site for the certified batch face
# (parity plan P2, pair L1; lane card /tmp/perf2lane/lane-task.md).
#
# One kernel process per (rank, bootstrap) unit. The unit's nrun fits are
# manifest ROWS of a single `fit-kl --cases` invocation: the input grid V
# is rendered ONCE (%.17e, the frozen .rust_csv_rows law) into one staged
# file that every case row hardlinks, the protocol handshake is paid ONCE
# per unit, and nothing is consumable until every case's receipts are
# attested (the run_batch law of R/kernel-pipeline.R). WHAT the kernel
# computes is untouched: the same certified binary, the same frozen
# constants -- init rides the rows verbatim, the run-i seed law is
# seed + i - 1, iters/m/n/k per row -- only WHO calls the kernel and WHEN
# changed (forensics: 8000 per-fit spawns + 4000 per-fit handshakes were
# 85.6% of the wall; the redesigned shape spends 2 contacts per unit).
#
# Division of validation law (pair G adjudication, do not drift): the
# client enforces STRUCTURE (counts, path safety, CSV safety, dimensions);
# the certified kernel face classifies SEMANTICS through its exit status,
# and the receipt attestation is what makes bytes consumable.

## ---- the frozen input-marshalling law ---------------------------------------

# The verbatim %.17e comma-grid rendering (the certified input contract of
# the batch face -- one row per matrix row, fields comma-separated).
.kp_grid_text <- function(mat) {
  apply(mat, 1L, function(r) paste(sprintf("%.17e", r), collapse = ","))
}

## ---- the unit serve ----------------------------------------------------------

# The base hardlink primitive has two build names in the fleet (vanilla
# 'link', this rig's renamed 'file.link'); resolve either, fail closed if
# the build carries neither -- the once-per-unit staging law is not
# negotiable down to a silent copy.
.kp_hard_link <- function(from, to) {
  fn <- tryCatch(get("file.link", envir = baseenv(), mode = "function"),
                 error = function(e) NULL)
  if (is.null(fn)) {
    fn <- tryCatch(get("link", envir = baseenv(), mode = "function"),
                   error = function(e) NULL)
  }
  if (is.null(fn)) {
    stop("no hardlink primitive (link/file.link) on this build: the " ,
         "once-per-unit V staging law requires hardlinks", domain = NA)
  }
  rc <- suppressWarnings(fn(from, to))
  # Two status conventions in the fleet: the renamed file.* family answers
  # TRUE/FALSE, base link answers the integer 0. Anything that is neither
  # an explicit TRUE nor a clean 0 is a failure -- fail closed, never a
  # silent copy.
  ok <- isTRUE(rc) || (is.atomic(rc) && length(rc) == 1L &&
                       is.numeric(rc) &&
                       identical(suppressWarnings(as.integer(rc)), 0L))
  if (!ok) {
    stop("hardlink staging failed from '", from, "' to '", to,
         "' (status ", paste(as.character(rc), collapse = ","),
         "): the once-per-unit V law requires hardlinks, not copies",
         domain = NA)
  }
  invisible(0L)
}

# Serve one (rank, bootstrap) unit: nrun fits of V at rank k, seeds
# seed, seed+1, ... seed+nrun-1, through ONE certified batch invocation.
#
# Contract:
#  * staging -- V is rendered ONCE to <root>/<tag>.shared/V.csv and each
#    case directory hardlinks that single rendering (link() failure is a
#    hard fault: a silent copy would let half-staged trees drift apart);
#  * the cases manifest rides the frozen header and the row law above;
#  * contacts: exactly one '--version' handshake + one batch exec (the
#    run_batch law; retry, when opted in, is witnessed, never silent);
#  * consumption: the returned fits are the ATTESTED bundles handed up by
#    kp_run_batch -- W, H, objective, meta validated per case; a batch
#    that exits 0 with any case un-attested delivers NOTHING and the
#    fault names the case.
#
# Returns invisible(list(unit, nrun, cases, manifest, fits, out.root,
# attempts)); 'fits' is index-aligned with 'cases'.
kp_serve_unit <- function(bin, V, k, seed, nrun = 1L, iters = 1L,
                          init = "nndsvd", tag = "unit",
                          root = NULL, out.root = NULL,
                          ledger = NULL, max_attempts = 1L) {
  if (!is.character(bin) || length(bin) != 1L || !nzchar(bin) ||
      is.na(bin)) {
    stop("'bin' must be a single non-empty path", domain = NA)
  }
  if (!is.character(init) || length(init) != 1L || !nzchar(init) ||
      is.na(init) || grepl("[,\n]", init)) {
    stop("'init' must be a single non-empty token without commas or ",
         "newlines (semantic classification is the kernel's)", domain = NA)
  }
  if (!is.character(tag) || length(tag) != 1L || is.na(tag) ||
      !grepl("^[A-Za-z0-9][A-Za-z0-9._-]*$", tag)) {
    stop("'tag' must be a single path-safe token (letters, digits, '.', ",
         "'_' or '-'), got: ", paste(as.character(tag), collapse = ","),
         domain = NA)
  }
  if (!is.matrix(V) || !is.numeric(V) || nrow(V) < 1L || ncol(V) < 1L) {
    stop("'V' must be a numeric matrix with at least one row and column",
         domain = NA)
  }
  k <- .kp_count(k, "k")
  nrun <- .kp_count(nrun, "nrun")
  iters <- .kp_count(iters, "iters")
  seed <- .kp_count(seed, "seed", allow.zero = TRUE)
  m <- nrow(V)
  n <- ncol(V)
  if (is.null(root)) root <- tempfile("kp-serve-in-")
  if (is.null(out.root)) out.root <- tempfile("kp-serve-out-")
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  dir.create(out.root, recursive = TRUE, showWarnings = FALSE)
  # The single staged rendering of this unit's grid.
  shared <- file.path(root, paste0(tag, ".shared"))
  dir.create(shared, recursive = TRUE, showWarnings = FALSE)
  shared.v <- file.path(shared, "V.csv")
  writeLines(.kp_grid_text(V), con = shared.v)
  cases <- character(nrun)
  for (i in seq_len(nrun)) {
    cases[[i]] <- paste0(tag, "-", sprintf("%04d", i))
    case.dir <- file.path(root, cases[[i]])
    dir.create(case.dir, recursive = TRUE, showWarnings = FALSE)
    .kp_hard_link(shared.v, file.path(case.dir, "V.csv"))
  }
  rows <- character(nrun)
  for (i in seq_len(nrun)) {
    # The frozen row law: init verbatim; the run-i seed law seed + i - 1;
    # the replicate column stays empty (seeded init is not this route).
    rows[[i]] <- paste0(cases[[i]], ",", init, ",",
                         as.character(seed + i - 1L), ",,",
                         as.character(iters), ",", as.character(m), ",",
                         as.character(n), ",", as.character(k))
  }
  manifest <- file.path(root, paste0(tag, "-cases.csv"))
  writeLines(c(.KP_BATCH_HEADER, rows), con = manifest)
  rb <- kp_run_batch(bin = bin, manifest = manifest, root = root,
                     out.root = out.root, max_attempts = max_attempts,
                     ledger = ledger, unit = tag)
  invisible(list(unit = tag, nrun = nrun, cases = cases,
                 manifest = manifest, shared = shared.v,
                 fits = rb$attested[cases],
                 out.root = out.root, attempts = rb$attempts))
}
