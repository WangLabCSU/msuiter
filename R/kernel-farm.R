# P2 worker farm: the fan-out controller for the independent fits
# (parity plan P2, pair L2; lane card /tmp/perf2lane/lane-task.md).
#
# The forensics Q3 finding this file answers: the rust tip ran ONE serial
# kernel at a time on a 10-vCPU host (sustained 1.008 cores -- ~90% idle
# compute), while the R faces' orphaned PSOCK workers (PPID=1) escaped the
# sidecar's rusage census (conc 2.058 vs container 3.69: the undercount).
# The farm therefore carries four laws, each witnessed:
#   * NO UNDERCOUNT: every unit is served exactly once, the requested
#     fan-out is recorded in the witness, and the farm makes zero process
#     contacts itself -- all contact is delegated to 'serve' (which is the
#     L1 kp_serve_unit by default, the one that pays the two contacts a
#     unit);
#   * CAPS VERBATIM: the seven thread caps of forensics-dossier Q3 are set
#     for the served phase so every process the farm's units spawn runs
#     one-threaded under them (census fact: caps hold per process, all
#     NLWP <= 2), and the ambient environment is restored afterwards,
#     also along a fault -- the farm borrows the process-global env, it
#     does not keep it;
#   * RSS GUARD: on the 8 GB rig host the fan-out is refused BEFORE any
#     contact when the injectable memory probe reports below-floor
#     headroom; a probe that cannot answer (NA) is treated as below floor
#     -- fail closed;
#   * ORPHANS REAPED: what a unit adopted during its run (an PSOCK-style
#     helper reparented to PPID 1, a detached wait=FALSE child -- both
#     census-proven shapes of the undercount) is registered in the farm's
#     adoption ledger and is census-dead when the farm returns, on the
#     success AND the faulted path.
# WHAT the kernel computes is untouched: the farm schedules, it never
# computes; the served bytes must not depend on how many hands served them
# (serial vs farmed results are identical()-grade -- the invariance law).

## ---- the frozen farm constants ------------------------------------------------

# The seven thread caps, verbatim from the forensics Q3 census (order and
# spelling are the contract; the red battery mirrors them independently).
.KP_FARM_CAPS <- c("OMP_NUM_THREADS", "OMP_THREAD_LIMIT", "R_LIMIT_THREADS",
                   "GOMAXPROCS", "MSUITER_THREADS", "STAN_OMP_NUM_THREADS",
                   "OPENBLAS_NUM_THREADS")

# The worker domain: one hand means the in-process serial; the fan-out
# starts at four and is capped at eight (the rig's ten vCPUs minus the
# sidecar/measurement headroom -- fan-out=1 law governs MEASUREMENT runs,
# not what the farm may offer).
.KP_FARM_WORKERS_MIN <- 4L
.KP_FARM_WORKERS_MAX <- 8L

# The RSS floor: available headroom one worker fan-out must clear before
# the first contact (one GiB: the eight GB rig host's measured per-worker
# kernel working set plus the R session).
.KP_FARM_RSS_FLOOR <- 1024 * 1024 * 1024

# The adoption ledger is addressed through this environment variable for
# the lifetime of the run: an unit registers the pid of anything it adopts.
.KP_FARM_ADOPT_ENV <- "KP_FARM_ADOPT"

## ---- the process census and the reaper ----------------------------------------

# One -ax census through a file capture (this build's bare ps hides
# tty-less processes; every observation here must see the detached class).
.kp_farm.census <- function() {
  tf <- tempfile("kp-farm-census-")
  # The format spec rides ONE -o token (split columns silently garble the
  # census on this build); -ax is mandatory -- bare ps hides tty-less
  # processes here.
  invisible(system2("ps", c("-o", "pid=,ppid=,command=", "-ax"),
                    stdin = "", stdout = tf, stderr = tf, wait = TRUE))
  L <- readLines(tf, warn = FALSE)
  unlink(tf)
  tok <- strsplit(trimws(L), "[[:space:]]+", perl = TRUE)
  keep <- vapply(tok, function(t) length(t) >= 3L,
                 FUN.VALUE = logical(1L), USE.NAMES = FALSE)
  pid <- suppressWarnings(as.integer(vapply(tok[keep], `[[`, 1L,
                                            FUN.VALUE = "", USE.NAMES = FALSE)))
  ppid <- suppressWarnings(as.integer(vapply(tok[keep], `[[`, 2L,
                                             FUN.VALUE = "", USE.NAMES = FALSE)))
  ok <- !is.na(pid) & !is.na(ppid)
  list(pid = pid[ok], ppid = ppid[ok])
}

.kp_farm.alive <- function(pids) {
  if (length(pids) == 0L) return(integer(0L))
  c <- .kp_farm.census()
  pids[pids %in% c$pid]
}

# This build's Sys.setenv refuses a single named-vector argument (it
# demands per-argument names); do.call over the as.list of the pair vector
# is the verbatim-equivalent route (probe-banked host quirk).
.kp_farm.setenv <- function(pairs) {
  if (length(pairs) > 0L) do.call("Sys.setenv", as.list(pairs))
  invisible(0L)
}

# The reap: adopted pids plus any child the main process still carries,
# SIGKILLed and census-poll verified dead. A resister is a hard fault --
# an un-attested live process would undercount exactly as the forensics
# measured.
.kp_farm.reap <- function(ledger) {
  adopted <- integer(0L)
  if (file.exists(ledger)) {
    lines <- suppressWarnings(readLines(ledger, warn = FALSE))
    pids <- suppressWarnings(as.integer(trimws(lines)))
    adopted <- pids[!is.na(pids)]
  }
  c <- .kp_farm.census()
  kids <- c$pid[c$ppid == Sys.getpid()]
  targets <- unique(c(adopted, kids))
  targets <- targets[targets != Sys.getpid()]
  # One settle before the first census: a just-forgotten child needs a
  # moment to become census-visible, and an invisible target must never
  # masquerade as a reaped one.
  Sys.sleep(0.1)
  deadline <- 60L
  while (deadline > 0L) {
    live <- .kp_farm.alive(targets)
    if (length(live) == 0L) return(invisible(0L))
    suppressWarnings(tryCatch(tools::pskill(live, 9L), error = function(e) NULL))
    deadline <- deadline - 1L
    Sys.sleep(0.05)
  }
  stop("farm reaping law violated: adopted processes still alive: ",
       paste(.kp_farm.alive(targets), collapse = ", "),
       " -- an orphan that escapes the census undercounts the measured tree",
       domain = NA)
}

## ---- the farm ------------------------------------------------------------------

# Fan the independent units out over the worker pool.
#
# Contract:
#  * units: a non-empty, uniquely named list; each element is the argument
#    list handed to 'serve' (by default the L1 kp_serve_unit) -- the farm
#    itself contacts nothing;
#  * workers: 1 (in-process serial) or [4, 8]; every other value is
#    refused before any contact;
#  * caps: the seven thread caps are set for the served phase and the
#    ambient environment restored on the way out, also along a fault;
#  * mem.probe: an optional function returning available bytes; below
#    .KP_FARM_RSS_FLOOR the fan-out is refused before any contact; the
#    serial route, which fans nothing out, is not asked;
#  * mclapply: the capability surface. A function is injected verbatim
#    (the tests' counting stand-in); FALSE declares the capability absent;
#    NULL auto-probes parallel::mclapply;
#  * adoption: for the run's lifetime .KP_FARM_ADOPT_ENV addresses a
#    ledger; pids registered there are dead before the farm returns.
#
# Returns invisible(list(results, plan, workers, parallel, witness));
# 'results' is named by unit, 'plan' is the deterministic round-robin
# schedule the fan-out was asked to follow, 'witness' attests the route
# taken -- a fallback never happens silently.
kp_farm <- function(units, workers = 4L, serve = NULL, mem.probe = NULL,
                    mclapply = NULL, caps = TRUE) {
  workers <- .kp_count(workers, "workers")
  if (!(workers == 1L || (workers >= .KP_FARM_WORKERS_MIN &&
                          workers <= .KP_FARM_WORKERS_MAX))) {
    stop("farm workers must be 1 (in-process serial) or in [",
         .KP_FARM_WORKERS_MIN, ", ", .KP_FARM_WORKERS_MAX,
         "] -- got: ", as.character(workers), domain = NA)
  }
  if (!is.list(units) || length(units) == 0L || is.null(names(units)) ||
      !all(nzchar(names(units))) || anyDuplicated(names(units)) ||
      !all(vapply(units, is.list, FUN.VALUE = logical(1L),
                  USE.NAMES = FALSE))) {
    stop("'units' must be a non-empty, uniquely named list of argument ",
         "lists (each handed verbatim to 'serve')", domain = NA)
  }
  if (is.null(serve)) serve <- kp_serve_unit
  if (!is.function(serve)) {
    stop("'serve' must be a function", domain = NA)
  }
  if (!is.null(mem.probe) && !is.function(mem.probe)) {
    stop("'mem.probe' must be a function returning available bytes",
         domain = NA)
  }
  if (!isTRUE(caps) && !identical(caps, FALSE)) {
    stop("'caps' must be TRUE or FALSE", domain = NA)
  }
  n <- length(units)
  # The RSS guard guards the FAN-OUT, before any contact; the serial route
  # brings no new processes, so it is not asked.
  if (workers > 1L && !is.null(mem.probe)) {
    avail <- tryCatch(mem.probe(), error = function(e) NA_real)
    if (!is.numeric(avail) || length(avail) != 1L || is.na(avail) ||
        avail < .KP_FARM_RSS_FLOOR) {
      stop("farm refuses to fan out: RSS guard -- available headroom ",
           if (is.numeric(avail) && length(avail) == 1L)
             format(avail, scientific = FALSE) else "unreadable",
           " bytes is below the floor ",
           format(.KP_FARM_RSS_FLOOR, scientific = FALSE),
           " (workers ", as.character(workers), " not started)", domain = NA)
    }
  }
  saved <- NULL
  ledger <- tempfile("kp-farm-adopt-")
  if (isTRUE(caps)) {
    # Per-name capture with this build's absence semantics: an unset
    # variable answers the EMPTY STRING (never NA), and for the caps an
    # empty value is no meaningful ambient state -- both read as absent so
    # the restore truly unsets them.
    saved <- vapply(.KP_FARM_CAPS,
                    function(nm) { v <- Sys.getenv(nm)
                                  if (length(v) == 0L || identical(v[[1L]], ""))
                                    as.character(NA) else v[[1L]] },
                    FUN.VALUE = "", USE.NAMES = FALSE)
    names(saved) <- .KP_FARM_CAPS
    cap.env <- rep("1", length(.KP_FARM_CAPS))
    names(cap.env) <- .KP_FARM_CAPS
    .kp_farm.setenv(cap.env)
  }
  writeLines(character(0L), con = ledger)
  adopt.env <- ledger
  names(adopt.env) <- .KP_FARM_ADOPT_ENV
  .kp_farm.setenv(adopt.env)
  on.exit({
    # Reap FIRST while the ledger is addressed, then surrender the
    # borrowed environment.
    tryCatch(.kp_farm.reap(ledger),
             error = function(e) warning(conditionMessage(e), domain = NA))
    if (isTRUE(caps) && !is.null(saved)) {
      have <- saved[!is.na(saved)]
      if (length(have) > 0L) .kp_farm.setenv(have)
      missing <- names(saved)[is.na(saved)]
      if (length(missing) > 0L) Sys.unsetenv(missing)
    }
    Sys.unsetenv(.KP_FARM_ADOPT_ENV)
    unlink(ledger)
  })
  plan <- list(unit = names(units),
               slot = if (workers == 1L) rep(1L, n)
                      else ((seq_len(n) - 1L) %% workers) + 1L)
  do.unit <- function(i) do.call(serve, units[[i]])
  mc <- NULL
  parallel <- FALSE
  witness <- ""
  if (workers == 1L) {
    witness <- "serial in-process: workers == 1 (no pool was touched)"
  } else if (is.function(mclapply)) {
    mc <- mclapply
    parallel <- TRUE
    witness <- paste0("parallel: injected mclapply over ",
                      as.character(workers), " workers serving ",
                      as.character(n), " units")
  } else if (is.logical(mclapply) && length(mclapply) == 1L && !is.na(mclapply) && !mclapply) {
    witness <- paste0("serial fallback: parallel::mclapply unavailable ",
                      "(declared absent by the caller; workers ",
                      as.character(workers), " requested)")
  } else {
    probed <- tryCatch(getFromNamespace("mclapply", "parallel"),
                       error = function(e) NULL)
    if (is.function(probed)) {
      mc <- probed
      parallel <- TRUE
      witness <- paste0("parallel: parallel::mclapply over ",
                        as.character(workers), " workers serving ",
                        as.character(n), " units")
    } else {
      witness <- paste0("serial fallback: parallel::mclapply capability ",
                        "absent -- the probe found no pool (workers ",
                        as.character(workers), " requested)")
    }
  }
  results <- if (parallel) {
    mc(seq_len(n), do.unit, mc.cores = workers)
  } else {
    lapply(seq_len(n), do.unit)
  }
  names(results) <- names(units)
  invisible(list(results = results, plan = plan, workers = workers,
                 parallel = parallel, witness = witness))
}
