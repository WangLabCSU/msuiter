"""P6 arm roster — the six pre-registered sigminer-v3 measurement arms as DATA.

Source of truth: the S1 pre-registration manifest
(/tmp/p6lane/logs/00-manifest-preregistration.md, SS1, banked before any image
build) and its echo in tests/test_p6_roster.py. Trees are the witnessed SHAs of
the sigminer lineage 196471a5 -> 1e174a04 -> 37fc92a8 -> a8b8825b (ancestry
attested by command in the trees attestation log 03b, 2026-10-15); the rust faces
share their R twin's tree byte-for-byte — one tree, two execution paths, which
is what makes the kernel-face ratio a kernel measurement and not a program
comparison.

Registry rows for these keys are minted by competitors/registry.py from this
table; digests arrive only via the SS3 inspect ceremony (docker image inspect
captured directly, never transcribed), so until the flip every row is
pending-verify and compose-time refused.
"""

from __future__ import annotations

ARM_RUNNER = "run_sigminer_arm.R"          # /work sibling of the frozen runner
ARM_INSTALLER = "install_sigminer_arm.R"   # tree-rooted resolver sibling
ARM_IMAGE_PREFIX = "msuiter-sigminer"      # tags: <prefix>:p6-<key>-r<N>

P6_ARM_SPECS: dict[str, dict[str, str]] = {
    "sigminer_pre_v3": {
        "tree_sha": "196471a57000ff8a160400ebfc984f6ab0ea23e4",
        "ns_sha256": "37744aee7eb63c89501109f50da4b5a7155d4912bc5540cda8764062866a90df",
        "version": "2.3.3", "face": "R",
        "image_digest": "sha256:57d7381cee1e243959a070b42cccd045fba5152715adce7d13afd1dff20a1d3f",
        "role": "pre-phase baseline (CRAN 2.3.3 ground truth, #479 era)",
    },
    "sigminer_post_p1": {
        "tree_sha": "1e174a044e1eb4288b73a664b1179c98b104d28c",
        "ns_sha256": "37744aee7eb63c89501109f50da4b5a7155d4912bc5540cda8764062866a90df",
        "version": "2.3.3", "face": "R",
        "image_digest": "sha256:2e0ef8f6b74a14d8783a9fd03ac2878033cc93c2abb36f1ace927c76e49ef51c",
        "role": "kernel-boundary phase on the R path (#482)",
    },
    "sigminer_post_p1_rust": {
        "tree_sha": "1e174a044e1eb4288b73a664b1179c98b104d28c",
        "ns_sha256": "37744aee7eb63c89501109f50da4b5a7155d4912bc5540cda8764062866a90df",
        "version": "2.3.3", "face": "rust",
        "image_digest": "sha256:0959ace3f85a23dcd874e33dd76c3267ec1eb5cf9801dc952c9dcb33b4afefee",
        "revision": 2,
        "role": "certified-kernel share of the kernel boundary",
    },
    "sigminer_post_p2": {
        "tree_sha": "37fc92a872720f947b5e2ac92d7de0fb96f2b092",
        "ns_sha256": "7d72444f8498635fb3e92b4bc3c29146c2c26b08577567417973832ffc68fea1",
        "version": "2.3.3", "face": "R",
        "image_digest": "sha256:b85670ebf3ae8b969e3ab17d2f00f117b6adb0d8e0208ae0060df7ec92a5c0a9",
        "role": "K-arbitration port",
    },
    "sigminer_post_v3": {
        "tree_sha": "a8b8825be0c0768580c85b7e749b7b9088d8d9d7",
        "ns_sha256": "7d72444f8498635fb3e92b4bc3c29146c2c26b08577567417973832ffc68fea1",
        "version": "2.3.3", "face": "R",
        "image_digest": "sha256:d810e886d04ed18519840c734c721a20a7e40ca3fc9fa89fe30d12b2e284c8f7",
        "role": "P0-P3 tip, R path (release candidate face)",
    },
    "sigminer_post_v3_rust": {
        "tree_sha": "a8b8825be0c0768580c85b7e749b7b9088d8d9d7",
        "ns_sha256": "7d72444f8498635fb3e92b4bc3c29146c2c26b08577567417973832ffc68fea1",
        "version": "2.3.3", "face": "rust",
        "image_digest": "sha256:4afb3d8ae7e20bb8e1e45582fbb2503726b880466e22c3aedb7b10d81f187e0e",
        "revision": 2,
        "role": "P0-P3 tip, certified-kernel face (parity-gate face)",
    },
}


def image_tag(tool: str, revision: int = 1) -> str:
    """Deterministic build tag for one arm generation (digest flip binds the
    RepoDigest of exactly this tag)."""
    return f"{ARM_IMAGE_PREFIX}:p6-{tool}-r{revision}"
