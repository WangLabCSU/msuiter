"""Shared container-adapter engine for the six P6 sigminer-v3 arms.

One engine, six thin per-arm modules: the measurement contract is identical
across arms (same four-file cell protocol, same frozen thread caps injected by
docker_cmd before the image token, same zero parameter overrides — memo §2a).
The ONLY behavioural difference between an arm's two faces is the --backend
token placed after the runner script, forwarded verbatim from the roster data
(competitors.p6_arms); the R face keeps the legacy call chain byte-identical
(the token is carried in argv for witnessability, consumed only by the rust
face's documented backend selection).

Skip-not-skip (memo §6): an absent image or unattested digest raises
AdapterUnavailable with the reason — never a zero-execution "success".
"""

from __future__ import annotations

from pathlib import Path

from . import docker_cmd, p6_arms
from .errors import AdapterUnavailable


def child_argv(tool: str, catalog_mount: Path | str | None) -> list[str]:
    """The real cell command inside the container (launched by m7_entry.py).

    Mirrors the frozen run_sigminer.R contract — counts/params/outdir required,
    catalog protocol-carried (the de-novo cell does not consume it: reference
    matching is the scoring-side job, memo §4) — plus the backend passthrough
    the arm runner resolves against the tree's documented backend parameter.
    """
    face = p6_arms.P6_ARM_SPECS[tool]["face"]
    catalog_dest = ("/work/catalog.csv" if catalog_mount is not None
                    else "/work/in/catalog.csv")
    return ["Rscript", f"/work/{p6_arms.ARM_RUNNER}",
            "--counts", "/work/in/counts.csv",
            "--catalog", catalog_dest,
            "--params", "/work/in/params.json",
            "--outdir", "/work/out",
            "--backend", face]


def run(tool: str, cell: dict, spec,
        catalog_mount: Path | str | None = None) -> dict:
    """Execute one arm cell per the §1/§6 mount contract."""
    reason = docker_cmd.image_gate(spec)
    if reason is not None:
        raise AdapterUnavailable(
            f"{tool}: {reason} — skip-not-skip (memo §5 ii/§6)")
    return docker_cmd.run_container_cell(
        spec=spec, in_dir=Path(cell["in_dir"]), out_dir=Path(cell["out_dir"]),
        child_argv=child_argv(tool, catalog_mount), catalog_mount=catalog_mount)
