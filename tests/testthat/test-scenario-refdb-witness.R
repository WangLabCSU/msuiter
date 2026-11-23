# test-scenario-refdb-witness.R -- the CS-15 refdb-witness law units
# (pillar 3). The scenario plants synthetic R objects (the D3 law: zero
# COSMIC numeric matrices, zero real-data bytes, zero downloads -- build and
# class labels ride only as FORMAT NAMES) and adjudicates the EXPORTED
# ms_refdb() face: the container admission laws (non-empty named list, the
# numeric-matrix law, the label-key dimnames law, the NA/non-finite ban, the
# non-negative law, the first-matrix channel authority), the governance-
# metadata laws (the named-list law, the required-field roster, the four
# single-non-empty-string fields, the build_independent bool, the build
# string-or-NA law, the A13 cross-field clause, the lowercase sha256 policy,
# the availability no-NA law), the double-gate split between the S7 property
# gates and the container validator, the precedence discriminators and the
# degenerate boundaries. The witness bytes under bench/scenarios/out/
# (cs15_specs.tsv, cs15_laws.tsv, cs15_precedence.tsv, cs15_degenerates.tsv,
# cs15_scalars.tsv) are the committed verdict: a drift in a fired clause, an
# observed error class, an accepted shape or the precedence order reddens
# here before print. The plants are synthetic -- no RNG, no network, no
# COSMIC bytes; the lane NEVER calls the benchmark driver, the declined
# calibration family, or any internal of the face (banned words, grepped).
# Framing law: DECISION RECORD only. What the face says on planted truth --
# the accepted shapes, the abort classes, the fired bullets -- is an
# OBSERVED, COMMITTED record, never a fidelity claim beyond what was
# measured. Cross-platform posture (D11): integer, label, logical, class
# and clause bytes are byte-committed; the face produces no float payload
# columns (the matrices carry cell values only through the validator, which
# is a verdict, not a print), so no float glyph rides any witness.
# The frozen block and the shared code block below are MINTED mechanically
# from the observed probe ledger (gen-frozen.cs15.R / probe-cs15.R); neither
# is ever hand-edited in place.

.rs_out15 <- function(fname) {
  file.path(.ms_root, "bench", "scenarios", "out", fname)
}

# The committed tables are written quote-free; quote = "" keeps every
# double quote inside the clauses literal on read.
.rs_tsv15 <- function(fname) {
  read.csv(.rs_out15(fname), header = TRUE, sep = "\t",
           stringsAsFactors = FALSE, na.strings = "", colClasses = "character",
           quote = "")
}

## <<CS15-FROZEN-BEGIN>>  (minted mechanically from the observed ledger
##    2026-11-23; DO NOT hand-edit: regenerate via gen-frozen.cs15.R) ##
.CS15_LAW_ARMS <- c("obs-zero-cols-rejected", "rej-mat-empty", "rej-mat-notlist", "rej-mat-null", "rej-mat-unnamed", "rej-mat-partial-name", "rej-mat-vector", "rej-mat-character", "rej-mat-dataframe", "rej-mat-rownames", "rej-mat-colnames", "rej-mat-nodimnames", "rej-mat-na", "rej-mat-nan", "rej-mat-inf", "rej-mat-negative", "rej-channels-disagree", "rej-channels-subset", "rej-meta-notlist", "rej-meta-unnamed", "rej-meta-emptyname", "rej-meta-absent-one", "rej-meta-absent-two", "rej-field-version-empty", "rej-field-version-na", "rej-field-version-multi", "rej-field-version-num", "rej-field-class-empty", "rej-field-schema-na", "rej-field-license-multi", "rej-indep-na", "rej-indep-num", "rej-indep-str", "rej-build-empty", "rej-build-empty-declared", "rej-build-num", "rej-build-multi", "rej-a13-undeclared", "rej-sha-upper", "rej-sha-short", "rej-sha-nonhex", "rej-sha-num", "rej-sha-na", "rej-avail-na", "rej-avail-num", "rej-avail-logical")
.CS15_LAW_CLS <- c("msuiter_error_refdb", "msuiter_error_refdb", "simpleError", "simpleError", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "simpleError", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb")
.CS15_LAW_MODE <- c("full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full")
.CS15_LAW_CLAUSES <- list()
.CS15_LAW_CLAUSES[["obs-zero-cols-rejected"]] <- paste0("reference matrix 'core' must carry rownames a",
            "nd colnames | labels are the only legal match",
            "ing key (never position) | rownames missing: ",
            "FALSE; colnames missing: TRUE | set the matri",
            "x dimnames")
.CS15_LAW_CLAUSES[["rej-mat-empty"]] <- paste0("matrices must be a non-empty named list | an ",
            "MsRefDb bundles at least one reference signat",
            "ure matrix | received: list of length 0 | pas",
            "s the reference matrices as a named list")
.CS15_LAW_CLAUSES[["rej-mat-notlist"]] <- paste0("<msuiter::MsRefDb> object properties are inva",
            "lid: | - @matrices must be <list>, not <integ",
            "er>")
.CS15_LAW_CLAUSES[["rej-mat-null"]] <- paste0("<msuiter::MsRefDb> object properties are inva",
            "lid: | - @matrices must be <list>, not <NULL>")
.CS15_LAW_CLAUSES[["rej-mat-unnamed"]] <- paste0("every reference matrix must be named | matrix",
            " names identify reference sets (e.g. PCAWG) |",
            " names: (none) | name every list element")
.CS15_LAW_CLAUSES[["rej-mat-partial-name"]] <- paste0("every reference matrix must be named | matrix",
            " names identify reference sets (e.g. PCAWG) |",
            " names: 'core', '' | name every list element")
.CS15_LAW_CLAUSES[["rej-mat-vector"]] <- paste0("reference matrix 'core' must be a numeric mat",
            "rix | reference signatures are channel-space ",
            "matrices | received: integer | pass numeric m",
            "atrices with full dimnames")
.CS15_LAW_CLAUSES[["rej-mat-character"]] <- paste0("reference matrix 'core' must be a numeric mat",
            "rix | reference signatures are channel-space ",
            "matrices | received: matrix | pass numeric ma",
            "trices with full dimnames")
.CS15_LAW_CLAUSES[["rej-mat-dataframe"]] <- paste0("reference matrix 'core' must be a numeric mat",
            "rix | reference signatures are channel-space ",
            "matrices | received: data.frame | pass numeri",
            "c matrices with full dimnames")
.CS15_LAW_CLAUSES[["rej-mat-rownames"]] <- paste0("reference matrix 'core' must carry rownames a",
            "nd colnames | labels are the only legal match",
            "ing key (never position) | rownames missing: ",
            "TRUE; colnames missing: FALSE | set the matri",
            "x dimnames")
.CS15_LAW_CLAUSES[["rej-mat-colnames"]] <- paste0("reference matrix 'core' must carry rownames a",
            "nd colnames | labels are the only legal match",
            "ing key (never position) | rownames missing: ",
            "FALSE; colnames missing: TRUE | set the matri",
            "x dimnames")
.CS15_LAW_CLAUSES[["rej-mat-nodimnames"]] <- paste0("reference matrix 'core' must carry rownames a",
            "nd colnames | labels are the only legal match",
            "ing key (never position) | rownames missing: ",
            "TRUE; colnames missing: TRUE | set the matrix",
            " dimnames")
.CS15_LAW_CLAUSES[["rej-mat-na"]] <- paste0("reference matrix 'core' must not contain NA o",
            "r non-finite values | the FFI contract reject",
            "s NA | offending cells: '2' | fix the referen",
            "ce matrix source")
.CS15_LAW_CLAUSES[["rej-mat-nan"]] <- paste0("reference matrix 'core' must not contain NA o",
            "r non-finite values | the FFI contract reject",
            "s NA | offending cells: '5' | fix the referen",
            "ce matrix source")
.CS15_LAW_CLAUSES[["rej-mat-inf"]] <- paste0("reference matrix 'core' must not contain NA o",
            "r non-finite values | the FFI contract reject",
            "s NA | offending cells: '8' | fix the referen",
            "ce matrix source")
.CS15_LAW_CLAUSES[["rej-mat-negative"]] <- paste0("reference matrix 'core' must be non-negative ",
            "| reference signatures are non-negative by de",
            "finition | offending cells: '3' | check the r",
            "eference matrix source")
.CS15_LAW_CLAUSES[["rej-channels-disagree"]] <- paste0("reference matrices must share the same channe",
            "l labels | channel labels are matched by labe",
            "l, element by element | matrix 'alt' disagree",
            "s; offending labels: 'X[C>X]X' | project all ",
            "matrices onto one common channel space")
.CS15_LAW_CLAUSES[["rej-channels-subset"]] <- paste0("reference matrices must share the same channe",
            "l labels | channel labels are matched by labe",
            "l, element by element | matrix 'small' disagr",
            "ees; offending labels: (none) | project all m",
            "atrices onto one common channel space")
.CS15_LAW_CLAUSES[["rej-meta-notlist"]] <- paste0("<msuiter::MsRefDb> object properties are inva",
            "lid: | - @metadata must be <list>, not <integ",
            "er>")
.CS15_LAW_CLAUSES[["rej-meta-unnamed"]] <- paste0("metadata must be a named list | governance fi",
            "elds: version, class, build, schema_version, ",
            "sha256, license, build_independent, availabil",
            "ity | received: list | provide the governance",
            " metadata")
.CS15_LAW_CLAUSES[["rej-meta-emptyname"]] <- paste0("metadata must be a named list | governance fi",
            "elds: version, class, build, schema_version, ",
            "sha256, license, build_independent, availabil",
            "ity | received: list | provide the governance",
            " metadata")
.CS15_LAW_CLAUSES[["rej-meta-absent-one"]] <- paste0("reference metadata is missing governance fiel",
            "ds | governance fields: version, class, build",
            ", schema_version, sha256, license, build_inde",
            "pendent, availability | missing: 'license' | ",
            "record the missing field(s) in metadata")
.CS15_LAW_CLAUSES[["rej-meta-absent-two"]] <- paste0("reference metadata is missing governance fiel",
            "ds | governance fields: version, class, build",
            ", schema_version, sha256, license, build_inde",
            "pendent, availability | missing: 'build', 'sh",
            "a256' | record the missing field(s) in metada",
            "ta")
.CS15_LAW_CLAUSES[["rej-field-version-empty"]] <- paste0("metadata field 'version' must be a single non",
            "-empty string | governance fields pin the ref",
            "erence set identity | received: '' | record t",
            "he field as a single string")
.CS15_LAW_CLAUSES[["rej-field-version-na"]] <- paste0("metadata field 'version' must be a single non",
            "-empty string | governance fields pin the ref",
            "erence set identity | received: 'NA' | record",
            " the field as a single string")
.CS15_LAW_CLAUSES[["rej-field-version-multi"]] <- paste0("metadata field 'version' must be a single non",
            "-empty string | governance fields pin the ref",
            "erence set identity | received: '1', '2' | re",
            "cord the field as a single string")
.CS15_LAW_CLAUSES[["rej-field-version-num"]] <- paste0("metadata field 'version' must be a single non",
            "-empty string | governance fields pin the ref",
            "erence set identity | received: '1' | record ",
            "the field as a single string")
.CS15_LAW_CLAUSES[["rej-field-class-empty"]] <- paste0("metadata field 'class' must be a single non-e",
            "mpty string | governance fields pin the refer",
            "ence set identity | received: '' | record the",
            " field as a single string")
.CS15_LAW_CLAUSES[["rej-field-schema-na"]] <- paste0("metadata field 'schema_version' must be a sin",
            "gle non-empty string | governance fields pin ",
            "the reference set identity | received: 'NA' |",
            " record the field as a single string")
.CS15_LAW_CLAUSES[["rej-field-license-multi"]] <- paste0("metadata field 'license' must be a single non",
            "-empty string | governance fields pin the ref",
            "erence set identity | received: 'CC0-1.0', 'C",
            "C-BY-4.0' | record the field as a single stri",
            "ng")
.CS15_LAW_CLAUSES[["rej-indep-na"]] <- paste0("metadata field 'build_independent' must be a ",
            "single TRUE or FALSE | build independence is ",
            "an explicit declaration (A13) | received: 'NA",
            "' | set build_independent = TRUE only for bui",
            "ld-agnostic sets")
.CS15_LAW_CLAUSES[["rej-indep-num"]] <- paste0("metadata field 'build_independent' must be a ",
            "single TRUE or FALSE | build independence is ",
            "an explicit declaration (A13) | received: '1'",
            " | set build_independent = TRUE only for buil",
            "d-agnostic sets")
.CS15_LAW_CLAUSES[["rej-indep-str"]] <- paste0("metadata field 'build_independent' must be a ",
            "single TRUE or FALSE | build independence is ",
            "an explicit declaration (A13) | received: 'TR",
            "UE' | set build_independent = TRUE only for b",
            "uild-agnostic sets")
.CS15_LAW_CLAUSES[["rej-build-empty"]] <- paste0("metadata field 'build' must be a single strin",
            "g, or NA if build independent | NA build is l",
            "egal only together with build_independent = T",
            "RUE | received: '' | record the genome build,",
            " or declare build independence")
.CS15_LAW_CLAUSES[["rej-build-empty-declared"]] <- paste0("metadata field 'build' must be a single strin",
            "g, or NA if build independent | NA build is l",
            "egal only together with build_independent = T",
            "RUE | received: '' | record the genome build,",
            " or declare build independence")
.CS15_LAW_CLAUSES[["rej-build-num"]] <- paste0("metadata field 'build' must be a single strin",
            "g, or NA if build independent | NA build is l",
            "egal only together with build_independent = T",
            "RUE | received: '38' | record the genome buil",
            "d, or declare build independence")
.CS15_LAW_CLAUSES[["rej-build-multi"]] <- paste0("metadata field 'build' must be a single strin",
            "g, or NA if build independent | NA build is l",
            "egal only together with build_independent = T",
            "RUE | received: 'GRCh38', 'GRCh37' | record t",
            "he genome build, or declare build independenc",
            "e")
.CS15_LAW_CLAUSES[["rej-a13-undeclared"]] <- paste0("a missing build must be declared via build_in",
            "dependent = TRUE | build-agnostic reference s",
            "ets must say so explicitly (A13) | build = NA",
            ", build_independent = FALSE | record the buil",
            "d, or set build_independent = TRUE")
.CS15_LAW_CLAUSES[["rej-sha-upper"]] <- paste0("metadata field 'sha256' must be a sha256 hex ",
            "digest | the digest pins the reference conten",
            "t (A13 manifest) | received: 'AAAAAAAAAAAAAAA",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            "AAAA' | record the sha256 of the reference so",
            "urce")
.CS15_LAW_CLAUSES[["rej-sha-short"]] <- paste0("metadata field 'sha256' must be a sha256 hex ",
            "digest | the digest pins the reference conten",
            "t (A13 manifest) | received: 'aaaaaaaaaaaaaaa",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "aaa' | record the sha256 of the reference sou",
            "rce")
.CS15_LAW_CLAUSES[["rej-sha-nonhex"]] <- paste0("metadata field 'sha256' must be a sha256 hex ",
            "digest | the digest pins the reference conten",
            "t (A13 manifest) | received: 'ggggggggggggggg",
            "ggggggggggggggggggggggggggggggggggggggggggggg",
            "gggg' | record the sha256 of the reference so",
            "urce")
.CS15_LAW_CLAUSES[["rej-sha-num"]] <- paste0("metadata field 'sha256' must be a sha256 hex ",
            "digest | the digest pins the reference conten",
            "t (A13 manifest) | received: '42' | record th",
            "e sha256 of the reference source")
.CS15_LAW_CLAUSES[["rej-sha-na"]] <- paste0("metadata field 'sha256' must be a sha256 hex ",
            "digest | the digest pins the reference conten",
            "t (A13 manifest) | received: 'NA' | record th",
            "e sha256 of the reference source")
.CS15_LAW_CLAUSES[["rej-avail-na"]] <- paste0("metadata field 'availability' must be a chara",
            "cter vector without NA | availability lists t",
            "he builds with official reference sets | rece",
            "ived: character of length 2 | list known buil",
            "ds, or pass character(0)")
.CS15_LAW_CLAUSES[["rej-avail-num"]] <- paste0("metadata field 'availability' must be a chara",
            "cter vector without NA | availability lists t",
            "he builds with official reference sets | rece",
            "ived: integer of length 1 | list known builds",
            ", or pass character(0)")
.CS15_LAW_CLAUSES[["rej-avail-logical"]] <- paste0("metadata field 'availability' must be a chara",
            "cter vector without NA | availability lists t",
            "he builds with official reference sets | rece",
            "ived: logical of length 1 | list known builds",
            ", or pass character(0)")
.CS15_SPEC_ARMS <- c("sp-canonical", "sp-two-matrices", "sp-na-declared", "sp-availability-zero", "sp-availability-multi", "sp-integer-matrix", "sp-1x1", "sp-dup-colnames")
.CS15_SPEC_CLS <- c("msuiter::MsRefDb", "msuiter::MsRefDb", "msuiter::MsRefDb", "msuiter::MsRefDb", "msuiter::MsRefDb", "msuiter::MsRefDb", "msuiter::MsRefDb", "msuiter::MsRefDb")
.CS15_SPEC_DETAILS <- list()
.CS15_SPEC_DETAILS[["sp-canonical"]] <- paste0("nmat=1;names=core;nrow=4;ncol=2;class=SBS;ver",
            "sion=1;build=GRCh38;indep=FALSE;avail=GRCh38;",
            "fmt=<MsRefDb> class: SBS | version: 1 | 1 mat",
            "rices")
.CS15_SPEC_DETAILS[["sp-two-matrices"]] <- paste0("nmat=2;names=core,ext;nrow=4;ncol=2;class=SBS",
            ";version=1;build=GRCh38;indep=FALSE;avail=GRC",
            "h38;fmt=<MsRefDb> class: SBS | version: 1 | 2",
            " matrices")
.CS15_SPEC_DETAILS[["sp-na-declared"]] <- paste0("nmat=1;names=core;nrow=4;ncol=2;class=SBS;ver",
            "sion=1;build=NA;indep=TRUE;avail=GRCh38;fmt=<",
            "MsRefDb> class: SBS | version: 1 | 1 matrices")
.CS15_SPEC_DETAILS[["sp-availability-zero"]] <- paste0("nmat=1;names=core;nrow=4;ncol=2;class=SBS;ver",
            "sion=1;build=GRCh38;indep=FALSE;avail=;fmt=<M",
            "sRefDb> class: SBS | version: 1 | 1 matrices")
.CS15_SPEC_DETAILS[["sp-availability-multi"]] <- paste0("nmat=1;names=core;nrow=4;ncol=2;class=SBS;ver",
            "sion=1;build=GRCh38;indep=FALSE;avail=GRCh38+",
            "GRCh37;fmt=<MsRefDb> class: SBS | version: 1 ",
            "| 1 matrices")
.CS15_SPEC_DETAILS[["sp-integer-matrix"]] <- paste0("nmat=1;names=core;nrow=4;ncol=2;class=SBS;ver",
            "sion=1;build=GRCh38;indep=FALSE;avail=GRCh38;",
            "fmt=<MsRefDb> class: SBS | version: 1 | 1 mat",
            "rices")
.CS15_SPEC_DETAILS[["sp-1x1"]] <- paste0("nmat=1;names=one;nrow=1;ncol=1;class=SBS;vers",
            "ion=1;build=GRCh38;indep=FALSE;avail=GRCh38;f",
            "mt=<MsRefDb> class: SBS | version: 1 | 1 matr",
            "ices")
.CS15_SPEC_DETAILS[["sp-dup-colnames"]] <- paste0("nmat=1;names=core;nrow=4;ncol=2;class=SBS;ver",
            "sion=1;build=GRCh38;indep=FALSE;avail=GRCh38;",
            "fmt=<MsRefDb> class: SBS | version: 1 | 1 mat",
            "rices")
.CS15_PLANT <- list()
.CS15_PLANT[["M1"]] <- c("structure(c(0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5), dim = c(4L, 2L), dimnames = list(c(\"A[C>A]A\", \"C[C>A]A\", \"G[C>G]C\", \"T[C>T]T\"), c(\"SBS1\", \"SBS5\")))")
.CS15_PLANT[["M2"]] <- c("structure(c(1, 2, 3, 4, 5, 6, 7, 8), dim = c(4L, 2L), dimnames = list(c(\"A[C>A]A\", \"C[C>A]A\", \"G[C>G]C\", \"T[C>T]T\"), c(\"SBS1\", \"SBS5\")))")
.CS15_PLANT[["META"]] <- c("list(version = \"1\", class = \"SBS\", build = \"GRCh38\", schema_version = \"1\", sha256 = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\", license = \"CC0-1.0\", build_independent = FALSE, availability = \"GRCh38\")")
.CS15_PLANT[["CH"]] <- c("c(\"A[C>A]A\", \"C[C>A]A\", \"G[C>G]C\", \"T[C>T]T\")")
.CS15_PLANT[["SN"]] <- c("c(\"SBS1\", \"SBS5\")")
.CS15_PLANT[["SHA64"]] <- c("\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"")
.CS15_PREC_ARMS <- c("prec-first-matrix-authority", "prec-field-before-a13", "prec-matrix-before-metadata", "prec-sha-before-availability")
.CS15_PREC_FIRES <- c("msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb", "msuiter_error_refdb")
.CS15_PREC_ANCHOR <- c(paste0("reference matrices must share the same channe",
            "l labels"), paste0("metadata field 'version' must be a single non",
            "-empty string"), "reference matrix 'core' must be non-negative", paste0("metadata field 'sha256' must be a sha256 hex ",
            "digest"))
.CS15_PREC_ANTI <- c("matrix 'core' disagrees", "must be declared via build_independent", "is missing governance fields", "'availability' must be")
.CS15_DEGEN <- list(
list(edge = "NA build: declared vs undeclared (A13)", arm = "sp-na-declared", cls = "accept", observed = paste0("nmat=1;names=core;nrow=4;ncol=2;class=SBS;ver",
            "sion=1;build=NA;indep=TRUE;avail=GRCh38;fmt=<",
            "MsRefDb> class: SBS | version: 1 | 1 matrices")),
  list(edge = "NA build: declared vs undeclared (A13)", arm = "rej-a13-undeclared", cls = "msuiter_error_refdb", observed = paste0("a missing build must be declared via build_in",
            "dependent = TRUE")),
  list(edge = "availability: zero-length vs NA entry", arm = "sp-availability-zero", cls = "accept", observed = paste0("nmat=1;names=core;nrow=4;ncol=2;class=SBS;ver",
            "sion=1;build=GRCh38;indep=FALSE;avail=;fmt=<M",
            "sRefDb> class: SBS | version: 1 | 1 matrices")),
  list(edge = "availability: zero-length vs NA entry", arm = "rej-avail-na", cls = "msuiter_error_refdb", observed = paste0("metadata field 'availability' must be a chara",
            "cter vector without NA")),
  list(edge = "colnames: duplicates ride, absence falls", arm = "sp-dup-colnames", cls = "accept", observed = paste0("nmat=1;names=core;nrow=4;ncol=2;class=SBS;ver",
            "sion=1;build=GRCh38;indep=FALSE;avail=GRCh38;",
            "fmt=<MsRefDb> class: SBS | version: 1 | 1 mat",
            "rices")),
  list(edge = "colnames: duplicates ride, absence falls", arm = "rej-mat-colnames", cls = "msuiter_error_refdb", observed = paste0("reference matrix 'core' must carry rownames a",
            "nd colnames")),
  list(edge = "column space: 1x1 accepted, 0-col refused", arm = "sp-1x1", cls = "accept", observed = paste0("nmat=1;names=one;nrow=1;ncol=1;class=SBS;vers",
            "ion=1;build=GRCh38;indep=FALSE;avail=GRCh38;f",
            "mt=<MsRefDb> class: SBS | version: 1 | 1 matr",
            "ices")),
  list(edge = "column space: 1x1 accepted, 0-col refused", arm = "obs-zero-cols-rejected", cls = "msuiter_error_refdb", observed = paste0("reference matrix 'core' must carry rownames a",
            "nd colnames"))
)
.CS15_SCAL_KEYS <- c("governance-fields", "label-key-law", "ffi-no-na-clause", "sha-pin-clause", "plant-checksum", "spec-checksum", "rng-before", "rng-after")
.CS15_SCAL_SOURCE <- list(
list(key = "governance-fields", from_arm = "rej-meta-absent-two", seg = 2L),
  list(key = "label-key-law", from_arm = "rej-mat-rownames", seg = 2L),
  list(key = "ffi-no-na-clause", from_arm = "rej-mat-na", seg = 2L),
  list(key = "sha-pin-clause", from_arm = "rej-sha-upper", seg = 2L)
)
## <<CS15-FROZEN-END>> ########################################################
## <<CS15-SHARED-BEGIN>>  (single source: injected byte-identically into
##    tests/testthat/test-scenario-refdb-witness.R and
##    bench/scenarios/run_refdb_witness.R; pure code -- no testthat, no
##    rails, reaches the package ONLY through the exported ms_refdb face)
.CS15_BULLET <- "ℹ"

##' -- error surface mirror (cli bullet glyphs are RENDERING, not bytes:
##' the theme prints ℹ, the testthat context prints an ASCII "i"; both
##' strip per segment -- CS-12/13/14 precedent)
.cs15_describe <- function(e) {
  m <- gsub("\n", " | ", paste(as.character(conditionMessage(e)),
                               collapse = " | "), fixed = TRUE)
  segs <- strsplit(m, " | ", fixed = TRUE)[[1L]]
  segs <- vapply(seq_along(segs), function(i) {
    s <- trimws(segs[i])
    for (b in c(paste0(.CS15_BULLET, " "), "i ")) {
      if (startsWith(s, b)) s <- substring(s, nchar(b) + 1L)
    }
    trimws(s)
  }, character(1L))
  paste0(segs, collapse = " | ")
}
.cs15_try <- function(expr) tryCatch(list(v = expr), error = identity)
.cs15_cls <- function(r) if (inherits(r, "error")) class(r)[1L] else
                         class(r$v)[1L]
.cs15_msg <- function(r) if (inherits(r, "error")) .cs15_describe(r) else ""

##' -- plants: the frozen deparse text IS the byte carrier. Reconstruction
##' goes through parse/eval of the committed text; the plant checksum rides
##' the frozen text and the live replays (U4/U6, runner rails) prove the
##' reconstruction is faithful -- a drifted plant reddens the lane before
##' any witness byte is written. No file writes: the refdb face is pure R.
.cs15_plants <- function(pd) {
  objs <- list()
  for (nm in names(.CS15_PLANT)) {
    src <- paste0(.CS15_PLANT[[nm]], collapse = "\n")
    if (!nzchar(src)) stop(".cs15_plants: empty plant ", nm)
    ex <- parse(text = src)
    if (length(ex) != 1L) {
      stop(".cs15_plants: plant ", nm, " is not a single expression")
    }
    objs[[nm]] <- eval(ex[[1L]])
  }
  objs$dir <- pd
  objs
}
##' -- plant-derived builders (exact mirrors of the observed probe shapes)
.cs15_mk <- function(ch, sn, vals) {
  matrix(vals, nrow = length(ch), ncol = length(sn), dimnames = list(ch, sn))
}
.cs15_badmat <- function(P, mod) {
  m <- .cs15_mk(P$CH, P$SN, c(1, 2, 3, 4, 5, 6, 7, 8))
  switch(mod,
    "na"     = { m[2L, 1L] <- NA_real_; m },
    "nan"    = { m[1L, 2L] <- NaN; m },
    "inf"    = { m[4L, 2L] <- Inf; m },
    "neg"    = { m[3L, 1L] <- -1; m },
    "noname" = { rownames(m) <- NULL; m },
    "nocol"  = { colnames(m) <- NULL; m },
    "nodim"  = { dimnames(m) <- NULL; m },
    stop(".cs15_badmat: unknown modification"))
}
.cs15_mch2 <- function(P, alt) {
  .cs15_mk(c(alt, P$CH[2L:4L]), P$SN, c(1, 2, 3, 4, 5, 6, 7, 8))
}
##' -- the accepted-shape rendering (integers, labels and logicals only:
##' D11 posture by construction -- the float-free face of the container)
.cs15_shape <- function(r) {
  paste0("nmat=", length(r@matrices), ";names=",
         paste0(names(r@matrices), collapse = ","),
         ";nrow=", nrow(r@matrices[[1L]]),
         ";ncol=", ncol(r@matrices[[1L]]),
         ";class=", r@metadata$class, ";version=", r@metadata$version,
         ";build=", r@metadata$build,
         ";indep=", r@metadata$build_independent,
         ";avail=", paste0(r@metadata$availability, collapse = "+"),
         ";fmt=", format(r))
}
##' -- the canonical texts whose dual-kernel checksums ride the scalars
##' witness (byte-stable joins over the frozen plant deparse texts and the
##' spec roster)
.cs15_plant_text <- function() {
  per <- vapply(names(.CS15_PLANT), function(nm)
    paste0(nm, "=", paste0(.CS15_PLANT[[nm]], collapse = "~")),
    character(1L))
  paste0(per, collapse = ";")
}
.cs15_spec_text <- function() paste0(.CS15_SPEC_ARMS, collapse = ";")

##' -- acceptance arms: what the face RETURNS on planted truth
.cs15_specfire <- function(arm, P) {
  switch(arm,
    "sp-canonical" = .cs15_try(ms_refdb(list(core = P$M1), P$META)),
    "sp-two-matrices" = .cs15_try(ms_refdb(list(core = P$M1, ext = P$M2),
                                            P$META)),
    "sp-na-declared" = .cs15_try({
      r <- P$META; r$build <- NA_character_
      r$build_independent <- TRUE
      ms_refdb(list(core = P$M1), r)
    }),
    "sp-availability-zero" = .cs15_try({
      r <- P$META; r$availability <- character(0L)
      ms_refdb(list(core = P$M1), r)
    }),
    "sp-availability-multi" = .cs15_try({
      r <- P$META; r$availability <- c("GRCh38", "GRCh37")
      ms_refdb(list(core = P$M1), r)
    }),
    "sp-integer-matrix" = .cs15_try(ms_refdb(list(core = matrix(
      as.integer(seq_len(8L)), 4L, 2L, dimnames = list(P$CH, P$SN))),
      P$META)),
    "sp-1x1" = .cs15_try(ms_refdb(list(one = matrix(0.7, 1L, 1L,
      dimnames = list(P$CH[[1L]], P$SN[[1L]]))), P$META)),
    "sp-dup-colnames" = .cs15_try(ms_refdb(list(core = matrix(1, 4L, 2L,
      dimnames = list(P$CH, c(P$SN[[1L]], P$SN[[1L]])))), P$META)),
    NULL)
}
##' -- the committed detail rendering per acceptance arm (recomputed live;
##' rails and U4 compare against the frozen bytes)
.cs15_detail <- function(arm, P) {
  r <- .cs15_specfire(arm, P)
  if (inherits(r, "error")) stop(".cs15_detail: acceptance arm refused ", arm)
  paste0(.cs15_shape(r$v))
}

##' -- law arms: what the face SAYS on planted violations
.cs15_fire <- function(arm, P) {
  switch(arm,
    "obs-zero-cols-rejected" = .cs15_try(ms_refdb(
      list(core = matrix(numeric(0L), 4L, 0L,
                         dimnames = list(P$CH, character(0L)))), P$META)),
    "rej-mat-empty" = .cs15_try(ms_refdb(list(), P$META)),
    "rej-mat-notlist" = .cs15_try(ms_refdb(42L, P$META)),
    "rej-mat-null" = .cs15_try(ms_refdb(NULL, P$META)),
    "rej-mat-unnamed" = .cs15_try(ms_refdb(list(P$M1), P$META)),
    "rej-mat-partial-name" = .cs15_try(ms_refdb(list(core = P$M1, P$M2),
                                                P$META)),
    "rej-mat-vector" = .cs15_try(ms_refdb(list(core = seq_len(8L)), P$META)),
    "rej-mat-character" = .cs15_try(ms_refdb(list(core = matrix("x", 4L, 2L,
      dimnames = list(P$CH, P$SN))), P$META)),
    "rej-mat-dataframe" = .cs15_try(ms_refdb(list(core = data.frame(
      SBS1 = seq_len(4L), SBS5 = seq_len(4L))), P$META)),
    "rej-mat-rownames" = .cs15_try(ms_refdb(list(core = .cs15_badmat(P,
      "noname")), P$META)),
    "rej-mat-colnames" = .cs15_try(ms_refdb(list(core = .cs15_badmat(P,
      "nocol")), P$META)),
    "rej-mat-nodimnames" = .cs15_try(ms_refdb(list(core = .cs15_badmat(P,
      "nodim")), P$META)),
    "rej-mat-na" = .cs15_try(ms_refdb(list(core = .cs15_badmat(P, "na")),
      P$META)),
    "rej-mat-nan" = .cs15_try(ms_refdb(list(core = .cs15_badmat(P, "nan")),
      P$META)),
    "rej-mat-inf" = .cs15_try(ms_refdb(list(core = .cs15_badmat(P, "inf")),
      P$META)),
    "rej-mat-negative" = .cs15_try(ms_refdb(list(core = .cs15_badmat(P,
      "neg")), P$META)),
    "rej-channels-disagree" = .cs15_try(ms_refdb(list(core = P$M1,
      alt = .cs15_mch2(P, "X[C>X]X")), P$META)),
    "rej-channels-subset" = .cs15_try(ms_refdb(list(core = P$M1,
      small = .cs15_mk(P$CH[1L:3L], P$SN, seq_len(6L))), P$META)),
    "rej-meta-notlist" = .cs15_try(ms_refdb(list(core = P$M1), 42L)),
    "rej-meta-unnamed" = .cs15_try({
      r <- P$META; names(r) <- NULL
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-meta-emptyname" = .cs15_try({
      r <- P$META; names(r)[3L] <- ""
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-meta-absent-one" = .cs15_try({
      r <- P$META; r$license <- NULL
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-meta-absent-two" = .cs15_try({
      r <- P$META; r$build <- NULL; r$sha256 <- NULL
      r$build_independent <- TRUE
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-field-version-empty" = .cs15_try({
      r <- P$META; r$version <- ""
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-field-version-na" = .cs15_try({
      r <- P$META; r$version <- NA_character_
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-field-version-multi" = .cs15_try({
      r <- P$META; r$version <- c("1", "2")
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-field-version-num" = .cs15_try({
      r <- P$META; r$version <- 1
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-field-class-empty" = .cs15_try({
      r <- P$META; r$class <- ""
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-field-schema-na" = .cs15_try({
      r <- P$META; r$schema_version <- NA_character_
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-field-license-multi" = .cs15_try({
      r <- P$META; r$license <- c("CC0-1.0", "CC-BY-4.0")
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-indep-na" = .cs15_try({
      r <- P$META; r$build_independent <- NA
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-indep-num" = .cs15_try({
      r <- P$META; r$build_independent <- 1L
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-indep-str" = .cs15_try({
      r <- P$META; r$build_independent <- "TRUE"
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-build-empty" = .cs15_try({
      r <- P$META; r$build <- ""
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-build-empty-declared" = .cs15_try({
      r <- P$META; r$build <- ""; r$build_independent <- TRUE
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-build-num" = .cs15_try({
      r <- P$META; r$build <- 38L
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-build-multi" = .cs15_try({
      r <- P$META; r$build <- c("GRCh38", "GRCh37")
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-a13-undeclared" = .cs15_try({
      r <- P$META; r$build <- NA_character_
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-sha-upper" = .cs15_try({
      r <- P$META; r$sha256 <- paste0(rep_len("A", 64L), collapse = "")
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-sha-short" = .cs15_try({
      r <- P$META; r$sha256 <- substr(P$SHA64, 1L, 63L)
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-sha-nonhex" = .cs15_try({
      r <- P$META; r$sha256 <- paste0(rep_len("g", 64L), collapse = "")
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-sha-num" = .cs15_try({
      r <- P$META; r$sha256 <- 42L
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-sha-na" = .cs15_try({
      r <- P$META; r$sha256 <- NA_character_
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-avail-na" = .cs15_try({
      r <- P$META; r$availability <- c("GRCh38", NA_character_)
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-avail-num" = .cs15_try({
      r <- P$META; r$availability <- 38L
      ms_refdb(list(core = P$M1), r)
    }),
    "rej-avail-logical" = .cs15_try({
      r <- P$META; r$availability <- TRUE
      ms_refdb(list(core = P$M1), r)
    }),
    NULL)
}

##' -- precedence discriminators: which law speaks when two could
.cs15_precfire <- function(arm, P) {
  switch(arm,
    "prec-first-matrix-authority" = .cs15_try(ms_refdb(list(core = P$M1,
      alt = .cs15_mch2(P, "X[C>X]X")), P$META)),
    "prec-field-before-a13" = .cs15_try({
      r <- P$META; r$version <- ""; r$build <- NA_character_
      ms_refdb(list(core = P$M1), r)
    }),
    "prec-matrix-before-metadata" = .cs15_try({
      r <- P$META; r$license <- NULL
      ms_refdb(list(core = .cs15_badmat(P, "neg")), r)
    }),
    "prec-sha-before-availability" = .cs15_try({
      r <- P$META; r$sha256 <- "x"; r$availability <- 38L
      ms_refdb(list(core = P$M1), r)
    }),
    NULL)
}
##' -- the frozen-table row builders (witness shape comes from the tables;
##' the committed TSVs must mirror these byte for byte)
.cs15_lawrows <- function() {
  data.frame(arm = .CS15_LAW_ARMS, face = rep("ms_refdb", length(.CS15_LAW_ARMS)),
    cls = .CS15_LAW_CLS, mode = .CS15_LAW_MODE,
    clause = vapply(.CS15_LAW_ARMS, function(a) .CS15_LAW_CLAUSES[[a]],
                    character(1L)),
    stringsAsFactors = FALSE, check.names = FALSE)
}
.cs15_specrows <- function() {
  data.frame(arm = .CS15_SPEC_ARMS, face = rep("ms_refdb", length(.CS15_SPEC_ARMS)),
    cls = .CS15_SPEC_CLS,
    detail = vapply(.CS15_SPEC_ARMS, function(a) .CS15_SPEC_DETAILS[[a]],
                    character(1L)),
    stringsAsFactors = FALSE, check.names = FALSE)
}
.cs15_precrows <- function() {
  data.frame(arm = .CS15_PREC_ARMS, fires_cls = .CS15_PREC_FIRES,
    fires_anchor = .CS15_PREC_ANCHOR, anti_anchor = .CS15_PREC_ANTI,
    stringsAsFactors = FALSE, check.names = FALSE)
}
.cs15_degenrows <- function() {
  row <- function(k) vapply(.CS15_DEGEN, function(d) d[[k]], character(1L))
  data.frame(edge = row("edge"), arm = row("arm"), cls = row("cls"),
    observed = row("observed"), stringsAsFactors = FALSE, check.names = FALSE)
}
.cs15_scalar_kv <- function(sc, k) sc$value[match(k, sc$key)]
## <<CS15-SHARED-END>>  (do not hand-edit in place: edit the source and
##    re-splice both hosts)
##    re-splice both hosts)
##    re-splice both hosts)
##    re-splice both hosts)
##    re-splice both hosts)

# ===========================================================================
# U1 -- rails: the runner exists and speaks the exported face, never an
# internal (banned-word grep over its full source).
# ===========================================================================
test_that("runner speaks the exported-face rails", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  runner <- file.path(.ms_root, "bench", "scenarios", "run_refdb_witness.R")
  expect_true(file.exists(runner))
  src <- paste(readLines(runner, warn = FALSE), collapse = "\n")
  for (need in c("--file=", "[attest]", "OVERALL PASS", "ms_refdb(", "cs15_")) {
    expect_true(grepl(need, src, fixed = TRUE), info = need)
  }
  for (ban in c("msuiter:::", ".ms_refdb", "msuiter_refdb_",
                "msuiter_validate_", "msuiter_abort", "MsRefDb(",
                "expect_", "ms_calibration_grid", "ms_fit_bootstrap",
                "ms_calibration_sanity", "run_benchmark", "set.seed",
                "sample(", "download.file", "http")) {
    expect_false(grepl(ban, src, fixed = TRUE), info = ban)
  }
})

# ===========================================================================
# U2 -- witness existence and shape: five committed TSVs, non-zero, with
# hard row-count gates and an all-character no-NA census (no vacuous green).
# ===========================================================================
test_that("the five witnesses exist with hard shape gates", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  for (f in c("cs15_specs.tsv", "cs15_laws.tsv", "cs15_precedence.tsv",
              "cs15_degenerates.tsv", "cs15_scalars.tsv")) {
    expect_true(file.exists(.rs_out15(f)))
    expect_gt(file.size(.rs_out15(f)), 0)
  }
  sp <- .rs_tsv15("cs15_specs.tsv"); lw <- .rs_tsv15("cs15_laws.tsv")
  pr <- .rs_tsv15("cs15_precedence.tsv"); dg <- .rs_tsv15("cs15_degenerates.tsv")
  sc <- .rs_tsv15("cs15_scalars.tsv")
  expect_identical(nrow(sp), 8L)
  expect_identical(nrow(lw), 46L)
  expect_identical(nrow(pr), 4L)
  expect_identical(nrow(dg), 8L)
  expect_true("key" %in% names(sc) && "value" %in% names(sc))
  expect_true(all(sc$key %in% .CS15_SCAL_KEYS))
  expect_identical(nrow(sc), length(.CS15_SCAL_KEYS))
  for (df in list(sp, lw, pr, dg, sc)) {
    expect_true(all(vapply(df, is.character, logical(1L))))
    expect_false(any(vapply(df, function(cc) any(is.na(cc)), logical(1L))))
  }
})

# ===========================================================================
# U3 -- the specs witness mirrors the frozen acceptance table byte for byte.
# ===========================================================================
test_that("committed specs mirror the frozen table", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  sp <- .rs_tsv15("cs15_specs.tsv"); fr <- .cs15_specrows()
  expect_identical(sp$arm, fr$arm)
  expect_identical(sp$face, fr$face)
  expect_identical(sp$cls, fr$cls)
  expect_identical(sp$detail, fr$detail)
})

# ===========================================================================
# U4 -- live replay of the acceptance arms: the shipped face still RETURNS
# exactly what the witness committed (class token + accepted-shape rendering).
# ===========================================================================
test_that("acceptance arms replay live through the face", {
  P <- .cs15_plants(file.path(tempdir(TRUE), "cs15-law-plants"))
  fr <- .cs15_specrows()
  for (i in seq_len(nrow(fr))) {
    arm <- fr$arm[i]
    r <- .cs15_specfire(arm, P)
    expect_false(inherits(r, "error"), info = arm)
    expect_identical(.cs15_cls(r), fr$cls[i], info = arm)
    expect_identical(.cs15_detail(arm, P), fr$detail[i], info = arm)
  }
})

# ===========================================================================
# U5 -- the laws witness mirrors the frozen law table: 46 arms, classes,
# adjudication modes, verbatim clauses.
# ===========================================================================
test_that("committed laws mirror the frozen law table", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  lw <- .rs_tsv15("cs15_laws.tsv"); fr <- .cs15_lawrows()
  expect_identical(lw$arm, fr$arm)
  expect_identical(lw$face, fr$face)
  expect_identical(lw$cls, fr$cls)
  expect_identical(lw$mode, fr$mode)
  expect_identical(lw$clause, fr$clause)
})

# ===========================================================================
# U6 -- live replay of the law arms: each fires its committed class, and its
# committed clause rides the live message verbatim (every clause is
# byte-stable: the face is pure R and the ledger was DET-proved).
# ===========================================================================
test_that("law arms replay live with their committed verdicts", {
  P <- .cs15_plants(file.path(tempdir(TRUE), "cs15-law-plants"))
  fr <- .cs15_lawrows()
  for (i in seq_len(nrow(fr))) {
    arm <- fr$arm[i]
    r <- .cs15_fire(arm, P)
    expect_true(inherits(r, "error"), info = arm)
    expect_identical(.cs15_cls(r), fr$cls[i], info = arm)
    msg <- .cs15_msg(r)
    if (identical(fr$mode[i], "full")) {
      expect_identical(msg, fr$clause[i], info = arm)
    } else {
      for (bl in strsplit(fr$clause[i], " | ", fixed = TRUE)[[1L]]) {
        expect_true(grepl(bl, msg, fixed = TRUE), info = paste0(arm, " :: ", bl))
      }
    }
  }
})

# ===========================================================================
# U7 -- precedence discriminators: the RIGHT law speaks when two could.
# ===========================================================================
test_that("precedence discriminators speak the right law", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  P <- .cs15_plants(file.path(tempdir(TRUE), "cs15-law-plants"))
  pr <- .cs15_precrows()
  cw <- .rs_tsv15("cs15_precedence.tsv")
  expect_identical(cw$arm, pr$arm)
  expect_identical(cw$fires_cls, pr$fires_cls)
  expect_identical(cw$fires_anchor, pr$fires_anchor)
  expect_identical(cw$anti_anchor, pr$anti_anchor)
  for (i in seq_len(nrow(pr))) {
    r <- .cs15_precfire(pr$arm[i], P)
    expect_true(inherits(r, "error"), info = pr$arm[i])
    expect_identical(.cs15_cls(r), pr$fires_cls[i], info = pr$arm[i])
    msg <- .cs15_msg(r)
    expect_true(grepl(pr$fires_anchor[i], msg, fixed = TRUE), info = pr$arm[i])
    expect_false(grepl(pr$anti_anchor[i], msg, fixed = TRUE), info = pr$arm[i])
  }
})

# ===========================================================================
# U8 -- degenerate boundaries: the asymmetry pairs the face draws on its own
# (declared vs undeclared NA build, zero-length vs NA availability, duplicate
# vs absent colnames, 1x1 vs zero-column matrix space).
# ===========================================================================
test_that("degenerate boundaries hold their committed sides", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  P <- .cs15_plants(file.path(tempdir(TRUE), "cs15-law-plants"))
  dg <- .rs_tsv15("cs15_degenerates.tsv"); fr <- .cs15_degenrows()
  expect_identical(dg$edge, fr$edge)
  expect_identical(dg$arm, fr$arm)
  expect_identical(dg$cls, fr$cls)
  expect_identical(dg$observed, fr$observed)
  for (i in seq_len(nrow(fr))) {
    arm <- fr$arm[i]
    if (identical(fr$cls[i], "accept")) {
      r <- .cs15_specfire(arm, P)
      expect_false(inherits(r, "error"), info = arm)
      expect_identical(.cs15_detail(arm, P), fr$observed[i], info = arm)
    } else {
      r <- .cs15_fire(arm, P)
      expect_true(inherits(r, "error"), info = arm)
      expect_true(grepl(fr$observed[i], .cs15_msg(r), fixed = TRUE), info = arm)
    }
  }
})

# ===========================================================================
# U9 -- plant checksum: every frozen plant byte re-hashes identically under
# BOTH governed SHA-256 kernels, and the scalars witness carries that
# checksum. The reconstruction round (parse/eval of the frozen deparse text)
# is exercised LIVE by U4/U6 through the face itself.
# ===========================================================================
test_that("plant bytes re-hash under both governed kernels", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  bytes <- charToRaw(.cs15_plant_text())
  hA <- .ms_fit_sha256(bytes)
  hB <- digest::digest(bytes, algo = "sha256", serialize = FALSE)
  expect_identical(hA, hB)
  expect_match(hA, "^[0-9a-f]{64}$")
  sc <- .rs_tsv15("cs15_scalars.tsv")
  expect_identical(.cs15_scalar_kv(sc, "plant-checksum"), hA)
  sbytes <- charToRaw(.cs15_spec_text())
  expect_identical(.cs15_scalar_kv(sc, "spec-checksum"),
                   .ms_fit_sha256(sbytes))
})

# ===========================================================================
# U10 -- scalars: the bytes the face speaks verbatim (cross-checked LIVE
# through its own clauses) and the silent RNG rails.
# ===========================================================================
test_that("scalars speak face bytes and RNG rails", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  P <- .cs15_plants(file.path(tempdir(TRUE), "cs15-law-plants"))
  sc <- .rs_tsv15("cs15_scalars.tsv")
  for (s in .CS15_SCAL_SOURCE) {
    msg <- .cs15_msg(.cs15_fire(s$from_arm, P))
    seg <- strsplit(msg, " | ", fixed = TRUE)[[1L]][s$seg]
    froz <- strsplit(.CS15_LAW_CLAUSES[[s$from_arm]], " | ", fixed = TRUE)[[1L]][s$seg]
    expect_identical(.cs15_scalar_kv(sc, s$key), seg, info = s$key)
    expect_identical(seg, froz, info = s$key)
  }
  expect_identical(.cs15_scalar_kv(sc, "rng-before"), "FALSE")
  expect_identical(.cs15_scalar_kv(sc, "rng-after"), "FALSE")
})
