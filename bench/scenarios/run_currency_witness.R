# run_currency_witness.R -- the CS-9 currency-witness scenario (pillar 3).
#
# Mandate: plant a nine-release synthetic capture (label band 9.x/2.x per
# the .CC_FIXTURE_RELEASES precedent -- no real roster label collides; the
# D3 law admits governance labels and shape facts only, never COSMIC
# numeric matrices) and adjudicate the EXPORTED catalog-currency family
# -- ms_catalog_currency_update(source = , offline = TRUE) as the injected
# capture deriver and ms_catalog_currency() as the offline verdict engine
# -- under five arms: clean, drift (the synthetic bytes against the SHIPPED
# committed sidecar), artefakt (one committed byte flipped in a cached
# source document), degenerate (an absent cache), and two ladders: the
# precedence ladder (defects accumulating -- zeroed sidecar digests, then
# a byte flip, then governed-manifest findings) and the version ladder
# (injected latest labels around the pinned 3.6). Every arm is driven
# through the EXPORTED faces alone. The whole scenario is RNG-free and
# network-free: the injected-source update leg never attempts a download,
# and the harvest sampling leg is not on the executed path.
#
# Framing law: DECISION RECORD only. What this scenario records is the
# shipped face's documented adjudicative behavior on planted truth: the
# five verdicts, the precedence order, the doc-state law, the MEASURED
# version_key collision law (3.6 == 3.6.0 reads "current"), and the
# committed last_current/first_behind rungs -- an OBSERVED, COMMITTED
# fact, never a calibration or a coverage claim. The shipped sidecar
# digests are the live provenance (re-read from ms_catalog_registry()),
# and the capture bytes re-hash through BOTH governed SHA-256 kernels --
# the canonical pure-R one and the digest accelerator -- so a silent
# byte-rot reddens the run. The witness bytes under out/ are the verdict;
# a byte-rerun must reproduce them identically.

.script_dir <- local({
  a <- grep("^--file=(.*)$", commandArgs(FALSE), perl = TRUE, value = TRUE)
  if (length(a) == 0L) return(getwd())
  f <- sub("^--file=", "", a[1L])
  if (!grepl("/", f, fixed = TRUE)) return(getwd())
  dirname(f)
})
ROOT <- normalizePath(file.path(.script_dir, "..", ".."), mustWork = TRUE)
OUT <- file.path(ROOT, "bench", "scenarios", "out")

if (requireNamespace("pkgload", quietly = TRUE) &&
    file.exists(file.path(ROOT, "DESCRIPTION"))) {
  suppressWarnings(suppressMessages(
    pkgload::load_all(ROOT, quiet = TRUE, export_all = TRUE)))
} else {
  library(msuiter)
}

# The offline legs parse the planted JSON documents with jsonlite. It is a
# Suggests hard gate for this scenario: absence is an OVERALL FAIL spoken
# here, never a silent skip (the vacuous-green ban).
if (!requireNamespace("jsonlite", quietly = TRUE)) {
  cat("== cs9 currency-witness scenario: OVERALL FAIL == (jsonlite absent)\n")
  quit(save = "no", status = 1L)
}

# -- frozen scenario constants (mirrored byte-identically in the law test) --
ROSTER <- c("3.6", paste0("2.", 9L:2L))              # head == pinned => clean
LAD <- c("3.4", "3.5", "3.6", "3.6.0", "3.6.1", "3.7")
PINNED <- "3.6"
REFDB <- "v3.6"
CELL <- c("COSMIC_v9.9_SBS_GRCh37.txt", "COSMIC_v9.9_SBS_GRCh38.txt",
          "COSMIC_v9.9_DBS_GRCh37.txt", "COSMIC_v9.9_DBS_GRCh38.txt")
COUNTS <- c(1L, 3L, 2L, 3L)
REF_BYTES <- 193L                                     # MEASURED text bytes
AVAIL_BYTES <- 3306L                                  # MEASURED text bytes
WROTE_FILES <- 4L
FLIP_OFFSET <- 0L                                     # zero-based byte offset
FLIP_BEFORE <- 123L                                   # '{'
FLIP_AFTER <- 122L                                    # 'z'
INJ_VERSION <- "v9.9-inj"
INJ_ROSTER_NAME <- "INJECTED_EXTRA.txt"
INJ_REPO <- "GhostRepo/Ghost"
# MEASURED digests (probe v3 over the real exported faces; never derived).
HEX_REF <- "637b85cd10ed96353285515f614f238538c4e07a4e5ffb7c9844690227703784"
HEX_AVAIL <- "d98a6973e8605c356c1bccad92caefb0bfd5199d9c7dd655415033dcc08f4522"
HEX_SHIPPED_REF <- "0a62d225f595e2151ca08711175ab6c0e700b9abdeb6372392c885eb06d3377b"
HEX_SHIPPED_AVAIL <- "62fb3ce39f0d3615eece126494f280e2d17f7ac6328c53af1e7be0fad465534f"
HEX_FLIPPED <- "956a0a78e479aaf887ed4c647739e241a326304b92891f580c86225f6ace5187"
PREC_VERDICTS <- c("ok", "drift", "corrupt", "inconsistent", "inconsistent")
PREC_FINDINGS <- c(0L, 0L, 0L, 1L, 4L)
PREC_VS <- c("current", "current", "unknown", "current", "unknown")
VER_STATES <- c("ahead", "ahead", "current", "current", "behind", "behind")
VER_VERDICTS <- c("ok", "ok", "ok", "ok", "behind", "behind")

verdict <- new.env(parent = emptyenv())
verdict$fail <- 0L
.check <- function(label, ok) {
  cat(if (isTRUE(ok)) "  ok   " else "  FAIL ")
  cat(label, "\n")
  if (!isTRUE(ok)) verdict$fail <- verdict$fail + 1L
  invisible(isTRUE(ok))
}

# Byte-truth reader for this base: readBin WITHOUT the element-count third
# argument silently returns ONE byte (MEASURED 2026-11-21) -- every file
# read here passes file.info()$size explicitly.
.read_bytes <- function(path) {
  size <- file.info(path)$size
  stopifnot(!is.na(size))
  raw <- readBin(path, "raw", size)
  stopifnot(length(raw) == size)
  raw
}

ref_txt <- function(roster) {
  paste0("{\"releases\":{\"human_cancer\":[",
         paste0(paste0("{\"version\":\"", roster, "\"}"), collapse = ","),
         "]}}")
}
avail_txt <- function(labels) {
  cell <- paste0(paste0("\"", CELL, "\":{\"profile_count\":",
                        as.character(COUNTS), "}"), collapse = ", ")
  paste0("{\"human_cancer\":{",
         paste0(paste0("\"", labels, "\":{\"SBS-96\":{", cell, "}}"),
                collapse = ", "), "}}")
}
lay_capture <- function(dir, roster, labels) {
  dir.create(dir, recursive = TRUE)
  src <- file.path(dir, "sources")
  dir.create(src)
  writeLines(ref_txt(roster), file.path(src, "reference_data.json"),
             useBytes = FALSE)
  writeLines(avail_txt(labels), file.path(src, "availability_data.json"),
             useBytes = FALSE)
  src
}
doc_states <- function(rep) {
  if (!isTRUE(rep$cache$present)) return(character())
  unname(vapply(rep$cache$docs, function(d) d$state, character(1L)))
}
is_trusted <- function(rep) {
  st <- doc_states(rep)
  isTRUE(rep$cache$present) && length(st) > 0L &&
    all(st %in% c("ok", "drift"))
}
flip_reference <- function(cache_dir) {
  p <- file.path(cache_dir, "sources", "reference_data.json")
  raw <- .read_bytes(p)
  before <- as.integer(raw[[1L]])
  raw[[1L]] <- as.raw(FLIP_AFTER)
  writeBin(raw, p, useBytes = FALSE)
  stopifnot(file.info(p)$size == length(raw))
  c(before = before, after = FLIP_AFTER)
}

WORK <- tempfile("cs9-witness-")
dir.create(WORK, recursive = TRUE)

# ---------------------------------------------------------------------------
# 1. the shipped provenance rails (live committed sidecar, never re-typed)
# ---------------------------------------------------------------------------
cat("== cs9 currency-witness: shipped provenance ==\n")
reg <- ms_catalog_registry()
docs <- reg$official$documents
.check("shipped sidecar pins the reference document digest",
       identical(docs$reference_data$sha256, HEX_SHIPPED_REF))
.check("shipped sidecar pins the availability document digest",
       identical(docs$availability_data$sha256, HEX_SHIPPED_AVAIL))
.man <- ms_refdb_manifest()
.check("the governed manifest carries the pinned version",
       identical(.man$version, REFDB))

# ---------------------------------------------------------------------------
# 2. the planted capture and the four single-cache arms
# ---------------------------------------------------------------------------
cat("== cs9 currency-witness: planted capture and arms ==\n")
cap_bytes <- c(ref = nchar(ref_txt(ROSTER)),
               avail = nchar(avail_txt(c(ROSTER, LAD))))
.check("capture bytes match the committed sizes",
       identical(as.integer(cap_bytes[["ref"]]), REF_BYTES) &&
         identical(as.integer(cap_bytes[["avail"]]), AVAIL_BYTES))

src <- lay_capture(file.path(WORK, "cap"), ROSTER, c(ROSTER, LAD))
cache <- file.path(WORK, "cache"); dir.create(cache)
upd <- ms_catalog_currency_update(source = src, cache = cache, offline = TRUE)
.check("the injected update leg wrote the four capture files",
       identical(as.integer(length(upd$update$wrote)), WROTE_FILES))
cand <- upd$update$candidate

arm_clean <- ms_catalog_currency(cache = cache, registry = cand)
.check("clean arm: verdict ok", identical(arm_clean$verdict, "ok"))
.check("clean arm: version_state current at the pinned label",
       identical(arm_clean$version_state, "current") &&
         identical(arm_clean$latest$release, PINNED))
.check("clean arm: both documents speak ok",
       identical(doc_states(arm_clean), c("ok", "ok")))
.check("clean arm: the hex triads close (cached == record == expected)",
       all(vapply(arm_clean$cache$docs, function(d)
         identical(d$cached, d$record_sha) && identical(d$cached, d$expected),
         logical(1L))) &&
         identical(unname(arm_clean$cache$docs$reference_data$cached), HEX_REF) &&
         identical(unname(arm_clean$cache$docs$availability_data$cached), HEX_AVAIL))
.check("clean arm: no governed findings, cache trusted",
       identical(length(arm_clean$pinned$refdb_findings), 0L) &&
         identical(is_trusted(arm_clean), TRUE))

arm_drift <- ms_catalog_currency(cache = cache, registry = NULL)
.check("drift arm: the shipped sidecar vs the synthetic bytes speak drift",
       identical(arm_drift$verdict, "drift") &&
         identical(doc_states(arm_drift), c("drift", "drift")))
.check("drift arm: drift still keeps the cache trusted",
       identical(is_trusted(arm_drift), TRUE))
.check("drift arm: the expectations are the shipped digests, not the capture",
       identical(unname(arm_drift$cache$docs$reference_data$expected),
                 HEX_SHIPPED_REF) &&
         identical(unname(arm_drift$cache$docs$availability_data$expected),
                   HEX_SHIPPED_AVAIL) &&
         identical(unname(arm_drift$cache$docs$reference_data$cached), HEX_REF))

cache3 <- file.path(WORK, "cache3"); dir.create(cache3)
invisible(ms_catalog_currency_update(source = src, cache = cache3,
                                      offline = TRUE))
fp <- flip_reference(cache3)
.check("artefakt arm: the committed byte flip is the one recorded",
       identical(fp[["before"]], FLIP_BEFORE) &&
         identical(fp[["after"]], FLIP_AFTER))
arm_art <- ms_catalog_currency(cache = cache3, registry = cand)
.check("artefakt arm: one flipped byte speaks corrupt",
       identical(arm_art$verdict, "corrupt"))
.check("artefakt arm: corruption poisons the version channels",
       identical(arm_art$version_state, "unknown") &&
         identical(arm_art$latest$status, "unmeasured") &&
         identical(arm_art$available$status, "unmeasured"))
.check("artefakt arm: the observed digest is the committed flipped hash",
       identical(unname(arm_art$cache$docs$reference_data$cached), HEX_FLIPPED) &&
         identical(arm_art$cache$docs$reference_data$record_sha, HEX_REF))

arm_deg <- ms_catalog_currency(cache = file.path(WORK, "never-written"),
                               registry = cand)
deg_error <- FALSE
deg_hint <- FALSE
.check("degenerate arm: an absent cache speaks no-cache, never an error",
       identical(arm_deg$verdict, "no-cache") &&
         identical(arm_deg$cache$present, FALSE) &&
         identical(is_trusted(arm_deg), FALSE))
deg_hint <- any(grepl("update", arm_deg$hints))
.check("degenerate arm: the hint names the update face (actionable)", deg_hint)

# ---------------------------------------------------------------------------
# 3. the precedence ladder (defects accumulate)
# ---------------------------------------------------------------------------
cat("== cs9 currency-witness: precedence ladder ==\n")
mk_man <- function(which) {
  m <- .man
  if (which >= 1L) m$version <- INJ_VERSION
  if (which >= 2L) names(m$files)[1L] <- INJ_ROSTER_NAME
  if (which >= 3L) {
    c40 <- paste0(rep_len("a", 40L), collapse = "")
    substr(c40, 40L, 40L) <- "f"
    m$upstream$commit <- c40
  }
  if (which >= 4L) m$upstream$repo <- INJ_REPO
  m
}
tw <- readRDS(cand)
for (k in names(tw$official$documents)) {
  tw$official$documents[[k]]$sha256 <- strrep("0", 64L)
}
twin_zeroed <- file.path(WORK, "twin_zeroed.rds")
saveRDS(tw, twin_zeroed, version = 2L)
cache5 <- file.path(WORK, "cache5"); dir.create(cache5)
invisible(ms_catalog_currency_update(source = src, cache = cache5,
                                      offline = TRUE))
invisible(flip_reference(cache5))
rungs <- list(
  list(defect = "none",                  reg = cand,        man = NULL,
       cache = cache),
  list(defect = "zeroed-sidecar-digests", reg = twin_zeroed,  man = NULL,
       cache = cache),
  list(defect = "plus-artefakt-byte-flip", reg = cand,        man = NULL,
       cache = cache3),
  list(defect = "plus-manifest-findings-1", reg = cand,        man = mk_man(1L),
       cache = cache),
  list(defect = "all-defects",            reg = twin_zeroed,  man = mk_man(4L),
       cache = cache3))
prec <- data.frame()
for (i in seq_along(rungs)) {
  r <- rungs[[i]]
  rep <- ms_catalog_currency(cache = r$cache, registry = r$reg,
                             refdb_manifest = r$man)
  prec <- rbind(prec, data.frame(
    rung = i, defect = r$defect, verdict = rep$verdict,
    findings_n = length(rep$pinned$refdb_findings),
    version_state = rep$version_state, stringsAsFactors = FALSE))
}
.check("precedence ladder: the committed verdict vector",
       identical(as.character(prec$verdict), PREC_VERDICTS))
.check("precedence ladder: findings grow monotonically 0 -> 4",
       identical(as.integer(prec$findings_n), PREC_FINDINGS) &&
         all(diff(as.integer(prec$findings_n)) >= 0L))
.check("precedence ladder: the artefakt rungs read version unknown",
       identical(as.character(prec$version_state), PREC_VS))
.check("precedence law: findings outrank digests (rung 4/5 inconsistent)",
       identical(prec$verdict[[4L]], "inconsistent") &&
         identical(prec$verdict[[5L]], "inconsistent"))

# The injected-manifest seam must not contaminate the governed default:
# after every injected rung, the plain face re-reads the governed manifest.
arm_recheck <- ms_catalog_currency(cache = cache, registry = cand)
memo_clean <- identical(arm_recheck$verdict, "ok") &&
  identical(length(arm_recheck$pinned$refdb_findings), 0L)
.check("the injected-manifest arms leave the governed default uncontaminated",
       memo_clean)

# ---------------------------------------------------------------------------
# 4. the version ladder (the measured key-collision law)
# ---------------------------------------------------------------------------
cat("== cs9 currency-witness: version ladder ==\n")
lad_rows <- data.frame()
for (i in seq_along(LAD)) {
  lab <- LAD[[i]]
  tv <- file.path(WORK, paste0("vl", i))
  dir.create(tv, recursive = TRUE)
  writeLines(ref_txt(c(lab, "1.0")), file.path(tv, "reference_data.json"),
             useBytes = FALSE)
  file.copy(file.path(src, "availability_data.json"),
            file.path(tv, "availability_data.json"), overwrite = TRUE)
  cv <- file.path(WORK, paste0("vlc", i)); dir.create(cv)
  ru <- ms_catalog_currency_update(source = tv, cache = cv, offline = TRUE)
  rv <- ms_catalog_currency(cache = cv, registry = ru$update$candidate)
  lad_rows <- rbind(lad_rows, data.frame(
    label = lab, version_state = rv$version_state, verdict = rv$verdict,
    stringsAsFactors = FALSE))
}
.check("version ladder: the committed state vector",
       identical(as.character(lad_rows$version_state), VER_STATES))
.check("version ladder: the committed verdict vector",
       identical(as.character(lad_rows$verdict), VER_VERDICTS))
.check("MEASURED law: 3.6 and 3.6.0 share the version_key (current)",
       identical(lad_rows$version_state[[4L]], "current"))
.last_cur <- which(lad_rows$version_state == "current")
.check("committed rungs: last_current 3.6.0, first_behind 3.6.1",
       identical(as.integer(max(.last_cur)), 4L) &&
         identical(lad_rows$label[[4L]], "3.6.0") &&
         identical(lad_rows$label[[5L]], "3.6.1"))

# ---------------------------------------------------------------------------
# 5. the dual-kernel digest identity (governed-infrastructure rail)
# ---------------------------------------------------------------------------
cat("== cs9 currency-witness: dual-kernel digest identity ==\n")
p_ref <- file.path(src, "reference_data.json")
bytes <- .read_bytes(p_ref)
h_canonical <- .ms_fit_sha256(bytes)
h_face <- .ms_cc_sha256_file(p_ref)
have_accel <- requireNamespace("digest", quietly = TRUE)
h_accel <- if (have_accel) {
  asNamespace("digest")$digest(bytes, algo = "sha256", serialize = FALSE)
} else {
  NA_character_
}
.check("canonical pure-R kernel reproduces the committed capture digest",
       identical(h_canonical, HEX_REF))
.check("the governed file hasher agrees byte-for-byte",
       identical(h_face, HEX_REF))
.check("the digest accelerator (where installed) agrees",
       !have_accel || identical(h_accel, HEX_REF))
kernels_equal <- identical(h_canonical, h_face) &&
  (!have_accel || identical(h_accel, h_canonical))
.check("all SHA-256 kernels speak one hash", kernels_equal)

# ---------------------------------------------------------------------------
# [attest] -- declined scope rails, made audible
# ---------------------------------------------------------------------------
cat("[attest] DECISION RECORD only: the face's behavior on planted truth is\n")
cat("[attest]   an OBSERVED, COMMITTED record -- no calibration, no coverage claim.\n")
cat("[attest] NETWORK: never attempted -- the injected-source update leg is\n")
cat("[attest]   offline by construction; no download face, no live registry is touched.\n")
cat("[attest] D3 law: synthetic 9.x/2.x capture labels only (the\n")
cat("[attest]   .CC_FIXTURE_RELEASES precedent); zero COSMIC numeric matrices\n")
cat("[attest]   anywhere -- profile_count cells are shape facts from {1,2,3}.\n")
cat("[attest] RNG-free executed path: no seed to pin, no draw to re-roll.\n")
cat("[attest] no estimation machinery: no bootstrap, no intervals,\n")
cat("[attest]   no conformal framing (paper declined-word), no new faces.\n")
cat("[attest] verdict arms speak through the exported faces only; the\n")
cat("[attest]   dual-kernel rail reaches the two governed SHA-256 kernels by\n")
cat("[attest]   name -- infrastructure equality, adjudication-independent.\n")

# ---------------------------------------------------------------------------
# 6. the committed witnesses (finiteness censused here, pre-write)
# ---------------------------------------------------------------------------
arm_rows <- data.frame(
  arm = c("clean", "drift", "artefakt", "degenerate"),
  verdict = c(arm_clean$verdict, arm_drift$verdict, arm_art$verdict,
              arm_deg$verdict),
  version_state = c(arm_clean$version_state, arm_drift$version_state,
                     arm_art$version_state, arm_deg$version_state),
  latest_status = c(arm_clean$latest$status, arm_drift$latest$status,
                     arm_art$latest$status, arm_deg$latest$status),
  latest_release = c(arm_clean$latest$release, arm_drift$latest$release,
                     NA_character_, NA_character_),
  available_status = c(arm_clean$available$status, arm_drift$available$status,
                        arm_art$available$status, arm_deg$available$status),
  docs_states = c(paste0(doc_states(arm_clean), collapse = ","),
                  paste0(doc_states(arm_drift), collapse = ","),
                  paste0(doc_states(arm_art), collapse = ","),
                  paste0(doc_states(arm_deg), collapse = ",")),
  findings_n = c(length(arm_clean$pinned$refdb_findings),
                 length(arm_drift$pinned$refdb_findings),
                 length(arm_art$pinned$refdb_findings),
                 length(arm_deg$pinned$refdb_findings)),
  present = as.integer(c(isTRUE(arm_clean$cache$present),
                         isTRUE(arm_drift$cache$present),
                         isTRUE(arm_art$cache$present),
                         isTRUE(arm_deg$cache$present))),
  trusted = c(as.integer(is_trusted(arm_clean)),
              as.integer(is_trusted(arm_drift)),
              as.integer(is_trusted(arm_art)),
              as.integer(is_trusted(arm_deg))),
  stringsAsFactors = FALSE)

hex_row <- function(arm, doc, d) {
  data.frame(arm = arm, doc = doc, expected = d$expected, cached = d$cached,
             record_sha = d$record_sha,
             rails_ok = as.integer(identical(d$cached, d$expected) &&
                                    identical(d$cached, d$record_sha)),
             stringsAsFactors = FALSE)
}
hex_rows <- rbind(
  hex_row("clean", "reference_data", arm_clean$cache$docs$reference_data),
  hex_row("clean", "availability_data", arm_clean$cache$docs$availability_data),
  hex_row("drift", "reference_data", arm_drift$cache$docs$reference_data),
  hex_row("drift", "availability_data", arm_drift$cache$docs$availability_data),
  hex_row("artefakt", "reference_data", arm_art$cache$docs$reference_data))

degens <- data.frame(
  check = c("no_cache_no_error", "no_cache_hint_names_update",
            "artefakt_flip_offset", "artefakt_flip_before", "artefakt_flip_after",
            "kernels_all_equal", "memo_noncontamination", "clean_rails_closed",
            "drift_is_not_clean", "sidecar_expected_differs"),
  value = c(1L, as.integer(deg_hint), as.integer(FLIP_OFFSET),
            as.integer(fp[["before"]]), as.integer(fp[["after"]]),
            as.integer(kernels_equal), as.integer(memo_clean),
            as.integer(all(vapply(arm_clean$cache$docs, function(d)
              identical(d$cached, d$expected), logical(1L)))),
            as.integer(!identical(arm_drift$verdict, arm_clean$verdict)),
            as.integer(!identical(arm_drift$cache$docs$reference_data$expected,
                                  HEX_REF))),
  stringsAsFactors = FALSE)

scalars <- data.frame(
  roster = paste0(ROSTER, collapse = ","),
  version_ladder = paste0(LAD, collapse = ","),
  pinned_version = PINNED, refdb_version = REFDB,
  build_files = paste0(CELL, collapse = ","),
  profile_counts = paste0(as.character(COUNTS), collapse = ","),
  flip_offset = FLIP_OFFSET, flip_before = FLIP_BEFORE, flip_after = FLIP_AFTER,
  hex_reference = HEX_REF, hex_availability = HEX_AVAIL,
  hex_shipped_reference = HEX_SHIPPED_REF,
  hex_shipped_availability = HEX_SHIPPED_AVAIL,
  hex_flipped_reference = HEX_FLIPPED,
  ref_bytes = REF_BYTES, avail_bytes = AVAIL_BYTES, wrote_files = WROTE_FILES,
  last_current_rung = 4L, last_current_label = "3.6.0",
  first_behind_label = "3.6.1",
  stringsAsFactors = FALSE)

# The finiteness census: refuse to commit a witness with a dead column
# (the witness-finiteness law -- a column that never fires is not evidence).
.hexes_ok <- function(x) {
  length(x) == 1L && is.character(x) && nchar(x) == 64L &&
    length(grep("^[0-9a-f]{64}$", x, perl = TRUE)) == 1L
}
ok_payload <-
  identical(arm_rows$arm, c("clean", "drift", "artefakt", "degenerate")) &&
  all(arm_rows$verdict %in% c("ok", "behind", "drift", "corrupt",
                              "no-cache", "inconsistent")) &&
  all(arm_rows$version_state %in% c("current", "behind", "ahead", "unknown")) &&
  all(arm_rows$latest_status %in% c("measured", "unmeasured")) &&
  all(arm_rows$available_status %in% c("measured", "unmeasured")) &&
  all(arm_rows$present %in% 0:1) && all(arm_rows$trusted %in% 0:1) &&
  all(as.integer(arm_rows$findings_n) >= 0L) &&
  all(vapply(c("expected", "cached", "record_sha"), function(k)
    all(vapply(as.character(hex_rows[[k]]), .hexes_ok, logical(1L))),
    logical(1L))) &&
  all(hex_rows$rails_ok %in% 0:1) &&
  all(prec$verdict %in% c("ok", "drift", "corrupt", "inconsistent")) &&
  all(as.integer(prec$findings_n) %in% 0:4) &&
  all(lad_rows$version_state %in% c("current", "behind", "ahead")) &&
  all(lad_rows$verdict %in% c("ok", "behind")) &&
  all(is.finite(as.numeric(degens$value)) & as.numeric(degens$value) >= 0) &&
  all(degens$check %in% c("no_cache_no_error", "no_cache_hint_names_update",
                          "artefakt_flip_offset", "artefakt_flip_before",
                          "artefakt_flip_after", "kernels_all_equal",
                          "memo_noncontamination", "clean_rails_closed",
                          "drift_is_not_clean", "sidecar_expected_differs")) &&
  isTRUE(nchar(scalars$hex_reference) == 64L)
if (!ok_payload) {
  cat("  FAIL witness payload census (refusing to commit an unlive column)\n")
  verdict$fail <- verdict$fail + 1L
}

dir.create(OUT, showWarnings = FALSE)
write.csv(arm_rows, file.path(OUT, "cs9_arms.csv"), row.names = FALSE)
write.csv(hex_rows, file.path(OUT, "cs9_hexes.csv"), row.names = FALSE)
write.csv(prec, file.path(OUT, "cs9_precedence.csv"), row.names = FALSE)
write.csv(lad_rows, file.path(OUT, "cs9_version_ladder.csv"), row.names = FALSE)
write.table(degens, file.path(OUT, "cs9_degenerates.tsv"), sep = "\t",
            quote = FALSE, row.names = FALSE, col.names = TRUE)
write.csv(scalars, file.path(OUT, "cs9_scalars.csv"), row.names = FALSE)

cat("== cs9 currency-witness scenario: ",
    if (identical(verdict$fail, 0L)) "OVERALL PASS" else "OVERALL FAIL",
    " == (evidence: ", OUT, ")\n", sep = "")
quit(save = "no", status = if (identical(verdict$fail, 0L)) 0L else 1L)
