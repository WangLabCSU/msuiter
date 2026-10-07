"""Competitor registry: selection, pinned provenance, lookup (design memo §2/§6).

Pins are data, not folklore: every entry carries the evidence of how the pin
was established (memo §2, probes run 2026-10-08) and an explicit
``PENDING-VERIFY`` wherever the digest could not be captured from
``docker image inspect``. **No digest is ever invented** — a field is only
filled by the verified-pull record of the GREEN dispatch (memo §5 rule ii).

Mirror policy (memo §5): container images are pulled only through the user's
mirror domains; both images here are harness-built from mirror-spelled
``FROM`` lines (see adapters/Dockerfile.*), so the image references are
local store tags. Any future registry-hosted reference must already be
mirror-spelled when it enters this table.
"""

from __future__ import annotations

from dataclasses import dataclass

PENDING_VERIFY = "PENDING-VERIFY"
STATUS_READY = "ready"
STATUS_PENDING_VERIFY = "pending-verify"


@dataclass(frozen=True)
class CompetitorSpec:
    """One pinned competitor row of the memo §2 table (immutable record).

    ``image_digest`` reads ``PENDING-VERIFY`` until captured from
    ``docker image inspect`` of a verified mirror-pulled image; adapters
    treat that value as not-ready (memo §5 rule ii).
    """

    name: str
    runtime: str                  # "R" | "python"
    version: str                  # pinned version, or "UNRESOLVED"
    image_ref: str                # local store tag (harness-built)
    image_digest: str             # "sha256:..." from docker image inspect
    status: str                   # "ready" | "pending-verify"
    entrypoint: str               # container interpreter for the cell runner
    runner_script: str            # script name mounted under /work in the image
    provenance: str               # memo §2 evidence record
    pending_reason: str = ""      # non-empty iff status == pending-verify


REGISTRY: dict[str, CompetitorSpec] = {
    "sigminer": CompetitorSpec(
        name="sigminer",
        runtime="R",
        version="2.3.1",
        image_ref="m7-sigminer:cr2.3.1",
        image_digest=PENDING_VERIFY,   # replaced only from docker image inspect
        status=STATUS_READY,
        entrypoint="python3",           # m7_entry.py measures the Rscript child
        runner_script="run_sigminer.R",
        provenance=(
            "CRAN 2.3.1; packageVersion('sigminer')=='2.3.1' in the host R "
            "library (2026-10-08); SBS96 label-aligned cross-validation "
            "against this copy already gates the package "
            "(tests/testthat/test-xval-sigminer.R); harness-built image from "
            "mirror-spelled rocker/r-ver base with build-time version assert "
            "(memo §2a)"),
    ),
    "sigprofiler": CompetitorSpec(
        name="sigprofiler",
        runtime="python",
        version="v1.1.5",
        image_ref="m7-sigprofiler:spa-1.1.5",
        image_digest="sha256:7dba2f43ad3a3858ed1cfdedd278c9c2f52a665fd4c18ac91a482b74258bfbed",  # docker image inspect .Id, 2026-10-08 verified build
        status=STATUS_READY,
        entrypoint="python3",
        runner_script="run_sigprofiler.py",
        provenance=(
            "gh api repos/SigProfilerSuite/SigProfilerAssignment releases/"
            "latest → tag v1.1.5 (published 2026-07-29T09:00:29Z); this "
            "network's PyPI index carries no distribution → pin provenance "
            "is the git tag (git ls-remote --tags → commit "
            "ff61b0f56d43c916582b7c505ce72364c883dfbd); container installs "
            "the tag through the GitHub API tarball endpoint "
            "(api.github.com/repos/.../tarball/refs/tags/v1.1.5) — the "
            "codeload archive family is dead on this network (404 from "
            "inside the build network), recorded in memo §9b (memo §2b)"),
    ),
    "signal": CompetitorSpec(
        name="signal",
        runtime="R",
        version="UNRESOLVED",
        image_ref="",
        image_digest="",
        status=STATUS_PENDING_VERIFY,
        entrypoint="",
        runner_script="",
        provenance=(
            "registry probes 2026-10-08: absent from the CRAN index and "
            "from the Bioconductor 3.22 index (BiocManager::repositories()); "
            "gh api repos/debruijn-lab/Signal → 404; GitHub search finds no "
            "canonical repo. Kept per the PI brief; refuses to run until the "
            "PI supplies package coordinates (memo §2c)"),
        pending_reason=(
            "pending-verify: PI coordinates required — package/version/image "
            "unresolved on this network (memo §2c; see the signeR "
            "hypothesis recorded in memo §10.2, HYPOTHESIS / UNVERIFIED)"),
    ),
}


def load() -> dict[str, CompetitorSpec]:
    """Registry snapshot for the orchestrator (shallow copy: callers may
    ``dataclasses.replace`` a row for a test cell, the table never mutates)."""
    return dict(REGISTRY)


def lookup(name: str) -> CompetitorSpec:
    """Resolve one competitor by name. Unknown names raise listing what is
    available — the zero-magic-string idiom of the engine registry
    (ARCHITECTURE §3.4)."""
    try:
        return REGISTRY[name]
    except KeyError:
        raise ValueError(
            f"unknown competitor {name!r} "
            f"(available: {', '.join(sorted(REGISTRY))})") from None
