#!/usr/bin/env sh
# Valgrind-leg harness for the Scheduled deep checks (issue #32 remediation).
#
# The archived `--use-valgrind` whole-suite runs took 5h+ on the runner and
# were doubly silenced -- a job-level `continue-on-error: true` plus an
# rcmdcheck `error_on = "never"` -- so they could not have failed (the D1
# class). The loudness law this harness installs: a valgrind leg is green
# only when memcheck demonstrably completed (its report census is REQUIRED),
# the nominated native-sentry roster ran under it, and the canary pair
# proves detection: a committed violation REPORTS, the clean run and the
# uninstrumented run stay SILENT.
#
# The 2026-10-21 runner forensics adds the TOOL ATTESTATION ORDER: an
# instrumented canary trip must demonstrably complete its lifecycle (its
# ERROR SUMMARY is REQUIRED) before the roster's census may speak at all,
# and a reportless roster run whose guest produced attestations while
# memcheck exited on a signal adjudicates as the tool's death, not the
# guest's (the silent-core-dump class).
#
# The same day's live-fire adds the REPORT SHAPE LAW: every line memcheck
# authors is ==pid== prefixed while the guest's own stdout is not, so the
# census patterns are pid-tolerant; a fully-freed heap omits the
# definitely-lost line entirely and attests zero loss by its own words
# ("All heap blocks were freed") -- absence of that line is a verdict, not
# an incompleteness. Violation headings likewise ride byte-true (no "bytes"
# suffix), and a trip's content words must be matched by a counted error.
#
# The same day's child-instrumentation forensics adds the CENSUS ADJUDICATION
# LAW (--trace-children=yes makes it necessary): the log then carries one
# report block per process -- the guest R and the tool swarm its build and
# test machinery execs (sh, sed, uname, rm under /bin or /usr/bin). Block
# order is a race, so no tail -1 read of a per-pid line is lawful: the last
# writer is typically the outer wrapper attesting its own zeros while an
# earlier block held the guest's errors. valgrind_report_census walks EVERY
# block -- per-pid completion, summed ERROR SUMMARY, evidence-cited ambient
# allowances, hard-zero on definitely-lost bytes -- and the census blindness
# classes are regression-tested by synthetic fixtures (selftest mode).
#
# Usage:
#   run_valgrind_leg.sh leg        # the gate itself (the CI arm)
#   run_valgrind_leg.sh selftest   # census fixtures + canary-only discriminating control
#
# Budget: every valgrind invocation is wall-clocked at ${valgrind_budget_s}
# seconds (default 3300, inside the 120-minute job ceiling); an overrun dies
# loudly instead of drifting into the platform timeout.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
canary_manifest=$here/valgrind-canary/Cargo.toml
canary_work=$root/src/rust/target/valgrind-canary
log_dir=${CHECK_VALGRIND_DIR:-$root/check-valgrind}
valgrind_budget_s=${valgrind_budget_s:-3300}
vg_error_rc=42

# The native-sentry roster: shipped testthat files whose code paths cross the
# R-to-native boundary. The whole suite is not valgrind-budget-coverable
# (2026-10-19 evidence: cancelled at the 360-minute platform ceiling).
#   ffi-probes -- the msffi_* call/error protocol, the direct FFI surface
#   fit        -- the fit numeric path through the engine/catalog call sites
#   extract    -- the extract numeric path (index arithmetic, the ASan class)
#   ms-compare -- the compare-null numeric path through the compare engine;
#     returned to the roster 2026-10-22 with the issue-#36 adjudication --
#     the roster-narrowing commit had silently dropped this FFI boundary
#     from observation, and an adjudicated surface is a measured surface.
roster="ffi-probes fit extract ms-compare"

die() { printf 'valgrind-leg: FAIL: %s\n' "$1" >&2; exit 1; }
note() { printf 'valgrind-leg: %s\n' "$1"; }

mode=${1:-}
case "$mode" in
  leg | selftest) ;;
  *) die "usage: run_valgrind_leg.sh <leg|selftest>" ;;
esac

probe_valgrind() {
  command -v valgrind >/dev/null 2>&1 \
    || die "the valgrind binary is missing -- an arm without its tool attests nothing"
  command -v Rscript >/dev/null 2>&1 \
    || die "Rscript is missing -- an arm that cannot spawn its subject attests nothing"
  command -v timeout >/dev/null \
    || die "coreutils timeout is missing -- the wall-clock budget cannot be enforced"
  valgrind --version >/dev/null || die "valgrind --version failed"
  note "$(valgrind --version | head -1) accepted; wall-clock budget ${valgrind_budget_s}s per invocation"
}

# Suppression precedence: env override > vendored reviewed file > opportunistic
# R-installed copies > none. R ships no valgrind.supp of its own -- falsified
# 2026-10-21 against the R 4.6.1 source tarball (full listing, zero hits);
# distro packages maintain their own, and ours is the reviewed artifact
# tools/deep-checks/valgrind.supp. With none in force the ERROR SUMMARY census
# must measure zero unadorned -- suppressions can never soften that gate, and
# the canary pair proves memcheck stays live under whatever file is in force.
resolve_suppressions() { # sets $suppressions ("" allowed) and $suppressions_kind
  suppressions=""; suppressions_kind=""
  cand=${VALGRIND_SUPPRESSIONS:-}
  if [ -n "$cand" ]; then
    [ -f "$cand" ] || die "VALGRIND_SUPPRESSIONS names a missing file: $cand"
    suppressions=$cand
    suppressions_kind=env-override
  elif [ -f "$here/valgrind.supp" ]; then
    suppressions=$here/valgrind.supp
    suppressions_kind=vendored-reviewed
  else
    home=$(Rscript -e 'cat(R.home())')
    for probe in "$home/etc/valgrind.supp" "$home/../etc/valgrind.supp"; do
      if [ -f "$probe" ]; then
        suppressions=$probe
        suppressions_kind=R-installed
        break
      fi
    done
    [ -n "$suppressions_kind" ] || suppressions_kind=none-measured-clean
  fi
}

# run_valgrind executes; it adjudicates only the wall-clock budget. Whether
# the run COUNTS is decided by the report census (tool completion is the
# census's authority), then by the guest exit code -- in that order, so an
# incomplete census can never be masked by an exit-code gate firing first.
# --trace-children=yes is load-bearing: at the default (no) the guest escapes
# instrumentation through execve, and the Rscript wrapper let the whole
# 413-test roster run native in 4 s while the "instrumented" run attested
# rc=0 (repro6 forensics, 2026-10-21).
run_valgrind() { # run_valgrind <log> <cmd...> -> sets vg_rc (caller adjudicates)
  log=$1; shift
  if [ -n "$suppressions" ]; then
    set -- --suppressions="$suppressions" "$@"
  fi
  if timeout --kill-after=60 "$valgrind_budget_s" \
      valgrind --tool=memcheck --leak-check=full --track-origins=yes \
        --error-exitcode="$vg_error_rc" --num-callers=20 \
        --trace-children=yes \
        "$@" > "$log" 2>&1
  then vg_rc=0; else vg_rc=$?; fi
  case "$vg_rc" in
    124 | 137) die "the ${valgrind_budget_s}s wall-clock budget was exceeded by: $*" ;;
  esac
}

install_package() {
  libdir=$(mktemp -d)
  export R_LIBS_USER="${R_LIBS_USER:+$R_LIBS_USER:}$libdir"
  note "installing the package for the native-sentry roster"
  R CMD INSTALL --library="$libdir" --no-multiarch "$root" \
    >"$log_dir/install.log" 2>&1 \
    || die "R CMD INSTALL failed (log $log_dir/install.log)"
}

build_driver() {
  driver=$(mktemp "${TMPDIR:-/tmp}/valgrind-sentry-XXXXXX")
  # Structured per-file attestations give the executed-work census a
  # machine-checkable signal (the counterpart of cargo's "test result: ok").
  # Load semantics mirror tests/testthat.R's test_check idiom: the leg
  # consumes the INSTALLED package (load_package="none"), never a pkgload
  # reload of the source tree; the reporter must be a real exported object.
  # Both laws are CI-measured lessons (2026-10-20): an unresolvable symbol
  # CRASHED every file instantly, and auto-loading FAILED the native-bound
  # tests -- the CRASH lines now carry the verbatim reasons so this never
  # again needs an artifact download to diagnose.
  # <!-- census-exempt tokens: 0 --> the superseded CRASH "0 0" placeholder
  # was structural filler, not a measurement; verdicts ride the reason line.
  cat > "$driver" <<'EOF'
args <- commandArgs(TRUE)
files <- strsplit(args[[1]], ";")[[1]]
library(msuiter)
cat(sprintf("VG_BOOT R=%s testthat=%s msuiter-lib=%s\n",
            paste(R.version[6:7], collapse="."),
            as.character(packageVersion("testthat")),
            dirname(dirname(find.package("msuiter")))))
ok <- TRUE
for (f in files) {
  res <- tryCatch(
    testthat::test_file(f, package = "msuiter", load_package = "none",
                        reporter = testthat::SilentReporter$new(),
                        stop_on_failure = FALSE),
    error = function(e) {
      msg <- gsub("[\r\n]+", " | ", conditionMessage(e), perl = TRUE)
      cat(sprintf("VG_TESTFILE %s CRASH %s\n", f, substr(msg, 1, 400)))
      NULL
    })
  if (is.null(res)) { ok <- FALSE; next }
  df <- as.data.frame(res)
  npass <- sum(df$passed); nbad <- sum(df$failed + df$error + df$warning)
  cat(sprintf("VG_TESTFILE %s %s %d %d\n", f,
              if (nbad == 0) "PASS" else "FAIL", npass, nbad))
  ok <- ok && nbad == 0
}
quit(status = if (ok) 0L else 1L)
EOF
}

valgrind_report_census() { # <suite-log> -- summed, adjudicated, per-pid (PR #45)
  log=$1
  if ! grep -qE '^(==[0-9]+== )?ERROR SUMMARY:' "$log"; then
    guest_saw=$(grep -c '^VG_TESTFILE' "$log" || true)
    tail_ctx=$(tail -5 "$log" | tr '\n' '|' | cut -c1-300)
    if [ "$vg_rc" -ge 129 ] && [ "$vg_rc" -le 192 ]; then
      die "MEMCHECK CORE DIED on signal $((vg_rc - 128)) (rc=$vg_rc) with $guest_saw guest attestation(s) and no report ever produced -- the tool's death is not the guest's (silent-core-dump class; log $log, tail [$tail_ctx])"
    fi
    die "LOUDNESS LAW: no ERROR SUMMARY line in $log (rc=$vg_rc, guest-lines=$guest_saw, tail [$tail_ctx]) -- memcheck never completed; a reportless run attests nothing (the D1 lesson)"
  fi
  grep -qE '^(==[0-9]+== )?HEAP SUMMARY:' "$log" \
    || die "LOUDNESS LAW: no HEAP SUMMARY line in $log -- the run terminated before the census could speak"
  # Under --trace-children=yes the log is a forest of per-pid report blocks
  # written in completion order (a race), so every per-pid figure is SUMMED
  # over blocks and no tail -1 read is lawful -- the wrapper's zeros would
  # mask the guest's errors (repro6 forensics, 2026-10-21). The laws, in
  # adjudication order, each regression-tested by a synthetic fixture:
  #   NO SELF-DECEPTION -- a nonzero (suppressed:) count would launder a
  #     report through the forks provably-dead suppression matcher (control
  #     probe 2026-10-21: a textbook invalid-read matches under no accepted
  #     spelling), so the census, not a suppression file, is the gate;
  #   HARD ZERO -- one byte definitely lost is fatal whoever the owner;
  #   HE WHO OPENS HIS MOUTH MUST FINISH -- a pid speaking any part of a
  #     report must speak the whole of it (a child that dies mid-report is
  #     the death of the tool, not of the guest);
  #   OWNERSHIP ADJUDICATION -- every loss record is allowed only by a
  #     reviewed evidence-cited signature below, else the leg dies naming
  #     pid, Command and record;
  #   FULL ACCOUNTING -- sum(ERROR SUMMARY) == count(loss-record headers)
  #     + adjudicated CJU hits: memcheck prints one header per counted
  #     leak error, so an excess is an error class with no owner, a
  #     deficit is a report that counted what it did not print, and a
  #     per-pid surplus is lawed only by its CAPTURED error context -- an
  #     arithmetic surplus alone never adjudicates;
  #   EXECUTED-WORK -- the roster attestation census (the D1 lesson).
  # The allowlists are byte-true against the 2026-10-21 13:42 truth-run
  # capture (/tmp/vgart5/repro6/check-valgrind/valgrind-suite.log):
  #   tool swarm -- the R build/test machinery execve-follows coreutils
  #     (/bin/sh -c wrappers, sed, uname, rm, which); their leaks are the
  #     container furniture, admitted BY PATH only, never by frame shape.
  #   epoch-registrar -- the 20,736 B / 9-block possibly-lost record whose
  #     frames cross crossbeam_epoch::collector::Collector::register: the
  #     rayon workers thread-local epoch registration, a by-design
  #     process-lifetime cache (loss record 3,652 of 4,593).
  #   once-cell-probe-cache -- the 3,276,808 B / 1-block possibly-lost
  #     record whose frames cross once_cell::imp::initialize_or_wait AND
  #     wrap__msffi_column_major_probe: the FFI probe bridge lazily
  #     initialised static, a by-design one-time cache (loss record
  #     4,591 of 4,593). The conjunction is the signature; neither word
  #     alone admits anything.
  #   wrapper-epilogue-CJU (issue #36 adjudication, 2026-10-22) -- the ten
  #     counted hits of one conditional-jump context inside the
  #     extendr-0.9.0 GENERATED closure of wrap__ms_compare_null_rust (the
  #     kernel is in no frame). Dissection of the shipped .so: the tested
  #     branch is the epilogue tbnz at closure+0x22F0 (vaddr 0xE0140 in both
  #     witnesses, base-independent), reading bit 0 of a never-written owns
  #     flag at [sp,#140] of the closure's own frame -- created by the
  #     sub sp,sp,#0x350 stack allocation at closure+0x24 (vaddr 0xDDE74)
  #     that the origin report names. The decision only picks the vector's
  #     __rust_dealloc path; with the flag's residue the observed path frees
  #     correctly (no invalid free, no leak, 167/167 tests across both
  #     witnesses, error count pinned at ten). Upstream: the crate's latest
  #     release is the pinned 0.9.0, so no adopted fix exists; the
  #     suppression file stays empty -- the census, not the fork's provably
  #     dead matcher, owns the adjudication. The four locks: captured context
  #     with wrapper-name AND closure AND stack-origin conjunctions,
  #     surplus == 10, contexts == records + 1.
  rc=0
  out=$(awk -v roster_n="$roster_n" \
    -v TOOL_RE='^(/usr)?/bin/(sh|sed|uname|rm|which|grep|cat|cut|dirname|basename|expr|mktemp)( .*|$)' \
    -v CJU_HITS_PIN=10 '
    function noslash(s) { gsub(/,/, "", s); return s + 0 }
    function speak(p) { if (!(p in say)) { say[p] = 1; npids++ } }
    /^==[0-9]+== +(at|by) / {
      if (pid in pend) { k = pid SUBSEP pend[pid]
        frames[k] = (k in frames ? frames[k] "\037" : "") $0 }
      else if (cjuopen[pid] == 1) { cjuf[pid] = (pid in cjuf ? cjuf[pid] "\037" : "") $0 }
      next
    }
    /^==[0-9]+==/ {
      pid = substr($0, 3, index(substr($0, 3), "==") - 1)
      if ($0 ~ /Conditional jump or move depends on uninitialised value/) {
        speak(pid); cjud[pid] = 1; cjuopen[pid] = 1
        cjuf[pid] = (pid in cjuf ? cjuf[pid] "\037" : "") $0
      }
      else if ($0 ~ /Uninitialised value was created by a stack allocation/) {
        if (cjuopen[pid] == 1) { cjuf[pid] = cjuf[pid] "\037" $0 }
      }
      else if ($0 ~ /HEAP SUMMARY:/) { cjuopen[pid] = 0; speak(pid); heap[pid] = 1 }
      else if ($0 ~ /ERROR SUMMARY:/) {
        cjuopen[pid] = 0; speak(pid); errseen[pid] = 1
        if (match($0, /ERROR SUMMARY: [0-9]+/)) { e = noslash(substr($0, RSTART + 15, RLENGTH - 15)) } else { e = 0 }
        ecount[pid] = e; sum_err += e
        if (match($0, /from [0-9]+/)) { ccount[pid] = noslash(substr($0, RSTART + 5, RLENGTH - 5)) }
        if (match($0, /\(suppressed: [0-9]+/)) { supp += noslash(substr($0, RSTART + 13, RLENGTH - 13)) }
      }
      else if ($0 ~ /All heap blocks were freed/) { cjuopen[pid] = 0; speak(pid); freed[pid] = 1 }
      else if ($0 ~ /definitely lost: [0-9]/) { cjuopen[pid] = 0; speak(pid); dlseen[pid] = 1 }
      else if (index($0, "Command: ") > 0) {
        c = substr($0, index($0, "Command: ") + 9)
        cmd[pid] = (pid in cmd ? cmd[pid] "\037" : "") c
      }
      else if (match($0, / bytes in [0-9,]+ blocks are (definitely|indirectly|possibly) lost in loss record /)) {
        cjuopen[pid] = 0
        speak(pid); pend[pid] = ++nrec[pid]; sum_rec++
        m = substr($0, RSTART, RLENGTH)
        k = (m ~ /definitely/) ? "definitely" : ((m ~ /indirectly/) ? "indirectly" : "possibly")
        key = pid SUBSEP pend[pid]; head[key] = $0; kind[key] = k
        if (k == "definitely") { dl[pid] += noslash($2); dl_total += noslash($2) }
      }
      else { cjuopen[pid] = 0 }
      next
    }
    /^VG_TESTFILE [^ ]+ PASS [0-9]+ [0-9]+$/ { files++; tests += $4 }
    END {
      if (supp > 0) { printf "NO SELF-DECEPTION: the reports claim %d suppressed violations, but this fork suppressions matcher is provably dead -- a count from a dead engine launders reports\n", supp; exit 9 }
      for (pid in dl) if (dl[pid] > 0) { printf "HARD ZERO: %d bytes definitely lost in pid %s (Command: %s) -- not one byte may be definitely lost, whoever the owner\n", dl[pid], pid, cmd[pid]; exit 2 }
      for (pid in say) {
        missing = ""
        if (!(pid in errseen)) { missing = missing ", ERROR SUMMARY" }
        if (!(pid in heap)) { missing = missing ", HEAP SUMMARY" }
        if (missing != "") { printf "INCOMPLETE: pid %s (Command: %s) opened a report but never spoke%s -- he who opens his mouth must finish (a child that dies mid-report is the death of the tool, not of the guest)\n", pid, cmd[pid], missing; exit 5 }
        if (nrec[pid] > 0 && !(pid in dlseen)) { printf "INCOMPLETE: pid %s (Command: %s) reported %d loss records but no per-class loss summary -- the classes cannot back the records\n", pid, cmd[pid], nrec[pid]; exit 5 }
      }
      for (pid in ecount) {
        recs = (pid in nrec ? nrec[pid] : 0)
        surplus = ecount[pid] - recs
        if (surplus <= 0) continue
        owned = (cjud[pid] == 1 && (pid in cjuf) &&
          cjuf[pid] ~ /wrap__ms_compare_null_rust/ &&
          cjuf[pid] ~ /closure/ &&
          cjuf[pid] ~ /Uninitialised value was created by a stack allocation/ &&
          surplus == CJU_HITS_PIN &&
          ccount[pid] == recs + 1)
        if (owned) { allow_cju++; cju_hits += surplus; continue }
        unadjudicated++
        printf "UNADJUDICATED: pid %s (Command: %s) -- %d counted error(s) beyond the %d adjudicated loss record(s) with no owning context\n", pid, cmd[pid], surplus, recs
        if (pid in cjuf) { t = cjuf[pid]; gsub(/\037/, "\n  ", t); printf "  %s\n", t }
        else printf "  (no error context was captured for this pid -- an arithmetic surplus alone never adjudicates)\n"
      }
      for (pid in nrec) {
        tool = 0; n = split(cmd[pid], segs, "\037")
        for (i = 1; i <= n; i++) { if (segs[i] ~ TOOL_RE) { tool = 1 } }
        for (r = 1; r <= nrec[pid]; r++) {
          key = pid SUBSEP r; f = (key in frames ? frames[key] : ""); h = head[key]
          if (tool) { allow_tool++; continue }
          if (f ~ /crossbeam_epoch::collector::Collector::register/) { allow_cache++; sig_epoch++; continue }
          if (f ~ /once_cell::imp::initialize_or_wait/ && f ~ /wrap__msffi_column_major_probe/) { allow_cache++; sig_once++; continue }
          unadjudicated++
          printf "UNADJUDICATED: pid %s (Command: %s)\n  %s\n", pid, cmd[pid], h
          t = f; gsub(/\037/, "\n  ", t); printf "  %s\n", t
        }
      }
      if (unadjudicated > 0) { exit 4 }
      if (sum_err != sum_rec + cju_hits) { printf "UNACCOUNTED: ERROR SUMMARY total %d vs %d loss-record headers + %d adjudicated CJU hits -- every counted error must be backed by an adjudicated record or an adjudicated context; an excess is an error class with no owner, a deficit is a report that counted what it did not print\n", sum_err, sum_rec, cju_hits; exit 3 }
      if (files + 0 != roster_n + 0) { printf "EXECUTED-WORK MISMATCH: %d roster file(s) attested PASS of %d nominated -- an arm that runs no files gates nothing (the D1 lesson)\n", files, roster_n; exit 6 }
      if (tests + 0 < 1) { printf "ZERO WORK: no attested test passed -- an arm that ran nothing gates nothing (the D1 lesson)\n"; exit 7 }
      printf "CENSUS pids=%d err=%d rec=%d dlbytes=%d tool=%d cache=%d epoch=%d onc=%d cju=%d hits=%d files=%d tests=%d\n", \
        npids + 0, sum_err + 0, sum_rec + 0, dl_total + 0, allow_tool + 0, allow_cache + 0, sig_epoch + 0, sig_once + 0, allow_cju + 0, cju_hits + 0, files + 0, tests + 0
    }
  ' "$log" 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf '%s\n' "$out"
    return 1          # the battery reads the refusal; the leg path dies below
  fi
  c_pids=$(printf '%s\n' "$out" | sed -nE 's/^CENSUS pids=([0-9]+) .*/\1/p')
  c_err=$(printf '%s\n' "$out" | sed -nE 's/.* err=([0-9]+) .*/\1/p')
  c_rec=$(printf '%s\n' "$out" | sed -nE 's/.* rec=([0-9]+) .*/\1/p')
  c_tool=$(printf '%s\n' "$out" | sed -nE 's/.* tool=([0-9]+) .*/\1/p')
  c_epoch=$(printf '%s\n' "$out" | sed -nE 's/.* epoch=([0-9]+) .*/\1/p')
  c_onc=$(printf '%s\n' "$out" | sed -nE 's/.* onc=([0-9]+) .*/\1/p')
  c_cju=$(printf '%s\n' "$out" | sed -nE 's/.* cju=([0-9]+) .*/\1/p')
  c_hits=$(printf '%s\n' "$out" | sed -nE 's/.* hits=([0-9]+) .*/\1/p')
  c_files=$(printf '%s\n' "$out" | sed -nE 's/.* files=([0-9]+) .*/\1/p')
  c_tests=$(printf '%s\n' "$out" | sed -nE 's/.* tests=([0-9]+)$/ \1/p' | tr -d ' ')
  [ -n "$c_pids" ] && [ -n "$c_err" ] && [ -n "$c_tests" ] \
    || die "the census machine line is malformed: [$out]"
  printf '%s\n' "$out"    # the machine line is evidence, spoken
  note "report census: $c_err error(s) fully adjudicated ambient (tool-swarm $c_tool, static caches epoch-registrar $c_epoch + once-cell-probe $c_onc, wrapper-epilogue CJU $c_cju context(s)/$c_hits hit(s) per the issue-#36 adjudication), $c_rec record headers backing the count, definitely-lost 0 bytes, roster $c_files/$roster_n files, $c_tests test(s) passed over $c_pids attested pids"
}

build_canary() {
  cargo build --quiet --manifest-path "$canary_manifest" \
    --target-dir "$canary_work" >"$log_dir/canary-build.log" 2>&1 \
    || die "the valgrind canary failed to build (log $log_dir/canary-build.log)"
  canary_bin=$(find "$canary_work/debug" -maxdepth 1 \
    -name msuiter-valgrind-canary -type f | head -1)
  [ -n "$canary_bin" ] || die "the canary binary was not found after the build"
}

run_canary() { # run_canary <log> <valgrind:yes|no> <class>
  log=$1; instrumented=$2; class=$3
  if [ "$instrumented" = yes ]; then
    run_valgrind "$log" "$canary_bin" trip "$class"
  else
    if "$canary_bin" trip "$class" > "$log" 2>&1; then vg_rc=0; else vg_rc=$?; fi
  fi
}

trip_signal() { # the report text each class is known to produce -- byte-true vs
  # the captured reports (the renamed fork's violation heading carries no "bytes")
  case $1 in
    heap) printf '%s\n' 'Invalid read of size [0-9]+' ;;
    leak) printf '%s\n' 'definitely lost' ;;
  esac
}

assert_trip_reported() { # <class> -- the instrumented trip must REPORT and COMPLETE
  class=$1
  run_canary "$log_dir/canary-trip-$class.log" yes "$class"
  grep -qE '^(==[0-9]+== )?ERROR SUMMARY:' "$log_dir/canary-trip-$class.log" \
    || die "TOOL ATTESTATION: the instrumented $class trip committed its violation but memcheck never emitted its ERROR SUMMARY (rc=$vg_rc) -- the tool cannot complete its lifecycle on this runner; the canaries precede the roster precisely to surface this here (log $log_dir/canary-trip-$class.log)"
  trip_count=$(sed -nE 's/^(==[0-9]+== )?ERROR SUMMARY: ([0-9]+) error.*/\2/p' "$log_dir/canary-trip-$class.log" | tail -1)
  [ -n "$trip_count" ] && [ "$trip_count" -ge 1 ] \
    || die "TOOL ATTESTATION: the instrumented $class trip committed its violation but memcheck's own summary counts $trip_count errors -- content words without a counted error are a contradiction, not a report (log $log_dir/canary-trip-$class.log)"
  if grep -Eq "$(trip_signal "$class")" "$log_dir/canary-trip-$class.log"; then
    note "control: the instrumented $class trip REPORTED its violation under a completed report (memcheck is live)"
  else
    die "LOUDNESS LAW: the $class canary committed its violation and memcheck stayed \
silent -- the instrumentation never ran (log $log_dir/canary-trip-$class.log)"
  fi
}

assert_trip_silent() { # <class> -- an UNinstrumented trip must stay SILENT
  class=$1
  run_canary "$log_dir/canary-uninstrumented-$class.log" no "$class"
  if grep -E 'Invalid read|definitely lost' \
      "$log_dir/canary-uninstrumented-$class.log" >/dev/null; then
    die "discrimination control broken: an UNinstrumented $class canary produced a \
memcheck-style report -- the leg could not tell a live tool from a dead one"
  fi
  note "control: the uninstrumented $class trip stayed silent (live vs dead discriminates)"
}

assert_clean_silent() {
  run_valgrind "$log_dir/canary-clean.log" "$canary_bin" clean
  if grep -Eq '^(==[0-9]+== )?(ERROR SUMMARY: [1-9]|definitely lost: [1-9])' "$log_dir/canary-clean.log"; then
    die "the CLEAN canary (no violation) produced a memcheck report -- the detection \
is not discriminating (log $log_dir/canary-clean.log)"
  fi
  note "control: the clean canary stayed silent under memcheck"
}

census_fixture() { # <name> <pass|die> <needle> -- the real census over a synthetic forest
  name=$1; expect=$2; needle=$3
  rc=0
  out=$(valgrind_report_census "$log_dir/fixtures/$name.log" 2>&1) || rc=$?
  case "$expect:$rc" in pass:0|die:1) ;; *) die "FIXTURE $name: expected $expect, got rc=$rc -- [$out]" ;; esac
  printf '%s\n' "$out" | grep -qF "$needle" \
    || die "FIXTURE $name: the census fired, but not for the crime under test (needle [$needle] absent) -- [$out]"
  note "census fixture $name: $expect as designed [$needle]"
}

write_fixture() { # write_fixture <name> -- heredoc on stdin: one synthetic report forest
  cat > "$log_dir/fixtures/$1.log"
}

run_census_fixtures() { # the census IS the gate (the forks suppression matcher is
  # provably dead), so its blindness classes are regression-tested as the
  # canaries test the tool. Each fixture is one documented way a report
  # forest lies; the needle is the law that must answer it.
  mkdir -p "$log_dir/fixtures"
  write_fixture clean-single <<'EOF'
VG_TESTFILE fixture PASS 1 0
==7100== Command: /usr/bin/uname -m
==7100== HEAP SUMMARY:
==7100==    in use at exit: 0 bytes in 0 blocks
==7100== All heap blocks were freed -- no leaks are possible
==7100== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)
EOF
  write_fixture tool-swarm <<'EOF'
VG_TESTFILE fixture PASS 1 0
==7101== Command: /usr/bin/sed -e s/[^=]*=//
==7101== 0 bytes in 1 blocks are definitely lost in loss record 1 of 1
==7101==    at 0x4865058: malloc (in /usr/libexec/valgrind/vgpreload_memcheck-arm64-linux.so)
==7101==    by 0x114F0B: ??? (in /usr/bin/sed)
==7101== HEAP SUMMARY:
==7101==    in use at exit: 0 bytes in 0 blocks
==7101== definitely lost: 0 bytes in 1 blocks
==7101==      possibly lost: 0 bytes in 0 blocks
==7101==    indirectly lost: 0 bytes in 0 blocks
==7101== ERROR SUMMARY: 1 errors from 1 contexts (suppressed: 0 from 0)
EOF
  write_fixture guest-caches <<'EOF'
VG_TESTFILE fixture PASS 1 0
==7102== Command: /usr/bin/Rscript fixture-driver
==7102== 20,736 bytes in 9 blocks are possibly lost in loss record 3,652 of 4,593
==7102==    by 0xACBE03: crossbeam_epoch::collector::Collector::register (in /tmp/tmp.X/msuiter/libs/msuiter.so)
==7102== 3,276,808 bytes in 1 blocks are possibly lost in loss record 4,591 of 4,593
==7102==    by 0xAA22DDF: once_cell::imp::initialize_or_wait (in /tmp/tmp.X/msuiter/libs/msuiter.so)
==7102==    by 0xABF27: wrap__msffi_column_major_probe (in /tmp/tmp.X/msuiter/libs/msuiter.so)
==7102== HEAP SUMMARY:
==7102==    in use at exit: 0 bytes in 0 blocks
==7102== definitely lost: 0 bytes in 0 blocks
==7102==      possibly lost: 3,297,544 bytes in 10 blocks
==7102==    indirectly lost: 0 bytes in 0 blocks
==7102== ERROR SUMMARY: 2 errors from 2 contexts (suppressed: 0 from 0)
EOF
  # The repro6 mask: the outer wrapper completes last attesting its own
  # zeros; a tail -1 read of ERROR SUMMARY calls this forest clean.
  write_fixture wrapper-mask <<'EOF'
VG_TESTFILE fixture PASS 1 0
==7201== Command: /usr/local/lib/R/bin/R --no-save --no-restore --file=/tmp/valgrind-sentry-x
==7201== 128 bytes in 1 blocks are possibly lost in loss record 1 of 1
==7201==    by 0x111111: guest_fn (in /usr/lib/R/library/msuiter/libs/msuiter.so)
==7201== HEAP SUMMARY:
==7201==    in use at exit: 0 bytes in 0 blocks
==7201== definitely lost: 0 bytes in 0 blocks
==7201==      possibly lost: 128 bytes in 1 blocks
==7201==    indirectly lost: 0 bytes in 0 blocks
==7201== ERROR SUMMARY: 1 errors from 1 contexts (suppressed: 0 from 0)
==7202== Command: /usr/bin/env wrapper
==7202== HEAP SUMMARY:
==7202==    in use at exit: 0 bytes in 0 blocks
==7202== All heap blocks were freed -- no leaks are possible
==7202== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)
EOF
  write_fixture unknown-owner <<'EOF'
VG_TESTFILE fixture PASS 1 0
==7203== Command: /usr/bin/weirdthing --do-work
==7203== 512 bytes in 1 blocks are possibly lost in loss record 1 of 1
==7203==    by 0x222222: suspicious_fn (in /usr/lib/nowhere.so)
==7203== HEAP SUMMARY:
==7203==    in use at exit: 0 bytes in 0 blocks
==7203== definitely lost: 0 bytes in 0 blocks
==7203==      possibly lost: 512 bytes in 1 blocks
==7203==    indirectly lost: 0 bytes in 0 blocks
==7203== ERROR SUMMARY: 1 errors from 1 contexts (suppressed: 0 from 0)
EOF
  write_fixture definitely-lost <<'EOF'
VG_TESTFILE fixture PASS 1 0
==7204== Command: /usr/local/lib/R/bin/R --no-save --file=/tmp/valgrind-sentry-y
==7204== 128 bytes in 1 blocks are definitely lost in loss record 1 of 1
==7204==    by 0x333333: doomed_fn (in /usr/lib/R/library/msuiter/libs/msuiter.so)
==7204== HEAP SUMMARY:
==7204==    in use at exit: 0 bytes in 0 blocks
==7204== definitely lost: 128 bytes in 1 blocks
==7204==      possibly lost: 0 bytes in 0 blocks
==7204==    indirectly lost: 0 bytes in 0 blocks
==7204== ERROR SUMMARY: 1 errors from 1 contexts (suppressed: 0 from 0)
EOF
  # A child that dies mid-report: it opened with a loss record and never
  # reached its summaries -- the tools death, which must never read as a
  # partial-clean over the survivors. The companion block carries the log
  # past the whole-log LOUDNESS preflight so the per-pid law is what fires.
  write_fixture silent-child <<'EOF'
VG_TESTFILE fixture PASS 1 0
==7205== Command: /usr/bin/env half-a-child
==7205== 256 bytes in 1 blocks are possibly lost in loss record 1 of 1
==7205==    by 0x444444: some_fn (in /usr/lib/nowhere.so)
==7206== Command: /usr/bin/uname -m
==7206== HEAP SUMMARY:
==7206==    in use at exit: 0 bytes in 0 blocks
==7206== All heap blocks were freed -- no leaks are possible
==7206== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)
EOF
  # A report that counted what it did not print: two errors claimed, one
  # record headable -- the gap is an error class no signature owns.
  write_fixture unaccounted <<'EOF'
VG_TESTFILE fixture PASS 1 0
==7207== Command: /usr/bin/Rscript fixture-driver
==7207== 20,736 bytes in 9 blocks are possibly lost in loss record 1 of 2
==7207==    by 0xACBE03: crossbeam_epoch::collector::Collector::register (in /tmp/tmp.X/msuiter/libs/msuiter.so)
==7207== HEAP SUMMARY:
==7207==    in use at exit: 0 bytes in 0 blocks
==7207== definitely lost: 0 bytes in 0 blocks
==7207==      possibly lost: 20,736 bytes in 9 blocks
==7207==    indirectly lost: 0 bytes in 0 blocks
==7207== ERROR SUMMARY: 2 errors from 2 contexts (suppressed: 0 from 0)
EOF
  # The dead suppression engine cannot guard anything; a report leaning on
  # it is laundering itself.
  write_fixture self-deception <<'EOF'
VG_TESTFILE fixture PASS 1 0
==7208== Command: /usr/bin/Rscript fixture-driver
==7208== HEAP SUMMARY:
==7208==    in use at exit: 0 bytes in 0 blocks
==7208== All heap blocks were freed -- no leaks are possible
==7208== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 3 from 3)
EOF
  # The issue-#36 context: the extendr-0.9.0 GENERATED closure of
  # wrap__ms_compare_null_rust reports one CJU whose tested word is a
  # never-written stack slot of the wrapper frame (origin: stack allocation
  # inside that same closure). Ten counted hits, one context, two adjudicated
  # records -- byte-true to the 2026-10-22 instrumented-roster capture
  # (leg mode, test-ms-compare.R PASS 167) and to the isolated reproduction
  # (same branch at closure+0x22F0 in both witnesses). Adjudication requires
  # four locks -- captured CJU context carrying the wrapper-name, closure and
  # stack-origin conjunctions; surplus == the witnessed 10; contexts ==
  # records + 1 -- so the guest pid's block below is verbatim evidence.
  write_fixture cju-adjudicated <<'EOF'
VG_TESTFILE fixture PASS 1 0
==7301== Command: Rscript /tmp/valgrind-sentry-DF70TY tests/testthat/test-ms-compare.R
==7301== Command: /usr/local/lib/R/bin/R --no-echo --no-restore --file=/tmp/valgrind-sentry-DF70TY --args tests/testthat/test-ms-compare.R
==7301== Conditional jump or move depends on uninitialised value(s)
==7301==    at 0x259B0140: msuiter::wrap__ms_compare_null_rust::{{closure}} (in /tmp/tmp.ejvrNu5h2t/msuiter/libs/msuiter.so)
==7301==    by 0x259ADC9B: wrap__ms_compare_null_rust (in /tmp/tmp.ejvrNu5h2t/msuiter/libs/msuiter.so)
==7301==    by 0x49910A3: R_doDotCall (dotcode.c:884)
==7301==  Uninitialised value was created by a stack allocation
==7301==    at 0x259ADE74: msuiter::wrap__ms_compare_null_rust::{{closure}} (in /tmp/tmp.ejvrNu5h2t/msuiter/libs/msuiter.so)
==7301==
==7301== HEAP SUMMARY:
==7301==    in use at exit: 120,435,674 bytes in 24,640 blocks
==7301==
==7301== 20,736 bytes in 9 blocks are possibly lost in loss record 4,043 of 4,981
==7301==    by 0x259CBE03: crossbeam_epoch::collector::Collector::register (in /tmp/tmp.ejvrNu5h2t/msuiter/libs/msuiter.so)
==7301==
==7301== 3,276,808 bytes in 1 blocks are possibly lost in loss record 4,979 of 4,981
==7301==    by 0x25A22DDF: once_cell::imp::initialize_or_wait (in /tmp/tmp.ejvrNu5h2t/msuiter/libs/msuiter.so)
==7301==    by 0x2599BF27: wrap__msffi_column_major_probe (in /tmp/tmp.ejvrNu5h2t/msuiter/libs/msuiter.so)
==7301==
==7301== LEAK SUMMARY:
==7301==    definitely lost: 0 bytes in 0 blocks
==7301==    indirectly lost: 0 bytes in 0 blocks
==7301==      possibly lost: 3,297,544 bytes in 10 blocks
==7301==    still reachable: 117,138,130 bytes in 24,630 blocks
==7301== ERROR SUMMARY: 12 errors from 3 contexts (suppressed: 0 from 0)
EOF
  # The conjunction binds: a CJU whose frames name a different owner is no
  # one's property and may not ride the allowlist's coattails.
  write_fixture cju-wrong-owner <<'EOF'
VG_TESTFILE fixture PASS 1 0
==7302== Command: /usr/bin/Rscript fixture-driver
==7302== Conditional jump or move depends on uninitialised value(s)
==7302==    at 0x259B0140: msuiter::compare_null_kernel::{closure} (in /tmp/tmp.X/msuiter/libs/msuiter.so)
==7302==  Uninitialised value was created by a stack allocation
==7302==    at 0x259ADE74: msuiter::compare_null_kernel::{closure} (in /tmp/tmp.X/msuiter/libs/msuiter.so)
==7302==
==7302== HEAP SUMMARY:
==7302==    in use at exit: 0 bytes in 0 blocks
==7302== All heap blocks were freed -- no leaks are possible
==7302== ERROR SUMMARY: 10 errors from 1 contexts (suppressed: 0 from 0)
EOF
  # The count is pinned to the witnessed ten: a drift is new behaviour, not
  # a courtesy.
  write_fixture cju-count-drift <<'EOF'
VG_TESTFILE fixture PASS 1 0
==7303== Command: /usr/bin/Rscript fixture-driver
==7303== Conditional jump or move depends on uninitialised value(s)
==7303==    at 0x259B0140: msuiter::wrap__ms_compare_null_rust::{{closure}} (in /tmp/tmp.X/msuiter/libs/msuiter.so)
==7303==  Uninitialised value was created by a stack allocation
==7303==    at 0x259ADE74: msuiter::wrap__ms_compare_null_rust::{{closure}} (in /tmp/tmp.X/msuiter/libs/msuiter.so)
==7303==
==7303== HEAP SUMMARY:
==7303==    in use at exit: 0 bytes in 0 blocks
==7303== All heap blocks were freed -- no leaks are possible
==7303== ERROR SUMMARY: 11 errors from 1 contexts (suppressed: 0 from 0)
EOF
  # One context beyond the records plus the one adjudicated CJU is a hidden
  # second error class wearing the allowlist's coat.
  write_fixture cju-context-drift <<'EOF'
VG_TESTFILE fixture PASS 1 0
==7304== Command: /usr/bin/Rscript fixture-driver
==7304== Conditional jump or move depends on uninitialised value(s)
==7304==    at 0x259B0140: msuiter::wrap__ms_compare_null_rust::{{closure}} (in /tmp/tmp.X/msuiter/libs/msuiter.so)
==7304==  Uninitialised value was created by a stack allocation
==7304==    at 0x259ADE74: msuiter::wrap__ms_compare_null_rust::{{closure}} (in /tmp/tmp.X/msuiter/libs/msuiter.so)
==7304==
==7304== HEAP SUMMARY:
==7304==    in use at exit: 0 bytes in 0 blocks
==7304== All heap blocks were freed -- no leaks are possible
==7304== ERROR SUMMARY: 10 errors from 2 contexts (suppressed: 0 from 0)
EOF
  # A surplus that cites no captured context at all may never be laundered
  # through the allowlist by the ERROR SUMMARY's arithmetic alone.
  write_fixture cju-no-context <<'EOF'
VG_TESTFILE fixture PASS 1 0
==7305== Command: /usr/bin/Rscript fixture-driver
==7305== HEAP SUMMARY:
==7305==    in use at exit: 0 bytes in 0 blocks
==7305== All heap blocks were freed -- no leaks are possible
==7305== ERROR SUMMARY: 10 errors from 0 contexts (suppressed: 0 from 0)
EOF
  roster_n=1
  census_fixture clean-single pass 'pids=1 err=0 rec=0 dlbytes=0 tool=0 cache=0'
  census_fixture tool-swarm pass 'err=1 rec=1 dlbytes=0 tool=1 cache=0'
  census_fixture guest-caches pass 'err=2 rec=2 dlbytes=0 tool=0 cache=2 epoch=1 onc=1'
  census_fixture wrapper-mask die 'UNADJUDICATED'
  census_fixture unknown-owner die 'UNADJUDICATED'
  census_fixture definitely-lost die 'HARD ZERO'
  census_fixture silent-child die 'INCOMPLETE'
  # the surplus law hardened 2026-10-22: a counted error with no owning
  # context is refused per-pid (UNADJUDICATED names it) before the global
  # balance speaks -- the global UNACCOUNTED keeper remains as the last bell
  census_fixture unaccounted die 'UNADJUDICATED'
  census_fixture self-deception die 'NO SELF-DECEPTION'
  # needle = the byte-true machine line as witnessed in the sealed run
  # (grep -F: a law must name contiguous bytes, never a schema imagined).
  census_fixture cju-adjudicated pass 'CENSUS pids=1 err=12 rec=2 dlbytes=0 tool=0 cache=2 epoch=1 onc=1 cju=1 hits=10 files=1 tests=1'
  census_fixture cju-wrong-owner die 'UNADJUDICATED'
  census_fixture cju-count-drift die 'UNADJUDICATED'
  census_fixture cju-context-drift die 'UNADJUDICATED'
  census_fixture cju-no-context die 'UNADJUDICATED'
}

mkdir -p "$log_dir"
probe_valgrind
resolve_suppressions
note "suppressations in force: $suppressions_kind${suppressions:+ (file $suppressions)}"

case "$mode" in
  selftest)
    run_census_fixtures
    build_canary
    assert_trip_silent heap
    assert_trip_silent leak
    assert_trip_reported heap
    assert_trip_reported leak
    assert_clean_silent
    note "SELFTEST OK: the census adjudicates a lying report forest, and the harness distinguishes a live memcheck from a dead one"
    ;;
  leg)
    # Census-law attestation before anything else: a regression in the
    # adjudication layer must fail in seconds, not after the roster burn.
    run_census_fixtures
    # Tool attestation precedes guest attestation (2026-10-21 forensics):
    # the canary battery must prove memcheck completes its lifecycle on
    # this runner before a roster census is allowed to adjudicate it.
    build_canary
    assert_trip_silent heap
    assert_trip_silent leak
    assert_trip_reported heap
    assert_trip_reported leak
    assert_clean_silent
    install_package
    build_driver
    cd "$root"
    roster_n=0
    for _ in $roster; do roster_n=$((roster_n + 1)); done
    roster_files=$(printf 'tests/testthat/test-%s.R;' $roster); roster_files=${roster_files%;}
    note "running the native-sentry roster [$roster] under memcheck"
    suite_log=$log_dir/valgrind-suite.log
    run_valgrind "$suite_log" Rscript "$driver" "$roster_files"
    valgrind_report_census "$suite_log" \
      || die "the report census refused the suite log -- the adjudication layer found an unowned, incomplete or unaccounted block (lines above)"
    # The census is the authority; the exit code only corroborates it. Which
    # pids feed --error-exitcode in the renamed fork (root only, or every
    # tracked child) is a property of the tool -- under trace-children both
    # witnesses are lawful whenever every counted error is adjudicated
    # ambient, so the exit code may only refuse: an error code with nothing
    # counted is laundering, and an unanticipated code is death.
    case "$vg_rc" in
      0)
        [ "$c_err" -eq 0 ] \
          && note "exit-code corroboration: rc=0 with a fully clean census (double attestation)" \
          || note "exit-code corroboration: rc=0 with $c_err adjudicated ambient error(s) -- the fork counts the root pids errors only" ;;
      "$vg_error_rc")
        [ "$c_err" -gt 0 ] \
          || die "memcheck exited on its error code ($vg_error_rc) although every attested block reported zero errors -- the exit code and the reports disagree (log $suite_log)"
        note "exit-code corroboration: rc=$vg_error_rc with $c_err adjudicated ambient error(s) -- the fork counts every tracked pid" ;;
      *)
        die "the roster run exited rc=$vg_rc with a completed census -- neither clean nor the error code memcheck carries for counted errors (log $suite_log)" ;;
    esac
    note "LEG GREEN: memcheck completed and reported (canary-attested), the roster ran, the census adjudicated every block, the canaries discriminated live from dead"
    ;;
esac
