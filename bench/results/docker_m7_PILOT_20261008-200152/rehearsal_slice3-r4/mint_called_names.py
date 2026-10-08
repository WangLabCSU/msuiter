"""RB-05(5): extract called-name tokens from the rehearsed runner bytes.

Host-side deterministic scan (exact bytes via tool transport); the container
step that consumes this file only performs get()/formals()/where() lookups.
"""
import re
import sys

SRC = "/tmp/m7probe/runcell/run_sigminer_fixed.R"
OUT = "/tmp/m7probe/runcell/called_names.txt"
CALL = re.compile(r"([A-Za-z.][A-Za-z0-9._]*)[ \t]*\(")
KEYWORDS = frozenset({"if", "for", "while", "function", "in", "next", "break",
                      "repeat", "else", "TRUE", "FALSE", "NULL", "force",
                      "library", "require"})

text = open(SRC, encoding="utf-8").read()
# strip full-line comments before scanning (leading # to EOL)
body = "\n".join(re.sub(r"#.*$", "", line) for line in text.splitlines())
toks = sorted(set(CALL.findall(body)) - KEYWORDS)
with open(OUT, "w", encoding="utf-8") as fh:
    for t in toks:
        fh.write(f"{t}\n")
print(f"wrote {len(toks)} called names; commandArgs present:",
      "commandArgs" in toks)
