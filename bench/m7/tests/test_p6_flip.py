#!/usr/bin/env python3
"""Group (AF) test_p6_flip -- the roster flip's parser and editor, sealed.

SS3 makes the flip the single code path by which a digest reaches the roster,
so its segment logic must be covered mechanically, not trusted from one
live run. The units drive tools/p6_flip_roster.py against a TEMPORARY copy
of the committed roster bytes (mod.ROSTER is redirected), so the real roster
is never touched and no docker is needed: the attested blocks are synthetic
fixture bytes derived via hashlib (test scaffolding, not a measurement --
no committed file ever sees them).

Death record: the first live dry-run aborted in flip() with "substring not
found" -- the segment terminator was spelled "\n    }}" (a doubled brace
left over from an f-string idiom) while the roster closes each block with a
single brace. These units keep that class of defect lit.
"""

from __future__ import annotations

import hashlib
import importlib.util as importlib_util
import json
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

_TOOLS = HERE / "tools"


def _load_flip():
    spec = importlib_util.spec_from_file_location(
        "p6_flip_roster_under_test", str(_TOOLS / "p6_flip_roster.py"))
    mod = importlib_util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _fixture_digest(label: str) -> str:
    """Synthetic 71-char digest bytes for scaffolding (never a claim)."""
    return "sha256:" + hashlib.sha256(("p6-flip-test/" + label).encode()
                                       ).hexdigest()


def _block(tool: str) -> dict:
    return {"face": "fixture", "tool": tool,
            "image_digest": _fixture_digest(tool),
            "image_ref": f"msuiter-sigminer:p6-{tool}-r1",
            "tree_sha": "0" * 40, "msuiter_source_sha": None}


def _temp_roster(tmp: Path) -> tuple[object, Path]:
    """An isolated copy of the committed roster bytes, redirected in-module."""
    mod = _load_flip()
    dst = tmp / "p6_arms_copy.py"
    shutil.copy2(mod.ROSTER, dst)
    mod.ROSTER = dst
    return mod, dst


def test_attested_parses_last_block_and_demands_wellformed_digests():
    """attested(): last [ATTESTED] wins (reruns), malformed digest is fatal."""
    mod = _load_flip()
    with tempfile.TemporaryDirectory() as td:
        scratch = Path(td)
        good = _block("sigminer_post_p1")
        stale = dict(good, image_digest=_fixture_digest("stale"))
        (scratch / "sigminer_post_p1.build.log").write_text(
            "# log\n"
            f"[ATTESTED] {json.dumps(stale, sort_keys=True)}\n"
            "churn text\n"
            f"[ATTESTED] {json.dumps(good, sort_keys=True)}\n",
            encoding="utf-8")
        (scratch / "sigminer_post_v3_rust.build.log").write_text(
            f"[ATTESTED] {json.dumps(_block('sigminer_post_v3_rust'), sort_keys=True)}\n",
            encoding="utf-8")
        out = mod.attested(scratch)
        assert set(out) == {"sigminer_post_p1", "sigminer_post_v3_rust"}, out
        assert out["sigminer_post_p1"]["image_digest"] == good["image_digest"], \
            "last [ATTESTED] block must win"
        (scratch / "sigminer_pre_v3.build.log").write_text(
            '[ATTESTED] {"tool": "sigminer_pre_v3", "image_digest": "sha256:tooshort"}\n',
            encoding="utf-8")
        try:
            mod.attested(scratch)
        except SystemExit as exc:
            assert exc.code == 2, exc.code
        else:
            raise Assertionerror("malformed image_digest must be refused")


def test_flip_dry_run_survives_the_committed_roster_shape():
    """RED witness: flip() must locate the block terminator on real bytes."""
    with tempfile.TemporaryDirectory() as td:
        mod, _dst = _temp_roster(Path(td))
        blocks = {t: _block(t) for t in
                  ("sigminer_post_p1", "sigminer_post_v3_rust")}
        rc = mod.flip(blocks, dry=True)
        assert rc == 0, rc


def test_flip_dry_run_writes_nothing():
    """A dry run leaves the roster bytes bit-identical."""
    with tempfile.TemporaryDirectory() as td:
        mod, dst = _temp_roster(Path(td))
        before = dst.read_bytes()
        blocks = {t: _block(t) for t in
                  ("sigminer_post_p1", "sigminer_post_v3_rust")}
        rc = mod.flip(blocks, dry=True)
        assert rc == 0, rc
        assert dst.read_bytes() == before, "dry run mutated the roster"


def test_flip_inserts_digest_directly_under_the_face_line():
    """The edit lands the digest line immediately after the face anchor,
    with the exact attested bytes, inside the right arm's block only."""
    with tempfile.TemporaryDirectory() as td:
        mod, dst = _temp_roster(Path(td))
        blocks = {t: _block(t) for t in
                  ("sigminer_post_p1", "sigminer_post_v3_rust")}
        rc = mod.flip(blocks, dry=False)
        assert rc == 0, rc
        text = dst.read_text(encoding="utf-8")
        for tool in blocks:
            seg = text[text.index(f'    "{tool}": {{'):
                      text.index("\n    }", text.index(f'    "{tool}": {{'))]
            lines = seg.splitlines()
            face_i = [i for i, ln in enumerate(lines) if '"face"' in ln]
            assert len(face_i) == 1, seg
            dig_i = [i for i, ln in enumerate(lines) if '"image_digest"' in ln]
            assert len(dig_i) == 1 and dig_i[0] == face_i[0] + 1, lines
            assert _block(tool)["image_digest"] in lines[dig_i[0]], lines[dig_i[0]]
        # untouched arms stay digest-free
        assert text.count('"image_digest"') == 2, text.count('"image_digest"')


def test_flip_is_idempotent_and_refuses_digest_conflict():
    """Same bytes again -> already-flipped rc 0; different bytes -> rc 2."""
    with tempfile.TemporaryDirectory() as td:
        mod, dst = _temp_roster(Path(td))
        blocks = {t: _block(t) for t in
                  ("sigminer_post_p1", "sigminer_post_v3_rust")}
        assert mod.flip(blocks, dry=False) == 0
        assert mod.flip(blocks, dry=False) == 0            # idempotent
        clash = {t: dict(b, image_digest=_fixture_digest("clash" + t))
                 for t, b in blocks.items()}
        assert mod.flip(clash, dry=False) == 2             # refuses to guess


if __name__ == "__main__":
    fails = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print(f"  PASS {name}")
            except Exception as exc:
                fails += 1
                print(f"  FAIL {name}: {type(exc).__name__}: {exc}")
    sys.exit(1 if fails else 0)
