# U-M7-02 fairness attestation — profile=degraded, adapter=docker, provider=synthetic

This is the **FAIRNESS ATTESTATION** half of the authoritative run: it
certifies *how* the cells ran, not *who won*.

- single ground truth: all competitors saw msuiter-generated simulated
  counts from the frozen G0 simulator (master seed 20260928, data streams bit-identical to G0)
- documented defaults only: zero threshold/parameter overrides (memo §3)
- frozen thread caps on every container cell: OMP_NUM_THREADS=1, OMP_THREAD_LIMIT=1, R_LIMIT_THREADS=1, GOMAXPROCS=1, MSUITER_THREADS=1, STAN_OMP_NUM_THREADS=1, OPENBLAS_NUM_THREADS=1
- one Docker VM for every cell (10 vCPU / 8 GB class), no host-side
  execution of container competitors (§4.1/§4.2)
- seeds: m7-tool-namespaced derivation, all on disk (Seeds.txt); commit ca0e55424127d513219d3d9fd1f6047b1476b8a8

| competitor | version | image ref | image digest | status |
|---|---|---|---|---|
| sigminer | 2.3.1 | msuiter-sigminer:slice3-r5 | sha256:05cb29e0cfe881c3a0c7d1ec7c9058cfbbb9539f5d1c135787027e6002c703e9 | ready |
| sigprofiler | v1.1.5 | m7-sigprofiler:spa-1.1.5 | sha256:7dba2f43ad3a3858ed1cfdedd278c9c2f52a665fd4c18ac91a482b74258bfbed | ready |

- cells: 42 total — cached: 42
- timings table: timings_m7_degraded_20261010-024833.csv (G0 six-column prefix + cpu_seconds; every measured second attributable)


## Re-adjudication lineage (RB-09(3)(iv))

- **sigminer__main__N100** — prior flag `defect-floor: wall/cpu 1004.9s > 3.0x pre-registered floor 310.0s (tool=sigminer arm=main n=100)` (floor epoch `pre-RB-09/rep-1-anchor-table@ddfaa2e`) now passes as `cached` under re-calibrated epoch `46bc002d7aea6b7f`;
  - mechanism: RB-09 (controller ruling 2026-10-09): the pre-registered floor table was calibrated from REP-1 witnesses (probe_sigminer_cell_argv --reps default; pilot Seeds.txt one rep row per class) while the protocol runs REP-100 cells — the defect-floor halt was an anchor-miscalibration artifact, the cell content itself intact. See the committed witness addendum and docs/devlog/2026-10-09-m7-benchmark-matrix.md.
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

### Adjudication table — primary (judge) arms

42 cells, 4200 samples, 2844 matched pairs pooled below.

| tool | version | arm | N | n_samples | tp | fp | fn |
|---|---|---|---|---|---|---|---|
| precision | recall | f1 | | | | | |
|---|---|---|---|---|---|---|---|
| sigminer | 2.3.1 | comp_clock_only | — | 300 | 0 | 700 | 600 |
| 0.000000 | 0.000000 | 0.000000 | | | | | |
| sigminer | 2.3.1 | comp_flat_triple | — | 300 | 0 | 1200 | 1500 |
| 0.000000 | 0.000000 | 0.000000 | | | | | |
| sigminer | 2.3.1 | comp_mmr | — | 300 | 0 | 900 | 2400 |
| 0.000000 | 0.000000 | 0.000000 | | | | | |
| sigminer | 2.3.1 | comp_pole | — | 300 | 0 | 700 | 2100 |
| 0.000000 | 0.000000 | 0.000000 | | | | | |
| sigminer | 2.3.1 | comp_strong_flat | — | 300 | 0 | 700 | 1200 |
| 0.000000 | 0.000000 | 0.000000 | | | | | |
| sigminer | 2.3.1 | main | — | 300 | 0 | 600 | 1500 |
| 0.000000 | 0.000000 | 0.000000 | | | | | |
| sigprofiler | v1.1.5 | comp_clock_only | — | 300 | 339 | 559 | 261 |
| 0.377506 | 0.565000 | 0.452603 | | | | | |
| sigprofiler | v1.1.5 | comp_flat_triple | — | 300 | 576 | 534 | 924 |
| 0.518919 | 0.384000 | 0.441379 | | | | | |
| sigprofiler | v1.1.5 | comp_mmr | — | 300 | 273 | 807 | 2127 |
| 0.252778 | 0.113750 | 0.156897 | | | | | |
| sigprofiler | v1.1.5 | comp_pole | — | 300 | 600 | 300 | 1500 |
| 0.666667 | 0.285714 | 0.400000 | | | | | |
| sigprofiler | v1.1.5 | comp_strong_flat | — | 300 | 108 | 837 | 1092 |
| 0.114286 | 0.090000 | 0.100699 | | | | | |
| sigprofiler | v1.1.5 | main | — | 300 | 527 | 775 | 973 |
| 0.404762 | 0.351333 | 0.376160 | | | | | |
| sigminer | 2.3.1 | None | 100 | 500 | 0 | 1200 | 2400 |
| 0.000000 | 0.000000 | 0.000000 | | | | | |
| sigminer | 2.3.1 | None | 1000 | 500 | 0 | 1300 | 2400 |
| 0.000000 | 0.000000 | 0.000000 | | | | | |
| sigminer | 2.3.1 | None | 10000 | 500 | 0 | 1600 | 2400 |
| 0.000000 | 0.000000 | 0.000000 | | | | | |
| sigminer | 2.3.1 | None | 100000 | 100 | 0 | 300 | 700 |
| 0.000000 | 0.000000 | 0.000000 | | | | | |
| sigminer | 2.3.1 | None | 300000 | 100 | 0 | 200 | 700 |
| 0.000000 | 0.000000 | 0.000000 | | | | | |
| sigminer | 2.3.1 | None | 1000000 | 100 | 0 | 200 | 700 |
| 0.000000 | 0.000000 | 0.000000 | | | | | |
| sigprofiler | v1.1.5 | None | 100 | 500 | 635 | 1033 | 1765 |
| 0.380695 | 0.264583 | 0.312193 | | | | | |
| sigprofiler | v1.1.5 | None | 1000 | 500 | 601 | 1204 | 1799 |
| 0.332964 | 0.250417 | 0.285850 | | | | | |
| sigprofiler | v1.1.5 | None | 10000 | 500 | 587 | 1275 | 1813 |
| 0.315252 | 0.244583 | 0.275458 | | | | | |
| sigprofiler | v1.1.5 | None | 100000 | 100 | 200 | 100 | 500 |
| 0.666667 | 0.285714 | 0.400000 | | | | | |
| sigprofiler | v1.1.5 | None | 300000 | 100 | 200 | 100 | 500 |
| 0.666667 | 0.285714 | 0.400000 | | | | | |
| sigprofiler | v1.1.5 | None | 1000000 | 100 | 200 | 100 | 500 |
| 0.666667 | 0.285714 | 0.400000 | | | | | |

### Sensitivity report columns (judge=False)

Report-only: the frozen grid flags these arms ``judge=False``;
they are reported, never mixed into adjudication (clause b).

| tool | version | arm | N | n_samples | tp | fp | fn |
|---|---|---|---|---|---|---|---|
| precision | recall | f1 | | | | | |
|---|---|---|---|---|---|---|---|
| sigminer | 2.3.1 | clock | — | 100 | 0 | 500 | 500 |
| 0.000000 | 0.000000 | 0.000000 | | | | | |
| sigminer | 2.3.1 | nb | — | 100 | 0 | 500 | 500 |
| 0.000000 | 0.000000 | 0.000000 | | | | | |
| sigminer | 2.3.1 | sparse | — | 100 | 0 | 300 | 500 |
| 0.000000 | 0.000000 | 0.000000 | | | | | |
| sigprofiler | v1.1.5 | clock | — | 100 | 113 | 220 | 387 |
| 0.339339 | 0.226000 | 0.271309 | | | | | |
| sigprofiler | v1.1.5 | nb | — | 100 | 152 | 246 | 348 |
| 0.381910 | 0.304000 | 0.338530 | | | | | |
| sigprofiler | v1.1.5 | sparse | — | 100 | 156 | 251 | 344 |
| 0.383292 | 0.312000 | 0.343991 | | | | | |
| sigminer | 2.3.1 | None | 1000 | 300 | 0 | 1300 | 1500 |
| 0.000000 | 0.000000 | 0.000000 | | | | | |
| sigprofiler | v1.1.5 | None | 1000 | 300 | 421 | 717 | 1079 |
| 0.369947 | 0.280667 | 0.319181 | | | | | |

### Exposure errors on matched bounds only

| tool | arm | N | signature | layer | status |
|---|---|---|---|---|---|
| mean cosine | mean abs err | mean rel err | | | |
|---|---|---|---|---|---|
| sigprofiler | clock | 1000 | SBS1 | easy | matched |
| 1.000000 | 144.076923 | 0.960513 | | | |
| sigprofiler | clock | 1000 | SBS5 | flat | matched |
| 1.000000 | 72.270000 | 0.240900 | | | |
| sigprofiler | comp_clock_only | 100 | SBS1 | easy | matched |
| 1.000000 | 26.857143 | 0.895238 | | | |
| sigprofiler | comp_clock_only | 100 | SBS5 | flat | matched |
| 1.000000 | 35.600000 | 0.508571 | | | |
| sigprofiler | comp_clock_only | 1000 | SBS1 | easy | matched |
| 1.000000 | 294.250000 | 0.980833 | | | |
| sigprofiler | comp_clock_only | 1000 | SBS5 | flat | matched |
| 1.000000 | 419.630000 | 0.599471 | | | |
| sigprofiler | comp_clock_only | 10000 | SBS1 | easy | matched |
| 1.000000 | 2951.000000 | 0.983667 | | | |
| sigprofiler | comp_clock_only | 10000 | SBS5 | flat | matched |
| 1.000000 | 4322.240000 | 0.617463 | | | |
| sigprofiler | comp_flat_triple | 100 | SBS1 | easy | matched |
| 1.000000 | 7.000000 | 0.875000 | | | |
| sigprofiler | comp_flat_triple | 100 | SBS13 | easy | matched |
| 1.000000 | 32.000000 | 0.842105 | | | |
| sigprofiler | comp_flat_triple | 100 | SBS2 | easy | matched |
| 1.000000 | 17.543210 | 0.461663 | | | |
| sigprofiler | comp_flat_triple | 100 | SBS5 | flat | matched |
| 1.000000 | 35.258427 | 4.407303 | | | |
| sigprofiler | comp_flat_triple | 1000 | SBS2 | easy | matched |
| 1.000000 | 200.160000 | 0.526737 | | | |
| sigprofiler | comp_flat_triple | 1000 | SBS5 | flat | matched |
| 1.000000 | 221.850000 | 2.773125 | | | |
| sigprofiler | comp_flat_triple | 10000 | SBS2 | easy | matched |
| 1.000000 | 2025.230000 | 0.532955 | | | |
| sigprofiler | comp_flat_triple | 10000 | SBS5 | flat | matched |
| 1.000000 | 1995.630000 | 2.494537 | | | |
| sigprofiler | comp_mmr | 100 | SBS1 | easy | matched |
| 1.000000 | 15.826087 | 0.791304 | | | |
| sigprofiler | comp_mmr | 100 | SBS15 | mmr | matched |
| 0.997432 | 18.400000 | 2.300000 | | | |
| sigprofiler | comp_mmr | 100 | SBS44 | mmr | matched |
| 1.000000 | 27.545455 | 9.181818 | | | |
| sigprofiler | comp_mmr | 100 | SBS5 | flat | matched |
| 1.000000 | 20.479452 | 0.511986 | | | |
| sigprofiler | comp_mmr | 100 | SBS6 | mmr | matched |
| 1.000000 | 20.750000 | 2.075000 | | | |
| sigprofiler | comp_mmr | 1000 | SBS1 | easy | matched |
| 1.000000 | 194.750000 | 0.973750 | | | |
| sigprofiler | comp_mmr | 1000 | SBS44 | mmr | matched |
| 1.000000 | 215.666667 | 7.188889 | | | |
| sigprofiler | comp_mmr | 1000 | SBS5 | flat | matched |
| 1.000000 | 334.266667 | 0.835667 | | | |
| sigprofiler | comp_mmr | 10000 | SBS5 | flat | matched |
| 1.000000 | 3801.695652 | 0.950424 | | | |
| sigprofiler | comp_pole | 100000 | SBS1 | easy | matched |
| 1.000000 | 8836.770000 | 0.883677 | | | |
| sigprofiler | comp_pole | 100000 | SBS5 | flat | matched |
| 1.000000 | 22635.010000 | 0.646715 | | | |
| sigprofiler | comp_pole | 300000 | SBS1 | easy | matched |
| 1.000000 | 26471.350000 | 0.882378 | | | |
| sigprofiler | comp_pole | 300000 | SBS5 | flat | matched |
| 1.000000 | 68116.110000 | 0.648725 | | | |
| sigprofiler | comp_pole | 1000000 | SBS1 | easy | matched |
| 1.000000 | 88294.360000 | 0.882944 | | | |
| sigprofiler | comp_pole | 1000000 | SBS5 | flat | matched |
| 1.000000 | 226988.930000 | 0.648540 | | | |
| sigprofiler | comp_strong_flat | 100 | SBS5 | flat | matched |
| 1.000000 | 8.460000 | 0.564000 | | | |
| sigprofiler | comp_strong_flat | 1000 | SBS5 | flat | matched |
| 1.000000 | 40.360000 | 0.269067 | | | |
| sigprofiler | comp_strong_flat | 10000 | SBS5 | flat | matched |
| 1.000000 | 69.000000 | 0.046000 | | | |
| sigprofiler | main | 100 | SBS1 | easy | matched |
| 1.000000 | 12.904762 | 0.860317 | | | |
| sigprofiler | main | 100 | SBS13 | easy | matched |
| 1.000000 | 9.250000 | 0.616667 | | | |
| sigprofiler | main | 100 | SBS2 | easy | matched |
| 1.000000 | 3.200000 | 0.213333 | | | |
| sigprofiler | main | 100 | SBS5 | flat | matched |
| 1.000000 | 14.187500 | 0.472917 | | | |
| sigprofiler | main | 1000 | SBS1 | easy | matched |
| 1.000000 | 143.600000 | 0.957333 | | | |
| sigprofiler | main | 1000 | SBS2 | easy | matched |
| 1.000000 | 69.107143 | 0.460714 | | | |
| sigprofiler | main | 1000 | SBS5 | flat | matched |
| 1.000000 | 83.510417 | 0.278368 | | | |
| sigprofiler | main | 10000 | SBS1 | easy | matched |
| 1.000000 | 1480.500000 | 0.987000 | | | |
| sigprofiler | main | 10000 | SBS2 | easy | matched |
| 1.000000 | 714.989474 | 0.476660 | | | |
| sigprofiler | main | 10000 | SBS5 | flat | matched |
| 1.000000 | 948.478723 | 0.316160 | | | |
| sigprofiler | nb | 1000 | SBS1 | easy | matched |
| 1.000000 | 145.250000 | 0.968333 | | | |
| sigprofiler | nb | 1000 | SBS2 | easy | matched |
| 1.000000 | 42.487805 | 0.283252 | | | |
| sigprofiler | nb | 1000 | SBS5 | flat | matched |
| 1.000000 | 95.368421 | 0.317895 | | | |
| sigprofiler | sparse | 1000 | SBS1 | easy | matched |
| 1.000000 | 165.256966 | 0.955567 | | | |
| sigprofiler | sparse | 1000 | SBS2 | easy | matched |
| 1.000000 | 74.896732 | 0.433076 | | | |
| sigprofiler | sparse | 1000 | SBS5 | flat | matched |
| 1.000000 | 91.707801 | 0.265142 | | | |

Honest footer: the authoritative measurement class is the docker-adapter
run at the frozen protocol — degraded profile at 100 reps. smoke/mock
passes prove pipeline plumbing only and are never quoted as results.
Clock-arm exposure columns are report-only sensitivity rows (undiluted
tumour-basis truth is an open adjudication item, G0 P2g).
