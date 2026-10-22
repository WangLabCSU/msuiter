#!/usr/bin/env python3
"""Merge covr shard fragments into the single coverage artifacts (2026-10-21).

The lane SRT is our own line format, written by tools/ci/run-covr-shard.R:
one "hits|filename:line" row per covr tally_coverage(by="line") triple
(covr exports no to_srt -- the trio is what its to_cobertura renders).
Merging is additive per instrumented line, which is the covr union
semantics the unsharded run had: an execution in any shard counts.

Outputs: the merged SRT (auditable witness) and a cobertura.xml carrying
the same per-file lineHits the unsharded covr::to_cobertura would have
rendered -- the Codecov upload contract is unchanged (files: cobertura.xml).
"""
import argparse, sys, xml.etree.ElementTree as ET
from collections import defaultdict


def parse_srt(path):
    merged = defaultdict(int)
    instruments = set()
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if not line:
                continue
            hits, sep, name = line.partition("|")
            if not sep or not hits.isdigit() or not name:
                raise SystemExit("not a covr SRT line (%s): %r" % (path, line))
            merged[name] += int(hits)
            instruments.add(name)
    return merged, instruments


def parse_srt_many(paths):
    merged, instruments = defaultdict(int), set()
    for path in paths:
        m, ins = parse_srt(path)
        for name, hits in m.items():
            merged[name] += hits
        instruments |= ins
    return merged, instruments


def render_cobertura(merged, out_path):
    by_file = defaultdict(list)
    for name in sorted(merged):
        fpath, _, lineno = name.rpartition(":")
        if not lineno.isdigit():
            raise SystemExit("SRT name lacks :line suffix: %r" % name)
        by_file[fpath].append((int(lineno), merged[name]))
    cov = ET.Element("coverage", {"line-rate": "0", "lines-covered": "0",
                                  "lines-valid": "0", "timestamp": "epoch"})
    sources = ET.SubElement(cov, "sources")
    ET.SubElement(sources, "source").text = ""
    packages = ET.SubElement(cov, "packages")
    tot_cov = tot_val = 0
    for fpath in sorted(by_file):
        entries = by_file[fpath]
        cls = ET.SubElement(packages, "classes")
        c = ET.SubElement(cls, "class", {"name": fpath, "filename": fpath,
                                         "line-rate": "0", "complexity": "0"})
        lines = ET.SubElement(c, "lines")
        ncov = sum(1 for _, h in entries if h > 0)
        for (lineno, hits) in entries:
            ET.SubElement(lines, "line", {"number": str(lineno), "hits": str(hits),
                                          "branch": "false", "cond": "true"})
        c.set("line-rate", str(round(ncov / len(entries), 6) if entries else 0))
        cov.set("lines-covered", str(int(cov.get("lines-covered")) + ncov))
        cov.set("lines-valid", str(int(cov.get("lines-valid")) + len(entries)))
        tot_cov += ncov; tot_val += len(entries)
    cov.set("line-rate", str(round(tot_cov / tot_val, 6) if tot_val else 0))
    ET.indent(cov)
    ET.ElementTree(cov).write(out_path, encoding="utf-8", xml_declaration=False)


def self_test(out):
    import tempfile, os
    base = tempfile.mkdtemp("covmerge-selftest-")
    try:
        fa = os.path.join(base, "a.srt"); fb = os.path.join(base, "b.srt")
        open(fa, "w").write("1|R/x.R:3\n0|R/x.R:4\n5|R/y.R:1\n")
        open(fb, "w").write("2|R/x.R:3\n7|R/x.R:4\n0|R/y.R:1\n")
        merged, ins = parse_srt_many([fa, fb])
        ok = (merged["R/x.R:3"] == 3 and merged["R/x.R:4"] == 7
             and merged["R/y.R:1"] == 5 and len(ins) == 3)
        out("covmerge: additive merge control %s" % ("FIR" if ok else "BROKEN"))
        xml = os.path.join(base, "cobertura.xml")
        render_cobertura(dict(merged), xml)
        body = open(xml, encoding="utf-8").read()
        ok2 = ('number="4" hits="7"' in body.replace("\n", " ").replace("  ", " ")
               or ('number="4"' in body and 'hits="7"' in body))
        ok2 = ok2 and 'name="R/x.R"' in body and 'hits="3"' in body
        out("covmerge: cobertura render control %s" % ("FIR" if ok2 else "BROKEN"))
        if not (ok and ok2):
            out("COVMERGE SELF-TEST FAILED")
            return 1
        out("COVMERGE SELF-TEST OK")
        return 0
    finally:
        import shutil; shutil.rmtree(base, ignore_errors=True)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--fragments", nargs="+")
    ap.add_argument("--out-srt"); ap.add_argument("--cobertura")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args(argv)
    out = lambda s: print(s, flush=True)
    if a.self_test:
        return self_test(out)
    if not a.fragments:
        out("covmerge: --fragments is required")
        return 2
    merged, _ = parse_srt_many(a.fragments)
    if a.out_srt:
        with open(a.out_srt, "w") as fh:
            for name in sorted(merged):
                fh.write("%d|%s\n" % (merged[name], name))
    if a.cobertura:
        render_cobertura(dict(merged), a.cobertura)
    out("covmerge: fragments=%d instrumented=%d covered=%d"
        % (len(a.fragments), len(merged), sum(1 for h in merged.values() if h > 0)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
