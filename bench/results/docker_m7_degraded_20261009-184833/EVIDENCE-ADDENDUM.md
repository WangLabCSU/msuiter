# EVIDENCE ADDENDUM — hardware pin truth and status-count fix-forward

Appended 2026-10-10 under U-M7-04 slice-B (B1b). This file is an
*additive* companion to the committed evidence in this directory:
`judgment_m7_degraded_20261010-024833.md` and every table here stand as
recorded — nothing is rewritten or replaced. Where prose and the
measured table disagree, this addendum states the measured truth and
the table rules.

## 1. Hardware pin, verbatim by reference

Every cell of this authoritative run executed on ONE degraded VM of the
`10 vCPU / 8 GB` class. The pin is stated in two committed prose
sources; quoted exactly, each extracted in the same command window that
created this file:

- `bench/results/docker_m7_degraded_20261009-184833/judgment_m7_degraded_20261010-024833.md:10`
  > - one Docker VM for every cell (10 vCPU / 8 GB class), no host-side
- `docs/devlog/2026-10-09-m7-benchmark-matrix.md:30`
  > token, one shared VM (Docker Desktop, 10 CPUs / 7.748 GiB — `docker info` verbatim).

Byte-exact corroboration of the same machine (the 42-cell attempt's
OOM postmortem, same devlog):

- `docs/devlog/2026-10-09-m7-benchmark-matrix.md:401`
  > 10 vCPUs / 8319504384 bytes (`docker info` verbatim): sigprofiler cells die

Extraction commands, re-runnable from the repo root:

```
$ grep -n "10 vCPU / 8 GB class" bench/results/docker_m7_degraded_20261009-184833/judgment_m7_degraded_20261010-024833.md
10:- one Docker VM for every cell (10 vCPU / 8 GB class), no host-side
$ grep -n "7.748 GiB" docs/devlog/2026-10-09-m7-benchmark-matrix.md
30:token, one shared VM (Docker Desktop, 10 CPUs / 7.748 GiB — `docker info` verbatim).
$ grep -n "8319504384" docs/devlog/2026-10-09-m7-benchmark-matrix.md
401:10 vCPUs / 8319504384 bytes (`docker info` verbatim): sigprofiler cells die
```

## 2. Status-count fix-forward

The judgment's header summary states, verbatim:

- `bench/results/docker_m7_degraded_20261009-184833/judgment_m7_degraded_20261010-024833.md:19`
  > - cells: 42 total — cached: 42

The authoritative table measures something different.
`timings_sharded_master.csv` (digest below) carries 42 data rows with
the status
histogram `ok: 36, cached: 6` — measured in this same window:

```
$ python3 -I -c "import csv, collections;r=list(csv.DictReader(open('bench/results/docker_m7_degraded_20261009-184833/timings_sharded_master.csv', newline='', encoding='utf-8')));print('rows=%d' % len(r));print(dict(collections.Counter(x['status'] for x in r)))"
rows=42
{'cached': 6, 'ok': 36}
```

**Measured truth for adjudication: 36 `ok` / 6 `cached` over 42 cells.**
The judgment's `cached: 42` line remains as historically recorded
(forward-only law); it overstates the cached count relative to the
table, and the table rules. The judgment itself documents the cached
statuses it does attest — the RB-09 re-adjudication lineage, quoted:

- `bench/results/docker_m7_degraded_20261009-184833/judgment_m7_degraded_20261010-024833.md:25`
  > - **sigminer__main__N100** — prior flag `defect-floor: wall/cpu 1004.9s > 3.0x pre-registered floor 310.0s (tool=sigminer arm=main n=100)` (floor epoch `pre-RB-09/rep-1-anchor-table@ddfaa2e`) now passes as `cached` under re-calibrated epoch `46bc002d7aea6b7f`;

(`cached` is a pass status under the harness contract —
`bench/m7/tools/matrix_governance.py:509` — `PASS_STATUSES = ("ok", "cached")`; cached rows are four-file-guard-trusted
recomputations of previously attested invocations, not failures.)

## 3. Integrity seals

SHA-256 over the exact bytes quoted above, measured in-window and
cross-checked tool-to-tool per file:

```
67779adefb2895984dcfa385b8b1c6402a488dac66f9ab5b1384ce8e155b83e7  bench/results/docker_m7_degraded_20261009-184833/judgment_m7_degraded_20261010-024833.md
bba05bd9b8e3d00efe9cdc8918ea7ad91a239dae7d45e696abc948674ca5fd8f  docs/devlog/2026-10-09-m7-benchmark-matrix.md
5389f3cdffb21e7da0684bc17bad3e9420eba63f8942b932eaab54a5c3155868  bench/results/docker_m7_degraded_20261009-184833/timings_sharded_master.csv
```

Control vector, measured the same window — `abc` hashes to

```
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
```

in `hashlib`, `openssl dgst -sha256 -r`, `node crypto.createHash` and
`shasum -a 256` (Apple CommonCrypto) alike; the per-file digests above
were `hashlib`/`shasum` pair-checked before publication.

## 4. Forward path

From U-M7-04 B1a the harness timings writer itself carries the pin:
every written row stamps `host` and `hw_profile` columns
(`bench/m7/competitors/timings.py`, head at:

```
$ git log --oneline -1 -- bench/m7/competitors/timings.py
cfef27c feat(m7): timings writer emits optional trailing hardware pins host+hw_profile; pinned reader with 7-col legacy back-compat branch
```

so future authoritative runs attest their machine from the table alone
and no prose addendum is needed.

