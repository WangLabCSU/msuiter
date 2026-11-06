"""sigminer_post_v3_rust_batch container adapter (R1-PARITY Phase-B arm).

P0-P3 tip, batch-bridge transport face (parity-measurement face)

Thin shim over competitors/_p6_common.py, shaped exactly like its six siblings:
the measurement contract (four-file cell protocol, frozen thread caps, zero
parameter overrides, skip-not-skip) is the shared engine's, and this module
only pins WHICH arm the child argv names. What makes this arm a face of its
own is the single --backend token the engine places -- "rust_batch" -- which
the arm's own runner fork forwards to the seam as the documented third
extraction value, where it routes one (rank, bootstrap) unit's fits through
the audited batch bridge (one protocol handshake plus one
``msuiter-kernel fit-kl --cases`` invocation) instead of one process spawn per
fit. Same certified binary family, same frozen geometry, same seed law: the
delta is transport, and the arm rides its own witnessed tree, its own forked
cell-surface bytes, its own image and its own 21 floor anchors.
"""

from __future__ import annotations

from pathlib import Path as _Path

from . import _p6_common
from .errors import AdapterUnavailable                    # noqa: F401 (contract)

TOOL = "sigminer_post_v3_rust_batch"
FACE = "rust_batch"


def _child_argv(catalog_mount=None) -> list[str]:
    return _p6_common.child_argv(TOOL, catalog_mount)


def run(cell: dict, spec, catalog_mount: _Path | str | None = None) -> dict:
    """One sigminer_post_v3_rust_batch cell: gate, compose, exec; sidecar-backed summary back."""
    return _p6_common.run(TOOL, cell, spec, catalog_mount)
