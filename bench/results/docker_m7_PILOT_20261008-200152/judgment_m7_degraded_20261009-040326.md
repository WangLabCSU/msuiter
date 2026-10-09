# U-M7-02 fairness attestation — profile=degraded, adapter=docker, provider=synthetic

This is the **FAIRNESS ATTESTATION** half of the authoritative run: it
certifies *how* the cells ran, not *who won*.

- single ground truth: all competitors saw msuiter-generated simulated
  counts from the frozen G0 simulator (master seed 20260928, data streams bit-identical to G0)
- documented defaults only: zero threshold/parameter overrides (memo §3)
- frozen thread caps on every container cell: OMP_NUM_THREADS=1, OMP_THREAD_LIMIT=1, R_LIMIT_THREADS=1, GOMAXPROCS=1, MSUITER_THREADS=1, STAN_OMP_NUM_THREADS=1, OPENBLAS_NUM_THREADS=1
- one Docker VM for every cell (10 vCPU / 8 GB class), no host-side
  execution of container competitors (§4.1/§4.2)
- seeds: m7-tool-namespaced derivation, all on disk (Seeds.txt); commit 5f6d14ed930f0c351b90db72f1ee1152a0a10080

| competitor | version | image ref | image digest | status |
|---|---|---|---|---|
| sigminer | 2.3.1 | msuiter-sigminer:slice3-r2 | sha256:c2a52c719f6ed2f45184e4fd61dcec767596b82c04061006c7ec9f5d0fb91157 | ready |
| sigprofiler | v1.1.5 | m7-sigprofiler:spa-1.1.5 | sha256:7dba2f43ad3a3858ed1cfdedd278c9c2f52a665fd4c18ac91a482b74258bfbed | ready |

- cells: 10 total — fail: 5, ok: 5
- timings table: timings_m7_degraded_20261009-040326.csv (G0 six-column prefix + cpu_seconds; every measured second attributable)

Honest footer: this is harness output serving as the adjudication gate.
Authoritative competitor measurement is the docker-adapter run at the
frozen protocol; smoke/mock passes prove pipeline plumbing only. This
half attests fairness, not outcomes; the Hungarian P/R/F1 scoring
verdict (U-M7-02 scoring slice, ARCHITECTURE §8) is appended below on
the final pass, produced by the scoring engine over the cachedir.

---

## Scoring verdict — Hungarian-matched P/R/F1 (ARCHITECTURE §8)

Harness output; formal adjudication only via the frozen protocol. Profile `degraded`, adapter `docker`.
This half is a pure function of the committed cell artifacts plus the
seed-derived ground truth: no RNG at score time, same cachedir =>
byte-identical table.

- primary metric: Hungarian one-to-one assignment under catalog
  cosine, match tolerance **0.85** — the frozen
  midpoint of the 0.80–0.90 robustness band (benchmark memo
  2026-10-05 §3; the band is protocol, the midpoint is the
  least-chosen choice). TODO(paper): pin the citation for the band.
- below-tolerance pairs are rejected by the matcher and fall out as
  FP/FN — never as weak matches.
- full long table (cell | signature | arm_rollup | n_rollup rows,
  count-pooled rollups): the benchmark_m7_<ts>.csv beside this document.

- unscorable cells reported honestly (skip-not-skip): `sigminer__comp_mmr__N100` (skipped:no-artifacts), `sigminer__comp_mmr__N1000` (skipped:no-artifacts), `sigminer__main__N100` (skipped:no-artifacts), `sigminer__main__N1000` (skipped:no-artifacts), `sigminer__nb__N1000` (skipped:no-artifacts)

### Adjudication table — primary (judge) arms

5 cells, 5 samples, 8 matched pairs pooled below.

| tool | version | arm | N | n_samples | tp | fp | fn |
|---|---|---|---|---|---|---|---|
| precision | recall | f1 | | | | | |
|---|---|---|---|---|---|---|---|
| sigprofiler | v1.1.5 | comp_mmr | — | 2 | 4 | 3 | 12 |
| 0.571429 | 0.250000 | 0.347826 | | | | | |
| sigprofiler | v1.1.5 | main | — | 2 | 2 | 7 | 8 |
| 0.222222 | 0.200000 | 0.210526 | | | | | |
| sigprofiler | v1.1.5 | None | 100 | 2 | 3 | 4 | 10 |
| 0.428571 | 0.230769 | 0.300000 | | | | | |
| sigprofiler | v1.1.5 | None | 1000 | 2 | 3 | 6 | 10 |
| 0.333333 | 0.230769 | 0.272727 | | | | | |

### Sensitivity report columns (judge=False)

Report-only: the frozen grid flags these arms ``judge=False``;
they are reported, never mixed into adjudication (clause b).

| tool | version | arm | N | n_samples | tp | fp | fn |
|---|---|---|---|---|---|---|---|
| precision | recall | f1 | | | | | |
|---|---|---|---|---|---|---|---|
| sigprofiler | v1.1.5 | nb | — | 1 | 2 | 3 | 3 |
| 0.400000 | 0.400000 | 0.400000 | | | | | |
| sigprofiler | v1.1.5 | None | 1000 | 1 | 2 | 3 | 3 |
| 0.400000 | 0.400000 | 0.400000 | | | | | |

### Exposure errors on matched bounds only

| tool | arm | N | signature | layer | status |
|---|---|---|---|---|---|
| mean cosine | mean abs err | mean rel err | | | |
|---|---|---|---|---|---|
| sigprofiler | comp_mmr | 100 | SBS5 | flat | matched |
| 1.000000 | 11.000000 | 0.275000 | | | |
| sigprofiler | comp_mmr | 100 | SBS6 | mmr | matched |
| 1.000000 | 20.000000 | 2.000000 | | | |
| sigprofiler | comp_mmr | 1000 | SBS44 | mmr | matched |
| 1.000000 | 197.000000 | 6.566667 | | | |
| sigprofiler | comp_mmr | 1000 | SBS5 | flat | matched |
| 1.000000 | 315.000000 | 0.787500 | | | |
| sigprofiler | main | 100 | SBS5 | flat | matched |
| 1.000000 | 6.000000 | 0.200000 | | | |
| sigprofiler | main | 1000 | SBS5 | flat | matched |
| 1.000000 | 93.000000 | 0.310000 | | | |
| sigprofiler | nb | 1000 | SBS2 | easy | matched |
| 1.000000 | 44.000000 | 0.293333 | | | |
| sigprofiler | nb | 1000 | SBS5 | flat | matched |
| 1.000000 | 136.000000 | 0.453333 | | | |

Honest footer: the authoritative measurement class is the docker-adapter
run at the frozen protocol — degraded profile at 100 reps. smoke/mock
passes prove pipeline plumbing only and are never quoted as results.
Clock-arm exposure columns are report-only sensitivity rows (undiluted
tumour-basis truth is an open adjudication item, G0 P2g).
