"""Group (AG) test_p6_seal_evidence -- the S5 sealing tool over synthetic bytes.

tools/p6_seal_evidence.py composes the ALREADY-SEALED laws of (AB) into one
deterministic artifact pass: discover the shard pass tables, merge under the
zero-cached / hardware-pin / first-wins laws, gate every row through the
digest-witness, adjudicate the pre-declared predicates (P-1 parity, P-2
TP-only non-regression, P-3 attribution, the yardstick two-state) over the
campaign outdir bytes ONLY, and file result.md + the committed master + the
seal report. The units here are synthetic-tree (CI-safe, no docker, no
campaign dependence); the live run happens exactly once, at S5.

The MEASURED-then-stated law is sealed as a NUMBER-TRACE unit: a figure may
appear in result.md only when it is derivable from an adjudication record
that was itself computed from input bytes -- a planted foreign constant (the
paper's 76x) must never reach the file.
"""

from __future__ import annotations

import csv
import hashlib
import json
import sys
import tempfile
import types
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from tools import p6_seal_evidence as seal          # noqa: E402  (RED seam)
from tools import p6_evidence as ev                 # noqa: E402

DIG = "sha256:" + "a1" * 32


def _row(tool, arm, n, seconds, status="ok"):
    return {"cell": f"{tool}__{arm}__N{n}", "tool": tool, "arm": arm,
            "n": n, "seconds": seconds, "status": status,
            "cpu_seconds": seconds * 1.4, "host": "testhost",
            "hw_profile": "10 vCPU / 8 GB class"}


def _write_table(path, rows):
    # canonical repo idiom (run_bench :194): plain csv.writer, explicit \n
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(list(ev.MASTER_COLUMNS))
        for r in rows:
            w.writerow([r[k] for k in ev.MASTER_COLUMNS])


def _read_table(path):
    lines = Path(path).read_text(encoding="utf-8").splitlines()
    names = lines[0].split(",")
    return [dict(zip(names, ln.split(","))) for ln in lines[1:] if ln]


def _mk_campaign(root: Path, *, drop=(), tamper=(), drop_tool=None,
                 force_dup=False):
    """Synthetic 2-shard campaign: tools sigminer + sigprofiler, class
    (main,100); optional complement shard; optional yardstick/baseline."""
    cd, out = root / "cache" / "camp", root / "results" / "camp"
    tools = [t for t in ("sigminer", "sigprofiler") if t != drop_tool]
    rows = [_row(t, "main", 100, 800.0 if t == "sigminer" else 400.0)
            for t in tools]
    rows = [r for r in rows if r["cell"] not in drop]
    _write_table(cd / "shard_out" / "main"
                 / "timings_m7_degraded_20261017-120000_main.csv", rows)
    if force_dup:
        _write_table(cd / "shard_out" / "main_force_1"
                     / "timings_m7_degraded_20261017-130000_main_force_1.csv",
                     [_row("sigminer", "main", 100, 800.0)])
    for r in rows:
        man = cd / "cells" / r["cell"] / "out" / "manifest.json"
        man.parent.mkdir(parents=True, exist_ok=True)
        d = "b2" * 32 if (r["tool"], "main", 100) in tamper else DIG
        man.write_text(json.dumps({"image_digest": d}) + "\n", encoding="utf-8")
    out.mkdir(parents=True, exist_ok=True)
    specs = {t: types.SimpleNamespace(image_digest=DIG) for t in tools}
    return cd, out, tools, specs


def test_discovery_takes_only_shard_pass_tables_in_order():
    with tempfile.TemporaryDirectory() as t:
        root = Path(t)
        cd, *_ = _mk_campaign(root)
        # decoys: a final-pass table in OUTDIR, a logs dir, a _scratch dir
        _write_table(root / "results" / "camp"
                     / "timings_m7_degraded_20261017-174727.csv",
                     [_row("sigminer", "main", 100, 0.0, status="cached")])
        (cd / "shard_out" / "logs").mkdir(parents=True, exist_ok=True)
        (cd / "shard_out" / "_scratch").mkdir(parents=True, exist_ok=True)
        got = seal.discover_shard_tables(cd)
        assert [p.parent.name for p in got] == ["main"], \
            f"discovery must read exactly the shard pass tables: {got}"


def test_seal_files_clean_master_ledger_and_report():
    with tempfile.TemporaryDirectory() as t:
        root = Path(t)
        cd, out, tools, specs = _mk_campaign(root)
        res = seal.seal(outdir=out, cachedir=cd, tools=tools,
                        classes=[("main", 100)], specs=specs,
                        baseline=None, yardstick=None, write=True)
        assert res["verdict"] == "SEALED", res
        master = _read_table(out / "master_committed.csv")
        assert {r["tool"] for r in master} == set(tools)
        assert all(r["status"] == "ok" for r in master), "zero-cached law"
        assert list(master[0].keys()) == list(ev.MASTER_COLUMNS), \
            "the frozen nine column schema"
        rep = json.loads((out / "gate_ledgers" / "p6_seal_report.json")
                         .read_text(encoding="utf-8"))
        sha = hashlib.sha256((out / "master_committed.csv")
                             .read_bytes()).hexdigest()
        assert rep["master_sha256"] == sha, "the ledger attests the bytes it filed"
        assert rep["sources"] == [str(cd / "shard_out" / "main"
                                      / "timings_m7_degraded_20261017-120000_main.csv")]


def test_short_master_is_a_refusal_not_a_filing():
    with tempfile.TemporaryDirectory() as t:
        cd, out, tools, specs = _mk_campaign(Path(t), drop=("sigminer__main__N100",))
        res = seal.seal(outdir=out, cachedir=cd, tools=tools,
                        classes=[("main", 100)], specs=specs,
                        baseline=None, yardstick=None, write=True)
        assert res["verdict"] == "REFUSE", res
        assert not (out / "master_committed.csv").exists(), \
            "an incomplete master may never be filed"
        assert any("sigminer__main__N100" in w for w in res["refusals"]), \
            "the refusal must name the missing cell"


def test_provenance_mismatch_is_a_refusal_naming_the_cell():
    with tempfile.TemporaryDirectory() as t:
        cd, out, tools, specs = _mk_campaign(
            Path(t), tamper={("sigminer", "main", 100)})
        res = seal.seal(outdir=out, cachedir=cd, tools=tools,
                        classes=[("main", 100)], specs=specs,
                        baseline=None, yardstick=None, write=True)
        assert res["verdict"] == "REFUSE", res
        # the REJECT record itself names the cell (its cell field) -- the why
        # string carries digests, not the cell key
        assert any("sigminer__main__N100" in str(v)
                   for v in res["provenance"] if v["verdict"] == "REJECT")


def test_duplicate_cell_first_wins_and_is_reported():
    with tempfile.TemporaryDirectory() as t:
        cd, out, tools, specs = _mk_campaign(Path(t), force_dup=True)
        res = seal.seal(outdir=out, cachedir=cd, tools=tools,
                        classes=[("main", 100)], specs=specs,
                        baseline=None, yardstick=None, write=True)
        assert res["verdict"] == "SEALED", res
        dups = [r for r in res["rejected"]
                if "duplicate cell across shards" in r["why"]]
        assert len(dups) == 1 and dups[0]["row"]["tool"] == "sigminer", \
            "the resume trail must be spoken, not silently merged"


def test_yardstick_measured_only_over_fair_bytes():
    with tempfile.TemporaryDirectory() as t:
        root = Path(t)
        cd, out, tools, specs = _mk_campaign(root)
        fair = {"rust_seconds": 0.25, "r_seconds": 1.0, "rust_niter": 400,
                "r_niter": 400, "iterations_fixed": 400}
        ys = out / "nmf_yardstick_authoritative.json"
        ys.write_text(json.dumps(fair) + "\n", encoding="utf-8")
        res = seal.seal(outdir=out, cachedir=cd, tools=tools,
                        classes=[("main", 100)], specs=specs,
                        baseline=None, yardstick=ys, write=True)
        assert res["verdict"] == "SEALED", res
        yline = [a for a in res["adjudications"] if a["name"].startswith("yardstick")]
        assert yline and yline[0]["state"] == "MEASURED"
        body = (out / "result.md").read_text(encoding="utf-8")
        assert "**yardstick**: MEASURED" in body and "4.0" in body, \
            "the ratio line must be the machine value (1.0/0.25)"
        ys.write_text(json.dumps({**fair, "fairness_flag": "rust!=r"}) + "\n",
                      encoding="utf-8")
        res2 = seal.seal(outdir=out, cachedir=cd, tools=tools,
                         classes=[("main", 100)], specs=specs,
                         baseline=None, yardstick=ys, write=False)
        assert res2["verdict"] == "REFUSE", \
            "a fairness_flag attestation is never admissible as MEASURED"


def test_parity_refuses_on_missing_side_never_fabricates():
    with tempfile.TemporaryDirectory() as t:
        cd, out, tools, specs = _mk_campaign(Path(t), drop_tool="sigprofiler")
        res = seal.seal(outdir=out, cachedir=cd, tools=tools,
                        classes=[("main", 100)], specs=specs,
                        baseline=None, yardstick=None, write=False)
        assert res["verdict"] == "REFUSE", res
        assert any("P-1" in a["name"] and a["state"] == "REFUSE"
                   for a in res["adjudications"]), \
            "a missing denominator side is REFUSE, never a silent pass"


def test_result_md_numbers_all_trace_to_inputs():
    with tempfile.TemporaryDirectory() as t:
        cd, out, tools, specs = _mk_campaign(Path(t))
        res = seal.seal(outdir=out, cachedir=cd, tools=tools,
                        classes=[("main", 100)], specs=specs,
                        baseline=None, yardstick=None, write=True)
        assert res["verdict"] == "SEALED", res
        body = (out / "result.md").read_text(encoding="utf-8")
        assert "800.0" in body, "a measured figure from the table must appear"
        assert "76" not in body.replace("0.76", ""), \
            "the paper's 76x is UNMEASURED and may never enter this file"


def test_refusal_ledger_files_report_and_result_but_never_master():
    # A gate FAIL over a COMPLETE master is a finding the campaign must speak:
    # the refusal lane files the ledger + result.md (verdict-bearing header),
    # and still never files the SEALED-reserved master.
    with tempfile.TemporaryDirectory() as t:
        cd, out, tools, specs = _mk_campaign(Path(t), drop_tool="sigprofiler")
        res = seal.seal(outdir=out, cachedir=cd, tools=tools,
                        classes=[("main", 100)], specs=specs,
                        baseline=None, yardstick=None, write=False)
        assert res["verdict"] == "REFUSE", res
        seal.file_refusal(outdir=out, report=res)
        assert not (out / "master_committed.csv").exists(), \
            "the master name is reserved for a SEALED pass"
        rep = json.loads((out / "gate_ledgers" / "p6_seal_report.json")
                         .read_text(encoding="utf-8"))
        assert rep["verdict"] == "REFUSE" and rep["refusals"], \
            "the refusal must be spoken in the ledger, not laundered"
        body = (out / "result.md").read_text(encoding="utf-8")
        assert "REFUSED" in body and "**P-1" in body, \
            "result.md must carry the verdict-bearing header and the P-1 line"
        assert "76" not in body.replace("0.76", "")


def test_refusal_ledger_rerun_is_byte_identical():
    with tempfile.TemporaryDirectory() as t:
        cd, out, tools, specs = _mk_campaign(Path(t), drop_tool="sigprofiler")
        res = seal.seal(outdir=out, cachedir=cd, tools=tools,
                       classes=[("main", 100)], specs=specs,
                       baseline=None, yardstick=None, write=False)
        seal.file_refusal(outdir=out, report=res)
        first = (out / "gate_ledgers" / "p6_seal_report.json").read_bytes()
        assert b'"sealed_utc": null' in first, \
            "a refusal never attests a seal instant"
        res2 = seal.seal(outdir=out, cachedir=cd, tools=tools,
                        classes=[("main", 100)], specs=specs,
                        baseline=None, yardstick=None, write=False)
        seal.file_refusal(outdir=out, report=res2)
        # sealed_utc was None in both; sort_keys makes the rest deterministic
        assert (out / "gate_ledgers" / "p6_seal_report.json") \
            .read_bytes() == first


P3_TOOLS = ("sigminer", "sigminer_pre_v3", "sigminer_post_p1",
            "sigminer_post_p1_rust", "sigminer_post_p2", "sigminer_post_v3",
            "sigminer_post_v3_rust", "sigprofiler")


def _mk_p3_campaign(root: Path, *, drop_rows_of=()):
    """Campaign whose rows carry every attribution stage tool at (main,100)
    -- the shape the live table actually has. drop_rows_of names tools whose
    rows are withheld while the roster still declares them."""
    cd, out = root / "cache" / "p3camp", root / "results" / "p3camp"
    rows = [_row(t, "main", 100, 100.0 + 25 * i)
            for i, t in enumerate(P3_TOOLS) if t not in drop_rows_of]
    for tag, part in (("main", rows),):
        _write_table(cd / "shard_out" / tag
                     / f"timings_m7_degraded_20261018-000000_{tag}.csv", part)
    for r in rows:
        man = cd / "cells" / r["cell"] / "out" / "manifest.json"
        man.parent.mkdir(parents=True, exist_ok=True)
        man.write_text(json.dumps({"image_digest": DIG}) + "\n", encoding="utf-8")
    out.mkdir(parents=True, exist_ok=True)
    specs = {t: types.SimpleNamespace(image_digest=DIG) for t in P3_TOOLS}
    return cd, out, list(P3_TOOLS), specs


def test_p3_gate_translates_predicate_ok_into_ledger_language():
    """The live run was the first execution of this path: attribution_split
    speaks OK/REFUSE, the sealed ledger lexicon is MEASURED/PASS/FAIL/REFUSE/
    LEDGERED-PENDING/PENDING -- the seal must translate, never copy."""
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        cd, out, tools, specs = _mk_p3_campaign(root)
        res = seal.seal(outdir=out, cachedir=cd, tools=tools,
                       classes=[("main", 100)], specs=specs,
                       expected_predicates=("P-3",), write=False)
        assert res["verdict"] == "SEALED", res["refusals"]
        line = [a for a in res["adjudications"]
                if a["name"].startswith("P-3 attribution N=100")]
        assert len(line) == 1
        assert line[0]["state"] == "PASS", line[0]
        assert line[0]["detail"].startswith("6 stages"), line[0]["detail"]
        # the closed vocabulary accepts the whole report end-to-end
        ev.write_result_md_text("P6 test", res["adjudications"])


def test_p3_missing_stage_rows_refuse_never_pass():
    """A stage that forms no ratio is unmeasured: REFUSE, and it poisons the
    verdict -- silence is not consent."""
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        cd, out, tools, specs = _mk_p3_campaign(root,
                                                drop_rows_of=("sigminer_post_p1_rust",))
        res = seal.seal(outdir=out, cachedir=cd, tools=tools,
                        classes=[("main", 100)], specs=specs,
                        expected_predicates=("P-3",), write=False)
        assert res["verdict"] == "REFUSE"
        assert any("kernel_face" in rf for rf in res["refusals"]), res["refusals"]


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
