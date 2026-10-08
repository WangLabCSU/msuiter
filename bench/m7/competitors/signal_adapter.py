"""Signal (Bioconductor) — pending-verify refuse-to-run stub (memo §2c).

The registry probe on 2026-10-08 could not resolve this package on the
network available to this harness (CRAN index, Bioconductor 3.22 index,
gh api, gh search all negative). Selection is kept per the PI brief, but
**execution is refused unconditionally** until the PI supplies authoritative
package/version/image coordinates: this adapter raises
``AdapterUnavailable`` on every invocation, with or without Docker present,
whatever the registry says — a pending-verify provenance must be seen, not
scored.

Zero invented provenance: no digest, no repository URL, no version is
fabricated to make the stub look ready. The sign-eR identification idea
for the brief's "Signal (R/Bioconductor)" is recorded in memo §10.2
explicitly as HYPOTHESIS / UNVERIFIED, for PI-side verification before any
activation.
"""

from __future__ import annotations

from pathlib import Path

from .errors import AdapterUnavailable
from . import registry

REFUSAL = "pending-verify: PI coordinates required"


def run(cell: dict, spec=None, catalog_mount: Path | str | None = None) -> dict:
    """Unconditional refusal (memo §2c): the exact package coordinates must
    come from the PI before this adapter may execute anything."""
    spec = spec if spec is not None else registry.lookup("signal")
    raise AdapterUnavailable(f"signal: {REFUSAL} — {spec.pending_reason}")
