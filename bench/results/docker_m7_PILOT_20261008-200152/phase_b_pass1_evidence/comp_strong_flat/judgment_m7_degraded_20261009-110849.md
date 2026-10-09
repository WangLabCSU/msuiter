# U-M7-02 fairness attestation — profile=degraded, adapter=docker, provider=synthetic

This is the **FAIRNESS ATTESTATION** half of the authoritative run: it
certifies *how* the cells ran, not *who won*.

- single ground truth: all competitors saw msuiter-generated simulated
  counts from the frozen G0 simulator (master seed 20260928, data streams bit-identical to G0)
- documented defaults only: zero threshold/parameter overrides (memo §3)
- frozen thread caps on every container cell: OMP_NUM_THREADS=1, OMP_THREAD_LIMIT=1, R_LIMIT_THREADS=1, GOMAXPROCS=1, MSUITER_THREADS=1, STAN_OMP_NUM_THREADS=1, OPENBLAS_NUM_THREADS=1
- one Docker VM for every cell (10 vCPU / 8 GB class), no host-side
  execution of container competitors (§4.1/§4.2)
- seeds: m7-tool-namespaced derivation, all on disk (Seeds.txt); commit 7de5b8cf7492fb818c527672ae9fc6ef4bb6f3ca

| competitor | version | image ref | image digest | status |
|---|---|---|---|---|
| sigminer | 2.3.1 | msuiter-sigminer:slice3-r5 | sha256:05cb29e0cfe881c3a0c7d1ec7c9058cfbbb9539f5d1c135787027e6002c703e9 | ready |
| sigprofiler | v1.1.5 | m7-sigprofiler:spa-1.1.5 | sha256:7dba2f43ad3a3858ed1cfdedd278c9c2f52a665fd4c18ac91a482b74258bfbed | ready |

- cells: 6 total — fail: 2, ok: 4
- timings table: timings_m7_degraded_20261009-110849.csv (G0 six-column prefix + cpu_seconds; every measured second attributable)

Honest footer: this is harness output serving as the adjudication gate.
Authoritative competitor measurement is the docker-adapter run at the
frozen protocol; smoke/mock passes prove pipeline plumbing only. This
half attests fairness, not outcomes; the Hungarian P/R/F1 scoring
verdict (U-M7-02 scoring slice, ARCHITECTURE §8) is appended below on
the final pass, produced by the scoring engine over the cachedir.
