#!/bin/sh
# ⑰ CJK-zero gate (Phase-7 O6, governance-scan-integrity law): authored
# surfaces must carry zero CJK/Hangul/kana bytes. The scan is UNTRUSTED until
# it has been seen to fire: --selftest plants a Han byte in a temp file and
# demands this very scanner reports it (a silent scanner is a vacuous one;
# perl without -CSD decodes nothing and matches nothing -- the known
# false-green trap on BSD grep -P and undecoded perl alike).
#
# Usage:  cjk_gate.sh --selftest            (law attestation, exit 0 = fires+cleans)
#         cjk_gate.sh FILE...               (scan list; exit 1 = hit, prints file:line)
set -u

scan() {                                             # $@ = files
    perl -CSD -ne 'if (/\p{Han}|\p{Hiragana}|\p{Katakana}|\p{Hangul}/) {
                       printf "%s:%d: CJK-HIT\n", $ARGV, $.; exit 1 }' "$@"
}

if [ "${1:-}" = "--selftest" ]; then
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/cjkg_st_XXXXXX")
    trap 'rm -rf "$tmp"' EXIT
    printf 'ok line, no exotic bytes\n' > "$tmp/clean.py"
    # The plant is a codepoint escape, never a literal: a gate that embeds
    # its own forbidden bytes cannot be scanned by itself.
    perl -CS -e 'print "plan line \x{6821}\n"' > "$tmp/planted.py"
    scan "$tmp/clean.py" || { echo "SELFTEST-DEFECT: clean file condemned"; exit 2; }
    if out=$(scan "$tmp/planted.py" 2>&1); then
        echo "SELFTEST-DEFECT: scanner silent on planted Han byte -- vacuous"
        exit 2
    else
        echo "SELFTEST-FIRE: $out"
    fi
    echo "[cjk_gate] selftest PASS (fired on plant, clean on clean)"
    exit 0
fi

[ $# -eq 0 ] && { echo "usage: cjk_gate.sh --selftest | FILE..."; exit 2; }
scan "$@" && { echo "[cjk_gate] PASS zero CJK over $# file(s)"; exit 0; } \
           || { echo "[cjk_gate] FAIL CJK present"; exit 1; }
