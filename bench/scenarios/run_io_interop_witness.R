# run_io_interop_witness.R -- the CS-13 io-interop-witness scenario
# (pillar 3).
#
# Mandate: plant synthetic registry-label TSV text and hand-picked rationals
# (the D3 law: zero COSMIC numeric matrices, zero real-data bytes, zero
# downloads, zero data objects -- "COSMIC" rides only as the format's NAME)
# and adjudicate the EXPORTED interop faces ms_import() and ms_export():
# the format enum with its [V]-discipline deferral clause, the
# option-before-file precedence, the file gate, the header-anchor law (the
# zero-data-column boundary included), the three-way registry-label law, the
# cell law versus the whole-number law two-level split, the signature-face
# downstream laws, and the certified export legs (header-collision, the
# 17-significant-digit fidelity posture, the provenance hash pair). Every
# arm is driven through the EXPORTED faces alone; the accepted returns, the
# abort classes and the fired bullets are the faces' own. The scenario is
# RNG-free, network-free and clock-free; the benchmark runner, the FFI shim
# and the DECLINED calibration family are never invoked here.
#
# Framing law: DECISION RECORD only. The witnesses under out/ are the
# committed verdict of what the shipped faces SAID on planted truth. Float
# posture (D11): integer, label, class and clause bytes are byte-committed;
# the ill-conditioned %.20g renderings and drift bits of the fidelity drill
# ride as payload censuses, never as cross-platform byte-equals.
#
# Rails: this runner carries the same frozen table as the law file
# (tests/testthat/test-scenario-io-interop-witness.R), mirrored
# byte-identically; every observed class and clause is rail-checked against
# the frozen bytes AS WE GO -- a drift fails the run before any witness is
# written. The witness bytes are written only after every payload census
# speaks; a byte-rerun must reproduce them identically.

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

options(cli.no_color = TRUE, width = 220L)

# -- frozen constants (mirrored byte-identically in the law test) ------------
RS_BULLET <- "\u2139"
CLASS_CATALOG <- "msuiter::MsCatalog"
CLASS_SIG <- "msuiter::MsSignature"
CLASS_DF <- "data.frame"
CLASS_INPUT <- "msuiter_error_input"
CLASS_OPTION <- "msuiter_error_option"
CLASS_SIGN <- "msuiter_error_signature"
CLASS_BASE <- "simpleError"

TABLE <- "SBS96"
TABLEROSTER <- paste0("SBS96=96,SBS192=192,SBS384=384,SBS1536=1536,",
                      "DBS78=78")
FORMATS <- "cosmic,sigprofiler"
HEADERS <- "cosmic=Type,sigprofiler=MutationType"

CL_OPTION <- function(received) {
  paste0("format must be one of the verified formats | WTSI long format is ",
         "deferred pending an upstream specimen ([V] discipline) | received: ",
         "'", received, "'; verified: cosmic, sigprofiler | see vignettes/",
         "articles/devlog-2026-10-04-M4-02-design-memo.qmd sections 2/4")
}
CL_FILE <- paste0("file must be a path to an existing file | ",
                  "ms_import() reads a catalog/signature TSV from disk")
CL_FILE_TAIL <- "pass the TSV path returned by ms_export()"
CL_HDR <- function(fmt, anchor, received) {
  bullet <- if (identical(fmt, "cosmic"))
    "the layout anchor is the bundled COSMIC v3.6 reference file"
  else
    "the layout anchor is the pinned SigProfilerAssignment specimen (tests fixture)"
  paste0(fmt, "-format files need a \"", anchor, "\" first header column | ",
         bullet, " | received header: ", received,
         " | pass a file written by ms_export(format = \"", fmt, "\")")
}
HDR_INFERMISS <- paste0("labels do not match any registry channel table ",
  "exactly | ms_import/ms_export accept only canonical-order registry ",
  "labels | rows: 96; first label: A[C>A]C | order the matrix by one of: ",
  "SBS96, SBS192, SBS384, SBS1536, DBS78")
CL_PINUNKNOWN <- function(received) {
  paste0("channel_table must name one of the registry tables | the table ",
         "pins the canonical label order | received: '", received,
         "' | use one of: SBS96, SBS192, SBS384, SBS1536, DBS78")
}
PINMISMATCH <- paste0("labels do not match the SBS96 canonical order | the ",
  "interop contract is exact registry order, no reordering | first ",
  "mismatch at row 1: A[C>A]C vs A[C>A]A | reorder the matrix with the ",
  "registry labels before export")
CELLABC <- paste0("cosmic-format data cells must be numeric | the interop ",
  "grid is numeric counts or probabilities; literal cells are ",
  "uninterpretable | offending cell: row 3 (A[C>A]G), column 1 (sA), ",
  "value 'abc' | repair the cell in the source file or re-export with ",
  "ms_export()")
wn <- function(entries) {
  paste0("catalog import needs finite non-negative whole-number counts | ",
         "a catalog is integer mutation counts | offending entries: ",
         entries, " | import probabilities with kind = \"signatures\"")
}
SIGN_NONNEG <- paste0("signatures must be non-negative | signatures and ",
  "exposures are non-negative by definition | offending cells: '5' | ",
  "check the engine output for sign errors")
SIGN_NAFIN <- paste0("signatures must not contain NA or non-finite values | ",
  "the FFI contract rejects NA | offending cells: '5' | fix the ",
  "upstream computation")
SIGN_ALLNA <- paste0("signatures must not contain NA or non-finite values | ",
  "the FFI contract rejects NA | offending cells: '1', '2', '3', '4', '5', ",
  "'6', '7', '8', '9', '10', ... (96 total) | fix the upstream computation")
XGATE <- function(received) {
  paste0("x must be an MsCatalog or an MsSignature | the interop face ",
         "exports channel x column matrices | received: ", received,
         " | pass a catalog (counts) or a signature set (probabilities)")
}
COLLIDE <- function(fmt, anchor, nm) {
  paste0("column names must not collide with the ", fmt, " header column ",
         "\"", anchor, "\" | the first exported column is the channel label ",
         "carrier | colliding names: ", nm, " | rename those ",
         "samples/signatures before exporting (a silent rename would not ",
         "round-trip)")
}
LOCALE_ONLY <- "[locale-variable base message; class-committed only]"
CELL_ANCHOR <- "data cells must be numeric"
WN_ANCHOR <- "needs finite non-negative whole-number counts"
FILE_ANCHOR <- "must be a path to an existing file"
FID_TOKENS <- c("1.2345678901234569e-01", "5.0000000000000000e-01",
                "3.3333333333333331e-01", "1.0000000000000002e+07")
FIDV <- c(0.123456789012345678, 0.500000000000000011,
          0.33333333333333331, 9999999.9999999999)

SHA_GOOD <- "5350e362193a3f1a7dcc181685fd52cf78de275b6dfa27c7736de59136e"
SHA_GOOD <- paste0(SHA_GOOD, "ff9f5")
CHANHASH <- "1edf6b63f9d98c7b6c62744d09d69889"

describe <- function(e) {
  m <- gsub("\n", " | ", paste(as.character(conditionMessage(e)),
                              collapse = " | "), fixed = TRUE)
  segs <- strsplit(m, " | ", fixed = TRUE)[[1L]]
  segs <- vapply(seq_along(segs), function(i) {
    s <- trimws(segs[i])
    # sub(fixed = TRUE) is a literal substring op on this base: anchored
    # patterns never match. Strip the two measured bullet renderings
    # (unicode theme, harness ASCII theme) by prefix instead.
    for (b in c(paste0(RS_BULLET, " "), "i ")) {
      if (startsWith(s, b)) s <- substring(s, nchar(b) + 1L)
    }
    trimws(s)
  }, character(1L))
  paste0(segs, collapse = " | ")
}
try1 <- function(expr) tryCatch(list(v = expr), error = identity)
obs_cls <- function(r) if (inherits(r, "error")) class(r)[1L] else
                        class(r$v)[1L]
obs_msg <- function(r) if (inherits(r, "error")) describe(r) else ""

# -- the plant builders (mirrored byte-identically in the law test) ---------
LAB <- as.character(.ms_io_channel_tables()[[TABLE]])

mk_catalog <- function(smp = c("sA", "sB")) {
  m <- matrix(seq_len(length(LAB) * length(smp)) %% 7L, nrow = length(LAB),
              ncol = length(smp), dimnames = list(LAB, smp))
  storage.mode(m) <- "double"
  ms_catalog(m, list(name = TABLE, labels = LAB), smp,
             provenance = list(genome = "SYNTH"))
}
mk_sig <- function(cols = c("sig1", "sig2"), vals = NULL) {
  m <- if (is.null(vals)) matrix(0.5, nrow = length(LAB), ncol = length(cols))
       else matrix(vals, nrow = length(LAB), ncol = length(cols))
  dimnames(m) <- list(LAB, cols)
  ms_signature(signatures = m,
               exposures = matrix(0, nrow = length(cols), ncol = 1L,
                                  dimnames = list(cols, "sA")),
               catalog_summary = msuiter_catalog_summary(
                 mk_catalog(smp = "sA")),
               engine = "cs13-witness", seed = 0)
}
wl <- function(lines, path) {
  # binary channel pins the EOL: plant bytes -- and the SHA-256 taken over
  # them -- must not ride the platform's text translation
  con <- file(path, open = "wb")
  on.exit(close(con))
  writeLines(lines, con)
  invisible(path)
}
write_tsv <- function(pd, nm, hdr, cols, rows) {
  p <- file.path(pd, nm)
  lines <- c(paste0(c(hdr, cols), collapse = "\t"),
             apply(rows, 1L, function(rw) paste0(unname(rw), collapse = "\t")))
  wl(lines, p)
  p
}
counts <- function(bad_val = NULL, bad_row = 5L) {
  v <- vapply(seq_along(LAB), function(i) as.character(i %% 4L),
              character(1L))
  if (!is.null(bad_val)) v[bad_row] <- bad_val
  cbind(LAB, v)
}
PD <- file.path(tempdir(TRUE), "cs13-run-plants")
dir.create(PD, showWarnings = FALSE)
W <- function(nm, ...) write_tsv(PD, nm, ...)
P <- new.env(parent = topenv())
P$dir <- PD
P$good <- W("good.tsv", "Type", c("sA", "sB"),
            cbind(LAB, counts()[, 2L], counts()[, 2L]))
P$sgp <- W("sgp.tsv", "MutationType", "sA", counts())
P$badh <- W("badh.tsv", "Kind", "sA", counts())
P$onecol <- file.path(PD, "onecol.tsv")
wl(c("Type", LAB), P$onecol)
revlab <- LAB
revlab[1L:2L] <- LAB[c(2L, 1L)]
P$mis <- W("mis.tsv", "Type", "sA", as.matrix(revlab))
P$nn <- W("nn.tsv", "Type", "sA", counts("abc", 3L))
P$fr <- W("fr.tsv", "Type", "sA", counts("1.5", 5L))
P$ng <- W("ng.tsv", "Type", "sA", counts("-1", 5L))
P$na1 <- W("na1.tsv", "Type", "sA", counts("NA", 5L))
P$nan1 <- W("nan1.tsv", "Type", "sA", counts("NaN", 5L))
P$infc <- W("infc.tsv", "Type", "sA", counts("Inf", 5L))
P$emptyc <- W("emptyc.tsv", "Type", "sA", counts("", 5L))
allna <- counts()
allna[, 2L] <- rep("NA", length(LAB))
P$allna <- W("allna.tsv", "Type", "sA", allna)
P$dup <- file.path(PD, "dup.tsv")
wl(c("Type\tsA\tsA",
     vapply(seq_along(LAB), function(i)
       paste0(LAB[i], "\t", i %% 4L, "\t", (i + 1L) %% 4L,
              collapse = ""), character(1L))), P$dup)
P$emptyf <- file.path(PD, "empty.tsv")
wl(character(0L), P$emptyf)
P$missing <- file.path(PD, "no-such.tsv")

# -- live detail renderings (the accepted-face echoes, verbatim keys) -------
detail <- function(arm) {
  esc <- function(x) gsub("\t", "\\t", x, fixed = TRUE)
  switch(arm,
    "e1-df" = {
      r <- try1(ms_export(mk_catalog(), "cosmic", NULL))
      paste0("hdr=", names(r$v)[1L], ";ncol=", ncol(r$v))
    },
    "e3-df" = {
      r <- try1(ms_export(mk_sig(), "sigprofiler", NULL))
      paste0("hdr=", names(r$v)[1L], ";ncol=", ncol(r$v))
    },
    "e10-write" = {
      fp <- file.path(PD, "run-fid.tsv")
      ms_export(mk_sig("fid", FIDV), "cosmic", fp)
      rr <- readLines(fp)
      toks <- vapply(seq_len(4L), function(k) {
        f <- strsplit(rr[k + 1L], "\t", fixed = TRUE)[[1L]]
        f[length(f)] }, character(1L))
      # Mirror of the law twin: the re-export identity bit is deliberately
      # absent (the 17-digit glyph is not round-trip secure on this base);
      # numeric faithfulness rides all.equal().
      paste0("hdr=", esc(rr[1L]),
             ";row1=", esc(strsplit(rr[2L], "\t", fixed = TRUE)[[1L]][1L]),
             ";tok-digits=", paste0(nchar(toks), collapse = ","),
             ";tok-plant-equal=", isTRUE(all.equal(as.numeric(toks), FIDV)))
    },
    "i-catalog" = {
      o <- try1(ms_import(P$good))$v
      paste0("dims=", paste(dim(o@counts), collapse = "x"),
             ";samps=", paste0(o@samples, collapse = ","),
             ";channame=", o@channels$name,
             ";prov-genome=", o@provenance$genome,
             ";prov-format=", o@provenance$format)
    },
    "i-sig" = {
      o <- try1(ms_import(P$good, "cosmic", "signatures"))$v
      cs <- o@catalog_summary
      bytes <- readBin(P$good, "raw", file.size(P$good))
      hA <- .ms_fit_sha256(bytes)
      hB <- digest::digest(bytes, algo = "sha256", serialize = FALSE)
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
      rp <- file.path(PD, "run-rt.tsv")
      ms_export(mk_catalog(), "cosmic", rp)
      o <- ms_import(rp)
      m2 <- o@counts
      storage.mode(m2) <- "double"
      paste0("import-storage=", storage.mode(o@counts),
             ";plant-storage=", storage.mode(mk_catalog()@counts),
             ";all-equal=", isTRUE(all.equal(o@counts, mk_catalog()@counts)),
             ";repair-identical=", identical(m2, mk_catalog()@counts))
    },
    "(none)")
}

# -- the frozen tables (mirrored from the law test) --------------------------
SPEC_ARMS <- c("e1-df", "e3-df", "e10-write", "i-catalog", "i-sig",
               "i-sigprof-catalog", "accept-frac-sig", "accept-dup-catalog",
               "accept-dup-sig", "kind-cat-partial", "kind-sign-partial",
               "kind-vec-first", "rt-int-storage")
SPEC_FACE <- c("ms_export", "ms_export", "ms_export", "ms_import", "ms_import",
               "ms_import", "ms_import", "ms_import", "ms_import", "ms_import",
               "ms_import", "ms_import", "ms_export+import")
SPEC_CLS <- c(CLASS_DF, CLASS_DF, "character", CLASS_CATALOG, CLASS_SIG,
              CLASS_CATALOG, CLASS_SIG, CLASS_CATALOG, CLASS_SIG,
              CLASS_CATALOG, CLASS_SIG, CLASS_CATALOG, CLASS_CATALOG)
SPEC_DETAIL <- c(
  "hdr=Type;ncol=3", "hdr=MutationType;ncol=3",
  paste0("hdr=Type\\tfid;row1=A[C>A]A;tok-digits=22,22,22,22;",
         "tok-plant-equal=TRUE"),
  "dims=96x2;samps=sA,sB;channame=SBS96;prov-genome=imported;prov-format=cosmic",
  paste0("dims=96x2;exposures=2x0;exporownames=sA,sB;build=imported:sha256=",
         SHA_GOOD, ";n_samples=0;n_channels=96;channame=SBS96;chanhash=",
         CHANHASH, ";hash-labels-recomputed=", CHANHASH,
         ";hashes-agree=TRUE;filehashA=", SHA_GOOD, ";filehashB=", SHA_GOOD,
         ";kernels-agree=TRUE;build-carries-filehash=TRUE"),
  "(none)", "(none)", "(none)", "(none)", "(none)", "(none)", "(none)",
  "import-storage=integer;plant-storage=double;all-equal=TRUE;repair-identical=TRUE")

specfire <- function(arm) {
  switch(arm,
    "e1-df" = try1(ms_export(mk_catalog(), "cosmic", NULL)),
    "e3-df" = try1(ms_export(mk_sig(), "sigprofiler", NULL)),
    "e10-write" = try1(ms_export(mk_sig("fid", FIDV), "cosmic",
                                  file.path(PD, "run-fid.tsv"))),
    "i-catalog" = try1(ms_import(P$good)),
    "i-sig" = try1(ms_import(P$good, "cosmic", "signatures")),
    "i-sigprof-catalog" = try1(ms_import(P$sgp, "sigprofiler")),
    "accept-frac-sig" = try1(ms_import(P$fr, "cosmic", "signatures")),
    "accept-dup-catalog" = try1(ms_import(P$dup)),
    "accept-dup-sig" = try1(ms_import(P$dup, "cosmic", "signatures")),
    "kind-cat-partial" = try1(ms_import(P$good, kind = "cat")),
    "kind-sign-partial" = try1(ms_import(P$good, kind = "sign")),
    "kind-vec-first" = try1(ms_import(P$good, kind = c("catalog", "signatures"))),
    "rt-int-storage" = try1({
      rp <- file.path(PD, "run-rt.tsv")
      ms_export(mk_catalog(), "cosmic", rp)
      ms_import(rp)
    }),
    NULL)
}

LAW_ARMS <- c("opt-e-wtsi", "opt-e-upper", "opt-i-wtsi-missing",
              "opt-i-wtsi-good", "hdr-cosmic-kind", "hdr-cosmic-onecol",
              "hdr-sgp-wrong", "lbl-infer-miss", "pin-unknown-nope",
              "pin-unknown-true", "pin-mismatch", "cell-nonnum-abc",
              "wn-frac", "wn-neg", "wn-na", "wn-nan", "wn-inf", "wn-allna",
              "sig-nonneg", "sig-na", "sig-nan", "sig-emptycell", "sig-allna",
              "exp-x-list", "exp-x-df", "exp-collide-Type", "exp-collide-MT",
              "file-missing", "file-null", "file-empty", "file-na", "file-vec",
              "file-num", "kind-junk", "file-emptyfile", "file-dir")
LAW_FACE <- c(rep("ms_export", 2), rep("ms_import", 6), rep("ms_import", 4),
              rep("ms_import", 6), rep("ms_import", 5), rep("ms_export", 4),
              rep("ms_import", 6), rep("ms_import", 3))
FB <- function(recv) paste0(CL_FILE, " | received: ", recv, " | ",
                            CL_FILE_TAIL)
LAW_CLS <- c(rep(CLASS_OPTION, 4), rep(CLASS_INPUT, 14), rep(CLASS_SIGN, 5),
             rep(CLASS_INPUT, 10), rep(CLASS_BASE, 3))
LAW_MODE <- c(rep("full", 27), "stable3", "full", "full", "full", "stable3",
              "full", "class-only", "class-only", "class-only")
LAW_CLAUSE <- c(CL_OPTION("wtsi"), CL_OPTION("COSMIC"), CL_OPTION("wtsi"),
                CL_OPTION("wtsi"),
                CL_HDR("cosmic", "Type", "'Kind', 'sA'"),
                CL_HDR("cosmic", "Type", "'Type'"),
                CL_HDR("sigprofiler", "MutationType", "'Type', 'sA', 'sB'"),
                HDR_INFERMISS, CL_PINUNKNOWN("NOPE"), CL_PINUNKNOWN("TRUE"),
                PINMISMATCH, CELLABC,
                wn("1"), wn("1"), wn("1"), wn("1"), wn("1"), wn("96"),
                SIGN_NONNEG, SIGN_NAFIN, SIGN_NAFIN, SIGN_NAFIN, SIGN_ALLNA,
                XGATE("list"), XGATE("data.frame"),
                COLLIDE("cosmic", "Type", "Type"),
                COLLIDE("sigprofiler", "MutationType", "MutationType"),
                paste0(CL_FILE, " | ", CL_FILE_TAIL),
                FB("(none)"), FB("''"), FB("'NA'"),
                paste0(CL_FILE, " | ", CL_FILE_TAIL), FB("'42'"),
                LOCALE_ONLY, LOCALE_ONLY, LOCALE_ONLY)

lawfire <- function(arm) {
  switch(arm,
    "opt-e-wtsi" = try1(ms_export(mk_catalog(), "wtsi", NULL)),
    "opt-e-upper" = try1(ms_export(mk_catalog(), "COSMIC", NULL)),
    "opt-i-wtsi-missing" = try1(ms_import(P$missing, "wtsi")),
    "opt-i-wtsi-good" = try1(ms_import(P$good, "wtsi")),
    "hdr-cosmic-kind" = try1(ms_import(P$badh)),
    "hdr-cosmic-onecol" = try1(ms_import(P$onecol)),
    "hdr-sgp-wrong" = try1(ms_import(P$good, "sigprofiler")),
    "lbl-infer-miss" = try1(ms_import(P$mis)),
    "pin-unknown-nope" = try1(ms_import(P$good, channel_table = "NOPE")),
    "pin-unknown-true" = try1(ms_import(P$good, channel_table = TRUE)),
    "pin-mismatch" = try1(ms_import(P$mis, channel_table = TABLE)),
    "cell-nonnum-abc" = try1(ms_import(P$nn)),
    "wn-frac" = try1(ms_import(P$fr)),
    "wn-neg" = try1(ms_import(P$ng)),
    "wn-na" = try1(ms_import(P$na1)),
    "wn-nan" = try1(ms_import(P$nan1)),
    "wn-inf" = try1(ms_import(P$infc)),
    "wn-allna" = try1(ms_import(P$allna)),
    "sig-nonneg" = try1(ms_import(P$ng, "cosmic", "signatures")),
    "sig-na" = try1(ms_import(P$na1, "cosmic", "signatures")),
    "sig-nan" = try1(ms_import(P$nan1, "cosmic", "signatures")),
    "sig-emptycell" = try1(ms_import(P$emptyc, "cosmic", "signatures")),
    "sig-allna" = try1(ms_import(P$allna, "cosmic", "signatures")),
    "exp-x-list" = try1(ms_export(list(), "cosmic", NULL)),
    "exp-x-df" = try1(ms_export(data.frame(a = 1), "cosmic", NULL)),
    "exp-collide-Type" = try1(ms_export(
      mk_catalog(smp = c("sA", "Type")), "cosmic", NULL)),
    "exp-collide-MT" = try1(ms_export(
      mk_sig(cols = c("sig1", "MutationType")), "sigprofiler", NULL)),
    "file-missing" = try1(ms_import(P$missing)),
    "file-null" = try1(ms_import(NULL)),
    "file-empty" = try1(ms_import("")),
    "file-na" = try1(ms_import(NA_character_)),
    "file-vec" = try1(ms_import(c(P$good, P$good))),
    "file-num" = try1(ms_import(42)),
    "kind-junk" = try1(ms_import(P$good, kind = "catalogs")),
    "file-emptyfile" = try1(ms_import(P$emptyf)),
    "file-dir" = try1(suppressWarnings(ms_import(P$dir))),
    NULL)
}

PREC_ARMS <- c("prec-wtsi-first", "prec-cell-vs-whole-abc",
               "prec-cell-vs-whole-nan")
PREC_FIRES <- c(CLASS_OPTION, CLASS_INPUT, CLASS_INPUT)
PREC_ANCHOR <- c("WTSI long format is deferred", CELL_ANCHOR, WN_ANCHOR)
PREC_ANTI <- c(FILE_ANCHOR, WN_ANCHOR, CELL_ANCHOR)
precfire <- function(arm) {
  switch(arm,
    "prec-wtsi-first" = try1(ms_import(P$missing, "wtsi")),
    "prec-cell-vs-whole-abc" = try1(ms_import(P$nn)),
    "prec-cell-vs-whole-nan" = try1(ms_import(P$nan1)),
    NULL)
}

# -- the rails ------------------------------------------------------------
n_rails <- 0L
n_fail <- 0L
rail <- function(nm, ok) {
  n_rails <<- n_rails + 1L
  if (!isTRUE(ok)) {
    n_fail <<- n_fail + 1L
    cat("FAIL|", nm, "\n", sep = "")
  }
}

rng0 <- exists(".Random.seed", inherits = TRUE)
cat("[begin] CS-13 io-interop-witness\n")

# -- witness: specs (acceptance arms as the faces returned them) -------------
sp_arm <- character(0L); sp_face <- character(0L); sp_cls <- character(0L)
sp_detail <- character(0L)
for (i in seq_along(SPEC_ARMS)) {
  arm <- SPEC_ARMS[i]
  r <- specfire(arm)
  rail(paste0("spec-", arm, "-returns"), !inherits(r, "error"))
  lc <- obs_cls(r); ld <- detail(arm)
  rail(paste0("spec-", arm, "-class"), identical(lc, SPEC_CLS[i]))
  if (nzchar(SPEC_DETAIL[i]))
    rail(paste0("spec-", arm, "-detail"), identical(ld, SPEC_DETAIL[i]))
  sp_arm <- c(sp_arm, arm); sp_face <- c(sp_face, SPEC_FACE[i])
  sp_cls <- c(sp_cls, lc); sp_detail <- c(sp_detail, ld)
}
specs_dat <- data.frame(arm = sp_arm, face = sp_face, cls = sp_cls,
                        detail = sp_detail, stringsAsFactors = FALSE)

# -- witness: laws (reject arms as the faces adjudicated them) ---------------
lw_arm <- character(0L); lw_face <- character(0L); lw_cls <- character(0L)
lw_mode <- character(0L); lw_clause <- character(0L)
for (i in seq_along(LAW_ARMS)) {
  arm <- LAW_ARMS[i]
  r <- lawfire(arm)
  rail(paste0("law-", arm, "-aborts"), inherits(r, "error"))
  lc <- obs_cls(r); lm <- obs_msg(r)
  rail(paste0("law-", arm, "-class"), identical(lc, LAW_CLS[i]))
  if (!identical(LAW_MODE[i], "class-only")) {
    if (identical(LAW_MODE[i], "full")) {
      rail(paste0("law-", arm, "-clause"), identical(lm, LAW_CLAUSE[i]))
    } else {
      rail(paste0("law-", arm, "-bullets"),
           all(vapply(strsplit(LAW_CLAUSE[i], " | ", fixed = TRUE)[[1L]],
                      function(b) grepl(b, lm, fixed = TRUE), logical(1L))))
    }
  }
  # stable3 arms commit the frozen stable bullets: the live echo beside them
  # is machine-volatile (temp paths) and may not be welded into a witness
  committed <- if (identical(LAW_MODE[i], "class-only")) LOCALE_ONLY
               else if (identical(LAW_MODE[i], "stable3")) LAW_CLAUSE[i]
               else lm
  lw_arm <- c(lw_arm, arm); lw_face <- c(lw_face, LAW_FACE[i])
  lw_cls <- c(lw_cls, lc); lw_mode <- c(lw_mode, LAW_MODE[i])
  lw_clause <- c(lw_clause, committed)
}
laws_dat <- data.frame(arm = lw_arm, face = lw_face, cls = lw_cls,
                       mode = lw_mode, clause = lw_clause,
                       stringsAsFactors = FALSE)

# -- witness: precedence discriminators --------------------------------------
pr_arm <- character(0L); pr_fires <- character(0L)
pr_anchor <- character(0L); pr_anti <- character(0L)
for (i in seq_along(PREC_ARMS)) {
  r <- precfire(PREC_ARMS[i])
  lc <- obs_cls(r); lm <- obs_msg(r)
  rail(paste0("prec-", PREC_ARMS[i], "-fires"),
       identical(lc, PREC_FIRES[i]) &&
       grepl(PREC_ANCHOR[i], lm, fixed = TRUE) &&
       !grepl(PREC_ANTI[i], lm, fixed = TRUE))
  pr_arm <- c(pr_arm, PREC_ARMS[i]); pr_fires <- c(pr_fires, lc)
  pr_anchor <- c(pr_anchor, PREC_ANCHOR[i]); pr_anti <- c(pr_anti, PREC_ANTI[i])
}
prec_dat <- data.frame(arm = pr_arm, fires_cls = pr_fires,
                       fires_anchor = pr_anchor, anti_anchor = pr_anti,
                       stringsAsFactors = FALSE)

# -- witness: fidelity drill ---------------------------------------------------
fp <- file.path(PD, "run-fid.tsv")
ms_export(mk_sig("fid", FIDV), "cosmic", fp)
rr <- readLines(fp)
live_tokens <- vapply(seq_len(4L), function(k) {
  f <- strsplit(rr[k + 1L], "\t", fixed = TRUE)[[1L]]
  f[length(f)]
}, character(1L))
rail("fid-tokens", identical(nchar(live_tokens), rep(22L, 4L)) &&
      isTRUE(all.equal(as.numeric(live_tokens), FIDV)))
imp <- ms_import(fp, "cosmic", "signatures")
iv <- as.vector(imp@signatures)
direct <- as.numeric(live_tokens)
diffrows <- which(iv != as.vector(matrix(FIDV, nrow = length(LAB))))
fid_arm <- paste0("fid-", seq_len(4L))
fid_tok <- live_tokens
fid_p20 <- vapply(seq_len(4L), function(k) sprintf("%.20g", FIDV[k]),
                  character(1L))
ui <- unique(iv)
fid_i20 <- vapply(seq_len(4L), function(k) sprintf("%.20g", ui[k]),
                  character(1L))
fid_d20 <- vapply(seq_len(4L), function(k) sprintf("%.20g", direct[k]),
                  character(1L))
fid_eqp <- vapply(seq_len(4L), function(k) paste0(identical(ui[k], FIDV[k])),
                  character(1L))
fid_eqd <- vapply(seq_len(4L), function(k) paste0(identical(direct[k], ui[k])),
                  character(1L))
fid_all <- rep(paste0(isTRUE(all.equal(iv, as.vector(matrix(FIDV,
                     nrow = length(LAB)))))), 4L)
fid_dat <- data.frame(arm = fid_arm, token = fid_tok, plant20 = fid_p20,
                      import20 = fid_i20, direct20 = fid_d20,
                      eqplant = fid_eqp, eqdirect = fid_eqd,
                      allequal = fid_all, stringsAsFactors = FALSE)
rail("fid-reader-faithful",
     identical(iv, rep(direct, times = 24L)))
rail("fid-allequal", all(fid_all == "TRUE"))

# -- witness: scalars ---------------------------------------------------------
roster_bytes <- paste0(vapply(names(.ms_io_channel_tables()), function(tn)
  paste0(tn, "=", length(.ms_io_channel_tables()[[tn]])), character(1L)),
  collapse = ",")
rail("roster-bytes", identical(roster_bytes, TABLEROSTER))
# the enum and anchor bytes are cross-checked LIVE through the faces' own
# clauses -- no reach-through to the faces' internals
m_opt <- obs_msg(lawfire("opt-e-wtsi"))
rail("formats-bytes-live", grepl("verified: cosmic, sigprofiler", m_opt,
                                 fixed = TRUE))
m_hdr <- obs_msg(lawfire("hdr-cosmic-kind"))
m_sgp <- obs_msg(lawfire("hdr-sgp-wrong"))
rail("headers-bytes-live",
     grepl('need a "Type"', m_hdr, fixed = TRUE) &&
     grepl('need a "MutationType"', m_sgp, fixed = TRUE))
spec_txt <- paste0(SPEC_ARMS, collapse = ";")
ck_a <- .ms_fit_sha256(charToRaw(spec_txt))
ck_b <- digest::digest(charToRaw(spec_txt), algo = "sha256", serialize = FALSE)
rail("plant-checksum-kernels", identical(ck_a, ck_b))
rng1 <- exists(".Random.seed", inherits = TRUE)
scal_dat <- data.frame(
  key = c("roster", "formats", "headers", "fid-n-diff", "fid-first-diff-row",
          "fid-max-absdiff", "plant-checksum", "rng-before", "rng-after"),
  value = c(roster_bytes, FORMATS, HEADERS,
            paste0(length(diffrows)),
            paste0(if (length(diffrows)) diffrows[1L] else NA_integer_),
            sprintf("%.20g", max(abs(iv - as.vector(matrix(FIDV,
                                nrow = length(LAB)))))),
            ck_a, paste0(rng0), paste0(rng1)),
  stringsAsFactors = FALSE)

# -- payload censuses (every column character, no NA, no stray delimiter) ----
census <- function(df) {
  is.data.frame(df) && nrow(df) > 0L &&
    all(vapply(df, is.character, logical(1L))) &&
    !any(vapply(df, function(cc) any(is.na(cc)), logical(1L)))
}
rail("specs-shape", nrow(specs_dat) == 13L && census(specs_dat))
rail("laws-shape", nrow(laws_dat) == 36L && census(laws_dat))
rail("prec-shape", nrow(prec_dat) == 3L && census(prec_dat))
rail("fid-shape", nrow(fid_dat) == 4L && census(fid_dat))
rail("scal-shape", nrow(scal_dat) == 9L && census(scal_dat))

# -- attestation face ---------------------------------------------------------
cat("[attest] FACE-only adjudication: returns, classes and clauses are the\n")
cat("[attest]   exported interop faces' own; no .ms_io_ internals beyond the\n")
cat("[attest]   sanctioned label source, no validator reach-through, no\n")
cat("[attest]   hand-rolled parsing of the verdicts.\n")
cat("[attest] D3: all plants are synthetic registry-label text and hand-picked\n")
cat("[attest]   rationals; zero COSMIC numeric matrices; downloads zero.\n")
cat("[attest] D11 posture: class/label/integer/clause bytes are byte-committed;\n")
cat("[attest]   the %.20g renderings and drift bits of the fidelity drill ride\n")
cat("[attest]   as payload censuses, never as cross-platform byte-equals.\n")
cat("[attest] The plant checksum re-hashes through BOTH governed SHA-256\n")
cat("[attest]   kernels (canonical pure-R and the digest accelerator).\n")
cat("[attest] RNG rails (.Random.seed presence): before = ", rng0, ", after = ", rng1,
    "\n", sep = "")
cat("[attest] The benchmark runner, the FFI shim and the DECLINED calibration\n")
cat("[attest]   family are never invoked here.\n")

# -- commit (all censuses spoke first) ----------------------------------------
if (!(census(specs_dat) && census(laws_dat) && census(prec_dat) &&
       census(fid_dat) && census(scal_dat))) {
  cat("OVERALL FAIL -- payload census refused a witness write\n")
  quit(status = 1L)
}
dir.create(OUT, showWarnings = FALSE)
.wtab <- function(nm, df) {
  write.table(df, file.path(OUT, nm), sep = "\t", quote = FALSE,
              row.names = FALSE, na = "")
}
.wtab("cs13_specs.tsv", specs_dat)
.wtab("cs13_laws.tsv", laws_dat)
.wtab("cs13_precedence.tsv", prec_dat)
.wtab("cs13_fidelity.tsv", fid_dat)
.wtab("cs13_scalars.tsv", scal_dat)

cat("\n", if (identical(n_fail, 0L)) "OVERALL PASS" else "OVERALL FAIL",
    " (", n_rails, " adjudications, ", n_fail, " failed)\n", sep = "")
quit(status = if (identical(n_fail, 0L)) 0L else 1L)
