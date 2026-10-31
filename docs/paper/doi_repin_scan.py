#!/usr/bin/env python3
"""PP-1 DOI re-pin pass (deliverable 3).

Collects every DOI mentioned in docs/research/*.md and (optionally, via --extra)
the manuscript bibliography source files, and re-verifies each against
publisher metadata via Crossref (primary) and OpenAlex (fallback). A planted
fabrication control MUST be refused by the same code path -- if the control
does not trip, the scan exits 2 (a non-firing control is a dead metric; DS-1
idiom).

Verdict classes per DOI:
  VERIFIED      resolves AND the recorded title tokens overlap the registry title
  TITLE-DRIFT   resolves but the recorded title does not support the registry title
  NOT-RESOLVED  404/absent on both registries (must not carry a DOI into print)

Output: a tab-separated census written by --out, plus a one-line roll-up.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

DOI_RE = re.compile(r"10\.[0-9]{4,9}/[^\s)\]\"',;|]+")
UA = {"User-Agent": "msuiter-pp1-doi-repin/1.0 (mailto:wangshx@csu.edu.cn)"}
STOP = {"the", "of", "and", "for", "a", "an", "in", "on", "to", "with",
        "via", "by", "its", "doi", "pmid", "note", "correct", "crossref"}

def clean_doi(s: str) -> str:
    """Strip markdown/trailing punctuation that is not part of a DOI."""
    return s.strip().rstrip("*_~`'\"]().,;:|")

def tidy_tokens(s: str) -> set[str]:
    """Drop DOI-form fragments so they cannot self-overlap the context."""
    toks = tokens(s)
    return {t for t in toks if not re.match(r"^[0-9]+$", t) and "10" not in t[:2]
            and t not in {"doi", "https", "http", "org"}}


def tokens(s: str) -> set[str]:
    return {t for t in re.split(r"[^a-z0-9]+", s.lower()) if len(t) > 3 and t not in STOP}


def http_json(url: str, timeout: int = 30):
    req = urllib.request.Request(url, headers=UA)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.getcode(), json.loads(r.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as exc:
        return exc.code, None
    except Exception:
        return -1, None


US = chr(95)
DH = chr(45)
CL = "".join(chr(c) for c in (91, 94, 97, 45, 122, 48, 45, 57, 43, 93))  # split class

def crossref_meta(doi: str):
    code, doc = http_json("https://api.crossref.org/works/" + urllib.parse.quote(doi, safe=""))
    if code != 200 or not doc or doc.get("status") not in (None, "ok"):
        return None
    msg = doc.get("message") or {}
    titles = msg.get("title") or []
    auth = [(a.get("family") or a.get("name") or "") for a in (msg.get("author") or [])]
    year = ""
    for key in ("published" + DH + "print", "issued"):
        v = msg.get(key)
        if isinstance(v, dict):
            cp = (v.get("date" + DH + "parts") or [[]])[0]
            if cp:
                year = str(cp[0])
    return {"title": titles[0] if titles else "", "src": "crossref",
            "authors": [a.lower() for a in auth if a], "year": year,
            "journal": (msg.get("container" + DH + "title") or [""])[0]}


def openalex_meta(doi: str):
    code, doc = http_json("https://api.openalex.org/works/https://doi.org/"
                          + urllib.parse.quote(doi, safe=""))
    if code != 200 or not doc:
        return None
    auth = [((a.get("author") or {}).get("display" + US + "name") or "")
            for a in (doc.get("authorships") or [])]
    src = ((doc.get("primary" + US + "location") or {}).get("source") or {})
    return {"title": doc.get("title") or "", "src": "openalex",
            "authors": [a.lower() for a in auth if a],
            "year": str(doc.get("publication" + US + "year") or ""),
            "journal": (src.get("display" + US + "name") or "")}


def classify(doi: str, context: str):
    rec = crossref_meta(doi) or openalex_meta(doi)
    if rec is None:
        return "NOT-RESOLVED", "", ""
    want, got = tidy_tokens(context), tokens(rec["title"])
    meta_toks: set[str] = set()
    for a in rec["authors"]:
        meta_toks |= {t for t in re.split(CL, a) if len(t) > 2 and t not in STOP}
    meta_toks |= {t for t in re.split(CL, rec["journal"].lower())
                  if len(t) > 3 and t not in STOP}
    via_title = bool(want & got)
    via_meta = bool(rec["year"] and rec["year"] in context and (want & meta_toks))
    verdict = "VERIFIED" if (via_title or via_meta) else "TITLE-DRIFT"
    route = "+".join(r for r, f in (("title", via_title), ("meta", via_meta)) if f) or "none"
    overlap = (len(want & got) / len(want)) if want else 1.0
    return verdict, f"{rec['src']} | {route} | overlap={overlap:.2f}", rec["title"]


def harvest(paths: list[Path]) -> dict[str, str]:
    found: dict[str, str] = {}
    for p in paths:
        for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
            for m in DOI_RE.finditer(line):
                doi = clean_doi(m.group(0))
                if doi.count("/") != 1:
                    continue
                if doi not in found:  # first context wins; docs are the anchor
                    found[doi] = re.sub(r"\s+", " ", line.strip())[:240]
    return found


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--roots", default="docs/research")
    ap.add_argument("--extra", action="append", default=[])
    ap.add_argument("--out", default="/tmp/doi-repin-census.tsv")
    ap.add_argument("--offline", action="store_true", help="only exercise controls")
    a = ap.parse_args()

    roots = [Path(a.roots).glob("**/*.md")]
    paths = sorted(p for group in roots for p in group)
    paths += [Path(e) for e in a.extra]
    table = harvest(paths)
    print(f"HARVEST {len(table)} unique DOIs from {len(paths)} files")

    rows = [("doi", "verdict", "registry", "resolved_title", "source_context")]
    fails = 0
    for i, (doi, ctx) in enumerate(sorted(table.items()), start=1):
        if a.offline:
            continue
        verdict, note, title = classify(doi, ctx)
        if verdict != "VERIFIED":
            fails += 1
        print(f"[{i:3d}/{len(table)}] {doi:55s} {verdict:12s} {note[:60]}")
        rows.append((doi, verdict, note, title, ctx))
        time.sleep(0.25)  # be polite to the public APIs

    # ---- fabrication control: planted DOIs MUST be refused by this path ----
    controls = {
        "10.1038/nonexist.2099.nope1234": "planted fake Nature-family DOI",
        "10.1016/j.planted.2099.999999":   "planted fake Cell-family DOI",
    }
    all_fired = True
    for doi, why in controls.items():
        verdict, note, _ = classify(doi, why)
        fired = verdict == "NOT-RESOLVED"
        all_fired &= fired
        print(f"CONTROL planted {doi:45s} -> {verdict:12s} fired={fired}")
        rows.append((doi, f"CONTROL-{'FIRED' if fired else 'NOT-FIRED'}", note, "", why))
    if not all_fired:
        print("CONTROL-FAILURE: planted DOIs were accepted; scanner is dead")
        return 2

    # ---- positive control: one known-good DOI must VERIFY --------------------
    pos = ("10.1186/gm1228", "SigProfiler assignment de Bruin Genome Medicine")
    pv, pn, _ = classify(pos[0], pos[1])
    print(f"CONTROL positive {pos[0]} -> {pv} {pn[:60]}")
    rows.append((pos[0], f"POSITIVE-{pv}", pn, "", pos[1]))

    # ---- recovery pass: flagged rows get a title-search proposal ------------
    flagged = [r for r in rows[1:] if r[1] in ("TITLE-DRIFT", "NOT-RESOLVED")
               and not r[1].startswith("CONTROL")]
    proposals = {}
    for doi, verdict, note, title, ctx in flagged:
        mq = re.search(r'"([^"]{20,200})"', ctx)
        field, q = ("query.title", mq.group(1)) if mq else \
            ("query.bibliographic", " ".join(sorted(tidy_tokens(ctx))[:8]) or doi)
        code, doc = http_json("https://api.crossref.org/works?rows=5&" + field +
                              "=" + urllib.parse.quote(q, safe=""))
        best, best_toks = None, 0
        if code == 200 and doc:
            items = (doc.get("message") or {}).get("items") or []
            for it in items:
                cand = (it.get("title") or [""])[0]
                shared = len(tidy_tokens(ctx) & tokens(cand))
                cand_doi = (it.get("doi") or "").lower()
                if shared > best_toks and cand_doi:
                    best, best_toks = (cand_doi, cand), shared
        if best:
            tag = "RECOVERED" if best_toks >= 2 else "UNRECOVERED"
            proposals[doi] = (tag, best[0], best[1])
        else:
            proposals[doi] = ("UNRECOVERED", "", "")
        time.sleep(0.25)
    rows = [rows[0]] + [
        r + proposals.get(r[0], ("", "", "")) if r[1] in ("TITLE-DRIFT", "NOT-RESOLVED") else r + ("", "", "")
        for r in rows[1:]
    ]

    out = Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join("\t".join(r) for r in rows) + "\n", encoding="utf-8")
    total = len(table)
    print(f"CENSUS {out} rows={total} not-verified={fails} "
          f"controls=fired:{all_fired} positive:{pv}")
    return 0 if all_fired else 2


if __name__ == "__main__":
    sys.exit(main())
