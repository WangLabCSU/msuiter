#!/usr/bin/env python3
"""Deterministic anchors_fragment.json -> matrix_governance._FLOOR_ANCHORS bridge.

The (AC) group seals WHAT an anchor must be (committed, reps-matched, verdict-OK
witness backing); this tool is the only sanctioned way such a table edit gets
PRODUCED. Values are never transcribed by a human or an agent: the fragment is
an INDEX (keys + witness pointers) and every figure is re-read FROM THE WITNESS
SIDECAR at registration time -- a fragment that lies about a witness dies, and
so does a fragment pointing at a witness that is not on disk. Legacy (RB-09)
entries are preserved untouched; entries claiming this caldir but missing from
the fragment are stale residue and REFUSE. Byte-sterile on REFUSE: the source
is not written unless the whole pass verifies.

Usage:
  python3 tools/register_p6_anchors.py --dir m7_floor_calibration_p6_20261017
"""

from __future__ import annotations

import argparse
import ast
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

REPS = 100                                          # frozen calibration reps
TABLE = "_FLOOR_ANCHORS"


def _parse_key(key: str):
    tool, arm, n = key.split("|")
    if not n.startswith("N") or not n[1:].isdigit():
        raise ValueError(f"fragment key {key!r}: N-part malformed")
    return (tool, arm, int(n[1:]))


def _load_current(source: Path) -> dict:
    tree = ast.parse(source.read_text(encoding="utf-8"))
    for node in tree.body:
        if (isinstance(node, ast.Assign) and len(node.targets) == 1
                and getattr(node.targets[0], "id", None) == TABLE):
            table = ast.literal_eval(node.value)
            return {tuple(k): v for k, v in table.items()}
    raise SystemExit(f"[FATAL] {source} carries no {TABLE} literal")


def _render(table: dict) -> str:
    lines = [f"{TABLE} = {{"]
    for key in sorted(table, key=lambda k: (str(k[0]), str(k[1]), k[2])):
        e = table[key]
        lines.append(f"    {key!r}: {{")
        lines.append(f"        'witness': {tuple(e['witness'])!r},")
        lines.append("        'reps': " + f"{e['reps']!r}, "
                     f"'cpu_seconds': {e['cpu_seconds']!r}, "
                     f"'wall_seconds': {e['wall_seconds']!r},")
        lines.append("    },")
    lines.append("}")
    return "\n".join(lines)


def _verify_witness(wdir: Path, fname: str, refusals: list[str]):
    """The witness is the authority: reread it, gate its own claims."""
    path = wdir / fname
    if not path.is_file():
        refusals.append(f"witness not on disk: {path}")
        return None
    doc = json.loads(path.read_text(encoding="utf-8"))
    if doc.get("verdict") != "OK" or doc.get("exit_code") != 0:
        refusals.append(f"witness {fname} does not speak "
                        f"verdict=OK/exit=0 -- unverified bytes are never "
                        f"anchored")
        return None
    if doc.get("reps") != REPS:
        refusals.append(f"witness {fname} reps={doc.get('reps')!r} != {REPS}")
        return None
    side = doc.get("sidecar", {})
    if "cpu_seconds" not in side or "wall_seconds" not in doc:
        refusals.append(f"witness {fname} lacks sidecar.cpu_seconds/"
                        f"wall_seconds -- no measurement, no anchor")
        return None
    return {"witness": None, "reps": doc["reps"],
            "cpu_seconds": side["cpu_seconds"],
            "wall_seconds": doc["wall_seconds"]}


def register(*, gov_source, results_dir, caldir) -> dict:
    """One verify-then-rewrite pass. Returns {verdict, refusals, count}."""
    gov_source, results_dir = Path(gov_source), Path(results_dir)
    wdir = results_dir / caldir / "witnesses"
    frag_path = results_dir / caldir / "anchors_fragment.json"
    refusals: list[str] = []
    if not frag_path.is_file():
        return {"verdict": "REFUSE",
                "refusals": [f"no fragment at {frag_path} -- nothing to "
                             f"register (calibration must complete first)"],
                "count": 0}
    fragment = json.loads(frag_path.read_text(encoding="utf-8"))
    current = _load_current(gov_source)
    ours = {k: v for k, v in current.items() if v["witness"][0] == caldir}
    # compare in the fragment's OWN key space: "tool|arm|N<n>"; comparing a
    # str(tuple) against fragment strings would flag every entry stale
    ours_frag = {f"{t}|{arm}|N{n}" for (t, arm, n) in ours}
    stale = sorted(ours_frag - set(fragment))
    if stale:
        refusals.append(f"table claims {len(stale)} entries from {caldir} "
                        f"that the fragment does not carry: {stale[:4]}")
    new_entries: dict = {}
    for key, idx in fragment.items():
        try:
            ck = _parse_key(key)
        except ValueError as exc:
            refusals.append(str(exc))
            continue
        w_tuple = list(idx.get("witness", []))
        if len(w_tuple) != 3 or w_tuple[0] != caldir or w_tuple[1] != "witnesses":
            refusals.append(f"fragment key {key!r}: witness pointer "
                            f"{w_tuple!r} outside {caldir}/witnesses/")
            continue
        entry = _verify_witness(wdir, w_tuple[2], refusals)
        if entry is None:
            continue
        entry["witness"] = tuple(w_tuple)
        new_entries[ck] = entry
    if refusals:
        return {"verdict": "REFUSE", "refusals": refusals, "count": 0}

    table = {k: dict(v) for k, v in current.items()
             if v["witness"][0] != caldir}
    table.update(new_entries)
    rendered = _render(table)
    tree = ast.parse(gov_source.read_text(encoding="utf-8"))
    node = next(n for n in tree.body
                if isinstance(n, ast.Assign) and len(n.targets) == 1
                and getattr(n.targets[0], "id", None) == TABLE)
    lines = gov_source.read_text(encoding="utf-8").splitlines(keepends=True)
    start, end = node.lineno - 1, node.end_lineno          # 1-based -> slice
    rebuilt = "".join(lines[:start]) + rendered + "\n" + "".join(lines[end:])
    if rebuilt != gov_source.read_text(encoding="utf-8"):
        gov_source.write_text(rebuilt, encoding="utf-8")   # atomic-enough:
        # verified BEFORE the first byte moved
    return {"verdict": "REGISTERED", "refusals": [], "count": len(new_entries)}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dir", required=True,
                    help="calibration dir name under --results")
    ap.add_argument("--results", type=Path, default=HERE.parent / "results")
    ap.add_argument("--gov", type=Path,
                    default=HERE / "tools" / "matrix_governance.py")
    args = ap.parse_args(argv)
    res = register(gov_source=args.gov, results_dir=args.results,
                   caldir=args.dir)
    print(json.dumps(res, indent=1))
    return 0 if res["verdict"] == "REGISTERED" else 4


if __name__ == "__main__":
    raise SystemExit(main())
