# g0-derive-inputs.R: derive the two G0 cosmic-file inputs from the
# bundled COSMIC v3.6 reference (PI adjudication 2026-10-06).
#
# Inputs (in-repo, sha256-pinned, license BSD-2 with provenance in the
# refdb governance chain):
#   inst/reference/refdb/COSMIC_v3.6/COSMIC_v3.6_SBS_GRCh37.txt
#
# Outputs (LOCAL ONLY, bench/g0/cache/ is gitignored -- D3: the files
# never enter version control):
#   bench/g0/cache/g0_signatures.csv   -- 5 x 96 truth matrix
#                                         (SBS1/SBS2/SBS13/SBS5/SBS40)
#   bench/g0/cache/g0_catalog.csv      -- 101-signature fitting catalog
#
# Name mapping (v3.6 split names -> G0 truth slots): SBS17a -> SBS17,
# SBS40a -> SBS40. The catalog keeps ALL its signatures verbatim
# (including 17a/17b/40a/b/c) -- the G0 estimator is intentionally given
# the full dictionary; only the truth slots get the mapping.
#
# Validation: the emitted files are checked against the provider's own
# loader rules (96 channels in canonical order, all 5 truth names
# present, positive channel sums) by the accompanying python check in
# run_grid.py itself.

library(S7)

.out <- function(...) cat(sprintf(...), "\n", sep = "")

root <- function() {
  # Script lives in <root>/tools/: two levels up from its dir. When run
  # via `Rscript tools/g0-derive-inputs.R` from the repo root, --file is
  # relative; normalizePath anchors it.
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", grep("^--file=", a, value = TRUE))
  if (length(f) > 0L) {
    cand <- normalizePath(f, mustWork = FALSE)
    if (file.exists(cand)) {
      # --file path exists relative to cwd: tools/ -> root is ONE level
      dirname(dirname(cand))
    } else {
      dirname(dirname(dirname(cand)))
    }
  } else {
    normalizePath(".")
  }
}
ROOT <- root()

ref_path <- file.path(ROOT, "inst/reference/refdb/COSMIC_v3.6",
                      "COSMIC_v3.6_SBS_GRCh37.txt")
if (!file.exists(ref_path)) {
  stop("bundled COSMIC v3.6 reference not found: ", ref_path)
}

# Read via the package's own import face (label validation reused).
if (requireNamespace("pkgload", quietly = TRUE) &&
    dir.exists(file.path(ROOT, "R"))) {
  pkgload::load_all(ROOT, quiet = TRUE)
} else {
  library(msuiter)
}
sigs <- ms_import(ref_path, format = "cosmic", kind = "signatures")
mat <- sigs@signatures
labels <- rownames(mat)

# ---- truth slots with the recorded name mapping -------------------------
TRUTH_NAMES <- c("SBS1", "SBS2", "SBS13", "SBS5", "SBS40")
MAPPING <- c(SBS17 = "SBS17a", SBS40 = "SBS40a")
colmap <- colnames(mat)
truth_cols <- vapply(TRUTH_NAMES, function(nm) {
  if (nm %in% colmap) return(match(nm, colmap))
  alt <- MAPPING[[nm]]
  if (!is.null(alt) && alt %in% colmap) return(match(alt, colmap))
  stop("truth slot ", nm, " (or mapped ", alt, ") absent from the reference")
}, integer(1))
truth <- mat[, truth_cols, drop = FALSE]
colnames(truth) <- TRUTH_NAMES

# ---- fitting catalog: ALL reference signatures verbatim -----------------

cache <- file.path(ROOT, "bench", "g0", "cache")
dir.create(cache, showWarnings = FALSE, recursive = TRUE)

write_truth <- file.path(cache, "g0_signatures.csv")
con <- file(write_truth, open = "w")
writeLines(paste(c("channel", TRUTH_NAMES), collapse = ","), con)
for (i in seq_len(nrow(truth))) {
  writeLines(paste0(labels[i], ",", paste(sprintf("%.10g", truth[i, ]),
                                          collapse = ",")), con)
}
close(con)

write_catalog <- file.path(cache, "g0_catalog.csv")
con <- file(write_catalog, open = "w")
writeLines(paste(c("channel", colnames(mat)), collapse = ","), con)
for (i in seq_len(nrow(mat))) {
  writeLines(paste0(labels[i], ",", paste(sprintf("%.10g", mat[i, ]),
                                          collapse = ",")), con)
}
close(con)

.out("derived: %s (5 truth slots)", write_truth)
.out("derived: %s (%d-signature catalog)", write_catalog, ncol(mat))
.out("mapping applied: %s", paste(names(MAPPING), MAPPING, sep = "->",
                                 collapse = ", "))
.out("D3 note: both files live in bench/g0/cache (gitignored); never committed.")
