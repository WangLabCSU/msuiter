# M7 benchmark ergonomics — the three-function trio stays three

Date: 2026-10-10 (U-M7-04 slice-B, item B3). Ruling issued by the
controller; recorded here as decided — this document does not
re-litigate it.

## Context

The v1 driver header (`R/ms-benchmark-driver.R`, design memo
`docs/devlog/2026-10-05-benchmark-design-memo.md`, D1/D2 stage) left one
ergonomics question open, verbatim in the file until today:

> the M0 container constructor keeps the name ms_benchmark(results,
> settings); the DRIVER is ms_run_benchmark() in this version -- whether
> the two merge behind one generic is an M7 polish decision, not a v1
> blocker.

Users reaching for "run a benchmark" meet three exported names and the
help system gives them no connective tissue.

## Ruling (controller decision, 2026-10-10)

1. `ms_benchmark(results, settings)` stays the **S7 container
   constructor** — it builds and validates an `MsBenchmark` from an
   already-scored results frame; it never executes anything.
2. `ms_run_benchmark()` stays the **single user entry for execution** —
   the one way to drive a grid through extraction and scoring.
3. `ms_benchmark_grid()` stays the **grid spec-builder**.
4. **No generic merge (YAGNI).** The three signatures and failure
   contracts are distinct and each is individually test-pinned
   (`test-classes-benchmark.R`, `test-ms-benchmark-driver.R`); a generic
   would add dispatch surface with no second implementation demanding it.

## Implementation

- Each of the three `@description` blocks now carries the same mutual
  pointer sentence — "Create specs with `ms_benchmark_grid()`, execute
  with `ms_run_benchmark()`, store via `ms_benchmark()`" — with the
  self-reference left as plain text and the other two as topics.
- `@family benchmark` added to all three blocks; roxygen2 (0.3.29)
  renders each topic an `\seealso{Other benchmark: ...}` cross-link
  section plus `\concept{benchmark}`.
- The driver header's open-question note is replaced by a pointer at
  this record.
- `man/` regenerated with roxygen2, not hand-edited (the `% Generated
  by roxygen2: do not edit by hand` law).

## Verification

- Regeneration trust established first: a `roxygenise()` run over the
  unedited tree reproduced every committed Rd byte-exactly (empty
  `git status man/ NAMESPACE`), proving the local roxygen2 matches the
  state every committed Rd was generated in.
- Post-edit, the working-tree delta is confined to exactly the five
  intended files: `R/ms-benchmark-driver.R`, `R/classes-benchmark.R`,
  `man/ms_benchmark.Rd`, `man/ms_benchmark_grid.Rd`,
  `man/ms_run_benchmark.Rd`.
- Bracket-link rendering in `\description{}`/`\item{}` stays literal —
  identical to the committed precedent (`man/ms_run_benchmark.Rd` already
  carried `[ms_benchmark_grid()]` verbatim in `\item{grid}` before this
  change).
- Targeted testthat against the installed current tree:
  `test-ms-benchmark-driver.R` **72 pass / 0 fail / 0 skip**,
  `test-classes-benchmark.R` **23 pass / 0 fail / 0 skip**
  (`stop_on_failure = TRUE`, rc 0). No house man-roxygen consistency
  gate exists in CI; the byte-exact baseline reproduction above is the
  equivalent assurance for this change.
- No new top-level CI checks (frozen 13-check topology untouched).

## Consequence

The help system alone now answers "which of the three do I call first":
any of the three topics cross-links the other two under
*Other benchmark*, and each description states the trio's roles in one
sentence. The open question is closed; the functions and signatures are
unchanged, so no user-visible API movement occurs.
