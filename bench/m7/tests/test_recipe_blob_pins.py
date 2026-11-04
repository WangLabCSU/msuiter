#!/usr/bin/env python3
"""Group (AM) test_recipe_blob_pins -- reading test for the P6 arm-recipe digest pins.

DEBT-BUILD-PIN-DRIFT, controller remedy (b) (ruling 2026-11-04): every digest pin
in bench/m7/adapters/Dockerfile.sigminer.tree must be a git BLOB digest -- the
sha256 of the named source file as git stores it at a named sealing commit -- and
this module re-measures every pin along the full trust triangle on every suite run:

  (i)   the constant against the blob at its own seal commit  (the pin means
        "these bytes at that commit");
  (ii)  the constant against the blob at HEAD                  (the drift
        detector: a mainline move that does not re-seal dies here);
  (iii) the constant against the on-disk adapter bytes         (the bake reality:
        p6_build_arms.FLAT_INPUTS stages those bytes into the COPY context);
  (iv)  the seal commit against the file's last-touch commit    (the seal names
        the current lineage head, not a remembered id).

The failure this gate exists to end is measured history: the frozen launcher
(m7_entry.py) moved at 1673a7f (PR #31) and again at 54c58d7 while the recipe
pin still spoke the bytes of its origin commit 2949e8a, and the whole suite
stayed green for sixteen days because nothing but the recipe itself read the pin.
A digest that no unit reads is a decorative gate; the positive-control unit here
replays exactly that dead-pin shape, measured, and demands the gate reject it.

No digest string is typed anywhere in this module -- every expected value flows
through the explicit-algorithm recorder over git or disk bytes (RB-06 idiom),
and the tamper units derive their defects from the measured values. The
launcher's attested three-move lineage is pinned by value: a fourth unattested
move reddens the suite, which is the drift attestation the companion ledger owes.
"""

from __future__ import annotations

import hashlib
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from tools import p6_build_arms                      # noqa: E402

REPO = HERE.parents[1]                               # msuiter repo root
ADAPTERS = HERE / "adapters"
RECIPE_REL = "bench/m7/adapters/Dockerfile.sigminer.tree"
RECIPE = ADAPTERS / "Dockerfile.sigminer.tree"
RECIPE_SELF = "Dockerfile.sigminer.tree"             # self-referential: never pinned
LAUNCHER_REL = "bench/m7/adapters/m7_entry.py"
LAUNCHER = "m7_entry.py"
WORK_ENTRY = "/work/m7_entry.py"
FLAT = frozenset(p6_build_arms.FLAT_INPUTS)

# The seal form the re-seal lane writes above every pin site; one seal binds
# exactly one site, path-and-commit spoken, full 40-hex.
SEAL_RE = re.compile(
    r"^#\s*blob-pin\s+(bench/m7/adapters/[A-Za-z0-9._-]+)\s+@\s+([0-9a-f]{40})\s*$")
COPY_RE = re.compile(r"^COPY\s+(\S+)\s+(\S+)\s*$")
SITE_RE = re.compile(
    r'RUN\s+test\s+"\$\(sha256sum\s+(/\S+)\s*\|.*?"\s*=\s*"([0-9a-f]{64})"')
HEX64_RE = re.compile(r"[0-9a-f]{64}")

# The launcher's attested drift history, oldest first, pinned by value
# (docs/devlog/2026-11-04-m7-build-pin-drift-attestation.md): origin seal, then
# the two moves the stale pin missed. A fourth touch reddens the lineage unit --
# moving the launcher is only lawful together with a re-seal and an attestation.
ATTESTED_LAUNCHER_MOVES = (
    "2949e8a7ca626229d800396a2b2b96a6fe8773d2",     # bytes at the origin seal
    "1673a7f6aa3451e4a8fac1918bf927e3d8130fc6",     # unwatched move #1 (#31)
    "54c58d70dfb5057f5089d21c5afffb46d4716118",     # unwatched move #2 (signeR)
)


def _sha(data: bytes) -> str:
    """The explicit-algorithm recorder: every expected digest passes here."""
    return hashlib.sha256(data).hexdigest()


def _git_bytes(*argv: str) -> bytes:
    proc = subprocess.run(("git", "-C", str(REPO), *argv), capture_output=True)
    if proc.returncode != 0:
        raise RuntimeError(f"git {' '.join(argv)} exited {proc.returncode}: "
                           f"{proc.stderr.decode('utf-8', 'replace')}")
    return proc.stdout


def _blob(rel: str, rev: str) -> bytes:
    return _git_bytes("show", f"{rev}:{rel}")


def _touches(rel: str) -> list[str]:
    return _git_bytes("log", "--format=%H", "HEAD", "--", rel).decode("ascii").split()


def _disk(name: str) -> bytes:
    return (ADAPTERS / name).read_bytes()


def _flip_last_hex(hexstr: str) -> str:
    """Mutate the final hex digit -- defects derived from measured values."""
    digits = "0123456789abcdef"
    idx = max(i for i, ch in enumerate(hexstr) if ch in digits)
    return hexstr[:idx] + format(int(hexstr[idx], 16) ^ 1, "x") + hexstr[idx + 1:]


def _logical_lines(raw: list[str]) -> list[tuple[int, str]]:
    """Fold backslash-continuations so a pin site is matchable as one line."""
    out, joined, start = [], "", None
    for no, line in enumerate(raw, start=1):
        if line.endswith("\\"):
            if start is None:
                start = no
            joined += line[:-1]
            continue
        out.append((no if start is None else start, joined + line))
        joined, start = "", None
    if joined:
        out.append((start, joined))
    return out


def _parse(text: str) -> tuple[list[dict], dict[str, str], list[dict]]:
    """Scan one recipe text into (sites, copies, flags). Pure."""
    sites: list[dict] = []
    copies: dict[str, str] = {}
    flags: list[dict] = []
    pending_seal: tuple[int, str, str] | None = None
    for lineno, line in _logical_lines(text.splitlines()):
        stripped = line.strip()
        if stripped.startswith("#"):
            seal = SEAL_RE.match(stripped)
            if seal:
                if pending_seal is not None:
                    flags.append({"check": "orphan-seal",
                                 "detail": f"seal {pending_seal[1]} @{pending_seal[2][:12]} "
                                           f"(line {pending_seal[0]}) backs no pin site"})
                pending_seal = (lineno, seal.group(1), seal.group(2))
            continue
        copy = COPY_RE.match(stripped)
        if copy:
            src, dest = copy.group(1), copy.group(2)
            if "/" in src or src.startswith("$"):
                continue                       # tree dirs and build-arg faces: other laws
            copies[dest + src if dest.endswith("/") else dest] = src
            continue
        site = SITE_RE.search(stripped)
        if site:
            sites.append({"first_lineno": lineno, "dest": site.group(1),
                          "constant": site.group(2),
                          "src": copies.get(site.group(1)),
                          "seal": pending_seal})
            pending_seal = None               # one seal binds one site
    if pending_seal is not None:
        flags.append({"check": "orphan-seal",
                      "detail": f"seal {pending_seal[1]} @{pending_seal[2][:12]} "
                                f"(line {pending_seal[0]}) backs no pin site"})
    return sites, copies, flags


def _flag(flags: list[dict], check: str, site: dict | None, **fields) -> None:
    entry = {"check": check}
    if site is not None:
        entry.update({"dest": site["dest"], "src": site["src"]})
    entry.update(fields)
    flags.append(entry)


def _gate(text: str, blob, disk, touches, flat: frozenset[str]) -> list[dict]:
    """The whole law over injected byte authorities. Pure and tamperable."""
    sites, copies, flags = _parse(text)
    for site in sites:
        src, constant, seal = site["src"], site["constant"], site["seal"]
        if src is None:
            _flag(flags, "site-without-copy", site,
                  detail=f"no COPY of a context file feeds {site['dest']}")
            continue
        if src not in flat:
            _flag(flags, "site-src-not-a-declared-build-input", site,
                  detail=f"{src} is not in p6_build_arms.FLAT_INPUTS")
        src_rel = f"bench/m7/adapters/{src}"
        if constant != _sha(disk(src)):
            _flag(flags, "constant-vs-disk", site,
                  detail=f"pin {constant} vs disk bytes {_sha(disk(src))}")
        if constant != _sha(blob(src_rel, "HEAD")):
            _flag(flags, "constant-vs-blob-at-head", site,
                  detail=f"pin {constant} vs blob@HEAD {_sha(blob(src_rel, 'HEAD'))}")
        if seal is None:
            _flag(flags, "unsealed-pin-site", site,
                  detail=f"{site['dest']} carries no '# blob-pin <path> @ <commit>' seal")
            continue
        _, seal_rel, seal_commit = seal
        if seal_rel != src_rel:
            _flag(flags, "seal-path-disagrees-with-copy", site,
                  detail=f"seal speaks {seal_rel}, the COPY feeds {src_rel}")
        if constant != _sha(blob(seal_rel, seal_commit)):
            _flag(flags, "constant-vs-blob-at-seal-commit", site,
                  detail=f"pin {constant} vs blob@{seal_commit[:12]} "
                         f"{_sha(blob(seal_rel, seal_commit))}")
        head_touches = touches(seal_rel)
        if not head_touches or head_touches[0] != seal_commit:
            head = head_touches[0] if head_touches else "<none>"
            _flag(flags, "seal-commit-is-not-lineage-head", site,
                  detail=f"seal names {seal_commit[:12]}, last touch of "
                         f"{seal_rel} is {head[:12]}")
    pinned_dests = {site["dest"] for site in sites}
    for dest, src in copies.items():
        if src in flat and src != RECIPE_SELF and dest not in pinned_dests:
            _flag(flags, "unpinned-copy", None, dest=dest, src=src,
                  detail=f"COPY {src} -> {dest} rides the context byte-unpinned")
    backed = {site["constant"] for site in sites}
    for literal in sorted(set(HEX64_RE.findall(text)) - backed):
        _flag(flags, "unbacked-digest-literal", None,
              detail=f"{literal} appears in the recipe backing no pin site")
    return flags


def _live_text() -> str:
    return RECIPE.read_text(encoding="utf-8")


def _live_flags(text: str | None = None) -> list[dict]:
    return _gate(text if text is not None else _live_text(),
                 blob=_blob, disk=_disk, touches=_touches, flat=FLAT)


def _flags_for(flags: list[dict], dest: str) -> set[str]:
    return {f["check"] for f in flags if f.get("dest") == dest}


def _site(dest: str) -> dict:
    sites, _, _ = _parse(_live_text())
    matches = [s for s in sites if s["dest"] == dest]
    assert len(matches) == 1, f"expected exactly one pin site for {dest}, got {len(matches)}"
    return matches[0]


def _insert_before(text: str, needle: str, added: str) -> str:
    lines = text.splitlines(keepends=True)
    for i, line in enumerate(lines):
        if needle in line and line.startswith("RUN "):
            lines.insert(i, added if added.endswith("\n") else added + "\n")
            return "".join(lines)
    raise AssertionError(f"pin site {needle!r} not found in the arm recipe")


# -- the live law ---------------------------------------------------------------

def test_every_pin_site_is_sealed_and_resolves_verbatim():
    """The headline gate: zero flags over the live recipe. Every site resolves
    against its seal commit, HEAD, disk and lineage head, and nothing else is
    scored -- this is the unit that must redden on any pin drift."""
    assert _live_flags() == [], _live_flags()


def test_every_declared_build_input_copy_is_pinned():
    """No FLAT_INPUTS member may ride the build context byte-unpinned: the
    asymmetry that hid the drift (R faces exiting before layer 18) dies here."""
    flags = _live_flags()
    unpinned = [f for f in flags if f["check"] == "unpinned-copy"]
    assert unpinned == [], unpinned
    sites, _, _ = _parse(_live_text())
    pinned = {s["src"] for s in sites if s["src"]}
    assert (FLAT - {RECIPE_SELF}) <= pinned, sorted(FLAT - {RECIPE_SELF} - pinned)


def test_no_digest_literal_lacks_a_pin_backing():
    """Every 64-hex literal in the recipe is the constant of a sealed pin site
    -- the hash-provenance backing law over this file (no orphan constants)."""
    sites, _, _ = _parse(_live_text())
    assert sites, "the arm recipe carries no digest pin sites at all"
    unbacked = [f for f in _live_flags() if f["check"] == "unbacked-digest-literal"]
    assert unbacked == [], unbacked


def test_launcher_lineage_is_the_attested_three_moves():
    """m7_entry.py may never gain a fourth silent touch: a mainline move
    requires a re-seal and a ledger entry, this unit is the trip-wire."""
    assert _touches(LAUNCHER_REL) == list(reversed(ATTESTED_LAUNCHER_MOVES))


# -- the tamper units (defects derived from measured values) ---------------------

def test_gate_flags_a_tampered_pin_constant():
    """A single flipped digit on the launcher pin must fire every byte side
    the site can speak: disk and head always, the seal-commit side whenever a
    seal binds the site (the TDD face without seals asserts the two)."""
    site = _site(WORK_ENTRY)
    tampered = _live_text().replace(
        f'"{site["constant"]}"', f'"{_flip_last_hex(site["constant"])}"', 1)
    checks = _flags_for(_live_flags(tampered), WORK_ENTRY)
    required = {"constant-vs-disk", "constant-vs-blob-at-head"}
    if site["seal"] is not None:
        required |= {"constant-vs-blob-at-seal-commit"}
    assert required <= checks, checks


def test_gate_flags_disk_drift_under_a_sealed_pin():
    """The bake-reality side: context bytes moving without a re-seal fire the
    disk flag on the launcher site on top of the baseline face (stage-1's
    already-dead pin keeps its own flags; the re-seal face proves the delta)."""
    def disk_drift(src: str) -> bytes:
        return _disk(src) + b"\n" if src == LAUNCHER else _disk(src)
    flags = _gate(_live_text(), blob=_blob, disk=disk_drift, touches=_touches,
                  flat=FLAT)
    base = _flags_for(_live_flags(), WORK_ENTRY)
    assert _flags_for(flags, WORK_ENTRY) >= base | {"constant-vs-disk"}, flags


def test_gate_flags_mainline_blob_drift_under_a_sealed_pin():
    """The sixteen-day window, made detectable before bake time: the HEAD blob
    moving without a re-seal fires the head flag on top of the baseline face."""
    def blob_drift(rel: str, rev: str) -> bytes:
        data = _blob(rel, rev)
        return data + b"\n" if rev == "HEAD" and rel == LAUNCHER_REL else data
    flags = _gate(_live_text(), blob=blob_drift, disk=_disk, touches=_touches,
                  flat=FLAT)
    base = _flags_for(_live_flags(), WORK_ENTRY)
    assert _flags_for(flags, WORK_ENTRY) >= base | {"constant-vs-blob-at-head"}, flags


def test_gate_flags_an_unsealed_pin_site():
    """Stripping a site's seal comment is a suite death, not a silent revert
    to bake-only enforcement."""
    site = _site(WORK_ENTRY)
    tampered = _live_text()
    if site["seal"] is not None:
        _, seal_rel, seal_commit = site["seal"]
        tampered = tampered.replace(f"# blob-pin {seal_rel} @ {seal_commit}\n", "", 1)
    checks = _flags_for(_live_flags(tampered), WORK_ENTRY)
    assert "unsealed-pin-site" in checks, checks


def test_gate_flags_an_unpinned_copy():
    """A COPY that loses its pin layer is completeness death on both sides:
    the dest becomes an unpinned ride and the orphan site has no feeding COPY."""
    renegade = "COPY install_sigminer_arm.R /work/install_sigminer_arm.R\n"
    tampered = _live_text().replace(
        renegade, "COPY install_sigminer_arm.R /work/install_sigminer_arm_orphan.R\n")
    flags = _live_flags(tampered)
    assert any(f["check"] == "unpinned-copy" for f in flags), flags
    assert "site-without-copy" in _flags_for(flags, "/work/install_sigminer_arm.R")


def test_gate_flags_a_stale_seal_commit():
    """A seal that names an older touch of its own file dies on the lineage
    check and on the blob-at-seal-commit check together."""
    stale = _touches(LAUNCHER_REL)[1]
    tampered = _insert_before(
        _live_text(), f"sha256sum {WORK_ENTRY}",
        f"# blob-pin {LAUNCHER_REL} @ {stale}")
    checks = _flags_for(_live_flags(tampered), WORK_ENTRY)
    assert {"seal-commit-is-not-lineage-head",
            "constant-vs-blob-at-seal-commit"} <= checks, checks


# -- the forensics control (the dead pin this gate was written for) ---------------

def test_control_the_origin_sealed_launcher_pin_is_rejected_today():
    """Measured replay of DEBT-BUILD-PIN-DRIFT § 3: at the recipe's own first
    commit the launcher pin re-measured honest against the launcher's origin
    bytes (born at 2949e8a), and today the same constant is dead against the
    disk bytes -- and this gate rejects it in both directions, end to end
    computed, so the 7ce0c147-vs-5abcb21e class can never sit green again."""
    touches = _touches(RECIPE_REL)
    assert touches, "the arm recipe has no committed history at all"
    origin = touches[-1]          # the pin text's first rider (measured recipe
    # history, NOT the launcher's origin narrative -- attested in
    # docs/devlog/2026-11-04-m7-build-pin-drift-attestation.md; the launcher's
    # own origin commit is computed from its own git log below, never quoted).
    origin_recipe = _blob(RECIPE_REL, origin).decode("utf-8")
    origin_sites, _, _ = _parse(origin_recipe)
    origin_site = next(s for s in origin_sites if s["dest"] == WORK_ENTRY)
    # The launcher's own origin commit comes from its git log, never from the
    # narrative; the pin must speak the file's bytes AT that origin.
    file_origin = _touches(LAUNCHER_REL)[-1]
    assert file_origin == ATTESTED_LAUNCHER_MOVES[0], file_origin
    assert origin_site["constant"] == _sha(_blob(LAUNCHER_REL, file_origin))
    assert origin_site["constant"] == _sha(_blob(LAUNCHER_REL, origin))     # honest at seal
    assert origin_site["constant"] != _sha(_disk(LAUNCHER))               # dead today
    tampered = _live_text().replace(f'"{_site(WORK_ENTRY)["constant"]}"',
                                    f'"{origin_site["constant"]}"', 1)
    checks = _flags_for(_live_flags(tampered), WORK_ENTRY)
    assert {"constant-vs-disk", "constant-vs-blob-at-head"} <= checks, checks
