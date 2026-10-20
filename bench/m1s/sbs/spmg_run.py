#!/usr/bin/env python3
# =============================================================================
# bench/m1s/sbs/spmg_run.py · SPMG baseline (runs inside bench/m1s/.venv )
#
# prerequisites (one-shot, idempotent):SigProfilerMatrixGenerator 1.3.6 custom-genome install——
#   genInstall.install("SYN5M", custom=True, fastaPath=cache/fasta,
#                      transcriptPath=cache/transcripts.txt)
#   (install_chromosomes for custom goes through system gzip -d + pure Python string-file;tsb goes
#   the full-length we provide +1 strand transcript records; .venv site-packages  nonempty validation).
#
# known upstream limitations (runtime bypass in this script; zero changes to upstream compute paths):
#   SPMG 1.3.6 generation entry uses the hardcoded CHECKSUMS whitelist to validate genomes
#   (reference_genome_manager.is_genome_installed:genome is not present in the dict , it directly
#   raise "has not been installed"), custom genomes can never pass it. This script
#   at runtime registers the local install products md5 into the dict(= so that it checks our own local files
#   do a download-integrity check); it modifies no upstream file; the matrix-generation code path stays fully original.
#   —— recorded verbatim in result.md.
#
# timing: sanity(100 mutations) is run once (doubling as the correctness cross-check input); the full set (10⁶) is run once,
#   perf_counter wall clock (SPMG has no warm-up reuse value; the cost of repeated reruns is minute-scale——caliber
#   is recorded verbatim as a single wall clock).
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
    """at runtime register the local tsb products md5(bypassing the upstream hardcoded whitelist; see the file-header note)."""
    rd = ref_install.reference_dir()
    tsb_dir = Path(rd.get_tsb_dir()) / GENOME
    entries = {}
    for p in sorted(tsb_dir.glob("*.txt")):
        entries[p.name[:-4]] = hashlib.md5(p.read_bytes()).hexdigest()
    reference_genome_manager.CHECKSUMS[GENOME] = entries
    print(f"[spmg] registered local checksums for {GENOME}: {len(entries)} files")


def run(project: str, vcf_dir: Path, out_tsv: Path, cwd: Path) -> dict:
    # SPMG caches per-chromosome converted products under <vcf_dir>/input/ ; after fixture regeneration it must
    # be dropped, otherwise reruns consume stale converted state (measured: it silently reuses the old record set).
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
    os.chdir(cache)  # SPMG puts output/ under CWD (thestandard CLI behavior)
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
