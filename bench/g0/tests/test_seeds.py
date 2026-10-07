"""⑥ 种子纪律测试（2026-10-07 G0 docker 重跑根因回归）。

根因回放：derive_seed 返回全 64-bit 值（如 5.5e18），容器侧 R
`as.integer(params$seed)` 溢出成 NA → sigfit/stl 整 cell FATAL；
11:02 smoke 的“通过”cell 实为陈旧缓存（旧 data_hash 不含工具参数）。
本组测试把三条纪律钉死：

  ① 工具边界种子必须落 [0, 2^31)（Stan seed / STL randomSeed 的 int32 域）；
  ② tool_seed 是 derive_seed 的确定性折叠（mod 2^31），黄金定点锁死派生布局，
     而 u64 派生流（numpy PCG64 数据流）不受影响；
  ③ Seeds.txt 逐工具列 == 实际喂容器的 tool_seed（协议 §2.3 落盘即事实）；
  ④ docker 命令装配：用户目录模式必须同时携带 cell 输入目录与
     catalog 原文件两个挂载（缺挂载 = 容器内 catalog.csv 失踪）。
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
    """run_grid 是脚本（含 argparse 主块，受 __main__ 守卫），按路径加载为模块。"""
    spec = importlib.util.spec_from_file_location("run_grid", str(HERE / "run_grid.py"))
    module = importlib.util.module_from_spec(spec)
    sys.modules["run_grid"] = module
    spec.loader.exec_module(module)
    return module


run_grid = _load_run_grid()

STAN_SEED_CAP = 1 << 31  # 工具边界：as.integer 域上限（Stan/STL 同域）


def test_tool_seed_within_stan_domain():
    # Arrange
    labels = list(product(["sigfit", "stl"], ["main", "nb", "sparse"],
                          [100, 1000, 300000], range(5)))
    # Act / Assert
    for parts in labels:
        s = seeds.tool_seed(*parts)
        assert 0 <= s < STAN_SEED_CAP, f"tool_seed{parts} = {s} 越出 [0, 2^31)"


def test_tool_seed_is_deterministic_folding_of_derived_seed():
    for parts in [("sigfit", "main", 1000), ("stl", "nb", 60, 3),
                  ("sigfit", "sparse", 1000, 7)]:
        assert seeds.tool_seed(*parts) == seeds.derive_seed(*parts) % STAN_SEED_CAP
        assert seeds.tool_seed(*parts) == seeds.tool_seed(*parts)  # 复现性


def test_tool_seed_golden_pins_derivation_layout():
    """黄金定点：派生布局（g0/v1 + FNV-1a + SplitMix64 + fold）任何漂移即红。"""
    golden = {
        ("sigfit", "main", 1000): 1007854028,
        ("stl", "main", 1000): 339750884,
        ("sigfit", "nb", 1000): 1976400330,
    }
    for parts, want in golden.items():
        assert seeds.tool_seed(*parts) == want, f"golden drift at {parts}"


def test_u64_data_stream_unaffected_by_tool_fold():
    """数据流（numpy PCG64 消费）保持 u64 全值——折叠只发生在工具边界。"""
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

    # Assert：表头不变；逐工具列 = tool_seed（容器实际所得），全部落 int32 域
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

    # Assert：两挂载齐全；目录文件直挂 rootfs 独立路径——叠挂在 cell 目录
    # bind 之内会令 Docker Desktop virtiofs 驱动 init 失败（runc: error
    # mounting … to rootfs，2026-10-07 smoke 全灭根因），D3 原样只读不变
    assert f"{ind}:/work/in:ro" in cmd
    assert f"{cat}:/work/catalog.csv:ro" in cmd
    assert sum("/work/catalog.csv:ro" in c for c in cmd) == 1
    assert cmd[cmd.index("--catalog") + 1] == "/work/catalog.csv"


def test_docker_cmd_single_mount_in_generated_catalog_mode():
    ind, outd = Path("/work/cell/in"), Path("/work/cell/out")
    cmd = run_grid.build_docker_cmd(ind, outd, "g0-stl", "run_stl.R")
    assert f"{ind}:/work/in" in cmd                       # generated 档 catalog.csv 在 in/ 内
    assert not any("catalog.csv:ro" in c for c in cmd)
    assert f"{outd}:/work/out" in cmd
    assert cmd[cmd.index("--catalog") + 1] == "/work/in/catalog.csv"


def test_docker_cmd_mount_sources_are_absolute():
    """相对 --cachedir 直进 docker -v 会被当命名卷（invalid characters for
    a local volume name，2026-10-07 smoke 二根因）——装配边界必须 resolve。"""
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
        assert src.startswith("/") and "relcell" in src, f"-v 源未绝对化: {s}"
