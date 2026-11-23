# test-scenario-ard-witness.R -- the CS-16 ard-witness law units
# (pillar 3). The scenario plants synthetic constructor calls (the D3 law:
# zero COSMIC numeric matrices, zero real-data bytes, zero downloads --
# ARD/NMF/SBS ride only as FORMAT NAMES) and adjudicates the EXPORTED
# ms_ard() face: the shared engine admission laws (name/mode/params/
# deterministic/packages/label), the S7 property-gate split against the
# validator, the ARD prior laws (a0/b0 positive-finite, tol positive-finite,
# max_iter positive whole, seed whole in [0, 2^31 - 1]), the third abort
# class the len-2 hyper values reach when the got:/format() bullet
# vectorises, the precedence discriminators with their anti anchors, the
# degenerate boundaries and the acceptance specs. The witness bytes under
# bench/scenarios/out/ (cs16_laws.tsv, cs16_specs.tsv, cs16_precedence.tsv,
# cs16_degenerates.tsv, cs16_scalars.tsv) are the committed verdict: a
# drift in a fired clause, an observed error class, an accepted shape or
# the precedence order reddens here before print. The plants are synthetic
# -- no RNG consumption, no network, no COSMIC bytes; the lane NEVER calls
# the benchmark driver, the declined calibration family, the registry face
# or any validator internal (banned words, grepped over the runner source).
# Framing law: DECISION RECORD only. What the face says on planted truth --
# the accepted shapes, the abort classes, the fired bullets -- is an
# OBSERVED, COMMITTED record, never a fidelity claim beyond what was
# measured. Cross-platform posture (D11): integer, label, logical, class
# and clause bytes are byte-committed; the face produces no float payload
# columns (hyper values ride to the validator as verdicts, not prints), so
# no float glyph rides any witness.
# The frozen block and the shared code block below are MINTED mechanically
# from the audited probe ledger (gen-frozen.cs16.R / probe-cs16.R); neither
# is ever hand-edited in place.

.rs_out16 <- function(fname) {
  file.path(.ms_root, "bench", "scenarios", "out", fname)
}

# The committed tables are written quote-free; quote = "" keeps every
# double quote inside the clauses literal on read.
.rs_tsv16 <- function(fname) {
  read.csv(.rs_out16(fname), header = TRUE, sep = "\t",
           stringsAsFactors = FALSE, na.strings = "", colClasses = "character",
           quote = "")
}

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
##    re-splice) ##

# ===========================================================================
# U1 -- rails: the runner exists and speaks the exported face, never an
# internal (banned-word grep over its full source).
# ===========================================================================
test_that("runner speaks the exported-face rails", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  runner <- file.path(.ms_root, "bench", "scenarios", "run_ard_witness.R")
  expect_true(file.exists(runner))
  src <- paste(readLines(runner, warn = FALSE), collapse = "\n")
  for (need in c("--file=", "[attest]", "OVERALL PASS", "ms_ard(", "cs16_",
                 "commandArgs", "digest::digest", "serialize = FALSE",
                 "charToRaw", "open = \"wb\"", "na = \"\"", "quote = FALSE",
                 "row.names = FALSE", "RNG-STATE-RAIL", ".ms_fit_sha256")) {
    expect_true(grepl(need, src, fixed = TRUE), info = need)
  }
  ## The bans govern the hand-written region: the minted frozen block is
  ## OBSERVED DATA and legitimately quotes the face's own bytes (the
  ## internal-class clause names msuiter_abort and the packages clause
  ## cites required_pkgs). Slice the two injected regions out before the
  ## absence scan; marker integrity itself is rail-checked here.
  lines <- strsplit(src, "\n", fixed = TRUE)[[1L]]
  .region <- function(beg, end) {
    b <- which(vapply(lines, function(l) grepl(beg, l, fixed = TRUE), logical(1L)))
    e <- which(vapply(lines, function(l) grepl(end, l, fixed = TRUE), logical(1L)))
    expect_identical(length(b), 1L, info = beg)
    expect_identical(length(e), 1L, info = end)
    c(b, e)
  }
  drop <- c(seq(.region("## <<CS16-FROZEN-BEGIN", "## <<CS16-FROZEN-END")[1]:
                .region("## <<CS16-FROZEN-BEGIN", "## <<CS16-FROZEN-END")[2]),
            seq(.region("## <<CS16-SHARED-BEGIN", "## <<CS16-SHARED-END")[1]:
                .region("## <<CS16-SHARED-BEGIN", "## <<CS16-SHARED-END")[2]))
  hand <- paste(lines[-drop], collapse = "\n")
  expect_gt(nchar(hand), 1000L)
  for (ban in c("msuiter:::", "msuiter_validate_", "msuiter_abort",
                "new(", "set.seed", "sample(", "runif(", "rnorm(",
                "download.file", "http", "unlink(", "Sys.setenv",
                "system2(", "readLines(", "expect_",
                "ms_calibration_grid", "ms_fit_bootstrap",
                "ms_calibration_sanity", "ms_select_k", "run_benchmark",
                "required_pkgs", "install_required", "load_registry_once",
                "register_engine(", "register_ard_engine(", "match_ms_engine",
                "ms_engines(", "ms_registry", "new_class(", "new.env(",
                "set_props")) {
    expect_false(grepl(ban, hand, fixed = TRUE), info = ban)
  }
})

# ===========================================================================
# U2 -- witness existence and shape: five committed TSVs, non-zero, with
# hard row-count gates and an all-character no-NA census (no vacuous green).
# ===========================================================================
test_that("the five witnesses exist with hard shape gates", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  for (f in c("cs16_laws.tsv", "cs16_specs.tsv", "cs16_precedence.tsv",
              "cs16_degenerates.tsv", "cs16_scalars.tsv")) {
    expect_true(file.exists(.rs_out16(f)))
    expect_gt(file.size(.rs_out16(f)), 0)
  }
  lw <- .rs_tsv16("cs16_laws.tsv"); sp <- .rs_tsv16("cs16_specs.tsv")
  pr <- .rs_tsv16("cs16_precedence.tsv"); dg <- .rs_tsv16("cs16_degenerates.tsv")
  sc <- .rs_tsv16("cs16_scalars.tsv")
  expect_identical(nrow(lw), 40L)
  expect_identical(nrow(sp), 9L)
  expect_identical(nrow(pr), 8L)
  expect_identical(nrow(dg), 14L)
  expect_true("key" %in% names(sc) && "value" %in% names(sc))
  expect_true(all(sc$key %in% .CS16_SCAL_KEYS))
  expect_identical(nrow(sc), length(.CS16_SCAL_KEYS))
  for (df in list(lw, sp, pr, dg, sc)) {
    expect_true(all(vapply(df, is.character, logical(1L))))
    expect_false(any(vapply(df, function(cc) any(is.na(cc)), logical(1L))))
    expect_false(any(vapply(df, function(cc) any(!nzchar(cc)), logical(1L))))
  }
})

# ===========================================================================
# U3 -- the laws witness mirrors the frozen law table: 40 arms, classes and
# verbatim clauses, byte for byte.
# ===========================================================================
test_that("committed laws mirror the frozen law table", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  lw <- .rs_tsv16("cs16_laws.tsv")
  expect_identical(lw$arm, .CS16_LAW_ARMS)
  expect_identical(lw$mode, rep("reject", 40L))
  expect_identical(lw$cls, .CS16_LAW_CLS)
  expect_identical(lw$msg, unname(vapply(.CS16_LAW_ARMS,
    function(a) .CS16_LAW_CLAUSES[[a]], character(1L))))
})

# ===========================================================================
# U4 -- live replay of the law arms: every arm still rejects with its
# committed class and its committed clause bytes ride the live message.
# ===========================================================================
test_that("law arms replay live through the face", {
  live <- .cs16_lawrows()
  expect_identical(live$arm, .CS16_LAW_ARMS)
  expect_identical(live$mode, rep("reject", 40L))
  expect_identical(live$cls, .CS16_LAW_CLS)
  expect_identical(live$msg, unname(vapply(.CS16_LAW_ARMS,
    function(a) .CS16_LAW_CLAUSES[[a]], character(1L))))
})

# ===========================================================================
# U5 -- the specs witness mirrors the frozen acceptance table, and the
# acceptance arms replay live: the face still returns what was committed.
# ===========================================================================
test_that("specs witness mirrors frozen and replays live", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  sp <- .rs_tsv16("cs16_specs.tsv")
  expect_identical(sp$arm, .CS16_SPEC_ARMS)
  expect_identical(sp$mode, rep("accept", 9L))
  expect_identical(sp$cls, .CS16_SPEC_CLS)
  expect_identical(sp$msg, unname(vapply(.CS16_SPEC_ARMS,
    function(a) .CS16_SPEC_DETAILS[[a]], character(1L))))
  live <- .cs16_specrows()
  expect_identical(live$arm, sp$arm)
  expect_identical(live$mode, sp$mode)
  expect_identical(live$cls, sp$cls)
  expect_identical(live$msg, sp$msg)
})

# ===========================================================================
# U6 -- the precedence witness: committed class, fired anchor PRESENT and
# anti anchor ABSENT in every arm, live replay included.
# ===========================================================================
test_that("precedence witness speaks anchors both ways", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  pr <- .rs_tsv16("cs16_precedence.tsv")
  expect_identical(pr$arm, .CS16_PREC_ARMS)
  expect_identical(pr$mode, rep("reject", 8L))
  expect_identical(pr$cls, .CS16_PREC_CLS)
  expect_identical(pr$fires_ok, rep("TRUE", 8L))
  expect_identical(pr$anti_ok, rep("TRUE", 8L))
  for (i in seq_len(8L)) {
    expect_true(grepl(.CS16_PREC_FIRES[i], pr$msg[i], fixed = TRUE),
                info = .CS16_PREC_ARMS[i])
    expect_false(grepl(.CS16_PREC_ANTI[i], pr$msg[i], fixed = TRUE),
                 info = .CS16_PREC_ARMS[i])
  }
  live <- .cs16_precrows()
  expect_identical(live$msg, pr$msg)
})

# ===========================================================================
# U7 -- the degenerate witness: seven boundary pairs, hi accepts / lo
# rejects by the committed law, replayed live against the committed bytes.
# ===========================================================================
test_that("degenerate boundaries hold on both sides", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  dg <- .rs_tsv16("cs16_degenerates.tsv")
  expect_identical(dg$pair, .CS16_DEGEN_PAIR)
  expect_identical(dg$side, .CS16_DEGEN_SIDE)
  expect_identical(dg$arm, .CS16_DEGEN_ARMS)
  expect_identical(dg$mode, .CS16_DEGEN_MODE)
  expect_identical(dg$cls, .CS16_DEGEN_CLS)
  expect_identical(dg$msg, unname(vapply(.CS16_DEGEN_ARMS,
    function(a) .CS16_DEGEN_MSG[[a]], character(1L))))
  expect_true(all(dg$mode[dg$side == "hi"] == "accept"))
  expect_true(all(dg$mode[dg$side == "lo"] == "reject"))
  live <- .cs16_degenrows()
  expect_identical(live$msg, dg$msg)
})

# ===========================================================================
# U8 -- the scalars witness: the re-fireable keys replay live to their
# committed bytes; the rng keys ride the committed purity verdict.
# ===========================================================================
test_that("scalars witness replays and the rng rail stays frozen", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  sc <- .rs_tsv16("cs16_scalars.tsv")
  expect_identical(sort(sc$key), sort(.CS16_SCAL_KEYS))
  rf <- .cs16_scalref_keys()
  for (k in rf) {
    expect_identical(sc$value[match(k, sc$key)], .cs16_scalval(k), info = k)
    expect_identical(.CS16_SCAL_VALS[[k]], sc$value[match(k, sc$key)], info = k)
  }
  for (k in setdiff(.CS16_SCAL_KEYS, rf)) {
    expect_true(k %in% c("rng-before", "rng-after"))
    expect_identical(sc$value[match(k, sc$key)], .CS16_SCAL_VALS[[k]], info = k)
  }
})

# ===========================================================================
# U9 -- dual-kernel SHA-256: the frozen plant corpus and the spec roster
# hash identically under both governed kernels and speak the hex policy.
# ===========================================================================
test_that("plant and spec corpora agree under both sha256 kernels", {
  for (tag in c("plant", "spec")) {
    txt <- if (identical(tag, "plant")) .cs16_plant_text() else .cs16_spec_text()
    ## measured corpora: plant 1586, spec 155 bytes; the floors catch an
    ## emptied or truncated roster, not a glyph style
    expect_gt(nchar(txt), if (identical(tag, "plant")) 1000L else 100L)
    bytes <- charToRaw(txt)
    a <- .ms_fit_sha256(bytes)
    b <- digest::digest(bytes, algo = "sha256", serialize = FALSE)
    expect_identical(a, b, info = tag)
    expect_true(grepl("^[0-9a-f]{64}$", a), info = tag)
    expect_false(grepl("[^0-9a-f]", a, perl = TRUE), info = tag)
    expect_identical(nchar(a), 64L)
  }
})

# ===========================================================================
# U10 -- frozen roster shape: counts, census recomputation, registry
# coverage, single-expression parsability and roster disjointness.
# ===========================================================================
test_that("the frozen roster speaks its own shape", {
  expect_identical(length(.CS16_LAW_ARMS), 40L)
  expect_identical(length(.CS16_SPEC_ARMS), 9L)
  expect_identical(length(.CS16_PREC_ARMS), 8L)
  expect_identical(length(.CS16_DEGEN_ARMS), 14L)
  expect_identical(length(.CS16_SCAL_KEYS), 9L)
  expect_identical(length(.CS16_ARM), 71L)
  expect_identical(length(.CS16_CENSUS), 5L)
  allc <- c(.CS16_LAW_ARMS, .CS16_SPEC_ARMS, .CS16_PREC_ARMS, .CS16_DEGEN_ARMS)
  expect_false(any(duplicated(allc)))
  expect_true(all(allc %in% names(.CS16_ARM)))
  for (a in names(.CS16_ARM)) {
    expect_identical(length(parse(text = .CS16_ARM[[a]])), 1L, info = a)
  }
  allcls <- c(.CS16_LAW_CLS, .CS16_PREC_CLS, .CS16_SPEC_CLS, .CS16_DEGEN_CLS)
  tally <- function(cl) paste0(cl, "=", sum(allcls == cl))
  want <- c(tally("msuiter_error_engine"), tally("msuiter_error_internal"),
            tally("simpleError"), tally("s7:character"),
            tally("s7:msuiter::MsArd"))
  expect_true(all(want %in% .CS16_CENSUS))
  expect_identical(sort(.CS16_CENSUS), sort(want))
})
