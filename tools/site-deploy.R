# site-deploy.R -- DS-2 US-4 dormant deploy guard (docs/site v2).
# Reads the MEASURED GitHub Pages state for the home repository -- from a
# banked JSON (--pages-json, byte-true capture) or live (--live, gh api) --
# and stays a no-op unless Pages is enabled. Activation is a controller
# decision taken separately: this guard never touches repository settings and
# never auto-pushes. The dormant/armed verdicts ride stdout as proof lines.
# usage: Rscript tools/site-deploy.R (--pages-json=<file> | --live)
#        [--bundle-dir=site-bundle]
args <- commandArgs(FALSE)
.has <- function(flag) any(grepl(paste0("^", flag), args))
.get <- function(pref, required = TRUE) {
  hit <- which(grepl(paste0("^", pref), args))
  if (!length(hit)) {
    if (required) stop("missing required argument ", pref, "<value>")
    return("")
  }
  sub(pref, "", args[hit[1L]])
}
REPO <- "WangLabCSU/msuiter"
bundle <- .get("--bundle-dir=", required = FALSE)
if (!nzchar(bundle)) bundle <- "site-bundle"

# The bundle must be complete before any deploy decision is voiced.
for (f in c("manifest.tsv", "PROVENANCE.tsv")) {
  if (!file.exists(file.path(bundle, f))) {
    cat("DEPLOY ABORTED: bundle incomplete -- missing", f, "in", bundle, "\n")
    quit(status = 2L)
  }
}
manifest <- readLines(file.path(bundle, "manifest.tsv"), warn = FALSE)

if (.has("--pages-json=") == .has("--live")) {
  cat("DEPLOY ABORTED: no Pages state supplied (pass exactly one of",
      "--pages-json=<file> or --live)\n")
  quit(status = 2L)
}

if (.has("--pages-json=")) {
  pj <- .get("--pages-json=")
  if (!file.exists(pj)) {
    cat("DEPLOY ABORTED: Pages state file unreadable:", pj, "\n")
    quit(status = 2L)
  }
  body <- paste(readLines(pj, warn = FALSE), collapse = "\n")
  measured <- "banked"
} else {
  r <- suppressWarnings(system2("gh", c("api", paste0("repos/", REPO, "/pages")),
                                stdout = TRUE, stderr = TRUE))
  st <- attr(r, "status")
  if (is.null(st)) st <- 0L
  body <- paste0(as.character(r), collapse = "\n")
  measured <- paste0("live rc=", as.integer(st))
  if (st != 0L && !nzchar(body)) {
    cat("DEPLOY DORMANT: Pages state unmeasured (", measured,
        ") -- staying no-op, no repository settings touched\n", sep = "")
    quit(status = 0L)
  }
}

# enabled classification: an "enabled" field true of its own value, and no
# API error envelope (the not-provisioned answer is a 404 body with message).
# Manual occurrence walk -- this base's fixed-mode grep is untrustworthy
# (measured: reports position 1 for a late literal); strsplit fixed is fine.
.sd_occurrences <- function(text, needle) {
  ch <- strsplit(text, "")[[1L]]
  nc <- strsplit(needle, "")[[1L]]
  n <- length(ch); m <- length(nc)
  out <- integer(0)
  if (m == 0L || n < m) return(out)
  i <- 1L
  while (i + m - 1L <= n) {
    hit <- TRUE
    for (k in seq_len(m)) if (!identical(ch[[i + k - 1L]], nc[[k]])) {
      hit <- FALSE
      break
    }
    if (hit) out <- c(out, i)
    i <- i + 1L
  }
  out
}
.enabled <- FALSE
for (o in .sd_occurrences(body, "\"enabled\"")) {
  tail <- substr(body, o + 9L, min(nchar(body), o + 24L))
  if (grepl("true", tail, fixed = TRUE)) .enabled <- TRUE
}
.errorish <- grepl("\"message\"", body, fixed = TRUE) ||
             grepl("Not Found", body, fixed = TRUE)
if (.enabled && !.errorish) {
  cat(paste0("DEPLOY ARMED: Pages enabled (", measured, ") -- publish ",
             "deferred to controller dispatch (no auto-push). Bundle: ",
             bundle, ", files=", length(manifest),
             " -- activation is a separate controller decision."), "\n")
} else {
  cat(paste0("DEPLOY DORMANT: Pages not enabled (", measured,
             ") -- no repository settings touched."), "\n")
}
quit(status = 0L)
