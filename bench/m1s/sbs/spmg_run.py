#!/usr/bin/env python3
# =============================================================================
# bench/m1s/sbs/spmg_run.py · SPMG 基线（在 bench/m1s/.venv 内运行）
#
# 前置（一次性，幂等）：SigProfilerMatrixGenerator 1.3.6 自定义基因组安装——
#   genInstall.install("SYN5M", custom=True, fastaPath=cache/fasta,
#                      transcriptPath=cache/transcripts.txt)
#   （install_chromosomes 对 custom 走系统 gzip -d + 纯 Python 串文件；tsb 走
#   我们提供的全长 +1 链转录本；全部落在 .venv site-packages 内。）
#
# 已知上游限制（本脚本的运行时绕过，全部上游计算路径零改动）：
#   SPMG 1.3.6 的生成入口用硬编码 CHECKSUMS 白名单校验基因组
#   （reference_genome_manager.is_genome_installed：genome 不在 dict 内直接
#   raise "has not been installed"），自定义基因组永远无法通过。本脚本在
#   运行时把本地安装产物的 md5 注册进该 dict（= 让它对我们自己的本地文件
#   做「下载完整性」校验），不修改任何上游文件；矩阵生成代码路径全为原装。
#   —— 如实记录于 result.md。
#
# 计时：sanity（100 变异）跑一次（兼正确性对拍输入）；全量（10⁶）跑一次，
#   perf_counter 墙钟（SPMG 无预热复用价值，多次复跑代价为分钟级——口径
#   如实记录为单次墙钟）。
# =============================================================================
import hashlib
import json
import sys
import time
from pathlib import Path

from SigProfilerMatrixGenerator import install as genInstall
from SigProfilerMatrixGenerator.scripts import ref_install
from SigProfilerMatrixGenerator.scripts import reference_genome_manager
from SigProfilerMatrixGenerator.scripts import SigProfilerMatrixGeneratorFunc as matGen

GENOME = "SYN5M"


def install_if_needed(cache: Path) -> None:
    rd = ref_install.reference_dir()
    tsb_dir = Path(rd.get_tsb_dir()) / GENOME
    if tsb_dir.exists() and any(tsb_dir.glob("*.txt")):
        print(f"[spmg] genome {GENOME} already installed at {tsb_dir}")
        return
    fasta_dir = cache / "fasta"
    transcripts = cache / "transcripts.txt"
    print(f"[spmg] installing custom genome {GENOME} from {fasta_dir}")
    t0 = time.perf_counter()
    genInstall.install(GENOME, custom=True, ftp=False,
                       fastaPath=str(fasta_dir), transcriptPath=str(transcripts),
                       exomePath=None)
    print(f"[spmg] install done in {time.perf_counter()-t0:.1f}s")


def register_checksums() -> None:
    """运行时注册本地 tsb 产物的 md5（绕过上游硬编码白名单；见文件头说明）。"""
    rd = ref_install.reference_dir()
    tsb_dir = Path(rd.get_tsb_dir()) / GENOME
    entries = {}
    for p in sorted(tsb_dir.glob("*.txt")):
        entries[p.name[:-4]] = hashlib.md5(p.read_bytes()).hexdigest()
    reference_genome_manager.CHECKSUMS[GENOME] = entries
    print(f"[spmg] registered local checksums for {GENOME}: {len(entries)} files")


def run(project: str, vcf_dir: Path, out_tsv: Path, cwd: Path) -> dict:
    # SPMG 会在 <vcf_dir>/input/ 缓存转换后的逐染色体文件；夹具重生成后必须
    # 清掉，否则重跑消费陈旧转换（实测会静默复用旧记录集）。
    for stale in (vcf_dir / "input", vcf_dir / "output"):
        if stale.exists():
            import shutil
            shutil.rmtree(stale)
    t0 = time.perf_counter()
    mats = matGen.SigProfilerMatrixGeneratorFunc(
        project, GENOME, str(vcf_dir), exome=False, plot=False)
    wall = time.perf_counter() - t0
    m = mats["96"]
    m.to_csv(out_tsv, sep="\t")
    return {"project": project, "wall_s": wall,
            "n_mutations": int(m.values.sum()),
            "shape": list(m.shape), "columns": list(m.columns)}


def main():
    cache = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path("cache")
    install_if_needed(cache)
    register_checksums()

    import os
    os.chdir(cache)  # SPMG 把 output/ 写在 CWD 下（standard CLI 行为）
    stats = {}
    stats["sanity"] = run("sanity", cache / "sanity_vcf",
                          cache / "spmg_sanity96.tsv", cache)
    print(f"[spmg] sanity: {stats['sanity']}")
    stats["full"] = run("full", cache / "vcf",
                        cache / "spmg_full96.tsv", cache)
    print(f"[spmg] full (dbsfree): {stats['full']}")
    stats["dense"] = run("dense", cache / "vcf_dense",
                         cache / "spmg_dense96.tsv", cache)
    print(f"[spmg] dense: {stats['dense']}")
    (cache / "spmg_timing.json").write_text(json.dumps(stats, indent=2))
    print(f"[spmg] timing json written: {cache / 'spmg_timing.json'}")


if __name__ == "__main__":
    main()
