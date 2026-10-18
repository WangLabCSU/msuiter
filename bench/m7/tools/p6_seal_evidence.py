#!/usr/bin/env python3
"""S5 sealing pass -- compose the campaign bytes into the committed evidence layer.

The laws themselves live in tools.p6_evidence / tools.p6_predicates (sealed by
groups AB/AA); this tool is the SINGLE deterministic pass that reads a campaign
outdir + cachedir and files the committed artifacts:

  master_committed.csv   the zero-cached shard-union master (all-ok law over
                         the full 8 x 21 grid), columns the frozen nine;
  result.md              machine-written via p6_evidence.write_result_md_text --
                         every figure is a value computed FROM input bytes and
                         handed to the writer as an adjudication record;
  gate_ledgers/p6_seal_report.json
                         the audit trail: sources, rejected-row ledger (the
                         spoken cached/duplicate trail), provenance verdicts,
                         the sha256 of the master it filed.

Inputs are DISCOVERED, never hand-listed: discover_shard_tables() takes exactly
the per-tag pass tables under shard_out/ (a tag carrying two tables is a
replay-trail event and dies), the final-pass table never enters the merge
(the zero-cached law has no reason to look at a replay). Predicates adjudicate
over the campaign bytes ONLY; a declared family that cannot adjudicate is a
REFUSE, never a silent pass (MEASURED-then-stated).

Usage (live, exactly once at S5):
  python3 tools/p6_seal_evidence.py --outdir ../results/p6_regen_<stamp> \
      --cachedir cache/p6_regen_<stamp> \
      --baseline ../results/docker_m7_degraded_20261010-202330/benchmark_m7_20261011-042331.csv
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
for _p in (str(HERE), str(HERE.parent / "g0")):     # G0_DIR read-only idiom
    if _p not in sys.path:
        sys.path.insert(0, _p)

from tools import p6_evidence as ev                  # noqa: E402
from tools import p6_predicates as pred              # noqa: E402

MASTER_NAME = "master_committed.csv"
LEDGER_NAME = "gate_ledgers/p6_seal_report.json"
GATE_OK = ("PASS", "OK", "MEASURED")

#: face tools for the pre-declared P-1/P-2 (manifest SS5): the rust face is
#: the release-gate reading, the R face is reported regardless of outcome.
P1_DEN = "sigprofiler"
P1_FACES = (("sigminer_post_v3_rust", "gate"), ("sigminer_post_v3", "reported"))
P2_TIPS = ("sigminer_post_v3", "sigminer_post_v3_rust")


def discover_shard_tables(cachedir) -> list[Path]:
    """One pass table per shard tag, tags in sorted order -- no more, no less.

    Excludes the logs/ sidecar and any _-prefixed scratch. A tag holding two
    stamped tables is a second-pass replay trail: merging one of them
    silently would be the fabrication the zero-cached law exists to stop."""
    root = Path(cachedir) / "shard_out"
    tables: list[Path] = []
    for tag in sorted((p for p in root.iterdir()
                       if p.is_dir() and p.name not in ("logs",)
                       and not p.name.startswith(("_", "."))),
                      key=lambda p: p.name):
        ts = sorted(tag.glob("timings_m7_degraded_*.csv"))
        if len(ts) > 1:
            raise SystemExit(f"[FATAL] shard {tag.name} carries {len(ts)} pass "
                             f"tables {[t.name for t in ts]} -- a replay "
                             f"trail, not a merge input")
        if ts:
            tables.append(ts[0])
    return tables


def load_table(path: Path) -> list[dict]:
    """Reader for the nine-column table written by run_bench's join idiom."""
    lines = Path(path).read_text(encoding="utf-8").splitlines()
    if not lines:
        return []
    names = lines[0].split(",")
    rows = [dict(zip(names, ln.split(","))) for ln in lines[1:] if ln]
    for r in rows:
        r["n"] = int(r["n"])
        r["seconds"] = float(r["seconds"])
        r["cpu_seconds"] = float(r["cpu_seconds"])
    return rows


def _read_csv_rows(path: Path) -> list[dict]:
    lines = Path(path).read_text(encoding="utf-8").splitlines()
    names = lines[0].split(",")
    return [dict(zip(names, ln.split(","))) for ln in lines[1:] if ln]


def _p2_line(subject, name, base_rows, arm_rows, judged, refusals,
             adjudications) -> None:
    """One gated P-2 reading: adjudicate, record, refuse loudly when not OK."""
    v = pred.tp_only_regression_verdict(base_rows, arm_rows,
                                        {subject: judged})
    state = v["verdict"]
    detail = ("; ".join(v["why"]) if state != "PASS" else
              f"{len(v['cells'])} judged classes held within the committed "
              f"tolerance")
    adjudications.append({"name": name, "state": state, "detail": detail})
    if state not in GATE_OK:
        refusals.append(f"P-2 gate: {subject} -> {state}: {detail}")


def seal(*, outdir, cachedir, tools, classes, specs,
         baseline=None, yardstick=None,
         expected_predicates=(), judged=None, write=False) -> dict:
    """One pass over the campaign bytes. Returns the seal report dict; the
    verdict is REFUSE unless every declared law and gated predicate speaks
    GATE_OK and nothing is left unadjudicated."""
    outdir, cachedir = Path(outdir), Path(cachedir)
    tables = discover_shard_tables(cachedir)
    master, rejected = ev.merge_shards([load_table(t) for t in tables])
    refusals: list[str] = []
    adjudications: list[dict] = []

    # ---- committed-master law: the full grid, first measurements only ------
    expected = {f"{t}__{a}__N{n}" for t in tools for (a, n) in classes}
    missing = sorted(expected - {r["cell"] for r in master})
    if missing:
        refusals.append(f"all-ok law: master short of the {len(expected)}-cell "
                        f"grid, missing {len(missing)}: {missing[:8]}")
    adjudications.append({
        "name": f"master all-ok ({len(expected)} cells, gate)",
        "state": "MEASURED" if not missing else "REFUSE",
        "detail": (f"{len(master)} accepted of {len(expected)}; "
                   f"{len(rejected)} rejected rows spoken in the ledger")})

    # ---- digest-witness law -------------------------------------------------
    verdicts = ev.verify_cell_provenance(cachedir, master, specs)
    bad = [v for v in verdicts if v["verdict"] != "OK"]
    if bad:
        refusals.extend(f"digest-witness law: {v['cell']}: {v['why']}"
                        for v in bad)
    adjudications.append({
        "name": "digest-witness provenance (gate)",
        "state": "PASS" if not bad and verdicts else "REFUSE",
        "detail": f"{len(verdicts)} rows checked, {len(bad)} rejected"})

    # ---- timing attestation line (figures trace to the table bytes) --------
    if master:
        worst = max(master, key=lambda r: r["seconds"])
        adjudications.append({
            "name": "master timing attestation",
            "state": "MEASURED",
            "detail": (f"max wall {worst['seconds']}s at "
                       f"{worst['cell']}, n={len(master)} rows, "
                       f"{len(tables)} shard pass tables")})

    # ---- P-1 parity ----------------------------------------------------------
    # The parity baseline being IN the roster is a structural law checked
    # always: a campaign that dropped sigprofiler has no admissible parity
    # evidence at all, declared or not. Face-by-face adjudication itself runs
    # only when the family is declared and both sides were measured; a face
    # absent from the roster is PENDING (reported), never a silent pass.
    if P1_DEN not in tools:
        refusals.append(f"P-1 baseline: campaign roster has no {P1_DEN} rows "
                        f"to measure parity against")
        adjudications.append({"name": "P-1 parity baseline presence (gate)",
                              "state": "REFUSE",
                              "detail": f"{P1_DEN} absent from the roster"})
    judged = list(judged) if judged is not None else list(classes)
    if "P-1" in expected_predicates:
        den = [r for r in master if r["tool"] == P1_DEN]
        for face, kind in P1_FACES:
            num = [r for r in master if r["tool"] == face]
            v = pred.parity_verdict(den, num, judged)
            state = v["verdict"]
            if state == "PASS":
                worst = max(v["cells"], key=lambda c: c["ratio"] or 0.0)
                detail = (f"{len(v['cells'])} judged classes, worst ratio "
                          f"{worst['ratio']:.3f} at {worst['cell']}")
            elif state == "FAIL":
                bad = sorted((c for c in v["cells"] if not c["passed"]),
                             key=lambda c: -(c["ratio"] or 0.0))
                detail = (f"{len(bad)} offending class(es): "
                          + ", ".join(f"{c['cell']} ratio {c['ratio']:.3f}"
                                       for c in bad))
            else:
                detail = "; ".join(v["why"])
            adjudications.append(
                {"name": f"P-1 parity {face} ({kind})",
                 "state": state, "detail": detail})
            if kind == "gate" and state not in GATE_OK:
                refusals.append(f"P-1 gate: {face} -> {state}: {detail}")
    else:
        adjudications.append({"name": "P-1 parity rust face (gate)",
                              "state": "PENDING",
                              "detail": "family not declared in this pass"})

    # ---- P-2 TP-only non-regression -----------------------------------------
    # The manifest's two admissable readings, both gated: each tip arm against
    # the committed 2.3.1 SIGMINER rows (a single baseline tool is admissible
    # -- the sigprofiler rows in that table are a different instrument, not a
    # baseline for sigminer tips), and the rust face against the v3 face.
    if "P-2" in expected_predicates:
        if baseline is None:
            refusals.append("P-2 declared but no baseline table supplied "
                            "-- no data, no claim")
        else:
            base_rows = [r for r in _read_csv_rows(Path(baseline))
                         if r.get("tool") == "sigminer"]
            if not base_rows:
                refusals.append(f"P-2: baseline {baseline} carries no sigminer "
                                f"rows -- no data, no claim")
            else:
                camp_rows = _read_csv_rows(_campaign_benchmark(outdir))
                for t in P2_TIPS:
                    arm_rows = [r for r in camp_rows if r.get("tool") == t]
                    _p2_line(t, f"P-2 {t} vs 2.3.1 baseline (gate)",
                             base_rows, arm_rows, judged, refusals,
                             adjudications)
                _p2_line("sigminer_post_v3_rust",
                         "P-2 sigminer_post_v3_rust vs sigminer_post_v3 "
                         "(gate)",
                         [r for r in camp_rows
                          if r.get("tool") == "sigminer_post_v3"],
                         [r for r in camp_rows
                          if r.get("tool") == "sigminer_post_v3_rust"],
                         judged, refusals, adjudications)
    else:
        adjudications.append({"name": "P-2 tip non-regression (gate)",
                              "state": "PENDING",
                              "detail": "family not declared in this pass"})

    # ---- P-3 attribution split ------------------------------------------------
    if "P-3" in expected_predicates:
        stage_tools = {x for s in pred.ATTRIBUTION_STAGES for x in s[1:3]}
        if not stage_tools <= set(tools):
            refusals.append(f"P-3 declared but stage tools absent from the "
                           f"table: {sorted(stage_tools - set(tools))}")
        else:
            #: the attribution ladder is the main arm's ladder; comp_* N tiers
            #: (e.g. comp_pole at 1e6) have no main cells and are not stages
            ns = sorted(nn for (a, nn) in classes if a == "main")
            for n in ns:
                v = pred.attribution_split(master, n=n, arms=("main",))
                #: attribution_split speaks its own verdict space (OK/REFUSE);
                #: the ledger's closed vocabulary needs it translated, and an
                #: empty stage set is no evidence -- it refuses, never passes.
                if v["verdict"] == "OK" and not v["stages"]:
                    state, detail = "REFUSE", (
                        f"no stage formed a ratio at N={n}: the declared "
                        f"stage tools share no cells -- unmeasured, unattributed")
                else:
                    state = "PASS" if v["verdict"] == "OK" else v["verdict"]
                    detail = ("; ".join(v["why"]) if v["verdict"] != "OK" else
                              f"{len(v['stages'])} stages at N={n}, worst "
                              f"{max(s['ratio'] for s in v['stages'].values()):.3f}")
                adjudications.append({"name": f"P-3 attribution N={n} (gate)",
                                      "state": state, "detail": detail})
                if state not in GATE_OK:
                    refusals.append(f"P-3 gate N={n} -> {state}: {detail}")
    else:
        adjudications.append({"name": "P-3 attribution split (gate)",
                              "state": "PENDING",
                              "detail": "family not declared in this pass"})

    # ---- yardstick two-state law ----------------------------------------------
    if yardstick is not None:
        p = Path(yardstick)
        if not p.is_file():
            refusals.append(f"yardstick attestation absent: {p}")
            adjudications.append({"name": "yardstick", "state": "REFUSE",
                                  "detail": f"absent: {p}"})
        else:
            doc = json.loads(p.read_text(encoding="utf-8"))
            fair = ("fairness_flag" not in doc
                    and doc.get("rust_niter") == doc.get("r_niter")
                    and doc.get("rust_niter") == doc.get("iterations_fixed"))
            if not fair:
                refusals.append("yardstick attestation carries a fairness_flag "
                                "or niter mismatch -- never admissible as "
                                "MEASURED")
                adjudications.append({"name": "yardstick", "state": "REFUSE",
                                      "detail": "unfair bytes refused"})
            else:
                ys = pred.yardstick_status(doc, pending_reason=None,
                                           evidence_path=None)
                fx = str(doc.get("fixture_sha256", "unrecorded"))[:16]
                adjudications.append({
                    "name": "yardstick", "state": ys["state"],
                    "detail": (f"ratio {ys['ratio']:.2f} "
                               f"(rust {ys['rust_seconds']:.6f}s, "
                               f"r {ys['r_seconds']:.6f}s) at the committed "
                               f"fixed count {doc.get('iterations_fixed')}, "
                               f"fixture {fx}")})
    else:
        adjudications.append({"name": "yardstick", "state": "PENDING",
                              "detail": "attestation not supplied to this "
                                        "pass (the committed file must carry "
                                        "the two-state reading)"})

    verdict = "REFUSE" if refusals else "SEALED"
    # A gate line speaking REFUSE/FAIL is fatal even if a branch forgot to
    # push its refusal; PENDING is REPORTED (an undeclared family is spoken
    # as unadjudicated, which is the opposite of a silent pass) and the
    # declared-live path can never reach it because main() declares all.
    gated_bad = [a for a in adjudications
                 if "(gate)" in a["name"] and a["state"] in ("REFUSE", "FAIL")]
    if gated_bad:
        verdict = "REFUSE"
    report = {"verdict": verdict,
              "sources": [str(t) for t in tables],
              "accepted": len(master),
              "rejected": rejected,
              "provenance": verdicts,
              "refusals": refusals,
              "adjudications": adjudications,
              "sealed_utc": (time.strftime("%Y-%m-%dT%H:%M:%S+00:00",
                                           time.gmtime())
                             if verdict == "SEALED" else None)}
    if write and verdict == "SEALED":
        _file(outdir, master, report)
    return report


def file_refusal(*, outdir, report) -> None:
    """File the refusal lane's evidence: verdict-bearing result.md (machine
    writer, every figure a computed adjudication record) and the gate ledger
    with its spoken refusals. The master name stays RESERVED: a campaign whose
    gate failed attests its measurements, never a SEALED master."""
    outdir = Path(outdir)
    if report.get("verdict") == "SEALED":
        raise SystemExit("[FATAL] file_refusal called on a SEALED report -- "
                         "the sealed lane is seal(write=True)")
    outdir.mkdir(parents=True, exist_ok=True)
    (outdir / "result.md").write_text(
        ev.write_result_md_text(
            "P6 evidence campaign -- REFUSED, gate ledger follows",
            report["adjudications"]),
        encoding="utf-8")
    led = outdir / "gate_ledgers"
    led.mkdir(exist_ok=True)
    (led / "p6_seal_report.json").write_text(
        json.dumps(report, sort_keys=True, indent=1) + "\n",
        encoding="utf-8")


def _campaign_benchmark(outdir: Path) -> Path:
    ts = sorted(outdir.glob("benchmark_m7_*.csv"))
    if len(ts) != 1:
        raise SystemExit(f"[FATAL] campaign benchmark table not singular: "
                         f"{[t.name for t in ts]}")
    return ts[0]


def _file(outdir: Path, master: list[dict], report: dict) -> None:
    outdir.mkdir(parents=True, exist_ok=True)
    with (outdir / MASTER_NAME).open("w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(list(ev.MASTER_COLUMNS))
        for r in sorted(master, key=lambda r: r["cell"]):
            w.writerow([r[k] for k in ev.MASTER_COLUMNS])
    (outdir / "result.md").write_text(
        ev.write_result_md_text(
            "P6 evidence campaign -- sealed adjudications",
            report["adjudications"]),
        encoding="utf-8")
    body = (outdir / MASTER_NAME).read_bytes()
    report["master_sha256"] = hashlib.sha256(body).hexdigest()
    led = outdir / "gate_ledgers"
    led.mkdir(exist_ok=True)
    (led / "p6_seal_report.json").write_text(
        json.dumps(report, sort_keys=True, indent=1) + "\n", encoding="utf-8")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--outdir", type=Path, required=True)
    ap.add_argument("--cachedir", type=Path, required=True)
    ap.add_argument("--baseline", type=Path, default=None)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--refuse-ledger", action="store_true",
                    help="on a REFUSE verdict, file result.md + the gate "
                         "ledger (the master name stays SEALED-reserved)")
    args = ap.parse_args(argv)

    from competitors import registry                      # noqa: E402
    reg = registry.load()
    #: only attested images may carry cells; a pending-verify roster entry
    #: (e.g. `signal`) has no digest and was never measured -- admitting it
    #: would fabricate a 21-cell deficit out of a non-participant.
    tools = sorted(t for t in reg if getattr(reg[t], "status", None) == "ready")
    from g0 import grid                                   # noqa: E402
    arms = grid.arms_for_profile("degraded")
    classes = [(a.name, n) for a in arms for n in a.n_list]
    judged = [(a.name, n) for a in arms if a.judge for n in a.n_list]
    report = seal(outdir=args.outdir, cachedir=args.cachedir,
                  tools=tools, classes=classes, judged=judged,
                  specs={t: reg[t] for t in tools},
                  baseline=args.baseline,
                  yardstick=(args.outdir / "nmf_yardstick_authoritative.json")
                  if (args.outdir / "nmf_yardstick_authoritative.json").is_file()
                  else None,
                  expected_predicates=("P-1", "P-2", "P-3"),
                  write=not args.dry_run)
    print(json.dumps({"verdict": report["verdict"],
                      "accepted": report["accepted"],
                      "refusals": report["refusals"]}, indent=1))
    if args.refuse_ledger and report["verdict"] == "REFUSE":
        file_refusal(outdir=args.outdir, report=report)
    return 0 if report["verdict"] == "SEALED" else 4


if __name__ == "__main__":
    raise SystemExit(main())
