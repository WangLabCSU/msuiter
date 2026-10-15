"""P6 evidence machinery — the committed-table laws as executable code.

Three laws the campaign must survive before anything is filed (task card laws
2 and 5, manifest §6):

  zero-cached    the committed master is the shard UNION whose every row is a
                 first-measurement 'ok' row; a 'cached' replay may steer a
                 resume but may never enter the table. A class seen twice is a
                 death/replay trail event: first-wins, the duplicate REPORTED.
  hardware-pin   a row without host/hw_profile attests nothing (U-M7-04
                 full-table clause) — dropped with a reason code, never silent.
  digest-witness each cell's own manifest.json under the campaign cachedir
                 must record the image_digest the registry row for that tool
                 carries; a mismatch is a witness for a different image, i.e.
                 not a witness at all.

MEASURED-then-stated also binds the writer: write_result_md_text stamps
numbers ONLY from the adjudication records it is handed, the state vocabulary
is closed, and no prose constant can masquerade as a measurement (the RB-10
idiom — machine-written claim lines plus the verbatim disclosure layer).
"""

from __future__ import annotations

import json
from pathlib import Path

#: The frozen committed-table schema (the nine the reader-verifier knows).
MASTER_COLUMNS = ("cell", "tool", "arm", "n", "seconds", "status",
                  "cpu_seconds", "host", "hw_profile")

#: Closed vocabulary for result.md claim lines (MEASURED-then-stated).
ADJUDICATION_STATES = ("MEASURED", "PASS", "FAIL", "REFUSE",
                       "LEDGERED-PENDING", "PENDING")


def merge_shards(shards):
    """Ordered shard-union merge. Returns (accepted_rows, rejected) where
    every rejected entry is {"row", "why"} — the Skip Law's spoken language,
    auditable next to the table it kept out."""
    accepted: dict[str, dict] = {}
    rejected: list[dict] = []
    for shard in shards:
        for row in shard:
            cell = row["cell"]
            if row.get("status") != "ok":
                rejected.append({"row": row, "why": (
                    "zero-cached law: status "
                    f"{row.get('status')!r} is not a first measurement")})
                continue
            if not (row.get("host") or "").strip():
                rejected.append({"row": row, "why": (
                    "hardware-pin law: row carries no host stamp")})
                continue
            if not (row.get("hw_profile") or "").strip():
                rejected.append({"row": row, "why": (
                    "hardware-pin law: row carries no hw_profile stamp")})
                continue
            if cell in accepted:
                rejected.append({"row": row, "why": (
                    "duplicate cell across shards: first-wins, resume trail "
                    "must be read (death protocol), not overwritten")})
                continue
            accepted[cell] = row
    return list(accepted.values()), rejected


def verify_cell_provenance(cachedir, rows, specs):
    """One verdict per row: the cell's own manifest must echo the registry
    digest of the tool that supposedly produced it.

    specs: {tool: CompetitorSpec-or-None-ish}. REJECT reasons are diagnostic
    strings; the caller files them with the merge report (an unbacked row is a
    defect witness, never a dropped row)."""
    verdicts = []
    for row in rows:
        cell = row["cell"]
        tool = row["tool"]
        spec = specs.get(tool)
        if spec is None:
            verdicts.append({"cell": cell, "verdict": "REJECT",
                             "why": f"no registry spec supplied for {tool}"})
            continue
        manifest = Path(cachedir) / "cells" / cell / "out" / "manifest.json"
        if not manifest.exists():
            verdicts.append({"cell": cell, "verdict": "REJECT",
                             "why": f"cell manifest missing: {manifest}"})
            continue
        try:
            doc = json.loads(manifest.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            verdicts.append({"cell": cell, "verdict": "REJECT",
                             "why": f"cell manifest unreadable: {exc}"})
            continue
        seen = doc.get("image_digest")
        want = getattr(spec, "image_digest", None)
        if seen != want:
            verdicts.append({"cell": cell, "verdict": "REJECT",
                             "why": (f"image digest witness mismatch: cell "
                                     f"manifest saw {seen!r}, registry row "
                                     f"for {tool} is {want!r} — the cell was "
                                     f"not measured against this arm's image")})
            continue
        verdicts.append({"cell": cell, "verdict": "OK", "why": ""})
    return verdicts


def write_result_md_text(header, adjudications):
    """Deterministic machine-written result.md body. Every claim line is a
    pure function of one adjudication record; unknown states are a hard error
    (the closed vocabulary is what keeps prose from becoming data)."""
    lines = [f"# {header}", ""]
    for adj in adjudications:
        state = adj.get("state")
        if state not in ADJUDICATION_STATES:
            raise ValueError(f"undecodable adjudication state {state!r} for "
                             f"{adj.get('name')!r} — closed vocabulary is "
                             f"{ADJUDICATION_STATES}")
        lines.append(f"- **{adj['name']}**: {state} — {adj.get('detail', '')}")
    lines += ["",
              "Machine-written: every figure above is a value handed to the",
              "writer from campaign or calibration bytes; this file carries no",
              "hand-typed numbers.", ""]
    return "\n".join(lines)
