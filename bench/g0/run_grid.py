#!/usr/bin/env python3
"""G0 网格编排器：生成 → adapter → 解析区间 → coverage → 判定 → 结果落盘。

用法（本 harness 的三种入口）：
  python3 run_grid.py --profile smoke --adapter mock --provider synthetic
  python3 run_grid.py --profile primary --adapter docker --provider cosmic-file --dry-run
  python3 run_grid.py --profile primary --adapter docker --provider cosmic-file \
      --tools sigfit,stl [--with-lrt-diagnostic]

注意：`--profile primary/degraded + 真实 adapter` 是冻结协议的**正式 G0 执行**，
须等 harness 审核通过、F5 执行环境落实后由作者开跑；smoke 档只验证管线自身。

结果 → results/（入 git）：Seeds.txt、coverage_*.csv、judgment_*.md、timings_*.csv。
重中间产物 → cache/（gitignored）：counts、truth、cell 输入/输出。
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
    """容器 adapter 的 docker run 命令装配（adapter_protocol.md 契约）。

    用户目录模式（cat_mount）：cell 输入目录与目录原文件各挂一个 ro
    挂载，两者缺一不可（2026-10-07 sigfit FATAL 根因：cat_bind 组装后
    从未进 cmd）。目录文件直挂 rootfs 独立路径 /work/catalog.csv——
    叠挂在 cell 目录 bind 之内（/work/in/catalog.csv）在 Docker Desktop
    virtiofs 驱动下 init 即失败（runc: error mounting … to rootfs，
    smoke 全灭复现于 2026-10-07）。generated/mock 模式的 catalog.csv
    已复制进 in/，单一挂载即可。
    """
    cmd = ["docker", "run", "--rm"]
    if cat_mount:
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
    """运行时捕获仓库 commit SHA（P2d：manifest 可溯源纪律）；
    非 git 环境/无 git 可执行文件时如实记 unknown。"""
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
                    help="逗号分隔的臂过滤（默认全部：main + 组合轴 comp_* "
                         "+ 敏感性臂 nb,clock,sparse）")
    ap.add_argument("--reps", type=int, default=None,
                    help="覆盖重复数（gray 重判用 400；否则用 profile 默认）")
    ap.add_argument("--grid", default=None, choices=["primary", "degraded"],
                    help="覆盖全网格臂的网格（默认用 profile 默认）")
    ap.add_argument("--provider-seed", type=int, default=0,
                    help="synthetic provider 的种子（cosmic-file 忽略）")
    ap.add_argument("--coverage-scale", type=float, default=1.0,
                    help="mock 测试钩子：区间宽度缩放（默认 1.0）")
    ap.add_argument("--with-lrt-diagnostic", action="store_true",
                    help="NB 臂追加自有 χ²₁ presence LRT 经验 size/power 报告列（P3）")
    ap.add_argument("--dry-run", action="store_true",
                    help="只落盘 Seeds.txt + counts/truth（不调 adapter、不出覆盖率）")
    ap.add_argument("--force-rerun", action="store_true",
                    help="忽略 cache 中已有产出，强制重跑全部 cell")
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
    """目录来源：synthetic → 生成 catalog.csv；cosmic-file → 用户原文件
    （G0_CATALOG_PATH 优先；只做原样引用/复制，绝不改写、绝不入库）。"""
    labels = provider.channel_labels
    user_catalog = os.environ.get("G0_CATALOG_PATH")
    if args.provider == "cosmic-file":
        src = Path(user_catalog) if user_catalog else None
        if src is None or not src.exists():
            raise SystemExit(
                "cosmic-file provider 需要 G0_CATALOG_PATH 指向用户自备的拟合目录 CSV"
                "（F3 = COSMIC v3.6 SBS96 GRCh37 全 101 签名；数据获取与许可是用户动作）")
        return {"kind": "file", "path": src.resolve()}
    names, W = provider.catalog_matrix()
    path = cachedir / "catalog__synthetic.csv"
    write_catalog_csv(path, labels, names, W)
    return {"kind": "generated", "path": path.resolve()}


def stage_generation(args, provider, arms, cachedir: Path):
    """生成 counts 与 truth，落盘 cache；返回 (cell_keys, per-cell truths)。"""
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
    """逐 (tool, arm, N) 调 adapter；返回 timings 与失败清单。

    cache 一致性：每个 cell 的 in/ 目录记 counts 内容 sha256；重跑时若
    数据/参数变化则整体重建（防止陈旧中间产物静默污染覆盖率）。
    """
    timings, failures = [], []
    for tool in tools:
        for arm, n, counts_path, _ in cells:
            stamp = f"{tool}__{arm.name}__N{n}"
            cell_dir = cachedir / "cells" / stamp
            ind, outd = cell_dir / "in", cell_dir / "out"
            # 输入装配（总是重写 counts；hash 变了才重建 cell 目录其余部分）
            counts_text = counts_path.read_text(encoding="utf-8")
            params = {"tool": tool, "seed": seeds.tool_seed(tool, arm.name, n),
                      "notes": "Tier-1 默认参数照用（协议 §2.3）"}
            if tool != "sigfit":
                params["nboot"] = 200                       # 冻结值
            if args.adapter == "mock":
                params["coverage_scale"] = args.coverage_scale
            sample_seeds = {sample_id(arm.name, n, r):
                            seeds.tool_seed(tool, arm.name, n, r)
                            for r in range(arm.reps)}
            params["sample_seeds"] = sample_seeds
            # data_hash 覆盖 counts + 臂参数 + 重复数 + 工具参数（含种子）：
            # 种子/参数漂移必须使陈旧 cell 输出失效（2026-10-07 陈旧缓存根因：
            # 旧 hash 不含工具参数，换 provider 后仍命中 synthetic 时代旧区间）
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
            # 目录装配：mock/生成目录复制；docker + 用户文件 → 单文件只读挂载
            cat_mount = None
            if catalog_ref["kind"] == "generated" or args.adapter == "mock":
                dest_cat = ind / "catalog.csv"
                if not dest_cat.exists():
                    dest_cat.write_text(
                        Path(catalog_ref["path"]).read_text(encoding="utf-8"),
                        encoding="utf-8")
            else:
                cat_mount = catalog_ref["path"]   # 用户原文件原样只读挂载

            (ind / ".data_hash").write_text(data_hash, encoding="utf-8")

            # 复跑守卫：数据/参数未变且已有产出时跳过（docker 档可断点续跑）；
            # --force-rerun 强制全量重跑。
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
    """解析各 cell 的 intervals.csv → IntervalRecord 长表。"""
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
    """逐 cell 覆盖率（主 estimand=absolute；secondary estimand 单独标记）。"""
    tables = {}
    for estimand in ("absolute", "raw", "fraction"):
        sub = [r for r in records if r.estimand == estimand]
        if not sub:
            continue
        cc = []
        for arm, n, _, truth_h in cells:
            truth_by_sig = dict(truth_h)        # {签名: 真值绝对 exposure}
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
    """P3 增补列：NB 臂上自有 χ²₁ presence LRT 的经验 size / power。

    与 G0 共用种子数据；NB 语义（size=8）与 Poisson 语义（size=None）
    双列对照——后者在 NB 真值下的 size 膨胀正是要测的量。
    H0 集 = provider 的 designated 缺席槽（ABS*，与真值无构造性共线），
    不把组合轴扩展槽混入（它们与真值可能近重复，会污染 size 解读）。
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
            raise SystemExit(f"unknown tool: {t} (Tier-1 = sigfit,stl; F2 冻结)")

    outdir, cachedir = Path(args.outdir), Path(args.cachedir)
    outdir.mkdir(parents=True, exist_ok=True)
    for sub in ("counts", "truth", "cells"):
        (cachedir / sub).mkdir(parents=True, exist_ok=True)

    # 1) 臂与种子
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

    # 2) provider 与目录
    provider = provider_by_name(args.provider, seed=args.provider_seed)
    catalog_ref = build_catalog_reference(args, provider, cachedir)
    print(f"[provider] {args.provider}; catalog={catalog_ref['path']}")

    # 3) 生成
    t0 = time.time()
    cells = stage_generation(args, provider, arms, cachedir)
    print(f"[sim] {len(cells)} (arm,N) cells x reps -> cache/ "
          f"({time.time() - t0:.1f}s)")
    if args.dry_run:
        print("[dry-run] seeds + counts + truth 已落盘；未调 adapter。")
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

    # 5) 解析 + 覆盖率 + 判定
    records = stage_parse(cells, tools, cachedir)
    if not records:
        print("[coverage] no intervals parsed — adapter 未产出（见 timings）")
        return 1
    tables = stage_coverage(records, cells, sim.layer_of)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    cov_path = outdir / f"coverage_{args.profile}_{stamp}.csv"
    write_coverage_csv(cov_path, tables)

    primary = tables.get("absolute", [])
    # P0-2（冻结增补条款 b）：敏感性臂（nb/clock/sparse）只细化不推翻判定——
    # 判定路径只吃 judge=True 的 main 模型臂（主多项 + 冻结真值组合轴
    # comp_*，adjudication §PI 已裁决 3 场景升级）；敏感性臂仅出报告列。
    judge_arms = {a.name for a in arms if a.judge}
    sens_arms = sorted({a.name for a in arms if not a.judge})
    main_cells = [c for c in primary if c.arm in judge_arms]
    judgment = cov.judge(primary, tier1_tools=tuple(tools), judge_arms=judge_arms)
    jd_path = outdir / f"judgment_{args.profile}_{stamp}.md"
    md = [
        f"# G0 判定摘要 — profile={args.profile}, adapter={args.adapter}, provider={args.provider}",
        f"",
        f"- 工具（F2 冻结）: {', '.join(tools)}",
        f"- 判定输入 cells: {len(main_cells)}（estimand=absolute 主 estimand；"
        f"arm ∈ {sorted(judge_arms)}）",
        f"- 敏感性臂（不进判定，仅报告列，冻结增补条款 b）: {sens_arms}",
        f"- commit: {git_sha()}",
        f"- 重复数: {arms[0].reps}" + ("（DEGRADED 档，须记入 memo）"
                                       if args.profile == "degraded" else ""),
        "",
        "```",
        judgment.summary(),
        "```",
        "",
        "次要 estimand（不进判定）: "
        + "; ".join(f"{k} ({len(v)} cells)" for k, v in tables.items() if k != "absolute"),
        "",
        "注意: 本文件为 harness 输出。正式 G0 判定仅可出自冻结协议"
        "（docs/devlog/2026-09-28-G0-pi-adjudication.md §PI 已裁决 5）"
        "在真实 adapter（docker）+ cosmic-file provider 下的 primary/degraded 运行；"
        "smoke/mock 结果只证明管线连通。",
    ]
    jd_path.write_text("\n".join(md), encoding="utf-8")
    print(f"[coverage] -> {cov_path}")
    print(f"[judgment] verdict={judgment.verdict} -> {jd_path}")

    # 6) P3 诊断列（可选）
    if args.with_lrt_diagnostic:
        rows = stage_lrt_diagnostic(provider, arms, cachedir, outdir)
        if rows:
            print(f"[lrt] P3 diagnostic -> {outdir / 'diagnostic_lrt_nb.csv'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
