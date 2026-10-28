#!/usr/bin/env python3
"""Resumable P6 floor-calibration batch: REP-100 witnesses for the six arms.

The RB-09 floor law is all-or-nothing per tool: a tool that arrives in
_MEASURED_TOOLS must carry one OK, reps-matched witness for EVERY protocol
class it will run, or floor_for KeyErrors mid-campaign after hours of
measurement. This tool mints exactly those bytes -- 6 arms x the 21 frozen
degraded-grid classes = 126 witnesses -- through the SAME probe that sealed
the legacy table (tools/probe_sigminer_cell_argv.run_probe), so the witness
schema, the freshness law and the --floor-gate off posture (a probe measures,
it never self-adjudicates) are inherited, not re-implemented.

Laws honored mechanically:
  * zero-cached/freshness: every probe gets a fresh per-cell cachedir; a
    replay with status 'cached' is DEFECT (the probe's own law), and DEFECT
    witnesses are never kept -- the batch stops on the first one, the fix is
    made, and the batch resumes over the missing set only;
  * MEASURED-then-stated: the anchor-table entries this tool prints (and the
    fragment it writes) are read FROM the finished witness bytes -- cpu_seconds
    from the validated sidecar, wall from the host clock -- never from hope;
  * provenance: CALIBRATION.json (schema m7-floor-calibration-1) records the
    explicit-algorithm hash recorder, the registry bytes' sha at mint, the
    probe count, and the witness_sha256 map over every committed witness.

Ordering (SS3/SS4): runs AFTER the inspect flip (the registry gate refuses
PENDING-VERIFY rows at compose time) and BEFORE the single authoritative
ignition (tests/test_p6_floor_governance.py gates the suite on these bytes).

Usage:
  python3 tools/calibrate_p6_floors.py                      # mint (resumable)
  python3 tools/calibrate_p6_floors.py --dir <existing>     # resume a named dir
  python3 tools/calibrate_p6_floors.py --only sigminer_post_v3
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from competitors import p6_arms                      # noqa: E402
from tools import probe_sigminer_cell_argv as probe  # noqa: E402

RESULTS = HERE.parent / "results"
REPS = 100                                          # the gated protocol scale


def grid_classes() -> list[tuple[str, int]]:
    """The 21 frozen classes (read-only g0 import -- sampling constants are
    untouchable law, this function may only READ them)."""
    from g0 import grid
    out = []
    for arm in grid.arms_for_profile("degraded"):
        for n in arm.n_list:
            out.append((arm.name, n))
    return out


def witness_doc_ok(path: Path) -> bool:
    """A kept witness is an OK/ok/rep-100 doc; anything else is re-minted."""
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return False
    return (doc.get("verdict") == "OK" and doc.get("status_tail") == "ok"
            and doc.get("sidecar", {}).get("exit_status") == 0)


def _utc_stamp() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S")


def _validate_declared_probes(ledger: Path, caldir: str, declared: int) -> int:
    """Attestation law: a declared probe count must equal the booked DONE rows
    of its own campaign in the lane budget ledger (shape column
    ``mint/<caldir>/...``). Hand-written ledger rows are impossible under the
    sole-logger law, so an inflated declaration has nothing to stand on:
    over- or under-speaking the booked legs is refused, not warned."""
    booked = 0
    for ln in ledger.read_text(encoding="utf-8").splitlines()[1:]:
        cols = ln.split("\t")
        if (len(cols) > 7 and cols[4].startswith(f"mint/{caldir}/")
                and cols[7] == "DONE"):
            booked += 1
    if int(declared) != booked:
        raise AssertionError(
            f"--probes-declared={declared} but the ledger books {booked} DONE "
            f"legs for mint/{caldir}/ -- attestation refused")
    return booked


def mint(wdir: Path, *, only: list[str] | None,
         probes_declared: int | None = None,
         campaign_note: str | None = None,
         budget_ledger: Path | None = None) -> int:
    classes = grid_classes()
    if len(classes) != 21:
        print(f"[FATAL] degraded grid shape drifted: {len(classes)} classes",
              file=sys.stderr)
        return 2
    wdir.mkdir(parents=True, exist_ok=True)
    witnesses = wdir / "witnesses"
    witnesses.mkdir(exist_ok=True)
    scratch = wdir / "_scratch"
    tools = only or sorted(p6_arms.P6_ARM_SPECS)
    probes_run = defects = 0
    t_start = time.monotonic()
    for tool in tools:
        for arm, n in classes:
            target = witnesses / f"{tool}__{arm}__N{n}__rep{REPS}.json"
            if target.exists() and witness_doc_ok(target):
                continue
            rc = probe.run_probe(tool, arm=arm, n=n, reps=REPS,
                                json_path=str(target), work=str(scratch))
            probes_run += 1
            if rc != 0 or not witness_doc_ok(target):
                doc = json.loads(target.read_text(encoding="utf-8")) \
                    if target.exists() else {}
                print(f"[DEFECT] {target.name}: rc={rc} "
                      f"reason={doc.get('reason', doc.get('missing', 'unknown'))}",
                      file=sys.stderr)
                defects += 1
                print("[stop] the batch halts on the first DEFECT: fix the cause, "
                      "re-invoke -- kept witnesses resume-skip, this cell re-mints",
                      file=sys.stderr)
                return 3
    if defects:
        return 3
    # ---- ledger: written only over a complete, all-OK witness set ----------
    registry_bytes = (HERE / "competitors" / "registry.py").read_bytes()
    wmap = {w.name: hashlib.sha256(w.read_bytes()).hexdigest()
            for w in sorted(witnesses.glob(f"*__rep{REPS}.json"))}
    expected = 21 * len(tools) if only else 21 * len(p6_arms.P6_ARM_SPECS)
    if len(wmap) < expected:
        print(f"[FATAL] ledger over incomplete set: {len(wmap)} < {expected}",
              file=sys.stderr)
        return 2
    if probes_declared is not None:
        if budget_ledger is None:
            print("[FATAL] --probes-declared requires --budget-ledger to "
                  "validate against", file=sys.stderr)
            return 2
        try:
            probes = _validate_declared_probes(budget_ledger, wdir.name,
                                               probes_declared)
        except AssertionError as exc:
            print(f"[FATAL] {exc}", file=sys.stderr)
            return 2
    else:
        probes = probes_run
    ledger = {
        "schema": "m7-floor-calibration-1",
        "created_utc": time.strftime("%Y-%m-%dT%H:%M:%S+00:00", time.gmtime()),
        "hash_recorder": "python3 hashlib.sha256 (explicit algorithm, never "
                         "the platform shasum default)",
        "registry_sha256_at_mint": hashlib.sha256(registry_bytes).hexdigest(),
        "probes": probes,
        "law": {
            "reps": f"all witnesses measured at REP-{REPS} (protocol scale)",
            "freshness": "fresh per-cell cachedir per probe; a 'cached' replay "
                         "is DEFECT, never a floor",
            "gate": "--floor-gate off: a probe measures, it never self-adjudicates",
        },
        "campaign_note": campaign_note or (
            "P6 evidence-loop calibration (lane manifest SS4); "
            "arms measured against their inspect-attested images"),
        "witness_sha256": wmap,
        "elapsed_seconds_probes_this_invocation": round(time.monotonic() - t_start, 1),
    }
    (wdir / "CALIBRATION.json").write_text(
        json.dumps(ledger, sort_keys=True, indent=1) + "\n", encoding="utf-8")

    # ---- MEASURED-then-stated: anchor entries assembled FROM witness bytes --
    fragment = {}
    for w in sorted(witnesses.glob(f"*__rep{REPS}.json")):
        doc = json.loads(w.read_text(encoding="utf-8"))
        key = f"{doc['tool']}|{doc['arm']}|N{doc['n']}"
        fragment[key] = {
            "witness": (wdir.name, "witnesses", w.name),
            "reps": doc["reps"],
            "cpu_seconds": doc["sidecar"]["cpu_seconds"],
            "wall_seconds": doc["wall_seconds"],
        }
    (wdir / "anchors_fragment.json").write_text(
        json.dumps(fragment, sort_keys=True, indent=1) + "\n", encoding="utf-8")
    print(f"[done] {len(fragment)} anchors over {len(tools)} arms in {wdir} "
          f"({probes_run} probes this invocation)")
    print("next: matrix_governance._FLOOR_ANCHORS table edit from "
          "anchors_fragment.json (MEASURED-then-stated), then the (AC) group "
          "witnesses the bytes")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dir", default=None,
                    help="witness dir name under bench/results (default: fresh "
                         "m7_floor_calibration_p6_<UTCstamp>)")
    ap.add_argument("--only", action="append", default=None,
                    help="restrict to this arm key (repeatable; development aid -- "
                         "the committed set must still be all six)")
    ap.add_argument("--probes-declared", type=int, default=None,
                    help="resume-pass attestation: the probe count this campaign's "
                         "mint legs already spoke; validated against --budget-ledger")
    ap.add_argument("--budget-ledger", type=Path, default=None,
                    help="lane budget.tsv whose booked rows back the declaration")
    ap.add_argument("--campaign-note", default=None,
                    help="honest provenance sentence for THIS campaign's ledger "
                         "(default: the frozen P6 SS4 note)")
    args = ap.parse_args(argv)
    if args.only:
        for t in args.only:
            if t not in p6_arms.P6_ARM_SPECS:
                print(f"[FATAL] unknown arm {t}", file=sys.stderr)
                return 2
    wdir = RESULTS / (args.dir or f"m7_floor_calibration_p6_{_utc_stamp()}")
    return mint(wdir, only=args.only, probes_declared=args.probes_declared,
                campaign_note=args.campaign_note, budget_ledger=args.budget_ledger)


if __name__ == "__main__":
    raise SystemExit(main())
