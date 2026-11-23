# run_ard_witness.R -- the CS-16 ard-witness scenario (pillar 3).
#
# Mandate: plant synthetic constructor calls (the D3 law: zero COSMIC
# numeric matrices, zero real-data bytes, zero downloads -- ARD/NMF ride
# only as FORMAT NAMES) and adjudicate the EXPORTED ms_ard() face: the
# shared engine admission laws, the S7 property-gate split against the
# validator, the ARD prior laws, the third abort class the len-2 hyper
# values reach, the precedence discriminators with their anti anchors, the
# degenerate boundaries and the acceptance specs. Every arm is driven
# through the exported constructors alone; the accepted returns, the abort
# classes and the fired bullets are the face's own. The scenario consumes
# no RNG, no network and no clock at the adjudication core; the benchmark
# runner and the DECLINED calibration family are never invoked here.
#
# Framing law: DECISION RECORD only. The witnesses under out/ are the
# committed verdict of what the shipped face SAID on planted truth. Float
# posture (D11): integer, label, logical, class and clause bytes are
# byte-committed; the face produces no float payload columns, so no float
# glyph rides any witness.
#
# Rails: this runner carries the same frozen block as the law file
# (tests/testthat/test-scenario-ard-witness.R), injected byte-identically
# from one minted source; every observed class, clause, shape and
# precedence order is rail-checked AS WE GO -- a drift fails the run
# before any witness is written. The witness bytes are written only after
# every payload census speaks; a byte-rerun must reproduce them identically.

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
stopif <- function(cond, msg) if (isTRUE(cond)) stop(msg, call. = FALSE)
## RNG-STATE-RAIL: the adjudication core must never seed or consume RNG;
## the purity verdict rides the scalars witness (committed bytes below).
rng0 <- exists(".Random.seed", envir = globalenv(), inherits = TRUE)

## <<CS16-FROZEN-BEGIN>>  (minted mechanically from the audited ledgers
##    2026-11-23; DO NOT hand-edit: regenerate via gen-frozen.cs16.R) ##
.CS16_LAW_ARMS <- c("lj-name-upper", "lj-name-hyphen", "lj-name-empty", "lj-name-na", "lj-mode-unknown", "lj-params-partial", "lj-params-null", "lj-det-na", "lj-pkgs-na", "lj-pkgs-empty", "lj-label-na", "lj-name-num", "lj-mode-num", "lj-params-vec", "lj-det-string", "lj-pkgs-list", "lj-label-num", "lj-a0-zero", "lj-a0-neg", "lj-a0-inf", "lj-a0-nan", "lj-a0-na", "lj-a0-len2", "lj-a0-str", "lj-b0-zero", "lj-b0-str", "lj-tol-zero", "lj-tol-neg", "lj-tol-inf", "lj-tol-str", "lj-mi-zero", "lj-mi-frac", "lj-mi-neg", "lj-mi-inf", "lj-mi-str", "lj-seed-neg", "lj-seed-frac", "lj-seed-above", "lj-seed-str", "lj-seed-len2")
.CS16_LAW_CLS <- c("msuiter_error_engine", "msuiter_error_engine", "msuiter_error_engine", "msuiter_error_engine", "msuiter_error_engine", "msuiter_error_engine", "simpleError", "msuiter_error_engine", "msuiter_error_engine", "msuiter_error_engine", "msuiter_error_engine", "simpleError", "simpleError", "simpleError", "simpleError", "simpleError", "simpleError", "msuiter_error_engine", "msuiter_error_engine", "msuiter_error_engine", "msuiter_error_engine", "msuiter_error_engine", "msuiter_error_internal", "simpleError", "msuiter_error_engine", "simpleError", "msuiter_error_engine", "msuiter_error_engine", "msuiter_error_engine", "simpleError", "msuiter_error_engine", "msuiter_error_engine", "msuiter_error_engine", "msuiter_error_engine", "simpleError", "msuiter_error_engine", "msuiter_error_engine", "msuiter_error_engine", "simpleError", "msuiter_error_internal")
.CS16_LAW_CLAUSES <- list()
.CS16_LAW_CLAUSES[["lj-name-upper"]] <- paste0("engine name must be a single lower-case snake",
            "_case string | engine names are registry keys",
            " (D9) | received: 'ARD' | use e.g. name = \"nm",
            "f_kl\"")
.CS16_LAW_CLAUSES[["lj-name-hyphen"]] <- paste0("engine name must be a single lower-case snake",
            "_case string | engine names are registry keys",
            " (D9) | received: 'a-b' | use e.g. name = \"nm",
            "f_kl\"")
.CS16_LAW_CLAUSES[["lj-name-empty"]] <- paste0("engine name must be a single lower-case snake",
            "_case string | engine names are registry keys",
            " (D9) | received: '' | use e.g. name = \"nmf_k",
            "l\"")
.CS16_LAW_CLAUSES[["lj-name-na"]] <- paste0("engine name must be a single lower-case snake",
            "_case string | engine names are registry keys",
            " (D9) | received: 'NA' | use e.g. name = \"nmf",
            "_kl\"")
.CS16_LAW_CLAUSES[["lj-mode-unknown"]] <- paste0("engine mode must be one of the known modes | ",
            "known modes: extract, fit | received: 'transf",
            "orm' | declare whether the engine extracts si",
            "gnatures or fits exposures")
.CS16_LAW_CLAUSES[["lj-params-partial"]] <- paste0("engine params must be a (named) list | params",
            " carry the hyper-parameters of the spec | rec",
            "eived: list | pass hyper-parameters as a name",
            "d list")
.CS16_LAW_CLAUSES[["lj-params-null"]] <- paste0("<msuiter::MsArd> object properties are invali",
            "d: | - @params must be <list>, not <NULL>")
.CS16_LAW_CLAUSES[["lj-det-na"]] <- paste0("deterministic must be a single TRUE or FALSE ",
            "| determinism is part of the engine contract ",
            "(thread invariance) | received: 'NA' | declar",
            "e whether the engine is seeded and thread inv",
            "ariant")
.CS16_LAW_CLAUSES[["lj-pkgs-na"]] <- paste0("packages must be a character vector of packag",
            "e names without NA | required_pkgs() reports ",
            "these before an engine runs | received: 'rlan",
            "g', 'NA' | list package names, or pass charac",
            "ter(0)")
.CS16_LAW_CLAUSES[["lj-pkgs-empty"]] <- paste0("packages must be a character vector of packag",
            "e names without NA | required_pkgs() reports ",
            "these before an engine runs | received: '' | ",
            "list package names, or pass character(0)")
.CS16_LAW_CLAUSES[["lj-label-na"]] <- paste0("label must be a single string (empty allowed)",
            " | the label is an optional human-readable en",
            "gine name | received: 'NA' | pass a short lab",
            "el, or leave it empty")
.CS16_LAW_CLAUSES[["lj-name-num"]] <- paste0("<msuiter::MsArd> object properties are invali",
            "d: | - @name must be <character>, not <double",
            ">")
.CS16_LAW_CLAUSES[["lj-mode-num"]] <- paste0("<msuiter::MsArd> object properties are invali",
            "d: | - @mode must be <character>, not <double",
            ">")
.CS16_LAW_CLAUSES[["lj-params-vec"]] <- paste0("<msuiter::MsArd> object properties are invali",
            "d: | - @params must be <list>, not <character",
            ">")
.CS16_LAW_CLAUSES[["lj-det-string"]] <- paste0("<msuiter::MsArd> object properties are invali",
            "d: | - @deterministic must be <logical>, not ",
            "<character>")
.CS16_LAW_CLAUSES[["lj-pkgs-list"]] <- paste0("<msuiter::MsArd> object properties are invali",
            "d: | - @packages must be <character>, not <li",
            "st>")
.CS16_LAW_CLAUSES[["lj-label-num"]] <- paste0("<msuiter::MsArd> object properties are invali",
            "d: | - @label must be <character>, not <doubl",
            "e>")
.CS16_LAW_CLAUSES[["lj-a0-zero"]] <- paste0("`a0` must be a single finite number > 0 | got",
            ": 0 | the ARD prior property `a0` | construct",
            " with ms_ard(a0 = , b0 = ) using positive val",
            "ues")
.CS16_LAW_CLAUSES[["lj-a0-neg"]] <- paste0("`a0` must be a single finite number > 0 | got",
            ": -1 | the ARD prior property `a0` | construc",
            "t with ms_ard(a0 = , b0 = ) using positive va",
            "lues")
.CS16_LAW_CLAUSES[["lj-a0-inf"]] <- paste0("`a0` must be a single finite number > 0 | got",
            ": Inf | the ARD prior property `a0` | constru",
            "ct with ms_ard(a0 = , b0 = ) using positive v",
            "alues")
.CS16_LAW_CLAUSES[["lj-a0-nan"]] <- paste0("`a0` must be a single finite number > 0 | got",
            ": NaN | the ARD prior property `a0` | constru",
            "ct with ms_ard(a0 = , b0 = ) using positive v",
            "alues")
.CS16_LAW_CLAUSES[["lj-a0-na"]] <- paste0("`a0` must be a single finite number > 0 | got",
            ": NA | the ARD prior property `a0` | construc",
            "t with ms_ard(a0 = , b0 = ) using positive va",
            "lues")
.CS16_LAW_CLAUSES[["lj-a0-len2"]] <- paste0("msuiter_abort: bullet 'i' must be a non-empty",
            " string")
.CS16_LAW_CLAUSES[["lj-a0-str"]] <- paste0("<msuiter::MsArd> object properties are invali",
            "d: | - @a0 must be <integer> or <double>, not",
            " <character>")
.CS16_LAW_CLAUSES[["lj-b0-zero"]] <- paste0("`b0` must be a single finite number > 0 | got",
            ": 0 | the ARD prior property `b0` | construct",
            " with ms_ard(a0 = , b0 = ) using positive val",
            "ues")
.CS16_LAW_CLAUSES[["lj-b0-str"]] <- paste0("<msuiter::MsArd> object properties are invali",
            "d: | - @b0 must be <integer> or <double>, not",
            " <character>")
.CS16_LAW_CLAUSES[["lj-tol-zero"]] <- paste0("`tol` must be a single finite number > 0 | go",
            "t: 0 | the ARD convergence-tolerance property",
            " `tol` | construct with a finite positive tol",
            "erance")
.CS16_LAW_CLAUSES[["lj-tol-neg"]] <- paste0("`tol` must be a single finite number > 0 | go",
            "t: -1e-05 | the ARD convergence-tolerance pro",
            "perty `tol` | construct with a finite positiv",
            "e tolerance")
.CS16_LAW_CLAUSES[["lj-tol-inf"]] <- paste0("`tol` must be a single finite number > 0 | go",
            "t: Inf | the ARD convergence-tolerance proper",
            "ty `tol` | construct with a finite positive t",
            "olerance")
.CS16_LAW_CLAUSES[["lj-tol-str"]] <- paste0("<msuiter::MsArd> object properties are invali",
            "d: | - @tol must be <integer> or <double>, no",
            "t <character>")
.CS16_LAW_CLAUSES[["lj-mi-zero"]] <- paste0("`max_iter` must be a single positive whole nu",
            "mber | got: 0 | the ARD iteration-cap propert",
            "y `max_iter` | construct with a positive whol",
            "e-number max_iter")
.CS16_LAW_CLAUSES[["lj-mi-frac"]] <- paste0("`max_iter` must be a single positive whole nu",
            "mber | got: 1.5 | the ARD iteration-cap prope",
            "rty `max_iter` | construct with a positive wh",
            "ole-number max_iter")
.CS16_LAW_CLAUSES[["lj-mi-neg"]] <- paste0("`max_iter` must be a single positive whole nu",
            "mber | got: -3 | the ARD iteration-cap proper",
            "ty `max_iter` | construct with a positive who",
            "le-number max_iter")
.CS16_LAW_CLAUSES[["lj-mi-inf"]] <- paste0("`max_iter` must be a single positive whole nu",
            "mber | got: Inf | the ARD iteration-cap prope",
            "rty `max_iter` | construct with a positive wh",
            "ole-number max_iter")
.CS16_LAW_CLAUSES[["lj-mi-str"]] <- paste0("<msuiter::MsArd> object properties are invali",
            "d: | - @max_iter must be <integer> or <double",
            ">, not <character>")
.CS16_LAW_CLAUSES[["lj-seed-neg"]] <- paste0("`seed` must be a single whole number in [0, 2",
            "^31 - 1] | got: -1 | the ARD initializer-seed",
            " property `seed` | construct with a whole-num",
            "ber seed in range")
.CS16_LAW_CLAUSES[["lj-seed-frac"]] <- paste0("`seed` must be a single whole number in [0, 2",
            "^31 - 1] | got: 1.5 | the ARD initializer-see",
            "d property `seed` | construct with a whole-nu",
            "mber seed in range")
.CS16_LAW_CLAUSES[["lj-seed-above"]] <- paste0("`seed` must be a single whole number in [0, 2",
            "^31 - 1] | got: 2147483648 | the ARD initiali",
            "zer-seed property `seed` | construct with a w",
            "hole-number seed in range")
.CS16_LAW_CLAUSES[["lj-seed-str"]] <- paste0("<msuiter::MsArd> object properties are invali",
            "d: | - @seed must be <integer> or <double>, n",
            "ot <character>")
.CS16_LAW_CLAUSES[["lj-seed-len2"]] <- paste0("msuiter_abort: bullet 'i' must be a non-empty",
            " string")
.CS16_SPEC_ARMS <- c("sp-canonical", "sp-ctor-identity", "sp-integer-hyper", "sp-mode-fit-legal", "sp-params-named", "sp-params-unnamed-passes", "sp-label-empty", "sp-override-all", "sp-replay-identity")
.CS16_SPEC_CLS <- c("s7:msuiter::MsArd", "s7:msuiter::MsArd", "s7:msuiter::MsArd", "s7:msuiter::MsArd", "s7:msuiter::MsArd", "s7:msuiter::MsArd", "s7:msuiter::MsArd", "s7:msuiter::MsArd", "s7:character")
.CS16_SPEC_DETAILS <- list()
.CS16_SPEC_DETAILS[["sp-canonical"]] <- paste0("name=ard;mode=extract;np=0;pnames=;det=TRUE;n",
            "pkg=0;pkgs=;label=ARD-NMF (SignatureAnalyzer ",
            "semantics);a0=10;b0=5;tol=1e-05;mi=2000;seed=",
            "1;fmt=<MsEngine> ARD-NMF (SignatureAnalyzer s",
            "emantics) (ard) | mode: extract | determinist",
            "ic")
.CS16_SPEC_DETAILS[["sp-ctor-identity"]] <- paste0("name=ard;mode=extract;np=0;pnames=;det=TRUE;n",
            "pkg=0;pkgs=;label=ARD-NMF (SignatureAnalyzer ",
            "semantics);a0=10;b0=5;tol=1e-05;mi=2000;seed=",
            "1;fmt=<MsEngine> ARD-NMF (SignatureAnalyzer s",
            "emantics) (ard) | mode: extract | determinist",
            "ic")
.CS16_SPEC_DETAILS[["sp-integer-hyper"]] <- paste0("name=ard;mode=extract;np=0;pnames=;det=TRUE;n",
            "pkg=0;pkgs=;label=ARD-NMF (SignatureAnalyzer ",
            "semantics);a0=10;b0=5;tol=1;mi=2000;seed=0;fm",
            "t=<MsEngine> ARD-NMF (SignatureAnalyzer seman",
            "tics) (ard) | mode: extract | deterministic")
.CS16_SPEC_DETAILS[["sp-mode-fit-legal"]] <- paste0("name=ard;mode=fit;np=0;pnames=;det=TRUE;npkg=",
            "0;pkgs=;label=ARD-NMF (SignatureAnalyzer sema",
            "ntics);a0=10;b0=5;tol=1e-05;mi=2000;seed=1;fm",
            "t=<MsEngine> ARD-NMF (SignatureAnalyzer seman",
            "tics) (ard) | mode: fit | deterministic")
.CS16_SPEC_DETAILS[["sp-params-named"]] <- paste0("name=ard;mode=extract;np=1;pnames=algo;det=TR",
            "UE;npkg=0;pkgs=;label=ARD-NMF (SignatureAnaly",
            "zer semantics);a0=10;b0=5;tol=1e-05;mi=2000;s",
            "eed=1;fmt=<MsEngine> ARD-NMF (SignatureAnalyz",
            "er semantics) (ard) | mode: extract | determi",
            "nistic")
.CS16_SPEC_DETAILS[["sp-params-unnamed-passes"]] <- paste0("name=ard;mode=extract;np=2;pnames=;det=TRUE;n",
            "pkg=0;pkgs=;label=ARD-NMF (SignatureAnalyzer ",
            "semantics);a0=10;b0=5;tol=1e-05;mi=2000;seed=",
            "1;fmt=<MsEngine> ARD-NMF (SignatureAnalyzer s",
            "emantics) (ard) | mode: extract | determinist",
            "ic")
.CS16_SPEC_DETAILS[["sp-label-empty"]] <- paste0("name=ard;mode=extract;np=0;pnames=;det=TRUE;n",
            "pkg=0;pkgs=;label=;a0=10;b0=5;tol=1e-05;mi=20",
            "00;seed=1;fmt=<MsEngine> ard (ard) | mode: ex",
            "tract | deterministic")
.CS16_SPEC_DETAILS[["sp-override-all"]] <- paste0("name=ard_x;mode=fit;np=1;pnames=k;det=FALSE;n",
            "pkg=1;pkgs=rlang;label=Custom ARD;a0=2;b0=3;t",
            "ol=1e-08;mi=10;seed=0;fmt=<MsEngine> Custom A",
            "RD (ard_x) | mode: fit | stochastic")
.CS16_SPEC_DETAILS[["sp-replay-identity"]] <- paste0("name=ard;mode=extract;np=0;pnames=;det=TRUE;n",
            "pkg=0;pkgs=;label=ARD-NMF (SignatureAnalyzer ",
            "semantics);a0=10;b0=5;tol=1e-05;mi=2000;seed=",
            "1;fmt=<MsEngine> ARD-NMF (SignatureAnalyzer s",
            "emantics) (ard) | mode: extract | determinist",
            "ic==name=ard;mode=extract;np=0;pnames=;det=TR",
            "UE;npkg=0;pkgs=;label=ARD-NMF (SignatureAnaly",
            "zer semantics);a0=10;b0=5;tol=1e-05;mi=2000;s",
            "eed=1;fmt=<MsEngine> ARD-NMF (SignatureAnalyz",
            "er semantics) (ard) | mode: extract | determi",
            "nistic")
.CS16_PREC_ARMS <- c("prec-name-over-mode", "prec-mode-over-params", "prec-det-over-pkgs", "prec-pkgs-over-label", "prec-shared-over-ard", "prec-a0-over-b0", "prec-tol-over-mi", "prec-mi-over-seed")
.CS16_PREC_CLS <- c("msuiter_error_engine", "msuiter_error_engine", "msuiter_error_engine", "msuiter_error_engine", "msuiter_error_engine", "msuiter_error_engine", "msuiter_error_engine", "msuiter_error_engine")
.CS16_PREC_FIRES <- c(paste0("engine name must be a single lower-case snake",
            "_case string"), "engine mode must be one of the known modes", "deterministic must be a single TRUE or FALSE", paste0("packages must be a character vector of packag",
            "e names without NA"), "label must be a single string (empty allowed)", "`a0` must be a single finite number > 0", "`tol` must be a single finite number > 0", paste0("`max_iter` must be a single positive whole nu",
            "mber"))
.CS16_PREC_ANTI <- c("engine mode must be", "engine params must be a (named) list", paste0("packages must be a character vector of packag",
            "e names without NA"), "label must be a single string (empty allowed)", "must be a single finite number > 0", "`b0` must be", "positive whole number", "whole number in [0")
.CS16_DEGEN_PAIR <- c("maxiter-floor", "maxiter-floor", "seed-floor", "seed-floor", "seed-ceiling", "seed-ceiling", "tol-floor", "tol-floor", "label-empty", "label-empty", "mode-domain", "mode-domain", "a0-finite-ceil", "a0-finite-ceil")
.CS16_DEGEN_SIDE <- c("hi", "lo", "hi", "lo", "hi", "lo", "hi", "lo", "hi", "lo", "hi", "lo", "hi", "lo")
.CS16_DEGEN_ARMS <- c("maxiter-floor-hi", "maxiter-floor-lo", "seed-floor-hi", "seed-floor-lo", "seed-ceiling-hi", "seed-ceiling-lo", "tol-floor-hi", "tol-floor-lo", "label-empty-hi", "label-empty-lo", "mode-domain-hi", "mode-domain-lo", "a0-finite-ceil-hi", "a0-finite-ceil-lo")
.CS16_DEGEN_MODE <- c("accept", "reject", "accept", "reject", "accept", "reject", "accept", "reject", "accept", "reject", "accept", "reject", "accept", "reject")
.CS16_DEGEN_CLS <- c("s7:msuiter::MsArd", "msuiter_error_engine", "s7:msuiter::MsArd", "msuiter_error_engine", "s7:msuiter::MsArd", "msuiter_error_engine", "s7:msuiter::MsArd", "msuiter_error_engine", "s7:msuiter::MsArd", "msuiter_error_engine", "s7:msuiter::MsArd", "msuiter_error_engine", "s7:msuiter::MsArd", "msuiter_error_engine")
.CS16_DEGEN_MSG <- list()
.CS16_DEGEN_MSG[["maxiter-floor-hi"]] <- paste0("name=ard;mode=extract;np=0;pnames=;det=TRUE;n",
            "pkg=0;pkgs=;label=ARD-NMF (SignatureAnalyzer ",
            "semantics);a0=10;b0=5;tol=1e-05;mi=1;seed=1;f",
            "mt=<MsEngine> ARD-NMF (SignatureAnalyzer sema",
            "ntics) (ard) | mode: extract | deterministic")
.CS16_DEGEN_MSG[["maxiter-floor-lo"]] <- paste0("`max_iter` must be a single positive whole nu",
            "mber | got: 0 | the ARD iteration-cap propert",
            "y `max_iter` | construct with a positive whol",
            "e-number max_iter")
.CS16_DEGEN_MSG[["seed-floor-hi"]] <- paste0("name=ard;mode=extract;np=0;pnames=;det=TRUE;n",
            "pkg=0;pkgs=;label=ARD-NMF (SignatureAnalyzer ",
            "semantics);a0=10;b0=5;tol=1e-05;mi=2000;seed=",
            "0;fmt=<MsEngine> ARD-NMF (SignatureAnalyzer s",
            "emantics) (ard) | mode: extract | determinist",
            "ic")
.CS16_DEGEN_MSG[["seed-floor-lo"]] <- paste0("`seed` must be a single whole number in [0, 2",
            "^31 - 1] | got: -1 | the ARD initializer-seed",
            " property `seed` | construct with a whole-num",
            "ber seed in range")
.CS16_DEGEN_MSG[["seed-ceiling-hi"]] <- paste0("name=ard;mode=extract;np=0;pnames=;det=TRUE;n",
            "pkg=0;pkgs=;label=ARD-NMF (SignatureAnalyzer ",
            "semantics);a0=10;b0=5;tol=1e-05;mi=2000;seed=",
            "2147483647;fmt=<MsEngine> ARD-NMF (SignatureA",
            "nalyzer semantics) (ard) | mode: extract | de",
            "terministic")
.CS16_DEGEN_MSG[["seed-ceiling-lo"]] <- paste0("`seed` must be a single whole number in [0, 2",
            "^31 - 1] | got: 2147483648 | the ARD initiali",
            "zer-seed property `seed` | construct with a w",
            "hole-number seed in range")
.CS16_DEGEN_MSG[["tol-floor-hi"]] <- paste0("name=ard;mode=extract;np=0;pnames=;det=TRUE;n",
            "pkg=0;pkgs=;label=ARD-NMF (SignatureAnalyzer ",
            "semantics);a0=10;b0=5;tol=1e-300;mi=2000;seed",
            "=1;fmt=<MsEngine> ARD-NMF (SignatureAnalyzer ",
            "semantics) (ard) | mode: extract | determinis",
            "tic")
.CS16_DEGEN_MSG[["tol-floor-lo"]] <- paste0("`tol` must be a single finite number > 0 | go",
            "t: 0 | the ARD convergence-tolerance property",
            " `tol` | construct with a finite positive tol",
            "erance")
.CS16_DEGEN_MSG[["label-empty-hi"]] <- paste0("name=ard;mode=extract;np=0;pnames=;det=TRUE;n",
            "pkg=0;pkgs=;label=;a0=10;b0=5;tol=1e-05;mi=20",
            "00;seed=1;fmt=<MsEngine> ard (ard) | mode: ex",
            "tract | deterministic")
.CS16_DEGEN_MSG[["label-empty-lo"]] <- paste0("label must be a single string (empty allowed)",
            " | the label is an optional human-readable en",
            "gine name | received: 'NA' | pass a short lab",
            "el, or leave it empty")
.CS16_DEGEN_MSG[["mode-domain-hi"]] <- paste0("name=ard;mode=fit;np=0;pnames=;det=TRUE;npkg=",
            "0;pkgs=;label=ARD-NMF (SignatureAnalyzer sema",
            "ntics);a0=10;b0=5;tol=1e-05;mi=2000;seed=1;fm",
            "t=<MsEngine> ARD-NMF (SignatureAnalyzer seman",
            "tics) (ard) | mode: fit | deterministic")
.CS16_DEGEN_MSG[["mode-domain-lo"]] <- paste0("engine mode must be one of the known modes | ",
            "known modes: extract, fit | received: 'transf",
            "orm' | declare whether the engine extracts si",
            "gnatures or fits exposures")
.CS16_DEGEN_MSG[["a0-finite-ceil-hi"]] <- paste0("name=ard;mode=extract;np=0;pnames=;det=TRUE;n",
            "pkg=0;pkgs=;label=ARD-NMF (SignatureAnalyzer ",
            "semantics);a0=1e+308;b0=5;tol=1e-05;mi=2000;s",
            "eed=1;fmt=<MsEngine> ARD-NMF (SignatureAnalyz",
            "er semantics) (ard) | mode: extract | determi",
            "nistic")
.CS16_DEGEN_MSG[["a0-finite-ceil-lo"]] <- paste0("`a0` must be a single finite number > 0 | got",
            ": Inf | the ARD prior property `a0` | constru",
            "ct with ms_ard(a0 = , b0 = ) using positive v",
            "alues")
.CS16_SCAL_KEYS <- c("validator-class", "clause-a0", "clause-b0", "clause-tol", "clause-mi", "clause-seed", "canonical-shape", "rng-before", "rng-after")
.CS16_SCAL_VALS <- list()
.CS16_SCAL_VALS[["validator-class"]] <- "msuiter_error_engine"
.CS16_SCAL_VALS[["clause-a0"]] <- paste0("`a0` must be a single finite number > 0 | got",
            ": 0 | the ARD prior property `a0` | construct",
            " with ms_ard(a0 = , b0 = ) using positive val",
            "ues")
.CS16_SCAL_VALS[["clause-b0"]] <- paste0("`b0` must be a single finite number > 0 | got",
            ": 0 | the ARD prior property `b0` | construct",
            " with ms_ard(a0 = , b0 = ) using positive val",
            "ues")
.CS16_SCAL_VALS[["clause-tol"]] <- paste0("`tol` must be a single finite number > 0 | go",
            "t: 0 | the ARD convergence-tolerance property",
            " `tol` | construct with a finite positive tol",
            "erance")
.CS16_SCAL_VALS[["clause-mi"]] <- paste0("`max_iter` must be a single positive whole nu",
            "mber | got: 1.5 | the ARD iteration-cap prope",
            "rty `max_iter` | construct with a positive wh",
            "ole-number max_iter")
.CS16_SCAL_VALS[["clause-seed"]] <- paste0("`seed` must be a single whole number in [0, 2",
            "^31 - 1] | got: -1 | the ARD initializer-seed",
            " property `seed` | construct with a whole-num",
            "ber seed in range")
.CS16_SCAL_VALS[["canonical-shape"]] <- paste0("name=ard;mode=extract;np=0;pnames=;det=TRUE;n",
            "pkg=0;pkgs=;label=ARD-NMF (SignatureAnalyzer ",
            "semantics);a0=10;b0=5;tol=1e-05;mi=2000;seed=",
            "1;fmt=<MsEngine> ARD-NMF (SignatureAnalyzer s",
            "emantics) (ard) | mode: extract | determinist",
            "ic")
.CS16_SCAL_VALS[["rng-before"]] <- "FALSE"
.CS16_SCAL_VALS[["rng-after"]] <- "FALSE"
.CS16_SCAL_REFIRE <- list(
"clause-a0" = "ms_ard(a0 = 0)",
"clause-b0" = "ms_ard(b0 = 0)",
"clause-tol" = "ms_ard(tol = 0)",
"clause-mi" = "ms_ard(max_iter = 1.5)",
"clause-seed" = "ms_ard(seed = -1)",
"validator-class" = "MsArd(name = \"ARD\")",
"canonical-shape" = "ms_ard()"
)
.CS16_ARM <- list(
"sp-canonical" = "ms_ard()",
"sp-ctor-identity" = "MsArd()",
"sp-integer-hyper" = paste0("ms_ard(a0 = 10, b0 = 5, tol = 1, max_iter = 2",
            "000, seed = 0)"),
"sp-mode-fit-legal" = "MsArd(mode = \"fit\")",
"sp-params-named" = "MsArd(params = list(algo = \"kl\"))",
"sp-params-unnamed-passes" = "MsArd(params = list(1, 2))",
"sp-label-empty" = "MsArd(label = \"\")",
"sp-override-all" = paste0("MsArd(name = \"ard_x\", mode = \"fit\", params = ",
            "list(k = 1), deterministic = FALSE, packages ",
            "= c(\"rlang\"), label = \"Custom ARD\", a0 = 2, b",
            "0 = 3, tol = 1e-08, max_iter = 10, seed = 0)"),
"sp-replay-identity" = paste0("paste0(.cs16_shape(ms_ard()), \"==\", .cs16_sha",
            "pe(ms_ard()))"),
"lj-name-upper" = "MsArd(name = \"ARD\")",
"lj-name-hyphen" = "MsArd(name = \"a-b\")",
"lj-name-empty" = "MsArd(name = \"\")",
"lj-name-na" = "MsArd(name = NA_character_)",
"lj-mode-unknown" = "MsArd(mode = \"transform\")",
"lj-params-partial" = "MsArd(params = list(1, k = 2))",
"lj-params-null" = "MsArd(params = NULL)",
"lj-det-na" = "MsArd(deterministic = NA)",
"lj-pkgs-na" = "MsArd(packages = c(\"rlang\", NA))",
"lj-pkgs-empty" = "MsArd(packages = \"\")",
"lj-label-na" = "MsArd(label = NA_character_)",
"lj-name-num" = "MsArd(name = 123)",
"lj-mode-num" = "MsArd(mode = 7)",
"lj-params-vec" = "MsArd(params = \"kl\")",
"lj-det-string" = "MsArd(deterministic = \"yes\")",
"lj-pkgs-list" = "MsArd(packages = list())",
"lj-label-num" = "MsArd(label = 5)",
"lj-a0-zero" = "ms_ard(a0 = 0)",
"lj-a0-neg" = "ms_ard(a0 = -1)",
"lj-a0-inf" = "ms_ard(a0 = Inf)",
"lj-a0-nan" = "ms_ard(a0 = NaN)",
"lj-a0-na" = "ms_ard(a0 = NA_real_)",
"lj-a0-len2" = "ms_ard(a0 = c(1, 2))",
"lj-a0-str" = "ms_ard(a0 = \"10\")",
"lj-b0-zero" = "ms_ard(b0 = 0)",
"lj-b0-str" = "ms_ard(b0 = \"5\")",
"lj-tol-zero" = "ms_ard(tol = 0)",
"lj-tol-neg" = "ms_ard(tol = -1e-05)",
"lj-tol-inf" = "ms_ard(tol = Inf)",
"lj-tol-str" = "ms_ard(tol = \"1e-5\")",
"lj-mi-zero" = "ms_ard(max_iter = 0)",
"lj-mi-frac" = "ms_ard(max_iter = 1.5)",
"lj-mi-neg" = "ms_ard(max_iter = -3)",
"lj-mi-inf" = "ms_ard(max_iter = Inf)",
"lj-mi-str" = "ms_ard(max_iter = \"2000\")",
"lj-seed-neg" = "ms_ard(seed = -1)",
"lj-seed-frac" = "ms_ard(seed = 1.5)",
"lj-seed-above" = "ms_ard(seed = 2147483648)",
"lj-seed-str" = "ms_ard(seed = \"1\")",
"lj-seed-len2" = "ms_ard(seed = c(1, 2))",
"prec-name-over-mode" = "MsArd(name = \"ARD\", mode = \"transform\")",
"prec-mode-over-params" = paste0("MsArd(mode = \"transform\", params = list(1, k ",
            "= 2))"),
"prec-det-over-pkgs" = paste0("MsArd(deterministic = NA, packages = c(\"rlang",
            "\", NA))"),
"prec-pkgs-over-label" = paste0("MsArd(packages = c(\"rlang\", NA), label = NA_c",
            "haracter_)"),
"prec-shared-over-ard" = "MsArd(label = NA_character_, a0 = 0)",
"prec-a0-over-b0" = "ms_ard(a0 = 0, b0 = 0)",
"prec-tol-over-mi" = "ms_ard(tol = 0, max_iter = 0)",
"prec-mi-over-seed" = "ms_ard(max_iter = 1.5, seed = -1)",
"maxiter-floor-hi" = "ms_ard(max_iter = 1)",
"maxiter-floor-lo" = "ms_ard(max_iter = 0)",
"seed-floor-hi" = "ms_ard(seed = 0)",
"seed-floor-lo" = "ms_ard(seed = -1)",
"seed-ceiling-hi" = "ms_ard(seed = 2147483647)",
"seed-ceiling-lo" = "ms_ard(seed = 2147483648)",
"tol-floor-hi" = "ms_ard(tol = 1e-300)",
"tol-floor-lo" = "ms_ard(tol = 0)",
"label-empty-hi" = "MsArd(label = \"\")",
"label-empty-lo" = "MsArd(label = NA_character_)",
"mode-domain-hi" = "MsArd(mode = \"fit\")",
"mode-domain-lo" = "MsArd(mode = \"transform\")",
"a0-finite-ceil-hi" = "ms_ard(a0 = 1e308)",
"a0-finite-ceil-lo" = "ms_ard(a0 = Inf)"
)
.CS16_CENSUS <- c("msuiter_error_engine=41", "msuiter_error_internal=2", "s7:character=1", "s7:msuiter::MsArd=15", "simpleError=12")
## <<CS16-FROZEN-END>> ##

## <<CS16-SHARED-BEGIN>>  (single source: injected byte-identically into
##    the law file and the runner; edit /tmp/p6gate/cs16-shared.R and
##    re-splice via splice-cs16.R -- never hand-edit in place)
.cs16_describe <- function(e) trimws(gsub("\n", " | ",
  paste(as.character(conditionMessage(e)), collapse = " | "), fixed = TRUE))
.cs16_strip <- function(s) {
  for (b in c("ℹ ", "i ")) s <- gsub(b, "", s, fixed = TRUE)
  s
}
.cs16_shape <- function(x) {
  pn <- names(x@params)
  if (is.null(pn)) pn <- character(0L)
  paste0(
    "name=", x@name,
    ";mode=", x@mode,
    ";np=", length(x@params),
    ";pnames=", paste0(pn, collapse = ","),
    ";det=", format(x@deterministic),
    ";npkg=", length(x@packages),
    ";pkgs=", paste0(x@packages, collapse = ","),
    ";label=", x@label,
    ";a0=", format(x@a0),
    ";b0=", format(x@b0),
    ";tol=", format(x@tol),
    ";mi=", format(x@max_iter),
    ";seed=", format(x@seed),
    ";fmt=", format(x))
}
.cs16_eval1 <- function(txt, tag) {
  if (is.na(txt) || !nzchar(txt)) stop(".cs16_eval1: no text for ", tag)
  ex <- parse(text = txt)
  if (length(ex) != 1L) {
    stop(".cs16_eval1: ", tag, " is not a single expression")
  }
  tryCatch(list(ok = TRUE, v = eval(ex[[1L]])), error = identity)
}
.cs16_verdict <- function(arm, r) {
  if (inherits(r, "error")) {
    list(arm = arm, mode = "reject", cls = class(r)[1L],
         msg = gsub("\t", " ", .cs16_strip(.cs16_describe(r)), fixed = TRUE))
  } else {
    rendered <- if (is.character(r)) r else .cs16_shape(r)
    list(arm = arm, mode = "accept", cls = paste0("s7:", class(r)[1L]),
         msg = gsub("\t", " ", rendered, fixed = TRUE))
  }
}
.cs16_fire <- function(arm) {
  r <- .cs16_eval1(.CS16_ARM[[arm]], arm)
  .cs16_verdict(arm, if (inherits(r, "error")) r else r$v)
}
.cs16_clean <- function(df) {
  ## witness bytes round-trip nameless through read.csv; strip any vapply
  ## residue names so identical() compares columns byte-true
  for (cnm in names(df)) attr(df[[cnm]], "names") <- NULL
  df
}
.cs16_rows <- function(arms) {
  vs <- lapply(arms, function(a) .cs16_fire(a))
  .cs16_clean(data.frame(arm = arms,
             mode = vapply(vs, function(z) z$mode, character(1L)),
             cls = vapply(vs, function(z) z$cls, character(1L)),
             msg = vapply(vs, function(z) z$msg, character(1L)),
             stringsAsFactors = FALSE))
}
.cs16_lawrows <- function() .cs16_rows(.CS16_LAW_ARMS)
.cs16_specrows <- function() .cs16_rows(.CS16_SPEC_ARMS)
.cs16_precrows <- function() {
  base <- .cs16_rows(.CS16_PREC_ARMS)
  base$fires_ok <- unname(vapply(seq_along(base$arm), function(i) {
    paste0(grepl(.CS16_PREC_FIRES[i], base$msg[i], fixed = TRUE))
  }, character(1L)))
  base$anti_ok <- unname(vapply(seq_along(base$arm), function(i) {
    paste0(!grepl(.CS16_PREC_ANTI[i], base$msg[i], fixed = TRUE))
  }, character(1L)))
  base
}
.cs16_degenrows <- function() {
  vs <- lapply(.CS16_DEGEN_ARMS, function(a) .cs16_fire(a))
  .cs16_clean(data.frame(pair = .CS16_DEGEN_PAIR, side = .CS16_DEGEN_SIDE,
             arm = .CS16_DEGEN_ARMS,
             mode = vapply(vs, function(z) z$mode, character(1L)),
             cls = vapply(vs, function(z) z$cls, character(1L)),
             msg = vapply(vs, function(z) z$msg, character(1L)),
             stringsAsFactors = FALSE))
}
.cs16_scalval <- function(k) {
  txt <- .CS16_SCAL_REFIRE[[k]]
  if (is.null(txt)) return(NA_character_)
  res <- .cs16_eval1(txt, k)
  if (inherits(res, "error")) {
    if (identical(k, "validator-class")) return(paste0(class(res)[1L]))
    return(.cs16_strip(.cs16_describe(res)))
  }
  r <- res$v
  if (identical(k, "canonical-shape")) return(.cs16_shape(r))
  paste0(r)
}
.cs16_scalref_keys <- function() names(.CS16_SCAL_REFIRE)
.cs16_plant_text <- function() {
  ord <- c(.CS16_LAW_ARMS, .CS16_SPEC_ARMS, .CS16_PREC_ARMS, .CS16_DEGEN_ARMS)
  paste0(vapply(ord, function(a)
    paste0(a, "=", .CS16_ARM[[a]]), character(1L)), collapse = ";")
}
.cs16_spec_text <- function() paste0(.CS16_SPEC_ARMS, collapse = ";")
## <<CS16-SHARED-END>>  (do not hand-edit in place: edit the source and
##    re-splice) ##
##    re-splice) ##
##    re-splice) ##
##    re-splice) ##
##    re-splice) ##
##    re-splice) ##
##    re-splice) ##
##    re-splice) ##

## ---------------------------------------------------------------------------
## writers, census and the dual-kernel hash rail
## ---------------------------------------------------------------------------
.wtab <- function(nm, df) {
  con <- file(file.path(OUT, nm), open = "wb")
  on.exit(close(con))
  write.table(df, con, sep = "\t", quote = FALSE, row.names = FALSE, na = "")
  invisible(nm)
}
.census <- function(nm, df, want.rows, key.col = 1L) {
  stopif(nrow(df) != want.rows, paste0("census ", nm, ": rows ", nrow(df)))
  stopif(any(duplicated(df[[key.col]])), paste0("census ", nm, ": duplicate keys"))
  for (cnm in names(df)) {
    col <- df[[cnm]]
    bad <- !is.character(col) || any(is.na(col)) || any(!nzchar(col)) ||
      any(grepl("\t", col, fixed = TRUE))
    stopif(bad, paste0("census ", nm, ".", cnm, ": non-character/NA/empty/tab"))
  }
  invisible(TRUE)
}
.ck <- function(bytes, tag) {
  a <- .ms_fit_sha256(bytes)
  b <- digest::digest(bytes, algo = "sha256", serialize = FALSE)
  stopif(!identical(a, b), paste0("ck: kernel disagreement on ", tag))
  stopif(!grepl("^[0-9a-f]{64}$", a), paste0("ck: hex policy on ", tag))
  stopif(nchar(a) != 64L, paste0("ck: length on ", tag))
  a
}
.file.sha <- function(nm) {
  p <- file.path(OUT, nm)
  con <- file(p, open = "rb")
  on.exit(close(con))
  bytes <- readBin(con, what = raw(), n = file.size(p))
  .ck(bytes, nm)
}

## ---------------------------------------------------------------------------
## build the five witness tables, rail-checked against the frozen block
## ---------------------------------------------------------------------------
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

laws <- .cs16_lawrows()
stopif(!identical(laws$arm, .CS16_LAW_ARMS), "laws: roster drift")
stopif(!identical(laws$mode, rep("reject", 40L)), "laws: a mode drift")
stopif(!identical(laws$cls, .CS16_LAW_CLS), "laws: a class drift")
stopif(!identical(laws$msg, unname(vapply(.CS16_LAW_ARMS,
  function(a) .CS16_LAW_CLAUSES[[a]], character(1L)))), "laws: clause byte drift")
.census("laws", laws, 40L)

specs <- .cs16_specrows()
stopif(!identical(specs$arm, .CS16_SPEC_ARMS), "specs: roster drift")
stopif(!identical(specs$mode, rep("accept", 9L)), "specs: a mode drift")
stopif(!identical(specs$cls, .CS16_SPEC_CLS), "specs: a class drift")
stopif(!identical(specs$msg, unname(vapply(.CS16_SPEC_ARMS,
  function(a) .CS16_SPEC_DETAILS[[a]], character(1L)))), "specs: detail byte drift")
.census("specs", specs, 9L)

prec <- .cs16_precrows()
stopif(!identical(prec$arm, .CS16_PREC_ARMS), "prec: roster drift")
stopif(!identical(prec$mode, rep("reject", 8L)), "prec: a mode drift")
stopif(!identical(prec$cls, .CS16_PREC_CLS), "prec: a class drift")
stopif(!all(prec$fires_ok == "TRUE"), "prec: a fired anchor missing")
stopif(!all(prec$anti_ok == "TRUE"), "prec: an anti anchor present")
for (i in seq_len(8L)) {
  stopif(!grepl(.CS16_PREC_FIRES[i], prec$msg[i], fixed = TRUE),
         paste0("prec: fire anchor absent in ", .CS16_PREC_ARMS[i]))
  stopif(grepl(.CS16_PREC_ANTI[i], prec$msg[i], fixed = TRUE),
         paste0("prec: anti anchor present in ", .CS16_PREC_ARMS[i]))
}
.census("prec", prec, 8L)

degen <- .cs16_degenrows()
stopif(!identical(degen$pair, .CS16_DEGEN_PAIR), "degen: pair drift")
stopif(!identical(degen$side, .CS16_DEGEN_SIDE), "degen: side drift")
stopif(!identical(degen$arm, .CS16_DEGEN_ARMS), "degen: arm drift")
stopif(!identical(degen$mode, .CS16_DEGEN_MODE), "degen: mode drift")
stopif(!identical(degen$cls, .CS16_DEGEN_CLS), "degen: class drift")
stopif(!identical(degen$msg, unname(vapply(.CS16_DEGEN_ARMS,
  function(a) .CS16_DEGEN_MSG[[a]], character(1L)))), "degen: msg byte drift")
stopif(!all(degen$mode[degen$side == "hi"] == "accept"), "degen: a hi side rejects")
stopif(!all(degen$mode[degen$side == "lo"] == "reject"), "degen: a lo side accepts")
.census("degen", degen, 14L, key.col = 3L)

rng1 <- exists(".Random.seed", envir = globalenv(), inherits = TRUE)
scal.vals <- vapply(.CS16_SCAL_KEYS, function(k) {
  if (identical(k, "rng-before")) return(format(rng0))
  if (identical(k, "rng-after")) return(format(rng1))
  v <- .cs16_scalval(k)
  stopif(is.na(v) || !nzchar(v), paste0("scalars: empty re-fire for ", k))
  stopif(!identical(v, .CS16_SCAL_VALS[[k]]), paste0("scalars: drift for ", k))
  v
}, character(1L))
scalars <- data.frame(key = .CS16_SCAL_KEYS, value = unname(scal.vals),
                      stringsAsFactors = FALSE)
stopif(!identical(scalars$value[match("rng-before", .CS16_SCAL_KEYS)],
                  .CS16_SCAL_VALS[["rng-before"]]), "scalars: rng-before drift")
stopif(!identical(scalars$value[match("rng-after", .CS16_SCAL_KEYS)],
                  .CS16_SCAL_VALS[["rng-after"]]), "scalars: rng-after drift")
.census("scalars", scalars, 9L)

## dual-kernel hashes over the frozen corpora (written nowhere, attested)
plant.sha <- .ck(charToRaw(.cs16_plant_text()), "plant-corpus")
spec.sha <- .ck(charToRaw(.cs16_spec_text()), "spec-corpus")

## ---------------------------------------------------------------------------
## all censuses spoke: commit the five witnesses
## ---------------------------------------------------------------------------
.wtab("cs16_laws.tsv", laws)
.wtab("cs16_specs.tsv", specs)
.wtab("cs16_precedence.tsv", prec)
.wtab("cs16_degenerates.tsv", degen)
.wtab("cs16_scalars.tsv", scalars)

cat("[attest] at=", format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
    " out=", OUT, "\n", sep = "")
for (nm in c("cs16_laws.tsv", "cs16_specs.tsv", "cs16_precedence.tsv",
             "cs16_degenerates.tsv", "cs16_scalars.tsv")) {
  cat("[attest] sha256 ", nm, "=", .file.sha(nm), "\n", sep = "")
}
cat("[attest] plant_sha256=", plant.sha, " spec_sha256=", spec.sha,
    " files=", length(list.files(OUT, pattern = "^cs16_")), "\n", sep = "")
cat("OVERALL PASS\n")
quit(save = "no", status = 0L)
