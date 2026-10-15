"""Group (Y) test_p6_roster — the P6 arm roster is registry DATA, not folklore.

Pre-registration law (lane manifest /tmp/p6lane/logs/00-manifest-preregistration.md,
SS1/SS3): the six new sigminer-arm registry keys, their frozen 40-hex tree SHAs,
their version pins and their backend face were banked BEFORE any image build; this
unit is the mechanical echo of that bank. A drift between the frozen roster here
and competitors.p6_arms is a broken promise to the pre-registration, not a typo
to be fixed forward: the test quotes the SHAs, the module must match.

RED-by-absence: competitors.p6_arms does not exist yet in this batch; the import
failure is the witnessed RED, and the same module is what competitors/registry.py
consumes to mint the six rows (SS1: digests arrive only via the SS3 inspect
ceremony, so until the flip every P6 row is pending-verify and compose-time
refused by the image gate).
"""

from __future__ import annotations

import dataclasses
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from competitors import docker_cmd, registry        # noqa: E402  (RED seam: p6_arms)
from competitors import p6_arms                     # noqa: E402  (RED-by-absence)

# The frozen roster, quoted verbatim from the pre-registration manifest SS1.
FROZEN_TREES = {
    "sigminer_pre_v3":       "196471a54d0f78a1a12f4f4a027082746524b565",
    "sigminer_post_p1":      "1e174a044e1eb4288b73a664b1179c98b104d28c",
    "sigminer_post_p1_rust": "1e174a044e1eb4288b73a664b1179c98b104d28c",
    "sigminer_post_p2":      "37fc92a872720f947b5e2ac92d7de0fb96f2b092",
    "sigminer_post_v3":      "a8b8825be0c0768580c85b7e749b7b9088d8d9d7",
    "sigminer_post_v3_rust": "a8b8825be0c0768580c85b7e749b7b9088d8d9d7",
}
FROZEN_VERSIONS = {
    "sigminer_pre_v3": "2.3.3", "sigminer_post_p1": "2.3.3",
    "sigminer_post_p1_rust": "2.3.3", "sigminer_post_p2": "2.3.3",
    "sigminer_post_v3": "2.3.3", "sigminer_post_v3_rust": "2.3.3",
}
FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^sha256:[0-9a-f]{64}$")


def test_roster_is_exactly_the_six_frozen_keys():
    assert set(p6_arms.P6_ARM_SPECS) == set(FROZEN_TREES), (
        f"P6 roster keys drifted from the pre-registration: "
        f"{set(p6_arms.P6_ARM_SPECS) ^ set(FROZEN_TREES)}")


def test_roster_tree_shas_are_the_banked_full_40hex():
    for name, spec in p6_arms.P6_ARM_SPECS.items():
        sha = spec["tree_sha"]
        assert FULL_SHA.match(sha), f"{name}: tree_sha not a full 40-hex: {sha!r}"
        assert sha == FROZEN_TREES[name], (
            f"{name}: tree {sha} is not the pre-registered "
            f"{FROZEN_TREES[name]} — a re-pin needs its own dated manifest amendment")
        assert spec["version"] == FROZEN_VERSIONS[name], f"{name}: version pin drift"


def test_face_convention_rust_twins_share_their_tree():
    for base in ("sigminer_post_p1", "sigminer_post_v3"):
        rust = f"{base}_rust"
        assert p6_arms.P6_ARM_SPECS[base]["face"] == "R", base
        assert p6_arms.P6_ARM_SPECS[rust]["face"] == "rust", rust
        assert (p6_arms.P6_ARM_SPECS[base]["tree_sha"]
                == p6_arms.P6_ARM_SPECS[rust]["tree_sha"]), (
            f"{rust}: the rust face must be the SAME tree as its R twin — one "
            f"tree, two backends, or the comparison is a different program")
    for single in ("sigminer_pre_v3", "sigminer_post_p2"):
        assert p6_arms.P6_ARM_SPECS[single]["face"] == "R", single


def test_registry_carries_every_p6_row_pre_flip_safe():
    reg = registry.load()
    for name, spec in p6_arms.P6_ARM_SPECS.items():
        assert name in reg, f"registry lacks the pre-registered arm {name}"
        row = reg[name]
        assert row.status in ("pending-verify", "ready"), f"{name}: {row.status}"
        assert row.version == FROZEN_VERSIONS[name], f"{name}: row version drift"
        assert row.tree_sha == FROZEN_TREES[name], (
            f"{name}: row tree_sha does not echo the frozen tree")
        assert row.face == spec["face"], f"{name}: face column does not echo the roster"
        if row.status == "ready":
            assert HEX64.match(row.image_digest or ""), (
                f"{name}: a READY row must carry an inspect-attested 71-char digest, "
                f"got {row.image_digest!r}")
        else:
            reason = docker_cmd.image_gate(row)
            assert reason is not None, (
                f"{name}: a pending-verify row must be compose-time refused")
            assert "PENDING-VERIFY" in reason or "provenance" in reason, (
                f"{name}: unexpected refusal reason {reason!r}")


def test_p6_flip_is_pairwise_and_never_face_laundering():
    """The SS3 flip ceremony pairs each arm with its probe witness; the rust
    face may never borrow its R twin's image identity (the two faces measure
    different execution paths; the parity predicate reads them apart)."""
    reg = registry.load()
    p1, p1r = reg["sigminer_post_p1"], reg["sigminer_post_p1_rust"]
    v3, v3r = reg["sigminer_post_v3"], reg["sigminer_post_v3_rust"]
    for plain, rust in ((p1, p1r), (v3, v3r)):
        if plain.status == rust.status == "ready":
            assert plain.image_digest != rust.image_digest, (
                f"{rust.name}: shares the plain image — the rust face must "
                f"ride its own baked artifact (kernel bin + ENV pin)")
        # a PENDING row flipped READY with a malformed digest is refused
        bad = dataclasses.replace(rust, image_digest="sha256:" + "0" * 63)
        assert docker_cmd.image_gate(bad) is not None, (
            f"{rust.name}: malformed digest must be refused pre-daemon")


def test_legacy_rows_are_byte_stable_under_the_p6_batch():
    """The P6 additions must not disturb the two reference arms — their
    digests are the same bytes the slice-3 campaign attested (the re-measure
    rides the same images, zero-cached law notwithstanding)."""
    reg = registry.load()
    assert reg["sigminer"].image_digest == (
        "sha256:05cb29e0cfe881c3a0c7d1ec7c9058cfbbb9539f5d1c135787027e6002c703e9")
    assert reg["sigminer"].image_ref == "msuiter-sigminer:slice3-r5"
    assert reg["sigprofiler"].version == "v1.1.5"
