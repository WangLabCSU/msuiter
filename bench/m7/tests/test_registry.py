"""① competitor registry load + pinned provenance (U-M7-02, design memo §2/§6).

Contract pinned here (implementation is the GREEN slice — RED-by-absence is
the expected state of this batch):

  competitors.registry.load()      -> {name: CompetitorSpec} for exactly
                                      {sigminer, sigprofiler, signal}
  CompetitorSpec.status            ∈ {"ready", "pending-verify"}
  registry.lookup(name)            -> spec; unknown name raises ValueError
                                      listing the available names (the
                                      zero-magic-string idiom of the engine
                                      registry, ARCH §3.4)
"""

from __future__ import annotations

import dataclasses
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
import sys
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from competitors import docker_cmd, registry                  # noqa: E402  (RED seam)

EXPECTED_NAMES = {"sigminer", "sigprofiler", "signal"}
VALID_STATUSES = {"ready", "pending-verify"}

# RB-05(6) flip witnesses 2026-10-09, data-only. The single authorized
# slice3-r5 bake: docker build exit 0 with the byte-pin assert, all three
# era-gated version gates and the network-none build self-witness green
# verbatim in the build log (rc 0, zero auto-install lines, NMF suggested
# 95.5). Controller ruling RB-05(6): registry flip only after the live
# docker image inspect + the GREEN cell-argv probe; both witness JSONs
# committed beside the pilot records (see the flip commit's --stat).
SIGMINER_IMAGE_REF = "msuiter-sigminer:slice3-r5"
SIGMINER_IMAGE_DIGEST = ("sha256:05cb29e0cfe881c3a0c7d1ec7c9058cfbbb9539f"
                         "5d1c135787027e6002c703e9")


def test_registry_loads_exactly_the_three_competitors():
    reg = registry.load()
    assert set(reg) == EXPECTED_NAMES, f"registry keys drifted: {set(reg)}"
    for name, spec in reg.items():
        assert spec.status in VALID_STATUSES, \
            f"{name}: illegal status {spec.status!r}"
        assert spec.name == name, f"{name}: spec.name mismatch"


def test_registry_provenance_pins_are_recorded():
    """§2 table: pins are data, not folklore — the registry carries them."""
    reg = registry.load()
    assert reg["sigminer"].version == "2.3.1", \
        f"sigminer pin drifted: {reg['sigminer'].version!r}"
    assert reg["sigprofiler"].version == "v1.1.5", \
        f"SigProfilerAssignment pin drifted: {reg['sigprofiler'].version!r}"
    # Image-backed entries must carry an explicit digest field; an uncaptured
    # digest reads PENDING-VERIFY (§5) — inventing one is prohibited.
    for name in ("sigminer", "sigprofiler"):
        digest = getattr(reg[name], "image_digest", None)
        assert isinstance(digest, str) and digest.strip(), \
            f"{name}: image_digest field missing/empty (use PENDING-VERIFY)"
    # The registry probe (§2c) could not resolve Signal in this network's
    # CRAN/Bioconductor indexes; until the PI supplies coordinates it must
    # be pending-verify, and it must say so rather than look ready.
    assert reg["signal"].status == "pending-verify"


def test_registry_lookup_unknown_name_lists_available():
    try:
        registry.lookup("sigmapro")
    except ValueError as e:
        msg = str(e)
        assert "sigminer" in msg and "sigprofiler" in msg and "signal" in msg, \
            f"error must list available names, got: {msg!r}"
    else:
        raise AssertionError("lookup() of an unknown name did not raise")


def test_sigminer_entry_carries_the_build9_verified_digest():
    """Data-only flip of the sentinel (charter 5 / memo §9c.1 ceremony): the
    sigminer row moves from PENDING-VERIFY to the live-inspect bytes, and
    image_ref to the very tag build9 was named to — image_gate probes and
    run_container_cell exec BOTH consume image_ref, so the pair is one and
    the same build artifact or the cell path re-opens the very gap the
    sentinel existed to hold shut (compose-time, daemon-free)."""
    spec = registry.load()["sigminer"]
    assert spec.image_digest == SIGMINER_IMAGE_DIGEST, (
        f"sigminer digest pin drifted from the build9 live-inspect capture: "
        f"{spec.image_digest!r}")
    assert spec.image_ref == SIGMINER_IMAGE_REF, (
        f"sigminer image_ref must name the built+tagged artifact (gate and "
        f"run consume this token): {spec.image_ref!r}")
    # Refuse-to-run semantics SURVIVE the flip: an entry lacking a verified
    # digest is refused at compose time — the provenance branch fires
    # before the daemon is consulted, so these checks are daemon-free.
    refused = dataclasses.replace(spec, image_digest=registry.PENDING_VERIFY)
    reason = docker_cmd.image_gate(refused)
    assert reason is not None and "PENDING-VERIFY" in reason, (
        "a PENDING-VERIFY digest must still be refused pre-daemon: "
        f"{reason!r}")
    malformed = dataclasses.replace(spec, image_digest="sha256:0" * 4)
    reason2 = docker_cmd.image_gate(malformed)
    assert reason2 is not None and "provenance not captured" in reason2, (
        "a malformed/mismatched-shape digest must still be refused "
        f"pre-daemon: {reason2!r}")
    # The unverified sibling keeps its sentinel state untouched by the flip.
    signal = registry.load()["signal"]
    assert signal.status == "pending-verify" and \
        docker_cmd.image_gate(signal) is not None, (
        "signal must remain pending-verify and compose-time refused")
