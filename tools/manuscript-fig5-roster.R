#!/usr/bin/env Rscript
# manuscript-fig5-roster: the section-8 Fig. 5 panel roster must equal the
#     section-3.4 witness bullet roster (paper/paper-draft.qmd).
#
# Contract. Section 8's figure manifest enumerates Fig. 5's scenario
# adjudication panels in one `(CS-1 ..., CS-N ...)` parenthetical; section 3.4
# narrates the same panels as `- **CS-N <label>**` bullet heads, each citing
# its bench/scenarios/run_<x>.R witness. One list rendered twice, so the two
# must agree in identity and order, and every section-3.4 script citation must
# name a committed file. The CS-17-era Fig. 5 row fell three lanes behind the
# prose (CS-18/CS-19/CS-20 narrated but unpinned) and nothing read it; this
# script is that reader. Drift exits 1.
#
# Run:  Rscript tools/manuscript-fig5-roster.R   (exit 0 = in step, exit 1 = drift)
#       --manuscript= retargets the read at an alternate .qmd (red-state units
#       in tests/testthat/test-manuscript-fig5-roster.R).

options(warn = 1)

.repo_root <- local({
  a <- commandArgs(FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f) > 0L) dirname(dirname(normalizePath(f[1]))) else normalizePath(".")
})

# `--<key>=<value>` retargets a half at an alternate file, so the red-state
# units can point the checker at a tampered copy without touching committed
# bytes. The script rides the --file= element of this base's full R invocation
# vector (cf. tools/docs-sync.R).
.arg_of <- function(key, default) {
  a <- commandArgs(FALSE)
  hit <- grep(paste0("^--", key, "="), a)
  if (length(hit) == 0L) default else sub(paste0("^--", key, "="), "", a[hit[1]])
}

.md <- function(...) file.path(.repo_root, "paper", ...)

# Structural defects (missing artifact, unparsable row) are producer errors:
# exit 2 so they never read as the drift verdict they are not.
.die <- function(...) {
  cat("manuscript-fig5-roster: ", ..., "\n", sep = "", file = stderr())
  quit(status = 2L)
}

.MIN_PANELS <- 2L

# The manifest row's content cell carries exactly one parenthesized region --
# the panel list. Locate it by its CS-1 head, never by position, so a reflowed
# row still parses or dies loudly. Fig. 5 labels carry no commas, so the
# clause delimiter is unambiguous.
.fig5_clauses <- function(row) {
  m <- regmatches(row, gregexec("\\(([^()]*)\\)", row, perl = TRUE))[[1]]
  if (!length(m)) .die("the Fig. 5 row carries no parenthesized panel list")
  segs <- m[seq(2L, length(m))]
  seg <- segs[grep("CS-1\\b", segs)][1L]
  if (is.na(seg)) .die("the Fig. 5 panel list does not open with CS-1")
  parts <- strsplit(seg, ",\\s*(?=CS-[0-9]+\\s)", perl = TRUE)[[1]]
  id <- sub("^\\s*(CS-[0-9]+)\\s.*$", "\\1", parts)
  label <- trimws(sub("^\\s*CS-[0-9]+\\s+", "", parts))
  ok <- grepl("^CS-[0-9]+$", id) & nzchar(label)
  if (any(!ok)) .die("unparsable Fig. 5 clause(s): ", paste(parts[!ok], collapse = " | "))
  list(id = id, label = label)
}

.bullet_roster <- function(lines) {
  i <- grep("^- \\*\\*CS-[0-9]+ ", lines)
  if (!length(i)) .die("no section-3.4 `- **CS-N ...` bullet heads found")
  bl <- lines[i]
  id <- sub("^- \\*\\*(CS-[0-9]+) .*$", "\\1", bl)
  label <- sub("^- \\*\\*CS-[0-9]+ (.*?)\\*\\*.*$", "\\1", bl)
  script <- vapply(bl, function(x) {
    h <- regmatches(x, regexpr("bench/scenarios/run_[A-Za-z0-9_]+\\.R", x))
    if (length(h)) h else NA_character_
  }, character(1L), USE.NAMES = FALSE)
  list(line = i, id = id, label = label, script = script)
}

manuscript <- .arg_of("manuscript", .md("paper-draft.qmd"))
if (!file.exists(manuscript)) .die("manuscript not found: ", manuscript)
lines <- readLines(manuscript, warn = FALSE)

fig_row <- grep("^\\|\\s*Fig\\.\\s*5\\s*\\|", lines)
if (length(fig_row) != 1L) {
  .die("expected exactly one `| Fig. 5 |` manifest row, found ", length(fig_row))
}
fig <- .fig5_clauses(lines[fig_row])
bul <- .bullet_roster(lines)

# Vacuous-green guard: both parses must be real lists before any comparison.
# The CS-1 anchor keeps a silent regex death from reading as agreement.
if (length(fig$id) < .MIN_PANELS || length(bul$id) < .MIN_PANELS) {
  .die("vacuous roster (fig5=", length(fig$id), " bullets=", length(bul$id), ")")
}
if (!("CS-1" %in% bul$id)) .die("section-3.4 roster does not open at CS-1")

cat(sprintf("manuscript-fig5-roster: fig5-panels: %d\n", length(fig$id)))
cat(sprintf("manuscript-fig5-roster: section-3.4-bullets: %d\n", length(bul$id)))

missing <- setdiff(bul$id, fig$id)
extra <- setdiff(fig$id, bul$id)
if (length(missing) || length(extra) || !identical(fig$id, bul$id)) {
  cat("manuscript-fig5-roster: DRIFT -- the section-8 Fig. 5 panel roster and",
      "the section-3.4 witness bullets disagree:\n")
  if (length(missing)) {
    cat("  missing from the Fig. 5 row: ", paste(missing, collapse = ", "), "\n", sep = "")
  }
  if (length(extra)) {
    cat("  in the Fig. 5 row but not narrated in section 3.4: ",
        paste(extra, collapse = ", "), "\n", sep = "")
  }
  if (!length(missing) && !length(extra)) {
    cat("  same panels, different order: fig5=", paste(fig$id, collapse = " "),
        " bullets=", paste(bul$id, collapse = " "), "\n", sep = "")
  }
  cat("manuscript-fig5-roster: extend the Fig. 5 row with the narrated lanes",
      "(or fix section 3.4). Exiting 1.\n")
  quit(status = 1L)
}

uncited <- bul$id[is.na(bul$script)]
if (length(uncited)) {
  cat("manuscript-fig5-roster: DRIFT -- section-3.4 bullet(s) cite no run script: ",
      paste(uncited, collapse = ", "), "\n", sep = "")
  quit(status = 1L)
}
absent <- bul$script[!file.exists(file.path(.repo_root, bul$script))]
if (length(absent)) {
  cat("manuscript-fig5-roster: DRIFT -- section-3.4 cites uncommitted witness script(s): ",
      paste(absent, collapse = ", "), "\n", sep = "")
  quit(status = 1L)
}
cat(sprintf("manuscript-fig5-roster: script-truth: %d cited run_*.R present\n",
            length(bul$script)))
cat(sprintf(paste0("manuscript-fig5-roster: OK -- the Fig. 5 panel roster equals",
                   " the section-3.4 witness roster (%d panels, %d committed scripts)\n"),
            length(fig$id), length(bul$script)))
quit(status = 0L)
