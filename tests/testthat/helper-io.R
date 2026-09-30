# Shared io-layer fixtures for the segment/SV input units
# (test-io-segments.R, test-io-sv.R). All fixtures are written into the
# session temp dir at runtime -- no committed binary fixtures, no
# network. Error assertions reuse expect_ms_error() from
# helper-classes.R.

# Write fixture lines to a temp file, plain or gzip-compressed; returns
# the path (caller unlinks).
.io_write_fixture <- function(lines, ext, gz = FALSE) {
  path <- tempfile(fileext = paste0(ext, if (gz) ".gz" else ""))
  con <- if (gz) gzfile(path, "wt") else file(path, "wt")
  writeLines(lines, con)
  close(con)
  path
}
