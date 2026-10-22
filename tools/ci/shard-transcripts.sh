#!/bin/bash
# shard-transcripts.sh -- print the long tail of every shard transcript that
# carries no attestation line: the shard whose process died before writing
# its verdict. The loop's own dump is a fixed 25-line tail per shard (log
# hygiene), which shows survivors' verdicts and only the dying shard's final
# page. A run with rc != 0 reads here before the transcripts go transient.
#
# usage: shard-transcripts.sh [dir]        (default: shard-logs)
#        shard-transcripts.sh --self-test  (controls must fire, not just run)
set -u

# One token, three consumers: the grep below, the self-test fixture, and the
# emitter cross-check. The cross-check greps the token against the PRODUCTION
# source of truth -- the attestation is minted in
# tests/testthat/helper-ci-shard-census.R -- so a drift between this script's
# pattern and the emitter's bytes can no longer masquerade as coverage (run
# 39646023270: a pattern missing one letter was self-consistent with its own
# fixture, the self-test stayed green while production never matched).
pat='MSUITER-ATTEST'
here=$(cd "$(dirname "$0")" && pwd)
emitter="$here/../../tests/testthat/helper-ci-shard-census.R"

if [ "${1:-}" = "--self-test" ]; then
  if ! grep -q "$pat" "$emitter"; then
    echo "SELFTEST DEFECT: the token '$pat' is not in the emitter $emitter" >&2
    exit 1
  fi
  tpl=$(mktemp "/tmp/shard-transcripts-selftest-XXXXXX") || exit 1
  d="$tpl.d"; mkdir -p "$d/shard-logs"
  trap 'rm -rf "$tpl" "$d"' exit
  printf 'noise\n%s kind=guards shard=1 status=ok\n' "$pat" > "$d/shard-logs/shard-1.log"
  printf 'the dying block\n' > "$d/shard-logs/shard-2.log"
  out=$(bash "$0" "$d/shard-logs")
  case "$out" in
    *shard-2.log*) : ;;
    *) echo "SELFTEST DEFECT: the dying shard went unspeaked" >&2; exit 1 ;;
  esac
  case "$out" in
    *"deep $d/shard-logs/shard-1.log"*)
      echo "SELFTEST DEFECT: an attested shard was printed" >&2; exit 1 ;;
  esac
  printf 'SHARD-TRANSCRIPTS SELFTEST OK\n'
  exit 0
fi

dir=${1:-shard-logs}
depth=${MSUITE_SHARD_DEEP_TAIL:-300}
for f in "$dir"/*.log; do
  [ -e "$f" ] || continue
  if ! grep -q "$pat" "$f"; then
    echo "-- deep $f --"
    tail -n "$depth" "$f"
  fi
done
