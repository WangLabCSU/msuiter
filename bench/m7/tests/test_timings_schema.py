"""③ timings schema contract (U-M7-02 §4.3).

The M7 timings table must concatenate with the G0 tables: the six G0 columns
``cell,tool,arm,n,seconds,status`` keep their names and order **verbatim**
(asserted against the byte-copied header of the authoritative G0 artifact
``bench/results/docker_degraded_pi_20261007-212438/timings_sharded_master.csv``),
and M7 appends exactly one measurement column ``cpu_seconds``.

U-M7-04 B1a (hardware-pin machine-checkability): behind the seven, two
**optional trailing** pin columns ``host`` and ``hw_profile`` ride every
written table, so the machine a table was measured on is checkable from the
table itself, without external prose. Committed pre-B1a artifacts — the
authoritative 42-cell run included — stay 7-col and must keep reading: the
reader's back-compat branch is pinned to that exact legacy header, never
open-ended.
"""

from __future__ import annotations

import csv
import shutil
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
FIXTURES = HERE / "tests" / "fixtures"
import sys
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from competitors import timings                      # noqa: E402 (RED seam)

G0_COLUMNS = next(csv.reader(
    (FIXTURES / "g0_timings_header.csv").read_text(encoding="utf-8")
    .splitlines()))
assert G0_COLUMNS == ["cell", "tool", "arm", "n", "seconds", "status"], \
    "G0 header fixture itself drifted — fix the fixture from the authoritative artifact"


def test_columns_are_g0_prefix_plus_cpu_seconds_plus_hardware_pins():
    cols = list(timings.TIMINGS_COLUMNS)
    assert cols == G0_COLUMNS + ["cpu_seconds", "host", "hw_profile"], \
        f"timings schema drifted from the G0-compatible + pin contract: {cols}"


def test_writer_emits_contract_header_and_round_trips_rows():
    """Every adapter's timings writer: same header, values round-trip."""
    row = {"cell": "sigminer__main__N100", "tool": "sigminer",
           "arm": "main", "n": 100, "seconds": 42.5,
           "status": "ok", "cpu_seconds": 41.0}
    tmp = Path(tempfile.mkdtemp(prefix="m7timings_"))
    try:
        path = tmp / "timings_m7_test.csv"
        timings.write_timings(path, [row])
        with path.open(newline="", encoding="utf-8") as fh:
            reader = csv.DictReader(fh)
            assert reader.fieldnames == list(timings.TIMINGS_COLUMNS)
            rows = list(reader)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    assert len(rows) == 1
    back = rows[0]
    assert back["cell"] == row["cell"] and back["tool"] == "sigminer"
    assert float(back["seconds"]) == 42.5 and float(back["cpu_seconds"]) == 41.0
    assert back["status"] == "ok"
    # Optionality law (U-M7-04 B1a): the pin columns are written even when
    # the row omits them — present-but-empty, never schema-absent.
    assert back["host"] == "" and back["hw_profile"] == ""


def test_intervals_header_stays_g0_compatible():
    """The adapter protocol's long-table schema (adapter_protocol.md §2) is
    the shared parse surface; the M7 harness consumes it unchanged."""
    cols = next(csv.reader(
        (FIXTURES / "g0_intervals_header.csv").read_text(encoding="utf-8")
        .splitlines()))
    assert cols == ["sample_id", "signature", "estimate", "lo95",
                    "hi95", "estimand", "zeroed"]
    # The parse helper lives on the harness side and must exist for GREEN:
    from competitors import intervals                 # noqa: F401 (RED seam)
    recs = intervals.parse(FIXTURES / "g0_intervals_header.csv")
    assert isinstance(recs, list) and not recs       # header-only fixture


def test_governance_metadata_rides_the_row_but_never_the_frozen_table():
    # The re-adjudication lineage (RB-09(3)(iv)) rides the row dict for the
    # judgment writer; the timings table is the frozen G0 six-column prefix
    # plus cpu_seconds and must NEVER gain a column from governance data.
    # The writer therefore projects known governance keys out explicitly,
    # and unknown keys must still raise loudly (no silent smuggling either
    # way). This unit reproduces the main-shard crash of the RB-09
    # re-ignition: six cached rows carried re_adjudication and the strict
    # DictWriter refused the extra key mid-write.
    row = {"cell": "sigminer__main__N100", "tool": "sigminer",
           "arm": "main", "n": "100", "seconds": "767.64",
           "status": "cached", "cpu_seconds": "1004.879",
           "re_adjudication": {"mechanism": "RB-09",
                              "prior_epoch": "7addcda244d18753"}}
    tmp = Path(tempfile.mkdtemp(prefix="m7timings_gov_"))
    try:
        path = timings.write_timings(tmp / "t.csv", [row])
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        assert lines[0] == ",".join(timings.TIMINGS_COLUMNS)
        assert "re_adjudication" not in text
        assert "7addcda244d18753" not in text
        try:
            timings.write_timings(tmp / "u.csv", [dict(row, smuggled=1)])
        except ValueError as exc:
            assert "smuggled" in str(exc)
        else:
            raise AssertionError("unknown row key passed silently")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_writer_stamps_hardware_pins_verbatim():
    """B1a: a row carrying host/hw_profile round-trips through the 9-col
    table byte-for-byte — the machine pin is checkable data, not prose."""
    row = {"cell": "sigprofiler__main__N100", "tool": "sigprofiler",
           "arm": "main", "n": 100, "seconds": 12.0,
           "status": "ok", "cpu_seconds": 11.0,
           "host": "m7-degraded-vm", "hw_profile": "10 vCPU / 8 GB class"}
    tmp = Path(tempfile.mkdtemp(prefix="m7timings_pin_"))
    try:
        path = timings.write_timings(tmp / "p.csv", [row])
        lines = path.read_text(encoding="utf-8").splitlines()
        assert lines[0] == ("cell,tool,arm,n,seconds,status,cpu_seconds,"
                            "host,hw_profile")
        with path.open(newline="", encoding="utf-8") as fh:
            back = list(csv.DictReader(fh))[0]
        assert back["host"] == "m7-degraded-vm"
        assert back["hw_profile"] == "10 vCPU / 8 GB class"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_reader_back_compat_accepts_the_seven_column_legacy_table():
    """B1a back-compat branch: committed pre-B1a tables — including the
    authoritative 42-cell artifact's exact 7-col header — keep reading; the
    two pin columns arrive empty, every legacy value verbatim."""
    tmp = Path(tempfile.mkdtemp(prefix="m7timings_legacy_"))
    try:
        path = tmp / "legacy.csv"
        path.write_text(
            ",".join(G0_COLUMNS + ["cpu_seconds"]) + "\n"
            "sigminer__main__N100,sigminer,main,100,767.64,cached,1004.879\n",
            encoding="utf-8")
        rows = timings.read_timings(path)
        assert len(rows) == 1
        assert rows[0]["cell"] == "sigminer__main__N100"
        assert rows[0]["status"] == "cached"
        assert float(rows[0]["cpu_seconds"]) == 1004.879
        assert rows[0]["host"] == "" and rows[0]["hw_profile"] == ""
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_reader_accepts_current_table_and_rejects_foreign_headers():
    """The back-compat branch is pinned to the exact legacy schema — any
    other header must raise, so drift can never masquerade as history."""
    tmp = Path(tempfile.mkdtemp(prefix="m7timings_read_"))
    try:
        good = timings.write_timings(tmp / "g.csv", [{
            "cell": "sigminer__main__N100", "tool": "sigminer",
            "arm": "main", "n": "100", "seconds": "1.5",
            "status": "ok", "cpu_seconds": "1.4",
            "host": "vm-a", "hw_profile": "10 vCPU / 8 GB class"}])
        rows = timings.read_timings(good)
        assert rows and rows[0]["host"] == "vm-a"
        bogus = tmp / "bogus.csv"
        bogus.write_text(
            ",".join(G0_COLUMNS + ["cpu_seconds", "bogus"]) + "\n",
            encoding="utf-8")
        try:
            timings.read_timings(bogus)
        except ValueError as exc:
            assert "bogus" in str(exc)
        else:
            raise AssertionError(
                "foreign header accepted — back-compat branch not pinned")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
