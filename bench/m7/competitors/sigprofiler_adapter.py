"""SigProfilerAssignment v1.1.5 container adapter (memo §2b/§6).

Assignment is executed through the tool's documented entry point
``Analyzer.cosmic_fit`` at its documented defaults — COSMIC v3.6 default
reference semantics, ``input_type="matrix"``, ``context_type="96"`` — and
this slice records **zero** parameter overrides (memo §3). The parsed
``intervals.csv`` long table is the single return surface.

Skip-not-skip (memo §6): an absent image or an uncaptured digest raises
``AdapterUnavailable`` with the reason.
"""

from __future__ import annotations

from pathlib import Path

from . import docker_cmd
from .errors import AdapterUnavailable


def _child_argv(catalog_mount: Path | str | None) -> list[str]:
    """SigProfilerAssignment's real command inside the container (launched
    by the shared m7_entry measurement wrapper)."""
    catalog_dest = ("/work/catalog.csv" if catalog_mount is not None
                    else "/work/in/catalog.csv")
    return ["python3", "/work/run_sigprofiler.py",
            "--counts", "/work/in/counts.csv",
            "--catalog", catalog_dest,
            "--params", "/work/in/params.json",
            "--outdir", "/work/out"]


def run(cell: dict, spec, catalog_mount: Path | str | None = None) -> dict:
    """Execute one SigProfilerAssignment cell. ``cell`` carries
    ``in_dir``/``out_dir`` per the §1/§6 mount contract."""
    reason = docker_cmd.image_gate(spec)
    if reason is not None:
        raise AdapterUnavailable(
            f"sigprofiler: {reason} — skip-not-skip (memo §5 ii/§6)")
    return docker_cmd.run_container_cell(
        spec=spec, in_dir=Path(cell["in_dir"]), out_dir=Path(cell["out_dir"]),
        child_argv=_child_argv(catalog_mount), catalog_mount=catalog_mount)
