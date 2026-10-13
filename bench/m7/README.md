# bench/m7 — U-M7-02 competitor benchmark harness

The competitor benchmark matrix: the orchestrator that measures the msuiter
side against the containerised competitors (sigminer / sigprofiler) under the
frozen G0 sampling protocol and files the timings/judgment products under
`bench/results/`. Like `bench/g0`, this is a bench artefact that never enters
the package (D9) and imports no package code.

Governance (profile law, floor table, hardware-pin law, verdict vocabulary,
single-authoritative-shot discipline) is owned by the devlogs listed at the
bottom; this README only documents the runnable surface.

## Layout

```
bench/m7/
├── run_bench.py            orchestrator (profile x competitors x arms -> outdir)
├── adapters/               competitor container runners
│   ├── Dockerfile.sigminer / Dockerfile.sigprofiler / install_sigminer.R
│   ├── run_sigminer.R / run_sigprofiler.py / m7_entry.py / self_witness.sh
│   └── mini_cell/          committed real-cell fixtures (catalog.csv, counts.csv)
├── competitors/            registry + mock/docker adapters + intervals/timings
├── scoring/                cell extraction, Hungarian matching, metrics, judgment
├── tools/
│   ├── run_m7_bench.sh             canonical docker-ignition launch wrapper
│   ├── matrix_governance.py        floor-table governance + hardware-pin verdict
│   ├── verify_hardware_pin.py      reader-side: attests a committed table from its bytes
│   ├── verify_campaign.py          GO-05 campaign law oracle (shared with bench/bootstrap)
│   ├── verify_rehearsal.py / verify_seed_determinism.py / audit_executed_surface_deps.py
│   └── probe_sigminer_cell_argv.py / probe_sigprofiler_cell_argv.py / smoke_rehearsal.sh
└── tests/                  python3 -m tests.run_all (no pytest requirement)
```

The sibling lane `bench/bootstrap/` (single-shot bootstrap-vs-sigminer
campaign, own README) calls the same oracle `tools/verify_campaign.py`, so
measurement and adjudication cannot drift apart.

## Canonical invocations

Self-check (the lane gate; run from this directory):

```sh
cd bench/m7
python3 -m tests.run_all        # prints "N/N tests passed." and exits 0
```

Dry-run of the matrix plan (no filesystem effect):

```sh
python3 run_bench.py --profile degraded --adapter docker --provider cosmic-file --dry-run
```

Authoritative launches go through `tools/run_m7_bench.sh`, which asserts the
`M7_HW_PROFILE` pin before the first shard (exit 2 when unset): the
authoritative `run_bench.py` pass likewise refuses to file without it.

## run_bench.py switches

As printed by `python3 run_bench.py --help` (the help text is the authority):

| switch | meaning |
|---|---|
| `--profile {smoke,primary,degraded}` | frozen shape/reps profile |
| `--adapter {mock,docker}` | measurement adapter |
| `--provider {synthetic,cosmic-file}` | catalog provider |
| `--competitors NAME[,…]` | comma-separated names from the registry ('mock' additionally resolves under `--adapter mock`) |
| `--arms A[,…]` | comma-separated arm filter (sharding hook, as in G0) |
| `--reps N` | override repetition count (profile default otherwise) |
| `--provider-seed N` | synthetic provider seed (cosmic-file ignores it) |
| `--cachedir DIR` | cell cache directory |
| `--outdir DIR` | output directory |
| `--force-rerun` | ignore cached cell outputs, re-invoke every cell |
| `--floor-gate {on,off}` | RB-08(7) 3x-floor DEFECT gate (+ defect ledger); 'off' is for calibration probes only — the matrix pass always runs it ON |
| `--shard-tag TAG` | suffix for the timings file name (sharded driver) |
| `--n-list N[,…]` | comma-separated N-point filter (pilot/shard selection; per-arm intersection, mirrors `--arms`) |
| `--dry-run` | print the machine-readable matrix plan (JSON) and exit 0 without touching the filesystem |

## Results

Committed witnesses live in `bench/results/`, one timestamped outdir per
authoritative run — e.g. `bench/results/docker_m7_degraded_20261010-202330/`
(9-column hardware-pinned master table + judgment + Seeds manifest); see that
directory's files for the output contract.

## Governance records (do not re-explain here)

- `docs/devlog/2026-10-08-m7-competitor-harness-design.md` — harness design memo
- `docs/devlog/2026-10-09-m7-benchmark-matrix.md` — matrix run + floor-table governance
- `docs/devlog/2026-10-10-m7-hardware-pin.md` — hardware-pin authority law and reader verifier
- `docs/devlog/2026-10-10-m7-benchmark-ergonomics.md` — benchmark trio naming ruling
- `docs/devlog/2026-10-10-m7-rb11-restoration.md` — RB-11 restoration record
- `docs/devlog/2026-10-10-m7-bootstrap-campaign.md` — GO-05 campaign pre-registration (protocol)
