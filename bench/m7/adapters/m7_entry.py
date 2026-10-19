#!/usr/bin/env python3
"""Shared measurement entry — the single argv[1] every M7 cell runs.

In the container this is what the ``docker run`` command invokes
(``competitors/docker_cmd.py::ENTRY_SCRIPT``); the mock path drives the very
same script host-side so the timing surface is identical (memo §4.3).

Contract:
  m7_entry.py --params <params.json> --outdir <out/> -- <child argv...>

It launches the competitor's real runner as its single child, reaps it via
``os.wait4`` so the child-tree rusage (ru_utime + ru_stime) is attributed
here — the CPU column is container-reported, never a host-side guess — and
writes ``<out>/timing.json`` deterministically:

  {"ru_utime": ..., "ru_stime": ..., "cpu_seconds": ..., "exit_status": ...}

The sidecar carries no wall clock and no paths: the fairness attestation
needs the numbers to be re-derivable, and shard-vs-serial byte-equality of
the cell outputs must not hinge on when or where the cell ran (wall seconds
belong to the timings table, measured host-side around the invocation).

Accounting v2 (PERF P2, pair S). The forensics Q3 census caught this rusage
route UNDERCOUNTING: orphaned workers (PPID=1) left the os.wait4 child tree
and escaped attribution (sidecar 2.058 vs container 3.69 concurrent on the
same run). The v2 keys answer at the cgroup, which no orphan can escape:

  {"accounting_version": 2, "cgroup_source": "v2"|"v1"|"absent",
   "cgroup_cpu_usec": ..., "cgroup_memory_peak_bytes": ...,
   "rss_peak_bytes": ..., "cgroup_reaped_pids": [...],
   "cgroup_drain_polls": ...}

``cgroup_cpu_usec`` is the cgroup's own cpu.stat usage_usec delta across the
child's lifetime (v1: cpuacct.usage_usec); the memory peak is the cgroup's
peak (v2 memory.peak, v1 memory.max_usage_in_bytes, falling back to the
observed memory.current / memory.usage_in_bytes samples); every process the
cgroup still lists when the child is reaped — except this sidecar's own pid,
never — is drained and SIGKILLed into the measured tree before the numbers
are read (the no-undercount law; the P2 farm mirrors it for its adoptions).
An unreadable cgroup is spoken as "absent"/None, never a fabricated zero.
The four legacy keys keep their exact contract and the probe validator is
the unchanged authority: the v2 keys are strictly additive.

The cgroup root is injectable through MSUITER_M7_CG_ROOT (the testable
handle; the platform defaults /sys/fs/cgroup2 then /sys/fs/cgroup ride
behind it).
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

ACCOUNTING_VERSION = 2
CG_ROOT_ENV = "MSUITER_M7_CG_ROOT"
DEFAULT_CG_ROOTS = ("/sys/fs/cgroup2", "/sys/fs/cgroup")
# The dialect carries no WNOHANGUP name; the non-blocking bit is the same
# 0x1 on both platforms (probe-banked green log; host-side census runs).
_WNOHANGUP = getattr(os, "WNOHANGUP", 1)


def resolve_cg_root(environ) -> str | None:
    """The cgroup root to read: the injected one wins outright; otherwise
    the first platform default that speaks a cgroup face, else None."""
    injected = str(environ.get(CG_ROOT_ENV, "") or "")
    if injected:
        return injected
    for cand in DEFAULT_CG_ROOTS:
        if discover_source(cand) != "absent":
            return cand
    for cand in DEFAULT_CG_ROOTS:
        if Path(cand).exists():
            return cand
    return None


def discover_source(root) -> str:
    """Which cgroup face ``root`` speaks: "v2" (cpu.stat / memory.current),
    "v1" (cpuacct.usage_usec / memory.usage_in_bytes) or "absent"."""
    if root is None:
        return "absent"
    root = Path(root)
    if (root / "cpu.stat").exists() or (root / "memory.current").exists():
        return "v2"
    if ((root / "cpuacct.usage_usec").exists()
            or (root / "memory.usage_in_bytes").exists()):
        return "v1"
    return "absent"


def _read_int(path: Path) -> int | None:
    try:
        text = path.read_text(encoding="utf-8").strip()
    except OSError:
        return None
    token = text.split()[0] if text else ""
    try:
        return int(token)
    except ValueError:
        return None


def read_usage_usec(root, source: str) -> int | None:
    """The cgroup's cumulative CPU use in microseconds, from its own
    bookkeeping (v2 cpu.stat usage_usec line; v1 cpuacct.usage_usec)."""
    if root is None or source == "absent":
        return None
    root = Path(root)
    if source == "v2":
        try:
            for line in (root / "cpu.stat").read_text(
                    encoding="utf-8").splitlines():
                fields = line.split()
                if fields and fields[0] == "usage_usec" and len(fields) > 1:
                    try:
                        return int(fields[1])
                    except ValueError:
                        return None
        except OSError:
            return None
        return None
    return _read_int(root / "cpuacct.usage_usec")


def read_mem_peak_bytes(root, source: str,
                        observed: int | None = None) -> int | None:
    """The cgroup's memory peak: the kernel-tracked peak file when present
    (v2 memory.peak, v1 memory.max_usage_in_bytes), else the highest value
    the sampler observed of the current-usage file, else None."""
    if root is None or source == "absent":
        return None
    root = Path(root)
    peak_name = "memory.peak" if source == "v2" else "memory.max_usage_in_bytes"
    peak = _read_int(root / peak_name)
    if peak is not None:
        return peak
    return observed


def read_members(root, source: str) -> list[int]:
    """The pids the cgroup itself lists (v2 cgroup.procs, v1 tasks)."""
    if root is None or source == "absent":
        return []
    name = "cgroup.procs" if source == "v2" else "tasks"
    try:
        text = (Path(root) / name).read_text(encoding="utf-8")
    except OSError:
        return []
    members = []
    for line in text.splitlines():
        try:
            members.append(int(line.strip()))
        except ValueError:
            continue
    return members


def _pid_alive(pid: int) -> bool:
    """Census aliveness: a killed member of the measured tree is DEAD the
    moment it is reaped, so the sidecar first harvests its own zombies --
    kill(pid, 0) answers success for an unreaped zombie, and a zombie still
    holds its cgroup, so an un-harvested kill would masquerade as an
    un-killable resister."""
    if pid <= 0:
        return False
    try:
        # The dialect answers a polled wait4 with (0, ...) rather than
        # raising when nothing was harvested: only a harvest of THIS pid
        # proves "ours and dead" (probe-banked host quirk).
        if os.wait4(pid, _WNOHANGUP)[0] == pid:
            return False               # ours and dead: harvested, fully gone
    except OSError:
        pass                           # not ours (ECHILD)
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except OSError:
        return True                      # exists, not ours to signal: alive


def drain_and_reap(root, source: str, self_pid: int, *,
                   deadline_seconds: float = 2.0,
                   interval: float = 0.05) -> dict:
    """Drain the cgroup's member census to stable and reap.

    Poll until every listed member except ``self_pid`` has left the world
    (the drain), or the deadline passes; anything still live then gets
    SIGKILLed and is poll-verified dead. ``self_pid`` is untouchable by
    construction: a sidecar that can report after killing its own
    measurement is the worse failure. Returns
    ``{"reaped": [...], "resisters": [...], "polls": n}``.
    """
    if source == "absent":
        return {"reaped": [], "resisters": [], "polls": 1}
    polls = 0
    deadline = time.monotonic() + deadline_seconds
    while True:
        targets = [p for p in read_members(root, source)
                   if p != self_pid and _pid_alive(p)]
        polls += 1
        if not targets or time.monotonic() >= deadline:
            break
        time.sleep(interval)
    reaped: list[int] = []
    resisters: list[int] = []
    killed = list(targets)
    for pid in killed:
        try:
            os.kill(pid, 9)
        except OSError:
            pass
    for _ in range(40):
        if not any(_pid_alive(p) for p in killed):
            break
        time.sleep(interval)
    for pid in killed:
        if _pid_alive(pid):
            resisters.append(pid)
        else:
            reaped.append(pid)
    return {"reaped": reaped, "resisters": resisters, "polls": polls}


def _rss_peak_of_member(pid: int) -> int | None:
    try:
        for line in Path(f"/proc/{pid}/status").read_text(
                encoding="utf-8").splitlines():
            if line.startswith("VmHWM:"):
                fields = line.split()
                return int(fields[1]) * 1024        # VmHWM is pages of KiB
    except OSError:
        return None
    return None


def collect_accounting(child_argv: list[str], *, cg_root=None, environ=None,
                       self_pid: int | None = None,
                       deadline_seconds: float = 2.0,
                       sampler_interval: float = 0.05) -> dict:
    """Run the child under the full measurement law and return the whole
    timing payload (legacy four keys + the additive v2 accounting keys).

    The cgroup's CPU counter is read around the child; while the child
    runs a sampler thread observes the memory-usage face and the members'
    RSS high-water marks; after the os.wait4 reap the member census is
    drained and reaped, and the counters are read a second time.
    """
    if environ is None:
        environ = os.environ
    root = Path(cg_root) if cg_root is not None else resolve_cg_root(environ)
    source = discover_source(root)
    root_for_read = root
    usec0 = read_usage_usec(root_for_read, source)
    mem_name = ("memory.current" if source == "v2"
                else "memory.usage_in_bytes" if source == "v1" else None)
    observed = {"mem": None, "rss": None}
    stop = threading.Event()

    def _pump():
        while not stop.wait(sampler_interval):
            if root_for_read is None or mem_name is None:
                continue
            try:
                mem = _read_int(Path(root_for_read) / mem_name)
            except OSError:
                mem = None
            if mem is not None and (observed["mem"] is None or mem > observed["mem"]):
                observed["mem"] = mem
            for pid in read_members(root_for_read, source):
                rss = _rss_peak_of_member(pid)
                if rss is not None and (observed["rss"] is None
                                        or rss > observed["rss"]):
                    observed["rss"] = rss

    sampler = threading.Thread(target=_pump, daemon=True)
    sampler.start()
    proc = subprocess.Popen(child_argv)
    _pid, raw, ru = os.wait4(proc.pid, 0)          # we reap: rusage is ours
    if os.WIFSIGNALED(raw):
        exit_status = 128 + os.WTERMSIG(raw)
    else:
        exit_status = os.WEXITSTATUS(raw)
    stop.set()
    sampler.join(timeout=2 * sampler_interval + 1.0)
    drain = drain_and_reap(root_for_read, source,
                           self_pid if self_pid is not None else os.getpid(),
                           deadline_seconds=deadline_seconds)
    usec1 = read_usage_usec(root_for_read, source)
    delta = (usec1 - usec0
             if usec0 is not None and usec1 is not None else None)
    return {
        "ru_utime": ru.ru_utime, "ru_stime": ru.ru_stime,
        "cpu_seconds": ru.ru_utime + ru.ru_stime,
        "exit_status": exit_status,
        "accounting_version": ACCOUNTING_VERSION,
        "cgroup_source": source,
        "cgroup_cpu_usec": delta,
        "cgroup_memory_peak_bytes": read_mem_peak_bytes(
            root_for_read, source, observed=observed["mem"]),
        "rss_peak_bytes": observed["rss"],
        "cgroup_reaped_pids": drain["reaped"],
        "cgroup_drain_polls": drain["polls"],
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--params", required=True)
    ap.add_argument("--outdir", required=True)
    ap.add_argument("child", nargs=argparse.REMAINDER)
    args = ap.parse_args()
    argv = list(args.child)
    if argv and argv[0] == "--":
        argv = argv[1:]
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    if not argv:
        (outdir / "timing.json").write_text(json.dumps(
            {"ru_utime": 0.0, "ru_stime": 0.0, "cpu_seconds": 0.0,
             "exit_status": 2, "error": "empty child argv"},
            sort_keys=True, indent=1), encoding="utf-8")
        print("m7_entry: no child argv after '--'", file=sys.stderr)
        return 2

    timing = collect_accounting(argv)
    (outdir / "timing.json").write_text(
        json.dumps(timing, sort_keys=True, indent=1), encoding="utf-8")
    return timing["exit_status"]


if __name__ == "__main__":
    raise SystemExit(main())
