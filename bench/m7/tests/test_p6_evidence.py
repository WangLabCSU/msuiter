"""Group (AB) test_p6_evidence — the committed-table laws as machine checks.

Three laws, three functions under test (tools.p6_evidence, RED-by-absence):

  zero-cached (task law 2 / manifest SS6): the committed campaign master is the
  shard UNION in which every row is a first-measurement 'ok' row. A 'cached'
  replay may inform a resume decision but may NEVER enter the committed table.

  hardware-pin (U-M7-04 B1a / ROADMAP full-table clause): a row without
  host/hw_profile attests nothing — the merge drops-and-reports, never files.

  digest-witness (task law 2, verify-by-command): a cell row is backed by the
  cell's own manifest.json in the campaign cachedir; the image_digest recorded
  there must equal the registry row for that tool, or the "witness" is for a
  different image and the row is disqualified.

All fixtures are synthetic tmp trees — CI-safe, no docker.
"""

from __future__ import annotations

import tempfile
import dataclasses
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from competitors import registry                     # noqa: E402
from tools import p6_evidence                        # noqa: E402  (RED seam)

REQUIRED_COLUMNS = ("cell", "tool", "arm", "n", "seconds", "status",
                    "cpu_seconds", "host", "hw_profile")


def _row(tool="sigminer_post_v3", arm="main", n=100, status="ok",
         host="mbp-wsx", hw_profile="10vcpu-8gb-pinned", **kw):
    r = {"cell": f"{tool}__{arm}__N{n}", "tool": tool, "arm": arm, "n": n,
         "seconds": 120.0, "status": status, "cpu_seconds": 110.0,
         "host": host, "hw_profile": hw_profile}
    r.update(kw)
    return r


# -- zero-cached merge ------------------------------------------------------------

def test_merge_is_union_and_never_admits_cached_rows():
    shards = [
        [_row(n=100), _row(n=1000, status="cached")],
        [_row(n=1000, status="ok")],               # same class, real measurement
        [_row(n=10000)],
    ]
    merged, rejected = p6_evidence.merge_shards(shards)
    assert [r["n"] for r in merged] == [100, 1000, 10000], merged
    assert all(r["status"] == "ok" for r in merged)
    assert any(r["status"] == "cached" for r, _why in
               [(rej["row"], rej["why"]) for rej in rejected]), (
        "the drop must be REPORTED with a reason code, never silent (Skip Law)")
    assert all("zero-cached" in rej["why"].lower() or "cached" in rej["why"]
               for rej in rejected), rejected


def test_merge_flags_double_measurement_conflicts():
    """A class measured ok in TWO shards is a resume-law event: first-wins,
    second reported — silently overwriting would erase the death/replay trail."""
    shards = [[_row(n=100, seconds=120.0)], [_row(n=100, seconds=400.0)]]
    merged, rejected = p6_evidence.merge_shards(shards)
    assert len(merged) == 1 and merged[0]["seconds"] == 120.0
    assert any("duplicate" in rej["why"].lower() or "conflict" in rej["why"].lower()
               for rej in rejected), rejected


def test_merge_drops_unstamped_rows_with_reason():
    merged, rejected = p6_evidence.merge_shards(
        [[_row(n=100), _row(n=1000, host=""), _row(n=10000, hw_profile=None)]])
    assert [r["n"] for r in merged] == [100]
    assert len(rejected) == 2 and all("hw" in rej["why"].lower()
                                      or "host" in rej["why"].lower()
                                      for rej in rejected), rejected


def test_master_columns_are_the_frozen_nine():
    assert tuple(p6_evidence.MASTER_COLUMNS) == REQUIRED_COLUMNS, (
        f"committed schema drift: {p6_evidence.MASTER_COLUMNS}")


def test_cell_identity_names_the_arm_tree_and_face():
    """Digest-witness law, strengthened: a P6 cell's own manifest.json is
    written from cell_identity, so the identity must carry the tree SHA and
    face the image was baked from — a wrong-tree bake is then caught by the
    cell's OWN bytes, not only by the build tag's naming convention. Legacy
    rows (no typed columns) contribute empty strings: the field exists, the
    witness law binds only where the roster attests a tree."""
    import run_bench
    from argparse import Namespace
    args = Namespace(adapter="docker", provider="synthetic", provider_seed=0)
    reg = registry.load()
    ident = run_bench.cell_identity("sigminer_post_v3_rust",
                                    reg["sigminer_post_v3_rust"], args)
    assert ident["tree_sha"] == "a8b8825be0c0768580c85b7e749b7b9088d8d9d7"
    assert ident["face"] == "rust"
    legacy = run_bench.cell_identity("sigminer", reg["sigminer"], args)
    assert legacy["tree_sha"] == "" and legacy["face"] == "", (
        "legacy rows keep an empty identity slice, never an invented one")


# -- digest-witness verification ----------------------------------------------------

def test_cell_provenance_requires_matching_digest_and_stamp():
    spec = dataclasses.replace(registry.lookup("sigminer_post_v3"),
                               status="ready",
                               image_digest="sha256:" + "a" * 64)
    with tempfile.TemporaryDirectory() as td:
        cachedir = Path(td)
        good = _row()
        cell_dir = cachedir / "cells" / good["cell"] / "out"
        cell_dir.mkdir(parents=True)
        (cell_dir / "manifest.json").write_text(json.dumps(
            {"image_digest": spec.image_digest}), encoding="utf-8")
        bad = _row(n=1000)
        bad_dir = cachedir / "cells" / bad["cell"] / "out"
        bad_dir.mkdir(parents=True)
        (bad_dir / "manifest.json").write_text(json.dumps(
            {"image_digest": "sha256:" + "b" * 64}), encoding="utf-8")
        missing = _row(n=10000)
        verdicts = p6_evidence.verify_cell_provenance(
            cachedir, [good, bad, missing], {"sigminer_post_v3": spec})
        by_cell = {v["cell"]: v for v in verdicts}
        assert by_cell[good["cell"]]["verdict"] == "OK", by_cell
        assert by_cell[bad["cell"]]["verdict"] == "REJECT", by_cell
        assert "digest" in by_cell[bad["cell"]]["why"], by_cell[bad["cell"]]
        assert by_cell[missing["cell"]]["verdict"] == "REJECT", by_cell
        assert "manifest" in by_cell[missing["cell"]]["why"].lower(), by_cell[missing["cell"]]


# -- machine-written result.md (RB-10 idiom) ------------------------------------------

def test_result_md_is_pure_over_its_adjudications():
    """MEASURED-then-stated: the writer stamps numbers ONLY from the data it is
    handed; an absent adjudication renders as PENDING, and no prose constant
    may masquerade as a measurement."""
    md = p6_evidence.write_result_md_text(
        header="P6 regeneration",
        adjudications=[{"name": "parity rust face", "state": "MEASURED",
                        "detail": "1.42x"},
                       {"name": "yardstick", "state": "LEDGERED-PENDING",
                        "detail": "nmf-rs unfetchable"},
                       {"name": "ci-noise anchor gate", "state": "PENDING",
                        "detail": "adjudication not yet run"}])
    assert "1.42x" in md and "MEASURED" in md
    assert "LEDGERED-PENDING" in md
    assert "adjudication not yet run" in md
    # determinism: same input, byte-identical output
    assert md == p6_evidence.write_result_md_text(
        header="P6 regeneration",
        adjudications=[{"name": "parity rust face", "state": "MEASURED",
                        "detail": "1.42x"},
                       {"name": "yardstick", "state": "LEDGERED-PENDING",
                        "detail": "nmf-rs unfetchable"},
                       {"name": "ci-noise anchor gate", "state": "PENDING",
                        "detail": "adjudication not yet run"}])
