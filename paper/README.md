# paper/ — the manuscript corpus

This tree holds everything the paper is built from: the manuscript itself and
the dated records that feed it. It is deliberately **outside the R package**:
nothing here is compiled, installed, tested, or rendered on the pkgdown site,
and the package never reads these files at runtime. The one intentional
coupling is the figure-roster law, `tools/manuscript-fig5-roster.R`, which
reads `paper/paper-draft.qmd` from the repository root and cross-checks its
Fig. 5 panel list against the witness scripts it cites.

## What lives here

| Class | Files | What it is |
|---|---|---|
| Manuscript | `paper-draft.qmd` | The manuscript spine (PP-1). Every number carries a `file:line` or commit anchor into committed evidence; undecided claims sit in explicit `[GATED: ...]` blocks. |
| Campaign devlogs | `devlog-*.qmd` (91) | The dated decision and delivery records of the whole campaign, oldest first. Each records what was done, the decisions taken (with their D-clause citations), the review rounds, and what was left open. |
| Research dossiers | `research-*.qmd` (10) | The pre-implementation survey corpus: method panoramas, fitting/inference semantics, source audits, standards and licensing, the algorithm zoo. |
| Independent reviews | `review-*.qmd` (6) | The five-expert adversarial review round and its synthesis — the "why" evidence behind the architecture. |
| Release record | `release-v0.1-checklist.qmd` | The v0.1 release-engineering preparation checklist. |

## Working with the corpus

Render the manuscript with Quarto from the repository root:

```sh
quarto render paper/paper-draft.qmd
```

Devlogs and dossiers are plain Quarto documents and render the same way.
Cross-references between corpus files point at `paper/<slug>.qmd` sources on
GitHub (the corpus is no longer a pkgdown article set, so there are no site
pages to link to).

## Ground rules

- New campaign work adds one `devlog-YYYY-MM-DD-<topic>.qmd` here and one row
  in the manuscript's section-3.4 witness list plus the section-8 Fig. 5 row
  **in the same commit** — `tools/manuscript-fig5-roster.R` (wired into CI as
  `test-manuscript-fig5-roster.R`) fails the build if the two rosters drift.
- Quantitative claims in the manuscript cite committed evidence under
  `bench/` (witness tables, campaign results). Nothing in this tree may
  assert a number that no committed witness backs.
- The corpus is self-contained: it depends on the repository, not on the
  package's `Suggests`, and contributes nothing to `R CMD check`.
