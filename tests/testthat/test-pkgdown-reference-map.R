# test-pkgdown-reference-map.R: DS-1 reference completeness law (docs/site v1).
# pkgdown publishes only what the _pkgdown.yml reference index names, and a
# name can silently drift out of the index or sit in two sections without any
# site build ever complaining. This law reads the reference block and the
# NAMESPACE bytes together and pins: the block exists exactly once; every
# NAMESPACE export is listed in exactly one section; every listed entry
# resolves to an export or to an S3 method registered in NAMESPACE; and the
# census is never inspected-empty. The parser is pure string surgery (no
# capture-group or anchored regexes -- this base's tre quirks). The tamper
# half is mandatory (dead-metric law): every reddening rule is fired against
# a constructed-broken copy and the constructed-perfect rebuild is the green
# control.

.ds1_which_eq <- function(vec, s) {
  out <- integer(0)
  for (i in seq_along(vec)) if (identical(vec[i], s)) out <- c(out, i)
  out
}

# --- law -------------------------------------------------------------------

.ds1_is_symbol <- function(x) {
  if (!nzchar(x) || grepl(" ", x, fixed = TRUE) ||
      grepl("\t", x, fixed = TRUE)) {
    return(FALSE)
  }
  ch <- strsplit(x, "")[[1L]]
  all(ch %in% c(LETTERS, letters, 0:9, ".", "_", "-"))
}

.ds1_parse_reference <- function(yml) {
  violations <- character(0)
  sections <- list()
  starts <- .ds1_which_eq(yml, "reference:")
  if (length(starts) == 0L) {
    return(list(ok = FALSE, sections = sections, items = character(0),
                violations = "no reference: block in _pkgdown.yml"))
  }
  if (length(starts) > 1L) {
    return(list(ok = FALSE, sections = sections, items = character(0),
                violations = paste0("reference: block appears ",
                                   length(starts), " times (exactly 1 allowed)")))
  }
  block <- starts[1]
  cur <- NULL            # currently open section: list(title =, items =)
  in_contents <- FALSE
  items_all <- character(0)
  flush <- function() {
    if (!is.null(cur)) {
      if (!nzchar(trimws(cur$title))) {
        violations <<- c(violations, "section with an empty title")
      }
      sections[[length(sections) + 1L]] <<- cur
    }
    invisible(NULL)
  }
  for (i in (block + 1L):length(yml)) {
    l <- yml[i]
    if (!nzchar(trimws(l)) || startsWith(l, "#")) next
    if (startsWith(l, "- title:")) {                  # column 0: new section
      flush()
      cur <- list(title = trimws(sub("^- title:", "", l)),
                  items = character(0))
      in_contents <- FALSE
      next
    }
    if (!startsWith(l, " ")) {
      break                                          # next top-level key
    }
    if (is.null(cur)) {
      violations <- c(violations, paste0("reference-block line before any ",
                                         "'- title:' section: ", l))
      next
    }
    t <- trimws(l)
    if (startsWith(t, "desc:")) {
      in_contents <- FALSE
      next
    }
    if (identical(t, "contents:")) {
      in_contents <- TRUE
      next
    }
    if (startsWith(t, "- ")) {
      if (!in_contents) {
        violations <- c(violations, paste0("item outside a contents: list ",
                                           "(section '", cur$title, "'): ", l))
        next
      }
      nm <- trimws(sub("^- ", "", t))
      if (!.ds1_is_symbol(nm)) {
        violations <- c(violations, paste0("item is not a symbol: ", nm,
                                           " (section '", cur$title, "')"))
        next
      }
      cur$items <- c(cur$items, nm)
      items_all <- c(items_all, nm)
      next
    }
    violations <- c(violations, paste0("unexpected reference-block line: ", l))
  }
  flush()
  list(ok = TRUE, sections = sections, items = items_all,
       violations = violations)
}

.ds1_exports <- function(ns) {
  ex <- character(0)
  for (l in ns) if (startsWith(l, "export(") && endsWith(l, ")")) {
    ex <- c(ex, substr(l, 8L, nchar(l) - 1L))
  }
  ex
}

.ds1_s3_names <- function(ns) {
  out <- character(0)
  for (l in ns) if (startsWith(l, "S3method(") && endsWith(l, ")")) {
    inner <- substr(l, 10L, nchar(l) - 1L)
    parts <- strsplit(inner, ",")[[1L]]
    if (length(parts) != 2L) next
    out <- c(out, paste0(trimws(parts[1]), ".", trimws(parts[2])))
  }
  out
}

.ds1_law <- function(yml, ns) {
  parsed <- .ds1_parse_reference(yml)
  if (!parsed$ok) {
    return(list(violations = parsed$violations, inspected = 0L, exports = 0L))
  }
  exports <- .ds1_exports(ns)
  s3 <- .ds1_s3_names(ns)
  v <- parsed$violations
  if (length(parsed$items) == 0L || length(exports) == 0L) {
    v <- c(v, paste0("vacuous census: inspected items=",
                     length(parsed$items), " exports=", length(exports)))
  }
  for (e in exports) {
    home <- character(0)
    for (s in parsed$sections) if (e %in% s$items) home <- c(home, s$title)
    if (length(home) == 0L) {
      v <- c(v, paste0("export not listed in any section: ", e))
    } else if (length(home) > 1L) {
      v <- c(v, paste0("export listed in ", length(home),
                       " sections (single-home law): ", e, " [",
                       paste0(home, collapse = " | "), "]"))
    }
  }
  resolvable <- c(exports, s3)
  for (it in setdiff(parsed$items, resolvable)) {
    v <- c(v, paste0("listed entry resolves to no export and no registered ",
                     "S3 method: ", it))
  }
  list(violations = v, inspected = length(parsed$items),
       exports = length(exports))
}

# --- repository gate ---------------------------------------------------------

.ds1_repo_file <- function(rel) {
  if (is.na(.ms_root)) {
    skip("repository checkout not locatable (R CMD check context)")
  }
  f <- file.path(.ms_root, rel)
  if (!file.exists(f)) {
    skip(paste0(rel, " not available (R CMD check context)"))
  }
  f
}

.ds1_shipped <- function() {
  yml <- readLines(.ds1_repo_file("_pkgdown.yml"), warn = FALSE)
  ns <- readLines(.ds1_repo_file("NAMESPACE"), warn = FALSE)
  list(yml = yml, ns = ns)
}

# --- green half ---------------------------------------------------------------

test_that("DS-1 the shipped reference map single-homes every export and resolves every entry", {
  d <- .ds1_shipped()
  r <- .ds1_law(d$yml, d$ns)
  expect_identical(r$violations, character(0),
                   info = paste0(r$violations, collapse = "\n"))
  expect_gte(r$inspected, r$exports)
  expect_gte(r$exports, 1L)
  cat("DS-1 CENSUS: inspected items=", r$inspected,
      " exports=", r$exports, "\n", sep = "")
})

# --- red half: constructed-broken controls, every rule must fire --------------

test_that("DS-1 dropping an export from its section reddens the completeness rule", {
  d <- .ds1_shipped()
  hit <- .ds1_which_eq(d$yml, "  - ms_sitrep")
  expect_length(hit, 1L)
  r <- .ds1_law(d$yml[-hit], d$ns)
  expect_true(any(grepl("export not listed in any section: ms_sitrep",
                       r$violations, fixed = TRUE)))
})

test_that("DS-1 listing one export under two sections reddens the single-home rule", {
  d <- .ds1_shipped()
  anchor <- .ds1_which_eq(d$yml, "  - ms_sitrep")
  expect_length(anchor, 1L)
  tampered <- append(d$yml, "  - ms_tally", after = anchor[1])
  r <- .ds1_law(tampered, d$ns)
  expect_true(any(vapply(r$violations, function(x) {
    grepl("single-home law", x, fixed = TRUE) && grepl("ms_tally", x,
                                                        fixed = TRUE)
  }, logical(1))))
})

test_that("DS-1 a ghost entry with no export and no S3 registration is named", {
  d <- .ds1_shipped()
  anchor <- .ds1_which_eq(d$yml, "  - ms_sitrep")
  expect_length(anchor, 1L)
  tampered <- append(d$yml, "  - ms_ghost_face", after = anchor[1])
  r <- .ds1_law(tampered, d$ns)
  expect_true(any(grepl("no export and no registered S3 method: ms_ghost_face",
                        r$violations, fixed = TRUE)))
})

test_that("DS-1 an S3 entry whose method is not registered is named", {
  d <- .ds1_shipped()
  hit <- .ds1_which_eq(d$yml, "  - print.MsQcBurden")
  expect_length(hit, 1L)
  tampered <- d$yml
  tampered[hit[1]] <- "  - print.NotAClass"
  r <- .ds1_law(tampered, d$ns)
  expect_true(any(grepl("no export and no registered S3 method: print.NotAClass",
                        r$violations, fixed = TRUE)))
})

test_that("DS-1 removing the reference: block reddens the law, not the run", {
  d <- .ds1_shipped()
  hit <- .ds1_which_eq(d$yml, "reference:")
  expect_length(hit, 1L)
  r <- .ds1_law(d$yml[-hit], d$ns)
  expect_true(any(grepl("no reference: block", r$violations, fixed = TRUE)))
})

test_that("DS-1 emptying the block trips the vacuous-row rule", {
  d <- .ds1_shipped()
  keep <- vapply(d$yml, function(l) !grepl("  - ", l, fixed = TRUE),
                 logical(1))
  r <- .ds1_law(d$yml[keep], d$ns)
  expect_true(any(grepl("vacuous census", r$violations, fixed = TRUE)))
})

test_that("DS-1 the constructed-perfect rebuild greens the law (live control)", {
  d <- .ds1_shipped()
  exports <- .ds1_exports(d$ns)
  expect_gte(length(exports), 1L)
  # a single deterministic section holding every export exactly once must pass
  # -- proves the green verdict above is carried by the bytes, not by luck.
  rebuilt <- c("reference:", "- title: control", "  contents:",
               paste0("  - ", exports), "articles:")
  r <- .ds1_law(rebuilt, d$ns)
  expect_identical(r$violations, character(0))
  expect_identical(r$inspected, length(exports))
})
