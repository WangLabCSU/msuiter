"""Auxilary Bioconductor competitor — container adapter (design memo §2c,
PI-confirmed identity ruling 2026-11-02; SIGNER-c lane promotion).

Position (PI hierarchy ruling): sigprofiler is THE primary comparison
target; this row and the sigminer row are AUXILIARY comparison objects.

Pure-adapter contract (memo §3): the harness writes ``counts.csv /
catalog.csv / params.json`` into the cell's ``in/`` (mounted read-only),
the container answers with the parsed long table plus the guard files;
nothing msuiter-internal crosses the boundary. The package runs at its
DOCUMENTED DEFAULTS: the call surface is the entry point with the mutation
matrix alone (the witnessed ``\\usage`` in the package's own Rd, probe03)
-- K is estimated by the algorithm at its documented default, the
opportunity matrix rides the documented uniform branch, and no tuning token
ever enters the argv (zero-invention law; an undocumented required lever
would make the row refuse, not the adapter improvise one).

The run is NON-SEEDABLE (the documented usage carries no seed argument) and
the runner records that in ``runner_notes.json`` — the row never asserts a
reproducibility the package does not document (memo §3).

Skip-not-skip (memo §6): an unverified pin or an absent image raises
``AdapterUnavailable`` with the reason via ``docker_cmd.image_gate`` --
never a generic crash, never a zero-execution "success".
"""

from __future__ import annotations

from pathlib import Path

from . import docker_cmd
from . import registry
from .errors import AdapterUnavailable


def _child_argv(catalog_mount: Path | str | None) -> list[str]:
    """The package's real command inside the container (launched by the
    shared m7_entry measurement wrapper). Documented defaults: the quad of
    the §1 mount contract and nothing else."""
    catalog_dest = ("/work/catalog.csv" if catalog_mount is not None
                    else "/work/in/catalog.csv")
    return ["Rscript", f"/work/{registry.lookup(registry.COMPETITOR_KEY).runner_script}",
            "--counts", "/work/in/counts.csv",
            "--catalog", catalog_dest,
            "--params", "/work/in/params.json",
            "--outdir", "/work/out"]


def run(cell: dict, spec=None, catalog_mount: Path | str | None = None) -> dict:
    """Execute one measured cell. ``spec`` defaults to the registry row;
    ``dataclasses.replace`` tamper copies are the test idiom and ride the
    same path (the gate consumes whatever spec it is handed)."""
    spec = spec if spec is not None else registry.lookup(registry.COMPETITOR_KEY)
    reason = docker_cmd.image_gate(spec)
    if reason is not None:
        raise AdapterUnavailable(
            f"{registry.COMPETITOR_KEY}: {reason} — skip-not-skip (memo §5 ii/§6)")
    return docker_cmd.run_container_cell(
        spec=spec, in_dir=Path(cell["in_dir"]), out_dir=Path(cell["out_dir"]),
        child_argv=_child_argv(catalog_mount), catalog_mount=catalog_mount)
