"""Group (AI) test_p2_pipeline -- the P2 sidecar accounting v2 (parity plan P2, pair S).

The forensics Q3 census caught the sidecar UNDERCOUNTING the measured tree:
the same run read 2.058 concurrent through the sidecar while the container
cgroup sustained 3.69 cores -- orphaned PSOCK-style workers (PPID=1) left
the os.wait4 rusage child tree and escaped attribution. The L2 farm now
reaps its own adopted orphans; the entry-side law this battery pins is the
same law read at the cgroup: CPU time is what the cgroup's cpu.stat says
(usage_usec delta), memory is what the cgroup's peak says, and every
process the cgroup still lists when the wrapped child exits is drained
and reaped -- never the sidecar's own pid -- before the numbers are
spoken.

Schema law: the four legacy rusage keys keep their exact contract (the
probe validator stays the authority), the v2 accounting keys are ADDITIVE
and always present, and an unreadable cgroup is written as "absent"/None
-- an honest zero is never fabricated into a missing measurement.

The cgroup surface is injectable through MSUITER_M7_CG_ROOT: the units
here drive synthetic cpu.stat / cpuacct.usage_usec / memory.peak /
tasks trees with REAL member pids (live /bin/sleep children), so the
drain-and-reap law is exercised against live processes, not a mock that
could hide a suicide or an escape. No container is contacted (D3; the
real-container re-scan is the G5 gate, controller side).

RED shape: the v2 surface (resolve_cg_root, discover_source,
read_usage_usec, read_mem_peak_bytes, read_members, drain_and_reap,
collect_accounting) does not exist yet on adapters.m7_entry -- every unit
fails red by absence until the GREEN commit lands.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))   # bench/m7
from adapters import m7_entry                                   # noqa: E402
import tools.probe_sigminer_cell_argv as probe                   # noqa: E402

ENTRY = str(Path(__file__).resolve().parents[1] / "adapters" / "m7_entry.py")


# -- fixtures ------------------------------------------------------------------

def _v2_root(td: str, *, usec: int = 1000, members=(), with_peak=None) -> Path:
    root = Path(td) / "cg2"
    root.mkdir(parents=True, exist_ok=True)
    (root / "cpu.stat").write_text(f"usage_usec {usec}\nsched_delay 0 0 0 0\n",
                                   encoding="utf-8")
    if with_peak is not None:
        (root / "memory.peak").write_text(str(with_peak), encoding="utf-8")
    (root / "memory.current").write_text("2048576", encoding="utf-8")
    _members(root / "cgroup.procs", members)
    return root


def _v1_root(td: str, *, usec: int = 1000, members=(), max_usage=None) -> Path:
    root = Path(td) / "cg1"
    root.mkdir(parents=True, exist_ok=True)
    (root / "cpuacct.usage_usec").write_text(str(usec), encoding="utf-8")
    if max_usage is not None:
        (root / "memory.max_usage_in_bytes").write_text(str(max_usage),
                                                        encoding="utf-8")
    (root / "memory.usage_in_bytes").write_text("1048576", encoding="utf-8")
    _members(root / "tasks", members)
    return root


def _members(path: Path, pids) -> None:
    path.write_text("".join(f"{int(p)}\n" for p in pids), encoding="utf-8")


def _child_bump(td: str, *, root: Path, member: int | None = None,
                final_usec: int = 3500, sleep_for: float = 0.4,
                rc: int = 0) -> list[str]:
    """A child that renames the cgroup's own bookkeeping, adopts a live
    orphan into the members file, lets the sampler observe, then exits."""
    is_v2 = (root / "cpu.stat").exists()
    members_name = "cgroup.procs" if is_v2 else "tasks"
    usec_name = "cpu.stat" if is_v2 else "cpuacct.usage_usec"
    script = Path(td) / f"child-{final_usec}-{rc}-{int(member is not None)}.py"
    lines = [
        "from pathlib import Path",
        "import subprocess, sys, time",
        f"root = Path({str(root)!r})",
    ]
    if member is not None:
        lines += [
            "p = subprocess.Popen(['/bin/sleep', '30'])",
            f"Path(root / {members_name!r}).write_text("
            "f'{p.pid}' + chr(10), encoding='utf-8')",
        ]
    lines += [
        f"time.sleep({sleep_for})",
        f"t = root / {usec_name!r}",
        "txt = t.read_text(encoding='utf-8')",
    ]
    if is_v2:
        lines += [
            "lines = [l for l in txt.splitlines() if not l.startswith('usage_usec ')]",
            f"t.write_text('usage_usec {final_usec}' + chr(10)"
            " + chr(10).join(lines) + chr(10), encoding='utf-8')",
        ]
    else:
        lines += [f"t.write_text({str(final_usec)!r}, encoding='utf-8')"]
    lines += [f"sys.exit({rc})"]
    script.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return [sys.executable, str(script)]


def _alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


# -- units -----------------------------------------------------------------------

def test_resolve_cg_root_prefers_the_injected_root():
    # MSUITER_M7_CG_ROOT is the law's testable handle -- when set it wins
    # over the platform defaults, and the default lookup runs only without it.
    with tempfile.TemporaryDirectory() as td:
        root = _v2_root(td)
        got = m7_entry.resolve_cg_root({"MSUITER_M7_CG_ROOT": str(root)})
        assert got == str(root)
        assert m7_entry.resolve_cg_root({}) in (None, str(root))  # default path, no crash


def test_v2_surface_discovery_and_parsing():
    with tempfile.TemporaryDirectory() as td:
        root = _v2_root(td, usec=1000, with_peak=9000000)
        src = m7_entry.discover_source(root)
        assert src == "v2"
        assert m7_entry.read_usage_usec(root, src) == 1000
        assert m7_entry.read_mem_peak_bytes(root, src) == 9000000
        assert m7_entry.read_members(root, src) == []


def test_v1_surface_discovery_and_parsing():
    with tempfile.TemporaryDirectory() as td:
        root = _v1_root(td, usec=2222, max_usage=8000000)
        src = m7_entry.discover_source(root)
        assert src == "v1"
        assert m7_entry.read_usage_usec(root, src) == 2222
        assert m7_entry.read_mem_peak_bytes(root, src) == 8000000


def test_absent_cgroup_is_absent_not_zero():
    with tempfile.TemporaryDirectory() as td:
        root = Path(td) / "nothing"
        root.mkdir(parents=True, exist_ok=True)
        src = m7_entry.discover_source(root)
        assert src == "absent"
        assert m7_entry.read_usage_usec(root, src) is None
        assert m7_entry.read_mem_peak_bytes(root, src) is None
        assert m7_entry.read_members(root, src) == []


def test_drain_reaps_the_live_orphan_and_never_itself():
    # The forensics shape, live: the wrapped child adopted a member (a real
    # live /bin/sleep now listed in the cgroup); the drain must SIGKILL it
    # into the measured tree and prove it dead, while the drainer's own pid
    # -- even when LISTED -- must never be reaped.
    with tempfile.TemporaryDirectory() as td:
        root = _v2_root(td, members=[os.getpid()])          # self is listed
        victim = subprocess.Popen(["/bin/sleep", "30"])
        _members(root / "cgroup.procs", [os.getpid(), victim.pid])
        res = m7_entry.drain_and_reap(root, "v2", os.getpid(),
                                      deadline_seconds=1.5)
        assert isinstance(res["reaped"], list)
        assert victim.pid in res["reaped"]
        assert os.getpid() not in res["reaped"]              # self-exclusion law
        assert not _alive(victim.pid)                        # census-dead proof
        assert _alive(os.getpid())                           # and still us
        assert res["resisters"] == []
        assert res["polls"] >= 1


def test_drain_only_targets_listed_members():
    # An unlisted live process is NOT the drain's business (it escaped the
    # cgroup's own census -- that is the container's undercount, spoken by
    # the G5 delta law, not invented here).
    with tempfile.TemporaryDirectory() as td:
        root = _v2_root(td, members=[])
        bystander = subprocess.Popen(["/bin/sleep", "30"])
        try:
            res = m7_entry.drain_and_reap(root, "v2", os.getpid(),
                                          deadline_seconds=0.5)
            assert res["reaped"] == []
            assert _alive(bystander.pid)
        finally:
            bystander.kill()
            bystander.wait()


def test_collect_accounting_reads_the_cgroups_delta_not_a_mock():
    # The usage_usec delta is read from the cgroup around the real child:
    # the child renames its own cgroup bookkeeping 1000 -> 3500 while it
    # runs, and the accounting must speak 2500.
    with tempfile.TemporaryDirectory() as td:
        root = _v2_root(td, usec=1000, with_peak=9000000)
        argv = _child_bump(td, root=root, member=None, final_usec=3500)
        acc = m7_entry.collect_accounting(argv, cg_root=root,
                                          deadline_seconds=1.5)
        assert acc["cgroup_source"] == "v2"
        assert acc["cgroup_cpu_usec"] == 2500
        assert acc["cgroup_memory_peak_bytes"] == 9000000
        assert "rss_peak_bytes" in acc                        # schema, always
        assert acc["cgroup_reaped_pids"] == []
        assert acc["exit_status"] == 0


def test_collect_accounting_adopts_and_reaps_under_the_undercount_law():
    # Full forensics shape end-to-end inside one collect: the child adopts
    # a live orphan into the member census, the collect must have the
    # orphan SIGKILLed and census-dead by the time it returns.
    with tempfile.TemporaryDirectory() as td:
        root = _v2_root(td, usec=1000)
        argv = _child_bump(td, root=root, member=1, final_usec=4000)
        acc = m7_entry.collect_accounting(argv, cg_root=root,
                                          deadline_seconds=2.0)
        reaped = acc["cgroup_reaped_pids"]
        assert len(reaped) == 1
        assert not _alive(reaped[0])
        # memory peak from the observed memory.current (no peak file here):
        assert acc["cgroup_memory_peak_bytes"] == 2048576
        assert acc["cgroup_cpu_usec"] == 3000


def test_v2_sidecar_stays_valid_under_the_frozen_probe_validator():
    # Additive-only law: a timing.json carrying the legacy four keys plus
    # the v2 accounting keys must pass the UNCHANGED validator; and the
    # absent-cgroup leg still speaks schema (None-valued, never fabricated).
    with tempfile.TemporaryDirectory() as td:
        root = Path(td) / "empty-cg"
        root.mkdir(parents=True, exist_ok=True)
        out = Path(td) / "out"
        argv = [sys.executable, "-c", "pass"]
        rc = subprocess.run([sys.executable, ENTRY, "--params",
                            _params(td), "--outdir", str(out), "--",
                            *argv],
                            env={**os.environ, "MSUITER_M7_CG_ROOT": str(root)},
                            capture_output=True, text=True)
        assert rc.returncode == 0
        timing = json.loads((out / "timing.json").read_text(encoding="utf-8"))
        assert timing["exit_status"] == 0
        assert timing["cgroup_source"] == "absent"
        for key in ("ru_utime", "ru_stime", "cpu_seconds", "exit_status",
                    "accounting_version", "cgroup_source", "cgroup_cpu_usec",
                    "cgroup_memory_peak_bytes", "rss_peak_bytes",
                    "cgroup_reaped_pids", "cgroup_drain_polls"):
            assert key in timing, key
        assert probe.validate_sidecar(out / "timing.json") is None


def test_entry_end_to_end_with_the_injected_cgroup():
    # The whole entry under MSUITER_M7_CG_ROOT: real child, real adopted
    # orphan, injected cgroup; the sidecar must speak the delta, name the
    # reaped pid, and the child's exit status must pass through.
    with tempfile.TemporaryDirectory() as td:
        root = _v2_root(td, usec=500)
        out = Path(td) / "out"
        argv = _child_bump(td, root=root, member=1, final_usec=6400, rc=0)
        env = {**os.environ, "MSUITER_M7_CG_ROOT": str(root)}
        rc = subprocess.run([sys.executable, ENTRY, "--params", _params(td),
                            "--outdir", str(out), "--", *argv],
                            env=env, capture_output=True, text=True)
        assert rc.returncode == 0, rc.stderr
        timing = json.loads((out / "timing.json").read_text(encoding="utf-8"))
        assert timing["cgroup_cpu_usec"] == 5900
        assert len(timing["cgroup_reaped_pids"]) == 1
        assert not _alive(timing["cgroup_reaped_pids"][0])
        assert timing["accounting_version"] == 2
        assert probe.validate_sidecar(out / "timing.json") is None
        # Nonzero child exit passes through and the validator sees it.
        argv3 = _child_bump(td, root=_v2_root(td, usec=500, members=[]),
                            member=None, final_usec=9, rc=3)
        rc3 = subprocess.run([sys.executable, ENTRY, "--params", _params(td),
                             "--outdir", str(out), "--", *argv3],
                             env={**os.environ,
                                  "MSUITER_M7_CG_ROOT": str(root)},
                             capture_output=True, text=True)
        assert rc3.returncode == 3
        timing3 = json.loads((out / "timing.json").read_text(encoding="utf-8"))
        assert timing3["exit_status"] == 3
        reason = probe.validate_sidecar(out / "timing.json")
        assert reason is not None and "exit_status" in reason


def _params(td: str) -> str:
    p = Path(td) / "params.json"
    p.write_text("{}", encoding="utf-8")
    return str(p)
