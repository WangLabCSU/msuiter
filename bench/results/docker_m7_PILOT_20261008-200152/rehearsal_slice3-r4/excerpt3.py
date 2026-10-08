"""RB-05(4.ii) witness excerpter, rules v3 (data-driven, verified).

Documented, deterministic rules (header records them + full-file sha256):
  R1  carriage-return progress animation collapsed to its final frame;
  R2  C++ compiler diagnostic bodies dropped: line whose first non-blank
      text starts with 'warning:' or 'note:', include-chain continuations
      starting with 'from ', 'in ', 'required from ', 'declared here',
      and code-gutter lines matching 'NNN |';
  R3  shape-noise windows: a line's SHAPE is the line with every digit run
      replaced by '9', truncated to its first 48 bytes. Shapes occurring
      at least 150 times are storm noise: the first 20 and last 40
      occurrences of each storm shape are kept verbatim; the suppressed
      middle becomes one '[... +N suppressed of storm shape ...]' marker.
  R4  every other line kept verbatim, order preserved.
"""
import collections
import hashlib
import re
import sys

def cr_collapse(raw: bytes) -> bytes:
    out = []
    for seg in raw.split(b"\n"):
        head, _, tail = seg.rpartition(b"\r")
        out.append(tail if head else seg)
    return b"\n".join(out)

R2_PREFIXES = (b"warning:", b"note:", b"from ", b"in ", b"required from ",
               b"declared here")
GUTTER = re.compile(rb"^[ ]*[0-9]+ [|]")
DIGITS = re.compile(rb"[0-9]+")
STORM_MIN, KEEP_HEAD, KEEP_TAIL, SHAPE_MAX = 150, 20, 40, 48

def is_r2(ln: bytes) -> bool:
    s = ln.strip()
    return any(s.startswith(p) for p in R2_PREFIXES) or bool(GUTTER.match(s))

def shape(ln: bytes) -> bytes:
    return DIGITS.sub(b"9", ln)[:SHAPE_MAX]

def excerpt(raw: bytes):
    lines = cr_collapse(raw).split(b"\n")
    idx = [i for i, ln in enumerate(lines) if not is_r2(ln)]
    by_shape = collections.defaultdict(list)
    for i in idx:
        by_shape[shape(lines[i])].append(i)
    keep = set()
    markers = {}
    dropped_diag = len(lines) - len(idx)
    for sh, hits in by_shape.items():
        if len(hits) < STORM_MIN:
            keep.update(hits)
        else:
            keep.update(hits[:KEEP_HEAD])
            keep.update(hits[-KEEP_TAIL:])
            mid = hits[KEEP_HEAD:len(hits) - KEEP_TAIL]
            if mid:
                markers[mid[len(mid) // 2]] = (sh, len(mid))
    out = []
    for i in idx:
        if i in markers:
            sh, n = markers[i]
            out.append(b"[... +" + str(n).encode() + b" suppressed of storm shape '"
                       + sh + b" ...]")
        elif i in keep:
            out.append(lines[i])
    return b"\n".join(out), dropped_diag, len(markers)

src, dst = sys.argv[1], sys.argv[2]
raw = open(src, "rb").read()
body, dropped, storms = excerpt(raw)
head = (
    f"## RB-05(4.ii) promoted witness -- documented rules excerpt v3:\n"
    f"## R1 CR-progress collapsed; R2 C++ diagnostic bodies dropped ({dropped}\n"
    f"## lines); R3 storm shapes (>={STORM_MIN} repeats, digit-masked 48-byte\n"
    f"## prefix key) kept head {KEEP_HEAD}/tail {KEEP_TAIL}, middle collapsed\n"
    f"## into {storms} markers; R4 all else verbatim, order preserved.\n"
    f"## full-file sha256 of the UNtrimmed original:\n"
    f"## {hashlib.sha256(raw).hexdigest()}\n"
    f"## (original retained on the controller host at {src})\n"
).encode()
open(dst, "wb").write(head + body)
print(f"{src} -> {dst}: raw={len(raw)} out={len(head)+len(body)}"
      f" dropped_diag={dropped} storm_markers={storms}")
