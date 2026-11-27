"""Adjudication-summarizer laws for tools/g0_adjudicate.py (T-7 post-run lane).

Every law is an observation on a live subprocess over a synthesized
authoritative outdir (judgment md + coverage csv), never a text grep of the
tool's bytes: the negatives must fire for their named cause, and the paired
controls (verdict A and verdict B fixtures corroborate; a crossed md/csv pair
speaks ROUNDTRIP-DRIFT and keeps the md authoritative) prove the instrument
is not vacuous.
"""

import csv
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent          # bench/g0/tests
G0_DIR = HERE.parent                            # bench/g0
TOOL = G0_DIR / "tools" / "g0_adjudicate.py"

CSV_COLS = ["estimand", "tool", "arm", "n", "signature", "layer", "truth_h",
            "k", "n_reps", "coverage", "cp_lo", "cp_hi", "filtered_rate",
            "error_rate", "p1_mechanism_i"]


def _run(outdir: Path):
    return subprocess.run([sys.executable, str(TOOL), "--outdir", str(outdir)],
                          capture_output=True, text=True)


def _write_csv(path: Path, rows):
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(CSV_COLS)
        for r in rows:
            w.writerow(r)


def _write_md(path: Path, verdict: str, arms: str = "{'main'}"):
    summary = f"verdict: {verdict}\nA-clause② flat all ≤0.90 @N≥300: False"
    path.write_text(
        "# G0 judgment summary — profile=primary, adapter=docker, provider=cosmic-file\n"
        "\n"
        f"- Tools (F2 frozen): sigfit, stl\n"
        f"- Judgment input cells: 2 (estimand=absolute main estimand; arm ∈ {arms})\n"
        "\n"
        "```\n" + summary + "\n```\n",
        encoding="utf-8")


def _cell(tool, coverage, cp_hi, n=1000, arm="main", layer="easy",
          signature="SBS1", reps=200):
    # column order = CSV_COLS (estimand first)
    return ["absolute", tool, arm, n, signature, layer, 0.15, 5, reps,
            coverage, round(coverage - 0.05, 4), cp_hi, 0.0, 0.0, 0]


def _outdir_case(csv_rows, verdict, arms="{'main'}"):
    tmp = tempfile.mkdtemp(prefix="g0adj-")
    outdir = Path(tmp)
    _write_md(outdir / "judgment_primary_20260101-000000.md", verdict, arms)
    _write_csv(outdir / "coverage_primary_20260101-000000.csv", csv_rows)
    return outdir


def test_verdict_a_corroborates_and_speaks_the_framing():
    # A-clause① : one tier-1 cell with ĉ ≤ 0.85 and CP_hi < 0.90 fires A.
    rows = [_cell("sigfit", 0.80, 0.85), _cell("stl", 0.93, 0.98)]
    out = _run(_outdir_case(rows, "A"))
    assert out.returncode == 0, out.stderr
    assert "verdict          : A  [CORROBORATED: table recompute -> A]" in out.stdout
    assert "A — the calibrated-inference headline HOLDS" in out.stdout
    # the backfill facts speak the table-carried extremes
    assert "min 0.8000 / max 0.9300" in out.stdout


def test_verdict_b_corroborates_and_names_the_ecosystem_framing():
    # kill→B : both tier-1 tools' N≥300 cells ĉ ≥ 0.90, no monotone worsening.
    rows = [_cell("sigfit", 0.96, 0.99), _cell("stl", 0.95, 0.98)]
    out = _run(_outdir_case(rows, "B"))
    assert out.returncode == 0, out.stderr
    assert "verdict          : B  [CORROBORATED: table recompute -> B]" in out.stdout
    assert "B — the coverage headline is falsified" in out.stdout


def test_gray_speaks_the_doubling_flow():
    # easy-layer cells between the clauses: not A① (CP_hi ≥ 0.90), not kill (ĉ < 0.90).
    rows = [_cell("sigfit", 0.88, 0.93), _cell("stl", 0.88, 0.93)]
    out = _run(_outdir_case(rows, "GRAY"))
    assert out.returncode == 0, out.stderr
    assert "verdict          : GRAY" in out.stdout
    assert "the borderline doubling flow applies first" in out.stdout
    assert "--reps 400" in out.stdout


def test_crossed_products_speak_drift_and_keep_the_md_authoritative():
    # md says B, the table recomputes A — the tool must say so loudly, not agree.
    rows = [_cell("sigfit", 0.80, 0.85), _cell("stl", 0.93, 0.98)]
    out = _run(_outdir_case(rows, "B"))
    assert out.returncode == 0, out.stderr
    assert "ROUNDTRIP-DRIFT" in out.stdout
    assert "(authoritative)" in out.stdout


def test_empty_outdir_refuses_for_its_named_cause():
    tmp = tempfile.mkdtemp(prefix="g0adj-empty-")
    out = _run(Path(tmp))
    assert out.returncode == 2
    assert "no judgment_primary_* product" in out.stderr


def test_header_drift_refuses():
    tmp = tempfile.mkdtemp(prefix="g0adj-hdr-")
    outdir = Path(tmp)
    (outdir / "judgment_primary_x.md").write_text("verdict: A\n", encoding="utf-8")
    (outdir / "coverage_primary_x.csv").write_text("wrong,header\n1,2\n", encoding="utf-8")
    out = _run(outdir)
    assert out.returncode == 2
    assert "header drift" in out.stderr
