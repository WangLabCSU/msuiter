# The P2 kernel pipeline: the redesigned call sites for the certified
# protocol-1 batch entry (parity plan P2; lane card /tmp/perf2lane/lane-task.md).
#
# What this module is: the reference implementation of the bridge shape that
# the frozen protocol-1 contract deserves -- ONE kernel process per unit
# serving the whole unit through the batch face (msuiter-kernel --cases),
# the exit status consumed from the system2 RETURNED VALUE (never an
# attribute: the attribute-only idiom is the documented silent-death
# hazard, bake-death #7 and the forensics section 7.6), per-case receipt
# attestation before any residue is consumed, a countable retry witness,
# and a deterministic worker farm. WHAT the kernel computes is untouched:
# same binary, same frozen constants (init nndsvd, the run-i seed law
# seed + i - 1, iters 2000, per-rank m/n/k, protocol=1), same bytes.
#
# Design laws (do not drift):
#  * Isolated process only, single contact point kp_exec() with a character
#    vector argv and NO shell. stdout/stderr are captured to files so the
#    result VALUE is the scalar exit status.
#  * kp_status() is the one status reader: the VALUE is the source; a
#    "status" attribute may corroborate the value or falsify it (an
#    integrity stop), never silently source it.
#  * Nothing is consumable until its per-case receipts are attested; a
#    batch is all-or-nothing, so a partial residue is a fault, never data.
#  * Retries are opt-in, bounded (1..4), and every attempt lands a ledger
#    row; the default route spawns exactly one attempt per batch.
#  * The farm never touches the seven thread-cap environment variables:
#    workers inherit the campaign caps verbatim (see kp_farm).
#  * Fail-closed everywhere; every fault names the file, case or field.
#
# Floor note: the package floor is R >= 4.3 (DESCRIPTION Depends), so this
# file avoids the %||% null-default idiom (a 4.4 export) outright.

## ---- frozen protocol constants (mirrors of the certified contract) -------

.KP_PROTOCOL <- 1L
.KP_BATCH_HEADER <- "case,init,seed,replicate,iters,m,n,k"
.KP_BATCH_COLUMNS <- 8L
# The frozen meta.csv key order of the protocol-1 contract (bin source
# msuiter-kernel.rs, witness of the P1 gate family).
.KP_META_KEYS <- c("protocol", "command", "init", "seed", "replicate",
                   "m", "n", "k", "iters", "iterations", "trace_len",
                   "obj_init", "obj_final", "eps", "engine_crate")
# Retry bounds: 1 = the no-retry default route; the ceiling keeps a
# misconfigured caller from turning the bridge into an unbounded loop.
.KP_ATTEMPTS_MIN <- 1L
.KP_ATTEMPTS_MAX <- 4L

.kp_count <- function(x, name, allow.zero = FALSE) {
  if (!is.numeric(x) || length(x) != 1L || !is.finite(x) ||
      x != floor(x) || x < (if (allow.zero) 0 else 1)) {
    stop("'", name, "' must be a single ",
         if (allow.zero) "non-negative " else "positive ",
         "whole number, got: ", paste(as.character(x), collapse = ","),
         domain = NA)
  }
  as.integer(x)
}

## ---- the real status channel ----------------------------------------------

# Exit status of an exec result. The system2 RETURNED VALUE is the source
# of truth: with stdout/stderr captured to files the result is the scalar
# exit code. A result that carries no usable value while wearing a status
# attribute is the TRUE-mode capture shape -- rejected outright (an
# attribute must never be what the consumer trusts).
kp_status <- function(res) {
  st <- attr(res, "status")
  val <- if (is.atomic(res) && length(res) == 1L &&
              (is.numeric(res) || is.integer(res)))
    suppressWarnings(as.integer(res)) else NA_integer_
  if (is.na(val)) {
    if (!is.null(st)) {
      stop("kernel exec result carries no exit-status VALUE (only a ",
           "'status' attribute, which is never a source of truth): the ",
           "status must arrive by value", domain = NA)
    }
    stop("kernel exec result carries no usable exit-status value", domain = NA)
  }
  if (!is.null(st)) {
    st <- suppressWarnings(as.integer(st))
    if (is.na(st) || !identical(st, val)) {
      stop("kernel exec status disagreement: value says ", val,
           ", the 'status' attribute says ",
           if (is.na(st)) "<unreadable>" else st,
           " -- attributes may corroborate or falsify, never source",
           domain = NA)
    }
  }
  val
}

# The single process contact point. Character-vector argv, never a shell;
# stdout/stderr land in files so the system2 result VALUE is the exit
# status; the captured text is attached for the fail-closed reporting.
# Tests swap this seam through assignInNamespace (house mock idiom).
kp_exec <- function(bin, args) {
  if (!is.character(bin) || length(bin) != 1L || !nzchar(bin) ||
      is.na(bin)) {
    stop("'bin' must be a single non-empty path", domain = NA)
  }
  if (!file.exists(bin)) {
    stop("kernel binary not found: ", bin, domain = NA)
  }
  args <- as.character(args)
  if (length(args) && (any(is.na(args)) || any(grepl("[\n]", args)))) {
    stop("kernel argv must be a character vector without NAs or newlines",
         domain = NA)
  }
  out.f <- tempfile("kp-exec-out-")
  err.f <- tempfile("kp-exec-err-")
  res <- suppressWarnings(system2(bin, args, stdout = out.f, stderr = err.f))
  out <- if (file.exists(out.f))
    readLines(out.f, warn = FALSE) else character()
  err <- if (file.exists(err.f))
    readLines(err.f, warn = FALSE) else character()
  attr(res, "stdout") <- out
  attr(res, "stderr") <- err
  res
}

# One protocol-1 handshake for a kernel process identity: '<bin> --version'
# must print the frozen line and agree on protocol=1. The bridge handshakes
# ONCE per unit, never per fit -- the forensics counted the per-fit tax.
kp_handshake <- function(bin) {
  res <- kp_exec(bin, c("--version"))
  status <- kp_status(res)
  if (!identical(status, 0L)) {
    stop("msuiter-kernel --version exited with status ", status,
         "; stderr: ", paste(as.character(attr(res, "stderr")),
                             collapse = " | "), domain = NA)
  }
  lines <- as.character(attr(res, "stdout"))
  lines <- lines[nzchar(lines)]
  if (!length(lines)) {
    stop("msuiter-kernel --version produced no output; cannot verify the ",
         "protocol-1 handshake.", domain = NA)
  }
  cand <- lines[grepl("^msuiter-kernel ", lines)]
  if (!length(cand)) {
    stop(paste0("msuiter-kernel --version did not print its protocol line; ",
                "saw: ", paste(lines, collapse = " / ")), domain = NA)
  }
  line <- cand[[1L]]
  shape <- paste0("^msuiter-kernel protocol=[0-9]+ engine=\"[^\"]*\" ",
                  "kl_eps=[-+0-9.eE]+$")
  if (!grepl(shape, line)) {
    stop("unexpected msuiter-kernel handshake line: ", line, domain = NA)
  }
  toks <- strsplit(line, " ", fixed = TRUE)[[1L]]
  proto.tok <- toks[grepl("^protocol=", toks)][1L]
  eps.tok <- toks[grepl("^kl_eps=", toks)][1L]
  if (is.na(proto.tok) || is.na(eps.tok)) {
    stop("unexpected msuiter-kernel handshake line: ", line, domain = NA)
  }
  protocol <- suppressWarnings(as.integer(sub("^protocol=", "", proto.tok)))
  if (is.na(protocol) || !identical(protocol, .KP_PROTOCOL)) {
    stop("unsupported msuiter-kernel protocol: expected protocol=",
         .KP_PROTOCOL, ", line said: ", line, domain = NA)
  }
  kl.eps <- suppressWarnings(as.numeric(sub("^kl_eps=", "", eps.tok)))
  if (!is.finite(kl.eps) || kl.eps < 0) {
    stop("unreadable kl_eps in handshake line: ", line, domain = NA)
  }
  engine <- sub("^.*engine=\"", "", line)
  engine <- sub("\"[^\"]*$", "", engine)
  list(protocol = protocol, engine = engine, kl_eps = kl.eps, raw = line)
}

## ---- the cases manifest ----------------------------------------------------

# Split a line at its first comma only (engine_crate legitimately contains
# commas). NULL when there is no comma.
.kp_split1 <- function(line) {
  hit <- regexpr(",", line)
  if (is.na(hit) || !nzchar(line)) return(NULL)
  i <- as.integer(hit)
  if (is.na(i)) return(NULL)
  list(left = substr(line, 1L, i - 1L),
       right = substr(line, i + 1L, nchar(line)))
}

# Read and fail-closed-validate a cases manifest STRUCTURE: frozen header,
# every row complete (8 columns), case names non-empty and unique, the
# dimensional counts whole and positive. SEMANTIC classification -- the init
# vocabulary, the seed/replicate law -- belongs to the certified kernel
# face, whose exit status is the source of truth for a fault and whose
# reported meta is what the receipt attestation compares against. A client
# that re-implements the kernel's validators pre-empts the witnessed death
# channel with a guess (the exact class the G pair pins: a batch row the
# kernel rejects at status 2 must arrive at the consumer AS a status-2
# death, not as a client-side vocabulary stop). Returns a character matrix
# with the frozen column names.
kp_read_manifest <- function(manifest) {
  if (!file.exists(manifest)) {
    stop("cases manifest not found: ", manifest, domain = NA)
  }
  lines <- readLines(manifest, warn = FALSE)
  lines <- lines[nzchar(lines)]
  if (!length(lines)) stop("cases manifest is empty: ", manifest, domain = NA)
  if (!identical(lines[[1L]], .KP_BATCH_HEADER)) {
    stop("cases manifest header must be '", .KP_BATCH_HEADER, "', got '",
         lines[[1L]], "'", domain = NA)
  }
  rows <- lines[-1L]
  if (!length(rows)) stop("cases manifest holds no rows", domain = NA)
  fields <- strsplit(rows, ",", fixed = TRUE)
  lens <- lengths(fields)
  bad <- which(lens != .KP_BATCH_COLUMNS)
  if (length(bad)) {
    stop("cases manifest row ", bad[[1L]] + 1L, ": expected ",
         .KP_BATCH_COLUMNS, " columns, got ", lens[[bad[[1L]]]],
         domain = NA)
  }
  mat <- matrix(unlist(fields, use.names = FALSE),
                nrow = length(fields), ncol = .KP_BATCH_COLUMNS,
                byrow = TRUE)
  colnames(mat) <- strsplit(.KP_BATCH_HEADER, ",", fixed = TRUE)[[1L]]
  cases <- mat[, , drop = FALSE]
  blank <- which(!nzchar(cases[, "case"]))
  if (length(blank)) {
    stop("cases manifest row ", blank[[1L]] + 1L,
         ": the case name must be non-empty", domain = NA)
  }
  for (i in seq_len(nrow(cases))) {
    whole <- function(col) {
      v <- suppressWarnings(as.integer(cases[i, col]))
      if (is.na(v) || v < 1L) {
        stop("cases manifest row ", i + 1L, ": column '", col,
             "' must be a positive whole number, got '",
             cases[i, col], "'", domain = NA)
      }
      v
    }
    invisible(whole("iters"))
    invisible(whole("m"))
    invisible(whole("n"))
    invisible(whole("k"))
  }
  dup <- duplicated(cases[, "case"])
  if (any(dup)) {
    stop("cases manifest repeats the case name '",
         cases[which(dup)[[1L]], "case"], "'", domain = NA)
  }
  cases
}

## ---- receipt attestation before consumption ---------------------------------

# meta.csv as key -> raw string map; malformed/duplicate/missing-key lines
# are fail-closed (mirror of the certified reader the P1 family witnessed).
kp_read_meta_csv <- function(path) {
  if (!file.exists(path)) {
    stop("msuiter-kernel did not produce meta.csv in the output directory: ",
         path, domain = NA)
  }
  lines <- readLines(path, warn = FALSE)
  lines <- lines[nzchar(lines)]
  meta <- list()
  for (line in lines) {
    sp <- .kp_split1(line)
    if (is.null(sp)) {
      stop("meta.csv line is not a key,value pair: ", line, domain = NA)
    }
    if (!is.null(meta[[sp$left]])) {
      stop("meta.csv repeats the field '", sp$left, "'.", domain = NA)
    }
    meta[[sp$left]] <- sp$right
  }
  miss <- setdiff(.KP_META_KEYS, names(meta))
  if (length(miss)) {
    stop("meta.csv is missing the required field '", miss[[1L]], "'.",
         domain = NA)
  }
  meta
}

# Read one rows x cols %.17e comma grid back; every deviation is
# fail-closed and names the file. (The L4 pair adds the vectorized fast
# route with an identical()-grade round-trip predicate against this one.)
kp_read_matrix_csv <- function(path, nrows, ncols, name) {
  if (!file.exists(path)) {
    stop("msuiter-kernel did not produce ", name,
         " in the output directory: ", path, domain = NA)
  }
  lines <- readLines(path, warn = FALSE)
  lines <- lines[nzchar(lines)]
  if (!identical(length(lines), as.integer(nrows))) {
    stop(name, " must hold exactly ", nrows, " rows, got ", length(lines),
         ".", domain = NA)
  }
  fields <- strsplit(lines, ",", fixed = TRUE)
  lens <- lengths(fields)
  bad <- which(lens != as.integer(ncols))
  if (length(bad)) {
    stop(name, " row ", bad[[1L]], " has ", lens[[bad[[1L]]]],
         " comma-separated fields, expected ", ncols, ".", domain = NA)
  }
  vals <- suppressWarnings(as.numeric(unlist(fields, use.names = FALSE)))
  if (!all(is.finite(vals))) {
    stop(name, " contains a non-finite value.", domain = NA)
  }
  if (any(vals < 0)) {
    hit <- which(vals < 0)[[1L]]
    stop(name, " contains a negative entry (flattened position ",
         hit, ").", domain = NA)
  }
  matrix(vals, nrow = as.integer(nrows), ncol = as.integer(ncols),
         byrow = TRUE)
}

# trace.csv: header, exactly iters+1 objective rows, the t column counting
# 0..iters without gaps, every objective finite.
kp_read_trace_csv <- function(path, iters.expect, name) {
  if (!file.exists(path)) {
    stop("msuiter-kernel did not produce ", name,
         " in the output directory: ", path, domain = NA)
  }
  lines <- readLines(path, warn = FALSE)
  lines <- lines[nzchar(lines)]
  if (!length(lines) || !identical(lines[[1L]], "t,objective")) {
    stop(name, " must start with the 't,objective' header.", domain = NA)
  }
  rows <- lines[-1L]
  want <- .kp_count(iters.expect, "iters") + 1L
  if (!identical(length(rows), want)) {
    stop(name, " must hold iterations + 1 = ", want,
         " objective rows, got ", length(rows), ".", domain = NA)
  }
  ts <- integer(length(rows))
  obj <- numeric(length(rows))
  for (i in seq_len(length(rows))) {
    sp <- .kp_split1(rows[[i]])
    if (is.null(sp)) {
      stop(name, " row is not a t,objective pair: ", rows[[i]], domain = NA)
    }
    ts[[i]] <- suppressWarnings(as.integer(sp$left))
    obj[[i]] <- suppressWarnings(as.numeric(sp$right))
    if (is.na(ts[[i]]) || !is.finite(obj[[i]])) {
      stop(name, " row ", i, " is unreadable: ", rows[[i]], domain = NA)
    }
  }
  if (!identical(ts, seq_len(want) - 1L)) {
    stop(name, " iteration column must count 0, 1, ... without gaps.",
         domain = NA)
  }
  obj
}

# The per-case receipt: the expected protocol fields (asked vs reported --
# the meta-expect attestation of the certified contract) plus the W/H grid
# and trace structural checks. A case is NOT consumable before this passes;
# every fault names the case and the file. seed/replicate arrive as the
# manifest's raw strings ("" when the column is empty).
# Route selector (parity plan P3): the three grid/trace reads ride either
# the audited scalar reference readers or, as the DEFAULT, the P2 L4
# vectorized readers of R/kernel-parse.R. The L4 family and
# tests/testthat/test-kernel-attest-route.R pin both routes at identical()
# grade over real certified bytes -- the receipt strength does not move
# with the route -- and "reference" stays available for adjudication. An
# unknown route is fail-closed.
kp_attest_case <- function(case, out.dir, m, n, k, iters, init, seed,
                           replicate, route = c("fast", "reference")) {
  where <- function(msg) paste0("receipt attestation failed for case '",
                                case, "': ", msg)
  route <- route[[1L]]
  if (!identical(route, "fast") && !identical(route, "reference")) {
    stop(where(paste0("unknown attest route '", route,
                      "': expected 'fast' or 'reference'")), domain = NA)
  }
  meta <- kp_read_meta_csv(file.path(out.dir, "meta.csv"))
  expect <- list(
    protocol = as.character(.KP_PROTOCOL),
    command = "fit-kl",
    init = init,
    seed = if (identical(init, "external")) "na" else as.character(seed),
    replicate = if (identical(init, "seeded"))
      as.character(if (!nzchar(replicate)) 0L else replicate) else "na",
    m = as.character(m), n = as.character(n), k = as.character(k),
    iters = as.character(iters),
    iterations = as.character(iters),
    trace_len = as.character(.kp_count(iters, "iters") + 1L))
  for (key in names(expect)) {
    # unname(): a matrix cell slice can carry its column name as a
    # 'names' attribute; identical() compares attributes, and the receipt
    # law is about BYTES, not about how the string was indexed out.
    asked <- unname(expect[[key]])
    got <- unname(meta[[key]])
    if (!identical(got, asked)) {
      stop(where(paste0("meta.csv field '", key, "' mismatch: asked ",
                       asked, ", kernel reported ",
                       if (is.null(got)) "<absent>" else got, ".")),
           domain = NA)
    }
  }
  if (identical(route, "fast")) {
    w <- kp_read_matrix_fast(file.path(out.dir, "W.csv"), m, k, "W.csv")
    h <- kp_read_matrix_fast(file.path(out.dir, "H.csv"), k, n, "H.csv")
    obj <- kp_read_trace_fast(file.path(out.dir, "trace.csv"), iters,
                              "trace.csv")
  } else {
    w <- kp_read_matrix_csv(file.path(out.dir, "W.csv"), m, k, "W.csv")
    h <- kp_read_matrix_csv(file.path(out.dir, "H.csv"), k, n, "H.csv")
    obj <- kp_read_trace_csv(file.path(out.dir, "trace.csv"), iters,
                             "trace.csv")
  }
  invisible(list(case = case, W = w, H = h, objective = obj, meta = meta))
}

## ---- the batch runner: one process per unit, attested, witnessed -----------

# Append one witness row to the attempts ledger. writeLines(con = path)
# TRUNCATES on each call, so every append after the header goes through an
# explicit file() handle.
.kp_ledger_row <- function(ledger, row) {
  con <- file(ledger, open = "a")
  on.exit(close(con), add = TRUE)
  writeLines(row, con = con)
  invisible(NULL)
}

# Run one cases manifest through the certified batch face. Laws enforced
# here: handshake once per call (not per fit); the exit status consumed by
# VALUE through kp_status; NOTHING consumable until every case's receipts
# are attested; every attempt leaves a ledger row when a ledger is asked
# for; retries are opt-in (default = exactly one attempt) and bounded.
kp_run_batch <- function(bin, manifest, root, out.root,
                         max_attempts = 1L, ledger = NULL,
                         unit = "(batch)") {
  max_attempts <- if (is.numeric(max_attempts) &&
                      length(max_attempts) == 1L &&
                      is.finite(max_attempts) &&
                      max_attempts == floor(max_attempts))
    as.integer(max_attempts) else NA_integer_
  if (is.na(max_attempts) || max_attempts < .KP_ATTEMPTS_MIN ||
      max_attempts > .KP_ATTEMPTS_MAX) {
    stop("max_attempts must be a whole number in [",
         .KP_ATTEMPTS_MIN, ", ", .KP_ATTEMPTS_MAX,
         "] (1 is the no-retry default route); max_attempts is a retry ",
         "budget and a retry budget out of range is a configuration fault",
         domain = NA)
  }
  if (!is.null(ledger) && (!is.character(ledger) || length(ledger) != 1L ||
                           !nzchar(ledger) || is.na(ledger))) {
    stop("'ledger' must be NULL or a single non-empty path", domain = NA)
  }
  cases <- kp_read_manifest(manifest)
  kp_handshake(bin)
  argv <- c("fit-kl", "--cases", manifest, "--root", root,
            "--out-root", out.root)
  if (!is.null(ledger)) {
    writeLines("unit,attempt,status,cause", con = ledger)
  }
  attempt <- 0L
  last.fault <- NULL
  while (attempt < max_attempts) {
    attempt <- attempt + 1L
    # A re-attempt starts from a clean output tree: a batch is
    # all-or-nothing, so residue of a failed attempt must never mix with
    # the attested bytes of a successful one.
    if (attempt > 1L) {
      for (i in seq_len(nrow(cases))) {
        unlink(file.path(out.root, cases[i, "case"]), recursive = TRUE,
               force = TRUE)
      }
    }
    res <- kp_exec(bin, argv)
    status <- kp_status(res)
    if (!identical(status, 0L)) {
      err.text <- paste(as.character(attr(res, "stderr")), collapse = " | ")
      last.fault <- paste0("msuiter-kernel batch unit '", unit,
                           "' attempt ", attempt,
                           " exited with status ", status,
                           "; stderr: ", err.text)
      if (!is.null(ledger)) {
        .kp_ledger_row(ledger, paste0(unit, ",", attempt, ",", status,
                                      ",exit-status"))
      }
      next
    }
    # rc 0 is only a PROMISE; consumption waits for per-case receipts. The
    # attested bundles ride the return upward -- the consumer receives the
    # validated bytes, never a directory path it must trust blindly. The
    # reads ride the DEFAULT attest route (the P2 L4 vectorized readers,
    # pinned identical()-grade to the reference route; see kp_attest_case).
    receipt.fault <- NULL
    attested <- list()
    for (i in seq_len(nrow(cases))) {
      got <- tryCatch(
        kp_attest_case(
          case = cases[i, "case"],
          out.dir = file.path(out.root, cases[i, "case"], "out"),
          m = as.integer(cases[i, "m"]), n = as.integer(cases[i, "n"]),
          k = as.integer(cases[i, "k"]), iters = as.integer(cases[i, "iters"]),
          init = cases[i, "init"],
          seed = cases[i, "seed"],
          replicate = cases[i, "replicate"]),
        error = function(e) conditionMessage(e))
      if (is.character(got)) { receipt.fault <- got; break }
      attested[[cases[i, "case"]]] <- got
    }
    if (!is.null(receipt.fault)) {
      last.fault <- receipt.fault
      if (!is.null(ledger)) {
        .kp_ledger_row(ledger, paste0(unit, ",", attempt, ",0,receipt"))
      }
      next
    }
    if (!is.null(ledger)) {
      .kp_ledger_row(ledger, paste0(unit, ",", attempt, ",0,ok"))
    }
    return(invisible(list(unit = unit, attempts = attempt,
                          cases = nrow(cases), out.root = out.root,
                          attested = attested)))
  }
  stop(last.fault, domain = NA)
}
