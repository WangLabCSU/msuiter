# site-bundle.R -- DS-2 US-4 deployable site bundle (docs/site v2).
# Emits, from a built pkgdown tree: manifest.tsv (sha256 TAB relpath, sorted,
# byte-reproducible -- no clock rides it) and PROVENANCE.tsv (trunk-sha stamp,
# file count, build clock). An empty tree is vacuous-red, never empty-green.
# usage: Rscript tools/site-bundle.R --site=<built-dir> --out=<dir> [--rev=<sha>]
args <- commandArgs(FALSE)
.get <- function(pref, required = TRUE) {
  hit <- grepl(paste0("^", pref), args)
  if (!any(hit)) {
    if (required) stop("missing required argument ", pref, "<value>")
    return("")
  }
  sub(pref, "", args[which(hit)[1L]])
}
site <- .get("--site=")
out <- .get("--out=")
rev <- .get("--rev=", required = FALSE)
if (!dir.exists(site)) stop("no such site dir: ", site)
if (!nzchar(rev)) {
  g <- suppressWarnings(system2("git", c("rev-parse", "HEAD"), stdout = TRUE,
                                stderr = FALSE))
  st <- attr(g, "status")
  if (!is.null(st) && st != 0L) {
    stop("no trunk revision: pass --rev=<sha> or run inside the checkout")
  }
  rev <- trimws(paste0(as.character(g), collapse = ""))
}
if (!nzchar(rev) || grepl(" ", rev, fixed = TRUE)) {
  stop("malformed trunk revision stamp")
}
abs_site <- normalizePath(site)
files <- list.files(abs_site, recursive = TRUE, full.names = TRUE)
if (!length(files)) {
  stop("vacuous: zero files under the site tree ", abs_site)
}
rel <- substring(files, nchar(abs_site) + 2L)
if (!requireNamespace("digest", quietly = TRUE)) {
  stop("digest namespace unavailable: manifest hashing is in-process by law")
}
sums <- character(length(files))
for (i in seq_along(files)) {
  sums[i] <- digest::digest(files[i], algo = "sha256", file = TRUE)
}
if (!all(nzchar(sums))) {
  bad <- files[!nzchar(sums)]
  stop("digest/manifest desync: empty hash for ", paste0(bad, collapse = ", "))
}
ord <- order(rel)
dir.create(out, recursive = TRUE, showWarnings = FALSE)
writeLines(paste0(sums[ord], "\t", rel[ord]), file.path(out, "manifest.tsv"))
writeLines(c(paste0("trunk_sha\t", rev),
             paste0("files\t", length(files)),
             paste0("built_utc\t", format(Sys.time(), tz = "UTC"))),
           file.path(out, "PROVENANCE.tsv"))
cat("SITE-BUNDLE OK files=", length(files), " rev=", rev,
    " out=", out, "\n", sep = "")
