# G0 degraded authoritative run — PI-gate closure (2026-10-08)

First AUTHORITATIVE-RUN-COMPLETE under the frozen PI protocol
(docs/devlog/2026-09-28-G0-pi-adjudication.md §PI-5): real docker adapter x
cosmic-file provider, degraded profile, 100 reps, commit 0113d05.

**Verdict: A.** A-clause ① fires on 108 adjudication cells (ĉ <= 0.85 and
CP_hi < 0.90); A-clause ② (flat all <= 0.90 @ N >= 300) holds; kill
conditions not met. Sensitivity arms (clock, nb, sparse) contributed report
columns only, per frozen augmentation clause b. 162 absolute-estimand cells
entered the adjudication; 42/42 tool cells completed with zero casualties on
the final cache-hit pass.

## The road here (execution-layer lessons, protocol untouched)

1. **Over-subscription OOM storm -> thread caps.** Under the 8 GB Docker VM
   the 8-way arm shard fan-out starved the kernel: 13 cells died with exit
   137 (SIGKILL). Root cause was thread oversubscription, not the protocol.
   Fix: execution-layer env caps injected before the image name
   (`OMP_NUM_THREADS=1`, `R_LIMIT_THREADS=1`, `GOMAXPROCS=1`,
   `MSUITER_THREADS=1`) -- see 333f06e. Sampling constants remained frozen
   throughout (G0 drift guards in ci-selfcheck kept green).
2. **Shard orchestration.** tools/run_degraded_pi.sh (d49e0d3): eight arm
   shards over one shared cachedir; a cell is authoritative only when its
   single `intervals.csv` appears after all 100 reps; the run ends with a
   serial cache-hit full recompute that emits the judgment + master timings.
3. **Verify-by-command discipline.** Every count above was taken from direct
   `find`/`ls` on the artifacts and the tail of the orchestration log, never
   from a rendered notification.

## Artifacts (this commit)

- `judgment_degraded_20261008-013750.md` — the verdict document (harness output).
- `timings_sharded_master.csv` — 42 cells x 100 reps timing matrix (paper benchmark table seed).
- `timings_degraded_20261008-013748.csv` / `coverage_degraded_*.csv` — final-pass timings + cell coverage.
- `Seeds.txt` — per-rep RNG seed record backing exact reproducibility.

All under `bench/results/docker_degraded_pi_20261007-212438/`, the contract
output location of the orchestration script (path relative to bench/g0).

## What this does NOT claim

- This is the **degraded** profile (100 reps, PI gate). The primary
  profile run (weekend-scale, protocol's full rep count) remains open and
  is the manuscript's headline benchmark substrate; its framing feeds the
  G0 Framing ADR before M7 writes any performance claims.
- D3 user COSMIC data stayed outside the repo (shared cachedir is
  gitignored, read-only verbatim mounts).
