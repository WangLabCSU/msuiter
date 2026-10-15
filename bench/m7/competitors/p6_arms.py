"""P6 arm roster — the six pre-registered sigminer-v3 measurement arms as DATA.

Source of truth: the S1 pre-registration manifest
(/tmp/p6lane/logs/00-manifest-preregistration.md, SS1, banked before any image
build) and its echo in tests/test_p6_roster.py. Trees are the witnessed SHAs of
the sigminer lineage 196471a5 -> 1e174a04 -> 37fc92a8 -> a8b8825b (ancestry
attested in the build log per the verify-by-command protocol); the rust faces
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
        "tree_sha": "196471a54d0f78a1a12f4f4a027082746524b565",
        "version": "2.3.3", "face": "R",
        "role": "pre-phase baseline (CRAN 2.3.3 ground truth, #479 era)",
    },
    "sigminer_post_p1": {
        "tree_sha": "1e174a044e1eb4288b73a664b1179c98b104d28c",
        "version": "2.3.3", "face": "R",
        "role": "kernel-boundary phase on the R path (#482)",
    },
    "sigminer_post_p1_rust": {
        "tree_sha": "1e174a044e1eb4288b73a664b1179c98b104d28c",
        "version": "2.3.3", "face": "rust",
        "role": "certified-kernel share of the kernel boundary",
    },
    "sigminer_post_p2": {
        "tree_sha": "37fc92a872720f947b5e2ac92d7de0fb96f2b092",
        "version": "2.3.3", "face": "R",
        "role": "K-arbitration port",
    },
    "sigminer_post_v3": {
        "tree_sha": "a8b8825be0c0768580c85b7e749b7b9088d8d9d7",
        "version": "2.3.3", "face": "R",
        "role": "P0-P3 tip, R path (release candidate face)",
    },
    "sigminer_post_v3_rust": {
        "tree_sha": "a8b8825be0c0768580c85b7e749b7b9088d8d9d7",
        "version": "2.3.3", "face": "rust",
        "role": "P0-P3 tip, certified-kernel face (parity-gate face)",
    },
}


def image_tag(tool: str, revision: int = 1) -> str:
    """Deterministic build tag for one arm generation (digest flip binds the
    RepoDigest of exactly this tag)."""
    return f"{ARM_IMAGE_PREFIX}:p6-{tool}-r{revision}"
