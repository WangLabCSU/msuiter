# bench/xval — sigminer / MutationalPatterns toy cross-validation (SBS96)

M1s acceptance gate, golden-fixture row "sigminer/MP toy cross-validation".
msuiter's SBS96 catalog is compared cell-by-cell (label-aligned) against:

1. **sigminer** 2.3.1 (`read_maf` -> `sig_tally`, CRAN),
2. **MutationalPatterns** 3.20.1 (`mut_matrix`, optional; skipped if absent),
3. a **pure-R naive recomputation** from the reference sequence itself
   (anti-"false agreement" third opinion).

Input: 264 synthetic SNVs on three REAL hg19 windows (chr1/chr7/chr12,
550 kb total, ACGT-verified) across 3 samples -- one targeted SNV per COSMIC
channel (96, so every channel cell is exercised) plus 168 seeded random SNVs,
all >= 3 bp apart (no adjacent-pair DBS merging, unambiguous +/-1 flanks).

## Run

```sh
Rscript bench/xval/run_xval.R        # ~1 min; writes artifacts here
```

Requires: `sigminer`, `BSgenome.Hsapiens.UCSC.hg19` (both read their side of
the reference from the BSgenome; msuiter reads the same sequence through its
own 2bit path, `patch_hg19.2bit`, written by the script with the same packing
contract as `tests/testthat/helper-tally.R`). `MutationalPatterns` is
optional: absent -> recorded and skipped; present -> third matrix column.

Reference numbers and the findings ledger (channel-order difference vs MP,
REF-validation difference vs both R packages, upstream API edges) live in
`result.md`. A distilled, CI-safe regression guard of the same comparison
runs as `tests/testthat/test-xval-sigminer.R` (skips when sigminer or the
BSgenome data package are not installed; both are Suggests).

## Artifacts

| file | content |
|---|---|
| `variants.csv` | the 264 toy SNVs (hg19 global coordinates) |
| `patch_hg19.2bit` | msuiter-side reference patch genome |
| `counts_msuiter.csv` / `counts_sigminer.csv` / `counts_MP.csv` / `counts_naiveR.csv` | 96 x 3 count matrices |
| `label_audit.csv` | channel vocabulary / order audit |
| `run.log` | full run transcript |
| `result.md` | verdict, numbers, methodology, findings ledger |
