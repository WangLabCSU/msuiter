# U-M7-02 fairness attestation — profile=degraded, adapter=docker, provider=synthetic

This is the **FAIRNESS ATTESTATION** half of the authoritative run: it
certifies *how* the cells ran, not *who won*.

- single ground truth: all competitors saw msuiter-generated simulated
  counts from the frozen G0 simulator (master seed 20260928, data streams bit-identical to G0)
- documented defaults only: zero threshold/parameter overrides (memo §3)
- frozen caps on every container cell: OMP_NUM_THREADS=1, OMP_THREAD_LIMIT=1, R_LIMIT_THREADS=1, GOMAXPROCS=1, MSUITER_THREADS=1, STAN_OMP_NUM_THREADS=1, OPENBLAS_NUM_THREADS=1, R_PARALLELLY_AVAILABLECORES_METHODS=system, R_PARALLELLY_AVAILABLECORES_SYSTEM=1
- one Docker VM for every cell (10 vCPU / 8 GB class), no host-side
  execution of container competitors (§4.1/§4.2)
- seeds: m7-tool-namespaced derivation, all on disk (Seeds.txt); commit 7bc3bd0d460d25bb0d499f2593b060fccccf7a54

| competitor | version | image ref | image digest | status |
|---|---|---|---|---|
| sigminer | 2.3.1 | msuiter-sigminer:slice3-r5 | sha256:37a5e7d9c61353dd1f40d945fe5ac426214335d01eca972dea71a99823bbdd98 | ready |
| sigprofiler | v1.1.5 | m7-sigprofiler:spa-1.1.5 | sha256:f1b3140eebaa90116e6050ebfc674c74eda4f8a8546d4cca67038e072899167c | ready |
| sigminer_pre_v3 | 2.3.3 | msuiter-sigminer:p6-sigminer_pre_v3-r1 | sha256:d48cb7fa658f91adda79aad9c7cb0c0dfe0e21eea675aae1ff35a4a97740ebe2 | ready |
| sigminer_post_p1 | 2.3.3 | msuiter-sigminer:p6-sigminer_post_p1-r1 | sha256:afe80a1f34ce4423a99ced84c4a67e9f85ca01261fb8dd84d998350d04aefa4f | ready |
| sigminer_post_p1_rust | 2.3.3 | msuiter-sigminer:p6-sigminer_post_p1_rust-r2 | sha256:bc1fb04da8243297de5099353a918064da21c5602b7df55dacea1be7d267394e | ready |
| sigminer_post_p2 | 2.3.3 | msuiter-sigminer:p6-sigminer_post_p2-r1 | sha256:65ebb01644048991433e052f0b98d25211426bb046db4590f69b3e3cf0e521c2 | ready |
| sigminer_post_v3 | 2.3.3 | msuiter-sigminer:p6-sigminer_post_v3-r1 | sha256:44707680ae2bde77df9d4d8ef8f2633e42eecce870f21942606d6d1b49f00e75 | ready |
| sigminer_post_v3_rust | 2.3.3 | msuiter-sigminer:p6-sigminer_post_v3_rust-r2 | sha256:de5e07eb4772b7e2458dc5a6d238dc919610d63fe1b3a253e98851747c05e937 | ready |

- cells: 168 total — cached: 168
- timings table: timings_m7_degraded_20261114-112641.csv (G0 six-column prefix + cpu_seconds + hardware pins host/hw_profile; every measured second attributable, every row attests its machine)

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

168 cells, 16800 samples, 13581 matched pairs pooled below.

| tool | version | arm | N | n_samples | tp | fp | fn | precision | recall | f1 |
|---|---|---|---|---|---|---|---|---|---|---|
| sigminer | 2.3.1 | comp_clock_only | — | 300 | 300 | 400 | 300 | 0.428571 | 0.500000 | 0.461538 |
| sigminer | 2.3.1 | comp_flat_triple | — | 300 | 0 | 1200 | 1500 | 0.000000 | 0.000000 | 0.000000 |
| sigminer | 2.3.1 | comp_mmr | — | 300 | 0 | 900 | 2400 | 0.000000 | 0.000000 | 0.000000 |
| sigminer | 2.3.1 | comp_pole | — | 300 | 700 | 0 | 1400 | 1.000000 | 0.333333 | 0.500000 |
| sigminer | 2.3.1 | comp_strong_flat | — | 300 | 0 | 700 | 1200 | 0.000000 | 0.000000 | 0.000000 |
| sigminer | 2.3.1 | main | — | 300 | 0 | 600 | 1500 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_post_p1 | 2.3.3 | comp_clock_only | — | 300 | 300 | 600 | 300 | 0.333333 | 0.500000 | 0.400000 |
| sigminer_post_p1 | 2.3.3 | comp_flat_triple | — | 300 | 0 | 1300 | 1500 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_post_p1 | 2.3.3 | comp_mmr | — | 300 | 0 | 700 | 2400 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_post_p1 | 2.3.3 | comp_pole | — | 300 | 1000 | 0 | 1100 | 1.000000 | 0.476190 | 0.645161 |
| sigminer_post_p1 | 2.3.3 | comp_strong_flat | — | 300 | 0 | 900 | 1200 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_post_p1 | 2.3.3 | main | — | 300 | 0 | 800 | 1500 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_post_p1_rust | 2.3.3 | comp_clock_only | — | 300 | 300 | 300 | 300 | 0.500000 | 0.500000 | 0.500000 |
| sigminer_post_p1_rust | 2.3.3 | comp_flat_triple | — | 300 | 280 | 300 | 1220 | 0.482759 | 0.186667 | 0.269231 |
| sigminer_post_p1_rust | 2.3.3 | comp_mmr | — | 300 | 300 | 497 | 2100 | 0.376412 | 0.125000 | 0.187676 |
| sigminer_post_p1_rust | 2.3.3 | comp_pole | — | 300 | 700 | 0 | 1400 | 1.000000 | 0.333333 | 0.500000 |
| sigminer_post_p1_rust | 2.3.3 | comp_strong_flat | — | 300 | 100 | 786 | 1100 | 0.112867 | 0.083333 | 0.095877 |
| sigminer_post_p1_rust | 2.3.3 | main | — | 300 | 199 | 500 | 1301 | 0.284692 | 0.132667 | 0.180991 |
| sigminer_post_p2 | 2.3.3 | comp_clock_only | — | 300 | 300 | 600 | 300 | 0.333333 | 0.500000 | 0.400000 |
| sigminer_post_p2 | 2.3.3 | comp_flat_triple | — | 300 | 0 | 1200 | 1500 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_post_p2 | 2.3.3 | comp_mmr | — | 300 | 0 | 800 | 2400 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_post_p2 | 2.3.3 | comp_pole | — | 300 | 900 | 0 | 1200 | 1.000000 | 0.428571 | 0.600000 |
| sigminer_post_p2 | 2.3.3 | comp_strong_flat | — | 300 | 0 | 800 | 1200 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_post_p2 | 2.3.3 | main | — | 300 | 0 | 800 | 1500 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_post_v3 | 2.3.3 | comp_clock_only | — | 300 | 300 | 500 | 300 | 0.375000 | 0.500000 | 0.428571 |
| sigminer_post_v3 | 2.3.3 | comp_flat_triple | — | 300 | 0 | 1200 | 1500 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_post_v3 | 2.3.3 | comp_mmr | — | 300 | 0 | 600 | 2400 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_post_v3 | 2.3.3 | comp_pole | — | 300 | 600 | 0 | 1500 | 1.000000 | 0.285714 | 0.444444 |
| sigminer_post_v3 | 2.3.3 | comp_strong_flat | — | 300 | 0 | 1100 | 1200 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_post_v3 | 2.3.3 | main | — | 300 | 0 | 700 | 1500 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_post_v3_rust | 2.3.3 | comp_clock_only | — | 300 | 300 | 300 | 300 | 0.500000 | 0.500000 | 0.500000 |
| sigminer_post_v3_rust | 2.3.3 | comp_flat_triple | — | 300 | 275 | 500 | 1225 | 0.354839 | 0.183333 | 0.241758 |
| sigminer_post_v3_rust | 2.3.3 | comp_mmr | — | 300 | 300 | 300 | 2100 | 0.500000 | 0.125000 | 0.200000 |
| sigminer_post_v3_rust | 2.3.3 | comp_pole | — | 300 | 800 | 97 | 1300 | 0.891862 | 0.380952 | 0.533867 |
| sigminer_post_v3_rust | 2.3.3 | comp_strong_flat | — | 300 | 100 | 785 | 1100 | 0.112994 | 0.083333 | 0.095923 |
| sigminer_post_v3_rust | 2.3.3 | main | — | 300 | 200 | 600 | 1300 | 0.250000 | 0.133333 | 0.173913 |
| sigminer_pre_v3 | 2.3.3 | comp_clock_only | — | 300 | 300 | 300 | 300 | 0.500000 | 0.500000 | 0.500000 |
| sigminer_pre_v3 | 2.3.3 | comp_flat_triple | — | 300 | 0 | 1300 | 1500 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_pre_v3 | 2.3.3 | comp_mmr | — | 300 | 0 | 1100 | 2400 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_pre_v3 | 2.3.3 | comp_pole | — | 300 | 600 | 0 | 1500 | 1.000000 | 0.285714 | 0.444444 |
| sigminer_pre_v3 | 2.3.3 | comp_strong_flat | — | 300 | 0 | 800 | 1200 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_pre_v3 | 2.3.3 | main | — | 300 | 0 | 800 | 1500 | 0.000000 | 0.000000 | 0.000000 |
| sigprofiler | v1.1.5 | comp_clock_only | — | 300 | 339 | 559 | 261 | 0.377506 | 0.565000 | 0.452603 |
| sigprofiler | v1.1.5 | comp_flat_triple | — | 300 | 576 | 534 | 924 | 0.518919 | 0.384000 | 0.441379 |
| sigprofiler | v1.1.5 | comp_mmr | — | 300 | 273 | 807 | 2127 | 0.252778 | 0.113750 | 0.156897 |
| sigprofiler | v1.1.5 | comp_pole | — | 300 | 600 | 300 | 1500 | 0.666667 | 0.285714 | 0.400000 |
| sigprofiler | v1.1.5 | comp_strong_flat | — | 300 | 108 | 837 | 1092 | 0.114286 | 0.090000 | 0.100699 |
| sigprofiler | v1.1.5 | main | — | 300 | 527 | 775 | 973 | 0.404762 | 0.351333 | 0.376160 |
| sigminer | 2.3.1 | — | 100 | 500 | 100 | 1100 | 2300 | 0.083333 | 0.041667 | 0.055556 |
| sigminer | 2.3.1 | — | 1000 | 500 | 100 | 1200 | 2300 | 0.076923 | 0.041667 | 0.054054 |
| sigminer | 2.3.1 | — | 10000 | 500 | 100 | 1500 | 2300 | 0.062500 | 0.041667 | 0.050000 |
| sigminer | 2.3.1 | — | 100000 | 100 | 300 | 0 | 400 | 1.000000 | 0.428571 | 0.600000 |
| sigminer | 2.3.1 | — | 300000 | 100 | 200 | 0 | 500 | 1.000000 | 0.285714 | 0.444444 |
| sigminer | 2.3.1 | — | 1000000 | 100 | 200 | 0 | 500 | 1.000000 | 0.285714 | 0.444444 |
| sigminer_post_p1 | 2.3.3 | — | 100 | 500 | 100 | 1300 | 2300 | 0.071429 | 0.041667 | 0.052632 |
| sigminer_post_p1 | 2.3.3 | — | 1000 | 500 | 100 | 1600 | 2300 | 0.058824 | 0.041667 | 0.048780 |
| sigminer_post_p1 | 2.3.3 | — | 10000 | 500 | 100 | 1400 | 2300 | 0.066667 | 0.041667 | 0.051282 |
| sigminer_post_p1 | 2.3.3 | — | 100000 | 100 | 300 | 0 | 400 | 1.000000 | 0.428571 | 0.600000 |
| sigminer_post_p1 | 2.3.3 | — | 300000 | 100 | 500 | 0 | 200 | 1.000000 | 0.714286 | 0.833333 |
| sigminer_post_p1 | 2.3.3 | — | 1000000 | 100 | 200 | 0 | 500 | 1.000000 | 0.285714 | 0.444444 |
| sigminer_post_p1_rust | 2.3.3 | — | 100 | 500 | 591 | 592 | 1809 | 0.499577 | 0.246250 | 0.329891 |
| sigminer_post_p1_rust | 2.3.3 | — | 1000 | 500 | 293 | 796 | 2107 | 0.269054 | 0.122083 | 0.167956 |
| sigminer_post_p1_rust | 2.3.3 | — | 10000 | 500 | 295 | 995 | 2105 | 0.228682 | 0.122917 | 0.159892 |
| sigminer_post_p1_rust | 2.3.3 | — | 100000 | 100 | 200 | 0 | 500 | 1.000000 | 0.285714 | 0.444444 |
| sigminer_post_p1_rust | 2.3.3 | — | 300000 | 100 | 300 | 0 | 400 | 1.000000 | 0.428571 | 0.600000 |
| sigminer_post_p1_rust | 2.3.3 | — | 1000000 | 100 | 200 | 0 | 500 | 1.000000 | 0.285714 | 0.444444 |
| sigminer_post_p2 | 2.3.3 | — | 100 | 500 | 100 | 1100 | 2300 | 0.083333 | 0.041667 | 0.055556 |
| sigminer_post_p2 | 2.3.3 | — | 1000 | 500 | 100 | 1600 | 2300 | 0.058824 | 0.041667 | 0.048780 |
| sigminer_post_p2 | 2.3.3 | — | 10000 | 500 | 100 | 1500 | 2300 | 0.062500 | 0.041667 | 0.050000 |
| sigminer_post_p2 | 2.3.3 | — | 100000 | 100 | 400 | 0 | 300 | 1.000000 | 0.571429 | 0.727273 |
| sigminer_post_p2 | 2.3.3 | — | 300000 | 100 | 300 | 0 | 400 | 1.000000 | 0.428571 | 0.600000 |
| sigminer_post_p2 | 2.3.3 | — | 1000000 | 100 | 200 | 0 | 500 | 1.000000 | 0.285714 | 0.444444 |
| sigminer_post_v3 | 2.3.3 | — | 100 | 500 | 100 | 1300 | 2300 | 0.071429 | 0.041667 | 0.052632 |
| sigminer_post_v3 | 2.3.3 | — | 1000 | 500 | 100 | 1500 | 2300 | 0.062500 | 0.041667 | 0.050000 |
| sigminer_post_v3 | 2.3.3 | — | 10000 | 500 | 100 | 1300 | 2300 | 0.071429 | 0.041667 | 0.052632 |
| sigminer_post_v3 | 2.3.3 | — | 100000 | 100 | 200 | 0 | 500 | 1.000000 | 0.285714 | 0.444444 |
| sigminer_post_v3 | 2.3.3 | — | 300000 | 100 | 200 | 0 | 500 | 1.000000 | 0.285714 | 0.444444 |
| sigminer_post_v3 | 2.3.3 | — | 1000000 | 100 | 200 | 0 | 500 | 1.000000 | 0.285714 | 0.444444 |
| sigminer_post_v3_rust | 2.3.3 | — | 100 | 500 | 588 | 493 | 1812 | 0.543941 | 0.245000 | 0.337834 |
| sigminer_post_v3_rust | 2.3.3 | — | 1000 | 500 | 290 | 995 | 2110 | 0.225681 | 0.120833 | 0.157395 |
| sigminer_post_v3_rust | 2.3.3 | — | 10000 | 500 | 297 | 997 | 2103 | 0.229521 | 0.123750 | 0.160801 |
| sigminer_post_v3_rust | 2.3.3 | — | 100000 | 100 | 200 | 97 | 500 | 0.673401 | 0.285714 | 0.401204 |
| sigminer_post_v3_rust | 2.3.3 | — | 300000 | 100 | 300 | 0 | 400 | 1.000000 | 0.428571 | 0.600000 |
| sigminer_post_v3_rust | 2.3.3 | — | 1000000 | 100 | 300 | 0 | 400 | 1.000000 | 0.428571 | 0.600000 |
| sigminer_pre_v3 | 2.3.3 | — | 100 | 500 | 100 | 1100 | 2300 | 0.083333 | 0.041667 | 0.055556 |
| sigminer_pre_v3 | 2.3.3 | — | 1000 | 500 | 100 | 1600 | 2300 | 0.058824 | 0.041667 | 0.048780 |
| sigminer_pre_v3 | 2.3.3 | — | 10000 | 500 | 100 | 1600 | 2300 | 0.058824 | 0.041667 | 0.048780 |
| sigminer_pre_v3 | 2.3.3 | — | 100000 | 100 | 200 | 0 | 500 | 1.000000 | 0.285714 | 0.444444 |
| sigminer_pre_v3 | 2.3.3 | — | 300000 | 100 | 200 | 0 | 500 | 1.000000 | 0.285714 | 0.444444 |
| sigminer_pre_v3 | 2.3.3 | — | 1000000 | 100 | 200 | 0 | 500 | 1.000000 | 0.285714 | 0.444444 |
| sigprofiler | v1.1.5 | — | 100 | 500 | 635 | 1033 | 1765 | 0.380695 | 0.264583 | 0.312193 |
| sigprofiler | v1.1.5 | — | 1000 | 500 | 601 | 1204 | 1799 | 0.332964 | 0.250417 | 0.285850 |
| sigprofiler | v1.1.5 | — | 10000 | 500 | 587 | 1275 | 1813 | 0.315252 | 0.244583 | 0.275458 |
| sigprofiler | v1.1.5 | — | 100000 | 100 | 200 | 100 | 500 | 0.666667 | 0.285714 | 0.400000 |
| sigprofiler | v1.1.5 | — | 300000 | 100 | 200 | 100 | 500 | 0.666667 | 0.285714 | 0.400000 |
| sigprofiler | v1.1.5 | — | 1000000 | 100 | 200 | 100 | 500 | 0.666667 | 0.285714 | 0.400000 |

### Sensitivity report columns (judge=False)

Report-only: the frozen grid flags these arms ``judge=False``;
they are reported, never mixed into adjudication (clause b).

| tool | version | arm | N | n_samples | tp | fp | fn | precision | recall | f1 |
|---|---|---|---|---|---|---|---|---|---|---|
| sigminer | 2.3.1 | clock | — | 100 | 0 | 500 | 500 | 0.000000 | 0.000000 | 0.000000 |
| sigminer | 2.3.1 | nb | — | 100 | 300 | 200 | 200 | 0.600000 | 0.600000 | 0.600000 |
| sigminer | 2.3.1 | sparse | — | 100 | 0 | 300 | 500 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_post_p1 | 2.3.3 | clock | — | 100 | 0 | 300 | 500 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_post_p1 | 2.3.3 | nb | — | 100 | 200 | 300 | 300 | 0.400000 | 0.400000 | 0.400000 |
| sigminer_post_p1 | 2.3.3 | sparse | — | 100 | 0 | 400 | 500 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_post_p1_rust | 2.3.3 | clock | — | 100 | 100 | 100 | 400 | 0.500000 | 0.200000 | 0.285714 |
| sigminer_post_p1_rust | 2.3.3 | nb | — | 100 | 100 | 268 | 400 | 0.271739 | 0.200000 | 0.230415 |
| sigminer_post_p1_rust | 2.3.3 | sparse | — | 100 | 0 | 200 | 500 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_post_p2 | 2.3.3 | clock | — | 100 | 0 | 200 | 500 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_post_p2 | 2.3.3 | nb | — | 100 | 300 | 200 | 200 | 0.600000 | 0.600000 | 0.600000 |
| sigminer_post_p2 | 2.3.3 | sparse | — | 100 | 0 | 200 | 500 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_post_v3 | 2.3.3 | clock | — | 100 | 0 | 200 | 500 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_post_v3 | 2.3.3 | nb | — | 100 | 200 | 300 | 300 | 0.400000 | 0.400000 | 0.400000 |
| sigminer_post_v3 | 2.3.3 | sparse | — | 100 | 0 | 300 | 500 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_post_v3_rust | 2.3.3 | clock | — | 100 | 96 | 100 | 404 | 0.489796 | 0.192000 | 0.275862 |
| sigminer_post_v3_rust | 2.3.3 | nb | — | 100 | 87 | 288 | 413 | 0.232000 | 0.174000 | 0.198857 |
| sigminer_post_v3_rust | 2.3.3 | sparse | — | 100 | 0 | 300 | 500 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_pre_v3 | 2.3.3 | clock | — | 100 | 0 | 200 | 500 | 0.000000 | 0.000000 | 0.000000 |
| sigminer_pre_v3 | 2.3.3 | nb | — | 100 | 200 | 200 | 300 | 0.500000 | 0.400000 | 0.444444 |
| sigminer_pre_v3 | 2.3.3 | sparse | — | 100 | 0 | 200 | 500 | 0.000000 | 0.000000 | 0.000000 |
| sigprofiler | v1.1.5 | clock | — | 100 | 113 | 220 | 387 | 0.339339 | 0.226000 | 0.271309 |
| sigprofiler | v1.1.5 | nb | — | 100 | 152 | 246 | 348 | 0.381910 | 0.304000 | 0.338530 |
| sigprofiler | v1.1.5 | sparse | — | 100 | 156 | 251 | 344 | 0.383292 | 0.312000 | 0.343991 |
| sigminer | 2.3.1 | — | 1000 | 300 | 300 | 1000 | 1200 | 0.230769 | 0.200000 | 0.214286 |
| sigminer_post_p1 | 2.3.3 | — | 1000 | 300 | 200 | 1000 | 1300 | 0.166667 | 0.133333 | 0.148148 |
| sigminer_post_p1_rust | 2.3.3 | — | 1000 | 300 | 200 | 568 | 1300 | 0.260417 | 0.133333 | 0.176367 |
| sigminer_post_p2 | 2.3.3 | — | 1000 | 300 | 300 | 600 | 1200 | 0.333333 | 0.200000 | 0.250000 |
| sigminer_post_v3 | 2.3.3 | — | 1000 | 300 | 200 | 800 | 1300 | 0.200000 | 0.133333 | 0.160000 |
| sigminer_post_v3_rust | 2.3.3 | — | 1000 | 300 | 183 | 688 | 1317 | 0.210103 | 0.122000 | 0.154365 |
| sigminer_pre_v3 | 2.3.3 | — | 1000 | 300 | 200 | 600 | 1300 | 0.250000 | 0.133333 | 0.173913 |
| sigprofiler | v1.1.5 | — | 1000 | 300 | 421 | 717 | 1079 | 0.369947 | 0.280667 | 0.319181 |

### Exposure errors on matched bounds only

| tool | arm | N | signature | layer | status | mean cosine | mean abs err | mean rel err |
|---|---|---|---|---|---|---|---|---|
| sigminer | comp_clock_only | 100 | SBS1 | easy | matched | 0.877688 | 7.922160 | 0.264072 |
| sigminer | comp_clock_only | 100 | Sig1 | — | matched | na | na | na |
| sigminer | comp_clock_only | 1000 | SBS1 | easy | matched | 0.876247 | 204.180249 | 0.680601 |
| sigminer | comp_clock_only | 1000 | Sig1 | — | matched | na | na | na |
| sigminer | comp_clock_only | 10000 | SBS1 | easy | matched | 0.877362 | 2086.658716 | 0.695553 |
| sigminer | comp_clock_only | 10000 | Sig1 | — | matched | na | na | na |
| sigminer | comp_pole | 100000 | SBS10a | pole | matched | 0.928709 | 2492.148015 | 0.083072 |
| sigminer | comp_pole | 100000 | SBS10b | pole | matched | 0.921276 | 29439.423704 | 2.943942 |
| sigminer | comp_pole | 100000 | SBS28 | pole | matched | 0.925915 | 23726.517202 | 4.745303 |
| sigminer | comp_pole | 100000 | Sig1 | — | matched | na | na | na |
| sigminer | comp_pole | 100000 | Sig2 | — | matched | na | na | na |
| sigminer | comp_pole | 100000 | Sig3 | — | matched | na | na | na |
| sigminer | comp_pole | 300000 | SBS10a | pole | matched | 0.925646 | 59001.604884 | 0.655573 |
| sigminer | comp_pole | 300000 | SBS28 | pole | matched | 0.927694 | 135998.395120 | 9.066560 |
| sigminer | comp_pole | 300000 | Sig1 | — | matched | na | na | na |
| sigminer | comp_pole | 300000 | Sig2 | — | matched | na | na | na |
| sigminer | comp_pole | 1000000 | SBS10a | pole | matched | 0.926889 | 244856.574251 | 0.816189 |
| sigminer | comp_pole | 1000000 | SBS28 | pole | matched | 0.926399 | 405143.425747 | 8.102869 |
| sigminer | comp_pole | 1000000 | Sig1 | — | matched | na | na | na |
| sigminer | comp_pole | 1000000 | Sig2 | — | matched | na | na | na |
| sigminer | nb | 1000 | SBS1 | easy | matched | 0.915626 | 96.770335 | 0.645136 |
| sigminer | nb | 1000 | SBS2 | easy | matched | 0.850819 | 82.473390 | 0.549823 |
| sigminer | nb | 1000 | SBS5 | flat | matched | 0.877507 | 112.642759 | 0.375476 |
| sigminer | nb | 1000 | Sig1 | — | matched | na | na | na |
| sigminer | nb | 1000 | Sig3 | — | matched | na | na | na |
| sigminer | nb | 1000 | Sig5 | — | matched | na | na | na |
| sigminer_post_p1 | comp_clock_only | 100 | SBS1 | easy | matched | 0.885521 | 20.506567 | 0.683552 |
| sigminer_post_p1 | comp_clock_only | 100 | Sig1 | — | matched | na | na | na |
| sigminer_post_p1 | comp_clock_only | 1000 | SBS1 | easy | matched | 0.893245 | 100.772862 | 0.335910 |
| sigminer_post_p1 | comp_clock_only | 1000 | Sig2 | — | matched | na | na | na |
| sigminer_post_p1 | comp_clock_only | 10000 | SBS1 | easy | matched | 0.878583 | 1999.952652 | 0.666651 |
| sigminer_post_p1 | comp_clock_only | 10000 | Sig2 | — | matched | na | na | na |
| sigminer_post_p1 | comp_pole | 100000 | SBS10a | pole | matched | 0.928631 | 8442.372807 | 0.281412 |
| sigminer_post_p1 | comp_pole | 100000 | SBS10d | pole | matched | 0.930651 | 28229.733899 | 5.645947 |
| sigminer_post_p1 | comp_pole | 100000 | SBS28 | pole | matched | 0.905575 | 23327.893300 | 4.665579 |
| sigminer_post_p1 | comp_pole | 100000 | Sig1 | — | matched | na | na | na |
| sigminer_post_p1 | comp_pole | 100000 | Sig2 | — | matched | na | na | na |
| sigminer_post_p1 | comp_pole | 100000 | Sig3 | — | matched | na | na | na |
| sigminer_post_p1 | comp_pole | 300000 | SBS10a | pole | matched | 0.934688 | 22869.184326 | 0.254102 |
| sigminer_post_p1 | comp_pole | 300000 | SBS10b | pole | matched | 0.919354 | 15664.581656 | 0.522153 |
| sigminer_post_p1 | comp_pole | 300000 | SBS10c | pole | matched | 0.876242 | 26567.702831 | 1.771180 |
| sigminer_post_p1 | comp_pole | 300000 | SBS10d | pole | matched | 0.928093 | 59196.347495 | 3.946423 |
| sigminer_post_p1 | comp_pole | 300000 | SBS28 | pole | matched | 0.924432 | 54312.341225 | 3.620823 |
| sigminer_post_p1 | comp_pole | 300000 | Sig1 | — | matched | na | na | na |
| sigminer_post_p1 | comp_pole | 300000 | Sig2 | — | matched | na | na | na |
| sigminer_post_p1 | comp_pole | 300000 | Sig3 | — | matched | na | na | na |
| sigminer_post_p1 | comp_pole | 300000 | Sig4 | — | matched | na | na | na |
| sigminer_post_p1 | comp_pole | 300000 | Sig5 | — | matched | na | na | na |
| sigminer_post_p1 | comp_pole | 1000000 | SBS10a | pole | matched | 0.927760 | 196974.523990 | 0.656582 |
| sigminer_post_p1 | comp_pole | 1000000 | SBS28 | pole | matched | 0.925601 | 453025.476003 | 9.060510 |
| sigminer_post_p1 | comp_pole | 1000000 | Sig1 | — | matched | na | na | na |
| sigminer_post_p1 | comp_pole | 1000000 | Sig2 | — | matched | na | na | na |
| sigminer_post_p1 | nb | 1000 | SBS1 | easy | matched | 0.916482 | 94.905087 | 0.632701 |
| sigminer_post_p1 | nb | 1000 | SBS5 | flat | matched | 0.872625 | 112.811246 | 0.376037 |
| sigminer_post_p1 | nb | 1000 | Sig1 | — | matched | na | na | na |
| sigminer_post_p1 | nb | 1000 | Sig4 | — | matched | na | na | na |
| sigminer_post_p1_rust | clock | 1000 | SBS1 | easy | matched | 0.940178 | 82.656427 | 0.551043 |
| sigminer_post_p1_rust | clock | 1000 | Sig2 | — | matched | na | na | na |
| sigminer_post_p1_rust | comp_clock_only | 100 | SBS1 | easy | matched | 0.917481 | 32.012374 | 1.067079 |
| sigminer_post_p1_rust | comp_clock_only | 100 | Sig1 | — | matched | na | na | na |
| sigminer_post_p1_rust | comp_clock_only | 1000 | SBS1 | easy | matched | 0.912510 | 16.829521 | 0.056098 |
| sigminer_post_p1_rust | comp_clock_only | 1000 | Sig2 | — | matched | na | na | na |
| sigminer_post_p1_rust | comp_clock_only | 10000 | SBS1 | easy | matched | 0.890943 | 54.714364 | 0.018238 |
| sigminer_post_p1_rust | comp_clock_only | 10000 | Sig2 | — | matched | na | na | na |
| sigminer_post_p1_rust | comp_flat_triple | 100 | SBS2 | easy | matched | 0.897055 | 31.307491 | 0.823881 |
| sigminer_post_p1_rust | comp_flat_triple | 100 | Sig2 | — | matched | na | na | na |
| sigminer_post_p1_rust | comp_flat_triple | 1000 | SBS2 | easy | matched | 0.887999 | 357.223286 | 0.940061 |
| sigminer_post_p1_rust | comp_flat_triple | 1000 | Sig2 | — | matched | na | na | na |
| sigminer_post_p1_rust | comp_flat_triple | 10000 | SBS2 | easy | matched | 0.894910 | 3723.755296 | 0.979936 |
| sigminer_post_p1_rust | comp_flat_triple | 10000 | Sig2 | — | matched | na | na | na |
| sigminer_post_p1_rust | comp_mmr | 100 | SBS1 | easy | matched | 0.866263 | 32.112423 | 1.605621 |
| sigminer_post_p1_rust | comp_mmr | 100 | SBS20 | mmr | matched | 0.916265 | 25.678910 | 3.668416 |
| sigminer_post_p1_rust | comp_mmr | 100 | Sig1 | — | matched | na | na | na |
| sigminer_post_p1_rust | comp_mmr | 100 | Sig2 | — | matched | na | na | na |
| sigminer_post_p1_rust | comp_mmr | 1000 | SBS20 | mmr | matched | 0.888548 | 107.888964 | 1.541271 |
| sigminer_post_p1_rust | comp_mmr | 1000 | Sig2 | — | matched | na | na | na |
| sigminer_post_p1_rust | comp_pole | 100000 | SBS10a | pole | matched | 0.927019 | 19844.600077 | 0.661487 |
| sigminer_post_p1_rust | comp_pole | 100000 | SBS28 | pole | matched | 0.925577 | 45155.399919 | 9.031080 |
| sigminer_post_p1_rust | comp_pole | 100000 | Sig1 | — | matched | na | na | na |
| sigminer_post_p1_rust | comp_pole | 100000 | Sig2 | — | matched | na | na | na |
| sigminer_post_p1_rust | comp_pole | 300000 | SBS10a | pole | matched | 0.924652 | 409.071998 | 0.004545 |
| sigminer_post_p1_rust | comp_pole | 300000 | SBS10b | pole | matched | 0.924965 | 119499.508653 | 3.983317 |
| sigminer_post_p1_rust | comp_pole | 300000 | SBS28 | pole | matched | 0.925245 | 45309.029691 | 3.020602 |
| sigminer_post_p1_rust | comp_pole | 300000 | Sig1 | — | matched | na | na | na |
| sigminer_post_p1_rust | comp_pole | 300000 | Sig2 | — | matched | na | na | na |
| sigminer_post_p1_rust | comp_pole | 300000 | Sig3 | — | matched | na | na | na |
| sigminer_post_p1_rust | comp_pole | 1000000 | SBS10a | pole | matched | 0.925698 | 498948.593551 | 1.663162 |
| sigminer_post_p1_rust | comp_pole | 1000000 | SBS28 | pole | matched | 0.926330 | 151051.406443 | 3.021028 |
| sigminer_post_p1_rust | comp_pole | 1000000 | Sig1 | — | matched | na | na | na |
| sigminer_post_p1_rust | comp_pole | 1000000 | Sig2 | — | matched | na | na | na |
| sigminer_post_p1_rust | comp_strong_flat | 100 | SBS4 | strong | matched | 0.869055 | 17.148330 | 0.489952 |
| sigminer_post_p1_rust | comp_strong_flat | 100 | Sig2 | — | matched | na | na | na |
| sigminer_post_p1_rust | main | 100 | SBS1 | easy | matched | 0.925085 | 4.658945 | 0.310596 |
| sigminer_post_p1_rust | main | 100 | Sig2 | — | matched | na | na | na |
| sigminer_post_p1_rust | main | 10000 | SBS1 | easy | matched | 0.944452 | 1415.830060 | 0.943887 |
| sigminer_post_p1_rust | main | 10000 | Sig3 | — | matched | na | na | na |
| sigminer_post_p1_rust | nb | 1000 | SBS1 | easy | matched | 0.954077 | 76.154835 | 0.507699 |
| sigminer_post_p1_rust | nb | 1000 | Sig2 | — | matched | na | na | na |
| sigminer_post_p2 | comp_clock_only | 100 | SBS1 | easy | matched | 0.891341 | 8.046179 | 0.268206 |
| sigminer_post_p2 | comp_clock_only | 100 | Sig1 | — | matched | na | na | na |
| sigminer_post_p2 | comp_clock_only | 1000 | SBS1 | easy | matched | 0.888665 | 61.494592 | 0.204982 |
| sigminer_post_p2 | comp_clock_only | 1000 | Sig1 | — | matched | na | na | na |
| sigminer_post_p2 | comp_clock_only | 10000 | SBS1 | easy | matched | 0.879680 | 384.426922 | 0.128142 |
| sigminer_post_p2 | comp_clock_only | 10000 | Sig1 | — | matched | na | na | na |
| sigminer_post_p2 | comp_pole | 100000 | SBS10a | pole | matched | 0.906727 | 6829.021454 | 0.227634 |
| sigminer_post_p2 | comp_pole | 100000 | SBS10b | pole | matched | 0.906591 | 12814.071357 | 1.281407 |
| sigminer_post_p2 | comp_pole | 100000 | SBS10d | pole | matched | 0.937084 | 19735.625578 | 3.947125 |
| sigminer_post_p2 | comp_pole | 100000 | SBS28 | pole | matched | 0.936267 | 24241.541091 | 4.848308 |
| sigminer_post_p2 | comp_pole | 100000 | Sig1 | — | matched | na | na | na |
| sigminer_post_p2 | comp_pole | 100000 | Sig2 | — | matched | na | na | na |
| sigminer_post_p2 | comp_pole | 100000 | Sig3 | — | matched | na | na | na |
| sigminer_post_p2 | comp_pole | 100000 | Sig4 | — | matched | na | na | na |
| sigminer_post_p2 | comp_pole | 300000 | SBS10a | pole | matched | 0.925103 | 29561.748595 | 0.328464 |
| sigminer_post_p2 | comp_pole | 300000 | SBS10d | pole | matched | 0.918021 | 70085.931186 | 4.672395 |
| sigminer_post_p2 | comp_pole | 300000 | SBS28 | pole | matched | 0.932067 | 80466.861166 | 5.364457 |
| sigminer_post_p2 | comp_pole | 300000 | Sig1 | — | matched | na | na | na |
| sigminer_post_p2 | comp_pole | 300000 | Sig2 | — | matched | na | na | na |
| sigminer_post_p2 | comp_pole | 300000 | Sig3 | — | matched | na | na | na |
| sigminer_post_p2 | comp_pole | 1000000 | SBS10a | pole | matched | 0.924382 | 117190.916324 | 0.390636 |
| sigminer_post_p2 | comp_pole | 1000000 | SBS28 | pole | matched | 0.928758 | 532809.083675 | 10.656182 |
| sigminer_post_p2 | comp_pole | 1000000 | Sig1 | — | matched | na | na | na |
| sigminer_post_p2 | comp_pole | 1000000 | Sig2 | — | matched | na | na | na |
| sigminer_post_p2 | nb | 1000 | SBS1 | easy | matched | 0.916339 | 101.728634 | 0.678191 |
| sigminer_post_p2 | nb | 1000 | SBS2 | easy | matched | 0.859760 | 80.688075 | 0.537920 |
| sigminer_post_p2 | nb | 1000 | SBS40 | flat | matched | 0.875479 | 72.880702 | 0.291523 |
| sigminer_post_p2 | nb | 1000 | Sig1 | — | matched | na | na | na |
| sigminer_post_p2 | nb | 1000 | Sig3 | — | matched | na | na | na |
| sigminer_post_p2 | nb | 1000 | Sig5 | — | matched | na | na | na |
| sigminer_post_v3 | comp_clock_only | 100 | SBS1 | easy | matched | 0.885545 | 20.828346 | 0.694278 |
| sigminer_post_v3 | comp_clock_only | 100 | Sig1 | — | matched | na | na | na |
| sigminer_post_v3 | comp_clock_only | 1000 | SBS1 | easy | matched | 0.891752 | 60.556532 | 0.201855 |
| sigminer_post_v3 | comp_clock_only | 1000 | Sig2 | — | matched | na | na | na |
| sigminer_post_v3 | comp_clock_only | 10000 | SBS1 | easy | matched | 0.877711 | 1911.229610 | 0.637077 |
| sigminer_post_v3 | comp_clock_only | 10000 | Sig2 | — | matched | na | na | na |
| sigminer_post_v3 | comp_pole | 100000 | SBS10a | pole | matched | 0.927516 | 20216.915260 | 0.673897 |
| sigminer_post_v3 | comp_pole | 100000 | SBS28 | pole | matched | 0.924954 | 44783.084741 | 8.956617 |
| sigminer_post_v3 | comp_pole | 100000 | Sig1 | — | matched | na | na | na |
| sigminer_post_v3 | comp_pole | 100000 | Sig2 | — | matched | na | na | na |
| sigminer_post_v3 | comp_pole | 300000 | SBS10a | pole | matched | 0.925330 | 70683.580838 | 0.785373 |
| sigminer_post_v3 | comp_pole | 300000 | SBS28 | pole | matched | 0.927121 | 124316.419161 | 8.287761 |
| sigminer_post_v3 | comp_pole | 300000 | Sig1 | — | matched | na | na | na |
| sigminer_post_v3 | comp_pole | 300000 | Sig2 | — | matched | na | na | na |
| sigminer_post_v3 | comp_pole | 1000000 | SBS10a | pole | matched | 0.927499 | 195754.355949 | 0.652515 |
| sigminer_post_v3 | comp_pole | 1000000 | SBS28 | pole | matched | 0.926043 | 454245.644054 | 9.084913 |
| sigminer_post_v3 | comp_pole | 1000000 | Sig1 | — | matched | na | na | na |
| sigminer_post_v3 | comp_pole | 1000000 | Sig2 | — | matched | na | na | na |
| sigminer_post_v3 | nb | 1000 | SBS1 | easy | matched | 0.921699 | 96.012864 | 0.640086 |
| sigminer_post_v3 | nb | 1000 | SBS2 | easy | matched | 0.864669 | 80.130203 | 0.534201 |
| sigminer_post_v3 | nb | 1000 | Sig1 | — | matched | na | na | na |
| sigminer_post_v3 | nb | 1000 | Sig5 | — | matched | na | na | na |
| sigminer_post_v3_rust | clock | 1000 | SBS1 | easy | matched | 0.958651 | 128.252940 | 0.855020 |
| sigminer_post_v3_rust | clock | 1000 | Sig2 | — | matched | na | na | na |
| sigminer_post_v3_rust | comp_clock_only | 100 | SBS1 | easy | matched | 0.915763 | 31.837777 | 1.061259 |
| sigminer_post_v3_rust | comp_clock_only | 100 | Sig1 | — | matched | na | na | na |
| sigminer_post_v3_rust | comp_clock_only | 1000 | SBS1 | easy | matched | 0.903070 | 138.270280 | 0.460901 |
| sigminer_post_v3_rust | comp_clock_only | 1000 | Sig2 | — | matched | na | na | na |
| sigminer_post_v3_rust | comp_clock_only | 10000 | SBS1 | easy | matched | 0.886404 | 1464.345607 | 0.488115 |
| sigminer_post_v3_rust | comp_clock_only | 10000 | Sig2 | — | matched | na | na | na |
| sigminer_post_v3_rust | comp_flat_triple | 100 | SBS2 | easy | matched | 0.901850 | 31.237919 | 0.822051 |
| sigminer_post_v3_rust | comp_flat_triple | 100 | Sig2 | — | matched | na | na | na |
| sigminer_post_v3_rust | comp_flat_triple | 1000 | SBS2 | easy | matched | 0.889366 | 357.009978 | 0.939500 |
| sigminer_post_v3_rust | comp_flat_triple | 1000 | Sig4 | — | matched | na | na | na |
| sigminer_post_v3_rust | comp_flat_triple | 10000 | SBS2 | easy | matched | 0.889693 | 3726.746628 | 0.980723 |
| sigminer_post_v3_rust | comp_flat_triple | 10000 | Sig2 | — | matched | na | na | na |
| sigminer_post_v3_rust | comp_mmr | 100 | SBS1 | easy | matched | 0.893761 | 14.864042 | 0.743202 |
| sigminer_post_v3_rust | comp_mmr | 100 | SBS20 | mmr | matched | 0.870847 | 58.206396 | 8.315199 |
| sigminer_post_v3_rust | comp_mmr | 100 | Sig1 | — | matched | na | na | na |
| sigminer_post_v3_rust | comp_mmr | 100 | Sig2 | — | matched | na | na | na |
| sigminer_post_v3_rust | comp_mmr | 1000 | SBS20 | mmr | matched | 0.893062 | 108.094286 | 1.544204 |
| sigminer_post_v3_rust | comp_mmr | 1000 | Sig2 | — | matched | na | na | na |
| sigminer_post_v3_rust | comp_pole | 100000 | SBS10a | pole | matched | 0.926985 | 29575.170541 | 0.985839 |
| sigminer_post_v3_rust | comp_pole | 100000 | SBS28 | pole | matched | 0.924788 | 35117.195425 | 7.023439 |
| sigminer_post_v3_rust | comp_pole | 100000 | Sig1 | — | matched | na | na | na |
| sigminer_post_v3_rust | comp_pole | 100000 | Sig2 | — | matched | na | na | na |
| sigminer_post_v3_rust | comp_pole | 300000 | SBS10a | pole | matched | 0.924617 | 45006.380836 | 0.500071 |
| sigminer_post_v3_rust | comp_pole | 300000 | SBS10b | pole | matched | 0.925323 | 74785.818801 | 2.492861 |
| sigminer_post_v3_rust | comp_pole | 300000 | SBS28 | pole | matched | 0.926269 | 45207.800369 | 3.013853 |
| sigminer_post_v3_rust | comp_pole | 300000 | Sig1 | — | matched | na | na | na |
| sigminer_post_v3_rust | comp_pole | 300000 | Sig2 | — | matched | na | na | na |
| sigminer_post_v3_rust | comp_pole | 300000 | Sig3 | — | matched | na | na | na |
| sigminer_post_v3_rust | comp_pole | 1000000 | SBS10a | pole | matched | 0.925060 | 99454.285599 | 0.331514 |
| sigminer_post_v3_rust | comp_pole | 1000000 | SBS10b | pole | matched | 0.924099 | 598392.624553 | 5.983926 |
| sigminer_post_v3_rust | comp_pole | 1000000 | SBS28 | pole | matched | 0.924676 | 51061.661049 | 1.021233 |
| sigminer_post_v3_rust | comp_pole | 1000000 | Sig1 | — | matched | na | na | na |
| sigminer_post_v3_rust | comp_pole | 1000000 | Sig2 | — | matched | na | na | na |
| sigminer_post_v3_rust | comp_pole | 1000000 | Sig3 | — | matched | na | na | na |
| sigminer_post_v3_rust | comp_strong_flat | 100 | SBS7 | strong | matched | 0.857818 | 34.851357 | 0.995753 |
| sigminer_post_v3_rust | comp_strong_flat | 100 | Sig1 | — | matched | na | na | na |
| sigminer_post_v3_rust | main | 100 | SBS1 | easy | matched | 0.904824 | 5.458088 | 0.363873 |
| sigminer_post_v3_rust | main | 100 | Sig2 | — | matched | na | na | na |
| sigminer_post_v3_rust | main | 10000 | SBS1 | easy | matched | 0.940880 | 1407.630837 | 0.938421 |
| sigminer_post_v3_rust | main | 10000 | Sig4 | — | matched | na | na | na |
| sigminer_post_v3_rust | nb | 1000 | SBS1 | easy | matched | 0.966713 | 111.999600 | 0.746664 |
| sigminer_post_v3_rust | nb | 1000 | Sig4 | — | matched | na | na | na |
| sigminer_pre_v3 | comp_clock_only | 100 | SBS1 | easy | matched | 0.881946 | 19.782196 | 0.659407 |
| sigminer_pre_v3 | comp_clock_only | 100 | Sig2 | — | matched | na | na | na |
| sigminer_pre_v3 | comp_clock_only | 1000 | SBS1 | easy | matched | 0.882086 | 212.544563 | 0.708482 |
| sigminer_pre_v3 | comp_clock_only | 1000 | Sig1 | — | matched | na | na | na |
| sigminer_pre_v3 | comp_clock_only | 10000 | SBS1 | easy | matched | 0.878230 | 1976.939702 | 0.658980 |
| sigminer_pre_v3 | comp_clock_only | 10000 | Sig2 | — | matched | na | na | na |
| sigminer_pre_v3 | comp_pole | 100000 | SBS10a | pole | matched | 0.928506 | 21395.377892 | 0.713179 |
| sigminer_pre_v3 | comp_pole | 100000 | SBS28 | pole | matched | 0.923763 | 43604.622110 | 8.720924 |
| sigminer_pre_v3 | comp_pole | 100000 | Sig1 | — | matched | na | na | na |
| sigminer_pre_v3 | comp_pole | 100000 | Sig2 | — | matched | na | na | na |
| sigminer_pre_v3 | comp_pole | 300000 | SBS10a | pole | matched | 0.926906 | 36966.968987 | 0.410744 |
| sigminer_pre_v3 | comp_pole | 300000 | SBS28 | pole | matched | 0.926882 | 158033.031015 | 10.535535 |
| sigminer_pre_v3 | comp_pole | 300000 | Sig1 | — | matched | na | na | na |
| sigminer_pre_v3 | comp_pole | 300000 | Sig2 | — | matched | na | na | na |
| sigminer_pre_v3 | comp_pole | 1000000 | SBS10a | pole | matched | 0.925959 | 246465.404462 | 0.821551 |
| sigminer_pre_v3 | comp_pole | 1000000 | SBS28 | pole | matched | 0.927269 | 403541.076856 | 8.070822 |
| sigminer_pre_v3 | comp_pole | 1000000 | Sig1 | — | matched | na | na | na |
| sigminer_pre_v3 | comp_pole | 1000000 | Sig2 | — | matched | na | na | na |
| sigminer_pre_v3 | nb | 1000 | SBS1 | easy | matched | 0.902504 | 148.142991 | 0.987620 |
| sigminer_pre_v3 | nb | 1000 | SBS40 | flat | matched | 0.865225 | 77.749990 | 0.311000 |
| sigminer_pre_v3 | nb | 1000 | Sig1 | — | matched | na | na | na |
| sigminer_pre_v3 | nb | 1000 | Sig2 | — | matched | na | na | na |
| sigprofiler | clock | 1000 | SBS1 | easy | matched | 1.000000 | 144.076923 | 0.960513 |
| sigprofiler | clock | 1000 | SBS5 | flat | matched | 1.000000 | 72.270000 | 0.240900 |
| sigprofiler | comp_clock_only | 100 | SBS1 | easy | matched | 1.000000 | 26.857143 | 0.895238 |
| sigprofiler | comp_clock_only | 100 | SBS5 | flat | matched | 1.000000 | 35.600000 | 0.508571 |
| sigprofiler | comp_clock_only | 1000 | SBS1 | easy | matched | 1.000000 | 294.250000 | 0.980833 |
| sigprofiler | comp_clock_only | 1000 | SBS5 | flat | matched | 1.000000 | 419.630000 | 0.599471 |
| sigprofiler | comp_clock_only | 10000 | SBS1 | easy | matched | 1.000000 | 2951.000000 | 0.983667 |
| sigprofiler | comp_clock_only | 10000 | SBS5 | flat | matched | 1.000000 | 4322.240000 | 0.617463 |
| sigprofiler | comp_flat_triple | 100 | SBS1 | easy | matched | 1.000000 | 7.000000 | 0.875000 |
| sigprofiler | comp_flat_triple | 100 | SBS13 | easy | matched | 1.000000 | 32.000000 | 0.842105 |
| sigprofiler | comp_flat_triple | 100 | SBS2 | easy | matched | 1.000000 | 17.543210 | 0.461663 |
| sigprofiler | comp_flat_triple | 100 | SBS5 | flat | matched | 1.000000 | 35.258427 | 4.407303 |
| sigprofiler | comp_flat_triple | 1000 | SBS2 | easy | matched | 1.000000 | 200.160000 | 0.526737 |
| sigprofiler | comp_flat_triple | 1000 | SBS5 | flat | matched | 1.000000 | 221.850000 | 2.773125 |
| sigprofiler | comp_flat_triple | 10000 | SBS2 | easy | matched | 1.000000 | 2025.230000 | 0.532955 |
| sigprofiler | comp_flat_triple | 10000 | SBS5 | flat | matched | 1.000000 | 1995.630000 | 2.494537 |
| sigprofiler | comp_mmr | 100 | SBS1 | easy | matched | 1.000000 | 15.826087 | 0.791304 |
| sigprofiler | comp_mmr | 100 | SBS15 | mmr | matched | 0.997432 | 18.400000 | 2.300000 |
| sigprofiler | comp_mmr | 100 | SBS44 | mmr | matched | 1.000000 | 27.545455 | 9.181818 |
| sigprofiler | comp_mmr | 100 | SBS5 | flat | matched | 1.000000 | 20.479452 | 0.511986 |
| sigprofiler | comp_mmr | 100 | SBS6 | mmr | matched | 1.000000 | 20.750000 | 2.075000 |
| sigprofiler | comp_mmr | 1000 | SBS1 | easy | matched | 1.000000 | 194.750000 | 0.973750 |
| sigprofiler | comp_mmr | 1000 | SBS44 | mmr | matched | 1.000000 | 215.666667 | 7.188889 |
| sigprofiler | comp_mmr | 1000 | SBS5 | flat | matched | 1.000000 | 334.266667 | 0.835667 |
| sigprofiler | comp_mmr | 10000 | SBS5 | flat | matched | 1.000000 | 3801.695652 | 0.950424 |
| sigprofiler | comp_pole | 100000 | SBS1 | easy | matched | 1.000000 | 8836.770000 | 0.883677 |
| sigprofiler | comp_pole | 100000 | SBS5 | flat | matched | 1.000000 | 22635.010000 | 0.646715 |
| sigprofiler | comp_pole | 300000 | SBS1 | easy | matched | 1.000000 | 26471.350000 | 0.882378 |
| sigprofiler | comp_pole | 300000 | SBS5 | flat | matched | 1.000000 | 68116.110000 | 0.648725 |
| sigprofiler | comp_pole | 1000000 | SBS1 | easy | matched | 1.000000 | 88294.360000 | 0.882944 |
| sigprofiler | comp_pole | 1000000 | SBS5 | flat | matched | 1.000000 | 226988.930000 | 0.648540 |
| sigprofiler | comp_strong_flat | 100 | SBS5 | flat | matched | 1.000000 | 8.460000 | 0.564000 |
| sigprofiler | comp_strong_flat | 1000 | SBS5 | flat | matched | 1.000000 | 40.360000 | 0.269067 |
| sigprofiler | comp_strong_flat | 10000 | SBS5 | flat | matched | 1.000000 | 69.000000 | 0.046000 |
| sigprofiler | main | 100 | SBS1 | easy | matched | 1.000000 | 12.904762 | 0.860317 |
| sigprofiler | main | 100 | SBS13 | easy | matched | 1.000000 | 9.250000 | 0.616667 |
| sigprofiler | main | 100 | SBS2 | easy | matched | 1.000000 | 3.200000 | 0.213333 |
| sigprofiler | main | 100 | SBS5 | flat | matched | 1.000000 | 14.187500 | 0.472917 |
| sigprofiler | main | 1000 | SBS1 | easy | matched | 1.000000 | 143.600000 | 0.957333 |
| sigprofiler | main | 1000 | SBS2 | easy | matched | 1.000000 | 69.107143 | 0.460714 |
| sigprofiler | main | 1000 | SBS5 | flat | matched | 1.000000 | 83.510417 | 0.278368 |
| sigprofiler | main | 10000 | SBS1 | easy | matched | 1.000000 | 1480.500000 | 0.987000 |
| sigprofiler | main | 10000 | SBS2 | easy | matched | 1.000000 | 714.989474 | 0.476660 |
| sigprofiler | main | 10000 | SBS5 | flat | matched | 1.000000 | 948.478723 | 0.316160 |
| sigprofiler | nb | 1000 | SBS1 | easy | matched | 1.000000 | 145.250000 | 0.968333 |
| sigprofiler | nb | 1000 | SBS2 | easy | matched | 1.000000 | 42.487805 | 0.283252 |
| sigprofiler | nb | 1000 | SBS5 | flat | matched | 1.000000 | 95.368421 | 0.317895 |
| sigprofiler | sparse | 1000 | SBS1 | easy | matched | 1.000000 | 165.256966 | 0.955567 |
| sigprofiler | sparse | 1000 | SBS2 | easy | matched | 1.000000 | 74.896732 | 0.433076 |
| sigprofiler | sparse | 1000 | SBS5 | flat | matched | 1.000000 | 91.707801 | 0.265142 |

Honest footer: the authoritative measurement class is the docker-adapter
run at the frozen protocol — degraded profile at 100 reps. smoke/mock
passes prove pipeline plumbing only and are never quoted as results.
Clock-arm exposure columns are report-only sensitivity rows (undiluted
tumour-basis truth is an open adjudication item, G0 P2g).
