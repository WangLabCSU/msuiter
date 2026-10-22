# Valgrind leg, child instrumentation: the execve escape, the last-writer
# census race, and the death of the suppression engine (PR #45)

Date: 2026-10-21. Lane: valgrind deep-check remediation (issue #32
successor class), branch `feat/valgrind-trace-children`, worktree
`msuiter-wt/vgfix`. Harness: `tools/deep-checks/run_valgrind_leg.sh`.
Gate: `tools/ci-selfcheck.py` (census-law block). Truth capture:
`/tmp/vgart5/repro6/check-valgrind/valgrind-suite.log` (host-side shrine,
cited only; committed evidence is read-only per the evidence law).

## 1. The blind window, in layers (what kept being false)

The leg believed four things that were false, each discovered only after
the previous was fixed -- the epistemic lesson is that a gate whose inputs
are single samples of an attacker-racy can be green indefinitely:

1. *pid-prefixed census blindness* (#42): every line the tool authors is
   `==pid== ` prefixed; unprefixed patterns matched nothing that mattered.
2. *uncounted attestation* (#43): presence-of-words was read as evidence
   of execution; the census became counted (files, tests, totals).
3. *the execve escape* (this PR's namesake): memcheck's `--trace-children`
   defaults to `no`, so the guest that survives through execve -- every R
   session, because `Rscript` is a shell wrapper that execve's the real
   `R` -- ran NATIVE while the harness watched the wrapper. The 413-test
   roster completed the "instrumented" leg in 4 seconds with rc=0. That
   number (413 tests, 4 s) is the confession.
4. *the last-writer census race* (found by enabling 3): with
   `--trace-children=yes` the log is a forest of per-pid report blocks
   written in completion order. The census read `ERROR SUMMARY` through
   `tail -1` -- the LAST writer wins, and the last writer is typically the
   outer wrapper attesting its own zeros while the guest attested errors.
   The repro6 capture proves the shape (pid 1838 carried 2 errors; the
   tail -1 read surfaced whatever finished last).

## 2. The suppression engine is dead (control probe, verbatim)

The vendored-suppressions mechanism (#39) presumes matching. Probed
2026-10-21 against the renamed fork:

* a textbook `Invalid read of size 8` violation at `fun:main` is
  suppressed by ZERO entries under every accepted spelling (`Memcheck:`,
  `Valgrind:`, fun/obj frames, file paths);
* the `Memcheck:` prefix is FATAL: `unknown tool suppression type` --
  and the pre-#45 `valgrind.supp` header TAUGHT that illegal prefix;
* the bogus prefix `Valgrind:` parses and entry types are never
  validated: `Valgrind: QQQQQ` is accepted silently.

Conclusion: on this fork, suppressions files cannot guard anything. They
were the third vacuous-green family found in this leg's stack (after the
uncounted census and the uninstrumented guest). Ownership adjudication
therefore moved UP into the census, where allowances are code, cite
evidence, and are fixture-tested -- and the census refuses any report
that claims `(suppressed: N>0)`, so leaning on a dead engine is loud
(NO SELF-DECEPTION law).

## 3. The census law this PR installs

`valgrind_report_census` walks EVERY block; laws in adjudication order,
each pinned by a synthetic fixture in `run_census_fixtures` (9 fixtures,
6 firing + 3 passing, name-pinned by the selfcheck):

1. NO SELF-DECEPTION -- nonzero `(suppressed:)` is death (fixture
   `self-deception`).
2. HARD ZERO -- one definitely-lost byte kills the leg, whoever the owner
   (`definitely-lost`).
3. HE WHO OPENS HIS MOUTH MUST FINISH -- a pid speaking any part of a
   report must speak the whole of it; a child that dies mid-report is
   the death of the tool, not of the guest (`silent-child`).
4. OWNERSHIP ADJUDICATION -- every loss record is allowed only by a
   reviewed, evidence-cited signature; anything else dies naming pid,
   Command and record (`unknown-owner`, `wrapper-mask`).
5. FULL ACCOUNTING -- `sum(ERROR SUMMARY) == count(record headers)`;
   every counted error must be an owned record (`unaccounted`).
6. EXECUTED-WORK -- roster files/tests census (the D1 lesson), summed.

The allowlists, byte-true against the repro6 capture:

* TOOL SWARM (by path only, never by frame shape): coreutils the R
  build/test machinery execs -- `/bin/sh -c` wrappers, sed, uname, rm,
  which, ... The capture's five tool records (two `sed -e` pids) prove
  the class.
* EPOCH-REGISTRAR (frame signature): the 20,736 B / 9-block possibly-lost
  record crossing `crossbeam_epoch::collector::Collector::register` --
  the rayon worker thread-local epoch registration, by-design
  process-lifetime cache (loss record 3,652 of 4,593).
* ONCE-CELL-PROBE-CACHE (conjunction, neither word alone): the
  3,276,808 B / 1-block record crossing
  `once_cell::imp::initialize_or_wait` AND `wrap__msffi_column_major_probe`
  -- the FFI probe bridge's lazily-initialised static (loss record
  4,591 of 4,593).

The acid test: the census, extracted and run under the container's awk
over the repro6 truth log verbatim, attests
`CENSUS pids=11 err=7 rec=7 dlbytes=0 tool=5 cache=2 epoch=1 onc=1
files=3 tests=413` -- every error owned, every number doubled.

## 4. The exit-code corroboration is demoted, not deleted

The census is the authority; `vg_rc` may only refuse. Under
child-instrumentation the fork's `--error-exitcode` model (root-only vs
all-tracked counting) is a property of the tool, and both witnesses are
lawful when every counted error is adjudicated ambient; an error code
with nothing counted is death. Which model the fork actually runs is
recorded by the leg note from the repro7 capture, not assumed.

## 5. Toolchain notes (mawk, not gawk)

The DC3 image's awk is mawk 1.3.4: no `gensub`, no `length(array)`, no
`; else` -- the census program is written mawk-safe and the whole leg is
syntax- and behaviour-checked IN the container before any push (local
gate: the truth-log acid test and the fixture battery both ran there).

## 6. Feeds (the bsdtar lesson, carried)

Truth-runs feed the container via `git archive` (reads git objects -- the
host's xattr-carrying files never enter the stream) piped straight to
the container's GNU tar. `bsdtar` is OUT of the feed chain: it smuggles
AppleDouble `._*` companions as hidden members (host `tar -t` self-reports
0 sidecars; the container extracts 14,661), which is what made the repro4
and repro5 `R CMD INSTALL` deaths (`_entrypoint.c: stray '\1'`). The
container-side gate still counts extracted sidecars and dies on any.

## 7. Verdict

The leg now attests what it used to only pretend: an instrumented guest
(413 tests truly under memcheck), a census that reads the whole forest,
adjudication that is code with evidence, and a suppression file that says
out loud it guards nothing. Gates frozen; the gate moved toward truth.
