#!/bin/sh
# RB-05(3.c) build-time self-witness: the cell protocol executed end-to-end
# inside the build, under RUN --network=none (the ruling layer adds it; the
# pre-bake rehearsal reproduces it with docker run --network=none + a staged
# dependency library via R_LIB_USER).
#
# The composed argv is the zero-touch composer's, verbatim in shape:
# competitors/docker_cmd.py ENTRY_ARGS (["--params", IN/params.json,
# "--outdir", OUT, "--"]) wrapping sigminer_adapter._child_argv(None)
# (Rscript /work/run_sigminer.R --counts ... --catalog ... --params ...
# --outdir ...) with the frozen THREAD_CAPS all at CAP_VALUE=1. The fixture
# inputs are the stage2-proven cell bytes (manifest
# bench/results/docker_m7_PILOT_20261008-200152/rehearsal_slice3-r4/
# rehearsal_manifest.json).
#
# Build dies unless: rc=0; intervals.csv carries the exact seven-column
# header plus >=1 data row; errors.log exists; timing.json exists and its
# sidecar schema is valid (ru_utime/ru_stime/cpu_seconds/exit_status, exit
# 0, cpu_seconds == utime+stime). The four-file trust guard holds at the
# container layer: manifest.json is host-side by contract (written by
# run_bench.py), so the build asserts every container-side production and the
# matrix re-asserts the full four. Any undeclared runtime dependency is a
# build-time death here, never a mid-measurement auto-install.
set -e
export OMP_NUM_THREADS=1 OMP_THREAD_LIMIT=1 R_LIMIT_THREADS=1 GOMAXPROCS=1
export MSUITER_THREADS=1 STAN_OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1

IN=/work/mini/in
OUT=/work/mini/out

test -s "$IN/counts.csv"
test -s "$IN/catalog.csv"
test -s "$IN/params.json"

python3 /work/m7_entry.py --params "$IN/params.json" --outdir "$OUT" -- \
  Rscript /work/run_sigminer.R --counts "$IN/counts.csv" \
  --catalog "$IN/catalog.csv" --params "$IN/params.json" --outdir "$OUT"

test -s "$OUT/intervals.csv"
test -s "$OUT/errors.log"
test -s "$OUT/timing.json"
head -n 1 "$OUT/intervals.csv" |
  grep -q -x 'sample_id,signature,estimate,lo95,hi95,estimand,zeroed'
awk -F, 'NR > 1 && NF == 7 { n++ } END { exit (n >= 1 ? 0 : 1) }' \
  "$OUT/intervals.csv"
python3 -c '
import json, sys
t = json.load(open("/work/mini/out/timing.json"))
keys = ("ru_utime", "ru_stime", "cpu_seconds", "exit_status")
ok = (all(k in t for k in keys) and t["exit_status"] == 0
      and abs(t["cpu_seconds"] - (t["ru_utime"] + t["ru_stime"])) < 1e-9)
sys.exit(0 if ok else 1)'

echo "[self-witness] mini-cell OK: rc 0, sidecar schema valid, container-side guard satisfied"
