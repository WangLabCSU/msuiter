"""Docker command composition for the M7 competitor containers (memo §4.2/§5).

Two load-bearing invariants, both pinned by tests/test_adapters.py:

1. **Caps-before-image.** Every thread cap is injected as ``-e CAP=1``
   strictly *before* the image token — the exact position that cured the G0
   over-subscription OOM storm (devlog 2026-10-08 §1, fix 333f06e). The
   frozen ``THREAD_CAPS`` tuple is the union of the G0 closure list
   (OMP_NUM_THREADS, R_LIMIT_THREADS, GOMAXPROCS, MSUITER_THREADS) and the
   BLAS/Stan caps already present in ``bench/g0/run_grid.py::build_docker_cmd``
   (OMP_NUM_THREADS, OMP_THREAD_LIMIT, STAN_OMP_NUM_THREADS,
   OPENBLAS_NUM_THREADS). Caps are pure execution-layer ceilings: sampling
   semantics are untouched.

2. **Mirror policy (memo §5).** Image *references* stored in the registry are
   either harness-built local tags or already mirror-spelled refs; every
   ``FROM``/pull in this harness spells the mirror host explicitly. The
   table below is the normative record (identical to memo §5); ``pull_via``
   translates an upstream reference for the build-time record.

The mount contract follows G0: ``in`` mounted read-only at ``/work/in``,
``out`` writable at ``/work/out``; a user-supplied (COSMIC) catalog mounts
as its own single-file read-only bind at ``/work/catalog.csv`` — overlaying
it inside the ``in`` bind fails under the Docker Desktop virtiofs driver
(2026-10-07 G0 root cause, mirrored here deliberately).
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

# Frozen union of the G0 closure cap list and the run_grid BLAS/Stan caps
# (order = memo §4.2 enumeration; position in the command is semantically
# load-bearing, order among caps is not).
THREAD_CAPS: tuple[str, ...] = (
    "OMP_NUM_THREADS", "OMP_THREAD_LIMIT", "R_LIMIT_THREADS", "GOMAXPROCS",
    "MSUITER_THREADS", "STAN_OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS",
)
CAP_VALUE = "1"

# Memo §5 translation table (authoritative record for this harness).
MIRROR_PREFIXES: dict[str, str] = {
    "docker.io": "9f6c5in3dh5vszgdz0.xuanyuan.run",
    "ghcr.io": "9f6c5in3dh5vszgdz0-ghcr.xuanyuan.run",
    "quay.io": "9f6c5in3dh5vszgdz0-quay.xuanyuan.run",
    "registry.gitlab.com": "9f6c5in3dh5vszgdz0-gitlab.xuanyuan.run",
    "mcr.microsoft.io": "9f6c5in3dh5vszgdz0-mcr.xuanyuan.run",
    "gcr.io": "9f6c5in3dh5vszgdz0-gcr.xuanyuan.run",
    "nvcr.io": "9f6c5in3dh5vszgdz0-nvcr.xuanyuan.run",
}


def pull_via(upstream_ref: str) -> str:
    """Spell an ``<upstream-host>/...`` reference through its mirror host
    (memo §5). Unmapped hosts raise — routing around the policy (e.g. after
    a 407) is prohibited; a 407 is environmental evidence, recorded as is."""
    host = upstream_ref.split("/", 1)[0]
    mirror = MIRROR_PREFIXES.get(host)
    if mirror is None:
        raise ValueError(
            f"no mirror for registry host {host!r}; direct upstream pulls "
            f"are prohibited by the memo §5 policy")
    return mirror + upstream_ref[len(host):]


def build_container_cmd(image: str, runner: str, in_dir: Path, out_dir: Path,
                        catalog_mount: Path | str | None = None,
                        entrypoint: str = "python3",
                        runner_args: list[str] | None = None) -> list[str]:
    """Compose the ``docker run`` command for one competitor cell.

    ``runner`` is the script name under ``/work`` in the image (the shared
    ``m7_entry.py`` measurement wrapper); ``runner_args`` defaults to the
    adapter-protocol quad. Mount sources are resolved to absolute paths —
    docker treats relative ``-v`` sources as named volumes (G0 2026-10-07
    second root cause).
    """
    cmd: list[str] = ["docker", "run", "--rm"]
    for cap in THREAD_CAPS:                     # caps BEFORE the image token
        cmd += ["-e", f"{cap}={CAP_VALUE}"]
    ind, outd = Path(in_dir).resolve(), Path(out_dir).resolve()
    cmd += ["-v", f"{ind}:/work/in:ro"]
    if catalog_mount is not None:
        cmd += ["-v", f"{Path(catalog_mount).resolve()}:/work/catalog.csv:ro"]
    cmd += ["-v", f"{outd}:/work/out"]
    cmd += [str(image)]                         # the one image token
    catalog_dest = ("/work/catalog.csv" if catalog_mount is not None
                    else "/work/in/catalog.csv")
    if runner_args is None:
        runner_args = ["--counts", "/work/in/counts.csv",
                       "--catalog", catalog_dest,
                       "--params", "/work/in/params.json",
                       "--outdir", "/work/out"]
    return cmd + [entrypoint, f"/work/{runner}", *runner_args]


def image_gate(spec) -> str | None:
    """Why this spec may not run, or ``None`` when the container path is
    admissible. Order matters: provenance is refused before the daemon is
    ever consulted (a PENDING-VERIFY digest must not be 'rescued' by a
    stray local tag)."""
    digest = (spec.image_digest or "").strip()
    if not digest.startswith("sha256:") or len(digest) != 71:
        return (f"image {spec.image_ref!r} digest is {digest or 'empty'!r} "
                f"— provenance not captured from 'docker image inspect' "
                f"(inventing digests is prohibited, memo §5 ii)")
    if shutil.which("docker") is None:
        return "docker CLI not available on this host"
    probe = subprocess.run(["docker", "image", "inspect", spec.image_ref],
                           capture_output=True, text=True)
    if probe.returncode != 0:
        return (f"image {spec.image_ref!r} is not present in the local "
                f"image store")
    return None


def verify_cell_outputs(out_dir: Path, guard_files: tuple[str, ...]) -> str | None:
    """Return the name of the first missing guard file, else ``None``."""
    for name in guard_files:
        if not (Path(out_dir) / name).exists():
            return name
    return None


# The measurement wrapper every image ships (adapters/m7_entry.py): it
# launches the competitor's real runner as its single child, records the
# child's rusage and writes out/timing.json. The container command always
# enters through it, so the CPU column is never a host-side guess (§4.3).
ENTRY_SCRIPT = "m7_entry.py"
ENTRY_ARGS = ["--params", "/work/in/params.json", "--outdir", "/work/out", "--"]


def run_container_cell(spec, in_dir: Path, out_dir: Path, child_argv: list[str],
                       catalog_mount: Path | str | None = None,
                       produced_files: tuple[str, ...] = ("intervals.csv",
                                                         "errors.log",
                                                         "timing.json")) -> dict:
    """Run one measured container cell (post image-gate) and return the
    sidecar-backed summary.

    ``child_argv`` is the competitor's real command inside the container
    (e.g. ``["Rscript", "/work/run_sigminer.R", ...]``); the shared
    ``m7_entry.py`` wrapper is what the image is asked to execute.
    A non-zero container exit is a cell FAILURE (RuntimeError), never a
    skip — skip-not-skip governs admissibility, not execution outcome.
    """
    from . import timings                       # local: sidecar parse only
    cmd = build_container_cmd(
        image=spec.image_ref, runner=ENTRY_SCRIPT, entrypoint=spec.entrypoint,
        in_dir=in_dir, out_dir=out_dir, catalog_mount=catalog_mount,
        runner_args=ENTRY_ARGS + list(child_argv))
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        tail = (proc.stderr or proc.stdout or "")[-400:]
        raise RuntimeError(f"container run failed (exit {proc.returncode}): {tail}")
    missing = verify_cell_outputs(out_dir, produced_files)
    if missing is not None:
        raise RuntimeError(
            f"{spec.name}: container exited 0 but produced no {missing} "
            f"— refusing to score an empty cell")
    sidecar = timings.read_timing_sidecar(Path(out_dir) / "timing.json")
    return {"cpu_seconds": timings.cpu_seconds_of(sidecar), "sidecar": sidecar}
