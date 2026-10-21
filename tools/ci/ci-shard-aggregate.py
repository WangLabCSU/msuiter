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

--advisory (coverage lane, whose covr arm is non-gating by long-standing
semantics -- see the coverage step's continue-on-error posture) prints every
defect it finds but exits green.

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
            if len(parts) != 3:
                die2("DEFECT malformed manifest row: %r" % line)
            rows.append((int(parts[0]), parts[1]))
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


def census(manifest, attest_dir, kind, configs, out):
    k, rows = parse_manifest(manifest)
    roster = {}
    for shard, fname in rows:
        roster.setdefault(shard, []).append(fname)
    defects, executed_total, files_total, fails, errs = [], 0, 0, 0, 0
    shards_ok = 0
    seen = set()
    for shard in range(1, k + 1):
        for name in expected_files(kind, shard, configs):
            path = os.path.join(attest_dir, name)
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
            if n_exec <= 0:
                defects.append("zero executed: %s runs no tests and gates nothing" % name)
            if n_fail != 0 or n_err != 0:
                defects.append("non-zero fail/error: %s fail=%d error=%d" % (name, n_fail, n_err))
            if fields.get("status") != "ok":
                defects.append("attestation not ok: %s status=%r" % (name, fields.get("status")))
            if n_file < len(roster[shard]):
                defects.append("shard %d attests %d files, manifest names %d"
                              % (shard, n_file, len(roster[shard])))
            executed_total += n_exec; files_total += n_file
            fails += n_fail; errs += n_err
            if n_exec > 0 and n_fail == 0 and n_err == 0 and fields.get("status") == "ok":
                shards_ok += 1
    for name in sorted(os.listdir(attest_dir)):
        if name.endswith(".attest") and name not in seen:
            defects.append("unknown attestation (outside manifest): %s" % name)
    out("AGGREGATE kind=%s shards=%d/%d files=%d/%d executed=%d fails=%d errors=%d defects=%d"
        % (kind, shards_ok, k, files_total, len(rows), executed_total, fails, errs, len(defects)))
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
            fh.write("# k=2\nshard\tfile\tseconds\n1\ttest-a.R\t5\n1\ttest-b.R\t5\n2\ttest-c.R\t5\n")
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
    ap.add_argument("--fanout-configs"); ap.add_argument("--advisory", action="store_true")
    ap.add_argument("--expect-config", help="fan-out: the arm's own OS-RCFG tag; the expected set is scoped to it")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args(argv)
    out = lambda s: print(s, flush=True)
    if a.self_test:
        return self_test(out)
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
    n = census(a.manifest, a.attest_dir, a.kind, configs, out)
    if n and a.advisory:
        out("ADVISORY kind=%s: %d defects tolerated (non-gating lane)" % (a.kind, n))
        return 0
    return 1 if n else 0


if __name__ == "__main__":
    sys.exit(main())
