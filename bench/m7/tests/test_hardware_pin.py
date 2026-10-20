"""(S) hardware-pin completeness gate for the authoritative table (U-M7-04 GO-05).

The B1a writer path made the hardware pins POSSIBLE: every written row carries
the trailing ``host``/``hw_profile`` columns, and "unset → present-but-empty"
was the right contract for probes and mock plumbing. But a table whose pin
columns are EMPTY does not attest its machine — the ROADMAP "hardware-pinned bench full table"
clause (docs/ROADMAP.md:100) demands the FULL table: every row pinned from the
measured environment, checkable from the table alone (EVIDENCE-ADDENDUM §4's
forward path: "future authoritative runs attest their machine from the table
alone").

This group seals the completion in three load-bearing places:

1. ``matrix_governance.hardware_pin_verdict`` — the pure, injected, CI-safe
   adjudicator: every row's pin must EQUAL the measured environment
   (runner hostname + operator's machine-class pin). A row with an empty or
   divergent pin is named, not averaged away. A zero-row table is not a
   complete table.
2. ``run_bench.main`` — the authoritative pass (docker adapter, final shard-
   free pass) REFUSES TO FILE without the operator's ``M7_HW_PROFILE``:
   fail-fast exit 2, zero filesystem side effects. The refusal mirrors the
   refuse-to-claim law: an unattested authoritative table may not be born.
   Mock passes and shard passes are untouched (B1a's present-but-empty
   optionality law stays intact for probes/plumbing).
3. ``tools/verify_hardware_pin.py`` — the verifier a reader re-runs against a
   committed table; its verdict is the same-window evidence a docs citation
   points at.
"""

from __future__ import annotations

import csv
import json
import os
import shutil
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
import sys
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from competitors import timings                      # noqa: E402
from tools import matrix_governance as gov          # noqa: E402 (RED seam 1)
import run_bench                                     # noqa: E402

HOST = "measurement-host-01"
CLASS = "10 vCPU / 8 GB class"


def _row(cell: str = "sigminer__main__N100", **over) -> dict:
    r = {"cell": cell, "tool": cell.split("__")[0],
         "arm": cell.split("__")[1], "n": cell.rpartition("N")[2],
         "seconds": "12.0", "status": "ok", "cpu_seconds": "11.0",
         "host": HOST, "hw_profile": CLASS}
    r.update(over)
    return r


# -- 1. the pure verdict ----------------------------------------------------------
def test_verdict_ok_only_when_every_row_pinned_to_the_measured_environment():
    v = gov.hardware_pin_verdict([_row(), _row("sigprofiler__main__N100")],
                                 host=HOST, hw_profile=CLASS)
    assert v["ok"] is True, f"fully pinned table judged not-ok: {v}"
    assert v["rows"] == 2


def test_verdict_names_rows_with_empty_or_divergent_pins():
    rows = [_row(),
            _row("sigminer__main__N1000", host=""),                 # empty
            _row("sigminer__main__N10000", hw_profile="8 vCPU class"),  # divergent
            _row("sigprofiler__main__N100", host="other-host",
                 hw_profile="")]
    v = gov.hardware_pin_verdict(rows, host=HOST, hw_profile=CLASS)
    assert v["ok"] is False
    assert v["missing_host"] == ["sigminer__main__N1000"], v
    assert v["missing_hw_profile"] == ["sigprofiler__main__N100"], v
    assert v["mismatched_host"] == ["sigprofiler__main__N100"], v
    assert v["mismatched_hw_profile"] == ["sigminer__main__N10000"], v


def test_verdict_rejects_an_empty_table():
    # Zero rows attests zero measurements: a "complete" table is not vacuous.
    v = gov.hardware_pin_verdict([], host=HOST, hw_profile=CLASS)
    assert v["ok"] is False, v


# -- 2. the authoring gate ----------------------------------------------------------
def _tmp() -> Path:
    return Path(tempfile.mkdtemp(prefix="m7hwpin_"))


def _authoritative_argv(tmp: Path) -> list:
    # degraded+docker is the authoritative shape. The gate must fire before
    # any image state is consulted, so the competitor here is the
    # PENDING-VERIFY `signal` row: ungated it only skips (skip-not-skip,
    # rc 1), never a container launch. The gate is adapter-shaped, not
    # competitor-shaped — post-GREEN it fires long before this choice reads.
    return ["--profile", "degraded", "--adapter", "docker",
            "--competitors", "signal", "--arms", "main", "--n-list", "100",
            "--cachedir", str(tmp / "cache"), "--outdir", str(tmp / "results")]


def _run_capturing(argv: list) -> tuple[int, str]:
    """main() with stderr captured, so the refusal can be audited for the
    law it speaks (it must name its own remedy, the M7_HW_PROFILE channel)."""
    import io
    err = io.StringIO()
    real = sys.stderr
    try:
        sys.stderr = err
        rc = run_bench.main(argv)
    finally:
        sys.stderr = real
    return rc, err.getvalue()


def test_authoritative_docker_pass_refuses_to_file_without_the_operator_pin():
    tmp = _tmp()
    saved = os.environ.pop(timings.HW_PROFILE_ENV, None)
    try:
        rc, err = _run_capturing(_authoritative_argv(tmp))
        assert rc == 2, f"unattested authoritative pass returned {rc}"
        assert timings.HW_PROFILE_ENV in err, \
            f"refusal does not name its remedy channel: {err!r}"
        # Fail-fast before any filesystem effect: neither tree may be born.
        assert not (tmp / "results").exists(), "outdir created despite refusal"
        assert not (tmp / "cache").exists(), "cachedir created despite refusal"
    finally:
        if saved is not None:
            os.environ[timings.HW_PROFILE_ENV] = saved
        shutil.rmtree(tmp, ignore_errors=True)


def test_blank_pin_refuses_like_an_absent_one():
    tmp = _tmp()
    saved = os.environ.get(timings.HW_PROFILE_ENV)
    os.environ[timings.HW_PROFILE_ENV] = "   "       # whitespace is absence
    try:
        rc, err = _run_capturing(_authoritative_argv(tmp))
        assert rc == 2, f"blank-pin authoritative pass returned {rc}"
        assert not (tmp / "results").exists()
    finally:
        if saved is None:
            os.environ.pop(timings.HW_PROFILE_ENV, None)
        else:
            os.environ[timings.HW_PROFILE_ENV] = saved
        shutil.rmtree(tmp, ignore_errors=True)


def test_dry_run_plan_is_untouched_by_the_authority_gate():
    # The plan printer has zero side effects by contract; an unattested
    # machine must still be plannable (the gate governs files, not intents).
    tmp = _tmp()
    saved = os.environ.pop(timings.HW_PROFILE_ENV, None)
    stdout = __import__("io").StringIO()
    real = sys.stdout
    try:
        sys.stdout = stdout
        rc = run_bench.main(_authoritative_argv(tmp) + ["--dry-run"])
    finally:
        sys.stdout = real
        if saved is not None:
            os.environ[timings.HW_PROFILE_ENV] = saved
        shutil.rmtree(tmp, ignore_errors=True)
    assert rc == 0, f"dry-run refused under the authority gate: rc={rc}"
    plan = json.loads(stdout.getvalue())
    assert plan["adapter"] == "docker" and plan["invocations"] >= 1


def test_mock_final_pass_stays_green_without_the_pin():
    # B1a optionality law: probe/plumbing passes keep the present-but-empty
    # contract; the refusal is scoped to the authoritative docker shape.
    tmp = _tmp()
    saved = os.environ.pop(timings.HW_PROFILE_ENV, None)
    try:
        rc = run_bench.main(["--profile", "smoke", "--adapter", "mock",
                             "--competitors", "sigminer",
                             "--cachedir", str(tmp / "cache"),
                             "--outdir", str(tmp / "results")])
        assert rc == 0, f"mock final pass gated though only docker is: rc={rc}"
        files = [p for p in (tmp / "results").iterdir()
                 if p.name.startswith("timings_m7_")]
        with files[0].open(newline="", encoding="utf-8") as fh:
            rows = list(csv.DictReader(fh))
        assert rows and all(r["hw_profile"] == "" for r in rows), \
            "mock pass must keep writing the present-but-empty pin column"
    finally:
        if saved is not None:
            os.environ[timings.HW_PROFILE_ENV] = saved
        shutil.rmtree(tmp, ignore_errors=True)


def test_judgment_speaks_the_nine_column_pinned_contract():
    # The judgment's timings-table line must name the hardware pins: a reader
    # of the fairness document learns from it that the table attests its
    # machine. (RED today: the line still recites "six-column prefix +
    # cpu_seconds" only.)
    tmp = _tmp()
    saved = os.environ.get(timings.HW_PROFILE_ENV)
    os.environ[timings.HW_PROFILE_ENV] = CLASS
    try:
        assert run_bench.main(["--profile", "smoke", "--adapter", "mock",
                               "--competitors", "sigminer",
                               "--cachedir", str(tmp / "cache"),
                               "--outdir", str(tmp / "results")]) == 0
    finally:
        if saved is None:
            os.environ.pop(timings.HW_PROFILE_ENV, None)
        else:
            os.environ[timings.HW_PROFILE_ENV] = saved
    jud = [p for p in (tmp / "results").iterdir()
           if p.name.startswith("judgment_m7_")]
    assert jud, "no judgment filed"
    text = jud[0].read_text(encoding="utf-8")
    line = [l for l in text.splitlines() if "timings table" in l]
    assert line, "judgment lost its timings-table line"
    assert "host" in line[0] and "hw_profile" in line[0], \
        f"judgment line does not name the pins: {line[0]!r}"
    shutil.rmtree(tmp, ignore_errors=True)


# -- 3. the reader-side verifier ------------------------------------------------------
def test_verifier_cli_verdicts_a_committed_table_from_its_own_bytes():
    from tools import verify_hardware_pin as vhp          # RED seam 3 (absent)
    tmp = _tmp()
    try:
        path = timings.write_timings(tmp / "t.csv", [_row(), _row("sigprofiler__main__N100")])
        rc, out = vhp.main(["--table", str(path), "--host", HOST,
                            "--hw-profile", CLASS])
        assert rc == 0, f"pinned table rejected: {out}"
        verdict = json.loads(out)
        assert verdict["ok"] is True and verdict["rows"] == 2

        bad = timings.write_timings(tmp / "b.csv",
                                    [_row(), _row("sigminer__main__N1000",
                                                 hw_profile="")])
        rc, out = vhp.main(["--table", str(bad), "--host", HOST,
                            "--hw-profile", CLASS])
        assert rc == 1, f"half-pinned table accepted: {out}"
        assert json.loads(out)["missing_hw_profile"] == ["sigminer__main__N1000"]
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
