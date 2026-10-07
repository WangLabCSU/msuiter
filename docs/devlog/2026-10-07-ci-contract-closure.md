# CI contract closure (round-7, 2026-10-07)

First run in repository history with the complete check matrix green on the
main tip: 13/13 check-runs success on 20655fa (run #32):

- R-CMD-check: 3 OS x {release, oldrel-1} + {4.3 Linux floor, devel} — all
  success, **including the devel arm at check-run level** (informative-only
  posture retained as the r-lib convention, but it now genuinely passes).
- rust (test/clippy -D warnings/deny four sections), guards (dep-direction,
  rng-KAT, G0 suite, ci-selfcheck 65/65, Cargo.lock pin assert, vendor budget,
  repo-mode testthat), msrv {ubuntu, windows}, coverage (upload-only).

Seven-root-cause chain, each pinned by a ci-selfcheck assertion so it cannot
silently regress:

1. empty `dependencies:` input renders `c(needs, ())` — split into two
   guarded steps (input physically absent unless set).
2. `error_on` vs the action's hyphenated `error-on` input name.
3. 4.3 floor arm needs `dependencies: '"hard"'` to dodge the unsolvable Bioc
   Suggests chain (BSgenome 404 on the 4.3 view).
4. `install-pandoc: 'true'` — the action's auto probe would drag the very
   Suggests the hard cap exists to exclude.
5. vignette builder knitr + plot/sanitize stack as CRAN-only `any::` extras.
6. `error-on` input is a RAW R expression: value must carry its own quotes
   ('"error"'), a bare symbol aborts "object 'error' not found".
7. hard cap also drops the Suggests-side testthat/withr the check tests
   need — testthat stack rides in as CRAN-only extras too.
8. devel arm double-fix: sitrep assertion admits R's "Under development"
   self-report string; xval skip path suppresses the upstream Bioc
   import-collision notice that --as-cran would escalate to a package WARN.

Standing gates unchanged: --as-cran strictness where tools exist,
error-level check gate (hard gates live in guards + scheduled valgrind),
_R_CHECK_LIMIT_CORES_ thread discipline, fail-fast off, devel allowed to
fail by policy even while green.
