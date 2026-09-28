"""⑤ adapter 协议与 mock runner 的往返测试。

端到端：run_grid（smoke 档，mock adapter，synthetic provider）→
counts → intervals → coverage → 判定文件落盘 → 表格可解析、数值有界。
再直接驱动 mock_runner 验证估计量恢复（近重复对只看组和——可辨识性
受限正是被测现象，单签名不苛求）。
"""

import csv
import shutil
import sys
import tempfile
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parents[1]
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from g0 import providers, seeds, sim                     # noqa: E402
from g0.grid import MASTER_TRUTH_COMPOSITION             # noqa: E402
PROVIDER = providers.SyntheticProvider(seed=0)


def _run_mock(counts_csv: Path, catalog_csv: Path, outdir: Path, seed: int,
              coverage_scale: float = 1.0) -> Path:
    import json
    import subprocess
    import sys
    params = {"tool": "sigfit", "seed": seed,
              "coverage_scale": coverage_scale, "sample_seeds": {}}
    pdir = counts_csv.parent
    (pdir / "params.json").write_text(json.dumps(params), encoding="utf-8")
    cmd = [sys.executable, str(HERE / "adapters" / "mock_runner.py"),
           "--counts", str(counts_csv), "--catalog", str(catalog_csv),
           "--params", str(pdir / "params.json"), "--outdir", str(outdir)]
    subprocess.run(cmd, check=True, capture_output=True, text=True)
    return outdir / "intervals.csv"


def _write_catalog(path: Path):
    from run_grid import write_catalog_csv
    names, W = PROVIDER.catalog_matrix()
    write_catalog_csv(path, PROVIDER.channel_labels, names, W)


def _write_counts(path: Path, arm: str, n: int, reps: int):
    from run_grid import write_counts_csv
    rows = []
    for rep in range(reps):
        s = seeds.derive_seed(arm, n, rep)
        cell = sim.sample_cell(PROVIDER, arm, n, rep, s)
        rows.append([f"{arm}__N{n}__r{rep}", *cell.counts.tolist()])
    write_counts_csv(path, PROVIDER.channel_labels, rows)


def test_mock_roundtrip_recovery_and_bounded_intervals():
    tmp = Path(tempfile.mkdtemp(prefix="g0rt_"))
    counts = tmp / "counts.csv"
    catalog = tmp / "catalog.csv"
    _write_counts(counts, "main", 1000, 8)
    _write_catalog(catalog)
    intervals = _run_mock(counts, catalog, tmp / "out", seed=42)
    assert intervals.exists()
    with intervals.open(newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))
    n_catalog = len(PROVIDER.catalog_matrix()[0])   # 真值 + 缺席 + 组合轴扩展槽
    assert len(rows) == 8 * n_catalog               # 8 reps × 全目录签名
    for r in rows:
        lo, hi, est = float(r["lo95"]), float(r["hi95"]), float(r["estimate"])
        assert 0.0 <= lo <= hi or (np.isnan(lo) and np.isnan(hi))
        assert est >= 0
        assert r["estimand"] == "absolute"
    # 真值恢复：可辨识签名（SBS1）±20%；近重复对只要求组和 ±20%
    truth_h = {k: v * 1000 for k, v in MASTER_TRUTH_COMPOSITION.items()}
    by_sig = {}
    for r in rows:
        if r["sample_id"].endswith("r0"):
            by_sig.setdefault(r["signature"], []).append(float(r["estimate"]))
    h1 = float(np.mean(by_sig["SBS1"]))
    assert abs(h1 - truth_h["SBS1"]) / truth_h["SBS1"] < 0.20
    pair = float(np.mean([a + b for a, b in zip(by_sig["SBS5"], by_sig["SBS40"])]))
    truth_pair = truth_h["SBS5"] + truth_h["SBS40"]
    assert abs(pair - truth_pair) / truth_pair < 0.20
    shutil.rmtree(tmp, ignore_errors=True)


def test_run_grid_end_to_end_smoke_mock():
    """管线往返：run_grid.main(smoke/mock/synthetic) 全链路 + 判定产出。"""
    import run_grid
    tmp = Path(tempfile.mkdtemp(prefix="g0e2e_"))
    rc = run_grid.main([
        "--profile", "smoke", "--adapter", "mock", "--provider", "synthetic",
        "--tools", "sigfit,stl", "--with-lrt-diagnostic",
        "--outdir", str(tmp / "results"), "--cachedir", str(tmp / "cache"),
    ])
    assert rc == 0
    results = tmp / "results"
    files = sorted(p.name for p in results.iterdir())
    assert any(f.startswith("Seeds") for f in files)
    cov_csv = [f for f in files if f.startswith("coverage_smoke")][0]
    jud_md = [f for f in files if f.startswith("judgment_smoke")][0]
    # Seeds.txt 有数据行且种子为 64-bit
    seeds_rows = (results / "Seeds.txt").read_text(encoding="utf-8").splitlines()
    data_rows = [l for l in seeds_rows if l and not l.startswith("#")]
    assert len(data_rows) > 10                     # 列头 + 2 臂 × N × 5 reps
    seed_val = int(data_rows[1].split("\t")[3])
    assert 0 <= seed_val < 2 ** 64
    # coverage 表可解析、数值有界
    with (results / cov_csv).open(newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))
    assert rows, "coverage table empty"
    for r in rows:
        c = float(r["coverage"])
        assert 0.0 <= c <= 1.0
        assert 0.0 <= float(r["cp_lo"]) <= float(r["cp_hi"]) <= 1.0
        assert r["layer"] in ("easy", "flat")
    tools_seen = {r["tool"] for r in rows}
    assert tools_seen == {"sigfit", "stl"}
    # flat 层 P1 归因列存在
    assert any(r["p1_mechanism_i"] == "1" and r["layer"] == "flat" for r in rows)
    # 判定文件存在且含 verdict
    text = (results / jud_md).read_text(encoding="utf-8")
    assert "verdict:" in text
    # P3 诊断列存在
    assert (results / "diagnostic_lrt_nb.csv").exists()
    shutil.rmtree(tmp, ignore_errors=True)


def test_undercoverage_scale_drives_verdict_A():
    """测试钩子：区间过窄（coverage_scale=0.3）→ 欠覆盖 → 判定走 A 支路。"""
    import run_grid
    tmp = Path(tempfile.mkdtemp(prefix="g0uc_"))
    rc = run_grid.main([
        "--profile", "smoke", "--adapter", "mock", "--provider", "synthetic",
        "--tools", "sigfit", "--arms", "main", "--coverage-scale", "0.25",
        "--outdir", str(tmp / "results"), "--cachedir", str(tmp / "cache"),
    ])
    assert rc == 0
    results = tmp / "results"
    jud = [p for p in results.iterdir() if p.name.startswith("judgment_smoke")][0]
    text = jud.read_text(encoding="utf-8")
    assert "verdict: A" in text
    shutil.rmtree(tmp, ignore_errors=True)


def test_adapter_files_conformance():
    """协议面：Dockerfile 锁定 F2 冻结版本；协议文档与 mock runner 在位。"""
    ad = HERE / "adapters"
    sigfit_docker = (ad / "Dockerfile.sigfit").read_text(encoding="utf-8")
    stl_docker = (ad / "Dockerfile.stl").read_text(encoding="utf-8")
    assert "kgori/sigfit@v2.2.0" in sigfit_docker      # F2 冻结版本
    assert "signature.tools.lib@v2.5.2" in stl_docker  # F2 冻结版本
    assert (ad / "adapter_protocol.md").exists()
    assert (ad / "run_sigfit.R").exists() and (ad / "run_stl.R").exists()
    assert (ad / "mock_runner.py").exists()
    # 协议文档记录 nboot=200（冻结）与清零规则 0.01
    proto = (ad / "adapter_protocol.md").read_text(encoding="utf-8")
    assert "nboot" in proto and "0.01" in proto
