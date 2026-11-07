"""The G0 pilot-coverage-experiment harness (the own part: simulation / seeds / coverage / LRT / grid).

The protocol's sources of fact (frozen; not alterable in the code):
- vignettes/articles/devlog-2026-09-28-G0-pi-adjudication.qmd   (the F1–F4 freeze + the two diagnostic columns added after the freeze)
- vignettes/articles/devlog-2026-09-28-G0-protocol-memo.qmd     (the full protocol: §2.3 the grid/seeds, §2.4 the judgment rules)
- vignettes/articles/devlog-2026-09-28-G0-realism-memo.qmd      (the grid low end ~30, the NB arm a must-pick, the clock-mixing arm)
- vignettes/articles/devlog-2026-09-28-assumption-audit-memo.qmd(the basis of the P1/P3 added columns)

The licensing red line: the COSMIC signature matrices are never checked into the repository (D3). The signature data has only two sources:
the synthetic provider (the default, for development/tests) and the cosmic-file provider (the user supplies
the environment variable G0_SIGNATURES_PATH, with a hard validation against the SBS96.txt label order on load).

This package is a bench comparator and never enters the msuiter package body (D9).
"""
