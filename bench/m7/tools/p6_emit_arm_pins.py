#!/usr/bin/env python3
"""Emit the committed arm identity pins (adapters/arm_pins/<tool>.json).

The arm runner's pin guard reads /work/arm_pin.json (COPYed by the Dockerfile
from this directory); these bytes must therefore equal the roster — the
single-source-of-truth check is tests/test_p6_roster.py
::test_arm_pin_files_mirror_the_roster, which re-derives every file from the
roster and byte-compares. Regenerate with this tool, never hand-edit: the
2026-10-15 A2 attestation (a mistranscribed tree SHA that survived a format-
only check) is the recorded failure mode this shape forecloses.

Usage:
  python3 tools/p6_emit_arm_pins.py          # write (idempotent)
  python3 tools/p6_emit_arm_pins.py --check  # verify, exit 1 on drift
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from competitors import p6_arms                      # noqa: E402

PINS_DIR = HERE / "adapters" / "arm_pins"


def pin_payload(tool: str) -> dict:
    spec = p6_arms.P6_ARM_SPECS[tool]
    return {"tool": tool, "face": spec["face"], "tree_sha": spec["tree_sha"],
            "expected_version": spec["version"], "ns_sha256": spec["ns_sha256"]}


def pin_text(tool: str) -> str:
    """House deterministic-JSON idiom (sort_keys, indent 1, trailing
    newline): byte-stable output so the mirror unit compares bytes."""
    return json.dumps(pin_payload(tool), sort_keys=True, indent=1) + "\n"


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    check = "--check" in argv
    drift = 0
    PINS_DIR.mkdir(parents=True, exist_ok=True)
    for tool in sorted(p6_arms.P6_ARM_SPECS):
        target = PINS_DIR / f"{tool}.json"
        want = pin_text(tool)
        have = target.read_text(encoding="utf-8") if target.exists() else None
        if have == want:
            print(f"OK    {target.name}")
            continue
        drift += 1
        if check:
            print(f"DRIFT {target.name} (re-run tools/p6_emit_arm_pins.py)")
        else:
            target.write_text(want, encoding="utf-8")
            print(f"WROTE {target.name}")
    if drift and check:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
