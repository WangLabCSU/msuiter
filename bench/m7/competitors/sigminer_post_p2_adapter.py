"""sigminer_post_p2 container adapter (P6 evidence loop, pre-registered arm).

K-arbitration port

Thin shim over competitors/_p6_common.py: the measurement contract (four-file
cell protocol, frozen thread caps, zero parameter overrides, skip-not-skip) is
the shared engine's; this module only pins WHICH arm the child argv names. The
--backend token it places is the sole face difference — the R face keeps the
legacy call chain, the rust face crosses to the certified kernel via the
tree's documented backend parameter (resolution option > MSUITER_KERNEL_BIN
env > PATH, validated by the build-time handshake in the image self-witness).
"""

from __future__ import annotations

from pathlib import Path as _Path

from . import _p6_common
from .errors import AdapterUnavailable                    # noqa: F401 (contract)

TOOL = "sigminer_post_p2"
FACE = "R"


def _child_argv(catalog_mount=None) -> list[str]:
    return _p6_common.child_argv(TOOL, catalog_mount)


def run(cell: dict, spec, catalog_mount: _Path | str | None = None) -> dict:
    """One sigminer_post_p2 cell: gate, compose, exec; sidecar-backed summary back."""
    return _p6_common.run(TOOL, cell, spec, catalog_mount)
