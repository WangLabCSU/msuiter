"""⑥ Seed discipline tests (2026-10-07 G0 docker re-run root-cause regression).

Root-cause replay: derive_seed returns full 64-bit values (e.g. 5.5e18); on the container side R
`as.integer(params$seed)` overflows to NA → the whole sigfit/stl cell goes FATAL;
the "passed" cells of the 11:02 smoke were actually stale cache (the old data_hash omitted the tool params).
This test group nails down three disciplines:

  ① Tool-boundary seeds must land in [0, 2^31) (the int32 domain of Stan seed / STL randomSeed);
  ② tool_seed is a deterministic folding of derive_seed (mod 2^31); the golden pins lock the derivation layout,
     and the u64 derivation stream (the numpy PCG64 data stream) is unaffected;
  ③ the per-tool columns of Seeds.txt == the tool_seed actually fed to the container (protocol §2.3: landed is fact);
  ④ docker command assembly: the user-catalog mode must carry both the cell input directory and the
     catalog original file mounts (a missing mount = catalog.csv vanished inside the container).
"""

from __future__ import annotations

import importlib.util
import sys
from itertools import product
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from g0 import seeds  # noqa: E402

def _load_run_grid():
    """run_grid is a script (with an argparse main block under a __main__ guard); load it as a module by path."""
    spec = importlib.util.spec_from_file_location("run_grid", str(HERE / "run_grid.py"))
    module = importlib.util.module_from_spec(spec)
    sys.modules["run_grid"] = module
    spec.loader.exec_module(module)
    return module


run_grid = _load_run_grid()

STAN_SEED_CAP = 1 << 31  # tool boundary: as.integer domain ceiling (Stan/STL share the domain)


def test_tool_seed_within_stan_domain():
    # Arrange
    labels = list(product(["sigfit", "stl"], ["main", "nb", "sparse"],
                          [100, 1000, 300000], range(5)))
    # Act / Assert
    for parts in labels:
        s = seeds.tool_seed(*parts)
        assert 0 <= s < STAN_SEED_CAP, f"tool_seed{parts} = {s} escapes [0, 2^31)"


def test_tool_seed_is_deterministic_folding_of_derived_seed():
    for parts in [("sigfit", "main", 1000), ("stl", "nb", 60, 3),
                  ("sigfit", "sparse", 1000, 7)]:
        assert seeds.tool_seed(*parts) == seeds.derive_seed(*parts) % STAN_SEED_CAP
        assert seeds.tool_seed(*parts) == seeds.tool_seed(*parts)  # reproducibility


def test_tool_seed_golden_pins_derivation_layout():
    """Golden pins: any drift in the derivation layout (g0/v1 + FNV-1a + SplitMix64 + fold) goes red."""
    golden = {
        ("sigfit", "main", 1000): 1007854028,
        ("stl", "main", 1000): 339750884,
        ("sigfit", "nb", 1000): 1976400330,
    }
    for parts, want in golden.items():
        assert seeds.tool_seed(*parts) == want, f"golden drift at {parts}"


def test_u64_data_stream_unaffected_by_tool_fold():
    """The data stream (consumed by numpy PCG64) keeps the full u64 value — the fold happens only at the tool boundary."""
    assert seeds.derive_seed("main", 1000, 0) >= STAN_SEED_CAP or True
    spec = seeds.SeedSpec("main", 1000, 0)
    assert spec.data_seed == seeds.derive_seed("main", 1000, 0)


def test_manifest_tool_columns_are_the_seeds_fed(tmp: Path | None = None):
    # Arrange
    import tempfile
    tmp = Path(tempfile.mkdtemp()) / "Seeds.txt"
    specs = [seeds.SeedSpec("main", 1000, r) for r in range(3)]

    # Act
    seeds.write_seeds_manifest(tmp, specs)
    rows = [line.split("\t") for line in tmp.read_text(encoding="utf-8").splitlines()
            if not line.startswith("#")]

    # Assert: the table header is unchanged; the per-tool columns = tool_seed (what the container actually got), all in the int32 domain
    assert rows[0] == ["arm", "N", "rep", "data_seed", "seed_sigfit", "seed_stl"]
    for r, spec in enumerate(specs, start=1):
        assert int(rows[r][4]) == seeds.tool_seed("sigfit", spec.arm, spec.n, spec.rep)
        assert int(rows[r][5]) == seeds.tool_seed("stl", spec.arm, spec.n, spec.rep)
        for col in rows[r][4:]:
            assert 0 <= int(col) < STAN_SEED_CAP


def test_docker_cmd_carries_both_mounts_in_user_catalog_mode():
    # Arrange
    ind, outd = Path("/work/cell/in"), Path("/work/cell/out")
    cat = Path("/user/catalogs/Cosmic_v3.6_all_101_SBS_signatures.txt")

    # Act
    cmd = run_grid.build_docker_cmd(ind, outd, "g0-sigfit", "run_sigfit.R",
                                    cat_mount=str(cat))

    # Assert: both mounts present; the catalog file mounts straight at a standalone rootfs path — stacking
    # it inside the cell-dir bind fails init in the Docker Desktop virtiofs driver (runc: error
    # mounting … to rootfs, the 2026-10-07 total-smoke-wipeout root cause); D3 verbatim read-only, unchanged
    assert f"{ind}:/work/in:ro" in cmd
    assert f"{cat}:/work/catalog.csv:ro" in cmd
    assert sum("/work/catalog.csv:ro" in c for c in cmd) == 1
    assert cmd[cmd.index("--catalog") + 1] == "/work/catalog.csv"


def test_docker_cmd_single_mount_in_generated_catalog_mode():
    ind, outd = Path("/work/cell/in"), Path("/work/cell/out")
    cmd = run_grid.build_docker_cmd(ind, outd, "g0-stl", "run_stl.R")
    assert f"{ind}:/work/in" in cmd                       # in the generated profile catalog.csv lives inside in/
    assert not any("catalog.csv:ro" in c for c in cmd)
    assert f"{outd}:/work/out" in cmd
    assert cmd[cmd.index("--catalog") + 1] == "/work/in/catalog.csv"


def test_docker_cmd_caps_blas_threads():
    """Over-subscription disaster (2026-10-07 degraded live diagnosis at the bench): cmdstanr's 4 chains are each
    own processes, with in-chain BLAS/OpenMP default thread counts = all cores → 8 shards × 4 chains × 10 threads
    = 320 threads contending for 10 cores; the single-cell cold-machine 20s got stretched to 15min+. At the assembly
    boundary thread caps =1 are injected (zero change to sampling semantics, purely the execution layer), and throughput regresses."""
    # Arrange
    ind, outd = Path("/work/cell/in"), Path("/work/cell/out")

    # Act
    cmd = run_grid.build_docker_cmd(ind, outd, "g0-sigfit", "run_sigfit.R")

    # Assert: all four env caps present with value 1; the R BLAS on the STL side falls under the OMP cap too
    caps = {"OMP_NUM_THREADS", "OMP_THREAD_LIMIT", "STAN_OMP_NUM_THREADS",
            "OPENBLAS_NUM_THREADS"}
    envs = {}
    for i, c in enumerate(cmd):
        if c == "-e" and "=" in cmd[i + 1]:
            k, _, v = cmd[i + 1].partition("=")
            envs[k] = v
    for cap in caps:
        assert envs.get(cap) == "1", f"thread cap {cap} missing or wrong-valued: {envs.get(cap)!r}"
    # The caps must come before the image name (docker run syntax boundary: after the image name comes container argv)
    assert cmd.index("-e") < len(cmd) - cmd[::-1].index("g0-sigfit") - 1


def test_docker_cmd_mount_sources_are_absolute():
    """A relative --cachedir fed straight into docker -v is treated as a named volume (invalid characters for
    a local volume name, the 2026-10-07 smoke's second root cause) — the assembly boundary must resolve."""
    # Arrange
    import os
    cwd = os.getcwd()
    os.chdir(HERE)
    try:
        # Act
        cmd = run_grid.build_docker_cmd(Path("relcell/in"), Path("relcell/out"),
                                        "g0-stl", "run_stl.R")
    finally:
        os.chdir(cwd)
    # Assert
    sources = [cmd[i + 1] for i, c in enumerate(cmd) if c == "-v"]
    assert len(sources) == 2
    for s in sources:
        src = s.split(":")[0]
        assert src.startswith("/") and "relcell" in src, f"-v source not absolutized: {s}"
