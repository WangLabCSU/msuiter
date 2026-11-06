"""The coex inversion-probe rig (Phase-D, controller ruling 2026-11-04):
the flatness law's missing PRODUCER — DEBT-COEX-PRODUCER closed it.

The pre-rig state: attestation.coex_record_ok admitted self-reported shape,
so a hand-written record qualified any witness on any machine (the banked
state C of the Phase-C adjudication). This module puts an author in front
of the record:

  build_record   the emit path: the verdict, the deltas and the solo mean
                 are DERIVED from the leg bytes, the record is BOUND to the
                 image/campaign/cell/host it was measured on, sealed with a
                 self-consistency digest, and self-checked against the very
                 teeth of attestation.coex_record_ok — the rig refuses to
                 mint an unlawful face;
  book_ledger    the double-entry half: every record is booked into
                 coex_ledger.jsonl beside the file, the rig as sole author;
  reseal         the forensic seam for the law's own battery: re-digest
                 WITHOUT re-validating, isolating the derived-face teeth
                 from the seal-consistency teeth (the emit path never lets
                 the same tamper past the rig's own mouth);
  measure_*      the campaign face: N=3 deliberate co-tenancy legs launched
                 together through the adapter's own build_container_cmd
                 (minus --rm: the ids must survive for the live replay),
                 against the serial solo baseline, reading each leg's timing
                 sidecar. Controller-triggered; the battery never opens a
                 container (the legs are injected synthetic bytes).

No cryptographic anti-forgery here: the teeth raise the forgery cost above
the rig cost (structural binding + double entry + daemon replay), and the
cryptographic-grade variant stays named in the debt file awaiting its own
ruling.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import tools.attestation as att
from competitors import docker_cmd

RIG_ID = "coex-inversion-rig/1"


class RigError(RuntimeError):
    """The rig refuses to emit: the record it was asked to sign is
    inadmissible. The reason bytes are coex_record_ok's, verbatim — the rig
    and the gate speak one law."""


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace(
        "+00:00", "Z")


def _derive(solo_legs: list[dict], cohort_legs: list[dict],
            bar_pct: float) -> tuple[float, list[float], str]:
    """The honest face of the measurement: mean-over-solo, one decimal, and
    the gate verdict the deltas dictate."""
    if not solo_legs:
        return 0.0, [], "NOT-FLAT"        # no baseline: the teeth will refuse
    solo_mean = sum(l["wall_s"] for l in solo_legs) / len(solo_legs)
    deltas = [round(100.0 * (l["wall_s"] - solo_mean) / solo_mean, 1)
              for l in cohort_legs]
    verdict = "FLAT" if deltas and max(deltas) <= bar_pct else "NOT-FLAT"
    return round(solo_mean, 6), deltas, verdict


def build_record(*, tool: str, arm: str, n: int, reps: int,
                 campaign: str, image: dict, solo_legs: list[dict],
                 cohort_legs: list[dict], cell_argv: list[str],
                 host: dict, provider: str = "synthetic",
                 provider_seed: str = "0", bar_pct: float = att.COEX_BAR_PCT,
                 measured_utc: str, rig: str = RIG_ID) -> dict:
    """One lawful inversion-probe record, or a RigError naming the defect.

    The typed columns do not exist here: solo_mean_s, deltas_pct, verdict
    and the shape token are computed from the leg bytes, and the emit path
    self-checks against attestation.coex_record_ok before handing anything
    out — the rig cannot speak a face the gate would refuse."""
    if not str(campaign or ""):
        raise RigError("the rig measures for a campaign — name it")
    produced = str(measured_utc)
    solo_mean, deltas, verdict = _derive(solo_legs, cohort_legs, bar_pct)
    bind = {
        "rig": rig, "campaign": campaign, "image": dict(image),
        "cell": {"tool": tool, "arm": arm, "n": int(n), "reps": int(reps),
                 "cell_argv": list(cell_argv)},
        "host": dict(host),
        "inspect": [{"container_id": l.get("container_id", ""),
                     "started": _real_iso(l, "start_real_ns"),
                     "finished": _real_iso(l, "stop_real_ns")}
                    for l in cohort_legs],
        "ledger_entry": {"produced_utc": produced, "rig": rig},
    }
    rec = {"schema": 1,
           "shape": f"{att.COEX_SHAPE_PREFIX}N={len(cohort_legs)}",
           "legs": [dict(l) for l in cohort_legs],
           "solo_legs": [dict(l) for l in solo_legs],
           "solo_mean_s": solo_mean, "deltas_pct": deltas,
           "bar_pct": bar_pct, "verdict": verdict,
           "measured_utc": produced, "provider": provider,
           "provider_seed": provider_seed, "bind": bind}
    rec = att.coex_seal(rec)
    reason = att.coex_record_ok(rec)
    if reason is not None:
        raise RigError(reason)
    return rec


def _real_iso(leg: dict, col: str) -> str:
    ns = (leg.get("clock") or {}).get(col)
    if not isinstance(ns, int):
        return ""
    return datetime.fromtimestamp(ns / 1e9, timezone.utc).isoformat(
        timespec="seconds").replace("+00:00", "Z")


def reseal(rec: dict) -> dict:
    """Re-digest a mutated record WITHOUT re-validating — the forensic seam
    the law's battery uses to isolate one tooth at a time. Not a production
    face: the emit path is build_record."""
    return att.coex_seal(dict(rec))


def ledger_path(dir_path) -> Path:
    return Path(dir_path) / att.COEX_LEDGER_NAME


def book_ledger(dir_path, rec: dict) -> Path:
    """The rig books the record beside its file — the ledger line carries
    the rig identity, so a hand-written booking is recognisable as one."""
    p = ledger_path(dir_path)
    p.parent.mkdir(parents=True, exist_ok=True)
    entry = {"produced_utc": rec["bind"]["ledger_entry"]["produced_utc"],
             "rig": rec["bind"]["ledger_entry"]["rig"],
             "record_sha256": rec[att.COEX_SEAL_COL]}
    with p.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(entry, sort_keys=True) + "\n")
    return p


# -- campaign face (controller-triggered; no test opens a container) -------

def host_identity(image_ref: str) -> dict:
    """The machine the measurement is taken on, read through the daemon:
    boot id, kernel release, cgroup — never typed from a template."""
    cp = subprocess.run(
        ["docker", "run", "--rm", "--entrypoint", "sh", image_ref, "-c",
         "cat /proc/sys/kernel/random/boot_id; uname -r; "
         "tail -n 1 /proc/self/cgroup"],
        capture_output=True, text=True, timeout=120)
    if cp.returncode != 0:
        raise RigError(f"host identity unreadable: {cp.stderr.strip()!r}")
    lines = cp.stdout.splitlines()
    if len(lines) < 3:
        raise RigError("host identity spoke an incomplete face")
    return {"boot_id": lines[0].strip(),
            "kernel_release": lines[1].strip(),
            "cgroup": lines[2].strip()}


def _launch_cmd(image_ref: str, runner: str, in_dir: Path, out_dir: Path,
                name: str, argv: list[str]) -> list[str]:
    """The adapter's own compose (caps, mounts, one image token, entrypoint)
    reshaped for the probe: no --rm (the container id must survive for the
    T6 replay), detached, named."""
    cmd = [c for c in docker_cmd.build_container_cmd(
        image_ref, runner, in_dir, out_dir, runner_args=argv)
        if c != "--rm"]
    cmd[1:1] = ["-d", "--name", name]
    return cmd


def _leg_from_daemon(name: str, out_dir: Path, t0_mono: int,
                     t1_mono: int) -> dict:
    """One measured leg: the daemon's clock pair, the cell's own timing
    sidecar, the host monotonic witness around the launch."""
    cp = subprocess.run(
        ["docker", "inspect", "--format", "{{json .State}}", name],
        capture_output=True, text=True, timeout=60)
    if cp.returncode != 0:
        raise RigError(f"leg {name!r} is not in the daemon — no silent leg")
    state = json.loads(cp.stdout)
    started = state.get("StartedAt") or ""
    finished = state.get("FinishedAt") or ""
    if not started or not finished or "0001-01-01" in finished:
        raise RigError(f"leg {name!r} reports no measured daemon clock face")
    sidecar = out_dir / "timing.json"
    try:
        face = json.loads(sidecar.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        raise RigError(f"leg {name!r} left no timing sidecar — a leg "
                       "without its measured face is absence, not zero")
    wall = float(face.get("wall_seconds") or 0.0)
    cpu = float(face.get("cpu_seconds") or 0.0)
    if not wall > 0 or not cpu > 0:
        raise RigError(f"leg {name!r} sidecar face is not positive: {face!r}")
    cid = subprocess.run(["docker", "inspect", "--format", "{{.Id}}", name],
                         capture_output=True, text=True,
                         timeout=60).stdout.strip()
    real0 = int(datetime.fromisoformat(started).timestamp() * 1e9)
    real1 = int(datetime.fromisoformat(finished).timestamp() * 1e9)
    return {"probe": name, "wall_s": wall, "cpu_s": cpu,
            "container_id": cid,
            "clock": {"start_mono_ns": t0_mono, "stop_mono_ns": t1_mono,
                      "start_real_ns": real0, "stop_real_ns": real1}}


def measure_legs(*, image_ref: str, runner: str, in_dir: Path,
                 out_root: Path, argv: list[str], reps: int,
                 cohort: bool) -> list[dict]:
    """Serial solo legs (cohort=False) or the N=3 deliberate co-tenancy
    launch: every cohort container started before the first is awaited, so
    the windows genuinely share the machine."""
    n = att.COEX_MIN_LEGS if cohort else 1
    tag = f"coex-{'cohort' if cohort else 'solo'}-{reps}-{int(time.time())}"
    legs: list[dict] = []
    if not cohort:
        for i in range(n):
            name, out_dir = f"{tag}-r{i}", out_root / f"r{i}"
            out_dir.mkdir(parents=True, exist_ok=True)
            t0 = time.monotonic_ns()
            subprocess.run(_launch_cmd(image_ref, runner, in_dir, out_dir,
                                       name, argv),
                           capture_output=True, text=True, timeout=86400,
                           check=True)
            legs.append(_leg_from_daemon(name, out_dir, t0,
                                        time.monotonic_ns()))
        return legs
    handles = []
    for i in range(n):
        name, out_dir = f"{tag}-r{i}", out_root / f"r{i}"
        out_dir.mkdir(parents=True, exist_ok=True)
        t0 = time.monotonic_ns()
        subprocess.run(_launch_cmd(image_ref, runner, in_dir, out_dir,
                                   name, argv),
                       capture_output=True, text=True, timeout=600,
                       check=True)
        handles.append((name, out_dir, t0))
    # co-tenancy is spoken by the launch shape: every container is live
    # before the first one is awaited, then the legs retire one by one.
    for name, out_dir, t0 in handles:
        subprocess.run(["docker", "wait", name], capture_output=True,
                       text=True, timeout=86400, check=True)
    return [_leg_from_daemon(name, out_dir, t0, time.monotonic_ns())
            for name, out_dir, t0 in handles]


def emit(*, tool: str, arm: str, n: int, reps: int, campaign: str,
         image: dict, in_dir: Path, out_root: Path, runner: str,
         cell_argv: list[str], measured_utc: str | None = None) -> dict:
    """The full producer run: host identity, serial baseline, deliberate
    cohort, bound+sealed record, booked beside the file. Campaign-side
    entry — the battery drives build_record directly."""
    host = host_identity(image["ref"])
    solo = measure_legs(image_ref=image["ref"], runner=runner,
                        in_dir=Path(in_dir), out_root=out_root / "solo",
                        argv=cell_argv, reps=reps, cohort=False)
    cohort = measure_legs(image_ref=image["ref"], runner=runner,
                          in_dir=Path(in_dir), out_root=out_root / "cohort",
                          argv=cell_argv, reps=reps, cohort=True)
    rec = build_record(tool=tool, arm=arm, n=n, reps=reps,
                       campaign=campaign, image=image, solo_legs=solo,
                       cohort_legs=cohort, cell_argv=cell_argv, host=host,
                       measured_utc=measured_utc or _now_iso())
    out_root.mkdir(parents=True, exist_ok=True)
    out = out_root / f"coex_{tool}_{arm}_N{n}_REP{reps}.json"
    out.write_text(json.dumps(rec, sort_keys=True), encoding="utf-8")
    book_ledger(out_root, rec)
    return rec


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="coex_inversion_probe")
    ap.add_argument("--tool", required=True)
    ap.add_argument("--arm", required=True)
    ap.add_argument("--n", type=int, required=True)
    ap.add_argument("--reps", type=int, required=True)
    ap.add_argument("--campaign", required=True)
    ap.add_argument("--image-ref", required=True)
    ap.add_argument("--image-digest", required=True)
    ap.add_argument("--in-dir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--runner", default="m7_entry.py")
    ap.add_argument("--cell-argv", default=None,
                    help="JSON list; defaults to the adapter quad")
    ap.add_argument("--yes-cohort", action="store_true",
                    help="spoken gate: this run launches real co-tenancy")
    ap.add_argument("--dry-run", action="store_true",
                    help="print the launch plan, launch nothing")
    ns = ap.parse_args(argv)
    if ns.dry_run:
        print(json.dumps([_launch_cmd(ns.image_ref, ns.runner,
                                      Path(ns.in_dir), Path(ns.out) / f"r{i}",
                                      f"plan-r{i}", ns.cell_argv and
                                      json.loads(ns.cell_argv) or [])
                          for i in range(att.COEX_MIN_LEGS)], indent=1))
        return 0
    if not ns.yes_cohort:
        print("coex rig: the deliberate co-tenancy launch is a spoken "
              "decision — pass --yes-cohort", file=sys.stderr)
        return 2
    cell_argv = (json.loads(ns.cell_argv) if ns.cell_argv else
                 ["--counts", "/work/in/counts.csv",
                  "--catalog", "/work/in/catalog.csv",
                  "--params", "/work/in/params.json", "--outdir",
                  "/work/out"])
    rec = emit(tool=ns.tool, arm=ns.arm, n=ns.n, reps=ns.reps,
               campaign=ns.campaign,
               image={"ref": ns.image_ref, "digest": ns.image_digest},
               in_dir=Path(ns.in_dir), out_root=Path(ns.out),
               runner=ns.runner, cell_argv=cell_argv)
    print(json.dumps({"emitted": rec["measured_utc"],
                      "record_sha256": rec[att.COEX_SEAL_COL],
                      "verdict": rec["verdict"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
