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

from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
import sys
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from competitors import registry                     # noqa: E402  (RED seam)

EXPECTED_NAMES = {"sigminer", "sigprofiler", "signal"}
VALID_STATUSES = {"ready", "pending-verify"}


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
