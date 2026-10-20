#!/usr/bin/env python3
# =============================================================================
# bench/m1s/sbs/gen_fixtures.py · M1s acceptance-gate SBS catalog generation bench deterministic fixtures
# (docs/ARCHITECTURE.md §8 budget row: catalog generation SBS96(10⁶ mutations)≥50× SPMG and
#   <5s single-core. CI only ships  sanity bound, this bench does not enter CI ).
#
# generated artifacts (all land under cache/,gitignore;seeds are recorded in the manifest; reruns are byte-reproducible):
#   cache/genome.2bit          our ms_tally synthetic reference (2 chromosomes × 2.5Mb,
#                              src/rust/catalog/tests/genome/fixture.rs of the
#                              enlarged version of the generator:chr1 TCAG…,chr2 (i*7+3) pattern,
#                              carries N blocks;2bit packing T=0 C=1 A=2 G=3, first base
#                              is in the high bits,N blocks write 0——agrees with fixture.rs )
#   cache/fasta/{1,2}.fasta.gz SPMG custom-genome install input (file name=chromosome name,
#                              save_chrom_strings naming convention;gzip mtime=0)
#   cache/transcripts.txt      SPMG install required transcript records (one
#                              full-length +1 +1 strand transcripts;SBS96 is independent of transcription; it only requires
#                              install_chromosomes_tsb nonempty validation)
#   cache/vcf/{S1,S2}.vcf      SPMG input: one per sample VCF(SPMG recognizes samples by file name
#                              samples); coordinate-sorted; total 10⁶ SNV
#   cache/variants.csv         our input:chrom,pos,ref,alt,sample(1-based)
#   cache/sanity_vcf/{S1,S2}.vcf + cache/sanity.csv
#                              correctness cross-check subset (100 mutations:92 at least ≥2bp apart:
#                              SNV + 2 pairs of same-sample adjacent SNV(→DBS, excluded from both sides into the
#                              SBS96)+ 1 cross-sample adjacent pair SNV(both sides keep SBS,
#                              SPMG dinuc_sub==1 is the single-sample criterion)+ 2 items close to
#                              the chromosome edges).
#
# SPMG and ours consume the same sequence (thepattern function agrees bit by bit ⇒ REF necessarily match the reference).
# =============================================================================
import gzip
import time
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
CACHE = HERE / "cache"

CHROM_LEN = 2_500_000
N_VAR = 1_000_000
SEED = 20260928  # numpy PCG64; recorded in the manifest
BASES = np.frombuffer(b"TCAG", dtype=np.uint8)  # fixture.rs alphabet table (ASCII)
# 2bit packing codes (UCSC):T=0 C=1 A=2 G=3 —— BASES index is the packing code
CODE = np.full(256, 255, dtype=np.uint8)
for _i, _letter in enumerate(BASES):
    CODE[_letter] = _i
CHROMS = ["1", "2"]  # SPMG side chromosome names (= FASTA file-name stem); our CSV use chr1/chr2

N_BLOCKS = {
    "1": [(1_000, 10), (1_250_000, 10), (2_499_000, 10)],
    "2": [(500_000, 5), (1_500_000, 5)],
}


def pattern(chrom: str) -> np.ndarray:
    """the deterministic pattern of the same family as fixture.rs specs() the enlarged variant)."""
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
    """±2bp positions whose window touches N the blocks (both sides will skip, thebench fixtures dodge them directly)."""
    bad = np.zeros(pos0.shape, dtype=bool)
    for start, length in N_BLOCKS[chrom]:
        bad |= (pos0 >= start - 2) & (pos0 <= start + length + 1)
    return bad


def write_2bit(path: Path) -> None:
    """UCSC 2bit(LE): the enlarged fixture.rs layout. The chromosome names = chr1/chr2
    (our variants.csv exact-match names;SPMG the FASTA file names remain 1/2)"""
    import struct

    recs = []
    for chrom in CHROMS:
        seq = pattern(chrom)
        for start, length in N_BLOCKS[chrom]:
            seq[start:start + length] = 0  # N block packed bits write 0(fixture.rs as in fixture.rs)
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
    # mtime=0: deterministic gzip(byte-identical on reruns)
    with open(path, "wb") as raw:
        with gzip.GzipFile(fileobj=raw, mode="wb", mtime=0) as gz:
            gz.write(data)


def _alt_for(ref: np.ndarray, rng) -> np.ndarray:
    """in the packing-code domain +1..+3(mod 4) guaranteed to be another base, mapped back to letters."""
    shift = rng.integers(1, 4, size=ref.shape)
    alt = BASES[(CODE[ref] + shift) % 4]
    assert not np.any(alt == ref), "alt must differ from ref"
    return alt


def _resample_n_zone_dense(pos0: np.ndarray, chrom: str, rng):
    """dense arm: independent resampling avoiding only the N ±2 window; keeps natural adjacency/duplicate density)."""
    for _ in range(64):
        bad = in_n_zone(pos0, chrom)
        if not bad.any():
            return pos0
        pos0[bad] = rng.integers(2, CHROM_LEN - 2, size=int(bad.sum()))
    raise RuntimeError("N-zone rejection did not converge")


def _resample_n_zone(pos0: np.ndarray, chrom: str, rng):
    """resample the positions that touch ±2bp the N blocks inside the same odd lattice: draw without replacement +  + avoid N, avoid duplicates;
    then filter, iterating until fully clean; assert uniqueness and the minimum gap overall."""
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

    # Dedupe (resampling may collide with kept positions): redraw duplicated values in batches until unique
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
    """Main arm (dbsfree): 10⁶ SNV, same-sample same-chromosome minimum spacing 2(odd lattice
    pos0 = 3 + 2·slot) and thus naturally duplicate-free (pos0,sample unique)⇒ the two-sided record sets align record by record
    aligned and SBS96 comparable cell by cell (SPMG 1.3.6SPMG 1.3.6 drops fully duplicate records whole-row and also counts the DBS pair
    members into SBS96——see the sanity arm and result.md  P0 note). Cross-sample adjacency
    still happens and both sides consistently judge it as SBS(dinuc the criterion is single-sample)."""
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
    """Secondary arm (dense): independent uniform sampling (natural adjacency density; DBS pairs and fully DBS duplicates
    duplicate records); dedupe by (chrom,pos0,sample) so the two record sets agree——SPMG drops
    fully duplicate records (1.3.6 measured1.3.6 occurrences of 16,019 duplicate single base substitution);
    we drop them wholesale, which is more conservative. Used for full-scale total reconciliation and speed reference."""
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
    # Dedupe: for the same (chrom,pos0,sample) only one record is kept
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
    """100 mutation cross-check subset (construction see the file-header note)."""
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

    # 92 regular ≥2bp , SNV(alternating the two samples, alternating the two chromosomes)
    p = 100
    while len(rows) < 92:
        chrom = CHROMS[len(rows) % 2]
        if not zone_clean(chrom, p):
            p += 10
            continue
        add(chrom, p, f"S{1 + len(rows) % 2}")
        p += 7 + int(rng.integers(0, 5))

    # 2 same-sample adjacent pairs (→ DBS: excluded from both sides out of SBS96)
    for chrom, base, sample in (("1", 300_000, "S1"), ("2", 800_000, "S2")):
        add(chrom, base, sample)
        add(chrom, base + 1, sample)

    # 1 cross-sample adjacent pair (both sides keep SBS:dinuc the criterion is single-sample)
    add("1", 1_500_000, "S1")
    add("1", 1_500_001, "S2")

    # 2 extreme legal positions (0-based 2 and LEN-3:±2 window stays exactly in bounds)
    add("2", 2, "S1")
    add("2", CHROM_LEN - 3, "S2")

    assert len(rows) == 100, len(rows)
    return rows


def write_vcf(path: Path, rows, chrom_prefix: bool):
    rows = sorted(rows, key=lambda r: r[1])  # coordinate-sorted (SPMG input convention)
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
          f"S2={sum(1 for r in rows if r[4]=='S2')}; same-sample same-chromosome minimum spacing 2)")
    print(f"  dense (after dedupe): {len(drows)}")
    print(f"  sanity: {len(srows)} rows, same-sample adjacent pairs (-> DBS) = {n_dbs_like}")


if __name__ == "__main__":
    main()
