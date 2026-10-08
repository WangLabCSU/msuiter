"""Scoring-verdict sections appended to the fairness attestation document.

Pure text operation: the fairness half's bytes are never rewritten — the
verdict half is *appended* below a separator (the test pins
``text.startswith(fairness_bytes)``). Framing and footer follow the G0
judgment-document precedent: this is harness output, formal adjudication runs
only through the frozen protocol, and the document says out loud which run
class is authoritative (docker adapter, degraded profile at 100 reps) versus
which only proves the plumbing (smoke/mock).

The tables here are a human-readable projection of the same rows the CSV
carries — same numbers, no second measurement path. Sensitivity arms
(``judge=False`` on the frozen grid) are reported in their own labelled
section and never mixed into the adjudication table (clause b).
"""

from __future__ import annotations

from pathlib import Path

from . import match

VERDICT_HEADING = "Scoring verdict"
_SEPARATOR = "\n\n---\n\n"


def _fmt6(v) -> str:
    if v is None:
        return "na"
    v = float(v)
    return "na" if v != v else f"{v:.6f}"


def _n(v) -> str:
    return "—" if v is None else str(v)


def _prf_table(rows: list) -> list:
    lines = ["| tool | version | arm | N | n_samples | tp | fp | fn |",
             "|---|---|---|---|---|---|---|---|",
             "| precision | recall | f1 | | | | | |",
             "|---|---|---|---|---|---|---|---|"]
    for r in rows:
        lines.append(f"| {r['tool']} | {r['version']} | {r['arm']} | "
                     f"{_n(r['N'])} | {r['n_samples']} | "
                     f"{r['tp']} | {r['fp']} | {r['fn']} |")
        lines.append(f"| {_fmt6(r['precision'])} | {_fmt6(r['recall'])} | "
                     f"{_fmt6(r['f1'])} | | | | | |")
    return lines


def _exposure_table(report) -> list:
    sig = [r for r in report.rows
           if r["row_type"] == "signature" and r["tp"]]
    if not sig:
        return ["No matched bounds in this pass — the signature rows of the",
                "CSV carry ``na`` exposure columns (absent bounds stay absent)."]
    lines = ["| tool | arm | N | signature | layer | status |",
             "|---|---|---|---|---|---|",
             "| mean cosine | mean abs err | mean rel err | | | |",
             "|---|---|---|---|---|---|"]
    for r in sig:
        lines.append(f"| {r['tool']} | {r['arm']} | {r['N']} | {r['signature']} | "
                     f"{r['layer'] or '—'} | {r['status']} |")
        lines.append(f"| {_fmt6(r['mean_match_cosine'])} | "
                     f"{_fmt6(r['mean_abs_exposure_error'])} | "
                     f"{_fmt6(r['mean_rel_exposure_error'])} | | | |")
    return lines


def _rollups(report, judge_class: str) -> list:
    return [r for r in report.rows
            if r["row_type"] in ("arm_rollup", "n_rollup")
            and r["judge_class"] == judge_class]


def build_verdict_text(report, meta: dict) -> str:
    """The verdict half as one string (pure function of report + meta)."""
    band_lo, band_hi = (f"{b:.2f}" for b in match.MATCH_ROBUSTNESS_BAND)
    lines = [
        f"## {VERDICT_HEADING} — Hungarian-matched P/R/F1 (ARCHITECTURE §8)",
        "",
        f"Harness output; formal adjudication only via the frozen protocol. "
        f"Profile `{meta.get('profile')}`, adapter `{meta.get('adapter')}`.",
        "This half is a pure function of the committed cell artifacts plus the",
        "seed-derived ground truth: no RNG at score time, same cachedir =>",
        "byte-identical table.",
        "",
        f"- primary metric: Hungarian one-to-one assignment under catalog",
        f"  cosine, match tolerance **{match.MATCH_MIN_COSINE:.2f}** — the frozen",
        f"  midpoint of the {band_lo}–{band_hi} robustness band (benchmark memo",
        "  2026-10-05 §3; the band is protocol, the midpoint is the",
        "  least-chosen choice). TODO(paper): pin the citation for the band.",
        "- below-tolerance pairs are rejected by the matcher and fall out as",
        "  FP/FN — never as weak matches.",
        "- full long table (cell | signature | arm_rollup | n_rollup rows,",
        "  count-pooled rollups): the benchmark_m7_<ts>.csv beside this document.",
        "",
    ]
    if report.skipped:
        lines += ["- unscorable cells reported honestly (skip-not-skip): "
                  + ", ".join(f"`{name}` ({why})" for name, why in report.skipped),
                  ""]
    if report.cells_scored == 0:
        lines += ["**No scored cells in this pass** — nothing to adjudicate;",
                  "the fairness half stands alone.", ""]
        return "\n".join(lines)
    lines += [f"### Adjudication table — primary (judge) arms", "",
              f"{report.cells_scored} cells, {report.samples_scored} samples, "
              f"{report.matches} matched pairs pooled below.", ""]
    prim = _rollups(report, "primary")
    lines += (_prf_table(prim) if prim
              else ["No primary-arm cells scored in this pass."])
    lines += ["", "### Sensitivity report columns (judge=False)", "",
              "Report-only: the frozen grid flags these arms ``judge=False``;",
              "they are reported, never mixed into adjudication (clause b).", ""]
    sens = _rollups(report, "sensitivity")
    lines += (_prf_table(sens) if sens
              else ["No sensitivity-arm cells scored in this pass."])
    lines += ["", "### Exposure errors on matched bounds only", ""]
    lines += _exposure_table(report)
    lines += ["",
              "Honest footer: the authoritative measurement class is the docker-adapter",
              "run at the frozen protocol — degraded profile at 100 reps. smoke/mock",
              "passes prove pipeline plumbing only and are never quoted as results.",
              "Clock-arm exposure columns are report-only sensitivity rows (undiluted",
              "tumour-basis truth is an open adjudication item, G0 P2g).",
              ""]
    return "\n".join(lines)


def append_verdict_sections(judgment_path: Path | str, report,
                            meta: dict) -> Path:
    """Append (never rewrite) the verdict half; idempotent by content so a
    re-run over the same document cannot double it."""
    judgment_path = Path(judgment_path)
    text = judgment_path.read_text(encoding="utf-8")
    if f"## {VERDICT_HEADING}" in text:
        return judgment_path
    verdict = build_verdict_text(report, meta)
    judgment_path.write_text(text.rstrip("\n") + _SEPARATOR + verdict,
                             encoding="utf-8")
    return judgment_path
