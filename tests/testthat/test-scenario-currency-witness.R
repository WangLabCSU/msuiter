# test-scenario-currency-witness.R -- the CS-9 currency-witness law units
# (pillar 3). The scenario plants a nine-release synthetic capture (9.x/2.x
# label band per the .CC_FIXTURE_RELEASES precedent -- no real roster label
# collides) and adjudicates the EXPORTED catalog-currency family
# ms_catalog_currency()/ms_catalog_currency_update(source=, offline=TRUE)
# under five arms: clean, drift (the synthetic bytes against the SHIPPED
# committed sidecar), artefakt (one committed byte flipped in a cached
# source document), degenerate (an absent cache), and two ladders -- the
# precedence ladder (defects accumulating: zeroed sidecar digests, then a
# byte flip, then governed-manifest findings) and the version ladder
# (injected latest labels around the pinned 3.6). The witness bytes under
# bench/scenarios/out/ are the committed verdict: a drift in the face's
# precedence law, the doc-state law, the version_key collision law, or the
# dual-kernel digest identity reddens here before print. The whole scenario
# is RNG-free and network-free -- the injected-source update leg never
# attempts a download, and there is no seed to pin.
# Framing law: DECISION RECORD only. What the face says on planted truth --
# the five verdicts, the precedence order, the measured key-collision law
# 3.6 == 3.6.0 ("current"), the committed last_current/first_behind rungs --
# is an OBSERVED, COMMITTED record, never a calibration or a coverage claim.
# The shipped sidecar digests are re-read LIVE from ms_catalog_registry()
# (the provenance rail cannot die silently); the capture bytes are
# re-derived byte-exactly from the frozen constants and re-hashed through
# BOTH governed SHA-256 kernels (canonical pure-R and the digest
# accelerator), so a silent byte-rot in what was measured reddens here.
# The pillar-2 idiom of reaching the package namespace directly
# (msuiter:::) is BANNED here and grepped away.

.rs_out9 <- function(fname) {
  file.path(.ms_root, "bench", "scenarios", "out", fname)
}

.rs_csv9 <- function(fname) {
  read.csv(.rs_out9(fname), header = TRUE, stringsAsFactors = FALSE)
}

.rs_tsv9 <- function(fname) {
  read.csv(.rs_out9(fname), header = TRUE, sep = "\t", stringsAsFactors = FALSE)
}

.is_hex64 <- function(x) {
  is.character(x) && length(x) == 1L && nchar(x) == 64L &&
    length(grep("^[0-9a-f]{64}$", x, perl = TRUE)) == 1L
}

.all_hex64 <- function(col) {
  col <- col[!is.na(col)]
  all(vapply(col, .is_hex64, logical(1L)))
}

# Frozen scenario constants -- mirrored byte-identically in
# bench/scenarios/run_currency_witness.R (single source of truth is the
# pair of files; a drift reddens the scalars unit below).
.CS9_ROSTER <- c("3.6", paste0("2.", 9L:2L))
.CS9_LAD <- c("3.4", "3.5", "3.6", "3.6.0", "3.6.1", "3.7")
.CS9_PINNED <- "3.6"
.CS9_REFDB <- "v3.6"
.CS9_CELL <- c("COSMIC_v9.9_SBS_GRCh37.txt", "COSMIC_v9.9_SBS_GRCh38.txt",
               "COSMIC_v9.9_DBS_GRCh37.txt", "COSMIC_v9.9_DBS_GRCh38.txt")
.CS9_COUNTS <- c(1L, 3L, 2L, 3L)
.CS9_FLIP_OFFSET <- 0L
.CS9_FLIP_BEFORE <- 123L
.CS9_FLIP_AFTER <- 122L
# MEASURED digests (probe v3, real exported faces, never hand-derived):
.CS9_HEX_REF <- "637b85cd10ed96353285515f614f238538c4e07a4e5ffb7c9844690227703784"
.CS9_HEX_AVAIL <- "d98a6973e8605c356c1bccad92caefb0bfd5199d9c7dd655415033dcc08f4522"
.CS9_HEX_SHIPPED_REF <- "0a62d225f595e2151ca08711175ab6c0e700b9abdeb6372392c885eb06d3377b"
.CS9_HEX_SHIPPED_AVAIL <- "62fb3ce39f0d3615eece126494f280e2d17f7ac6328c53af1e7be0fad465534f"
.CS9_HEX_FLIPPED <- "956a0a78e479aaf887ed4c647739e241a326304b92891f580c86225f6ace5187"
.CS9_PREC_VERDICTS <- c("ok", "drift", "corrupt", "inconsistent", "inconsistent")
.CS9_PREC_FINDINGS <- c(0L, 0L, 0L, 1L, 4L)
.CS9_PREC_VS <- c("current", "current", "unknown", "current", "unknown")
.CS9_VER_STATES <- c("ahead", "ahead", "current", "current", "behind", "behind")
.CS9_VER_VERDICTS <- c("ok", "ok", "ok", "ok", "behind", "behind")

# Byte-exact re-derivation of the planted capture (the same paste the
# runner lays through writeLines; the file bytes are the text plus the
# writeLines terminator).
.cs9_ref_txt <- function() {
  paste0("{\"releases\":{\"human_cancer\":[",
         paste0(paste0("{\"version\":\"", .CS9_ROSTER, "\"}"),
                collapse = ","), "]}}")
}
.cs9_avail_txt <- function() {
  cell <- paste0(paste0("\"", .CS9_CELL, "\":{\"profile_count\":",
                        as.character(.CS9_COUNTS), "}"), collapse = ", ")
  paste0("{\"human_cancer\":{",
         paste0(paste0("\"", c(.CS9_ROSTER, .CS9_LAD),
                       "\":{\"SBS-96\":{", cell, "}}"),
                collapse = ", "), "}}")
}
.cs9_file_hash <- function(txt) {
  .ms_cc_sha256_raw(charToRaw(paste0(txt, "\n")))
}

test_that("the CS-9 runner speaks the committed scenario shape", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  f <- file.path(.ms_root, "bench", "scenarios", "run_currency_witness.R")
  expect_true(file.exists(f))
  src <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_true(grepl("--file=", src, fixed = TRUE))
  expect_true(grepl("quit(", src, fixed = TRUE))
  expect_true(grepl("OVERALL PASS", src, fixed = TRUE))
  expect_true(grepl("[attest]", src, fixed = TRUE))
  expect_true(grepl("ms_catalog_currency", src, fixed = TRUE))
  expect_true(grepl("ms_catalog_currency_update", src, fixed = TRUE))
  expect_true(grepl("offline = TRUE", src, fixed = TRUE))
  expect_true(grepl("DECISION RECORD", src, fixed = TRUE))
  expect_true(grepl("jsonlite", src, fixed = TRUE))
  # The network is spoken for by absence: no download face, no URL leg.
  expect_false(grepl("download.file", src, fixed = TRUE))
  expect_false(grepl("download.url", src, fixed = TRUE))
  expect_false(grepl("url(", src, fixed = TRUE))
  expect_false(grepl("Sys.set.seed", src, fixed = TRUE))
  expect_false(grepl("Sys.time", src, fixed = TRUE))
  # Rail spoken by absence: the pillar-2 namespace-reach idiom is banned.
  expect_false(grepl("msuiter:::", src, fixed = TRUE))
})

test_that("the scalars witness pins the frozen scenario constants", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  scal <- .rs_csv9("cs9_scalars.csv")
  expect_identical(nrow(scal), 1L)
  expect_identical(as.character(scal$roster), paste(.CS9_ROSTER, collapse = ","))
  expect_identical(as.character(scal$version_ladder), paste(.CS9_LAD, collapse = ","))
  expect_identical(as.character(scal$pinned_version), .CS9_PINNED)
  expect_identical(as.character(scal$refdb_version), .CS9_REFDB)
  expect_identical(as.character(scal$build_files), paste(.CS9_CELL, collapse = ","))
  expect_identical(as.character(scal$profile_counts),
                   paste0(as.character(.CS9_COUNTS), collapse = ","))
  expect_identical(as.integer(scal$flip_offset), .CS9_FLIP_OFFSET)
  expect_identical(as.integer(scal$flip_before), .CS9_FLIP_BEFORE)
  expect_identical(as.integer(scal$flip_after), .CS9_FLIP_AFTER)
  expect_identical(as.character(scal$hex_reference), .CS9_HEX_REF)
  expect_identical(as.character(scal$hex_availability), .CS9_HEX_AVAIL)
  expect_identical(as.character(scal$hex_shipped_reference), .CS9_HEX_SHIPPED_REF)
  expect_identical(as.character(scal$hex_shipped_availability), .CS9_HEX_SHIPPED_AVAIL)
  expect_identical(as.character(scal$hex_flipped_reference), .CS9_HEX_FLIPPED)
  expect_identical(as.integer(scal$ref_bytes), 193L)
  expect_identical(as.integer(scal$avail_bytes), 3306L)
  expect_identical(as.integer(scal$wrote_files), 4L)
  expect_identical(as.integer(scal$last_current_rung), 4L)
  expect_identical(as.character(scal$last_current_label), "3.6.0")
  expect_identical(as.character(scal$first_behind_label), "3.6.1")
})

test_that("the planted capture re-derives byte-exactly and re-hashes through both kernels", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  ref <- .cs9_ref_txt()
  avail <- .cs9_avail_txt()
  expect_identical(nchar(ref), 193L)
  expect_identical(nchar(avail), 3306L)
  # The canonical pure-R kernel and the shipped digests agree...
  expect_identical(.ms_fit_sha256(charToRaw(paste0(ref, "\n"))), .CS9_HEX_REF)
  expect_identical(.ms_fit_sha256(charToRaw(paste0(avail, "\n"))), .CS9_HEX_AVAIL)
  # ...and so does the governed file hasher's dispatcher.
  expect_identical(.cs9_file_hash(ref), .CS9_HEX_REF)
  expect_identical(.cs9_file_hash(avail), .CS9_HEX_AVAIL)
  # The single flipped byte re-hashes to the committed artefakt digest.
  flipped <- paste0("z", substr(ref, 2L, nchar(ref)))
  expect_identical(.cs9_file_hash(flipped), .CS9_HEX_FLIPPED)
  if (requireNamespace("digest", quietly = TRUE)) {
    ns <- asNamespace("digest")
    expect_identical(ns$digest(charToRaw(paste0(ref, "\n")),
                               algo = "sha256", serialize = FALSE), .CS9_HEX_REF)
  }
})

test_that("the shipped sidecar is the live provenance of the drift expectations", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  reg <- ms_catalog_registry()
  docs <- reg$official$documents
  expect_true(all(c("reference_data", "availability_data") %in% names(docs)))
  expect_identical(docs$reference_data$sha256, .CS9_HEX_SHIPPED_REF)
  expect_identical(docs$availability_data$sha256, .CS9_HEX_SHIPPED_AVAIL)
  hexes <- .rs_csv9("cs9_hexes.csv")
  drift <- hexes[hexes$arm == "drift", ]
  expect_identical(nrow(drift), 2L)
  expect_identical(unname(drift$expected[drift$doc == "reference_data"]),
                   .CS9_HEX_SHIPPED_REF)
  expect_identical(unname(drift$expected[drift$doc == "availability_data"]),
                   .CS9_HEX_SHIPPED_AVAIL)
})

test_that("the clean arm holds its rails: ok/current and closed hex triads", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  arms <- .rs_csv9("cs9_arms.csv")
  expect_identical(as.character(arms$arm),
                   c("clean", "drift", "artefakt", "degenerate"))
  clean <- arms[arms$arm == "clean", ]
  expect_identical(nrow(clean), 1L)
  expect_identical(as.character(clean$verdict), "ok")
  expect_identical(as.character(clean$version_state), "current")
  expect_identical(as.character(clean$latest_status), "measured")
  expect_identical(as.character(clean$latest_release), .CS9_PINNED)
  expect_identical(as.character(clean$docs_states), "ok,ok")
  expect_identical(as.integer(clean$findings_n), 0L)
  expect_identical(as.integer(clean$trusted), 1L)
  expect_identical(as.integer(clean$present), 1L)
  hexes <- .rs_csv9("cs9_hexes.csv")
  ch <- hexes[hexes$arm == "clean", ]
  expect_identical(nrow(ch), 2L)
  expect_identical(as.integer(ch$rails_ok), c(1L, 1L))
  expect_true(.all_hex64(as.character(ch$expected)))
  expect_identical(unname(ch$expected[ch$doc == "reference_data"]), .CS9_HEX_REF)
  expect_identical(unname(ch$expected[ch$doc == "availability_data"]), .CS9_HEX_AVAIL)
  expect_identical(as.character(ch$cached), as.character(ch$expected))
  expect_identical(as.character(ch$record_sha), as.character(ch$expected))
})

test_that("the drift arm is the decision record the unit suite never made", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  arms <- .rs_csv9("cs9_arms.csv")
  dr <- arms[arms$arm == "drift", ]
  expect_identical(nrow(dr), 1L)
  # The synthetic capture against the SHIPPED 3.6 sidecar speaks drift --
  # not ok, not corrupt: the bytes exist and parse, they just are not the
  # bytes the committed registry vouches for.
  expect_identical(as.character(dr$verdict), "drift")
  expect_identical(as.character(dr$version_state), "current")
  expect_identical(as.character(dr$docs_states), "drift,drift")
  # drift keeps the cache trusted (the doc-state law: ok/drift are the
  # trusted states) -- the drift-vs-trusted pair is the committed law.
  expect_identical(as.integer(dr$trusted), 1L)
  hexes <- .rs_csv9("cs9_hexes.csv")
  dh <- hexes[hexes$arm == "drift", ]
  expect_identical(as.integer(dh$rails_ok), c(0L, 0L))
  expect_identical(unname(dh$cached[dh$doc == "reference_data"]), .CS9_HEX_REF)
  expect_identical(unname(dh$cached[dh$doc == "availability_data"]), .CS9_HEX_AVAIL)
})

test_that("the artefakt arm corrupts on a single committed byte", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  arms <- .rs_csv9("cs9_arms.csv")
  art <- arms[arms$arm == "artefakt", ]
  expect_identical(nrow(art), 1L)
  expect_identical(as.character(art$verdict), "corrupt")
  expect_identical(as.character(art$version_state), "unknown")
  expect_identical(as.character(art$latest_status), "unmeasured")
  expect_identical(as.character(art$available_status), "unmeasured")
  expect_identical(as.integer(art$trusted), 0L)
  expect_identical(as.integer(art$present), 1L)
  hexes <- .rs_csv9("cs9_hexes.csv")
  ah <- hexes[hexes$arm == "artefakt", ]
  expect_identical(nrow(ah), 1L)
  expect_identical(as.character(ah$doc), "reference_data")
  expect_identical(as.character(ah$expected), .CS9_HEX_REF)
  expect_identical(as.character(ah$cached), .CS9_HEX_FLIPPED)
  expect_identical(as.integer(ah$rails_ok), 0L)
})

test_that("the degenerate arm speaks an actionable no-cache, never an error", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  arms <- .rs_csv9("cs9_arms.csv")
  dg <- arms[arms$arm == "degenerate", ]
  expect_identical(nrow(dg), 1L)
  expect_identical(as.character(dg$verdict), "no-cache")
  expect_identical(as.integer(dg$present), 0L)
  expect_identical(as.integer(dg$trusted), 0L)
  degens <- .rs_tsv9("cs9_degenerates.tsv")
  val <- function(k) as.integer(degens$value[degens$check == k])
  expect_identical(val("no_cache_no_error"), 1L)
  expect_identical(val("no_cache_hint_names_update"), 1L)
})

test_that("the precedence ladder is ordered and its findings column is monotone", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  lad <- .rs_csv9("cs9_precedence.csv")
  expect_identical(nrow(lad), 5L)
  expect_identical(as.character(lad$verdict), .CS9_PREC_VERDICTS)
  expect_identical(as.integer(lad$findings_n), .CS9_PREC_FINDINGS)
  expect_identical(as.character(lad$version_state), .CS9_PREC_VS)
  # findings grow monotonically as defects accumulate (0 -> 4).
  expect_true(all(diff(as.integer(lad$findings_n)) >= 0L))
  # Precedence law: once a governed finding exists it outranks everything
  # (rung 4 is inconsistent although the zeroed digests still speak);
  # corrupt outranks drift (rung 2 is corrupt, not drift).
  expect_identical(as.character(lad$verdict[4L]), "inconsistent")
  expect_identical(as.character(lad$verdict[3L]), "corrupt")
  # The artefakt rung poisons the version channel: unknown, not current.
  expect_identical(as.character(lad$version_state[3L]), "unknown")
})

test_that("the version ladder commits the measured key-collision law", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  vl <- .rs_csv9("cs9_version_ladder.csv")
  expect_identical(as.character(vl$label), .CS9_LAD)
  expect_identical(as.character(vl$version_state), .CS9_VER_STATES)
  expect_identical(as.character(vl$verdict), .CS9_VER_VERDICTS)
  # The MEASURED law: 3.6 and 3.6.0 share the 3-slot version_key, so an
  # injected latest of 3.6.0 still reads current against the pinned 3.6.
  expect_identical(as.character(vl$version_state[vl$label == "3.6.0"]), "current")
  expect_identical(as.character(vl$version_state[vl$label == "3.6.1"]), "behind")
  # ahead does not degrade the verdict: the rung stays ok.
  expect_identical(as.character(vl$verdict[vl$label == "3.4"]), "ok")
  expect_identical(as.integer(vl$verdict == "behind"),
                   as.integer(c(0L, 0L, 0L, 0L, 1L, 1L)))
})

test_that("the witness payload census: every column alive and in-domain", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  files <- c("cs9_arms.csv", "cs9_hexes.csv", "cs9_precedence.csv",
              "cs9_version_ladder.csv", "cs9_degenerates.tsv", "cs9_scalars.csv")
  present <- vapply(files, function(f) file.exists(.rs_out9(f)), logical(1L))
  expect_identical(unname(present), rep(TRUE, length(files)))
  nonempty <- sum(vapply(files, function(f)
    sum(nzchar(readLines(.rs_out9(f), warn = FALSE))) > 0L, logical(1L)))
  expect_true(nonempty >= 5L)
  arms <- .rs_csv9("cs9_arms.csv")
  expect_true(all(arms$verdict %in%
    c("ok", "behind", "drift", "corrupt", "no-cache", "inconsistent")))
  expect_true(all(arms$version_state %in%
    c("current", "behind", "ahead", "unknown")))
  expect_true(all(arms$latest_status %in% c("measured", "unmeasured")))
  expect_true(all(arms$available_status %in% c("measured", "unmeasured")))
  expect_true(all(arms$present %in% 0:1))
  expect_true(all(arms$trusted %in% 0:1))
  expect_true(all(as.integer(arms$findings_n) >= 0L))
  hexes <- .rs_csv9("cs9_hexes.csv")
  for (k in c("expected", "cached", "record_sha")) {
    expect_true(.all_hex64(as.character(hexes[[k]])))
  }
  expect_true(all(hexes$rails_ok %in% 0:1))
  lad <- .rs_csv9("cs9_precedence.csv")
  expect_true(all(lad$verdict %in%
    c("ok", "drift", "corrupt", "inconsistent")))
  expect_true(all(as.integer(lad$findings_n) %in% 0:4))
  vl <- .rs_csv9("cs9_version_ladder.csv")
  expect_true(all(vl$version_state %in% c("current", "behind", "ahead")))
  expect_identical(length(grep("^[0-9]+(\\.[0-9]+){1,2}$", vl$label, perl = TRUE)),
                   nrow(vl))
})
