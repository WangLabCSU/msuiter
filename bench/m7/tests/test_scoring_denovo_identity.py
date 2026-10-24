"""⑫ De-novo prediction identity resolution (PERF P4 adjudication, verdict B).

The committed sigminer runners drive the de-novo bp_* chain and delegate
reference matching to the scoring side ("reference matching is the
scoring-side get_sig_similarity job (memo §4)" — run_sigminer.R:55-58,
run_sigminer_arm.R:74-77). The frozen protocol is untouched: catalog-name
predictions keep the catalog-column cosine path bit-for-bit (the
sigprofiler echo regime stays byte-identical); a catalog-unknown name is
scored in SPECTRUM space — cosine(pred spectrum, truth spectrum) over the
cell's ground-truth calls, Hungarian one-to-one as today — from the
optional witness sidecar ``out/spectra.csv`` (long form
``signature,channel,value``). Resolution is exact: a prediction spectrum
missing any channel or any non-finite value is NOT partially trusted — it
is unresolved, and a stratum whose predictions the cosine gate could not
observe is declared in the table (``de-novo-unresolved=<n>`` note + the
verdict's declared-not-measured section), never vacuously scored.

No name guessing, no heuristics, no fuzzy ID matching — the only new
knowledge channel is the committed spectrum itself.
"""

from __future__ import annotations

import csv
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
import sys
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from scoring import judgment, match, run_products, truth   # noqa: E402
from tests import scoring_fixtures as fx            # noqa: E402

PROFILE = "degraded"
ARM, N, REPS = "main", 100, 10
TOOL = "sigminer"                                    # de-novo runner family
TRUTH_SIG = "SBS5"                                   # present in degraded/main


def _score(root: Path):
    return run_products.score_cachedir(root, profile=PROFILE,
                                       provider_name="synthetic",
                                       provider_seed=0)


def _build_cell(root: Path, pred_name: str, spectrum_from: str | None = None,
                *, drop_channels: int = 0) -> None:
    """Commit one cell: every rep calls exactly ``pred_name`` with the truth
    exposure of SBS5 (30.0 at main@N100, frozen generator). When
    ``spectrum_from`` names a provider catalog slot, the witness sidecar
    commits that column's bit-exact values under the de-novo label — what a
    faithful extraction of that signature looks like. ``drop_channels``
    truncates the witness (strict-coverage probe)."""
    provider = truth.load_provider("synthetic", 0)
    samples = {r: {pred_name: 30.0} for r in range(REPS)}
    cd = fx.write_cell(root, TOOL, ARM, N, samples)
    if spectrum_from is None:
        return
    vec = truth.catalog_vector(provider, spectrum_from)
    labels = list(provider.channel_labels)
    keep = len(labels) - drop_channels
    with (cd / "out" / "spectra.csv").open("w", newline="",
                                           encoding="utf-8") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(["signature", "channel", "value"])
        for ch, v in zip(labels[:keep], vec[:keep]):
            w.writerow([pred_name, str(ch), repr(float(v))])


def test_denovo_spectra_resolve_to_matches():
    """A faithful de-novo extraction (committed spectrum bit-exact the
    truth signature's catalog column) must score tp on the spectrum path —
    the scoring-side job the committed runners promise. Today the name-key
    lookup alone makes it structurally impossible (P4 forensics dossier)."""
    root = fx.tmp_cachedir(prefix="m7sc_denovo_")
    try:
        _build_cell(root, "Sig1", TRUTH_SIG)
        rep = _score(root)
        cell = rep.row("cell", tool=TOOL, arm=ARM, N=N)
        sig = rep.row("signature", tool=TOOL, arm=ARM, N=N, signature=TRUTH_SIG)
        denovo = rep.row("signature", tool=TOOL, arm=ARM, N=N, signature="Sig1")
        assert cell["tp"] == REPS, (
            f"defect P4-SCORING-1 (de-novo identity seam): faithful de-novo "
            f"extraction scored tp={cell['tp']}, fp={cell['fp']}, "
            f"notes={denovo['notes']!r} — the scoring side performs no "
            f"spectrum-space match")
        assert cell["fp"] == 0 and cell["fn"] == 4 * REPS
        assert sig["tp"] == REPS and sig["status"] == "matched"
        assert sig["mean_match_cosine"] == 1.0
        assert denovo["status"] == "matched" and denovo["tp"] == REPS
        assert denovo["notes"] == "denovo-spectra"
        assert "de-novo-unresolved" not in (cell["notes"] or "")
        assert rep.dead_strata == []
    finally:
        fx.cleanup(root)


def test_unresolved_denovo_calls_are_flagged_not_vacuously_scored():
    """No witness sidecar => the cosine gate could not observe these calls.
    Their zeros must be DECLARED (cell note + report.dead_strata), never
    carried as a measured scored zero (vacuous-green doctrine)."""
    root = fx.tmp_cachedir(prefix="m7sc_unres_")
    try:
        _build_cell(root, "Sig1", None)
        rep = _score(root)
        cell = rep.row("cell", tool=TOOL, arm=ARM, N=N)
        denovo = rep.row("signature", tool=TOOL, arm=ARM, N=N, signature="Sig1")
        assert cell["tp"] == 0 and cell["fp"] == REPS      # counted, not dropped
        assert denovo["status"] == "false_called" and denovo["notes"] == "uncatalogued"
        assert f"de-novo-unresolved={REPS}" in (cell["notes"] or ""), cell["notes"]
        assert rep.dead_strata == [(f"{TOOL}__{ARM}__N{N}", REPS)], rep.dead_strata
    finally:
        fx.cleanup(root)


def test_below_tolerance_spectra_is_measured_zero_not_flagged():
    """A committed spectrum whose best truth cosine is genuinely below the
    frozen 0.85 tolerance is a REAL measurement zero: fp, no dead-strata
    flag. Discriminates 'unobserved' from 'observed-and-wrong'."""
    provider = truth.load_provider("synthetic", 0)
    t_sigs = sorted(truth.cell_truth(PROFILE, ARM, N))
    col = truth.catalog_vector(provider, "SBS4")           # extended slot, off-target
    worst = max(match.cosine(col, truth.truth_vector(provider, t)) for t in t_sigs)
    assert worst < match.MATCH_MIN_COSINE, (
        f"fixture premise broken: SBS4 reaches cos {worst:.4f} on this grid")
    root = fx.tmp_cachedir(prefix="m7sc_lowcos_")
    try:
        _build_cell(root, "Sig1", "SBS4")
        rep = _score(root)
        cell = rep.row("cell", tool=TOOL, arm=ARM, N=N)
        denovo = rep.row("signature", tool=TOOL, arm=ARM, N=N, signature="Sig1")
        assert cell["tp"] == 0 and cell["fp"] == REPS
        assert denovo["status"] == "false_called"
        assert denovo["notes"] == "denovo-spectra"          # observed, rejected
        assert "de-novo-unresolved" not in (cell["notes"] or "")
        assert rep.dead_strata == []
    finally:
        fx.cleanup(root)


def test_partial_channel_spectra_is_unresolvable():
    """Strict coverage: a witness missing channels is never partially
    trusted — it degrades to the unresolved (flagged) path, not a cosine
    over the remainder."""
    root = fx.tmp_cachedir(prefix="m7sc_partial_")
    try:
        _build_cell(root, "Sig1", TRUTH_SIG, drop_channels=1)
        rep = _score(root)
        cell = rep.row("cell", tool=TOOL, arm=ARM, N=N)
        denovo = rep.row("signature", tool=TOOL, arm=ARM, N=N, signature="Sig1")
        assert cell["tp"] == 0
        assert denovo["notes"] == "uncatalogued"
        assert f"de-novo-unresolved={REPS}" in (cell["notes"] or "")
        assert rep.dead_strata and rep.dead_strata[0][1] == REPS
    finally:
        fx.cleanup(root)


def test_unresolved_strata_are_declared_in_the_verdict_half():
    """The vacuous-green counterpart at the document layer: a pass whose
    arms could not be observed by the cosine gate must say so in the
    appended verdict half (declared, not measured) — the zeros may not
    ride out as adjudication."""
    root = fx.tmp_cachedir(prefix="m7sc_declare_")
    try:
        _build_cell(root, "Sig1", None)
        rep = _score(root)
        text = judgment.build_verdict_text(
            rep, {"profile": PROFILE, "adapter": "docker"})
        assert "declared, not measured" in text, (
            "unobserved de-novo zeros must be declared in the verdict half")
        assert TOOL in text and str(REPS) in text
    finally:
        fx.cleanup(root)


def test_echoed_prediction_control_is_byte_preserved():
    """Positive control (the sigprofiler regime, byte-preservation law):
    catalog-echoed names score exactly as before — tp, cos 1.0, and NO new
    note tokens or flags anywhere on the rows."""
    root = fx.tmp_cachedir(prefix="m7sc_echo_")
    try:
        _build_cell(root, TRUTH_SIG, None)
        rep = _score(root)
        cell = rep.row("cell", tool=TOOL, arm=ARM, N=N)
        sig = rep.row("signature", tool=TOOL, arm=ARM, N=N, signature=TRUTH_SIG)
        assert cell["tp"] == REPS and cell["fp"] == 0
        assert sig["status"] == "matched" and sig["mean_match_cosine"] == 1.0
        assert (sig["notes"] or "") == "" and (cell["notes"] or "") == ""
        assert rep.dead_strata == []
        assert cell["match_tolerance"] == match.MATCH_MIN_COSINE
    finally:
        fx.cleanup(root)
