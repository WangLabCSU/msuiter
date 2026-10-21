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

if [ "${1:-}" = "--self-test" ]; then
  tpl=$(mktemp "/tmp/shard-transcripts-selftest-XXXXXX") || exit 1
  d="$tpl.d"; mkdir -p "$d/shard-logs"
  trap 'rm -rf "$tpl" "$d"' exit
  printf 'noise\nMSUITE-ATTEST kind=guards shard=1 status=ok\n' > "$d/shard-logs/shard-1.log"
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
  if ! grep -q 'MSUITE-ATTEST' "$f"; then
    echo "-- deep $f --"
    tail -n "$depth" "$f"
  fi
done
