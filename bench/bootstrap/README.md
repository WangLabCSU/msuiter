# bench/bootstrap — GO-05 bootstrap-vs-sigminer campaign lane

Host-R measurement lane for the bootstrap row of `docs/PERFORMANCE.md`
(U-M7-04 GO-05, SCOPE B). Pre-registration law: the protocol
`docs/devlog/2026-10-10-m7-bootstrap-campaign.md` is committed before any
campaign execution and is the sole definition of what a number may mean here.

Instruments:

- `gen_campaign.R` — the SOLE data generator (deterministic under the frozen
  `SEED=20260928`; double-run byte identity is a TDD unit; emits
  `campaign.rds` + `seal.json` + `Seeds.txt`).
- `run_campaign.R` — the single launcher: environment attestation (the frozen
  `M7_HW_PROFILE` pin), docker-ps co-tenancy census, launch ledger, probes →
  oracle tier decision → single authoritative full arms (3x-floor gate),
  share-normalized correctness anchor, invariance witness, pinned table,
  reader-verified `result.md`.
- `emit_campaign_table.py` — writes the 9-column pinned
  `campaign_timings.csv` from the arm witnesses.
- Laws (tier, floor, anchor, reader verdict) live in exactly one place:
  `bench/m7/tools/verify_campaign.py` — the harness and the post-hoc reader
  call the same oracle, so measurement and adjudication cannot drift.

One-key full shot (after the m7 matrix has fully completed):

```sh
export M7_HW_PROFILE='host-R campaign | Apple Silicon | 10 cores | hw.ncpu=10 hw.memsize=25769803776 | R 4.5.2'
TS=$(date -u +%Y%m%dT%H%M%SZ)
Rscript --vanilla bench/bootstrap/run_campaign.R -- \
  --outdir bench/results/bootstrap_vs_sigminer_${TS} --mode full \
  2>&1 | tee /tmp/go05lane/campaign_${TS}.log
```

Smoke rehearsals (`--mode pilot --smoke`, small shapes, disposable numbers)
must also run with no measurement container live; their outdirs live under
/tmp and never support a claim. Re-read a committed campaign any time with
`python3 bench/m7/tools/verify_campaign.py --campaign <dir>`.
