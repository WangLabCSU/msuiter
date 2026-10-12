"""⑨ Judgment document: preserved fairness half + scoring-verdict half.

The final (cache-hit) pass of run_bench.main must produce ONE authoritative
judgment_m7_<profile>_<ts>.md that keeps the fairness attestation verbatim
and APPENDS the scoring-verdict sections (this slice), including the frozen
framing — harness output; formal adjudication only via the frozen protocol —
and the honest footer naming which run classes are authoritative (the
degraded profile at 100 reps; mock/smoke prove plumbing only).

The call-site contract is exercised through the real orchestrator entry, so
the benchmark CSV appearing in the authoritative outdir is what is pinned,
not a re-implementation of it.
"""

from __future__ import annotations

import shutil
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
import sys
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import run_bench                                      # noqa: E402
from scoring import run_products                      # noqa: E402 (RED seam)


def _smoke(tmp: Path) -> int:
    return run_bench.main(["--profile", "smoke", "--adapter", "mock",
                           "--competitors", "sigminer",
                           "--cachedir", str(tmp / "cache"),
                           "--outdir", str(tmp / "results")])


def _judgment_text(results: Path) -> str:
    docs = sorted(p for p in results.iterdir()
                  if p.name.startswith("judgment_m7_") and p.name.endswith(".md"))
    assert docs, f"no judgment document in {sorted(p.name for p in results.iterdir())}"
    return docs[-1].read_text(encoding="utf-8")


def test_final_pass_emits_benchmark_csv_into_authoritative_outdir():
    tmp = Path(tempfile.mkdtemp(prefix="m7jd_"))
    try:
        assert _smoke(tmp) == 0
        results = tmp / "results"
        benches = [p.name for p in results.iterdir()
                   if p.name.startswith("benchmark_m7_") and p.name.endswith(".csv")]
        assert len(benches) == 1, \
            f"exactly one benchmark table per final pass, got {benches}"
        text = (results / benches[0]).read_text(encoding="utf-8").splitlines()
        assert text[0] == ",".join(run_products.BENCHMARK_COLUMNS)
        assert any("sigminer" in line for line in text[1:]), \
            "the measured-as competitor must appear in the table"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_judgment_keeps_fairness_half_and_appends_verdict_half():
    tmp = Path(tempfile.mkdtemp(prefix="m7jd_"))
    try:
        assert _smoke(tmp) == 0
        text = _judgment_text(tmp / "results")
        fair = text.find("fairness attestation")
        verdict = text.find("Scoring verdict")
        assert fair >= 0, "fairness attestation half must be preserved"
        assert verdict >= 0, "scoring-verdict half must be appended"
        assert fair < verdict, "the verdict half must come after the preserved half"
        assert "| competitor | version | image ref | image digest | status |" in text, \
            "the preserved attestation table must survive the append"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_frozen_framing_and_honest_footer_are_verbatim_present():
    tmp = Path(tempfile.mkdtemp(prefix="m7jd_"))
    try:
        assert _smoke(tmp) == 0
        text = _judgment_text(tmp / "results")
        low = text.lower()
        assert "harness output" in low and "frozen protocol" in low, \
            "the frozen framing sentence is non-negotiable (G0 judgment precedent)"
        assert "100 reps" in text, \
            "the honest footer must name the authoritative degraded class"
        assert "plumbing" in low, \
            "mock/smoke passes must be declared non-authoritative"
        assert "0.85" in text and "0.80" in text and "0.90" in text, \
            "the tolerance and its frozen sweep band must be stated"
        assert "TODO(paper)" in text, \
            "the citation for the tolerance decision is an open paper-side item"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_verdict_separates_judge_arms_from_sensitivity_report_columns():
    """Adjudication clause b (frozen): sensitivity arms never mix into the
    verdict table; they are reported, labelled, separately."""
    tmp = Path(tempfile.mkdtemp(prefix="m7jd_"))
    try:
        assert _smoke(tmp) == 0
        text = _judgment_text(tmp / "results")
        assert "Sensitivity" in text and "judge=False" in text, \
            "sensitivity report section (with its frozen flag) must be explicit"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_prf_table_labels_n_bearing_rollup_rows_without_str_none():
    """Backlog 'renderer N-row fix' (release-blocking, U-M7-02 triage).

    N-bearing rows (``n_rollup``) carry no arm label, and the paired
    arm_rollup rows carry no N. Both must print the absent-label placeholder
    '—' (the one ``_n()`` already gives the N column), never a leaked
    Python ``str(None)``. Numerics are unaffected by this — it pins the
    display projection only (the CSV layer renders absent fields as '',
    pinned by test_scoring_determinism)."""
    tmp = Path(tempfile.mkdtemp(prefix="m7jdn_"))
    try:
        assert _smoke(tmp) == 0
        text = _judgment_text(tmp / "results")
        verdict = text[text.find("Scoring verdict"):]
        data = [[c.strip() for c in ln.strip().strip("|").split("|")]
                for ln in verdict.splitlines()
                if ln.strip().startswith("|")
                and not set(ln) <= {"|", "-", " "}]
        assert data, "the verdict half must contain rendered table rows"
        for cells in data:
            assert "None" not in cells, \
                f"a rendered table cell leaked str(None): {cells}"
        n_rows = [c for c in data if len(c) == 8 and c[3] in ("100", "1000")]
        assert n_rows, "the smoke grid must produce N-bearing rollup rows"
        for c in n_rows:
            assert c[2] == "—", \
                f"N-bearing rows must print the absent-label placeholder " \
                f"in the stratum column, got: {c}"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_append_is_a_pure_text_operation_on_the_judgment_file():
    """append_verdict_sections is callable standalone (the emitter is a pure
    function of report+meta), idempotent-checked by content, and never
    rewrites the fairness bytes above the separator."""
    tmp = Path(tempfile.mkdtemp(prefix="m7jdp_"))
    try:
        jud = tmp / "judgment_m7_smoke_ts.md"
        fairness_body = "# fairness attestation stub\n\noriginal bytes.\n"
        jud.write_text(fairness_body, encoding="utf-8")
        empty = run_products.score_cachedir(tmp / "no-cells", profile="smoke",
                                            provider_name="synthetic", provider_seed=0)
        meta = {"profile": "smoke", "adapter": "mock", "provider": "synthetic"}
        run_products.append_verdict_sections(jud, empty, meta)
        text = jud.read_text(encoding="utf-8")
        assert text.startswith(fairness_body), "preserved half bytes mutated"
        assert "no scored cells" in text.lower(), \
            "a zero-cell report must say so, not print an empty verdict"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
