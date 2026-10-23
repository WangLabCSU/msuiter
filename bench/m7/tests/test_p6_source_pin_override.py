#!/usr/bin/env python3
"""Group (AJ) test_p6_source_pin_override -- the certified-kernel pin overlay.

tools/p6_build_arms.py carries MSUITER_SOURCE_SHA as the P6 reproducibility
witness: the committed default is frozen by value here, and a Phase-4 style
re-adjudication build may only ride a different kernel through an EXPLICIT
M7_MSUITER_SOURCE_SHA env overlay. The overlay is 40-hex validated at the
resolver (the A2 failure mode was a shaped mistranscription surviving a
format-only check, so value checks live here and the object probe lives
downstream); a shaped non-object then dies at the very cat-file gate the
default rides -- the overlay adds no trust gap: the same witnessed-object
discipline covers both routes.

RED-by-absence is the TDD state of this group: resolve_msuiter_source_sha /
attested_identity are introduced by the GREEN slice; the r-face and
cat-file units seal PRE-EXISTING gates so the new route is measured against
the old one.
"""

from __future__ import annotations

import contextlib
import hashlib
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from tools import p6_build_arms as mod             # noqa: E402
from competitors import p6_arms                     # noqa: E402

ENV_KEY = "M7_MSUITER_SOURCE_SHA"
# The P6 reproducibility witness, quoted verbatim (same pin-by-value idiom as
# tests/test_p6_roster.py::FROZEN_TREES -- a regex cannot catch a shaped typo).
DEFAULT_WITNESS = "dbef3a77dce3f7b2bb9405895c426dd6342167c6"
FULL_SHA = re.compile(r"^[0-9a-f]{40}$")


def _fixture_digest(label: str) -> str:
    """Synthetic 71-char digest bytes for scaffolding (never a claim)."""
    return "sha256:" + hashlib.sha256(("p4-pin-override/" + label).encode()
                                       ).hexdigest()


@contextlib.contextmanager
def _env_overlay(value):
    """Set (or, on value=None, clear) the overlay around one leg."""
    had = ENV_KEY in os.environ
    saved = os.environ.get(ENV_KEY)
    if value is None:
        os.environ.pop(ENV_KEY, None)
    else:
        os.environ[ENV_KEY] = value
    try:
        yield
    finally:
        if had:
            os.environ[ENV_KEY] = saved
        else:
            os.environ.pop(ENV_KEY, None)


@contextlib.contextmanager
def _spied_exports():
    """Behave-with-the-committed-bytes routing probe: replace _export_tree
    with a recorder of (repo, sha) so assemble()'s routing is WITNESSED, not
    inferred from a log text. The untouched original is restored on exit."""
    calls: list[tuple[Path, str]] = []
    original = mod._export_tree

    def _record(repo, sha, dest, log):
        calls.append((Path(repo), sha))
        Path(dest).mkdir(parents=True, exist_ok=True)

    mod._export_tree = _record
    try:
        yield calls
    finally:
        mod._export_tree = original


def _heads40() -> str:
    return subprocess.run(
        [mod.GIT_EXE, "-C", str(mod.MSUITER_SRC), "rev-parse", "HEAD"],
        capture_output=True, text=True).stdout.strip()


def test_default_pin_is_the_p6_replay_witness_verbatim():
    # Act + Assert: the committed constant and the env-absent resolver must
    # both answer the pre-registration witness, byte for byte.
    assert mod.MSUITER_SOURCE_SHA == DEFAULT_WITNESS, (
        "the committed default drifted from the P6 replay witness -- the "
        "default may never be replaced, only overlaid")
    with _env_overlay(None):
        assert mod.resolve_msuiter_source_sha() == DEFAULT_WITNESS


def test_env_overlay_overrides_the_default():
    # Arrange: a real, distinct witnessed object -- the msuiter repo's own head.
    head = _heads40()
    assert FULL_SHA.match(head) and head != DEFAULT_WITNESS, head
    # Act + Assert
    with _env_overlay(head):
        assert mod.resolve_msuiter_source_sha() == head, (
            "an explicit overlay must route the build to the new sha")


def test_rust_assemble_routes_the_export_to_the_override():
    # Arrange
    tool = "sigminer_post_v3_rust"
    override = "a" * 40
    # Act
    with _env_overlay(override), _spied_exports() as calls:
        with tempfile.TemporaryDirectory() as td:
            mod.assemble(tool, Path(td) / "scratch")
    # Assert: exactly two witnessed exports -- the sigminer tree from the
    # read-only GT, and the msuiter kernel at the OVERLAY sha, not the default.
    assert calls == [(mod.SIGMINER_GT,
                      p6_arms.P6_ARM_SPECS[tool]["tree_sha"]),
                     (mod.MSUITER_SRC, override)], calls


def test_r_face_assemble_exports_no_msuiter_tree():
    """The re-adjudication premise the P4 build ceremony must not violate:
    an R-face arm carries no kernel bytes -- the msuiter dir is created
    inert and never exported into."""
    # Arrange
    tool = "sigminer_post_p1"
    # Act (assertions ride inside the scratch's lifetime)
    with _env_overlay("a" * 40), _spied_exports() as calls:
        with tempfile.TemporaryDirectory() as td:
            ctx, _log = mod.assemble(tool, Path(td) / "scratch")
            inert = ctx / "msuiter"
            assert inert.is_dir(), f"R-face inert msuiter dir absent under {ctx}"
            assert not any(inert.iterdir()), \
                f"R-face inert msuiter dir must be empty: {sorted(inert.iterdir())}"
        assert calls == [(mod.SIGMINER_GT,
                          p6_arms.P6_ARM_SPECS[tool]["tree_sha"])], calls


def test_malformed_overrides_are_refused():
    bad = ["", "not-a-sha", "a" * 39, "A" * 40, "sha256:" + "b" * 64,
           "g" * 40]
    for value in bad:
        # Act
        with _env_overlay(value):
            refused = False
            try:
                mod.resolve_msuiter_source_sha()
            except SystemExit as exc:
                assert exc.code == 2, f"{value!r}: rc {exc.code} != 2"
                refused = True
            # Assert
            assert refused, f"malformed overlay {value!r} was accepted"


def test_assemble_dies_before_msuiter_export_on_malformed_override():
    """The refusal is a pre-flight death: the recorder must never see a
    kernel export at a malformed sha -- the overlay cannot smuggle a
    shaped-non-object past the resolver into the cat-file leg."""
    with _env_overlay("dead" + "gg" * 18), _spied_exports() as calls:
        died = False
        try:
            with tempfile.TemporaryDirectory() as td:
                mod.assemble("sigminer_post_p1_rust", Path(td) / "scratch")
        except SystemExit as exc:
            assert exc.code == 2, exc.code
            died = True
        # Assert
        assert died, "malformed overlay survived assemble()"
        assert all(repo != mod.MSUITER_SRC for repo, _sha in calls), calls


def test_shaped_non_object_override_dies_at_the_cat_file_gate():
    """The overlay inherits the witnessed-object gate verbatim: a validly
    shaped, non-existent 40-hex (the all-zero oid is no object in any repo)
    dies rc 2 before a single byte lands."""
    with tempfile.TemporaryDirectory() as td:
        dest = Path(td) / "out"
        log = Path(td) / "t.log"
        died = False
        try:
            mod._export_tree(mod.MSUITER_SRC, "0" * 40, dest, log)
        except SystemExit as exc:
            assert exc.code == 2, exc.code
            died = True
        # Assert
        assert died, "a shaped non-object must die at the cat-file -e gate"
        assert not dest.exists(), "a died export must leave no partial tree"


def test_real_object_override_exports_the_described_package():
    """End-to-end leg of the overlay route: a witnessed real object exports
    complete (DESCRIPTION + NAMESPACE probed) -- the same contract the
    default rides, now witnessed for a non-default sha."""
    head = _heads40()
    assert FULL_SHA.match(head) and head != DEFAULT_WITNESS, head
    with tempfile.TemporaryDirectory() as td:
        dest = Path(td) / "out"
        log = Path(td) / "t.log"
        mod._export_tree(mod.MSUITER_SRC, head, dest, log)
        for need in ("DESCRIPTION", "NAMESPACE"):
            assert (dest / need).is_file(), f"exported tree lacks {need}"


def test_attested_identity_names_the_sha_the_image_actually_carried():
    """SS3 attestation honesty: the [ATTESTED] block must speak the sha the
    build was routed to -- under the overlay the new sha, without it the
    witness default, and never a kernel claim on an R face."""
    digest = _fixture_digest("identity")
    rust = "sigminer_post_v3_rust"
    with _env_overlay(None):
        blk = mod.attested_identity(rust, digest)
        assert blk["msuiter_source_sha"] == DEFAULT_WITNESS, blk
    with _env_overlay("f" * 40):
        blk = mod.attested_identity(rust, digest)
        assert blk["msuiter_source_sha"] == "f" * 40, blk
    assert mod.attested_identity("sigminer_post_p1", digest)[
        "msuiter_source_sha"] is None
    blk = mod.attested_identity(rust, digest)
    assert blk["image_digest"] == digest
    assert blk["image_ref"].startswith(f"msuiter-sigminer:p6-{rust}-r"), blk
    assert blk["tree_sha"] == p6_arms.P6_ARM_SPECS[rust]["tree_sha"]


if __name__ == "__main__":
    fails = 0
    for _name, _fn in sorted(globals().items()):
        if _name.startswith("test_") and callable(_fn):
            try:
                _fn()
                print(f"  PASS {_name}")
            except Exception as _exc:
                fails += 1
                print(f"  FAIL {_name}: {type(_exc).__name__}: {_exc}")
    sys.exit(1 if fails else 0)
