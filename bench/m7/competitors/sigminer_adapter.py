"""SigMiner 2.3.1 container adapter (memo §2a/§6).

Pure-adapter contract (memo §3): the harness writes ``counts.csv /
catalog.csv / params.json`` into the cell's ``in/``, the container mounts it
read-only, and the parsed ``intervals.csv`` long table is the only thing
that flows back. SigMiner runs at its package documented defaults — this
slice records **zero** parameter overrides; the only lever touched is the
extraction entry point's documented ``seed`` parameter (the package's own
docstring: "a random seed to make reproducible result"), forwarded verbatim
from ``params.json`` (slice-3 memo §9d: the pre-slice claim of a package-
documented seed entry point was fiction — the witnessed 2.3.1 NAMESPACE
carries that name 0 times; the runner call sites are pinned against the
witnessed export fixture by test_sigminer_api_contract).

Skip-not-skip (memo §6): an absent image or an uncaptured digest raises
``AdapterUnavailable`` with the reason — never a generic crash, never a
zero-execution "success".
"""

from __future__ import annotations

from pathlib import Path

from . import docker_cmd
from .errors import AdapterUnavailable


def _child_argv(catalog_mount: Path | str | None) -> list[str]:
    """SigMiner's real command inside the container (launched by the shared
    m7_entry measurement wrapper)."""
    catalog_dest = ("/work/catalog.csv" if catalog_mount is not None
                    else "/work/in/catalog.csv")
    return ["Rscript", "/work/run_sigminer.R",
            "--counts", "/work/in/counts.csv",
            "--catalog", catalog_dest,
            "--params", "/work/in/params.json",
            "--outdir", "/work/out"]


def run(cell: dict, spec, catalog_mount: Path | str | None = None) -> dict:
    """Execute one SigMiner cell. ``cell`` carries ``in_dir``/``out_dir``
    per the §1/§6 mount contract; returns the sidecar-backed summary."""
    reason = docker_cmd.image_gate(spec)
    if reason is not None:
        raise AdapterUnavailable(
            f"sigminer: {reason} — skip-not-skip (memo §5 ii/§6)")
    return docker_cmd.run_container_cell(
        spec=spec, in_dir=Path(cell["in_dir"]), out_dir=Path(cell["out_dir"]),
        child_argv=_child_argv(catalog_mount), catalog_mount=catalog_mount)
