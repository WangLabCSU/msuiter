#!/usr/bin/env python3
"""SS3 roster flip: image_digest data edits sourced ONLY from inspect bytes.

The SS3 law: a digest arrives via `docker image inspect` and nothing else --
tools/p6_build_arms.py captured those bytes into each arm's build log as an
[ATTESTED] line at build success. This tool PARSES those lines and writes the
``"image_digest": "..."`` key into the roster spec, anchored on the face line
(each edit asserts a unique anchor). There is no code path by which a
hand-typed 71-char digest reaches the roster: pass --tool without a finished
build and it refuses; an image_digest string that is not 7+64 hex is refused.

After the edit it re-runs the roster group's mirror units via the same
in-process collector the suite uses -- the flip is admissible only in a
GREEN echo (the byte-compare against the emitter is the anti-transcription
tripwire).

Usage:
  python3 tools/p6_flip_roster.py --scratch /tmp/p6build            # all built
  python3 tools/p6_flip_roster.py --scratch /tmp/p6build --dry-run
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from competitors import p6_arms                      # noqa: E402

ROSTER = HERE / "competitors" / "p6_arms.py"
ATTEST_RE = re.compile(r"\[ATTESTED\] (\{.*\})\s*$", re.MULTILINE)
DIGEST_OK = re.compile(r"^sha256:[0-9a-f]{64}$")


def attested(scratch: Path) -> dict[str, dict]:
    """tool -> attested block, from the build logs' inspect lines."""
    out: dict[str, dict] = {}
    for log in sorted(scratch.glob("*.build.log")):
        latest = None
        for m in ATTEST_RE.finditer(log.read_text(encoding="utf-8")):
            latest = json.loads(m.group(1))          # last block wins (reruns)
        if latest is None:
            continue
        if "tool" not in latest:
            if "instrument" in latest:
                continue                     # the yardstick attestation:
                # delivery evidence sharing the scratch, never roster data
            sys.stderr.write(f"[FATAL] {log.name}: [ATTESTED] block names "
                             "neither tool nor instrument\n")
            raise SystemExit(2)
        if not DIGEST_OK.match(latest.get("image_digest", "")):
            sys.stderr.write(f"[FATAL] {log.name}: image_digest is not "
                             f"sha256+64hex: {latest.get('image_digest')!r}\n")
            raise SystemExit(2)
        out[latest["tool"]] = latest
    return out


def flip(blocks: dict[str, dict], *, dry: bool) -> int:
    text = ROSTER.read_text(encoding="utf-8")
    changed = 0
    for tool, blk in sorted(blocks.items()):
        if tool not in p6_arms.P6_ARM_SPECS:
            sys.stderr.write(f"[FATAL] attested tool {tool} is not in the roster\n")
            return 2
        # Anchor: the face line inside THIS spec block (spec blocks are short
        # and delimited by the next key; the tool key line makes it unique).
        spec = p6_arms.P6_ARM_SPECS[tool]
        anchor = (f'        "version": "{spec["version"]}", '
                  f'"face": "{spec["face"]}",\n')
        seg_start = text.index(f'    "{tool}": {{')
        seg_end = text.index("\n    }", seg_start)
        seg = text[seg_start:seg_end]
        if '"image_digest"' in seg:
            have = re.search(r'"image_digest": "([^"]+)"', seg).group(1)
            if have == blk["image_digest"]:
                print(f"OK    {tool} already flipped to {have[:18]}...")
                continue
            sys.stderr.write(f"[FATAL] {tool}: roster carries {have!r}, the "
                             f"build log attests {blk['image_digest']!r} -- "
                             f"refusing to guess which is real\n")
            return 2
        assert seg.count(anchor) == 1, f"{tool}: face-line anchor matched twice"
        seg_new = seg.replace(anchor, anchor +
                              f'        "image_digest": "{blk["image_digest"]}",\n')
        text = text[:seg_start] + seg_new + text[seg_end:]
        changed += 1
        print(f"FLIP  {tool} <- {blk['image_digest']} (image {blk['image_ref']})")
    if dry:
        print("(dry run -- nothing written)")
        return 0
    if changed:
        ROSTER.write_text(text, encoding="utf-8")
        print(f"[wrote] roster: {changed} image_digest keys added")
    return 0


def verify_green() -> int:
    """The roster mirror units must echo GREEN over the flipped bytes. The
    house collector is vars()/test_-prefixed (run_all takes no argv), so the
    module runs in-process exactly the way the suite's dispatcher does."""
    import importlib.util as u
    importlib.invalidate_caches()
    spec = u.spec_from_file_location("tests.test_p6_roster",
                                     str(HERE / "tests" / "test_p6_roster.py"))
    mod = u.module_from_spec(spec)
    spec.loader.exec_module(mod)
    fails = 0
    for name, fn in sorted(vars(mod).items()):
        if not name.startswith("test_") or not callable(fn):
            continue
        try:
            fn()
            print(f"  PASS {name}")
        except Exception as exc:
            fails += 1
            print(f"  FAIL {name}: {exc}")
    print(f"[verify] tests.test_p6_roster fails={fails}")
    return 1 if fails else 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--scratch", type=Path, default=Path("/tmp/p6build"))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--skip-verify", action="store_true",
                    help="dev aid; the committed flip always verifies")
    args = ap.parse_args(argv)
    blocks = attested(args.scratch)
    if not blocks:
        sys.stderr.write(f"[FATAL] no [ATTESTED] inspect lines under "
                         f"{args.scratch} -- nothing to flip\n")
        return 2
    missing = sorted(set(p6_arms.P6_ARM_SPECS) - set(blocks))
    if missing and not args.dry_run:
        sys.stderr.write(f"[NOTE] not yet attested: {missing} "
                         f"(partial flips are legal; each row gates its own "
                         f"compose-time refusal until flipped)\n")
    rc = flip(blocks, dry=args.dry_run)
    if rc or args.dry_run:
        return rc
    if args.skip_verify:
        return 0
    return verify_green()


if __name__ == "__main__":
    raise SystemExit(main())
