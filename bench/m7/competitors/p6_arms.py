"""P6 arm roster — the seven pre-registered sigminer-v3 measurement arms as DATA.

Source of truth: the S1 pre-registration manifest
(/tmp/p6lane/logs/00-manifest-preregistration.md, SS1, banked before any image
build) and its echo in tests/test_p6_roster.py. Trees are the witnessed SHAs of
the sigminer lineage 196471a5 -> 1e174a04 -> 37fc92a8 -> a8b8825b (ancestry
attested by command in the trees attestation log 03b, 2026-10-15); the rust faces
share their R twin's tree byte-for-byte — one tree, two execution paths, which
is what makes the kernel-face ratio a kernel measurement and not a program
comparison. The seventh row (R1-PARITY Phase-B, controller ruling (ii)
2026-11-04) is the batch-bridge transport face: it descends from the rust tip's
witnessed tree by one documented seam commit and shares nothing but its lineage.

Registry rows for these keys are minted by competitors/registry.py from this
table; digests arrive only via the SS3 inspect ceremony (docker image inspect
captured directly, never transcribed), so until the flip every row is
pending-verify and compose-time refused.
"""

from __future__ import annotations

ARM_RUNNER = "run_sigminer_arm.R"          # /work sibling of the frozen runner
ARM_INSTALLER = "install_sigminer_arm.R"   # tree-rooted resolver sibling
ARM_IMAGE_PREFIX = "msuiter-sigminer"      # tags: <prefix>:p6-<key>-r<N>
# Per-arm cell-surface overrides. An arm that names neither key rides the two
# frozen shared bytes above (the six sealed rows do), so the shared engine's
# minted bytes never move; an arm that needs its own runner fork says so here
# and the Dockerfile byte-pins the fork beside the frozen originals.
ARM_SELF_WITNESS = "self_witness_arm.sh"   # /work build-time trust guard

# The face tokens, one spelling each. The documented two (.RUST_BACKENDS on
# the seam side) are the frozen public surface; the batch transport token is
# the third, admitted only on the bp surface and only by exact spelling.
FACE_R, FACE_RUST = "R", "rust"
FACE_RUST_BATCH = "rust_batch"

# The faces that cross the process boundary to the certified kernel. They
# differ only in how many kernel processes a unit pays -- one per fit for
# "rust", one per (rank, bootstrap) unit for "rust_batch" -- so every build-
# side "does this arm need the kernel strata" decision asks this one question
# and a face can not half-route. Mirrors the seam-side .RUST_ROUTE_FACES.
RUST_ROUTE_FACES = (FACE_RUST, FACE_RUST_BATCH)


def rides_kernel(spec: dict) -> bool:
    """True when one arm's face crosses to the certified kernel, and so needs
    the msuiter R layer plus the built kernel binary in its image."""
    return spec["face"] in RUST_ROUTE_FACES


def runner_script(spec: dict) -> str:
    """The cell-runner script one arm rides: its own fork when the roster
    names one, the shared frozen original otherwise. The default-preserving
    read that keeps the six sealed rows' minted bytes untouched."""
    return spec.get("runner_script") or ARM_RUNNER


def self_witness(spec: dict) -> str:
    """The build-time trust guard one arm rides, with the same law as
    runner_script(): a fork when the roster names one, the frozen shared
    witness otherwise."""
    return spec.get("self_witness") or ARM_SELF_WITNESS

P6_ARM_SPECS: dict[str, dict[str, str]] = {
    "sigminer_pre_v3": {
        "tree_sha": "196471a57000ff8a160400ebfc984f6ab0ea23e4",
        "ns_sha256": "37744aee7eb63c89501109f50da4b5a7155d4912bc5540cda8764062866a90df",
        "version": "2.3.3", "face": "R",
        "image_digest": "sha256:d48cb7fa658f91adda79aad9c7cb0c0dfe0e21eea675aae1ff35a4a97740ebe2",
        "role": "pre-phase baseline (CRAN 2.3.3 ground truth, #479 era)",
    },
    "sigminer_post_p1": {
        "tree_sha": "1e174a044e1eb4288b73a664b1179c98b104d28c",
        "ns_sha256": "37744aee7eb63c89501109f50da4b5a7155d4912bc5540cda8764062866a90df",
        "version": "2.3.3", "face": "R",
        "image_digest": "sha256:afe80a1f34ce4423a99ced84c4a67e9f85ca01261fb8dd84d998350d04aefa4f",
        "role": "kernel-boundary phase on the R path (#482)",
    },
    "sigminer_post_p1_rust": {
        "tree_sha": "1e174a044e1eb4288b73a664b1179c98b104d28c",
        "ns_sha256": "37744aee7eb63c89501109f50da4b5a7155d4912bc5540cda8764062866a90df",
        "version": "2.3.3", "face": "rust",
        "image_digest": "sha256:bc1fb04da8243297de5099353a918064da21c5602b7df55dacea1be7d267394e",
        "revision": 2,
        "role": "certified-kernel share of the kernel boundary",
    },
    "sigminer_post_p2": {
        "tree_sha": "37fc92a872720f947b5e2ac92d7de0fb96f2b092",
        "ns_sha256": "7d72444f8498635fb3e92b4bc3c29146c2c26b08577567417973832ffc68fea1",
        "version": "2.3.3", "face": "R",
        "image_digest": "sha256:65ebb01644048991433e052f0b98d25211426bb046db4590f69b3e3cf0e521c2",
        "role": "K-arbitration port",
    },
    "sigminer_post_v3": {
        "tree_sha": "a8b8825be0c0768580c85b7e749b7b9088d8d9d7",
        "ns_sha256": "7d72444f8498635fb3e92b4bc3c29146c2c26b08577567417973832ffc68fea1",
        "version": "2.3.3", "face": "R",
        "image_digest": "sha256:44707680ae2bde77df9d4d8ef8f2633e42eecce870f21942606d6d1b49f00e75",
        "role": "P0-P3 tip, R path (release candidate face)",
    },
    "sigminer_post_v3_rust": {
        "tree_sha": "a8b8825be0c0768580c85b7e749b7b9088d8d9d7",
        "ns_sha256": "7d72444f8498635fb3e92b4bc3c29146c2c26b08577567417973832ffc68fea1",
        "version": "2.3.3", "face": "rust",
        "image_digest": "sha256:de5e07eb4772b7e2458dc5a6d238dc919610d63fe1b3a253e98851747c05e937",
        "revision": 2,
        "role": "P0-P3 tip, certified-kernel face (parity-gate face)",
    },
    # R1-PARITY Phase-B (lane card /tmp/r1lane/DESIGN.md, controller ruling
    # (ii) 2026-11-04): the seventh pre-registered arm. Its single delta from
    # the rust twin above is the TRANSPORT the 4000 certified fits arrive by --
    # the batch bridge (one handshake plus one `fit-kl --cases` invocation per
    # (rank, bootstrap) unit) instead of one process spawn per fit. Same
    # certified binary family, same frozen 20x50x4 geometry, same seed law.
    # It rides its OWN witnessed tree (a documented descendant of the rust
    # twin's, adding the seam-side batch token), its OWN runner fork, its OWN
    # self-witness fork, its OWN image tag, and zero bytes of anything above.
    "sigminer_post_v3_rust_batch": {
        "tree_sha": "15b827981dd1a4be28207eb084f78140b70f8f09",
        "ns_sha256": "7d72444f8498635fb3e92b4bc3c29146c2c26b08577567417973832ffc68fea1",
        "version": "2.3.3", "face": "rust_batch",
        "image_digest": "sha256:dd8bc22acac18323c90c04514f6427ca09554ad71b0f6bd39e4fd2fd61975ee9",
        "runner_script": "run_sigminer_arm_batch.R",
        "self_witness": "self_witness_batch_arm.sh",
        "lineage_base": "sigminer_post_v3_rust",
        "role": "P0-P3 tip, batch-bridge transport face (parity-measurement face)",
    },
}


def image_tag(tool: str, revision: int = 1) -> str:
    """Deterministic build tag for one arm generation (digest flip binds the
    RepoDigest of exactly this tag)."""
    return f"{ARM_IMAGE_PREFIX}:p6-{tool}-r{revision}"
