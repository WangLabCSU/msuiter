"""Group (AH) test_p6_anchor_registration -- the deterministic fragment->table
bridge for matrix_governance._FLOOR_ANCHORS.

The (AC) group SEALS the anchor law (every anchor must be backed by a
committed, reps-matched, verdict-OK witness). This unit seals the only legal
WAY such an edit can be produced: tools/register_p6_anchors.py reads the
calibrator's anchors_fragment.json -- values already composed FROM witness
bytes by the calibrator -- re-verifies each witness sidecar on disk, and
rewrites the literal table. No number is ever hand-transcribed: a value that
is not in the fragment cannot appear in the table (MEASURED-then-stated), and
a fragment naming a witness that is not on disk is a REFUSE that leaves the
governance bytes byte-sterile.
"""

from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import types
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from tools import register_p6_anchors as reg         # noqa: E402  (RED seam)

GOV_HEADER = '"""fixture governance module."""\n\n_FLOOR_ANCHORS = {\n'
GOV_FOOTER = '\n}\n'

LEGACY = "    ('sigminer', 'clock', 1000): {\n" \
         "        'witness': ('m7_floor_calibration_20261009', 'witnesses',\n" \
         "                    'sigminer__clock__N1000__rep100.json'),\n" \
         "        'reps': 100, 'cpu_seconds': 1079.517548, 'wall_seconds': 820.965,\n" \
         "    },"


def _mk_fixture(root: Path, *, n_anchors=2, drop_witness=None):
    """results/<caldir>/witnesses/ + anchors_fragment.json + governance source."""
    caldir = "m7_floor_calibration_p6_test"
    wdir = root / "results" / caldir / "witnesses"
    wdir.mkdir(parents=True)
    gov = root / "matrix_governance_fx.py"
    gov.write_text(GOV_HEADER + LEGACY + GOV_FOOTER, encoding="utf-8")
    fragment = {}
    for i in range(n_anchors):
        tool, arm, n = "sigminer_post_v3", "main", 100 * (i + 1)
        wname = f"{tool}__{arm}__N{n}__rep100.json"
        if wname != drop_witness:
            (wdir / wname).write_text(json.dumps({
                "tool": tool, "arm": arm, "n": n, "reps": 100,
                "verdict": "OK", "exit_code": 0,
                "sidecar": {"cpu_seconds": 100.0 + i},
                "wall_seconds": 90.0 + i,
            }, sort_keys=True) + "\n", encoding="utf-8")
        fragment[f"{tool}|{arm}|N{n}"] = {
            "witness": (caldir, "witnesses", wname), "reps": 100,
            "cpu_seconds": 100.0 + i, "wall_seconds": 90.0 + i,
        }
    (root / "results" / caldir / "anchors_fragment.json").write_text(
        json.dumps(fragment, sort_keys=True, indent=1) + "\n", encoding="utf-8")
    return caldir, gov


def _table_of(source: Path) -> dict:
    ns: dict = {}
    exec(compile(source.read_text(encoding="utf-8"), str(source), "exec"), ns)
    return ns["_FLOOR_ANCHORS"]


def test_registration_imports_with_fragment_values_and_keeps_legacy():
    with tempfile.TemporaryDirectory() as t:
        root = Path(t)
        caldir, gov = _mk_fixture(root)
        res = reg.register(gov_source=gov, results_dir=root / "results",
                          caldir=caldir)
        assert res["verdict"] == "REGISTERED", res
        table = _table_of(gov)
        assert ("sigminer_post_v3", "main", 100) in table
        assert table[("sigminer_post_v3", "main", 200)]["cpu_seconds"] == 101.0
        assert ("sigminer", "clock", 1000) in table, "legacy entries survive"


def test_missing_witness_is_a_refuse_and_leaves_bytes_sterile():
    with tempfile.TemporaryDirectory() as t:
        root = Path(t)
        drop = "sigminer_post_v3__main__N200__rep100.json"
        caldir, gov = _mk_fixture(root, drop_witness=drop)
        before = hashlib.sha256(gov.read_bytes()).hexdigest()
        res = reg.register(gov_source=gov, results_dir=root / "results",
                           caldir=caldir)
        assert res["verdict"] == "REFUSE", res
        assert any(drop in w for w in res["refusals"]), \
            "the refusal must name the missing witness"
        assert hashlib.sha256(gov.read_bytes()).hexdigest() == before, \
            "a refused registration is byte-sterile"


def test_rerun_is_idempotent():
    with tempfile.TemporaryDirectory() as t:
        root = Path(t)
        caldir, gov = _mk_fixture(root)
        reg.register(gov_source=gov, results_dir=root / "results",
                     caldir=caldir)
        first = gov.read_bytes()
        res = reg.register(gov_source=gov, results_dir=root / "results",
                           caldir=caldir)
        assert res["verdict"] == "REGISTERED"
        assert gov.read_bytes() == first, "second pass is a byte-identical no-op"


def test_unbacked_number_cannot_enter_the_table():
    # a fragment whose sidecar disagrees with the witness on disk is a lie:
    # the registry must verify AGAINST THE WITNESS, not trust the fragment
    with tempfile.TemporaryDirectory() as t:
        root = Path(t)
        caldir, gov = _mk_fixture(root)
        w = (root / "results" / caldir / "witnesses"
             / "sigminer_post_v3__main__N100__rep100.json")
        doc = json.loads(w.read_text(encoding="utf-8"))
        doc["sidecar"]["cpu_seconds"] = 12345.678  # witness says 12345.678
        w.write_text(json.dumps(doc, sort_keys=True) + "\n", encoding="utf-8")
        res = reg.register(gov_source=gov, results_dir=root / "results",
                           caldir=caldir)
        assert res["verdict"] == "REGISTERED"
        got = _table_of(gov)[("sigminer_post_v3", "main", 100)]["cpu_seconds"]
        assert got == 12345.678, \
            "the witness is the authority; the fragment is only an index"


if __name__ == "__main__":
    fails = 0
    for name, fn in sorted(vars().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print(f"  PASS {name}")
            except Exception as exc:
                fails += 1
                print(f"  FAIL {name}: {exc}")
    raise SystemExit(1 if fails else 0)
