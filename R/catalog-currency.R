# catalog-currency.R: the P5 catalog-currency instrument (parity plan
# docs/research/09 section 5, phase P5; governance shape of
# data-raw/build_refdb.R + R/refdb.R).
#
# msuiter's COSMIC reference snapshot is governed by two committed records:
#   * the refdb manifest (inst/reference/refdb/refdb_manifest.rds) -- the
#     pinned BSD-2 mirror bytes the package actually ships and verifies at
#     load; and
#   * the provenance sidecar (inst/catalog-currency/catalog_registry.rds,
#     validated by catalog-currency-governance.R) -- the committed digest
#     registry for the OFFICIAL COSMIC release records: canonical
#     downloads-page URLs, SHA-256 digests of the measured source
#     documents, version labels and structural (shape) facts. D3 law:
#     digests, URLs, version labels and shape counts only -- COSMIC
#     numeric content never enters the sidecar, the cache or any fixture.
#
# The instrument answers one question mechanically: is the pinned snapshot
# still current against the official COSMIC release line? It resolves
#   * pinned   -- what the committed records assert,
#   * latest   -- what the official source documents last measured as, and
#   * available -- the full official release-label list,
# and reports drift per source document (pinned vs latest vs available),
# never silently. Network policy and the injected-source offline mode are
# documented on ms_catalog_currency_update(); the login-gated matrix-bytes
# leg stays UNMEASURED by law (zero-fabrication).
.ms_cc_report <- function(reg, cache, rec, refdb_manifest) {
  # ---- 1. the pinned leg (registry + live refdb agreement, fail-closed) ---
  findings <- .ms_cc_refdb_findings(reg, refdb_manifest)
  pinned <- list(
    release = reg$pinned_release,
    mirror_repo = reg$mirror$repo,
    mirror_commit = reg$mirror$commit,
    refdb_version = refdb_manifest$version,
    refdb_findings = findings
  )
  # ---- 2. the cache leg (integrity, then registry agreement) --------------
  docs <- list()
  present <- !is.null(rec)
  if (present) {
    for (k in .MS_CC_DOC_KEYS) {
      want_record <- rec$documents[[k]]$sha256
      want_registry <- reg$official$documents[[k]]$sha256
      path <- .ms_cc_doc_path(cache, k)
      if (!file.exists(path)) {
        docs[[k]] <- list(state = "missing", expected = want_registry,
                        cached = NA_character_, record_sha = want_record)
        next
      }
      got <- .ms_cc_sha256_file(path)
      state <- if (!identical(got, want_record)) {
        "corrupt"                    # the cache broke against its own record
      } else if (!identical(got, want_registry)) {
        "drift"                      # the source moved against the committed sidecar
      } else {
        "ok"
      }
      docs[[k]] <- list(state = state, expected = want_registry, cached = got,
                        record_sha = want_record)
    }
  }
  doc_states <- vapply(docs, function(d) d$state, character(1L))
  trusted <- present && all(doc_states %in% c("ok", "drift"))
  integrity_bad <- present && any(doc_states %in% c("corrupt", "missing"))
  # ---- 3. the latest/available legs (only from a trusted record) ----------
  if (trusted) {
    latest <- list(status = "measured", release = rec$latest_release)
    available <- list(status = "measured", releases = rec$releases)
    cmp <- .ms_cc_version_cmp(rec$latest_release, reg$pinned_release)
    version_state <- switch(as.character(cmp), "-1" = "ahead", "0" = "current", "1" = "behind")
  } else {
    latest <- list(status = "unmeasured", release = NA_character_)
    available <- list(status = "unmeasured", releases = character())
    version_state <- "unknown"
  }
  # ---- 4. the verdict (precedence is law, documented and tested) ----------
  verdict <- if (length(findings)) {
    "inconsistent"
  } else if (integrity_bad) {
    "corrupt"
  } else if (!present) {
    "no-cache"
  } else if (any(doc_states == "drift")) {
    "drift"
  } else if (identical(version_state, "behind")) {
    "behind"
  } else {
    "ok"
  }
  # ---- 5. the human surface ------------------------------------------------
  messages <- sprintf(
    "verdict: %s (pinned %s vs latest %s, available: %s)",
    verdict, reg$pinned_release,
    if (identical(latest$status, "measured")) latest$release else "unmeasured",
    if (identical(available$status, "measured")) paste(available$releases, collapse = ", ") else "unmeasured"
  )
  if (identical(version_state, "behind")) {
    messages <- c(messages, sprintf(
      "the official line published release '%s' after this snapshot was pinned -- review the bump deliberately (commit + digests together, never one of them)",
      latest$release))
  }
  if (identical(version_state, "ahead")) {
    messages <- c(messages, sprintf(
      "the sidecar pins '%s' while the source documents still report '%s' -- the re-pin was measured ahead of the last update run",
      reg$pinned_release, latest$release))
  }
  if (length(findings)) {
    messages <- c(messages, findings)
  }
  hints <- character()
  if (identical(verdict, "no-cache")) {
    hints <- c(hints, sprintf(
      "no cache at %s -- run ms_catalog_currency_update() (offline-capable via `source`) to derive it",
      cache))
  }
  if (identical(verdict, "corrupt")) {
    hints <- c(hints, "the cache broke against its own record -- re-derive with ms_catalog_currency_update()")
  }
  if (identical(verdict, "drift")) {
    hints <- c(hints, "the official source documents moved against the committed sidecar -- review, then re-pin via data-raw/build_catalog_registry.R")
  }
  structure(
    list(
      schema_version = .MS_CC_SCHEMA,
      kind = "ms_catalog_currency_report",
      verdict = verdict,
      version_state = version_state,
      pinned = pinned,
      cache = list(present = present, dir = cache, docs = docs),
      latest = latest,
      available = available,
      messages = messages,
      hints = hints
    ),
    class = "ms_catalog_currency_report"
  )
}

# Process-level memo of the validated refdb governance manifest. Reading it
# re-hashes every shipped matrix through the pure-R SHA-256 kernel
# (fail-closed over the bytes), which is expensive to repeat for every
# currency check within one session; the memo keeps that to one validated
# read per process while preserving the fail-closed guarantee (an injected
# manifest still bypasses it and is re-validated every time).
.MS_CC_REFDB_MEMO <- new.env(parent = emptyenv())

.ms_cc_resolve_refdb_manifest <- function(refdb_manifest) {
  if (!is.null(refdb_manifest)) {
    return(.ms_cc_validate_injected_manifest(refdb_manifest))
  }
  memo <- .MS_CC_REFDB_MEMO$manifest
  if (!is.null(memo)) {
    return(memo)
  }
  memo <- ms_refdb_manifest() # fail-closed over the shipped bytes itself
  .MS_CC_REFDB_MEMO$manifest <- memo
  memo
}

.ms_cc_public_cache <- function(cache) {
  if (is.null(cache)) .ms_cc_default_cache_dir() else .ms_cc_arg_dir(cache, "cache")
}

# ===========================================================================
# Public API.
# ===========================================================================

#' The committed catalog-currency digest registry
#'
#' Reads and fully validates the provenance sidecar that makes msuiter's
#' pinned COSMIC catalog snapshot mechanically verifiable: the canonical
#' official-site URLs, the SHA-256 digests of the measured release and
#' availability source documents, the pinned/target version labels, the
#' BSD-2 mirror provenance and the refdb cross-reference pointers.
#'
#' **Governance (fail-closed, the refdb loader pattern).** The sidecar's
#' `schema_version` gates the read (a newer schema is refused, never read
#' best-effort), every digests/URL/label field is validated against its
#' documented shape, and the login-gated matrix-bytes leg must be recorded
#' `UNMEASURED` -- a fabricated digests there is a hard stop.
#'
#' @param path NULL (default; the bundled
#'   `inst/catalog-currency/catalog_registry.rds`) or a single path to an
#'   alternative sidecar (review candidates, test fixtures).
#' @return A named list: the validated registry (schema_version, kind,
#'   pinned_release, mirror provenance, refdb pointers, the official
#'   documents/releases/structure block, and the UNMEASURED matrix-bytes
#'   record).
#' @seealso [ms_catalog_currency()] for the verdict, [ms_refdb_manifest()]
#'   for the shipped-bytes governance it cross-checks.
#' @export
ms_catalog_registry <- function(path = NULL) {
  path <- .ms_cc_arg_string(path, "path", allow_null = TRUE,
                           call = rlang::caller_call(2L))
  reg_path <- if (is.null(path)) .ms_cc_bundled_registry() else
    normalizePath(path, mustWork = FALSE)
  .ms_cc_read_registry(reg_path, call = rlang::caller_call(2L))
}

#' Verify the pinned COSMIC catalog snapshot for currency
#'
#' The offline verdict engine of the P5 catalog-currency instrument. It
#' resolves three legs and reports drift per governed source document:
#'
#' * **pinned** -- what the committed sidecar and the live refdb governance
#'   manifest assert (version label, mirror commit, governed file set);
#' * **latest** -- what the last derived cache record measured as the
#'   official release line (only trusted when every cached document's
#'   bytes verify against the cache's own record);
#' * **available** -- the full measured release-label list.
#'
#' **Verdict law** (precedence: `inconsistent` > `corrupt` > `no-cache` >
#' `drift` > `behind` > `ok`): `inconsistent` is the pinned-vs-refdb
#' cross-check disagreeing; `corrupt` is the cache breaking against its
#' own record (bytes changed or vanished); `no-cache` means nothing was
#' ever derived (an actionable state, not an error -- see `$hints`);
#' `drift` is the cached documents disagreeing with the committed sidecar
#' digests; `behind` is the official line having published a newer
#' release than the pinned one. `version_state` is the separate
#' `current`/`behind`/`ahead`/`unknown` axis. Nothing here mutates
#' anything; the returned report is a plain named list carrying class
#' `ms_catalog_currency_report`.
#'
#' @param cache NULL (default; resolved from the
#'   `msuiter.catalog_currency.cache_dir` option, else the
#'   `MSUITER_CATALOG_CURRENCY_CACHE_DIR` environment variable, else the
#'   user cache directory) or a single directory holding a derived cache.
#' @param registry NULL (the committed sidecar) or a single path to an
#'   alternative sidecar.
#' @param refdb_manifest NULL (default; the governed manifest is read
#'   through [ms_refdb_manifest()], which itself re-verifies every shipped
#'   digest) or a governance-manifest-shaped list -- a test/automation
#'   seam, validated before use and never trusted half-read.
#' @return A `ms_catalog_currency_report`: the verdict, version_state,
#'   the pinned/latest/available legs, per-document states (each with
#'   `state`, `expected`, `cached`, `record_sha`), plus `messages` and
#'   `hints`.
#' @seealso [ms_catalog_currency_update()] to (re-)derive the cache,
#'   [ms_catalog_registry()] for the sidecar contract.
#' @export
ms_catalog_currency <- function(cache = NULL, registry = NULL, refdb_manifest = NULL) {
  cache <- .ms_cc_public_cache(cache)
  registry <- .ms_cc_arg_string(registry, "registry", allow_null = TRUE,
                               call = rlang::caller_call(2L))
  reg <- .ms_cc_read_registry(
    if (is.null(registry)) .ms_cc_bundled_registry() else
      normalizePath(registry, mustWork = FALSE),
    call = rlang::caller_call(2L)
  )
  man <- .ms_cc_resolve_refdb_manifest(refdb_manifest)
  rec <- .ms_cc_read_record(cache)
  .ms_cc_report(reg, cache, rec, man)
}

#' Refresh the catalog-currency cache from the official source documents
#'
#' The updater leg of the P5 instrument. It fetches (or, with `source`,
#' injects) the two governed official documents -- the release reference
#' and the availability structure of the COSMIC signatures downloads page
#' -- extracts their JSON payloads canonically, writes the verbatim bytes
#' into the GITIGNORED cache directory, and records the computed SHA-256
#' digests in the cache's own integrity record. The derivation is
#' byte-idempotent: same sources, same bytes (no timestamps, no
#' randomness), mirroring the refdb builder's discipline. A candidate
#' sidecar is written next to the record for human review -- the
#' committed sidecar is only ever re-pinned deliberately via
#' `data-raw/build_catalog_registry.R`, never by this call.
#'
#' **Injected-source mode (offline by construction).** `source` is a
#' downloads-page file or a split directory holding
#' `reference_data.json`/`availability_data.json`; with a `source` given,
#' no network leg is ever attempted. `offline = TRUE` additionally
#' refuses the default official-site fetch. D3 law: only digests, URLs,
#' version labels and shape counts are recorded; COSMIC numeric content
#' is never read, kept or committed anywhere in this flow.
#'
#' @param source NULL (the official-site fetch) or a single existing path:
#'   a downloads-page capture file or a split document directory.
#' @param cache the cache directory (default as in [ms_catalog_currency()]).
#' @param registry NULL (the committed sidecar, whose canonical URLs and
#'   structure the candidate is derived against) or a sidecar path.
#' @param offline TRUE refuses every network leg; with `source = NULL`
#'   that is a structured refusal pointing at `source`.
#' @return Invisibly, the [ms_catalog_currency()] report for the freshly
#'   derived cache, extended with `$update` (the written file paths and
#'   the candidate sidecar path).
#' @seealso [ms_catalog_currency()] for the verdict semantics.
#' @export
ms_catalog_currency_update <- function(source = NULL, cache = NULL,
                                       registry = NULL, offline = FALSE) {
  source <- .ms_cc_arg_existing_path(source, "source", call = rlang::caller_call(2L))
  cache <- .ms_cc_public_cache(cache)
  registry <- .ms_cc_arg_string(registry, "registry", allow_null = TRUE,
                               call = rlang::caller_call(2L))
  offline <- .ms_cc_arg_flag(offline, "offline", call = rlang::caller_call(2L))
  reg <- .ms_cc_read_registry(
    if (is.null(registry)) .ms_cc_bundled_registry() else
      normalizePath(registry, mustWork = FALSE),
    call = rlang::caller_call(2L)
  )
  page_url <- reg$official$page_url

  harvest <- .ms_cc_harvest(source, page_url, offline)
  ref <- .ms_cc_parse_reference(harvest$ref_text)
  latest <- .ms_cc_latest_version(ref$releases)
  structure <- .ms_cc_parse_availability(harvest$avail_text, latest)

  doc_states <- list(
    reference_data = list(text = harvest$ref_text),
    availability_data = list(text = harvest$avail_text)
  )
  wrote <- character()
  for (k in .MS_CC_DOC_KEYS) {
    wrote <- c(wrote, .ms_cc_write_verbatim(.ms_cc_doc_path(cache, k),
                                            doc_states[[k]]$text))
  }
  rec <- .ms_cc_build_record(harvest$origin, doc_states, ref$releases,
                             latest, latest, structure, page_url)
  rec_path <- .ms_cc_record_path(cache)
  dir.create(cache, recursive = TRUE, showWarnings = FALSE)
  saveRDS(rec, rec_path, version = 2L)
  wrote <- c(wrote, rec_path)

  candidate <- reg
  candidate$official$documents <- lapply(rec$documents, function(d) {
    list(url = d$url, script_id = d$script_id, sha256 = d$sha256, bytes = d$bytes)
  })
  candidate$official$releases <- rec$releases
  candidate$official$latest_release <- rec$latest_release
  candidate$official$structure_release <- rec$structure_release
  candidate$official$structure <- rec$structure
  cand_path <- .ms_cc_candidate_path(cache)
  saveRDS(candidate, cand_path, version = 2L)
  wrote <- c(wrote, cand_path)

  rep <- ms_catalog_currency(cache = cache, registry = registry,
                            refdb_manifest = NULL)
  rep$update <- list(wrote = wrote, candidate = cand_path)
  rep
}

#' Print a catalog-currency report
#'
#' Compact print of a `ms_catalog_currency_report`: the verdict/version axis,
#' the pinned-vs-latest-vs-available legs, and the per-document drift states.
#'
#' @param x A `ms_catalog_currency_report` from
#'   [ms_catalog_currency()].
#' @param ... Further arguments (unused; compatibility with the generic).
#' @return `x`, invisibly.
#' @export
print.ms_catalog_currency_report <- function(x, ...) {
  cat("msuiter catalog-currency report\n")
  cat(sprintf("  verdict: %-12s version: %s\n", x$verdict, x$version_state))
  cat(sprintf("  pinned:  %s (mirror %.12s...  refdb %s)\n",
              x$pinned$release, x$pinned$mirror_commit, x$pinned$refdb_version))
  if (length(x$pinned$refdb_findings)) {
    for (f in x$pinned$refdb_findings) cat("    ! ", f, "\n", sep = "")
  }
  cat(sprintf("  latest:  %s (%s)\n",
              if (identical(x$latest$status, "measured")) x$latest$release else "-",
              x$latest$status))
  cat(sprintf("  available: %s (%s)\n",
              if (identical(x$available$status, "measured"))
                paste(x$available$releases, collapse = ", ") else "-",
              x$available$status))
  for (k in names(x$cache$docs)) {
    d <- x$cache$docs[[k]]
    cat(sprintf("  document %-16s %-8s expected %.12s... got %s\n",
                k, d$state, d$expected,
                if (is.na(d$cached)) "(absent)" else paste0(substr(d$cached, 1L, 12L), "...")))
  }
  for (m in x$messages) cat("  > ", m, "\n", sep = "")
  for (h in x$hints) cat("  i ", h, "\n", sep = "")
  invisible(x)
}
