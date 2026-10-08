#!/usr/bin/env python3
"""U-M7-02 competitor benchmark orchestrator (design memo §4/§6).

Pipeline idiom inherited verbatim from ``bench/g0/run_grid.py``:
generation → adapter → parse → table → authoritative pass. The cell
contract is ``in/{counts.csv,catalog.csv,params.json,.data_hash}``
(read-only to the container) and
``out/{intervals.csv,errors.log,manifest.json,timing.json}``.

Fairness discipline (§4): every competitor executes as a container on the
same Docker VM with the frozen thread caps injected before the image token
(``competitors.docker_cmd``), and every measured second lands in the
timings table (wall = host-side subprocess measurement, CPU = the
container-side rusage sidecar).

Cache discipline (§4.4, stricter than G0): a cell is trusted only when the
``.data_hash`` over (counts bytes, arm params, competitor identity+version,
caps) matches **and** all four out/ guard files are present — the fairness
table is not attestable without the manifest/timing sidecars. Missing any
one ⇒ re-run, never trust.

Inputs come from the frozen G0 simulator via read-only ``sys.path``
import; this harness never writes to, and never even references, the G0
cache tree (its own cache is ``bench/m7/cache/``, gitignored) and adds no
COSMIC/user data (D3).

Usage:
  python3 run_bench.py --profile smoke --adapter mock --competitors mock \
      --cachedir cache/smoke --outdir results/smoke
  python3 run_bench.py --profile degraded --adapter docker \
      --competitors sigminer,sigprofiler --arms main
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib
import io
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent                       # bench/m7
G0_DIR = HERE.parent / "g0"                                  # frozen, read-only
for _p in (str(HERE), str(G0_DIR)):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from competitors import docker_cmd, mock_adapter, registry   # noqa: E402
from competitors.errors import AdapterUnavailable            # noqa: E402
from competitors import timings                              # noqa: E402
from g0 import grid, seeds, sim                              # noqa: E402
from g0.providers import ProviderError, provider_by_name    # noqa: E402

# The four-file re-run guard (stricter than G0's two-file guard, §4.4).
GUARD_FILES = ("intervals.csv", "errors.log", "manifest.json", "timing.json")
# M7 tool-seed namespace: cannot collide with G0's "g0/v1|tool|..." streams.
M7_TOOL_NS = "m7-tool"


def parse_args(argv=None) -> argparse.Namespace:
    """Argument idiom mirrored from run_grid.py (see module docstring)."""
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--profile", default="smoke",
                    choices=["smoke", "primary", "degraded"])
    ap.add_argument("--adapter", default="mock", choices=["mock", "docker"])
    ap.add_argument("--provider", default="synthetic",
                    choices=["synthetic", "cosmic-file"])
    ap.add_argument("--competitors", default="sigminer,sigprofiler,signal",
                    help="comma-separated names from the registry "
                         "('mock' additionally resolves under --adapter mock)")
    ap.add_argument("--arms", default=None,
                    help="comma-separated arm filter (sharding hook, as in G0)")
    ap.add_argument("--reps", type=int, default=None,
                    help="override repetition count (profile default otherwise)")
    ap.add_argument("--provider-seed", type=int, default=0,
                    help="synthetic provider seed (cosmic-file ignores it)")
    ap.add_argument("--cachedir", default=str(HERE / "cache"))
    ap.add_argument("--outdir", default=str(HERE / "results"))
    ap.add_argument("--force-rerun", action="store_true",
                    help="ignore cached cell outputs, re-invoke every cell")
    ap.add_argument("--shard-tag", default=None,
                    help="suffix for the timings file name (sharded driver)")
    ap.add_argument("--n-list", default=None, dest="n_list",
                    help="comma-separated N-point filter (pilot/shard "
                         "selection; per-arm intersection, mirrors --arms)")
    ap.add_argument("--dry-run", action="store_true", dest="dry_run",
                    help="print the machine-readable matrix plan (JSON) and "
                         "exit 0 without touching the filesystem")
    return ap.parse_args(argv)


def git_sha() -> str:
    """Commit provenance for the manifests/Seeds note (G0 P2d discipline);
    recorded as 'unknown' off a git context rather than invented."""
    try:
        out = subprocess.run(["git", "rev-parse", "HEAD"], cwd=str(HERE),
                             capture_output=True, text=True, check=True)
        return out.stdout.strip()
    except Exception:                                        # noqa: BLE001
        return "unknown"


def sample_id(arm: str, n: int, rep: int) -> str:
    return f"{arm}__N{n}__r{rep}"


def m7_seeds(competitor: str, arm: str, n: int, reps: int) -> tuple[int, dict]:
    """Batch anchor + per-sample map for the tool stream (§3 seeds discipline).

    Labels are namespaced ``m7-tool|<competitor>|<arm>|N<n>|r<k>`` through
    the frozen ``g0.seeds.derive_seed`` (FNV-1a + SplitMix64 over master
    20260928), folded to the int32 tool-seed domain exactly as G0's
    ``tool_seed`` does — data streams stay the untouched G0 ones.
    """
    batch = seeds.derive_seed(M7_TOOL_NS, competitor, arm, f"N{n}") \
        % seeds.TOOL_SEED_CAP
    samples = {sample_id(arm, n, r):
               seeds.derive_seed(M7_TOOL_NS, competitor, arm, f"N{n}", f"r{r}")
               % seeds.TOOL_SEED_CAP
               for r in range(reps)}
    return batch, samples


def build_plan(args, competitor_names: list, specs: dict, arms) -> dict:
    """The selected matrix as data (U-M7-03 --dry-run): the exact invocation
    set a full pass would execute plus the frozen fairness/provenance context
    (caps, master seed, tool namespace, image refs and digests). Pure
    function — no filesystem, no subprocess; commit provenance is stamped by
    the caller."""
    cells = [{"tool": name, "arm": a.name, "n": n, "reps": a.reps}
             for name in competitor_names
             for a in arms for n in a.n_list]
    return {
        "profile": args.profile, "adapter": args.adapter,
        "provider": args.provider, "provider_seed": args.provider_seed,
        "competitors": list(competitor_names),
        "caps": list(docker_cmd.THREAD_CAPS),
        "master_seed": seeds.MASTER_SEED, "tool_namespace": M7_TOOL_NS,
        "cells": cells, "invocations": len(cells),
        "samples_total": sum(c["reps"] for c in cells),
        "provenance": {name: {"version": specs[name].version,
                              "image_ref": specs[name].image_ref,
                              "image_digest": specs[name].image_digest,
                              "status": specs[name].status}
                       for name in competitor_names},
    }


def compute_data_hash(counts_text: str, arm, reps: int, params: dict,
                      identity: dict) -> str:
    """Cache key over (counts bytes, arm params, reps, competitor
    identity+version, caps, run params) — the 2026-10-07 G0 stale-cache
    root-cause cure, extended with the competitor identity dimension: any
    drift in version, image digest or caps invalidates the cell."""
    blob = (counts_text
            + json.dumps(arm.params, sort_keys=True) + str(reps)
            + json.dumps(identity, sort_keys=True)
            + json.dumps(params, sort_keys=True))
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()[:16]


def _atomic_write_text(path: Path, text: str) -> None:
    """Unique-temp + rename publish: the sharded driver runs several
    run_bench processes over one cachedir, so shared files must never be
    observed half-written."""
    tmp = path.with_name(f"{path.name}.tmp{os.getpid()}")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(path)


def _csv_text(header: list[str], rows: list[list]) -> str:
    """Newline-normalised CSV body (single source of bytes for the atomic
    cache writers — '\\n' line endings keep data_hash byte-stable across
    passes and platforms)."""
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow(header)
    w.writerows(rows)
    return buf.getvalue()


def stage_generation(provider, arms, cachedir: Path) -> list:
    """Deterministic counts/truth per (arm, N) under this harness's own
    cachedir (bit-identical to G0: same data streams, same frozen profile)."""
    labels = provider.channel_labels
    cells = []
    for arm in arms:
        for n in arm.n_list:
            sids, rows, truth_h = [], [], None
            for rep in range(arm.reps):
                spec = seeds.SeedSpec(arm.name, n, rep)
                cell = sim.sample_cell(provider, arm.name, n, rep,
                                       spec.data_seed, arm.params)
                sids.append(sample_id(arm.name, n, rep))
                rows.append([sids[-1], *cell.counts.tolist()])
                truth_h = cell.truth_h
            cpath = cachedir / "counts" / f"{arm.name}__N{n}.csv"
            _atomic_write_text(
                cpath, _csv_text(["sample_id", *labels], rows))
            _atomic_write_text(
                cachedir / "truth" / f"{arm.name}__N{n}.json",
                json.dumps({"arm": arm.name, "n": n, "params": arm.params,
                           "composition_shares": sim.truth_composition(
                               arm.name, arm.params),
                           "truth_h": {k: float(v) for k, v in truth_h.items()}},
                          indent=1))
            cells.append((arm, n, cpath))
    return cells


def build_catalog_reference(args, provider, cachedir: Path) -> dict:
    """Catalog source (§3): synthetic → generated file in our own cache;
    cosmic-file → the user's file mounted read-only (G0_CATALOG_PATH idiom;
    M7 adds no COSMIC data, D3 red line)."""
    if args.provider == "cosmic-file":
        src = Path(os.environ.get("G0_CATALOG_PATH", ""))
        if not src.is_file():
            raise ProviderError(
                "cosmic-file provider needs G0_CATALOG_PATH pointing at the "
                "user-provisioned signature catalog CSV (acquisition/license "
                "are user actions; the harness only mounts it read-only)")
        return {"kind": "file", "path": src.resolve()}
    names, W = provider.catalog_matrix()
    path = cachedir / "catalog__synthetic.csv"
    if not path.exists():
        rows = [[lab, *(f"{v:.8g}" for v in W[i])]
                for i, lab in enumerate(provider.channel_labels)]
        _atomic_write_text(path, _csv_text(["channel", *names], rows))
    return {"kind": "generated", "path": path}


def invoke_adapter(args, competitor: str, spec, in_dir: Path, out_dir: Path,
                   catalog_mount):
    """Dispatch to the competitor's adapter module (or the mock idiom)."""
    cell = {"in_dir": in_dir, "out_dir": out_dir}
    if args.adapter == "mock":
        return mock_adapter.run(cell, spec, catalog_mount=catalog_mount)
    mod = importlib.import_module(f"competitors.{competitor}_adapter")
    return mod.run(cell, spec, catalog_mount=catalog_mount)


def cell_identity(competitor: str, spec, args) -> dict:
    """The competitor-identity slice of the cache key (§4.4): pin, image
    provenance and caps — drift here must invalidate the cell, never
    silently reuse it."""
    return {"competitor": competitor, "runtime": spec.runtime,
            "version": spec.version, "image_ref": spec.image_ref,
            "image_digest": spec.image_digest, "entrypoint": spec.entrypoint,
            "runner_script": spec.runner_script,
            "caps": list(docker_cmd.THREAD_CAPS),
            "adapter": args.adapter, "provider": args.provider,
            "provider_seed": args.provider_seed}


def write_cell_manifest(out_dir: Path, manifest: dict) -> None:
    """Deterministic bytes (sort_keys, fixed indent): the fairness-table
    sidecar must be byte-stable so shard vs serial runs attest identically."""
    (out_dir / "manifest.json").write_text(
        json.dumps(manifest, sort_keys=True, indent=1), encoding="utf-8")


def run_cell(args, competitor: str, spec, arm, n: int, counts_path: Path,
             cachedir: Path, catalog_ref: dict) -> dict:
    """One competitor × (arm, N) cell: stage inputs, apply the four-file
    guard, invoke (or hit cache), attest. Returns the timings row."""
    stamp = f"{competitor}__{arm.name}__N{n}"
    cell_dir = cachedir / "cells" / stamp
    ind, outd = cell_dir / "in", cell_dir / "out"
    counts_text = counts_path.read_text(encoding="utf-8")
    batch, samples = m7_seeds(competitor, arm.name, n, arm.reps)
    params = {"competitor": competitor, "version": spec.version,
              "runner": spec.runner_script, "seed": batch,
              "sample_seeds": samples,
              "caps": list(docker_cmd.THREAD_CAPS),
              "protocol": "documented defaults, zero overrides (memo §3)"}
    identity = cell_identity(competitor, spec, args)
    data_hash = compute_data_hash(counts_text, arm, arm.reps, params, identity)

    # Stale-cache cure: a changed hash demolishes the cell before re-staging
    # (never trust mixed generations of in/out).
    hash_file = ind / ".data_hash"
    if hash_file.exists() and hash_file.read_text(encoding="utf-8") != data_hash:
        shutil.rmtree(cell_dir, ignore_errors=True)
    ind.mkdir(parents=True, exist_ok=True)
    outd.mkdir(parents=True, exist_ok=True)
    (ind / "counts.csv").write_text(counts_text, encoding="utf-8")
    (ind / "params.json").write_text(json.dumps(params, sort_keys=True,
                                                indent=1), encoding="utf-8")
    catalog_mount = None
    if catalog_ref["kind"] == "generated" or args.adapter == "mock":
        dest_cat = ind / "catalog.csv"
        if not dest_cat.exists():
            dest_cat.write_text(Path(catalog_ref["path"]).read_text(encoding="utf-8"),
                               encoding="utf-8")
    else:
        catalog_mount = catalog_ref["path"]   # user file: own ro bind, G0 lesson
    hash_file.write_text(data_hash, encoding="utf-8")

    def row(status: str, seconds: float, cpu: float) -> dict:
        return {"cell": stamp, "tool": competitor, "arm": arm.name,
                "n": n, "seconds": seconds, "status": status,
                "cpu_seconds": cpu}

    trusted = (not args.force_rerun
               and all((outd / name).exists() for name in GUARD_FILES))
    if trusted:
        return row("cached", 0.0, 0.0)

    t0 = time.time()
    try:
        summary = invoke_adapter(args, competitor, spec, ind, outd, catalog_mount)
    except AdapterUnavailable as e:                  # skip-not-skip sentinel
        return row(f"skip: {e}", 0.0, 0.0)
    except Exception as e:                           # noqa: BLE001 — cell failure
        return row(f"fail: {str(e)[-400:]}", round(time.time() - t0, 2), 0.0)
    write_cell_manifest(outd, {**identity, "data_hash": data_hash,
                              "profile": args.profile, "arm": arm.name,
                              "n": n, "reps": arm.reps,
                              "seeds": {"batch_anchor": batch,
                                       "sample_seeds": samples},
                              "protocol": params["protocol"]})
    return row("ok", round(time.time() - t0, 2),
               round(float(summary.get("cpu_seconds", 0.0)), 3))


def write_seeds_manifest(path: Path, arms, competitor_names, args) -> None:
    """Seeds.txt (§1 discipline): every seed on disk, data streams bit-identical
    to G0, tool streams under the m7-tool namespace."""
    path.parent.mkdir(parents=True, exist_ok=True)
    note = (f"profile={args.profile} adapter={args.adapter} "
            f"provider={args.provider} competitors={','.join(competitor_names)} "
            f"commit={git_sha()}")
    with path.open("w", encoding="utf-8") as fh:
        fh.write(f"# U-M7-02 Seeds manifest | master_seed={seeds.MASTER_SEED} | "
                 f"data stream = {seeds.STREAM_VERSION} (bit-identical to G0); "
                 f"tool stream namespace = {M7_TOOL_NS}|<competitor>|<arm>|N<n>|r<k>\n")
        fh.write(f"# note: {note}\n")
        cols = ["arm", "N", "rep", "data_seed"] + [f"seed_{c}" for c in competitor_names]
        fh.write("\t".join(cols) + "\n")
        for arm in arms:
            for n in arm.n_list:
                for rep in range(arm.reps):
                    spec = seeds.SeedSpec(arm.name, n, rep)
                    tool_cols = [seeds.derive_seed(M7_TOOL_NS, c, arm.name,
                                                   f"N{n}", f"r{rep}")
                                 % seeds.TOOL_SEED_CAP for c in competitor_names]
                    fh.write("\t".join(str(v) for v in
                                      (arm.name, n, rep, spec.data_seed,
                                       *tool_cols)) + "\n")


def write_judgment(outdir: Path, args, rows, specs, ts: str) -> Path:
    """Fairness attestation (§4.5) — the harness-output/adjudication-gate
    framing of the G0 judgment document. The scoring-verdict half is appended
    below by the scoring slice on the final (non-shard) pass."""
    tally = {}
    for r in rows:
        key = ("cached" if r["status"] == "cached"
               else "ok" if r["status"] == "ok"
               else "skip" if r["status"].startswith("skip") else "fail")
        tally[key] = tally.get(key, 0) + 1
    path = outdir / f"judgment_m7_{args.profile}_{ts}.md"
    lines = [
        f"# U-M7-02 fairness attestation — profile={args.profile}, "
        f"adapter={args.adapter}, provider={args.provider}",
        "",
        "This is the **FAIRNESS ATTESTATION** half of the authoritative run: it",
        "certifies *how* the cells ran, not *who won*.",
        "",
        "- single ground truth: all competitors saw msuiter-generated simulated",
        "  counts from the frozen G0 simulator (master seed "
        f"{seeds.MASTER_SEED}, data streams bit-identical to G0)",
        "- documented defaults only: zero threshold/parameter overrides (memo §3)",
        "- frozen thread caps on every container cell: "
        + ", ".join(f"{c}=1" for c in docker_cmd.THREAD_CAPS),
        "- one Docker VM for every cell (10 vCPU / 8 GB class), no host-side",
        "  execution of container competitors (§4.1/§4.2)",
        f"- seeds: m7-tool-namespaced derivation, all on disk (Seeds.txt); "
        f"commit {git_sha()}",
        "",
        "| competitor | version | image ref | image digest | status |",
        "|---|---|---|---|---|",
    ]
    lines += [f"| {name} | {specs[name].version} | {specs[name].image_ref or '—'} "
              f"| {specs[name].image_digest or '—'} | {specs[name].status} |"
              for name in specs]
    lines += [
        "",
        f"- cells: {len(rows)} total — "
        + ", ".join(f"{k}: {v}" for k, v in sorted(tally.items())),
        f"- timings table: timings_m7_{args.profile}_{ts}.csv "
        "(G0 six-column prefix + cpu_seconds; every measured second attributable)",
        "",
        "Honest footer: this is harness output serving as the adjudication gate.",
        "Authoritative competitor measurement is the docker-adapter run at the",
        "frozen protocol; smoke/mock passes prove pipeline plumbing only. This",
        "half attests fairness, not outcomes; the Hungarian P/R/F1 scoring",
        "verdict (U-M7-02 scoring slice, ARCHITECTURE §8) is appended below on",
        "the final pass, produced by the scoring engine over the cachedir.",
        "",
    ]
    path.write_text("\n".join(lines), encoding="utf-8")
    return path


def main(argv=None) -> int:
    args = parse_args(argv)
    competitor_names = [c.strip() for c in args.competitors.split(",") if c.strip()]
    specs = {}
    for name in competitor_names:
        if name == "mock" and args.adapter == "mock":
            specs[name] = mock_adapter.MOCK_SPEC          # fourth spec, §10.4
        else:
            try:
                specs[name] = registry.lookup(name)
            except ValueError as e:
                print(f"[registry] {e}", file=sys.stderr)
                return 2

    outdir, cachedir = Path(args.outdir), Path(args.cachedir)

    arms = grid.arms_for_profile(args.profile)
    if args.arms:
        keep = {a.strip() for a in args.arms.split(",") if a.strip()}
        arms = [a for a in arms if a.name in keep]
        if not arms:
            print(f"[grid] --arms {args.arms!r} matched nothing in profile "
                  f"{args.profile!r}", file=sys.stderr)
            return 2
    if args.reps:
        arms = [grid.ArmSpec(a.name, a.n_list, args.reps, a.params, a.judge)
                for a in arms]
    if args.n_list:
        try:
            want = {int(t) for t in args.n_list.split(",") if t.strip()}
        except ValueError:
            print(f"[grid] --n-list {args.n_list!r} must be comma-separated "
                  f"integers", file=sys.stderr)
            return 2
        pruned = []
        for a in arms:
            kept = tuple(n for n in a.n_list if n in want)
            if kept:
                pruned.append(grid.ArmSpec(a.name, kept, a.reps, a.params,
                                          a.judge))
        if not pruned:
            print(f"[grid] --n-list {args.n_list!r} matched no N point in "
                  f"profile {args.profile!r}", file=sys.stderr)
            return 2
        arms = pruned

    if args.dry_run:                    # plan-only seam: zero side effects
        plan = build_plan(args, competitor_names, specs, arms)
        plan["commit"] = git_sha()
        print(json.dumps(plan, sort_keys=True, indent=1))
        return 0

    outdir.mkdir(parents=True, exist_ok=True)
    for sub in ("counts", "truth", "cells"):
        (cachedir / sub).mkdir(parents=True, exist_ok=True)

    write_seeds_manifest(outdir / "Seeds.txt", arms, competitor_names, args)
    print(f"[seeds] manifest -> {outdir / 'Seeds.txt'}")

    try:
        provider = provider_by_name(args.provider, seed=args.provider_seed)
        catalog_ref = build_catalog_reference(args, provider, cachedir)
    except ProviderError as e:
        print(f"[provider] {e}", file=sys.stderr)
        return 2
    print(f"[provider] {args.provider}; catalog={catalog_ref['path']}")

    cells = stage_generation(provider, arms, cachedir)
    print(f"[sim] {len(cells)} (arm,N) cells x reps -> cachedir")

    rows, failures, skips = [], [], []
    for competitor in competitor_names:
        for arm, n, counts_path in cells:
            row = run_cell(args, competitor, specs[competitor], arm, n,
                           counts_path, cachedir, catalog_ref)
            rows.append(row)
            if row["status"].startswith("fail"):
                failures.append(row["cell"])
            elif row["status"].startswith("skip"):
                skips.append((row["cell"], row["status"]))

    ts = time.strftime("%Y%m%d-%H%M%S")
    suffix = f"_{args.shard_tag}" if args.shard_tag else ""
    tpath = outdir / f"timings_m7_{args.profile}_{ts}{suffix}.csv"
    timings.write_timings(tpath, rows)

    jd = write_judgment(outdir, args, rows, specs, ts)
    ok = sum(1 for r in rows if r["status"] in ("ok", "cached"))
    print(f"[adapter] {args.adapter}: {ok}/{len(rows)} cells ok|cached; "
          f"timings -> {tpath.name}")
    for cell_name, status in skips:
        print(f"SKIP {cell_name} ({status[5:]})")
    if failures:
        print(f"[adapter] FAILED cells: {failures[:5]}"
              f"{'...' if len(failures) > 5 else ''}", file=sys.stderr)
    print(f"[attestation] -> {jd.name}")
    if args.shard_tag is None:            # final authoritative pass only
        from scoring import run_products  # deferred import: pure consumer slice
        bench, srep = run_products.emit(
            cachedir=cachedir, outdir=outdir, profile=args.profile,
            adapter=args.adapter, provider=args.provider,
            provider_seed=args.provider_seed, ts=ts, judgment_path=jd)
        print(f"[scoring] {bench.name}: {srep.cells_scored} cells scored, "
              f"{len(srep.skipped)} skipped -> verdict appended to {jd.name}")
    # skip-not-skip: a required cell that came back SKIP fails the run —
    # a missing environment must be seen, never tallied as green.
    return 0 if not failures and not skips else 1


if __name__ == "__main__":
    raise SystemExit(main())
