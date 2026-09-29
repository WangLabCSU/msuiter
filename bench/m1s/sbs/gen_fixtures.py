#!/usr/bin/env python3
# =============================================================================
# bench/m1s/sbs/gen_fixtures.py · M1s 验收门 SBS 目录生成 bench 的确定性夹具
# （docs/ARCHITECTURE.md §8 预算行：目录生成 SBS96（10⁶ 突变）≥50× SPMG 且
#   <5s 单核。CI 只放 sanity bound，本 bench 不进 CI。）
#
# 生成物（全部落在 cache/，gitignore；seeds 记录在案，重跑逐字节可复现）：
#   cache/genome.2bit          我方 ms_tally 的合成参考（2 染色体 × 2.5Mb，
#                              src/rust/catalog/tests/genome/fixture.rs 夹具
#                              生成器的放大版：chr1 TCAG…、chr2 (i*7+3) 模式，
#                              带 N blocks；2bit 打包 T=0 C=1 A=2 G=3，首碱基
#                              在高位，N 块下打包位写 0——与 fixture.rs 一致）
#   cache/fasta/{1,2}.fasta.gz SPMG 自定义基因组安装输入（文件名=染色体名，
#                              save_chrom_strings 的命名约定；gzip mtime=0）
#   cache/transcripts.txt      SPMG install 必需的转录本文件（每染色体一条
#                              全长 +1 链转录本；SBS96 与转录无关，仅满足
#                              install_chromosomes_tsb 的非空校验）
#   cache/vcf/{S1,S2}.vcf      SPMG 输入：每样本一个 VCF（SPMG 以文件名识别
#                              样本），坐标排序，共 10⁶ SNV
#   cache/variants.csv         我方输入：chrom,pos,ref,alt,sample（1-based）
#   cache/sanity_vcf/{S1,S2}.vcf + cache/sanity.csv
#                              正确性对拍子集（100 变异：92 个间隔 ≥2bp 的
#                              SNV + 2 对同样本相邻 SNV（→DBS，双侧排除出
#                              SBS96）+ 1 对跨样本相邻 SNV（双侧均保持 SBS，
#                              SPMG dinuc_sub==1 为单样本判据）+ 2 个贴近
#                              染色体边缘的极端合法位置）
#
# SPMG 与我方消费同一序列（pattern 函数逐位一致 ⇒ REF 与参考必然一致）。
# =============================================================================
import gzip
import time
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
CACHE = HERE / "cache"

CHROM_LEN = 2_500_000
N_VAR = 1_000_000
SEED = 20260928  # numpy PCG64，记录在案
BASES = np.frombuffer(b"TCAG", dtype=np.uint8)  # fixture.rs 的字母表（ASCII）
# 2bit 打包码（UCSC）：T=0 C=1 A=2 G=3 —— BASES 的下标即打包码
CODE = np.full(256, 255, dtype=np.uint8)
for _i, _letter in enumerate(BASES):
    CODE[_letter] = _i
CHROMS = ["1", "2"]  # SPMG 侧染色体名（= FASTA 文件名词干）；我方 CSV 用 chr1/chr2

N_BLOCKS = {
    "1": [(1_000, 10), (1_250_000, 10), (2_499_000, 10)],
    "2": [(500_000, 5), (1_500_000, 5)],
}


def pattern(chrom: str) -> np.ndarray:
    """与 fixture.rs specs() 同族的确定性模式（放大版）。"""
    i = np.arange(CHROM_LEN, dtype=np.int64)
    if chrom == "1":
        return BASES[i % 4]
    return BASES[(i * 7 + 3) % 4]


def seq_with_n(chrom: str) -> np.ndarray:
    seq = pattern(chrom).copy()
    for start, length in N_BLOCKS[chrom]:
        seq[start:start + length] = ord("N")
    return seq


def in_n_zone(pos0: np.ndarray, chrom: str) -> np.ndarray:
    """±2bp 窗口触及 N 块的位置（双侧都会 skip，bench 夹具直接避开）。"""
    bad = np.zeros(pos0.shape, dtype=bool)
    for start, length in N_BLOCKS[chrom]:
        bad |= (pos0 >= start - 2) & (pos0 <= start + length + 1)
    return bad


def write_2bit(path: Path) -> None:
    """UCSC 2bit（LE）：放大版 fixture.rs 布局。染色体名 = chr1/chr2
    （我方 variants.csv 的精确匹配名；SPMG 的 FASTA 文件名仍为 1/2）。"""
    import struct

    recs = []
    for chrom in CHROMS:
        seq = pattern(chrom)
        for start, length in N_BLOCKS[chrom]:
            seq[start:start + length] = 0  # N 块下打包位写 0（fixture.rs 同）
        codes = CODE[seq]
        pad = (-len(codes)) % 4
        codes = np.concatenate([codes, np.zeros(pad, dtype=np.uint8)])
        codes = codes.reshape(-1, 4)
        packed = (codes[:, 0] << 6) | (codes[:, 1] << 4) | (codes[:, 2] << 2) | codes[:, 3]
        nb = N_BLOCKS[chrom]
        recs.append((f"chr{chrom}", len(seq), nb, packed.astype(np.uint8).tobytes()))

    off = 16
    for name, _size, nb, _dna in recs:
        off += 1 + len(name) + 4
    index = b""
    body = b""
    for name, size, nb, dna in recs:
        index += bytes([len(name)]) + name.encode() + struct.pack("<I", off)
        rec = struct.pack("<II", size, len(nb))
        rec += b"".join(struct.pack("<I", s) for s, _ in nb)
        rec += b"".join(struct.pack("<I", l) for _, l in nb)
        rec += struct.pack("<II", 0, 0)  # soft blocks = 0, reserved
        rec += dna
        body += rec
        off += len(rec)
    with open(path, "wb") as fh:
        fh.write(struct.pack("<IIII", 0x1A412743, 0, len(recs), 0))
        fh.write(index)
        fh.write(body)


def write_fasta(path: Path, chrom: str) -> None:
    seq = seq_with_n(chrom)
    lines = [f">{chrom} synthetic bench chromosome {chrom}"]
    for i in range(0, len(seq), 60):
        lines.append(seq[i:i + 60].tobytes().decode("ascii"))
    data = ("\n".join(lines) + "\n").encode("ascii")
    # mtime=0：确定性 gzip（重跑逐字节一致）
    with open(path, "wb") as raw:
        with gzip.GzipFile(fileobj=raw, mode="wb", mtime=0) as gz:
            gz.write(data)


def _alt_for(ref: np.ndarray, rng) -> np.ndarray:
    """打包码域 +1..+3（mod 4）必为另一碱基，映射回字母。"""
    shift = rng.integers(1, 4, size=ref.shape)
    alt = BASES[(CODE[ref] + shift) % 4]
    assert not np.any(alt == ref), "alt must differ from ref"
    return alt


def _resample_n_zone_dense(pos0: np.ndarray, chrom: str, rng):
    """dense 臂：仅避 N ±2 窗的独立重采样（保留自然相邻/重复密度）。"""
    for _ in range(64):
        bad = in_n_zone(pos0, chrom)
        if not bad.any():
            return pos0
        pos0[bad] = rng.integers(2, CHROM_LEN - 2, size=int(bad.sum()))
    raise RuntimeError("N-zone rejection did not converge")


def _resample_n_zone(pos0: np.ndarray, chrom: str, rng):
    """把 ±2bp 触 N 块的位置在同奇数栅格内重采样：无放回抽签 + 「避 N、避重」
    过滤，迭代到全净；整体断言唯一性与最小间隔。"""
    slot_max = (CHROM_LEN - 3 - 3) // 2

    def in_n(v: np.ndarray) -> np.ndarray:
        return in_n_zone(v, chrom)

    for _ in range(64):
        bad = np.flatnonzero(in_n(pos0))
        if len(bad) == 0:
            break
        pos0[bad] = 3 + 2 * rng.choice(slot_max + 1, size=len(bad), replace=False)
    else:
        raise RuntimeError("N-zone rejection did not converge")

    # 去重（重采样可能与保留位冲突）：对重复值按批重抽，直到唯一
    for _ in range(64):
        uniq, counts = np.unique(pos0, return_counts=True)
        dups = uniq[counts > 1]
        if len(dups) == 0:
            break
        mask = np.isin(pos0, dups)
        k = int(mask.sum())
        used = set(np.unique(pos0[~mask]).tolist())
        fixed = []
        cand = 3 + 2 * rng.choice(slot_max + 1, size=k + 256, replace=False)
        for v in cand:
            if v not in used and not in_n(np.array([v]))[0]:
                used.add(int(v))
                fixed.append(int(v))
            if len(fixed) == k:
                break
        if len(fixed) < k:
            raise RuntimeError("dedupe redraw starved")
        pos0[mask] = fixed
    else:
        raise RuntimeError("dedupe did not converge")

    assert len(np.unique(pos0)) == len(pos0), "odd-grid positions must be unique"
    assert np.all(np.diff(np.sort(pos0)) >= 2), "min gap 2 must hold (dbsfree arm)"
    return pos0


def sample_variants():
    """主臂（dbsfree）：10⁶ SNV，同样本同染色体位置最小间隔 2（奇数栅格
    pos0 = 3 + 2·slot），天然无重复（pos0,sample 唯一）⇒ 双侧记录集逐条
    对齐、SBS96 逐格可比（SPMG 1.3.6 会整条丢弃完全重复记录、且把 DBS 对
    成员一并计入 SBS96——见 sanity 臂与 result.md 的 P0 注记）。跨样本相邻
    仍会发生并被双侧一致判为 SBS（dinuc 判据是单样本的）。"""
    rng = np.random.default_rng(SEED)
    per_sample_chrom = N_VAR // 4  # 250k
    slot_max = (CHROM_LEN - 3 - 3) // 2
    rows = []
    for s in ("S1", "S2"):
        per_chrom_rows = []
        for chrom in CHROMS:
            slots = np.sort(rng.choice(slot_max + 1, size=per_sample_chrom,
                                       replace=False))
            pos0 = 3 + 2 * slots
            pos0 = _resample_n_zone(pos0, chrom, rng)
            ref = pattern(chrom)[pos0]
            alt = _alt_for(ref, rng)
            per_chrom_rows.append((chrom, pos0, ref, alt))
        for c, (chrom, pos0, ref, alt) in enumerate(per_chrom_rows):
            for i in range(per_sample_chrom):
                rows.append((f"chr{chrom}", int(pos0[i]) + 1,
                             chr(ref[i]), chr(alt[i]), s))
    rows.sort(key=lambda r: (r[0], r[1]))
    return rows


def sample_variants_dense():
    """次臂（dense）：独立均匀采样（自然相邻密度，天然出现 DBS 对与完全
    重复记录）；按 (chrom,pos0,sample) 去重使两侧记录集一致——SPMG 会丢弃
    完全重复记录（1.3.6 实测 16,019 条「duplicate single base substitution」），
    我们整位丢弃更保守。用于全尺度总量对账与速度参考。"""
    rng = np.random.default_rng(SEED)
    chrom_idx = rng.integers(0, 2, size=N_VAR)
    pos0 = rng.integers(2, CHROM_LEN - 2, size=N_VAR)
    for c, chrom in enumerate(CHROMS):
        mask = chrom_idx == c
        idx = np.flatnonzero(mask)
        pos0[idx] = _resample_n_zone_dense(pos0[idx], chrom, rng)
    ref = np.empty(N_VAR, dtype=np.uint8)
    for c, chrom in enumerate(CHROMS):
        mask = chrom_idx == c
        ref[mask] = pattern(chrom)[pos0[mask]]
    alt = _alt_for(ref, rng)
    sample = np.where(np.arange(N_VAR) % 2 == 0, "S1", "S2")
    # 去重：同 (chrom,pos0,sample) 只保留一条
    seen = set()
    rows = []
    order = np.argsort(pos0 * 2 + chrom_idx, kind="stable")
    for i in order:
        key = (int(chrom_idx[i]), int(pos0[i]), sample[i])
        if key in seen:
            continue
        seen.add(key)
        rows.append((f"chr{chrom_idx[i] + 1}", int(pos0[i]) + 1,
                     chr(ref[i]), chr(alt[i]), sample[i]))
    rows.sort(key=lambda r: (r[0], r[4], r[1]))
    return rows


def sanity_rows():
    """100 变异对拍子集（构图见文件头注释）。"""
    rng = np.random.default_rng(SEED + 1)
    rows = []

    def add(chrom, pos0, sample):
        seq = pattern(chrom)
        ref = chr(seq[pos0])
        alt = chr(BASES[(CODE[seq[pos0]] + 1 + int(rng.integers(0, 3))) % 4])
        assert alt != ref
        rows.append((f"chr{chrom}", pos0 + 1, ref, alt, sample))

    def zone_clean(chrom, pos0):
        return not in_n_zone(np.array([pos0]), chrom)[0]

    # 92 个间隔 ≥2bp 的常规 SNV（两样本交替、两染色体交替）
    p = 100
    while len(rows) < 92:
        chrom = CHROMS[len(rows) % 2]
        if not zone_clean(chrom, p):
            p += 10
            continue
        add(chrom, p, f"S{1 + len(rows) % 2}")
        p += 7 + int(rng.integers(0, 5))

    # 2 对同样本相邻（→ DBS：双侧均排除出 SBS96）
    for chrom, base, sample in (("1", 300_000, "S1"), ("2", 800_000, "S2")):
        add(chrom, base, sample)
        add(chrom, base + 1, sample)

    # 1 对跨样本相邻（双侧均保持 SBS：dinuc 判据是单样本的）
    add("1", 1_500_000, "S1")
    add("1", 1_500_001, "S2")

    # 2 个极端合法位置（0-based 2 与 LEN-3：±2 窗恰好不出界）
    add("2", 2, "S1")
    add("2", CHROM_LEN - 3, "S2")

    assert len(rows) == 100, len(rows)
    return rows


def write_vcf(path: Path, rows, chrom_prefix: bool):
    rows = sorted(rows, key=lambda r: r[1])  # 坐标排序（SPMG 输入约定）
    with open(path, "w") as fh:
        fh.write("##fileformat=VCFv4.2\n")
        fh.write("##source=msuiter-m1s-bench synthetic fixtures\n")
        fh.write("#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n")
        for chrom, pos, ref, alt, _s in rows:
            name = chrom if chrom_prefix else chrom.removeprefix("chr")
            fh.write(f"{name}\t{pos}\t.\t{ref}\t{alt}\t.\tPASS\t.\n")


def main():
    t0 = time.perf_counter()
    (CACHE / "fasta").mkdir(parents=True, exist_ok=True)
    (CACHE / "vcf").mkdir(parents=True, exist_ok=True)
    (CACHE / "sanity_vcf").mkdir(parents=True, exist_ok=True)

    write_2bit(CACHE / "genome.2bit")
    for chrom in CHROMS:
        write_fasta(CACHE / "fasta" / f"{chrom}.fasta.gz", chrom)
    with open(CACHE / "transcripts.txt", "w") as fh:
        for chrom in CHROMS:
            fh.write(f"gene{chrom}\ttx{chrom}\t{chrom}\t1\t1\t{CHROM_LEN}\n")

    rows = sample_variants()
    assert len(rows) == N_VAR
    with open(CACHE / "variants.csv", "w") as fh:
        fh.write("chrom,pos,ref,alt,sample\n")
        for r in rows:
            fh.write(",".join(map(str, r)) + "\n")
    for s in ("S1", "S2"):
        write_vcf(CACHE / "vcf" / f"{s}.vcf", [r for r in rows if r[4] == s],
                  chrom_prefix=False)

    drows = sample_variants_dense()
    with open(CACHE / "variants_dense.csv", "w") as fh:
        fh.write("chrom,pos,ref,alt,sample\n")
        for r in drows:
            fh.write(",".join(map(str, r)) + "\n")
    (CACHE / "vcf_dense").mkdir(exist_ok=True)
    for s in ("S1", "S2"):
        write_vcf(CACHE / "vcf_dense" / f"{s}.vcf", [r for r in drows if r[4] == s],
                  chrom_prefix=False)

    srows = sanity_rows()
    with open(CACHE / "sanity.csv", "w") as fh:
        fh.write("chrom,pos,ref,alt,sample\n")
        for r in srows:
            fh.write(",".join(map(str, r)) + "\n")
    for s in ("S1", "S2"):
        write_vcf(CACHE / "sanity_vcf" / f"{s}.vcf", [r for r in srows if r[4] == s],
                  chrom_prefix=False)

    n_dbs_like = sum(
        1 for a, b in zip(srows, srows[1:])
        if a[0] == b[0] and a[4] == b[4] and b[1] - a[1] == 1
    )
    print(f"fixtures written to {CACHE} in {time.perf_counter()-t0:.1f}s")
    print(f"  main (dbsfree): {len(rows)} (S1={sum(1 for r in rows if r[4]=='S1')}, "
          f"S2={sum(1 for r in rows if r[4]=='S2')}; 同样本同染色体最小间隔 2)")
    print(f"  dense (去重后): {len(drows)}")
    print(f"  sanity: {len(srows)} rows, same-sample adjacent pairs (-> DBS) = {n_dbs_like}")


if __name__ == "__main__":
    main()
