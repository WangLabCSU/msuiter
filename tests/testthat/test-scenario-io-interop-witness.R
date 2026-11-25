# test-scenario-io-interop-witness.R -- the CS-13 io-interop-witness law
# units (pillar 3). The scenario plants file bytes and adjudicates the
# EXPORTED interop faces ms_import() and ms_export() under seven arms: the
# format enum with its [V]-discipline deferral clause and the
# option-before-file precedence, the file gate, the header-anchor law (the
# zero-data-column boundary included), the three-way registry-label law, the
# cell law versus the whole-number law two-level split, the signature-face
# downstream laws, and the certified export legs (header-collision, the
# 17-significant-digit fidelity posture with its measured 1-ulp drill, the
# provenance hash pair). The witness bytes under bench/scenarios/out/
# (cs13_specs.tsv, cs13_laws.tsv, cs13_precedence.tsv, cs13_fidelity.tsv,
# cs13_scalars.tsv) are the committed verdict: a drift in a fired clause, an
# observed error class, a written token or the precedence order reddens here
# before print. The plant is synthetic registry-label TSV text and hand-picked
# rationals -- no RNG, no network, no COSMIC bytes; the lane NEVER calls the
# benchmark driver, the declined calibration family, or any internal of the
# face except the label source of truth (banned words, grepped).
# Framing law: DECISION RECORD only. What the faces say on planted truth --
# the accepted round-trips, the abort classes, the fired bullets, the written
# bytes -- is an OBSERVED, COMMITTED record, never a fidelity claim beyond
# what was measured. Cross-platform posture (D11): integer, label, class and
# clause bytes are byte-committed; the ill-conditioned float renderings and
# drift bits from the 1-ulp fidelity drill carry payload CENSUSES only
# (non-empty, non-NA, in-domain), never cross-platform byte-equals.
# The pillar-2 idiom of reaching the package namespace directly (msuiter:::)
# is BANNED here and grepped away.

.rs_out13 <- function(fname) {
  file.path(.ms_root, "bench", "scenarios", "out", fname)
}

# The committed tables are written quote-free; quote = "" keeps every double
# quote inside the clauses (and every other byte) literal on read.
.rs_tsv13 <- function(fname) {
  read.csv(.rs_out13(fname), header = TRUE, sep = "\t",
           stringsAsFactors = FALSE, na.strings = "", colClasses = "character",
           quote = "")
}

# cli bullet glyphs are RENDERING, not bytes (CS-12 precedent): the \u2139 theme
# prints outside the harness, the testthat context prints an ASCII "i".
# Both are stripped per line; the law table stores the bullet-free joins.
.cs13_describe <- function(e) {
  # the message may arrive as one string carrying embedded newlines (inside
  # the testthat harness) or as a vector of lines (plain Rscript) -- stitch
  # first, split on the joiner, strip every bullet rendering per segment
  m <- gsub("\n", " | ", paste(as.character(conditionMessage(e)),
                              collapse = " | "), fixed = TRUE)
  segs <- strsplit(m, " | ", fixed = TRUE)[[1L]]
  segs <- vapply(seq_along(segs), function(i) {
    s <- trimws(segs[i])
    # sub(fixed = TRUE) is a literal substring op on this base: anchored
    # patterns never match. Strip the two measured bullet renderings
    # (unicode theme, harness ASCII theme) by prefix instead.
    for (b in c(paste0(.CS13_BULLET, " "), "i ")) {
      if (startsWith(s, b)) s <- substring(s, nchar(b) + 1L)
    }
    trimws(s)
  }, character(1L))
  paste0(segs, collapse = " | ")
}

# ---------------------------------------------------------------------------
# Frozen constants -- mirrored byte-identically in
# bench/scenarios/run_io_interop_witness.R (single source of truth). Every
# value MEASURED through the exported faces (probes cs13-probe1/2/3,
# EXIT-0); none derived.

.CS13_CLASS_CATALOG <- "msuiter::MsCatalog"
.CS13_BULLET <- "\u2139"
.CS13_CLASS_SIG <- "msuiter::MsSignature"
.CS13_CLASS_DF <- "data.frame"
.CS13_CLASS_INPUT <- "msuiter_error_input"
.CS13_CLASS_OPTION <- "msuiter_error_option"
.CS13_CLASS_SIGN <- "msuiter_error_signature"
.CS13_CLASS_BASE <- "simpleError"

.CS13_TABLE <- "SBS96"
.CS13_TABLEROSTER <- paste0("SBS96=96,SBS192=192,SBS384=384,SBS1536=1536,",
                            "DBS78=78")
.CS13_FORMATS <- "cosmic,sigprofiler"
.CS13_HEADERS <- "cosmic=Type,sigprofiler=MutationType"

# verbatim fired texts ( | joins, glyph-stripped) --------------------------------
.CS13_CL_OPTION <- function(received) {
  paste0("format must be one of the verified formats | WTSI long format is ",
         "deferred pending an upstream specimen ([V] discipline) | received: ",
         "'", received, "'; verified: cosmic, sigprofiler | see ",
         "paper/devlog-2026-10-04-M4-02-design-memo.qmd sections 2/4")
}
.CS13_CL_FILE <- paste0("file must be a path to an existing file | ",
                        "ms_import() reads a catalog/signature TSV from disk")
.CS13_CL_FILE_TAIL <- "pass the TSV path returned by ms_export()"
.CS13_CL_HDR <- function(fmt, anchor, received) {
  bullet <- if (identical(fmt, "cosmic"))
    "the layout anchor is the bundled COSMIC v3.6 reference file"
  else
    "the layout anchor is the pinned SigProfilerAssignment specimen (tests fixture)"
  paste0(fmt, "-format files need a \"", anchor, "\" first header column | ",
         bullet, " | received header: ", received,
         " | pass a file written by ms_export(format = \"", fmt, "\")")
}
.CS13_HDR_INFERMISS <- paste0("labels do not match any registry channel ",
  "table exactly | ms_import/ms_export accept only canonical-order registry ",
  "labels | rows: 96; first label: A[C>A]C | order the matrix by one of: ",
  "SBS96, SBS192, SBS384, SBS1536, DBS78")
.CS13_CL_PINUNKNOWN <- function(received) {
  paste0("channel_table must name one of the registry tables | the table ",
         "pins the canonical label order | received: '", received,
         "' | use one of: SBS96, SBS192, SBS384, SBS1536, DBS78")
}
.CS13_PINMISMATCH <- paste0("labels do not match the SBS96 canonical order | ",
  "the interop contract is exact registry order, no reordering | first ",
  "mismatch at row 1: A[C>A]C vs A[C>A]A | reorder the matrix with the ",
  "registry labels before export")
.CS13_CELLABC <- paste0("cosmic-format data cells must be numeric | the ",
  "interop grid is numeric counts or probabilities; literal cells are ",
  "uninterpretable | offending cell: row 3 (A[C>A]G), column 1 (sA), ",
  "value 'abc' | repair the cell in the source file or re-export with ",
  "ms_export()")
.cs13_wn <- function(entries) {
  paste0("catalog import needs finite non-negative whole-number counts | ",
         "a catalog is integer mutation counts | offending entries: ",
         entries, " | import probabilities with kind = \"signatures\"")
}
.CS13_SIGN_NONNEG <- paste0("signatures must be non-negative | signatures ",
  "and exposures are non-negative by definition | offending cells: '5' | ",
  "check the engine output for sign errors")
.CS13_SIGN_NAFIN <- paste0("signatures must not contain NA or non-finite ",
  "values | the FFI contract rejects NA | offending cells: '5' | fix the ",
  "upstream computation")
.CS13_SIGN_ALLNA <- paste0("signatures must not contain NA or non-finite ",
  "values | the FFI contract rejects NA | offending cells: '1', '2', '3', ",
  "'4', '5', '6', '7', '8', '9', '10', ... (96 total) | fix the upstream ",
  "computation")
.CS13_XGATE <- function(received) {
  paste0("x must be an MsCatalog or an MsSignature | the interop face ",
         "exports channel x column matrices | received: ", received,
         " | pass a catalog (counts) or a signature set (probabilities)")
}
.CS13_COLLIDE <- function(fmt, anchor, nm) {
  paste0("column names must not collide with the ", fmt, " header column ",
         "\"", anchor, "\" | the first exported column is the channel ",
         "label carrier | colliding names: ", nm, " | rename those ",
         "samples/signatures before exporting (a silent rename would not ",
         "round-trip)")
}
.CS13_LOCALE_ONLY <- "[locale-variable base message; class-committed only]"

# the three-way cell/whole-number discriminators speak these anchors
.CS13_CELL_ANCHOR <- "data cells must be numeric"
.CS13_WN_ANCHOR <- "needs finite non-negative whole-number counts"
.CS13_FILE_ANCHOR <- "must be a path to an existing file"

# fidelity tokens -- the R printer's output for the four planted literals
# (byte-committed; the %.20g renderings beside them are census-only)
.CS13_FID_TOKENS <- c("1.2345678901234569e-01", "5.0000000000000000e-01",
                      "3.3333333333333331e-01", "1.0000000000000002e+07")

# ---------------------------------------------------------------------------
# The plant builders -- mirrored byte-identically in the runner (single
# source of truth). Plants are deterministic: no RNG, no clock, ASCII only.
.cs13_lab <- function() as.character(.ms_io_channel_tables()[[.CS13_TABLE]])

.cs13_mk_catalog <- function(smp = c("sA", "sB")) {
  LAB <- .cs13_lab()
  m <- matrix(seq_len(length(LAB) * length(smp)) %% 7L, nrow = length(LAB),
              ncol = length(smp), dimnames = list(LAB, smp))
  storage.mode(m) <- "double"
  ms_catalog(m, list(name = .CS13_TABLE, labels = LAB), smp,
             provenance = list(genome = "SYNTH"))
}

.cs13_mk_sig <- function(cols = c("sig1", "sig2"), vals = NULL) {
  LAB <- .cs13_lab()
  m <- if (is.null(vals)) matrix(0.5, nrow = length(LAB), ncol = length(cols))
       else matrix(vals, nrow = length(LAB), ncol = length(cols))
  dimnames(m) <- list(LAB, cols)
  ms_signature(signatures = m,
               exposures = matrix(0, nrow = length(cols), ncol = 1L,
                                  dimnames = list(cols, "sA")),
               catalog_summary = msuiter_catalog_summary(
                 .cs13_mk_catalog(smp = "sA")),
               engine = "cs13-witness", seed = 0)
}

.cs13_wl <- function(lines, path) {
  # binary channel pins the EOL: plant bytes -- and the SHA-256 taken over
  # them -- must not ride the platform's text translation
  con <- file(path, open = "wb")
  on.exit(close(con))
  writeLines(lines, con)
  invisible(path)
}
.cs13_write_tsv <- function(pd, nm, hdr, cols, rows) {
  p <- file.path(pd, nm)
  lines <- c(paste0(c(hdr, cols), collapse = "\t"),
             apply(rows, 1L, function(rw) paste0(unname(rw), collapse = "\t")))
  .cs13_wl(lines, p)
  p
}

# the planted columns: labels in the FIRST column (probe-1's blind window
# law: a plant whose label column never entered the file observes nothing)
.cs13_counts <- function(bad_val = NULL, bad_row = 5L) {
  LAB <- .cs13_lab()
  v <- vapply(seq_along(LAB), function(i) as.character(i %% 4L),
              character(1L))
  if (!is.null(bad_val)) v[bad_row] <- bad_val
  cbind(LAB, v)
}

.cs13_plants <- function() {
  LAB <- .cs13_lab()
  pd <- file.path(tempdir(TRUE), "cs13-law-plants")
  dir.create(pd, showWarnings = FALSE)
  W <- function(nm, ...) .cs13_write_tsv(pd, nm, ...)
  P <- list()
  P$dir <- pd
  P$good <- W("good.tsv", "Type", c("sA", "sB"),
              cbind(LAB, .cs13_counts()[, 2L], .cs13_counts()[, 2L]))
  P$sgp <- W("sgp.tsv", "MutationType", "sA", .cs13_counts())
  P$badh <- W("badh.tsv", "Kind", "sA", .cs13_counts())
  P$onecol <- file.path(pd, "onecol.tsv")
  .cs13_wl(c("Type", LAB), P$onecol)
  rev2 <- LAB
  rev2[1L:2L] <- LAB[c(2L, 1L)]
  P$mis <- W("mis.tsv", "Type", "sA", as.matrix(rev2))
  P$nn <- W("nn.tsv", "Type", "sA", .cs13_counts("abc", 3L))
  P$fr <- W("fr.tsv", "Type", "sA", .cs13_counts("1.5", 5L))
  P$ng <- W("ng.tsv", "Type", "sA", .cs13_counts("-1", 5L))
  P$na1 <- W("na1.tsv", "Type", "sA", .cs13_counts("NA", 5L))
  P$nan1 <- W("nan1.tsv", "Type", "sA", .cs13_counts("NaN", 5L))
  P$infc <- W("infc.tsv", "Type", "sA", .cs13_counts("Inf", 5L))
  P$emptyc <- W("emptyc.tsv", "Type", "sA", .cs13_counts("", 5L))
  allna <- .cs13_counts()
  allna[, 2L] <- rep("NA", length(LAB))
  P$allna <- W("allna.tsv", "Type", "sA", allna)
  dup <- file.path(pd, "dup.tsv")
  .cs13_wl(c("Type\tsA\tsA",
             vapply(seq_along(LAB), function(i)
               paste0(LAB[i], "\t", i %% 4L, "\t", (i + 1L) %% 4L,
                      collapse = ""), character(1L))), dup)
  P$emptyf <- file.path(pd, "empty.tsv")
  .cs13_wl(character(0L), P$emptyf)
  P$missing <- file.path(pd, "no-such.tsv")
  P$dup <- dup
  P
}

.cs13_try <- function(expr) tryCatch(list(v = expr), error = identity)
.cs13_cls <- function(r) if (inherits(r, "error")) class(r)[1L] else
                         class(r$v)[1L]
.cs13_msg <- function(r) if (inherits(r, "error")) .cs13_describe(r) else ""

# per-spec live detail renderings (the committed detail bytes recomputed)
.cs13_detail <- function(arm, P) {
  LAB <- .cs13_lab()
  esc <- function(x) gsub("\t", "\\t", x, fixed = TRUE)
  switch(arm,
    "e1-df" = {
      r <- .cs13_try(ms_export(.cs13_mk_catalog(), "cosmic", NULL))
      paste0("hdr=", names(r$v)[1L], ";ncol=", ncol(r$v))
    },
    "e3-df" = {
      r <- .cs13_try(ms_export(.cs13_mk_sig(), "sigprofiler", NULL))
      paste0("hdr=", names(r$v)[1L], ";ncol=", ncol(r$v))
    },
    "e10-write" = {
      fp <- file.path(P$dir, "law-fid.tsv")
      ms_export(.cs13_mk_sig(cols = "fid", vals = .CS13_FID_PLANT),
                "cosmic", fp)
      rr <- readLines(fp)
      toks <- vapply(seq_len(4L), function(k) {
        f <- strsplit(rr[k + 1L], "\t", fixed = TRUE)[[1L]]
        f[length(f)] }, character(1L))
      # D11 posture: byte-freeze here rides the LABEL and the digit-count
      # only. The re-export identity bit is DELIBERATELY ABSENT -- on this
      # base the 17-significant-digit glyph of a halfway double does not
      # re-parse to the double its own glyph names (witnessed: the …69
      # glyph re-exports as …68 in the SAME process), so a byte-round-trip
      # identity is not a law; numeric faithfulness rides all.equal().
      paste0("hdr=", esc(rr[1L]),
             ";row1=", esc(strsplit(rr[2L], "\t", fixed = TRUE)[[1L]][1L]),
             ";tok-digits=", paste0(nchar(toks), collapse = ","),
             ";tok-plant-equal=",
             isTRUE(all.equal(as.numeric(toks), .CS13_FID_PLANT)))
    },
    "i-catalog" = {
      o <- .cs13_try(ms_import(P$good))$v
      paste0("dims=", paste(dim(o@counts), collapse = "x"),
             ";samps=", paste0(o@samples, collapse = ","),
             ";channame=", o@channels$name,
             ";prov-genome=", o@provenance$genome,
             ";prov-format=", o@provenance$format)
    },
    "i-sig" = {
      o <- .cs13_try(ms_import(P$good, "cosmic", "signatures"))$v
      cs <- o@catalog_summary
      bytes <- readBin(P$good, "raw", file.size(P$good))
      hA <- .ms_fit_sha256(bytes)
      hB <- asNamespace("digest")$digest(bytes, algo = "sha256",
                                         serialize = FALSE)
      hL <- msuiter_hash_labels(as.character(LAB))
      paste0("dims=", paste(dim(o@signatures), collapse = "x"),
             ";exposures=", paste(dim(o@exposures), collapse = "x"),
             ";exporownames=", paste0(rownames(o@exposures), collapse = ","),
             ";build=", cs$build,
             ";n_samples=", cs$n_samples,
             ";n_channels=", cs$n_channels,
             ";channame=", cs$channel_name,
             ";chanhash=", cs$channel_hash,
             ";hash-labels-recomputed=", hL,
             ";hashes-agree=", identical(cs$channel_hash, hL),
             ";filehashA=", hA, ";filehashB=", hB,
             ";kernels-agree=", identical(hA, hB),
             ";build-carries-filehash=",
             identical(cs$build, paste0("imported:sha256=", hA)))
    },
    "rt-int-storage" = {
      rp <- file.path(P$dir, "law-rt.tsv")
      ms_export(.cs13_mk_catalog(), "cosmic", rp)
      o <- ms_import(rp)
      m2 <- o@counts
      storage.mode(m2) <- "double"
      paste0("import-storage=", storage.mode(o@counts),
             ";plant-storage=", storage.mode(.cs13_mk_catalog()@counts),
             ";all-equal=", isTRUE(all.equal(o@counts,
                                             .cs13_mk_catalog()@counts)),
             ";repair-identical=", identical(m2, .cs13_mk_catalog()@counts))
    },
    "(none)"  # cls-only arms carry no rendering; the sentinel rides the
               # witness too (empty fields read back as NA: forensics U3)
  )
}
.CS13_FID_PLANT <- c(0.123456789012345678, 0.500000000000000011,
                     0.33333333333333331, 9999999.9999999999)

# the 36 law arms: how each is fired live, and its committed adjudication
.cs13_fire <- function(arm, P) {
  TAB <- .CS13_TABLE
  switch(arm,
    "opt-e-wtsi"        = .cs13_try(ms_export(.cs13_mk_catalog(), "wtsi", NULL)),
    "opt-e-upper"       = .cs13_try(ms_export(.cs13_mk_catalog(), "COSMIC", NULL)),
    "opt-i-wtsi-missing" = .cs13_try(ms_import(P$missing, "wtsi")),
    "opt-i-wtsi-good"   = .cs13_try(ms_import(P$good, "wtsi")),
    "hdr-cosmic-kind"   = .cs13_try(ms_import(P$badh)),
    "hdr-cosmic-onecol" = .cs13_try(ms_import(P$onecol)),
    "hdr-sgp-wrong"     = .cs13_try(ms_import(P$good, "sigprofiler")),
    "lbl-infer-miss"    = .cs13_try(ms_import(P$mis)),
    "pin-unknown-nope"  = .cs13_try(ms_import(P$good, channel_table = "NOPE")),
    "pin-unknown-true"  = .cs13_try(ms_import(P$good, channel_table = TRUE)),
    "pin-mismatch"      = .cs13_try(ms_import(P$mis, channel_table = TAB)),
    "cell-nonnum-abc"   = .cs13_try(ms_import(P$nn)),
    "wn-frac"           = .cs13_try(ms_import(P$fr)),
    "wn-neg"            = .cs13_try(ms_import(P$ng)),
    "wn-na"             = .cs13_try(ms_import(P$na1)),
    "wn-nan"            = .cs13_try(ms_import(P$nan1)),
    "wn-inf"            = .cs13_try(ms_import(P$infc)),
    "wn-allna"          = .cs13_try(ms_import(P$allna)),
    "sig-nonneg"        = .cs13_try(ms_import(P$ng, "cosmic", "signatures")),
    "sig-na"            = .cs13_try(ms_import(P$na1, "cosmic", "signatures")),
    "sig-nan"           = .cs13_try(ms_import(P$nan1, "cosmic", "signatures")),
    "sig-emptycell"     = .cs13_try(ms_import(P$emptyc, "cosmic", "signatures")),
    "sig-allna"         = .cs13_try(ms_import(P$allna, "cosmic", "signatures")),
    "exp-x-list"        = .cs13_try(ms_export(list(), "cosmic", NULL)),
    "exp-x-df"          = .cs13_try(ms_export(data.frame(a = 1), "cosmic", NULL)),
    "exp-collide-Type"  = .cs13_try(ms_export(.cs13_mk_catalog(smp = c("sA", "Type")), "cosmic", NULL)),
    "exp-collide-MT"    = .cs13_try(ms_export(.cs13_mk_sig(cols = c("sig1", "MutationType")), "sigprofiler", NULL)),
    "file-missing"      = .cs13_try(ms_import(P$missing)),
    "file-null"         = .cs13_try(ms_import(NULL)),
    "file-empty"        = .cs13_try(ms_import("")),
    "file-na"           = .cs13_try(ms_import(NA_character_)),
    "file-vec"          = .cs13_try(ms_import(c(P$good, P$good))),
    "file-num"          = .cs13_try(ms_import(42)),
    "kind-junk"         = .cs13_try(ms_import(P$good, kind = "catalogs")),
    "file-emptyfile"    = .cs13_try(ms_import(P$emptyf)),
    "file-dir"          = suppressWarnings(.cs13_try(ms_import(P$dir))),
    NULL)
}

.cs13_lawrows <- function() {
  W1 <- .cs13_wn("1"); W96 <- .cs13_wn("96")
  FB <- function(recv) paste0(.CS13_CL_FILE, " | received: ", recv, " | ",
                              .CS13_CL_FILE_TAIL)
  data.frame(
    arm = c("opt-e-wtsi", "opt-e-upper", "opt-i-wtsi-missing",
            "opt-i-wtsi-good", "hdr-cosmic-kind", "hdr-cosmic-onecol",
            "hdr-sgp-wrong", "lbl-infer-miss", "pin-unknown-nope",
            "pin-unknown-true", "pin-mismatch", "cell-nonnum-abc",
            "wn-frac", "wn-neg", "wn-na", "wn-nan", "wn-inf", "wn-allna",
            "sig-nonneg", "sig-na", "sig-nan", "sig-emptycell", "sig-allna",
            "exp-x-list", "exp-x-df", "exp-collide-Type", "exp-collide-MT",
            "file-missing", "file-null", "file-empty", "file-na", "file-vec",
            "file-num", "kind-junk", "file-emptyfile", "file-dir"),
    face = c(rep("ms_export", 2), rep("ms_import", 6), rep("ms_import", 4),
             rep("ms_import", 6), rep("ms_import", 5), rep("ms_export", 4),
             rep("ms_import", 6), rep("ms_import", 3)),
    cls = c(rep(.CS13_CLASS_OPTION, 4), rep(.CS13_CLASS_INPUT, 14),
            rep(.CS13_CLASS_SIGN, 5), rep(.CS13_CLASS_INPUT, 10),
            rep(.CS13_CLASS_BASE, 3)),
    mode = c(rep("full", 27), "stable3", "full", "full", "full", "stable3",
             "full", "class-only", "class-only", "class-only"),
    clause = c(.CS13_CL_OPTION("wtsi"), .CS13_CL_OPTION("COSMIC"),
               .CS13_CL_OPTION("wtsi"), .CS13_CL_OPTION("wtsi"),
               .CS13_CL_HDR("cosmic", "Type", "'Kind', 'sA'"),
               .CS13_CL_HDR("cosmic", "Type", "'Type'"),
               .CS13_CL_HDR("sigprofiler", "MutationType", "'Type', 'sA', 'sB'"),
               .CS13_HDR_INFERMISS,
               .CS13_CL_PINUNKNOWN("NOPE"), .CS13_CL_PINUNKNOWN("TRUE"),
               .CS13_PINMISMATCH, .CS13_CELLABC,
               W1, W1, W1, W1, W1, W96,
               .CS13_SIGN_NONNEG, .CS13_SIGN_NAFIN, .CS13_SIGN_NAFIN,
               .CS13_SIGN_NAFIN, .CS13_SIGN_ALLNA,
               .CS13_XGATE("list"), .CS13_XGATE("data.frame"),
               .CS13_COLLIDE("cosmic", "Type", "Type"),
               .CS13_COLLIDE("sigprofiler", "MutationType", "MutationType"),
               paste0(.CS13_CL_FILE, " | ", .CS13_CL_FILE_TAIL),
               FB("(none)"), FB("''"), FB("'NA'"),
               paste0(.CS13_CL_FILE, " | ", .CS13_CL_FILE_TAIL),
               FB("'42'"),
               .CS13_LOCALE_ONLY, .CS13_LOCALE_ONLY, .CS13_LOCALE_ONLY),
    stringsAsFactors = FALSE, check.names = FALSE)
}

# ---------------------------------------------------------------------------
# The 13 acceptance arms: what the faces RETURN on planted truth. cls-only
# arms carry an empty detail; rendering arms carry the verbatim keys below
# (all MEASURED: probes 1-3 plus the quick/gate ledger 2026-11-22).
.CS13_SPECROWS <- function() {
  data.frame(
    arm = c("e1-df", "e3-df", "e10-write", "i-catalog", "i-sig",
            "i-sigprof-catalog", "accept-frac-sig", "accept-dup-catalog",
            "accept-dup-sig", "kind-cat-partial", "kind-sign-partial",
            "kind-vec-first", "rt-int-storage"),
    face = c("ms_export", "ms_export", "ms_export", "ms_import", "ms_import",
             "ms_import", "ms_import", "ms_import", "ms_import", "ms_import",
             "ms_import", "ms_import", "ms_export+import"),
    cls = c(.CS13_CLASS_DF, .CS13_CLASS_DF, "character", .CS13_CLASS_CATALOG,
            .CS13_CLASS_SIG, .CS13_CLASS_CATALOG, .CS13_CLASS_SIG,
            .CS13_CLASS_CATALOG, .CS13_CLASS_SIG, .CS13_CLASS_CATALOG,
            .CS13_CLASS_SIG, .CS13_CLASS_CATALOG, .CS13_CLASS_CATALOG),
    detail = c("hdr=Type;ncol=3", "hdr=MutationType;ncol=3",
      paste0("hdr=Type\\tfid;row1=A[C>A]A;tok-digits=22,22,22,22;",
             "tok-plant-equal=TRUE"),
      "dims=96x2;samps=sA,sB;channame=SBS96;prov-genome=imported;prov-format=cosmic",
      paste0("dims=96x2;exposures=2x0;exporownames=sA,sB;build=imported:",
             "sha256=5350e362193a3f1a7dcc181685fd52cf78de275b6dfa27c7736de",
             "59136eff9f5;n_samples=0;n_channels=96;channame=SBS96;",
             "chanhash=1edf6b63f9d98c7b6c62744d09d69889;hash-labels-recomp",
             "uted=1edf6b63f9d98c7b6c62744d09d69889;hashes-agree=TRUE;",
             "filehashA=5350e362193a3f1a7dcc181685fd52cf78de275b6dfa27c773",
             "6de59136eff9f5;filehashB=5350e362193a3f1a7dcc181685fd52cf78d",
             "e275b6dfa27c7736de59136eff9f5;kernels-agree=TRUE;",
             "build-carries-filehash=TRUE"),
      "(none)", "(none)", "(none)", "(none)", "(none)", "(none)", "(none)",
      "import-storage=integer;plant-storage=double;all-equal=TRUE;repair-identical=TRUE"),
    stringsAsFactors = FALSE, check.names = FALSE)
}

# the acceptance-arm live firings (returned values, never swallowed errors)
.cs13_specfire <- function(arm, P) {
  switch(arm,
    "e1-df"             = .cs13_try(ms_export(.cs13_mk_catalog(), "cosmic", NULL)),
    "e3-df"             = .cs13_try(ms_export(.cs13_mk_sig(), "sigprofiler", NULL)),
    "e10-write"        = .cs13_try(ms_export(
      .cs13_mk_sig("fid", .CS13_FID_PLANT), "cosmic",
      file.path(P$dir, "law-fid.tsv"))),
    "i-catalog"        = .cs13_try(ms_import(P$good)),
    "i-sig"            = .cs13_try(ms_import(P$good, "cosmic", "signatures")),
    "i-sigprof-catalog" = .cs13_try(ms_import(P$sgp, "sigprofiler")),
    "accept-frac-sig"  = .cs13_try(ms_import(P$fr, "cosmic", "signatures")),
    "accept-dup-catalog" = .cs13_try(ms_import(P$dup)),
    "accept-dup-sig"   = .cs13_try(ms_import(P$dup, "cosmic", "signatures")),
    "kind-cat-partial" = .cs13_try(ms_import(P$good, kind = "cat")),
    "kind-sign-partial" = .cs13_try(ms_import(P$good, kind = "sign")),
    "kind-vec-first"   = .cs13_try(ms_import(P$good, kind = c("catalog", "signatures"))),
    "rt-int-storage"   = .cs13_try({
      rp <- file.path(P$dir, "law-rt.tsv")
      ms_export(.cs13_mk_catalog(), "cosmic", rp)
      ms_import(rp)
    }),
    NULL)
}

# precedence discriminators: which law speaks when two could
.CS13_PRECROWS <- function() {
  data.frame(
    arm = c("prec-wtsi-first", "prec-cell-vs-whole-abc", "prec-cell-vs-whole-nan"),
    fires_cls = c(.CS13_CLASS_OPTION, .CS13_CLASS_INPUT, .CS13_CLASS_INPUT),
    fires_anchor = c("WTSI long format is deferred", .CS13_CELL_ANCHOR,
                     .CS13_WN_ANCHOR),
    anti_anchor = c(.CS13_FILE_ANCHOR, .CS13_WN_ANCHOR, .CS13_CELL_ANCHOR),
    stringsAsFactors = FALSE, check.names = FALSE)
}
.cs13_precfire <- function(arm, P) {
  switch(arm,
    "prec-wtsi-first"        = .cs13_try(ms_import(P$missing, "wtsi")),
    "prec-cell-vs-whole-abc" = .cs13_try(ms_import(P$nn)),
    "prec-cell-vs-whole-nan" = .cs13_try(ms_import(P$nan1)),
    NULL)
}

# scalars: registry bytes, enum bytes, plant checksum, fid drill scalars, RNG rails
.CS13_SCALAR_KEYS <- c("roster", "formats", "headers", "fid-n-diff",
                       "fid-first-diff-row", "fid-max-absdiff",
                       "plant-checksum", "rng-before", "rng-after")

# canonical text whose dual-kernel checksum rides in the scalars witness
.cs13_spec_text <- function()
  paste0(vapply(.CS13_SPECROWS()$arm, function(a) a, character(1L)),
         collapse = ";")

# ===========================================================================
# U1 -- runner rails: the witness exists and speaks the attestation idiom,
# reaching the package ONLY through the exported faces.
# ===========================================================================
test_that("runner speaks the exported-face rails", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  runner <- file.path(.ms_root, "bench", "scenarios",
                      "run_io_interop_witness.R")
  expect_true(file.exists(runner))
  src <- paste(readLines(runner, warn = FALSE), collapse = "\n")
  for (need in c("--file=", "[attest]", "OVERALL PASS", "ms_import(",
                 "ms_export(", "cs13_")) {
    expect_true(grepl(need, src, fixed = TRUE), info = need)
  }
  for (ban in c("msuiter:::", ".ms_io_resolve_table", ".ms_io_file_sha256",
                "msuiter_validate_", "expect_", "ms_calibration_grid",
                "ms_fit_bootstrap", "ms_calibration_sanity", "run_benchmark",
                "set.seed", "sample(", "download.file", "http")) {
    expect_false(grepl(ban, src, fixed = TRUE), info = ban)
  }
})

# ===========================================================================
# U2 -- witness existence and shape: five committed TSVs, non-zero, with the
# hard row-count gates and an all-finite-character census (no vacuous green).
# ===========================================================================
test_that("the five witnesses exist with hard shape gates", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  for (f in c("cs13_specs.tsv", "cs13_laws.tsv", "cs13_precedence.tsv",
              "cs13_fidelity.tsv", "cs13_scalars.tsv")) {
    expect_true(file.exists(.rs_out13(f)))
    expect_gt(file.size(.rs_out13(f)), 0)
  }
  sp <- .rs_tsv13("cs13_specs.tsv"); lw <- .rs_tsv13("cs13_laws.tsv")
  pr <- .rs_tsv13("cs13_precedence.tsv"); fd <- .rs_tsv13("cs13_fidelity.tsv")
  sc <- .rs_tsv13("cs13_scalars.tsv")
  expect_identical(nrow(sp), 13L)
  expect_identical(nrow(lw), 36L)
  expect_identical(nrow(pr), 3L)
  expect_identical(nrow(fd), 4L)
  expect_true("key" %in% names(sc) && "value" %in% names(sc))
  expect_true(all(sc$key %in% .CS13_SCALAR_KEYS))
  expect_identical(nrow(sc), length(.CS13_SCALAR_KEYS))
  for (df in list(sp, lw, pr, fd, sc)) {
    expect_true(all(vapply(df, is.character, logical(1L))))
    expect_false(any(vapply(df, function(cc) any(is.na(cc)), logical(1L))))
  }
})

# ===========================================================================
# U3 -- the specs witness mirrors the frozen table byte-for-byte (arm, face,
# class token, verbatim detail rendering).
# ===========================================================================
test_that("committed specs mirror the frozen table", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  sp <- .rs_tsv13("cs13_specs.tsv"); fr <- .CS13_SPECROWS()
  expect_identical(sp$arm, fr$arm)
  expect_identical(sp$face, fr$face)
  expect_identical(sp$cls, fr$cls)
  expect_identical(sp$detail, fr$detail)
})

# ===========================================================================
# U4 -- live replay of the acceptance arms: the shipped faces still RETURN
# exactly what the witnesses committed (class tokens + detail renderings).
# ===========================================================================
test_that("acceptance arms replay live through the faces", {
  P <- .cs13_plants(); fr <- .CS13_SPECROWS()
  for (i in seq_len(nrow(fr))) {
    arm <- fr$arm[i]
    r <- .cs13_specfire(arm, P)
    expect_false(inherits(r, "error"), info = arm)
    expect_identical(.cs13_cls(r), fr$cls[i], info = arm)
    if (nzchar(fr$detail[i])) {
      expect_identical(.cs13_detail(arm, P), fr$detail[i], info = arm)
    }
  }
})

# ===========================================================================
# U5 -- the laws witness mirrors the frozen law table: 36 arms, classes,
# adjudication modes, verbatim clauses.
# ===========================================================================
test_that("committed laws mirror the frozen law table", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  lw <- .rs_tsv13("cs13_laws.tsv"); fr <- .cs13_lawrows()
  expect_identical(lw$arm, fr$arm)
  expect_identical(lw$face, fr$face)
  expect_identical(lw$cls, fr$cls)
  expect_identical(lw$mode, fr$mode)
  expect_identical(lw$clause, fr$clause)
})

# ===========================================================================
# U6 -- live replay of the reject arms: each fires its committed class, and
# per mode the clause matches (full = verbatim; stable3 = every frozen
# bullet rides the live message; class-only = the base R message is
# locale-variable, class-committed only).
# ===========================================================================
test_that("reject arms replay live with their committed verdicts", {
  P <- .cs13_plants(); fr <- .cs13_lawrows()
  for (i in seq_len(nrow(fr))) {
    arm <- fr$arm[i]
    r <- .cs13_fire(arm, P)
    expect_true(inherits(r, "error"), info = arm)
    expect_identical(.cs13_cls(r), fr$cls[i], info = arm)
    if (!identical(fr$mode[i], "class-only")) {
      msg <- .cs13_msg(r)
      if (identical(fr$mode[i], "full")) {
        expect_identical(msg, fr$clause[i], info = arm)
      } else {
        for (bl in strsplit(fr$clause[i], " | ", fixed = TRUE)[[1L]]) {
          expect_true(grepl(bl, msg, fixed = TRUE),
                      info = paste0(arm, " :: ", bl))
        }
      }
    }
  }
})

# ===========================================================================
# U7 -- precedence discriminators: the RIGHT law speaks when two could.
# ===========================================================================
test_that("precedence discriminators speak the right law", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  P <- .cs13_plants(); pr <- .CS13_PRECROWS()
  cw <- .rs_tsv13("cs13_precedence.tsv")
  expect_identical(cw$arm, pr$arm)
  expect_identical(cw$fires_cls, pr$fires_cls)
  expect_identical(cw$fires_anchor, pr$fires_anchor)
  expect_identical(cw$anti_anchor, pr$anti_anchor)
  for (i in seq_len(nrow(pr))) {
    r <- .cs13_precfire(pr$arm[i], P)
    expect_true(inherits(r, "error"), info = pr$arm[i])
    expect_identical(.cs13_cls(r), pr$fires_cls[i], info = pr$arm[i])
    msg <- .cs13_msg(r)
    expect_true(grepl(pr$fires_anchor[i], msg, fixed = TRUE),
                info = pr$arm[i])
    expect_false(grepl(pr$anti_anchor[i], msg, fixed = TRUE),
                 info = pr$arm[i])
  }
})

# ===========================================================================
# U8 -- fidelity drill: the R-printer tokens are byte-committed (D11
# sanctioned); the %.20g renderings and the drift bits carry payload
# censuses only, never cross-platform byte-equals.
# ===========================================================================
test_that("the fidelity drill holds its byte and census posture", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  fd <- .rs_tsv13("cs13_fidelity.tsv")
  expect_identical(fd$token, .CS13_FID_TOKENS)
  for (cn in c("plant20", "import20", "direct20")) {
    v <- as.numeric(fd[[cn]])
    expect_false(any(is.na(v)), info = cn)
    expect_true(all(is.finite(v)), info = cn)
    expect_true(all(v > 0), info = cn)
  }
  for (cn in c("eqplant", "eqdirect", "allequal")) {
    expect_true(all(fd[[cn]] %in% c("TRUE", "FALSE")), info = cn)
  }
  expect_identical(fd$allequal, rep("TRUE", 4L))
  # live: the exported bytes must satisfy STRUCTURE and numeric identity --
  # the committed token strings are a sealing-platform census record: the
  # 17-significant-digit rendering of a halfway double drifts by an ULP
  # across platforms (witnessed on the windows fan-out leg) AND is not
  # round-trip secure even in one process (the …69 glyph re-exports as …68
  # on darwin), so no live byte-equality rides them -- the D11 posture.
  P <- .cs13_plants()
  fp <- file.path(P$dir, "law-fid.tsv")
  ms_export(.cs13_mk_sig("fid", .CS13_FID_PLANT), "cosmic", fp)
  rr <- readLines(fp)
  live_tokens <- vapply(seq_len(4L), function(k) {
    f <- strsplit(rr[k + 1L], "\t", fixed = TRUE)[[1L]]
    f[length(f)]
  }, character(1L))
  expect_identical(nchar(live_tokens), rep(22L, 4L))
  expect_true(isTRUE(all.equal(as.numeric(live_tokens), .CS13_FID_PLANT)))
  # the reader is faithful to the bytes it read (same-parser structural bit):
  # the 96-row column is the four live tokens' doubles recycled row-wise
  imp <- ms_import(fp, "cosmic", "signatures")
  direct <- as.numeric(live_tokens)
  expect_identical(as.vector(imp@signatures), rep(direct, times = 24L))
  expect_true(isTRUE(all.equal(as.vector(imp@signatures),
                               as.vector(matrix(.CS13_FID_PLANT, nrow = 96L)))))
})

# ===========================================================================
# U9 -- the provenance pair: build carries the file hash, the hash agrees
# under both governed kernels, the channel hash equals the recomputed label
# hash, and the exposures/n_samples zero pair is locked.
# ===========================================================================
test_that("the provenance pair is locked end to end", {
  P <- .cs13_plants()
  o <- ms_import(P$good, "cosmic", "signatures")
  bytes <- readBin(P$good, "raw", file.size(P$good))
  hA <- .ms_fit_sha256(bytes)
  hB <- digest::digest(bytes, algo = "sha256", serialize = FALSE)
  expect_identical(hA, hB)
  expect_identical(o@catalog_summary$build, paste0("imported:sha256=", hA))
  expect_identical(o@catalog_summary$n_samples, 0L)
  expect_identical(dim(o@exposures), c(2L, 0L))
  expect_identical(o@catalog_summary$channel_hash, msuiter_hash_labels(.cs13_lab()))
})

# ===========================================================================
# U10 -- scalars: registry and enum bytes verbatim, the plant checksum under
# both kernels over the canonical spec text, the fid drill scalars within
# census, and the RNG rails silent.
# ===========================================================================
test_that("scalars speak registry, checksum and RNG rails", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  sc <- .rs_tsv13("cs13_scalars.tsv")
  kv <- function(k) sc$value[match(k, sc$key)]
  expect_identical(kv("roster"), .CS13_TABLEROSTER)
  expect_identical(kv("formats"), .CS13_FORMATS)
  expect_identical(kv("headers"), .CS13_HEADERS)
  txt <- .cs13_spec_text()
  bytes <- charToRaw(txt)
  expect_identical(kv("plant-checksum"), .ms_fit_sha256(bytes))
  expect_identical(kv("plant-checksum"),
                   digest::digest(bytes, algo = "sha256", serialize = FALSE))
  expect_identical(kv("fid-n-diff"), "24")
  expect_identical(kv("fid-first-diff-row"), "1")
  expect_true(is.finite(as.numeric(kv("fid-max-absdiff"))))
  expect_true(abs(as.numeric(kv("fid-max-absdiff"))) < 1e-15)
  expect_identical(kv("rng-before"), "FALSE")
  expect_identical(kv("rng-after"), "FALSE")
})


