"""Group (Q) test_ensemble_cache — L3 hash-keyed ensemble cache (Phase-9 O1).

The card the cache serves (Phase-6 O4 sketch, controller-adopted clause): the
whole 100-member ensemble is a deterministic function of (fixture bytes,
frozen protocol constants, RNG regime, code-version token) — a leg that
re-runs byte-identical inputs under byte-identical code pays ~970 s to
recompute what is reproducible by construction. The cache memoises at the
container-composition point (competitors._p6_common.run), NEVER inside the
image, and under an adoption-gate posture:

  OFF by default. The campaign driver and the frozen gates never consult it
    implicitly; only MSUITER_ENS_CACHE_DIR set to a path OUTSIDE the tree
    turns it on. The tripwire against driver-side activation is pinned here.
  A miss runs the ensemble. A hit serves bytes that are, by construction of
    the store step, the gate-passed fresh-run bytes — the measured legs
    (report O1) attest byte-identity against the frozen witnesses.
  Corruption is a miss, never a failure: a truncated payload file or a
    tampered entry silently falls through to the fresh path (tamper tests
    below) — the cache may lose memoity, may not lose correctness.
  Only gate-passed legs populate. run_container_cell raises on a missing
    guard file or an invalid sidecar; capture is reached only past that.
  A served leg is counted, never mistaken: its sidecar carries the
    cache-hit token and ~0 cpu; the witness minter refuses such a sidecar
    (freshness_law extension) so a replay can never pose as a measurement.

RED-by-absence: the module is imported from competitors.ensemble_cache.
"""

from __future__ import annotations

import json
import os
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from competitors import docker_cmd, ensemble_cache   # noqa: E402 (RED-by-absence)


REPO_ROOT = HERE.parents[1]                          # msuiter tree root


class _Spec:
    """Minimal registry-row face: the identity columns the key binds."""
    def __init__(self, **kw):
        self.name = kw.get("name", "sigminer_post_v3")
        self.runtime = "R"
        self.version = "2.3.3"
        self.image_ref = kw.get("image_ref", "msuiter-sigminer:t")
        self.image_digest = kw.get("image_digest", "sha256:" + "a" * 64)
        self.entrypoint = "python3"
        self.runner_script = "m7_entry.py"
        self.tree_sha = kw.get("tree_sha", "a8b8825b")
        self.face = kw.get("face", "R")


CHILD_ARGV = ["Rscript", "/work/run_sigminer_arm.R",
              "--counts", "/work/in/counts.csv",
              "--catalog", "/work/in/catalog.csv",
              "--params", "/work/in/params.json",
              "--outdir", "/work/out", "--backend", "R"]


def _fixture(in_dir: Path, *, counts="a,b\n1,2\n", params="p\n", catalog=None):
    in_dir.mkdir(parents=True, exist_ok=True)
    (in_dir / "counts.csv").write_text(counts, encoding="utf-8")
    (in_dir / "params.json").write_text(params, encoding="utf-8")
    if catalog is not None:
        (in_dir / "catalog.csv").write_text(catalog, encoding="utf-8")


def _fresh_cell(out_dir: Path, *, extra=("spectra.csv",)):
    """What the real cell leaves behind when the gates let it pass."""
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "intervals.csv").write_text("s,x,1.0,0,2,absolute,0\n",
                                           encoding="utf-8")
    (out_dir / "errors.log").write_text("", encoding="utf-8")
    for name in extra:
        (out_dir / name).write_text(f"{name}\n", encoding="utf-8")
    (out_dir / "timing.json").write_text(json.dumps(
        {"ru_utime": 1000.0, "ru_stime": 1.0, "cpu_seconds": 1001.0,
         "exit_status": 0}), encoding="utf-8")


def _stub_docker(calls: list):
    """Replace the two container-side seams (image_gate + run_container_cell):
    record the launch, write a gate-passed cell. Returns the restore call."""
    def fake(spec, in_dir, out_dir, child_argv, catalog_mount=None,
             produced_files=("intervals.csv", "errors.log", "timing.json")):
        calls.append({"child_argv": list(child_argv),
                      "catalog_mount": catalog_mount})
        _fresh_cell(Path(out_dir))
        return {"cpu_seconds": 1001.0, "sidecar": {"exit_status": 0}}
    originals = (docker_cmd.run_container_cell, docker_cmd.image_gate)
    docker_cmd.run_container_cell = fake
    docker_cmd.image_gate = lambda spec: None
    def restore():
        docker_cmd.run_container_cell, docker_cmd.image_gate = originals
    return restore


def _with_env(tmp: Path):
    os.environ[ensemble_cache.CACHE_ENV] = str(tmp)


def _without_env():
    os.environ.pop(ensemble_cache.CACHE_ENV, None)


# -- (1) default posture ------------------------------------------------------

def test_cache_is_off_unless_the_advisory_env_names_a_directory(tmpdir=None):
    """Unset env => zero cache contact: the fresh path runs and nothing is
    read from, or written to, any cache namespace."""
    from competitors import _p6_common
    calls: list = []
    restore = _stub_docker(calls)
    import tempfile
    work = Path(tempfile.mkdtemp(prefix="ens_off_"))
    try:
        _without_env()
        _fixture(work / "in")
        summary = _p6_common.run("sigminer_post_v3",
                                 {"in_dir": work / "in",
                                  "out_dir": work / "out"}, _Spec())
        assert len(calls) == 1, "fresh path must run exactly once when off"
        assert summary["cpu_seconds"] == 1001.0
    finally:
        restore()
        shutil.rmtree(work, ignore_errors=True)


def test_frozen_drivers_never_set_the_env():
    """Tripwire: neither the campaign ignition script nor the orchestrator
    may name the cache env — activation is an operator/advisory act only."""
    banned = ensemble_cache.CACHE_ENV
    for rel in ("tools/p6_ignition.sh", "run_bench.py"):
        text = (HERE / rel).read_text(encoding="utf-8")
        assert banned not in text, f"{rel} consults {banned} implicitly"


def test_in_tree_cache_dir_is_refused_treated_as_absent():
    """A cache dir inside the tree is a governance breach; the module must
    behave exactly as if the env were unset (fresh path, zero writes)."""
    from competitors import _p6_common
    import tempfile
    calls: list = []
    restore = _stub_docker(calls)
    work = Path(tempfile.mkdtemp(prefix="ens_intree_"))
    try:
        _with_env(REPO_ROOT / "bench" / "results" / "ens_cache_pollution")
        _fixture(work / "in")
        _p6_common.run("sigminer_post_v3",
                       {"in_dir": work / "in", "out_dir": work / "out"},
                       _Spec())
        assert len(calls) == 1, "in-tree cache must not serve"
        assert not (REPO_ROOT / "bench" / "results"
                    / "ens_cache_pollution").exists(), "in-tree cache must not write"
    finally:
        _without_env()
        restore()
        shutil.rmtree(work, ignore_errors=True)


# -- (2) key binding ----------------------------------------------------------

def _key(**mutate):
    import tempfile
    work = Path(tempfile.mkdtemp(prefix="ens_key_"))
    try:
        _fixture(work / "in", counts=mutate.get("counts", "a,b\n1,2\n"),
                 params=mutate.get("params", '{"seed": 1}'),
                 catalog=mutate.get("catalog", "c\n"))
        spec = mutate.get("spec") or _Spec()
        return ensemble_cache.key_of(spec=spec, in_dir=work / "in",
                                     catalog_mount=None, child_argv=CHILD_ARGV)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def test_key_is_pure_over_identical_inputs():
    k1, k2 = _key(), _key()
    assert k1 == k2, "the key must be a pure function of the key components"


def test_key_changes_with_every_bound_component():
    base = _key()
    mutations = {
        "counts": "a,b\n1,3\n",                       # fixture bytes
        "params": '{"seed": 2}',                      # RNG regime
        "catalog": "c2\n",
        "spec": _Spec(image_digest="sha256:" + "b" * 64),   # code version
        "spec2": _Spec(tree_sha="deadbeef"),                # tree token
        "spec3": _Spec(face="rust"),                        # face token
    }
    assert _key(**{k: v for k, v in mutations.items() if k == "counts"}) != base
    assert _key(params=mutations["params"]) != base
    assert _key(catalog=mutations["catalog"]) != base
    assert _key(spec=mutations["spec"]) != base
    assert _key(spec=mutations["spec2"]) != base
    assert _key(spec=mutations["spec3"]) != base
    # child argv (the only face-difference carrier) must bind too:
    import tempfile
    work = Path(tempfile.mkdtemp(prefix="ens_key_argv_"))
    try:
        _fixture(work / "in", catalog="c\n")
        k_plain = ensemble_cache.key_of(spec=_Spec(), in_dir=work / "in",
                                        catalog_mount=None,
                                        child_argv=CHILD_ARGV)
        k_rust = ensemble_cache.key_of(spec=_Spec(), in_dir=work / "in",
                                       catalog_mount=None,
                                       child_argv=[*CHILD_ARGV[:-1], "rust"])
        assert k_plain != k_rust, "child argv is not key-bound"
    finally:
        shutil.rmtree(work, ignore_errors=True)


# -- (3) miss -> fresh; gate-pass -> store; warm -> serve ---------------------

def _two_leg_shape(tmp: Path, *, mutate=None):
    """Run one shape cold (stores), replay it warm (serves). Returns facts."""
    from competitors import _p6_common
    import tempfile
    work = Path(tempfile.mkdtemp(prefix="ens_shape_"))
    calls: list = []
    restore = _stub_docker(calls)
    try:
        _with_env(tmp)
        _fixture(work / "in", catalog="c\n")
        spec = _Spec()
        cold = _p6_common.run("sigminer_post_v3",
                              {"in_dir": work / "in",
                               "out_dir": work / "out"}, spec)
        assert len(calls) == 1, "cold leg must have launched the container"
        assert cold["cpu_seconds"] == 1001.0
        # a warm replay: fresh out dir, identical key components
        shutil.rmtree(work / "out", ignore_errors=True)
        warm = _p6_common.run("sigminer_post_v3",
                              {"in_dir": work / "in",
                               "out_dir": work / "out"}, spec)
        assert len(calls) == 1, ("warm leg must NOT launch the container — "
                                 "a hit serves without launching")
        for name in ("intervals.csv", "errors.log", "spectra.csv"):
            assert (work / "out" / name).exists(), f"served cell lacks {name}"
        assert ((work / "out" / "intervals.csv").read_text(encoding="utf-8")
                == "s,x,1.0,0,2,absolute,0\n"), "served bytes differ"
        side = json.loads((work / "out" / "timing.json").read_text(encoding="utf-8"))
        assert side.get("measurement") == "cache-hit", "sidecar must speak cache-hit"
        assert float(side.get("cpu_seconds", 9e9)) < 1.0, "served cpu must be ~0"
        return warm
    finally:
        _without_env()
        restore()
        shutil.rmtree(work, ignore_errors=True)


def test_cold_leg_stores_and_warm_leg_serves_without_launching(tmpdir=None):
    import tempfile
    warm = _two_leg_shape(Path(tempfile.mkdtemp(prefix="ens_cache_")))
    assert warm["cpu_seconds"] == 0.0 or warm["cpu_seconds"] < 1.0


# -- (4) corruption is a miss, never a failure --------------------------------

def _seed_one_leg(tmp: Path, work: Path) -> tuple:
    """Cold-fill the cache once; return (calls, restore-fn) with cache warm."""
    from competitors import _p6_common
    calls: list = []
    restore = _stub_docker(calls)
    _with_env(tmp)
    _fixture(work / "in", catalog="c\n")
    _p6_common.run("sigminer_post_v3", {"in_dir": work / "in",
                                        "out_dir": work / "out"}, _Spec())
    shutil.rmtree(work / "out", ignore_errors=True)
    return calls, restore


def test_truncated_payload_falls_through_to_the_fresh_path():
    from competitors import _p6_common
    import tempfile
    tmp = Path(tempfile.mkdtemp(prefix="ens_cache_"))
    work = Path(tempfile.mkdtemp(prefix="ens_work_"))
    try:
        calls, restore = _seed_one_leg(tmp, work)
        # truncate every stored interval payload to zero bytes
        payload_root = tmp / "keys"
        hit = False
        for p in payload_root.rglob("*intervals.csv"):
            p.write_text("", encoding="utf-8")
            hit = True
        assert hit, "tamper plant found no payload file — store shape changed"
        _p6_common.run("sigminer_post_v3", {"in_dir": work / "in",
                                           "out_dir": work / "out"}, _Spec())
        assert len(calls) == 2, ("truncated entry must be a silent MISS that "
                                 "runs the ensemble again, never a failure")
        assert (work / "out" / "intervals.csv").read_text(encoding="utf-8") \
            == "s,x,1.0,0,2,absolute,0\n"
    finally:
        _without_env()
        restore()
        shutil.rmtree(tmp, ignore_errors=True)
        shutil.rmtree(work, ignore_errors=True)


def test_tampered_entry_digest_falls_through_to_the_fresh_path():
    from competitors import _p6_common
    import tempfile
    tmp = Path(tempfile.mkdtemp(prefix="ens_cache_"))
    work = Path(tempfile.mkdtemp(prefix="ens_work_"))
    try:
        calls, restore = _seed_one_leg(tmp, work)
        entries = list(tmp.rglob("*entry.json"))
        assert entries, "store wrote no entry.json"
        for e in entries:
            doc = json.loads(e.read_text(encoding="utf-8"))
            files = doc.get("files") or {}
            assert files, "entry carries no file-digest map"
            first = next(iter(files))
            files[first] = "0" * 64                    # wrong-key / rotated blob
            e.write_text(json.dumps(doc), encoding="utf-8")
        _p6_common.run("sigminer_post_v3", {"in_dir": work / "in",
                                           "out_dir": work / "out"}, _Spec())
        assert len(calls) == 2, "tampered entry must refuse service silently"
    finally:
        _without_env()
        restore()
        shutil.rmtree(tmp, ignore_errors=True)
        shutil.rmtree(work, ignore_errors=True)


def test_unparseable_entry_is_a_miss():
    from competitors import _p6_common
    import tempfile
    tmp = Path(tempfile.mkdtemp(prefix="ens_cache_"))
    work = Path(tempfile.mkdtemp(prefix="ens_work_"))
    try:
        calls, restore = _seed_one_leg(tmp, work)
        for e in tmp.rglob("*entry.json"):
            e.write_text("{not json", encoding="utf-8")
        _p6_common.run("sigminer_post_v3", {"in_dir": work / "in",
                                           "out_dir": work / "out"}, _Spec())
        assert len(calls) == 2
    finally:
        _without_env()
        restore()
        shutil.rmtree(tmp, ignore_errors=True)
        shutil.rmtree(work, ignore_errors=True)


def test_failed_leg_never_populates():
    """A container that dies (or leaves a guard file missing) must not leave
    a half-truth in the cache: store is reached only past run_container_cell's
    own guard/sidecar validation, so a raised leg stores nothing."""
    from competitors import _p6_common
    import tempfile
    tmp = Path(tempfile.mkdtemp(prefix="ens_cache_"))
    work = Path(tempfile.mkdtemp(prefix="ens_work_"))
    try:
        _with_env(tmp)
        _fixture(work / "in", catalog="c\n")
        def dying(spec, in_dir, out_dir, child_argv, catalog_mount=None,
                  produced_files=()):
            raise RuntimeError("container exited 1")
        original = docker_cmd.run_container_cell
        docker_cmd.run_container_cell = dying
        try:
            try:
                _p6_common.run("sigminer_post_v3",
                               {"in_dir": work / "in", "out_dir": work / "out"},
                               _Spec())
                raised = False
            except RuntimeError:
                raised = True
            assert raised, "cell failure must propagate as a cell failure"
        finally:
            docker_cmd.run_container_cell = original
        assert not list(tmp.rglob("*entry.json")), "failed leg wrote an entry"
    finally:
        _without_env()
        shutil.rmtree(tmp, ignore_errors=True)
        shutil.rmtree(work, ignore_errors=True)


# -- (5) served legs cannot mint witnesses ------------------------------------

def test_probe_freshness_law_refuses_a_served_sidecar():
    """freshness_law is the mint-side firewall: cache-hit sidecars are
    measurements of a copy, never of the ensemble — DEFECT them."""
    from tools import probe_sigminer_cell_argv as probe
    assert probe.freshness_law("ok", sidecar={"measurement": "cache-hit",
                                              "exit_status": 0}) is not None, \
        "a cache-hit sidecar must never mint a floor witness"
    assert probe.freshness_law("ok", sidecar={"exit_status": 0}) is None, \
        "an ordinary measured sidecar must still mint"
