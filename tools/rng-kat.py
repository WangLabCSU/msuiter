#!/usr/bin/env python3
"""Independent known-answer test for the msuiter in-house PCG64 stream layout.

Recomputes, in pure-stdlib Python, every golden vector frozen in
src/rust/engine/src/rng.rs (canonical stream layout v1) plus the published
SplitMix64 known-answer values, and compares bit-for-bit.

The Rust golden tests freeze the vectors; this script re-derives them from
the documented layout with a second implementation so the two cannot drift
together unnoticed. U-M0-07 CI runs this on every push.

Layout reference: src/rust/engine/src/rng.rs module docs (layout v1).
"""
import re
import sys
import pathlib

M64 = (1 << 64) - 1
M128 = (1 << 128) - 1


def mix64(z: int) -> int:
    x = z & M64
    x = ((x ^ (x >> 30)) * 0xBF58476D1CE4E5B9) & M64
    x = ((x ^ (x >> 27)) * 0x94D049BB133111EB) & M64
    return (x ^ (x >> 31)) & M64


class SplitMix64:
    def __init__(self, seed: int):
        self.state = seed & M64

    def next_word(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & M64
        return mix64(self.state)


def rotr64(x: int, r: int) -> int:
    r &= 63
    if r == 0:
        return x & M64
    return ((x >> r) | (x << (64 - r))) & M64


class MsRng:
    """PCG64 (128-bit LCG + XSL-RR) with canonical stream layout v1."""

    def __init__(self, master_seed: int, replicate: int = 0, rank: int = 0,
                 fold: int = 0, layout_id: int = 0, pcg_mult: int = 0):
        h = mix64(layout_id)
        h = mix64(h ^ (master_seed & M64))
        h = mix64(h ^ (replicate & M64))
        h = mix64(h ^ (rank & M64))
        h = mix64(h ^ (fold & M64))
        exp = SplitMix64(h)
        initstate = exp.next_word()
        initseq = exp.next_word()
        self.mult = pcg_mult
        self.inc = ((initseq << 1) | 1) & M128
        self.state = 0
        self._step()
        self.state = (self.state + initstate) & M128
        self._step()

    def _step(self) -> None:
        self.state = (self.state * self.mult + self.inc) & M128

    def next_u64(self) -> int:
        # canonical pcg64: XSL-RR on the POST-step state (pcg-cpp
        # output_previous = false for 128-bit states; numpy-compatible)
        self._step()
        rot = self.state >> 122
        xsl = ((self.state >> 64) & M64) ^ (self.state & M64)
        return rotr64(xsl, rot)


def parse_const(text: str, name: str) -> int:
    m = re.search(rf"const {name}: u64 = (0x[0-9A-Fa-f_]+);", text)
    if not m:
        raise SystemExit(f"FAIL: {name} not found in rng.rs")
    return int(m.group(1).replace("_", ""), 16)


def parse_goldens(text: str):
    pat = re.compile(
        r"first_words\(\s*(\d+)\s*,\s*"
        r"(StreamId::ZERO|StreamId\s*\{[^}]*\})\s*\)\s*,\s*\[(.*?)\]",
        re.S,
    )
    cases = []
    for m in pat.finditer(text):
        seed = int(m.group(1))
        sid = m.group(2)
        if "ZERO" in sid:
            rep = rank = fold = 0
        else:
            grab = lambda k: int(re.search(rf"{k}\s*:\s*(\d+)", sid).group(1))
            rep, rank, fold = grab("replicate"), grab("rank"), grab("fold")
        words = [int(w.replace("_", ""), 16)
                 for w in re.findall(r"0x[0-9a-fA-F_]+", m.group(3))]
        cases.append((seed, rep, rank, fold, words))
    return cases


def main() -> int:
    src = (pathlib.Path(__file__).resolve().parent.parent
           / "src" / "rust" / "engine" / "src" / "rng.rs")
    text = src.read_text()
    layout_id = parse_const(text, "LAYOUT_ID")
    pcg_mult = re.search(r"const PCG_MULT: u128 = (0x[0-9A-Fa-f_]+);", text)
    if not pcg_mult:
        raise SystemExit("FAIL: PCG_MULT not found in rng.rs")
    pcg_mult = int(pcg_mult.group(1).replace("_", ""), 16)

    cases = parse_goldens(text)
    if len(cases) != 3:
        raise SystemExit(f"FAIL: expected 3 golden cases, found {len(cases)}")

    ok = True
    for seed, rep, rank, fold, want in cases:
        rng = MsRng(seed, rep, rank, fold,
                    layout_id=layout_id, pcg_mult=pcg_mult)
        got = [rng.next_u64() for _ in want]
        good = got == want
        ok = ok and good
        print(f"{'OK  ' if good else 'FAIL'} golden seed={seed} "
              f"stream=({rep},{rank},{fold}) [{len(want)} words]")

    sm = SplitMix64(0)
    w0, w1 = sm.next_word(), sm.next_word()
    kat = w0 == 0xE220A8397B1DCDAF and w1 == 0x6E789E6AA1B965F4
    ok = ok and kat
    print(f"{'OK  ' if kat else 'FAIL'} SplitMix64 published KAT (seed 0)")

    print("rng-kat: PASS" if ok else "rng-kat: FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
