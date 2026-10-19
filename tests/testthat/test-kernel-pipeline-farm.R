# P2 lane, TDD pair L2 (worker farm): the fan-out controller for the
# independent fits. Forensics Q3 banked the two facts this pair retires:
# the rust tip runs ONE serial kernel at a time on a 10-vCPU host (pole
# 1.008 cores -- ~90% idle compute for minutes per cell), while the R-face
# farm's orphaned PSOCK workers (PPID=1) escaped the sidecar's wait4-rusage
# census (conc 2.058 vs container 3.69 -- the UNDERCOUNT). The law this
# battery pins: the farm must never undercount (every unit served exactly
# once, the requested fan-out witnessed), every worker process runs under
# the seven verbatim thread caps (forensics-dossier §3: caps hold per
# process, all NLWP <= 2), the 8 GB rig host gets an RSS guard before
# fan-out, and PSOCK-orphan reaping is ENFORCED -- anything a unit adopted
# during the run is dead by the time the farm returns, proven by census.
#
# Invariance law (the L1 companion): the served bytes must not depend on
# HOW MANY hands served them -- serial and farmed results are identical().
# WHAT the kernel computes is again untouched: the farm only schedules.
#
# D3: every numeric is generated from a set seed; no certified binary is
# contacted here -- the farm delegates all process contact to 'serve' and
# this battery proves it never contacts one itself.
#
# Units F1..F8 bind the future surface (msuiter:::kp_farm) and are red by
# absence until the GREEN commit lands R/kernel-farm.R.

## ---- farm-local fixtures -----------------------------------------------------

# The seven verbatim caps, mirrored from the forensics-dossier §3 census
# (OMP_NUM_THREADS/OMP_THREAD_LIMIT/R_LIMIT_THREADS/GOMAXPROCS/
# MSUITER_THREADS/STAN_OMP_NUM_THREADS/OPENBLAS_NUM_THREADS = 1). This
# vector is the contract witness: the farm module's cap constant must be
# identical to it, in order and spelling.
.kpp.farm.caps <- c("OMP_NUM_THREADS", "OMP_THREAD_LIMIT",
                    "R_LIMIT_THREADS", "GOMAXPROCS", "MSUITER_THREADS",
                    "STAN_OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS")

.kpp.const <- function(name) {
  getFromNamespace(name, "msuiter")
}

# n synthetic units: named argument lists the mock serve consumes; the
# mock's answer is a deterministic function of the unit name, so serial vs
# farmed results can be compared identical()-grade.
.kpp.farm.units <- function(n) {
  names <- paste0("u", sprintf("%02d", seq_len(n)))
  units <- lapply(names, function(nm) list(tag = nm))
  names(units) <- names
  units
}

.kpp.farm.mock.serve <- function(st, extra = NULL) {
  function(..., tag) {
    st$served <- c(st$served, tag)
    if (!is.null(extra)) extra(tag, ...)
    list(tag = tag, value = nchar(tag) + 1L)
  }
}

# Counting stand-in for parallel::mclapply: runs in-process (the unit
# battery must not fork), records the requested fan-out so the farm's
# mc.cores law is countable, preserves index order.
.kpp.farm.mock.mclapply <- function(st) {
  st$calls <- 0L
  st$cores <- integer(0L)
  function(X, FUN, ...) {
    dots <- list(...)
    st$cores <- c(st$cores, dots$mc.cores)
    st$calls <- st$calls + 1L
    lapply(as.list(X), function(i) FUN(i))
  }
}

## ---- the process census (renamed-R build: bare ps hides tty-less
## ---- processes, so every census runs -ax through one file capture) ----------

.kpp.census <- function() {
  tf <- tempfile("kpp-census-")
  # One -o token for the whole format spec; -ax mandatory on this rig.
  invisible(system2("ps", c("-o", "pid=,ppid=,command=", "-ax"),
                    stdin = "", stdout = tf, stderr = tf, wait = TRUE))
  L <- readLines(tf, warn = FALSE)
  tok <- strsplit(trimws(L), "[[:space:]]+", perl = TRUE)
  keep <- vapply(tok, function(t) length(t) >= 3L,
                 FUN.VALUE = logical(1L), USE.NAMES = FALSE)
  pid <- suppressWarnings(as.integer(vapply(tok[keep], `[[`, 1L,
                                            FUN.VALUE = "", USE.NAMES = FALSE)))
  ppid <- suppressWarnings(as.integer(vapply(tok[keep], `[[`, 2L,
                                              FUN.VALUE = "", USE.NAMES = FALSE)))
  cmd <- vapply(tok[keep], function(t) paste(t[-(1L:2L)], collapse = " "),
                FUN.VALUE = "", USE.NAMES = FALSE)
  ok <- !is.na(pid) & !is.na(ppid)
  list(pid = pid[ok], ppid = ppid[ok], cmd = cmd[ok])
}

.kpp.alive <- function(pid) {
  if (length(pid) == 0L) return(integer(0L))
  c <- .kpp.census()
  pid[pid %in% c$pid]
}

# Two orphan classes the forensics named, both born (or reparented) at
# PPID 1 so the naive child-tree census cannot see them:
#  * "detached": system2 wait=FALSE (this build detaches to PPID 1); the
#    pid is recovered by census diff -- unique durations keep the diff
#    collision-free.
#  * "shw": an sh that backgrounds a sleep, reports its pid through
#    stdout, and exits -- the PSOCK-orphan shape (PPID 1, pid known).
.kpp.spawn.adopt <- function(duration, via = c("detached", "shw")) {
  via <- match.arg(via, c("detached", "shw"))
  dur <- as.character(duration)
  if (identical(via, "detached")) {
    b <- .kpp.census()
    invisible(system2("/bin/sleep", dur, wait = FALSE))
    Sys.sleep(0.25)                                # fork-visibility settle
    a <- .kpp.census()
    new <- setdiff(a$pid, b$pid)
    hits <- new[a$ppid[match(new, a$pid, nomatch = 0L)] == 1L &
                grepl(paste0("sleep ", dur), a$cmd[match(new, a$pid)])]
    expect_identical(length(hits), 1L,
                     info = paste0("detached sleep ", dur))
    hits[[1L]]
  } else {
    scr <- tempfile("kpp-orphan-")
    writeLines(c("#!/bin/sh", paste0("sleep ", dur, " & echo $!")), con = scr)
    tf <- tempfile("kpp-orphan-out-")
    invisible(system2("/bin/sh", scr, stdin = "", stdout = tf,
                      stderr = tf, wait = TRUE))
    op <- suppressWarnings(as.integer(trimws(readLines(tf, warn = FALSE)[[1L]])))
    expect_false(is.na(op), info = tf)
    Sys.sleep(0.25)                                # reparent-visibility settle
    op
  }
}

## ---- the battery --------------------------------------------------------------

test_that("F1 plan determinism and immutability: the same unit list yields
           the same plan twice, round-robin slots, inputs untouched", {
  kp.farm <- .kpp_surface("kp_farm")               # red by absence
  st.a <- new.env(parent = emptyenv()); st.a$served <- character(0L)
  st.b <- new.env(parent = emptyenv()); st.b$served <- character(0L)
  mk <- .kpp.farm.mock.mclapply(new.env(parent = emptyenv()))
  units <- .kpp.farm.units(6L)
  snapshot <- units
  a <- kp.farm(units = units, workers = 4L,
               serve = .kpp.farm.mock.serve(st.a), mclapply = mk)
  b <- kp.farm(units = units, workers = 4L,
               serve = .kpp.farm.mock.serve(st.b), mclapply = mk)
  expect_identical(a$plan, b$plan)
  expect_identical(a$plan$unit, names(units))
  expect_identical(a$plan$slot, c(1L, 2L, 3L, 4L, 1L, 2L))
  expect_identical(units, snapshot)                 # no mutation
  expect_identical(a$results, b$results)
  expect_identical(names(a$results), names(units))
})

test_that("F2 serial/farm invariance and the no-undercount law: every unit
           served exactly once on both routes, identical bytes, and the
           farm itself never contacts the kernel", {
  kp.farm <- .kpp_surface("kp_farm")               # red by absence
  st.s <- new.env(parent = emptyenv()); st.s$served <- character(0L)
  st.f <- new.env(parent = emptyenv()); st.f$served <- character(0L)
  st.x <- new.env(parent = emptyenv()); st.x$calls <- 0L
  mk <- new.env(parent = emptyenv()); mk$cores <- integer(0L); mk$calls <- 0L
  mcl <- function(X, FUN, ...) {
    dots <- list(...)
    mk$cores <- c(mk$cores, dots$mc.cores)
    mk$calls <- mk$calls + 1L
    lapply(as.list(X), function(i) FUN(i))
  }
  units <- .kpp.farm.units(9L)
  res <- list()
  .kpp_with_exec(function(bin, args) {
    st.x$calls <- st.x$calls + 1L
    stop("the farm must delegate every process contact to serve")
  }, {
    res$serial <- kp.farm(units = units, workers = 1L,
                          serve = .kpp.farm.mock.serve(st.s))
    res$farm <- kp.farm(units = units, workers = 5L,
                        serve = .kpp.farm.mock.serve(st.f), mclapply = mcl)
  })
  expect_identical(st.x$calls, 0L)                 # delegation is total
  expect_identical(sort(st.s$served), names(units)) # exactly once each
  expect_identical(sort(st.f$served), names(units))
  expect_identical(res$serial$results, res$farm$results)
  expect_identical(names(res$serial$results), names(res$farm$results))
  expect_identical(mk$cores, 5L)                   # the fan-out was requested
})

test_that("F3 the seven caps verbatim: set for the served phase, restored
           after -- also along a faulted serve", {
  kp.farm <- .kpp_surface("kp_farm")               # red by absence
  expect_identical(.kpp.const(".KP_FARM_CAPS"), .kpp.farm.caps)
  st <- new.env(parent = emptyenv()); st$served <- character(0L)
  seen <- new.env(parent = emptyenv())
  # Ambient state the restore must come back to: one cap at 9, one unset.
  # This build answers the EMPTY STRING for unset variables (never NA --
  # probe-banked), so absence is normalized to NA at the capture.
  pre <- vapply(.kpp.farm.caps,
                function(nm) { v <- Sys.getenv(nm)
                              if (length(v) == 0L || identical(v[[1L]], ""))
                                as.character(NA) else v[[1L]] },
                FUN.VALUE = "", USE.NAMES = FALSE)
  names(pre) <- .kpp.farm.caps
  Sys.setenv(OMP_NUM_THREADS = "9")
  Sys.unsetenv("GOMAXPROCS")
  on.exit({
    have <- pre[!is.na(pre)]
    if (length(have) > 0L) do.call("Sys.setenv", as.list(have))
    Sys.unsetenv(names(pre)[is.na(pre)])
  })
  probe.serve <- .kpp.farm.mock.serve(st, extra = function(tag, ...) {
    seen$vals <- c(seen$vals, list(Sys.getenv(.kpp.farm.caps)))
  })
  mk <- .kpp.farm.mock.mclapply(new.env(parent = emptyenv()))
  invisible(kp.farm(units = .kpp.farm.units(3L), workers = 4L,
                    serve = probe.serve, mclapply = mk))
  expect_false(is.null(seen$vals))
  absent <- function(x) length(x) == 1L && (is.na(x) || identical(x, ""))
  for (i in seq_along(seen$vals)) {
    expect_identical(seen$vals[[i]],
                     structure(rep("1", length(.kpp.farm.caps)),
                               names = .kpp.farm.caps))
  }
  post <- Sys.getenv(.kpp.farm.caps)
  expect_identical(post[["OMP_NUM_THREADS"]], "9")
  expect_true(absent(post[["GOMAXPROCS"]]))
  # The fault path must restore too (the on.exit law of the farm itself).
  boom <- function(..., tag) stop("simulated serve death ", tag, domain = NA)
  err <- tryCatch({
    kp.farm(units = .kpp.farm.units(2L), workers = 4L,
            serve = boom, mclapply = mk)
    NULL
  }, error = function(e) conditionMessage(e))
  expect_false(is.null(err))
  post2 <- Sys.getenv(.kpp.farm.caps)
  expect_identical(post2[["OMP_NUM_THREADS"]], "9")
  expect_true(absent(post2[["GOMAXPROCS"]]))
})

test_that("F4 the RSS guard: below the floor the farm refuses to fan out
           before any contact; serial needs no headroom", {
  kp.farm <- .kpp_surface("kp_farm")               # red by absence
  floor <- .kpp.const(".KP_FARM_RSS_FLOOR")
  expect_true(is.numeric(floor) && length(floor) == 1L && floor > 0)
  st <- new.env(parent = emptyenv()); st$served <- character(0L)
  st$probe <- 0L
  mk <- .kpp.farm.mock.mclapply(st)
  lo <- function() { st$probe <- st$probe + 1L; floor - 1 }
  err <- tryCatch({
    kp.farm(units = .kpp.farm.units(4L), workers = 4L,
            serve = .kpp.farm.mock.serve(st), mclapply = mk,
            mem.probe = lo)
    NULL
  }, error = function(e) conditionMessage(e))
  expect_false(is.null(err), "a starving host must hard-stop the fan-out")
  expect_true(grepl("RSS guard", err, fixed = TRUE), info = err)
  expect_identical(st$probe, 1L)                   # consulted, once, early
  expect_identical(st$calls, 0L)                   # nothing was scheduled
  expect_identical(st$served, character(0L))       # nothing was served
  hi <- function() { st$probe <- st$probe + 1L; floor }
  ok.res <- kp.farm(units = .kpp.farm.units(4L), workers = 4L,
                    serve = .kpp.farm.mock.serve(st), mclapply = mk,
                    mem.probe = hi)
  expect_identical(length(ok.res$results), 4L)
  # Serial fans nothing out, so the guard is not in its way.
  st1 <- new.env(parent = emptyenv()); st1$served <- character(0L)
  st1$probe <- 0L
  invisible(kp.farm(units = .kpp.farm.units(2L), workers = 1L,
                    serve = .kpp.farm.mock.serve(st1),
                    mem.probe = function() { st1$probe <- st1$probe + 1L
                                            0 }))
  expect_identical(st1$probe, 0L)
})

test_that("F5 PSOCK-orphan reaping is enforced: what a unit adopted is
           census-dead when the farm returns, on both orphan shapes", {
  kp.farm <- .kpp_surface("kp_farm")               # red by absence
  adopt.env <- .kpp.const(".KP_FARM_ADOPT_ENV")    # the adoption ledger name
  st <- new.env(parent = emptyenv()); st$served <- character(0L)
  st$alive <- integer(0L)
  born <- new.env(parent = emptyenv()); born$pids <- integer(0L)
  serve <- function(..., tag) {
    st$served <- c(st$served, tag)
    # Each unit adopts one orphan of the forensics' shape: a backgrounded
    # sleep whose pid the unit registers in the farm's adoption ledger.
    pid <- .kpp.spawn.adopt(41L + as.integer(substr(tag, 2L, 3L)),
                            via = "shw")
    expect_identical(length(.kpp.alive(pid)), 1L)  # positive control: alive
    born$pids <- c(born$pids, pid)
    ledger <- Sys.getenv(adopt.env)
    expect_false(is.na(ledger), "the adoption ledger must be addressed")
    con <- file(ledger, open = "a"); writeLines(as.character(pid), con)
    close(con)
    list(tag = tag, value = 0L)
  }
  mk <- .kpp.farm.mock.mclapply(new.env(parent = emptyenv()))
  invisible(kp.farm(units = .kpp.farm.units(3L), workers = 4L,
                    serve = serve, mclapply = mk))
  expect_identical(length(born$pids), 3L)
  expect_identical(.kpp.alive(born$pids), integer(0L))
  # The detached shape (system2 wait=FALSE reparents to PPID 1) is the
  # second undercount class; registered orphans of it are equally swept.
  st2 <- new.env(parent = emptyenv()); st2$served <- character(0L)
  d.pids <- new.env(parent = emptyenv()); d.pids$pids <- integer(0L)
  serve2 <- function(..., tag) {
    st2$served <- c(st2$served, tag)
    pid <- .kpp.spawn.adopt(51L + as.integer(substr(tag, 2L, 3L)),
                            via = "detached")
    expect_identical(length(.kpp.alive(pid)), 1L)
    d.pids$pids <- c(d.pids$pids, pid)
    con <- file(Sys.getenv(adopt.env), open = "a")
    writeLines(as.character(pid), con)
    close(con)
    list(tag = tag, value = 0L)
  }
  invisible(kp.farm(units = .kpp.farm.units(2L), workers = 4L,
                    serve = serve2, mclapply = mk))
  expect_identical(.kpp.alive(d.pids$pids), integer(0L))
})

test_that("F5b the reaping law survives a faulted unit: the on.exit sweep
           still kills every registered orphan", {
  kp.farm <- .kpp_surface("kp_farm")               # red by absence
  adopt.env <- .kpp.const(".KP_FARM_ADOPT_ENV")
  born <- new.env(parent = emptyenv()); born$pids <- integer(0L)
  st <- new.env(parent = emptyenv()); st$served <- character(0L)
  serve <- function(..., tag) {
    st$served <- c(st$served, tag)
    pid <- .kpp.spawn.adopt(61L, via = "shw")
    expect_identical(length(.kpp.alive(pid)), 1L)
    born$pids <- c(born$pids, pid)
    con <- file(Sys.getenv(adopt.env), open = "a")
    writeLines(as.character(pid), con)
    close(con)
    if (identical(tag, "u02")) stop("simulated mid-unit death", domain = NA)
    list(tag = tag, value = 0L)
  }
  mk <- .kpp.farm.mock.mclapply(new.env(parent = emptyenv()))
  err <- tryCatch({
    kp.farm(units = .kpp.farm.units(2L), workers = 4L,
            serve = serve, mclapply = mk)
    NULL
  }, error = function(e) conditionMessage(e))
  expect_false(is.null(err), "the fault must reach the caller")
  expect_true(grepl("simulated mid-unit death", err, fixed = TRUE), info = err)
  expect_identical(.kpp.alive(born$pids), integer(0L))
})

test_that("F9 the POSIX rig probe answers honestly: it refuses a machine
           that cannot run the rig, caches its answer, and shares the units'
           machinery verbatim (the windows R CMD check arms of 2026-10-19
           ran the F5 orphans into an absent /bin/sh and quoted
           subscript-out-of-bounds where a skip was owed)", {
  # Negative control, platform-independent: no machine can execute this
  # trio, so a probe that answers TRUE for it is measuring its own
  # optimism. The two calls also pin the cache: a re-ask returns the same
  # settled answer, not a re-vote.
  fake <- list(ps = "definitely-not-a-ps-9f3",
                sleep = "/definitely-not/sleep-9f3",
                sh = "/definitely-not/sh-9f3")
  expect_false(isTRUE(.kpp.posix.rig(bins = fake)))
  expect_false(isTRUE(.kpp.posix.rig(bins = fake)))
  # The probe must speak with the units' own voice: the default bins are
  # the very constants the census and the spawn helpers reach for.
  expect_identical(.kpp.posix.bins,
                   list(ps = "ps", sleep = "/bin/sleep", sh = "/bin/sh"))
})

test_that("F6 the domain: workers in {1, 4..8}; malformed units refused;
           all refusals happen before any contact", {
  kp.farm <- .kpp_surface("kp_farm")               # red by absence
  st <- new.env(parent = emptyenv()); st$served <- character(0L)
  mk <- .kpp.farm.mock.mclapply(st)
  for (bad in list(0L, 2L, 3L, 9L, 10L, -1L, 1.5, as.integer(NA), "4")) {
    err <- tryCatch({
      kp.farm(units = .kpp.farm.units(1L), workers = bad,
              serve = .kpp.farm.mock.serve(st), mclapply = mk)
      NULL
    }, error = function(e) conditionMessage(e))
    expect_false(is.null(err), info = paste(format(bad), collapse = ""))
    expect_true(grepl("workers", err, fixed = TRUE), info = err)
  }
  for (bad.units in list(NULL, list(), list(a = 1L),
                         structure(list(list(tag = "x")), names = NULL),
                         structure(list(list(tag = "x"),
                                         list(tag = "x")),
                                   names = c("a", "a")))) {
    err <- tryCatch({
      kp.farm(units = bad.units, workers = 4L,
              serve = .kpp.farm.mock.serve(st), mclapply = mk)
      NULL
    }, error = function(e) conditionMessage(e))
    expect_false(is.null(err), "malformed unit lists must be refused")
  }
  expect_identical(st$calls, 0L)
  expect_identical(st$served, character(0L))
  # The accepted domain serves.
  for (w in c(1L, 4L, 5L, 6L, 7L, 8L)) {
    stw <- new.env(parent = emptyenv()); stw$served <- character(0L)
    r <- kp.farm(units = .kpp.farm.units(5L), workers = w,
                 serve = .kpp.farm.mock.serve(stw),
                 mclapply = .kpp.farm.mock.mclapply(stw))
    expect_identical(length(r$results), 5L)
    expect_identical(sort(stw$served), paste0("u", sprintf("%02d", 1:5)))
  }
})

test_that("F7 workers == 1 is the in-process serial: no pool is touched,
           the route is witnessed", {
  kp.farm <- .kpp_surface("kp_farm")               # red by absence
  st <- new.env(parent = emptyenv()); st$served <- character(0L)
  mk <- .kpp.farm.mock.mclapply(st)
  res <- kp.farm(units = .kpp.farm.units(4L), workers = 1L,
                 serve = .kpp.farm.mock.serve(st), mclapply = mk)
  expect_identical(st$calls, 0L)                  # the pool was never touched
  expect_false(isTRUE(res$parallel))
  expect_true(grepl("workers == 1", res$witness, fixed = TRUE),
              info = res$witness)
  expect_identical(sort(st$served), paste0("u", sprintf("%02d", 1:4)))
})

test_that("F8 the capability probe and the witnessed fallback: a farm that
           cannot fan out says so -- never silently", {
  kp.farm <- .kpp_surface("kp_farm")               # red by absence
  st <- new.env(parent = emptyenv()); st$served <- character(0L)
  absent <- kp.farm(units = .kpp.farm.units(3L), workers = 4L,
                     serve = .kpp.farm.mock.serve(st), mclapply = FALSE)
  expect_false(isTRUE(absent$parallel))
  expect_true(grepl("mclapply", absent$witness, fixed = TRUE),
              info = absent$witness)
  expect_true(grepl("unavailable", absent$witness, fixed = TRUE) ||
              grepl("absent", absent$witness, fixed = TRUE),
              info = absent$witness)
  expect_identical(sort(st$served), paste0("u", sprintf("%02d", 1:3)))
  expect_identical(absent$workers, 4L)             # the ask is recorded too

  # A rig that REFUSES the fan-out at the asked worker count must still be
  # served witnessed -- never through a third party's raw error. The
  # refusal here is the CRAN-era discipline gate itself, the very export
  # the CI workflow carries for FFI contract 6 (_R_CHECK_LIMIT_CORES_):
  # parallel's .check_ncores stops any mclapply ask above two processes.
  # Presence of the symbol is not ability -- the capability probe must
  # consult the fan mechanism itself. (CI run 39171701050 guards arm: the
  # presence-only probe said parallel, mclapply said 4 simultaneous
  # processes spawned, and the farm died quoting.)
  st1 <- new.env(parent = emptyenv()); st1$served <- character(0L)
  refused <- withr::with_envvar(c("_R_CHECK_LIMIT_CORES_" = "true"),
    kp.farm(units = .kpp.farm.units(3L), workers = 4L,
            serve = .kpp.farm.mock.serve(st1)))
  expect_false(isTRUE(refused$parallel), info = refused$witness)
  expect_true(grepl("mclapply", refused$witness, fixed = TRUE),
              info = refused$witness)
  expect_true(grepl("unavailable", refused$witness, fixed = TRUE) ||
              grepl("absent", refused$witness, fixed = TRUE) ||
              grepl("refused", refused$witness, fixed = TRUE),
              info = refused$witness)
  expect_identical(sort(st1$served), paste0("u", sprintf("%02d", 1:3)))
  expect_identical(refused$workers, 4L)            # the ask is recorded too

  # Ambient-rig agreement (census, not counter): on whatever rig runs the
  # suite, the auto-probed farm must AGREE with a live same-shape probe of
  # the fan mechanism -- the parallel route where the pool really can fan
  # out at the asked count, the witnessed fallback where it really
  # cannot. No in-process counter may be consulted: a fork's bookkeeping
  # lives and dies in the fork -- exactly the census-not-counter lesson
  # the whole orphan law rests on. On both routes every unit is served and
  # the returned bytes are the proof.
  live <- tryCatch(
    identical(parallel::mclapply(seq_len(1L), function(i) i,
                                 mc.cores = 4L), list(1L)),
    error = function(e) FALSE, warning = function(w) FALSE)
  st2 <- new.env(parent = emptyenv()); st2$served <- character(0L)
  real <- kp.farm(units = .kpp.farm.units(3L), workers = 4L,
                  serve = .kpp.farm.mock.serve(st2))
  expect_identical(isTRUE(real$parallel), live, info = real$witness)
  expect_true(grepl("mclapply", real$witness, fixed = TRUE),
              info = real$witness)
  if (live) {
    expect_true(grepl("parallel", real$witness, fixed = TRUE),
                info = real$witness)
  }
  expect_identical(names(real$results), paste0("u", sprintf("%02d", 1:3)))
  # On the parallel route the farm FORKS: a fork's served-writes live and
  # die in the fork, so the in-process counter is void evidence there and
  # the returned bytes below are the proof. On the witnessed fallback the
  # in-process route must record every unit.
  if (!live) {
    expect_identical(sort(st2$served), paste0("u", sprintf("%02d", 1:3)))
  }
  for (nm in names(real$results)) {
    expect_identical(real$results[[nm]]$tag, nm)
    expect_identical(real$results[[nm]]$value, nchar(nm) + 1L)
  }
})
