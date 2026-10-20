#!/usr/bin/env python3
"""G0 grid orchestrator: generate → adapter → parse intervals → coverage → judgment → land results.

Usage (the three entry points of this harness):
  python3 run_grid.py --profile smoke --adapter mock --provider synthetic
  python3 run_grid.py --profile primary --adapter docker --provider cosmic-file --dry-run
  python3 run_grid.py --profile primary --adapter docker --provider cosmic-file \
      --tools sigfit,stl [--with-lrt-diagnostic]

Note: `--profile primary/degraded + the real adapter` is the FORMAL G0 execution of the frozen
protocol; the author may start it only after harness review passes and the F5 run environment lands; the smoke profile verifies the pipeline itself only.

Results → results/ (in git): Seeds.txt, coverage_*.csv, judgment_*.md, timings_*.csv.
Heavy intermediates → cache/ (gitignored): counts, truth, cell inputs/outputs.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from g0 import coverage as cov  # noqa: E402
from g0 import grid, seeds, sim  # noqa: E402
from g0.providers import provider_by_name  # noqa: E402

TOOL_IMAGE = {"sigfit": "g0-sigfit", "stl": "g0-stl"}
TOOL_RUNNER = {"sigfit": "run_sigfit.R", "stl": "run_stl.R"}


def build_docker_cmd(ind: Path, outd: Path, image: str, runner: str,
                     cat_mount: str | None = None) -> list[str]:
    """Docker run command assembly for the container adapters (the adapter_protocol.md contract).

    User-catalog mode (cat_mount): the cell input dir and the catalog original file each get
    their own ro mount; neither may be missing (2026-10-07 sigfit FATAL root cause: cat_bind was
    assembled but never made it into cmd). The catalog file mounts straight at a standalone
    rootfs path /work/catalog.csv — stacking it inside the cell-dir bind (/work/in/catalog.csv)
    fails at init under the Docker Desktop virtiofs driver (runc: error mounting … to rootfs;
    the full-smoke-wipeout repro of 2026-10-07). In generated/mock mode catalog.csv is already
    copied into in/, so a single mount suffices.
    Mount sources are always resolved to absolute paths: docker treats a relative -v source as
    a named volume ("invalid characters for a local volume name", the same day's second root cause).
    """
    cmd = ["docker", "run", "--rm"]
    # Thread caps (2026-10-07 degraded live diagnosis at the bench): cmdstanr's 4 chains are independent
    # processes × in-chain BLAS/OpenMP default all-core threads × 8 parallel shards = hundreds of
    # threads contending for 10 cores; the cold-machine 20s cell got stretched to 15min+. Sampling
    for cap in ("OMP_NUM_THREADS", "OMP_THREAD_LIMIT",
                "STAN_OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS"):
        cmd += ["-e", f"{cap}=1"]
    ind, outd = Path(ind).resolve(), Path(outd).resolve()
    if cat_mount:
        cat_mount = Path(cat_mount).resolve()
        cmd += ["-v", f"{ind}:/work/in:ro",
                "-v", f"{cat_mount}:/work/catalog.csv:ro"]
    else:
        cmd += ["-v", f"{ind}:/work/in"]
    cat_dest = "/work/catalog.csv" if cat_mount else "/work/in/catalog.csv"
    cmd += ["-v", f"{outd}:/work/out", image, "Rscript", f"/work/{runner}",
            "--counts", "/work/in/counts.csv", "--catalog", cat_dest,
            "--params", "/work/in/params.json", "--outdir", "/work/out"]
    return cmd


def git_sha() -> str:
    """Runtime capture of the repo commit SHA (P2d: manifest traceability discipline);
    honestly records unknown outside a git checkout or without a git executable."""
    try:
        out = subprocess.run(["git", "rev-parse", "HEAD"], cwd=str(HERE),
                             capture_output=True, text=True, check=True)
        return out.stdout.strip()
    except Exception:
        return "unknown"


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--profile", default="smoke",
                    choices=["smoke", "primary", "degraded"])
    ap.add_argument("--adapter", default="mock", choices=["mock", "docker"])
    ap.add_argument("--provider", default="synthetic",
                    choices=["synthetic", "cosmic-file"])
    ap.add_argument("--tools", default="sigfit,stl")
    ap.add_argument("--arms", default=None,
                    help="comma-separated arm filter (default: all — main + composition axis comp_* "
                         "+ sensitivity arms nb,clock,sparse)")
    ap.add_argument("--reps", type=int, default=None,
                    help="override the repetition count (gray re-judication uses 400; otherwise the profile default)")
    ap.add_argument("--grid", default=None, choices=["primary", "degraded"],
                    help="override the grid for the full-grid arms (default: the profile default)")
    ap.add_argument("--provider-seed", type=int, default=0,
                    help="seed of the synthetic provider (ignored by cosmic-file)")
    ap.add_argument("--coverage-scale", type=float, default=1.0,
                    help="mock test hook: interval-width scaling (default 1.0)")
    ap.add_argument("--with-lrt-diagnostic", action="store_true",
                    help="NB arm: append the own χ²₁ presence LRT empirical size/power report column (P3)")
    ap.add_argument("--dry-run", action="store_true",
                    help="land only Seeds.txt + counts/truth (no adapter call, no coverage output)")
    ap.add_argument("--force-rerun", action="store_true",
                    help="ignore existing outputs in cache; force a full re-run of every cell")
    ap.add_argument("--outdir", default=str(HERE / "results"))
    ap.add_argument("--cachedir", default=str(HERE / "cache"))
    return ap.parse_args(argv)


def sample_id(arm: str, n: int, rep: int) -> str:
    return f"{arm}__N{n}__r{rep}"


def decode_sample_id(sid: str):
    arm, n, rep = sid.split("__")
    return arm, int(n[1:]), int(rep[1:])


def write_counts_csv(path: Path, labels, rows):
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["sample_id", *labels])
        w.writerows(rows)


def write_catalog_csv(path: Path, labels, names, W):
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["channel", *names])
        for i, lab in enumerate(labels):
            w.writerow([lab, *(f"{v:.8g}" for v in W[i])])


def build_catalog_reference(args, provider, cachedir: Path):
    """Catalog source: synthetic → generate catalog.csv; cosmic-file → the user's original file
    (G0_CATALOG_PATH takes precedence; referenced/copied verbatim only — never rewritten, never committed)."""
    labels = provider.channel_labels
    user_catalog = os.environ.get("G0_CATALOG_PATH")
    if args.provider == "cosmic-file":
        src = Path(user_catalog) if user_catalog else None
        if src is None or not src.exists():
            raise SystemExit(
                "the cosmic-file provider needs G0_CATALOG_PATH pointing at the user's own fit-catalog CSV"
                "(F3 = COSMIC v3.6 SBS96 GRCh37, all 101 signatures; data acquisition and licensing are a user action)")
        return {"kind": "file", "path": src.resolve()}
    names, W = provider.catalog_matrix()
    path = cachedir / "catalog__synthetic.csv"
    write_catalog_csv(path, labels, names, W)
    return {"kind": "generated", "path": path.resolve()}


def stage_generation(args, provider, arms, cachedir: Path):
    """Generate counts and truth, land them in cache; return (cell_keys, per-cell truths)."""
    labels = provider.channel_labels
    cells = []
    for arm in arms:
        for n in arm.n_list:
            sids, counts_rows = [], []
            truth_h = None
            for rep in range(arm.reps):
                spec = seeds.SeedSpec(arm.name, n, rep)
                cell = sim.sample_cell(provider, arm.name, n, rep,
                                       spec.data_seed, arm.params)
                sids.append(sample_id(arm.name, n, rep))
                counts_rows.append([sids[-1], *cell.counts.tolist()])
                truth_h = cell.truth_h
            cpath = cachedir / "counts" / f"{arm.name}__N{n}.csv"
            write_counts_csv(cpath, labels, counts_rows)
            comp = sim.truth_composition(arm.name, arm.params)
            (cachedir / "truth" / f"{arm.name}__N{n}.json").write_text(
                json.dumps({"arm": arm.name, "n": n, "params": arm.params,
                            "composition": (arm.params.get("composition",
                                                            sim.DEFAULT_COMPOSITION)
                                            if arm.name != "sparse" else "master(sparse)"),
                            "composition_shares": comp,
                            "truth_h": {k: float(v) for k, v in truth_h.items()}},
                           indent=1), encoding="utf-8")
            cells.append((arm, n, cpath, truth_h))
    return cells


def stage_adapter(args, tools, cells, catalog_ref, cachedir: Path):
    """Call the adapter per (tool, arm, N); return timings and the failure list.

    Cache consistency: each cell's in/ dir records the counts content sha256; on a re-run, if
    the data/params changed the cell is rebuilt wholesale (so stale intermediates cannot silently pollute coverage).
    """
    timings, failures = [], []
    for tool in tools:
        for arm, n, counts_path, _ in cells:
            stamp = f"{tool}__{arm.name}__N{n}"
            cell_dir = cachedir / "cells" / stamp
            ind, outd = cell_dir / "in", cell_dir / "out"
            # Input assembly (always rewrite counts; rebuild the rest of the cell dir only when the hash changed)
            counts_text = counts_path.read_text(encoding="utf-8")
            params = {"tool": tool, "seed": seeds.tool_seed(tool, arm.name, n),
                      "notes": "Tier-1 default parameters as-is (protocol §2.3)"}
            if tool != "sigfit":
                params["nboot"] = 200                       # frozen value
            if args.adapter == "mock":
                params["coverage_scale"] = args.coverage_scale
            sample_seeds = {sample_id(arm.name, n, r):
                            seeds.tool_seed(tool, arm.name, n, r)
                            for r in range(arm.reps)}
            params["sample_seeds"] = sample_seeds
            # data_hash covers counts + arm params + repetition count + tool params (seeds incl.):
            # seed/param drift must invalidate stale cell outputs (2026-10-07 stale-cache root cause:
            # the old hash omitted the tool params, so after a provider switch it still hit synthetic-era intervals)
            data_hash = hashlib.sha256(
                (counts_text + json.dumps(arm.params, sort_keys=True)
                 + str(arm.reps)
                 + json.dumps(params, sort_keys=True)).encode("utf-8")).hexdigest()[:16]
            if (ind / ".data_hash").exists() and \
                    (ind / ".data_hash").read_text(encoding="utf-8") != data_hash:
                shutil.rmtree(cell_dir, ignore_errors=True)
            ind.mkdir(parents=True, exist_ok=True)
            outd.mkdir(parents=True, exist_ok=True)
            dest_counts = ind / "counts.csv"
            dest_counts.write_text(counts_text, encoding="utf-8")
            (ind / "params.json").write_text(json.dumps(params, indent=1),
                                             encoding="utf-8")
            # Catalog assembly: mock/generated catalogs get copied; docker + user file → single-file read-only mount
            cat_mount = None
            if catalog_ref["kind"] == "generated" or args.adapter == "mock":
                dest_cat = ind / "catalog.csv"
                if not dest_cat.exists():
                    dest_cat.write_text(
                        Path(catalog_ref["path"]).read_text(encoding="utf-8"),
                        encoding="utf-8")
            else:
                cat_mount = catalog_ref["path"]   # the user's original file mounted verbatim read-only

            (ind / ".data_hash").write_text(data_hash, encoding="utf-8")

            # Re-run guard: skip when data/params are unchanged and outputs exist (the docker profile can resume
            # from a breakpoint); --force-rerun forces a full re-run.
            if (not args.force_rerun
                    and (outd / "intervals.csv").exists()
                    and (outd / "errors.log").exists()):
                timings.append({"cell": stamp, "tool": tool, "arm": arm.name,
                                "n": n, "seconds": 0.0, "status": "cached"})
                continue

            t0 = time.time()
            try:
                if args.adapter == "mock":
                    cmd = [sys.executable, str(HERE / "adapters" / "mock_runner.py"),
                           "--counts", str(dest_counts), "--catalog",
                           str(ind / "catalog.csv"), "--params",
                           str(ind / "params.json"), "--outdir", str(outd)]
                    subprocess.run(cmd, check=True, capture_output=True, text=True)
                else:
                    cmd = build_docker_cmd(ind, outd, TOOL_IMAGE[tool],
                                           TOOL_RUNNER[tool], cat_mount=cat_mount)
                    subprocess.run(cmd, check=True, capture_output=True, text=True)
                status = "ok"
            except subprocess.CalledProcessError as e:
                status = f"fail: {e.stderr[-400:] if e.stderr else e}"
                failures.append(stamp)
            timings.append({"cell": stamp, "tool": tool, "arm": arm.name,
                            "n": n, "seconds": round(time.time() - t0, 2),
                            "status": status})
    return timings, failures


def stage_parse(cells, tools, cachedir: Path):
    """Parse each cell's intervals.csv → the IntervalRecord long table."""
    records = []
    for arm, n, _, _ in cells:
        for tool in tools:
            path = cachedir / "cells" / f"{tool}__{arm.name}__N{n}" / "out" / "intervals.csv"
            if not path.exists():
                continue
            with path.open(newline="", encoding="utf-8") as fh:
                for row in csv.DictReader(fh):
                    a, nn, rep = decode_sample_id(row["sample_id"])
                    def fnum(x):
                        try:
                            v = float(x)
                        except (TypeError, ValueError):
                            return float("nan")
                        return v
                    lo, hi, est = fnum(row["lo95"]), fnum(row["hi95"]), fnum(row["estimate"])
                    err = not (np.isfinite(lo) and np.isfinite(hi))
                    records.append(cov.IntervalRecord(
                        tool=tool, arm=a, n=nn, signature=row["signature"],
                        rep=rep, estimate=est,
                        lo95=0.0 if err else lo, hi95=0.0 if err else hi,
                        estimand=row.get("estimand", "absolute"),
                        zeroed=str(row.get("zeroed", "0")) in ("1", "True", "true"),
                        error=err))
    return records


def stage_coverage(records, cells, layer_of):
    """Per-cell coverage (main estimand=absolute; secondary estimands flagged separately)."""
    tables = {}
    for estimand in ("absolute", "raw", "fraction"):
        sub = [r for r in records if r.estimand == estimand]
        if not sub:
            continue
        cc = []
        for arm, n, _, truth_h in cells:
            truth_by_sig = dict(truth_h)        # {signature: truth absolute exposure}
            cc += cov.cell_coverage([r for r in sub if r.arm == arm.name and r.n == n],
                                    truth_by_sig, layer_of)
        tables[estimand] = cc
    return tables


def write_coverage_csv(path: Path, tables):
    cols = ["estimand", "tool", "arm", "n", "signature", "layer", "truth_h",
            "k", "n_reps", "coverage", "cp_lo", "cp_hi", "filtered_rate",
            "error_rate", "p1_mechanism_i"]
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(cols)
        for estimand, cells in tables.items():
            for c in cells:
                w.writerow([estimand, c.tool, c.arm, c.n, c.signature, c.layer,
                            f"{c.truth_h:.4f}", c.k, c.n_reps,
                            f"{c.coverage:.4f}", f"{c.cp_lo:.4f}",
                            f"{c.cp_hi:.4f}", f"{c.filtered_rate:.3f}",
                            f"{c.error_rate:.3f}", int(c.p1_mechanism_i)])


def stage_lrt_diagnostic(provider, arms, cachedir: Path, outdir: Path):
    """P3 supplemental column: empirical size / power of the own χ²₁ presence LRT on the NB arm.

    Shares the G0 seed data; the NB semantics (size=8) and the Poisson semantics (size=None)
    run as twin columns — the latter's size inflation under NB truth is exactly the quantity to measure.
    The H0 set = the provider's designated absent slots (ABS*, no constructive collinearity with the truth),
    and the composition-axis extension slots are kept out (they may be near-duplicates of the truth and would pollute the size reading).
    """
    from g0 import lrt
    nb_arms = [a for a in arms if a.name == "nb"]
    if not nb_arms:
        return None
    arm = nb_arms[0]
    names, W = provider.catalog_matrix()
    absent_names = set(getattr(provider, "absent", {}))
    absent_idx = [i for i, k in enumerate(names) if k in absent_names]
    truth_names = list(provider.truth)
    rows_out = []
    for n in arm.n_list:
        cpath = cachedir / "counts" / f"{arm.name}__N{n}.csv"
        if not cpath.exists():
            continue
        with cpath.open(newline="", encoding="utf-8") as fh:
            r = list(csv.reader(fh))
        X = np.array([[float(x) for x in row[1:]] for row in r[1:]], dtype=float)
        for tag, size in (("nb(size=8)", 8.0), ("poisson(misspec)", None)):
            res = lrt.presence_lrt_scan(X, W, absent_idx, size=size)
            size_rate = np.mean([res_["reject"] for res_ in res])
            present_idx = [i for i, k in enumerate(names) if k in truth_names]
            res_p = lrt.presence_lrt_scan(X, W, present_idx, size=size)
            power_rate = np.mean([res_["reject"] for res_ in res_p])
            rows_out.append({"arm": arm.name, "n": n, "lrt_semantics": tag,
                             "empirical_size_absent": round(float(size_rate), 4),
                             "power_present": round(float(power_rate), 4),
                             "n_tests_per_rate": int(X.shape[0] * len(absent_idx))})
    path = outdir / "diagnostic_lrt_nb.csv"
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows_out[0]))
        w.writeheader()
        w.writerows(rows_out)
    return rows_out


def main(argv=None) -> int:
    args = parse_args(argv)
    tools = [t.strip() for t in args.tools.split(",") if t.strip()]
    for t in tools:
        if t not in ("sigfit", "stl"):
            raise SystemExit(f"unknown tool: {t} (Tier-1 = sigfit,stl; F2 frozen)")

    outdir, cachedir = Path(args.outdir), Path(args.cachedir)
    outdir.mkdir(parents=True, exist_ok=True)
    for sub in ("counts", "truth", "cells"):
        (cachedir / sub).mkdir(parents=True, exist_ok=True)

    # 1) Arms and seeds
    arms = grid.arms_for_profile(args.profile)
    if args.arms:
        keep = set(args.arms.split(","))
        arms = [a for a in arms if a.name in keep]
    if args.grid:
        target = grid.PRIMARY_GRID if args.grid == "primary" else grid.DEGRADED_GRID
        arms = [grid.ArmSpec(a.name, target, a.reps, a.params, a.judge)
                if a.n_list in (grid.PRIMARY_GRID, grid.DEGRADED_GRID) else a
                for a in arms]
    if args.reps:
        arms = [grid.ArmSpec(a.name, a.n_list, args.reps, a.params, a.judge)
                for a in arms]
    specs = grid.all_seed_specs(arms)
    note = (f"profile={args.profile} adapter={args.adapter} provider={args.provider}"
            f" tools={','.join(tools)} reps={arms[0].reps}"
            f" commit={git_sha()}"
            + (" DEGRADED" if args.profile == "degraded" else "")
            + (" GRAY-RERUN(reps override)" if args.reps else ""))
    seeds.write_seeds_manifest(outdir / "Seeds.txt", specs,
                               tool_names=tools, header_note=note)
    print(f"[seeds] {len(specs)} cells -> {outdir / 'Seeds.txt'}")

    # 2) Provider and catalog
    provider = provider_by_name(args.provider, seed=args.provider_seed)
    catalog_ref = build_catalog_reference(args, provider, cachedir)
    print(f"[provider] {args.provider}; catalog={catalog_ref['path']}")

    # 3) Generation
    t0 = time.time()
    cells = stage_generation(args, provider, arms, cachedir)
    print(f"[sim] {len(cells)} (arm,N) cells x reps -> cache/ "
          f"({time.time() - t0:.1f}s)")
    if args.dry_run:
        print("[dry-run] seeds + counts + truth landed; adapter not called.")
        return 0

    # 4) adapter
    timings, failures = stage_adapter(args, tools, cells, catalog_ref, cachedir)
    tpath = outdir / f"timings_{args.profile}_{time.strftime('%Y%m%d-%H%M%S')}.csv"
    with tpath.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["cell", "tool", "arm", "n",
                                           "seconds", "status"])
        w.writeheader()
        w.writerows(timings)
    print(f"[adapter] {args.adapter}: "
          f"{sum(1 for t in timings if t['status'] in ('ok', 'cached'))}"
          f"/{len(timings)} cells ok; timings -> {tpath}")
    if failures:
        print(f"[adapter] FAILED cells: {failures[:5]}{'...' if len(failures) > 5 else ''}")

    # 5) Parse + coverage + judgment
    records = stage_parse(cells, tools, cachedir)
    if not records:
        print("[coverage] no intervals parsed — adapter produced nothing (see timings)")
        return 1
    tables = stage_coverage(records, cells, sim.layer_of)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    cov_path = outdir / f"coverage_{args.profile}_{stamp}.csv"
    write_coverage_csv(cov_path, tables)

    primary = tables.get("absolute", [])
    # P0-2 (frozen supplemental clause b): the sensitivity arms (nb/clock/sparse) refine but never overturn the verdict —
    # the judgment path consumes only the judge=True main-model arms (the main multinomial + the frozen
    # truth composition axis comp_*, adjudication §PI scenario-3 upgrade already ruled); sensitivity arms are report-only.
    judge_arms = {a.name for a in arms if a.judge}
    sens_arms = sorted({a.name for a in arms if not a.judge})
    main_cells = [c for c in primary if c.arm in judge_arms]
    judgment = cov.judge(primary, tier1_tools=tuple(tools), judge_arms=judge_arms)
    jd_path = outdir / f"judgment_{args.profile}_{stamp}.md"
    md = [
        f"# G0 judgment summary — profile={args.profile}, adapter={args.adapter}, provider={args.provider}",
        f"",
        f"- Tools (F2 frozen): {', '.join(tools)}",
        f"- Judgment input cells: {len(main_cells)} (estimand=absolute main estimand; "
        f"arm ∈ {sorted(judge_arms)})",
        f"- Sensitivity arms (not judged, report column only; frozen supplemental clause b): {sens_arms}",
        f"- commit: {git_sha()}",
        f"- Repetitions: {arms[0].reps}" + (" (DEGRADED profile; must be recorded in the memo)"
                                       if args.profile == "degraded" else ""),
        "",
        "```",
        judgment.summary(),
        "```",
        "",
        "secondary estimands (not judged): "
        + "; ".join(f"{k} ({len(v)} cells)" for k, v in tables.items() if k != "absolute"),
        "",
        "Note: this file is harness output. Formal G0 judgments may issue only from the frozen protocol"
        "(docs/devlog/2026-09-28-G0-pi-adjudication.md §PI ruling 5)"
        "under the real adapter (docker) + the cosmic-file provider, in a primary/degraded run;"
        "smoke/mock results prove only pipeline connectivity.",
    ]
    jd_path.write_text("\n".join(md), encoding="utf-8")
    print(f"[coverage] -> {cov_path}")
    print(f"[judgment] verdict={judgment.verdict} -> {jd_path}")

    # 6) P3 diagnostic column (optional)
    if args.with_lrt_diagnostic:
        rows = stage_lrt_diagnostic(provider, arms, cachedir, outdir)
        if rows:
            print(f"[lrt] P3 diagnostic -> {outdir / 'diagnostic_lrt_nb.csv'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
