"""⑪ sigminer adapter API-contract pin (slice-3, memo §9c.2/§9d).

The slice-2 forensics proved the shipped adapter chain ran on a fictional
"documented API" (signature_extract / fitsignatures / signature_import /
signature_renorm / set.seed — 0/5 in the CRAN 2.3.1 NAMESPACE, every
published version, tree-wide). These units pin the realigned chain against
the witnessed truth so fiction can never re-enter silently:

* the contract fixture is the verbatim ``export(...)`` stanza of the
  2.3.1 Archive NAMESPACE (witness: the build-log tarball URL, sha256
  b2836c76..1953b; the fixture's own hash is pinned below);
* the five fictional names are eradicated from the whole chain
  (run_sigminer.R / install_sigminer.R / sigminer_adapter.py);
* every ``sig_*``/``bp_*`` call site in the R runner resolves inside the
  witnessed export set;
* the build guard verifies the witnessed contract from the resolver's own
  fetched tarball bytes — with a sha256 tripwire — and its CORE_API
  subset (shared verbatim with the runner) covers the real extraction/
  assignment family;
* the exact-version pin and the NaN-not-zero-width interval honesty
  (house convention from the SigProfiler sibling runner) hold;
* the seed flows through the package's DOCUMENTED ``seed`` parameter —
  the fictional "sigminer set.seed entry point" claim stays dead.

Host-side text/fixture contract only: no R, no docker, no build dollars.
"""

from __future__ import annotations

import hashlib
import re
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]                 # bench/m7
ADAPTERS = HERE / "adapters"
FIXTURE = (HERE / "tests" / "fixtures" /
           "sigminer_2.3.1_namespace_exports.txt")

RUNNER = (ADAPTERS / "run_sigminer.R").read_text(encoding="utf-8")
INSTALLER = (ADAPTERS / "install_sigminer.R").read_text(encoding="utf-8")
PY_ADAPTER = (HERE / "competitors" / "sigminer_adapter.py").read_text(
    encoding="utf-8")

# The five fictional names (slice-2 §9c.2 fact-check: 0/5 across every
# published sigminer version; internal provenance = the old runner's own
# false "documented API" premise).
FICTIONAL = ("set.seed", "signature_extract", "fitsignatures",
             "signature_import", "signature_renorm")

# The extraction/assignment family the realigned chain drives — witnessed
# verbatim in the 2.3.1 NAMESPACE (slice-2 fact-check).
CORE_API = ("bp_extract_signatures", "bp_get_sig_obj", "bp_get_stats",
            "sig_extract", "sig_fit", "sig_fit_bootstrap", "sig_estimate",
            "sig_exposure", "sig_names")

# Contract fixture provenance (written from the witnessed tarball, §9d):
# Archive/sigminer/sigminer_2.3.1.tar.gz, sha256
# b2836c76a52f7c7add8756afb09dc50ab31d736b4640b803bee57b6caec1953b.
FIXTURE_SHA256 = ("2168cf32059f09c2e12cf3f82cb9befc9b15a58883c92f"
                  "a3473c462671927948")
FIXTURE_EXPORT_LINES = 115
# Full sigminer/NAMESPACE bytes of that tarball (import/S3 stanzas included)
# — the identical constant the build guard carries as its own tripwire.
NAMESPACE_SHA256 = ("37744aee7eb63c89501109f50da4b5a7155d4912bc5540"
                    "cda8764062866a90df")


def _fixture_exports() -> frozenset[str]:
    names = set()
    for line in FIXTURE.read_text(encoding="utf-8").splitlines():
        m = re.fullmatch(r"export\(([^()]+)\)$", line.strip())
        assert m, f"fixture line is not a verbatim export() stanza: {line!r}"
        names.add(m.group(1))
    return names


def _r_code_only(src: str) -> str:
    """Strip R comment tails — contract claims live in code, prose may
    name the fiction precisely to prohibit it."""
    return "\n".join(re.sub(r"(?<!\\)#.*$", "", ln) for ln in src.splitlines())


def test_fixture_is_the_witnessed_verbatim_namespace():
    raw = FIXTURE.read_bytes()
    got = hashlib.sha256(raw).hexdigest()
    assert got == FIXTURE_SHA256, (
        f"contract fixture drifted from the witnessed 2.3.1 NAMESPACE: "
        f"{got} != {FIXTURE_SHA256}")
    lines = [l for l in raw.decode("utf-8").splitlines() if l.strip()]
    assert len(lines) == FIXTURE_EXPORT_LINES, (
        f"expected {FIXTURE_EXPORT_LINES} verbatim export() lines, "
        f"got {len(lines)}")
    exports = _fixture_exports()
    assert all(name in exports for name in CORE_API), (
        "the witnessed NAMESPACE must contain the real extraction/"
        "assignment family")


def test_fictional_api_eradicated_chain_wide():
    for name, src in (("run_sigminer.R", RUNNER),
                      ("install_sigminer.R", INSTALLER),
                      ("sigminer_adapter.py", PY_ADAPTER)):
        code = _r_code_only(src) if name.endswith(".R") else src
        for bad in FICTIONAL:
            assert bad not in code, (
                f"{name}: fictional sigminer API name {bad!r} resurrected — "
                f"0/5 in the witnessed NAMESPACE (slice-2 §9c.2)")


def test_runner_calls_only_witnessed_exports():
    code = _r_code_only(RUNNER)
    assert "library(sigminer)" in code, "runner must load the pinned package"
    called = set(re.findall(r"\b((?:sig|bp)_[a-z0-9_]+)\s*\(", code))
    assert called, "the realigned runner must drive the sig_*/bp_* family"
    rogue = called - _fixture_exports()
    assert not rogue, (
        f"runner calls un-witnessed package entries: {sorted(rogue)}")
    assert "bp_extract_signatures" in called and "bp_get_sig_obj" in called, (
        "the NMF extraction sequence must run the documented best-practice "
        "entry points")


def test_installer_guard_verifies_from_the_fetched_witness():
    exports = _fixture_exports()
    # the build gate derives the export contract from the resolver's OWN
    # downloaded bytes (no refetch, no second copy to drift):
    assert re.search(r'INSTALLED_TF\[\["sigminer"\]\]', INSTALLER), \
        "installer must stash the fetched root tarball for the tail assert"
    assert re.search(r'untar\(tf,\s*exdir\s*=\s*exd,\s*files\s*=\s*'
                     r'"sigminer/NAMESPACE"\)', INSTALLER), \
        "tail assert must read the NAMESPACE out of the witnessed tarball"
    assert re.search(r'contract\s*<-\s*sub\("\^export\\\\\(', INSTALLER), \
        "tail assert must parse the verbatim export() stanza"
    assert "witnessed sigminer export missing" in INSTALLER
    assert re.search(r"length\(contract\)\s*<\s*100L", INSTALLER), \
        "a thinned-out witness must stop the build"
    # hash tripwire: a re-routed or swapped artifact dies on bytes, not
    # trust — over the coreutils channel (base R 4.3.3 has no digest(); the
    # slice-3 pre-flight proved that live on the build base)
    assert re.search(rf'NS_SHA256\s*<-\s*"{NAMESPACE_SHA256}"', INSTALLER), \
        "the build guard must carry the witnessed NAMESPACE hash"
    assert 'sha256File <- function' in INSTALLER and \
        'system2("sha256sum"' in INSTALLER, \
        "the hash channel must be the zero-dependency coreutils one"
    assert re.search(r'sha256File\(nsf\)', INSTALLER), \
        "the tail assert must hash the witnessed bytes before trusting them"
    # core family: installer and runner agree, and both stay inside the witness
    m2 = re.search(r"CORE_API\s*<-\s*c\((.*?)\)", INSTALLER, re.S)
    assert m2, "installer must function-assert the core family"
    m3 = re.search(r"CORE_API\s*<-\s*c\((.*?)\)", _r_code_only(RUNNER), re.S)
    assert m3, "runner must function-assert the core family"
    core_i = frozenset(re.findall(r'"([^"]+)"', m2.group(1)))
    core_r = frozenset(re.findall(r'"([^"]+)"', m3.group(1)))
    assert core_i == core_r, "guard/runner core families must not drift apart"
    assert core_i <= exports and set(CORE_API) <= core_i, (
        "CORE_API must stay inside the witness and cover the real family")


def test_exact_version_pin_survives_realignment():
    assert re.search(r'identical\(v(ersion)?\s*,\s*"2\.3\.1"\)', INSTALLER), \
        "installer lost the exact-version pin assert"
    assert re.search(r'identical\(version,\s*"2\.3\.1"\)', RUNNER), \
        "runner lost the exact-version pin guard"


def test_absent_intervals_emit_nan_never_zero_width():
    code = _r_code_only(RUNNER)
    assert not re.search(
        r'sprintf\("%\.4f",\s*v\),\s*sprintf\("%\.4f",\s*v\),\s*'
        r'sprintf\("%\.4f",\s*v\)', code), (
        "zero-width interval masquerade (estimate duplicated into lo/hi) "
        "is prohibited — house convention: absent bounds are NaN")
    assert re.search(r"\bNaN\b", code), (
        "the table writer must emit NaN for intervals the package does not "
        "report")
    assert '"absolute"' in code, (
        "the documented absolute-exposure estimand must stay declared")


def test_seed_flows_through_documented_parameter_only():
    code = _r_code_only(RUNNER)
    assert re.search(r"bp_extract_signatures\(", code) and \
        re.search(r"seed\s*=\s*seed", code), (
        "the reproducible-run lever is the package's documented seed "
        "parameter (its own docstring: 'a random seed to make reproducible "
        "result')")
    for prose in ("sigminer::set.seed", "documented `set.seed()"):
        assert prose not in RUNNER, (
            f"the fictional seed-entry-point claim ({prose!r}) must stay "
            f"dead — 0 occurrences in the witnessed NAMESPACE")


def test_guard_resolves_operator_stanzas_dequoted():
    """build8 death 2026-10-08 (log /tmp/m7_sigminer_build8.log, tail
    FATAL 'witnessed sigminer export missing: \"%>%\"'). The NAMESPACE
    grammar quotes non-syntactic export names — the witnessed bytes carry
    exactly export("%>%") and export(":=") — and exists() looks up
    BINDING names, so the stanza quotes must come off before resolution
    (host repro /tmp/m7_dl/repro_dequote.R: %in% and <- resolve clean on
    baseenv, the quote-embedded forms never resolve; the live host
    sigminer namespace answers TRUE only to the clean operator names).
    Pinned here so the guard parser can never regress into the quote trap.
    """
    # (a) witness shape: the two operator stanzas verbatim in the
    #     byte-pinned fixture — the fixture MUST stay verbatim, the
    #     dequote belongs to the consuming guard, not the witness.
    raw = FIXTURE.read_text(encoding="utf-8").splitlines()
    assert 'export("%>%")' in raw and 'export(":=")' in raw, (
        "the witnessed NAMESPACE carries the pipe and assignment operator "
        "stanzas — the fixture must stay verbatim")
    # (b) the guard pipeline: parse -> DEQUOTE -> resolve, normalization
    #     strictly before the exists() loop (anchor: its unique for-loop).
    assert "sub('^\"(.*)\"$'," in INSTALLER and 'sub("^`(.*)`$",' in INSTALLER, (
        "the tail assert must strip NAMESPACE quoting from the parsed "
        "contract before exists() resolution (build8 root cause)")
    i_norm = INSTALLER.find("sub('^\"(.*)\"$',")
    i_loop = INSTALLER.find("for (fn in contract)")
    assert 0 <= i_norm < i_loop, (
        "the dequote normalization must sit BEFORE the exists() resolve loop")
    # (c) the algorithm over the fixture bytes: all 115 clean, zero
    #     quote-embedded, both operators present as real binding names.
    contract = [re.sub(r"^export\((.*)\)$", r"\1", ln.strip())
                for ln in raw if ln.strip().startswith("export(")]
    assert len(contract) == FIXTURE_EXPORT_LINES, (
        "fixture stanza count drifted from the witnessed 115")
    fixed = [re.sub(r'^"(.*)"$', r"\1", re.sub(r"^`(.*)`$", r"\1", c))
             for c in contract]
    assert not any(f.startswith(('"', "`")) for f in fixed), (
        "dequote left a quoted name — the exists() channel would FATAL again")
    assert "%>%" in fixed and ":=" in fixed and set(CORE_API) <= set(fixed), (
        "the resolved name set must cover the operators and the core family")
