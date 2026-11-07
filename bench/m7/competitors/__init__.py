"""U-M7-02 competitor adapter package (design memo
vignettes/articles/devlog-2026-10-08-m7-competitor-harness-design.qmd §6).

External tools are bench references and never enter the ``ms_*`` API
(ARCHITECTURE D9/D15). Everything in this package is harness-side: registry
data, command composition, parsing and the skip-not-skip refusal protocol.
"""
