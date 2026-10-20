"""⑤ Round-trip tests of the adapter protocol and the mock runner.

End-to-end: run_grid (smoke profile, mock adapter, synthetic provider) →
counts → intervals → coverage → judgment file landed → tables parseable, values bounded.
Then drive mock_runner directly to verify estimand recovery (the near-duplicate pair is judged
as a group only — limited identifiability is exactly the phenomenon under test; single signatures are not demanded).
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
    n_catalog = len(PROVIDER.catalog_matrix()[0])   # truth + absent + composition-axis extension slots
    assert len(rows) == 8 * n_catalog               # 8 reps × full-catalog signatures
    for r in rows:
        lo, hi, est = float(r["lo95"]), float(r["hi95"]), float(r["estimate"])
        assert 0.0 <= lo <= hi or (np.isnan(lo) and np.isnan(hi))
        assert est >= 0
        assert r["estimand"] == "absolute"
    # Truth recovery: identifiable signature (SBS1) ±20%; the near-duplicate pair only as a group ±20%
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
    """Pipeline round-trip: run_grid.main(smoke/mock/synthetic) full chain + judgment output."""
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
    # Seeds.txt has data rows and the seed is 64-bit
    seeds_rows = (results / "Seeds.txt").read_text(encoding="utf-8").splitlines()
    data_rows = [l for l in seeds_rows if l and not l.startswith("#")]
    assert len(data_rows) > 10                     # column header + 2 arms × N × 5 reps
    seed_val = int(data_rows[1].split("\t")[3])
    assert 0 <= seed_val < 2 ** 64
    # the coverage table parses and its values are bounded
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
    # the flat-layer P1 attribution column exists
    assert any(r["p1_mechanism_i"] == "1" and r["layer"] == "flat" for r in rows)
    # the judgment file exists and contains the verdict
    text = (results / jud_md).read_text(encoding="utf-8")
    assert "verdict:" in text
    # the P3 diagnostic column exists
    assert (results / "diagnostic_lrt_nb.csv").exists()
    shutil.rmtree(tmp, ignore_errors=True)


def test_undercoverage_scale_drives_verdict_A():
    """Test hook: intervals too narrow (coverage_scale=0.3) → under-coverage → the judgment takes the A branch."""
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
    """Protocol surface: the Dockerfiles pin the F2 frozen versions; the protocol doc and the mock runner are in place."""
    ad = HERE / "adapters"
    sigfit_docker = (ad / "Dockerfile.sigfit").read_text(encoding="utf-8")
    stl_docker = (ad / "Dockerfile.stl").read_text(encoding="utf-8")
    assert "kgori/sigfit@v2.2.0" in sigfit_docker      # F2 frozen version
    # F2 frozen version: STL goes via git clone pinned to a tag (evading the remotes API rate limit, see the Dockerfile header note)
    assert "Nik-Zainal-Group/signature.tools.lib" in stl_docker
    assert "--branch v2.5.2" in stl_docker
    assert (ad / "adapter_protocol.md").exists()
    assert (ad / "run_sigfit.R").exists() and (ad / "run_stl.R").exists()
    assert (ad / "mock_runner.py").exists()
    # the protocol doc records nboot=200 (frozen) and the zeroing rule 0.01
    proto = (ad / "adapter_protocol.md").read_text(encoding="utf-8")
    assert "nboot" in proto and "0.01" in proto
