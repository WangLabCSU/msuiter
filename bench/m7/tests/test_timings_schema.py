"""③ timings schema contract (U-M7-02 §4.3).

The M7 timings table must concatenate with the G0 tables: the six G0 columns
``cell,tool,arm,n,seconds,status`` keep their names and order **verbatim**
(asserted against the byte-copied header of the authoritative G0 artifact
``bench/results/docker_degraded_pi_20261007-212438/timings_sharded_master.csv``),
and M7 appends exactly one measurement column ``cpu_seconds``.
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


def test_columns_are_g0_prefix_plus_cpu_seconds():
    cols = list(timings.TIMINGS_COLUMNS)
    assert cols == G0_COLUMNS + ["cpu_seconds"], \
        f"timings schema drifted from the G0-compatible contract: {cols}"


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
