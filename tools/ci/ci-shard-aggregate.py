#!/usr/bin/env python3
"""Strict attestation aggregator for the sharded CI lanes (2026-10-21).

Consumes the committed shard manifest and the per-shard MSUITER-ATTEST
verdicts produced by tools/ci/run-testthat-shard.R (kind=guards) and its
fan-out invocation (kind=fanout). The census is structural, not trust-based:

  * every manifest shard must attest                    -- missing shard dies
  * every attestation must report executed >= 1        -- an arm that ran no
                                                          tests gates nothing
  * fail/error counters must be zero, status must be ok
  * files reported must cover the manifest's shard roster
  * attestations from outside the manifest die too      -- unknown shard

--advisory is retired (2026-10-24): it let the coverage lane print defects
and exit green -- a vacuous green in the gate itself. The lane gates now. The
installed-copy context's structural absences are sanctioned the same way
fan-out skips are: byte-exact rows in the committed divergences ledger
(--ledger), reverse-audited so a row that sanctions nothing is a defect.

--self-test builds a miniature attestation world, removes pieces from it,
and requires each control to be OBSERVED FIRING. A control that never
trips is a vacuous green in the gate itself.
"""
import argparse, os, sys, tempfile, shutil


def die2(msg):
    """Loud, counted death: a DEFECT line and exit 2 (usage-class)."""
    print(msg, flush=True)
    sys.exit(2)


def parse_manifest(path):
    k, rows = None, []
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if line.startswith("#"):
                if " k=" in line:
                    k = int(line.split("k=")[1].split()[0])
                continue
            if not line.strip():
                continue
            parts = line.split("\t")
            if parts[0] == "shard":
                continue
            if len(parts) != 4:
                die2("DEFECT malformed manifest row: %r" % line)
            if parts[3] not in ("T0", "T1", "T2"):
                die2("DEFECT manifest tier outside {T0,T1,T2}: %r" % line)
            rows.append((int(parts[0]), parts[1], int(parts[2]), parts[3]))
    if k is None or not rows:
        die2("DEFECT manifest unusable: %s" % path)
    return k, rows


def parse_attest(path):
    line = None
    for raw in open(path, encoding="utf-8"):
        if raw.startswith("MSUITER-ATTEST"):
            line = raw.strip()
    if line is None:
        return None
    fields = {}
    for tok in line.split()[1:]:
        if "=" in tok:
            key, val = tok.split("=", 1)
            fields[key] = val
    return fields


def expected_files(kind, shard, configs):
    if kind != "fanout" or configs is None:
        return ["shard-%d.attest" % shard]
    return ["shard-%d-%s-%s.attest" % (shard, os_, cfg) for (os_, cfg) in configs]


def scope_configs(configs, expect, out):
    """Fan-out scoping (run 39616815087 forensics): each arm holds ONLY its
    own attestation forest. The expected set must therefore be pinned to the
    arm's own config -- an arm censusing the whole roster declared the other
    arms' six-shard sets missing (18 vacuous DEFECTs, all four fan-out arms
    doomed). --expect-config is mandatory for fan-out: unscoped censuses
    cannot distinguish other-arms-absent from other-arms-dead."""
    if expect is None:
        out("DEFECT fan-out census requires --expect-config OS-RCFG (the arm's own tag)")
        return None
    scoped = [(o, c) for (o, c) in configs if "%s-%s" % (o, c) == expect]
    if not scoped:
        out("DEFECT --expect-config %r is not in the fan-out roster" % expect)
        return None
    return scoped


def parse_exclusions(path, out):
    """Read the sanctioned-skip ledger: 'os<TAB>config<TAB>shard<TAB>cause'.

    The ledger is the single authority for what an arm may DECLARAbLY not
    run (round-2, run 39753886611 forensics: the M2 xval reference is
    uninstallable at R 4.3 -- Bioc 3.18 trees 404 on every mirror). An
    exclusion is not a permission to say nothing: it inverts the burden of
    proof -- the arm must now carry a marker where an attestation used to
    be, and any attestation appearing under an active exclusion is drift
    between the plan and the run, so it dies too."""
    rows = {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line.strip() or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) != 4 or not all(p.strip() for p in parts):
                out("DEFECT malformed shard-exclusions row: %r" % line)
                return None
            os_, cfg, shard, cause = parts
            key = (os_, cfg, shard)
            if key in rows:
                out("DEFECT duplicate shard-exclusions row: %r" % line)
                return None
            rows[key] = cause
    return rows


def exclusion_marker(tag, shard, cause):
    """The exact bytes a sanctioned marker must carry, and nothing else."""
    return ["MSUITER-EXCL shard=%s tag=%s" % (shard, tag), cause]


def write_exclusion_marker(registry, tag, shard, out_path, out):
    """Render the marker for a registered (tag, shard) from the ledger.

    ci.yml asks for markers instead of synthesizing them: the only way a
    marker can exist is by being read out of the committed ledger, so a
    marker that drifts from the ledger cannot be produced by accident.

    Returns 0 (marker written), 2 (ledger malformed -- parse_exclusions has
    already spoken its DEFECT), or 3 (the pair is simply not registered, so
    the caller runs the shard). 3 is a sentinel, not a defect: it must not
    borrow the DEFECT token the arms' logs are read for."""
    rows = parse_exclusions(registry, out)
    if rows is None:
        return 2
    hits = [k for k in rows if "%s-%s" % (k[0], k[1]) == tag and k[2] == str(shard)]
    if not hits:
        out("EXCL-UNREGISTERED tag=%s shard=%s (run the shard)" % (tag, shard))
        return 3
    os_, cfg, sh = hits[0]
    with open(out_path, "w") as fh:
        fh.write("\n".join(exclusion_marker(tag, sh, rows[hits[0]])) + "\n")
    out("EXCL-MARKER %s (cause of record: %s)" % (out_path, rows[hits[0]][:80]))
    return 0


def parse_divergences(path, out):
    """Read the covr sanctioned-divergences ledger (covr-divergences.tsv).

    The covr lane runs the testthat corpus against the INSTALLED copy, a
    context the repo-mode corpus was not written for: files that locate the
    checkout (tools/) observe structural skips and attest executed=0. Such
    an absence is permitted the same way fan-out skips are -- named in the
    committed ledger, byte-checked at the census, and reverse-audited: a row
    that sanctions nothing is itself a defect, so the ledger can never bank
    silence."""
    rows = {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line.strip() or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) != 4 or not all(p.strip() for p in parts):
                out("DEFECT malformed divergences row: %r" % line)
                return None
            shard, files, why, witness = parts
            if not shard.isdigit():
                out("DEFECT non-integer divergences shard: %r" % line)
                return None
            key = int(shard)
            if key in rows:
                out("DEFECT duplicate divergences row for shard %d" % key)
                return None
            rows[key] = {"files": set(f for f in files.split(",") if f),
                        "why": why, "witness": witness}
    return rows


def read_t0_budget(path, out):
    """Read the committed PR-gate T0 budget TSV (issue #76): key/value
    rows under comment lines. The budget is a MEASURED number committed
    in the repo -- the census re-prices the manifest against it so a
    hand-edited manifest or a drifted weights table cannot outrun the
    hang-budget spirit: drift goes red."""
    kv = {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line.strip() or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 2:
                out("DEFECT malformed pr-gate-budget row: %r" % line)
                return None, None
            kv[parts[0]] = parts[1]
    try:
        return int(kv["t0-measured"]), int(kv["t0-ceiling"])
    except (KeyError, ValueError):
        out("DEFECT pr-gate-budget lacks numeric t0-measured/t0-ceiling rows")
        return None, None


def census(manifest, attest_dir, kind, configs, out, exclusions=None,
           divergences=None, tiers=None, t0_budget=None):
    if not os.path.isdir(attest_dir):
        # A vanished evidence directory is the download-artifact failure mode
        # of the issue #76 guards gate: it must speak, never crash bare and
        # never read green.
        out("DEFECT attest-dir absent: %s -- the lane handed the census no "
            "evidence directory" % attest_dir)
        return 1
    k, rows_all = parse_manifest(manifest)
    rows = [r for r in rows_all if r[3] in tiers] if tiers is not None else list(rows_all)
    roster = {}
    for shard, fname, _sec, _tier in rows:
        roster.setdefault(shard, []).append(fname)
    defects, executed_total, files_total, fails, errs = [], 0, 0, 0, 0
    sanctioned_total = 0
    used_rows = set()
    shards_ok = 0
    excluded_total = 0
    seen = set()
    for shard in sorted(roster):
        for name in expected_files(kind, shard, configs):
            path = os.path.join(attest_dir, name)
            excl_name = None
            if kind == "fanout" and exclusions:
                for (os_, cfg) in configs:
                    if (os_, cfg, str(shard)) in exclusions:
                        excl_name = "shard-%d-%s-%s.excl" % (shard, os_, cfg)
            if excl_name is not None:
                # The ledger says this arm may not run this shard. Silence
                # is not accepted either: exactly the marker, exactly the
                # ledger's bytes, and never both an attestation and it.
                marker_path = os.path.join(attest_dir, excl_name)
                if os.path.exists(path):
                    defects.append("ran under an active exclusion (ledger is stale?): %s" % name)
                    seen.add(excl_name)
                    continue
                if not os.path.exists(marker_path):
                    defects.append("exclusion marker missing: %s (shard %d is registered as excluded)"
                                   % (excl_name, shard))
                    continue
                with open(marker_path, encoding="utf-8") as fh:
                    body = fh.read()
                want = "\n".join(exclusion_marker("%s-%s" % (os_, cfg), shard,
                                                  exclusions[(os_, cfg, str(shard))])) + "\n"
                if body != want:
                    defects.append("exclusion marker off the ledger: %s" % excl_name)
                    continue
                seen.add(excl_name)
                excluded_total += 1
                continue
            if not os.path.exists(path):
                defects.append("missing attestation: %s (shard %d)" % (name, shard))
                continue
            fields = parse_attest(path)
            seen.add(name)
            if fields is None:
                defects.append("missing attestation (no MSUITER-ATTEST line): %s" % name)
                continue
            if fields.get("kind") != kind:
                defects.append("attestation kind mismatch: %s kind=%r" % (name, fields.get("kind")))
                continue
            if fields.get("shard") != str(shard):
                defects.append("unknown shard: %s claims shard=%r" % (name, fields.get("shard")))
                continue
            try:
                n_exec = int(fields["executed"]); n_fail = int(fields["fail"])
                n_err = int(fields["error"]); n_file = int(fields["files"])
            except (KeyError, ValueError):
                defects.append("attestation unreadable counters: %s" % name)
                continue
            shard_defects = []
            if n_exec <= 0:
                shard_defects.append("zero executed: %s runs no tests and gates nothing" % name)
            if n_fail != 0 or n_err != 0:
                shard_defects.append("non-zero fail/error: %s fail=%d error=%d" % (name, n_fail, n_err))
            if fields.get("status") != "ok":
                shard_defects.append("attestation not ok: %s status=%r" % (name, fields.get("status")))
            if n_file < len(roster[shard]):
                shard_defects.append("shard %d attests %d files, manifest names %d"
                                    % (shard, n_file, len(roster[shard])))
            row = divergences.get(shard) if divergences is not None else None
            if row is not None:
                att_why = fields.get("why")
                why_ok = ((att_why is None and row["why"] == "-")
                         or att_why == row["why"])
                files_ok = set(roster[shard]) == row["files"]
                if (fields.get("status") == "vacuous" and n_exec == 0
                        and n_fail == 0 and n_err == 0 and why_ok and files_ok):
                    sanctioned_total += 1
                    used_rows.add(shard)
                    out("SANCTIONED %s (shard %d): status=vacuous executed=0 "
                        "why=%s [witness: %s]"
                        % (name, shard, "-" if att_why is None else att_why,
                           row["witness"]))
                    shard_defects = []
                else:
                    shard_defects.append(
                        "coverage divergences row for shard %d does not match "
                        "(attestation status=%r why=%r executed=%d fail=%d "
                        "vs ledger why=%r files=%s)"
                        % (shard, fields.get("status"), att_why, n_exec,
                           n_fail, row["why"], ",".join(sorted(row["files"]))))
            defects.extend(shard_defects)
            executed_total += n_exec; files_total += n_file
            fails += n_fail; errs += n_err
            if n_exec > 0 and n_fail == 0 and n_err == 0 and fields.get("status") == "ok":
                shards_ok += 1
    if kind == "fanout" and exclusions:
        # A tier-scoped arm never visits a shard whose in-tier roster is
        # empty, so the roster loop never consumes that shard's ledger
        # marker -- yet the workflow's pre-launch gate writes it for every
        # registered (arm, shard), ledger bytes or nothing. Consume those
        # markers here (byte law still applies) so a registered exclusion
        # reads lawful off-tier and an unregistered one still reads rogue.
        for (os_, cfg, sh_str), cause in sorted(exclusions.items()):
            try:
                sh = int(sh_str)
            except ValueError:
                continue
            if sh in roster:
                continue
            excl_name = "shard-%d-%s-%s.excl" % (sh, os_, cfg)
            marker_path = os.path.join(attest_dir, excl_name)
            if os.path.exists(marker_path):
                with open(marker_path, encoding="utf-8") as fh:
                    body = fh.read()
                want = "\n".join(exclusion_marker("%s-%s" % (os_, cfg), sh,
                                                  cause)) + "\n"
                if body != want:
                    defects.append("exclusion marker off the ledger: %s" % excl_name)
                seen.add(excl_name)
                excluded_total += 1
    for name in sorted(os.listdir(attest_dir)):
        if name.endswith(".attest") and name not in seen:
            defects.append("unknown attestation (outside manifest): %s" % name)
        if name.endswith(".excl") and name not in seen:
            defects.append("rogue exclusion marker (unregistered): %s" % name)
    if t0_budget is not None:
        _measured, ceiling = read_t0_budget(t0_budget, out)
        if ceiling is not None:
            t0sum = sum(sec for (_s, _f, sec, tier) in rows_all if tier == "T0")
            if t0sum > ceiling:
                defects.append("T0 weight %d s exceeds the committed ceiling %d s "
                               "(tools/ci/pr-gate-budget.tsv) -- the PR-gate battery "
                               "may not grow past its measured budget" % (t0sum, ceiling))
    if divergences is not None:
        for shard in sorted(divergences):
            if shard not in used_rows:
                defects.append("stale divergences row: shard %d sanctioned nothing "
                               "(attestation healthy, absent, or off the row's byte "
                               "signature -- ledger is [%s])"
                               % (shard, divergences[shard]["witness"][:60]))
    out("AGGREGATE kind=%s tiers=%s shards=%d/%d files=%d/%d executed=%d fails=%d errors=%d excluded=%d sanctioned=%d defects=%d"
        % (kind, "+".join(tiers) if tiers is not None else "all",
           shards_ok, len(roster), files_total, len(rows), executed_total, fails, errs,
           excluded_total, sanctioned_total, len(defects)))
    for d in defects:
        out("DEFECT " + d)
    return len(defects)


def self_test(out):
    def attest(shard, kind, files, executed, status="ok", fail=0, err=0, extra=None):
        d = {"kind": kind, "shard": str(shard), "files": str(files), "tests": str(executed + 1),
             "executed": str(executed), "pass": str(executed), "fail": str(fail),
             "error": str(err), "skip": "0", "warn": "0", "status": status}
        if extra:
            d.update(extra)
        return " ".join(["MSUITER-ATTEST"] + ["%s=%s" % kv for kv in d.items()])
    base = tempfile.mkdtemp("aggregate-selftest-")
    try:
        man = os.path.join(base, "manifest.tsv")
        with open(man, "w") as fh:
            fh.write("# k=2\nshard\tfile\tseconds\ttier\n"
                   "1\ttest-a.R\t5\tT0\n1\ttest-b.R\t5\tT0\n"
                   "2\ttest-c.R\t5\tT0\n")
        adir = os.path.join(base, "attest"); os.mkdir(adir)
        def write(name, line):
            with open(os.path.join(adir, name), "w") as fh:
                fh.write(line + "\n")
        good = {}
        good["shard-1.attest"] = attest(1, "guards", 2, 3)
        good["shard-2.attest"] = attest(2, "guards", 1, 3)
        def census_count(defect_needle):
            collected = []
            n = census(man, adir, "guards", None, collected.append)
            if n == 0 or not any(defect_needle in c for c in collected):
                out("SELF-TEST BROKEN: control expected DEFECT containing %r" % defect_needle)
                return False
            return True
        for name in good:
            write(name, good[name])
        fired = []
        os.remove(os.path.join(adir, "shard-2.attest"))
        fired.append(census_count("missing attestation"))
        out("missing-shard control FIR" if fired[-1] else "SELF-TEST BROKEN: missing-shard control")
        absent_n = []
        n_absent = census(man, os.path.join(base, "no-such-attest-dir"), "guards",
                          None, absent_n.append)
        out("attest-dir-absent control FIR" if n_absent == 1
            and any("attest-dir absent" in c for c in absent_n)
            else "SELF-TEST BROKEN: attest-dir-absent control")
        write("shard-2.attest", attest(2, "guards", 1, 0, status="vacuous"))
        fired.append(census_count("zero executed"))
        out("zero-executed control FIR" if fired[-1] else "SELF-TEST BROKEN: zero-executed control")
        write("shard-9.attest", attest(9, "guards", 1, 3))
        fired.append(census_count("unknown"))
        out("unknown-shard control FIR" if fired[-1] else "SELF-TEST BROKEN: unknown-shard control")
        os.remove(os.path.join(adir, "shard-9.attest"))
        write("shard-2.attest", good["shard-2.attest"])
        collected = []
        n = census(man, adir, "guards", None, collected.append)
        fired.append(n == 0)
        out("good control stays GREEN" if n == 0 else "SELF-TEST BROKEN: good set went RED: %s" % collected)
        # -- Fan-out scoping law (run 39616815087: unscoped arms censused the
        # whole roster and doomed each other with 18 vacuous DEFECTs) --
        for nm in list(os.listdir(adir)):
            os.remove(os.path.join(adir, nm))
        def fanatt(shard, tag):
            return attest(shard, "fanout", 2 if shard == 1 else 1, 3,
                          extra={"tag": tag})
        mine = "macos-latest-release"
        other = "windows-latest-oldrel_1".replace("_", "-")
        for shard in (1, 2):
            with open(os.path.join(adir, "shard-%d-%s.attest" % (shard, mine)), "w") as fh:
                fh.write(fanatt(shard, mine) + "\n")
        cfgs = [(mine.rpartition("-")[0], mine.rpartition("-")[2]),
                (other.rpartition("-")[0], other.rpartition("-")[2])]
        collected = []
        n = census(man, adir, "fanout", [(mine.rpartition("-")[0], mine.rpartition("-")[2])],
                   collected.append)
        fired.append(n == 0)
        out("scoped-arm control stays GREEN" if n == 0
            else "SELF-TEST BROKEN: scoped arm went RED: %s" % collected)
        collected = []
        n = census(man, adir, "fanout", [(other.rpartition("-")[0], other.rpartition("-")[2])],
                   collected.append)
        fired.append(n > 0 and any("missing attestation" in c for c in collected))
        out("other-config-missing control FIR" if fired[-1]
            else "SELF-TEST BROKEN: other-config control silent: %s" % collected)
        collected = []
        sc = scope_configs(cfgs, None, collected.append)
        fired.append(sc is None and any("expect-config" in c for c in collected))
        out("unscoped refusal control FIR" if fired[-1]
            else "SELF-TEST BROKEN: unscoped refusal silent: %s" % collected)
        collected = []
        sc = scope_configs(cfgs, "bogus-9", collected.append)
        fired.append(sc is None and any("not in the fan-out roster" in c for c in collected))
        out("bogus-config control FIR" if fired[-1]
            else "SELF-TEST BROKEN: bogus-config control silent: %s" % collected)
        # -- Sanctioned-exclusion ledger law (shard-exclusions.tsv; run
        # 39753886611: the M2 xval reference is uninstallable at R 4.3 --
        # Bioc 3.18 404 everywhere). An arm that cannot run a shard must say
        # so from the committed ledger AND carry the rendered marker;
        # silence, drift and unregistered skips all die. --
        scoped = [(mine.rpartition("-")[0], mine.rpartition("-")[2])]
        reg = os.path.join(base, "exclusions.tsv")
        excl_cause = "reference not installable at the arm R floor (self-test fixture)"
        def write_reg(with_row):
            with open(reg, "w") as fh:
                fh.write("# ledger\n")
                if with_row:
                    fh.write("macos-latest\trelease\t2\t%s\n" % excl_cause)
        mk_path = os.path.join(adir, "shard-2-%s.excl" % mine)
        at_path = os.path.join(adir, "shard-2-%s.attest" % mine)
        os.remove(at_path)
        write_reg(True)
        rows = parse_exclusions(reg, out)
        if rows is None or write_exclusion_marker(reg, mine, "2", mk_path, lambda s: None) != 0:
            out("SELF-TEST BROKEN: exclusion writer rejected its own ledger")
            fired.append(False)
        else:
            collected = []
            n = census(man, adir, "fanout", scoped, collected.append, exclusions=rows)
            fired.append(n == 0 and any("excluded=1" in c for c in collected))
            out("sanctioned-exclusion control stays GREEN" if fired[-1]
                else "SELF-TEST BROKEN: sanctioned exclusion went RED: %s" % collected)
            os.remove(mk_path)
            collected = []
            n = census(man, adir, "fanout", scoped, collected.append, exclusions=rows)
            fired.append(n > 0 and any("exclusion marker missing" in c for c in collected))
            out("missing-marker control FIR" if fired[-1]
                else "SELF-TEST BROKEN: missing-marker control silent: %s" % collected)
            write_exclusion_marker(reg, mine, "2", mk_path, lambda s: None)
            with open(at_path, "w") as fh:
                fh.write(fanatt(2, mine) + "\n")
            collected = []
            n = census(man, adir, "fanout", scoped, collected.append, exclusions=rows)
            fired.append(n > 0 and any("ran under an active exclusion" in c for c in collected))
            out("drift control FIR" if fired[-1]
                else "SELF-TEST BROKEN: drift control silent: %s" % collected)
            os.remove(at_path)
            write_reg(False)
            empty = parse_exclusions(reg, out)
            collected = []
            n = census(man, adir, "fanout", scoped, collected.append, exclusions=empty)
            fired.append(n > 0 and any("rogue exclusion marker" in c for c in collected))
            out("rogue-marker control FIR" if fired[-1]
                else "SELF-TEST BROKEN: rogue-marker control silent: %s" % collected)
            with open(mk_path, "w") as fh:
                fh.write("MSUITER-EXCL shard=2 tag=%s\ndoctored cause\n" % mine)
            collected = []
            n = census(man, adir, "fanout", scoped, collected.append, exclusions=rows)
            fired.append(n > 0 and any("off the ledger" in c for c in collected))
            out("marker-off-ledger control FIR" if fired[-1]
                else "SELF-TEST BROKEN: marker-off-ledger control silent: %s" % collected)
            os.remove(mk_path)
            with open(at_path, "w") as fh:
                fh.write(fanatt(2, mine) + "\n")
        # -- Covr sanctioned-divergences ledger law (covr-divergences.tsv).
        # The installed-copy context gives checkout-locating files structural
        # executed=0 attests (sentry class, PR #52 forensics); the census
        # gates, the ledger sanctions byte-exact vacuities, and rows that
        # sanction nothing are themselves defects -- the ledger can never
        # bank silence. --
        for nm in list(os.listdir(adir)):
            os.remove(os.path.join(adir, nm))
        def covatt(shard, files, executed, status, why=None, skip=None):
            d = {"kind": "coverage", "shard": str(shard), "files": str(files),
                 "tests": str(executed + (1 if status == "vacuous" else 0)),
                 "executed": str(executed), "pass": str(executed),
                 "fail": "0", "error": "0",
                 "skip": str(skip if skip is not None else 0),
                 "warn": "0", "status": status}
            if why is not None:
                d["why"] = why
            return " ".join(["MSUITER-ATTEST"] + ["%s=%s" % kv for kv in d.items()])
        with open(os.path.join(adir, "shard-1.attest"), "w") as fh:
            fh.write(covatt(1, 0, 0, "vacuous", skip=1) + "\n")
        with open(os.path.join(adir, "shard-2.attest"), "w") as fh:
            fh.write(covatt(2, 1, 4, "ok") + "\n")
        collected = []
        n = census(man, adir, "coverage", None, collected.append)
        fired.append(n > 0 and any("zero executed" in c for c in collected))
        out("covr-ungated-vacuous control FIR" if fired[-1]
            else "SELF-TEST BROKEN: covr vacuous slipped without a ledger")
        led = os.path.join(base, "div.tsv")
        def write_led(body):
            with open(led, "w") as fh:
                fh.write("# ledger\n" + body)
        def cov_census(ledger_path):
            rows = parse_divergences(ledger_path, out) if ledger_path else None
            if rows is None and ledger_path:
                return -1, []
            collected = []
            n = census(man, adir, "coverage", None, collected.append,
                       divergences=rows)
            return n, collected
        write_led("1\ttest-a.R,test-b.R\t-\tself-test fixture\n")
        n, collected = cov_census(led)
        fired.append(n == 0 and any("SANCTIONED" in c for c in collected)
                    and any("sanctioned=1" in c for c in collected))
        out("covr-sanction control stays GREEN" if fired[-1]
            else "SELF-TEST BROKEN: sanctioned covr vacuous went RED: %s" % collected)
        write_led("1\ttest-a.R,test-b.R\tbogus-why\tself-test fixture\n")
        n, collected = cov_census(led)
        fired.append(n > 0 and any("does not match" in c for c in collected))
        out("covr-forged-why control FIR" if fired[-1]
            else "SELF-TEST BROKEN: forged why passed: %s" % collected)
        write_led("1\ttest-wrong.R\t-\tself-test fixture\n")
        n, collected = cov_census(led)
        fired.append(n > 0 and any("does not match" in c for c in collected))
        out("covr-files-drift control FIR" if fired[-1]
            else "SELF-TEST BROKEN: roster drift passed: %s" % collected)
        with open(os.path.join(adir, "shard-1.attest"), "w") as fh:
            fh.write(covatt(1, 0, 0, "vacuous", why="covr-failed") + "\n")
        write_led("1\ttest-a.R,test-b.R\t-\tself-test fixture\n")
        n, collected = cov_census(led)
        fired.append(n > 0 and any("covr-failed" in c for c in collected))
        out("covr-failed masquerade control FIR" if fired[-1]
            else "SELF-TEST BROKEN: covr-failed masqueraded as sanctioned: %s" % collected)
        with open(os.path.join(adir, "shard-1.attest"), "w") as fh:
            fh.write(covatt(1, 2, 5, "ok") + "\n")
        n, collected = cov_census(led)
        fired.append(n > 0 and any("stale divergences row" in c for c in collected))
        out("covr-stale-row control FIR" if fired[-1]
            else "SELF-TEST BROKEN: stale row rode unseen: %s" % collected)
        # -- Tier + budget law (issue #76). The manifest is the single
        # partition; the tier column says what a lane runs. A shard empty
        # in the tier needs no attestation; a shard WITH tier files that
        # stays silent dies; the committed T0 budget is re-priced at every
        # census so drift goes red. --
        for nm in list(os.listdir(adir)):
            os.remove(os.path.join(adir, nm))
        man3 = os.path.join(base, "manifest-tiers.tsv")
        with open(man3, "w") as fh:
            fh.write("# k=2\nshard\tfile\tseconds\ttier\n"
                     "1\ttest-a.R\t5\tT0\n1\ttest-b.R\t600\tT1\n"
                     "2\ttest-deep.R\t700\tT1\n")
        with open(os.path.join(adir, "shard-1.attest"), "w") as fh:
            fh.write(attest(1, "guards", 1, 3) + "\n")   # T0 file only
        collected = []
        n = census(man3, adir, "guards", None, collected.append,
                   tiers=["T0"])
        fired.append(n == 0 and any("tiers=T0" in c for c in collected))
        out("tier-empty-shard needs-no-attestation control stays GREEN" if fired[-1]
            else "SELF-TEST BROKEN: tier-skipped shard went RED: %s" % collected)
        collected = []
        n = census(man3, adir, "guards", None, collected.append,
                   tiers=["T0", "T1"])
        fired.append(n > 0 and any("missing attestation: shard-2.attest" in c
                                    for c in collected))
        out("tier-deepened census control FIR" if fired[-1]
            else "SELF-TEST BROKEN: T1 file ran unwatched: %s" % collected)
        with open(os.path.join(adir, "shard-2.attest"), "w") as fh:
            fh.write(attest(2, "guards", 1, 2) + "\n")
        collected = []
        n = census(man3, adir, "guards", None, collected.append,
                   tiers=["T0"])
        fired.append(n > 0 and any("unknown attestation" in c for c in collected))
        out("tier-blind attestation control FIR" if fired[-1]
            else "SELF-TEST BROKEN: out-of-tier attestation rode unseen: %s" % collected)
        os.remove(os.path.join(adir, "shard-2.attest"))
        # -- Out-of-tier marker law (issue #76): shard 2 holds only the
        # T1 file, so a T0 census never visits it; the registered marker
        # must ride green, an unregistered one must still die. --
        for nm in list(os.listdir(adir)):
            os.remove(os.path.join(adir, nm))
        with open(os.path.join(adir, "shard-1-linux-latest-release.attest"), "w") as fh:
            fh.write(attest(1, "fanout", 1, 1) + "\n")   # the T0 file, attested
        reg2 = os.path.join(base, "exclusions-oott.tsv")
        with open(reg2, "w") as fh:
            fh.write("linux-latest\trelease\t2\tfile needs the arm feature the "
                     "release floor lacks (self-test fixture)\n")
        oott_rows = parse_exclusions(reg2, out)
        if oott_rows is None:
            out("SELF-TEST BROKEN: out-of-tier ledger did not parse")
            fired.append(False)
        else:
            mk2 = os.path.join(adir, "shard-2-linux-latest-release.excl")
            write_exclusion_marker(reg2, "linux-latest-release", "2", mk2,
                                   lambda s: None)
            collected = []
            n = census(man3, adir, "fanout", [("linux-latest", "release")],
                       collected.append, exclusions=oott_rows, tiers=["T0"])
            fired.append(n == 0)
            out("out-of-tier registered marker control stays GREEN" if fired[-1]
                else "SELF-TEST BROKEN: off-tier marker reddened the census: %s"
                    % collected)
            os.remove(mk2)
            collected = []
            with open(mk2, "w") as fh:
                fh.write("MSUITER-EXCL tag=linux-latest-release shard=2\n"
                         "cause=planted by the self-test\n")
            n2 = census(man3, adir, "fanout", [("linux-latest", "release")],
                         collected.append, tiers=["T0"])
            fired.append(n2 > 0 and any(
                "rogue exclusion marker" in c for c in collected))
            out("out-of-tier rogue marker control FIR" if fired[-1]
                else "SELF-TEST BROKEN: unregistered off-tier marker rode unseen: %s"
                    % collected)
        for nm in list(os.listdir(adir)):
            os.remove(os.path.join(adir, nm))
        with open(os.path.join(adir, "shard-1.attest"), "w") as fh:
            fh.write(attest(1, "guards", 1, 3) + "\n")   # the state the
        # budget controls below were written against (mirrors the tier law
        # controls' committed-shape attestation)
        bud = os.path.join(base, "budget.tsv")
        with open(bud, "w") as fh:
            fh.write("# witness\nkey\tvalue\tnote\n"
                     "t0-measured\t5\tw\nt0-ceiling\t4\tw\n")
        collected = []
        n = census(man3, adir, "guards", None, collected.append,
                   tiers=["T0"], t0_budget=bud)
        fired.append(n > 0 and any("T0 weight" in c for c in collected))
        out("T0-budget ceiling control FIR" if fired[-1]
            else "SELF-TEST BROKEN: over-budget T0 passed: %s" % collected)
        with open(bud, "w") as fh:
            fh.write("key\tvalue\tnote\nt0-measured\t5\tw\nt0-ceiling\t999\tw\n")
        collected = []
        n = census(man3, adir, "guards", None, collected.append,
                   tiers=["T0"], t0_budget=bud)
        fired.append(n == 0)
        out("T0-budget headroom control stays GREEN" if fired[-1]
            else "SELF-TEST BROKEN: in-budget set went RED: %s" % collected)
        if not all(fired):
            out("AGGREGATE SELF-TEST FAILED")
            return 1
        out("AGGREGATE SELF-TEST OK")
        return 0
    finally:
        shutil.rmtree(base, ignore_errors=True)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest"); ap.add_argument("--attest-dir")
    ap.add_argument("--kind", choices=["guards", "fanout", "coverage"], default="guards")
    ap.add_argument("--fanout-configs")
    ap.add_argument("--expect-config", help="fan-out: the arm's own OS-RCFG tag; the expected set is scoped to it")
    ap.add_argument("--exclusions", help="fan-out: the sanctioned-skip ledger (shard-exclusions.tsv)")
    ap.add_argument("--ledger", help="coverage: the sanctioned-divergences ledger (covr-divergences.tsv)")
    ap.add_argument("--tier", help="run only these committed manifest tiers (comma-separated, e.g. T0 or T0,T1)")
    ap.add_argument("--t0-budget", help="fan-out: path to the committed PR-gate T0 budget TSV (required)")
    ap.add_argument("--write-exclusion-marker", action="store_true",
                    help="render the marker ci.yml must leave for a registered (tag, shard)")
    ap.add_argument("--tag"); ap.add_argument("--shard"); ap.add_argument("--out")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args(argv)
    out = lambda s: print(s, flush=True)
    if a.self_test:
        return self_test(out)
    if a.write_exclusion_marker:
        if not (a.exclusions and a.tag and a.shard and a.out):
            out("DEFECT --write-exclusion-marker needs --exclusions, --tag, --shard, --out")
            return 2
        return write_exclusion_marker(a.exclusions, a.tag, a.shard, a.out, out)
    if not a.manifest or not a.attest_dir:
        out("DEFECT --manifest and --attest-dir are required"); return 2
    configs = None
    if a.kind == "fanout":
        if not a.fanout_configs:
            out("DEFECT fan-out census requires --fanout-configs"); return 2
        configs = []
        for line in open(a.fanout_configs, encoding="utf-8"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) != 2:
                out("DEFECT malformed fanout-configs row: %r" % line); return 2
            configs.append(tuple(parts))
        scoped = scope_configs(configs, a.expect_config, out)
        if scoped is None:
            return 2
        configs = scoped
    elif a.expect_config is not None:
        out("DEFECT --expect-config is fan-out only (kind=%s)" % a.kind)
        return 2
    exclusions = None
    if a.exclusions:
        if a.kind != "fanout":
            out("DEFECT --exclusions is fan-out only (kind=%s)" % a.kind)
            return 2
        exclusions = parse_exclusions(a.exclusions, out)
        if exclusions is None:
            return 2
    divergences = None
    if a.ledger:
        if a.kind != "coverage":
            out("DEFECT --ledger is coverage-only (kind=%s)" % a.kind)
            return 2
        divergences = parse_divergences(a.ledger, out)
        if divergences is None:
            return 2
    tiers = None
    if a.tier:
        tiers = [t.strip() for t in a.tier.split(",") if t.strip()]
        if not tiers or any(t not in ("T0", "T1", "T2") for t in tiers):
            out("DEFECT --tier outside {T0,T1,T2}: %r" % a.tier)
            return 2
    if a.kind == "fanout" and not a.t0_budget:
        out("DEFECT fan-out census requires --t0-budget (the committed "
            "PR-gate T0 budget, tools/ci/pr-gate-budget.tsv)")
        return 2
    n = census(a.manifest, a.attest_dir, a.kind, configs, out,
               exclusions=exclusions, divergences=divergences,
               tiers=tiers, t0_budget=a.t0_budget)
    return 1 if n else 0


if __name__ == "__main__":
    sys.exit(main())
