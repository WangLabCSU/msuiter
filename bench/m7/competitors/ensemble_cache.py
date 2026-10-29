"""L3 hash-keyed ensemble cache (Phase-9 O1; Phase-6 O4 design sketch,
controller-adopted form).

The 100-member NMF bootstrap ensemble is a deterministic function of
(fixture bytes, frozen protocol constants, RNG regime, code-version token):
six independent post-cap container legs already reproduced byte-identical
intervals for one such cell (witness digest d202a833..., Phase-6 O3). A leg
that re-runs byte-identical inputs under byte-identical code is paying the
~970 s serialized floor to recompute a result that is reproducible by
construction. This module memoises AT THE CONTAINER-COMPOSITION POINT
(competitors._p6_common.run) — never inside the image — and is governed by
its adoption-gate clause:

  * OFF by default (advisory): only ``MSUITER_ENS_CACHE_DIR``, set by the
    operator to a directory OUTSIDE the tree, consults the cache. The
    campaign driver and the frozen gates never name the env (pinned tripwire
    in tests/test_ensemble_cache.py); an in-tree value is refused outright.
  * A key miss runs the ensemble — the fresh path is byte-for-byte today's
    path.
  * Only gate-passed legs populate: capture is reached only after
    ``docker_cmd.run_container_cell`` returned, i.e. guard files present and
    the timing sidecar schema-valid. A failed container raises past it.
  * Corruption is a miss, never a failure: an unparseable entry, a missing
    payload file or a file whose bytes disagree with the entry's digest map
    (truncated, rotated, wrong-key blob) refuses service SILENTLY and the
    leg simply recomputes. A cache may lose memoity; it may not lose truth.
  * A served leg stays truthful and separate: its sidecar carries
    ``"measurement": "cache-hit"`` with ~0 cpu (the copy cost), and the
    probe freshness law refuses to mint a floor witness from such a sidecar,
    so a replay can never pose as a measurement (RB-09 lineage).

Entry form: ``<cache>/keys/<key>/payload/`` (the cell's out bytes except the
sidecar) plus ``entry.json`` written LAST — the entry's existence is the
commit point; its digest map is re-verified on every serve.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import time
from pathlib import Path

from . import docker_cmd

CACHE_ENV = "MSUITER_ENS_CACHE_DIR"
#: Sidecar token marking a leg as served-from-cache, never a measurement.
CACHE_HIT_MEASUREMENT = "cache-hit"
#: Files the fresh path itself produces that must not ride the payload map:
#: the sidecar is re-minted per served leg; manifest.json is host-written by
#: run_bench after the adapter returns, outside this boundary.
_EXCLUDED = ("timing.json", "manifest.json")

_HERE = Path(__file__).resolve()
REPO_ROOT = _HERE.parents[3]                          # msuiter tree root


def cache_dir() -> Path | None:
    """The admissible cache root, or ``None`` when the cache is off.

    Off = env unset/blank, or the operator pointed it inside the tree (the
    frozen surfaces and the campaign cachedir must never host cache bytes).
    """
    raw = (os.environ.get(CACHE_ENV) or "").strip()
    if not raw:
        return None
    cand = Path(raw).resolve()
    try:
        cand.relative_to(REPO_ROOT)
        return None                              # in-tree placement: refused
    except ValueError:
        return cand


def enabled() -> bool:
    return cache_dir() is not None


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _key_payload(spec, in_dir: Path, catalog_mount, child_argv: list[str]) -> dict:
    """The all-or-nothing key components (Phase-6 O4 key law): fixture bytes,
    the code-version tokens, the execution-layer caps. params.json (frozen
    protocol constants + seed regime, including the caps echo) rides as
    fixture bytes; the catalog is bound by content whether it is staged in
    ``in/`` or mounted from its own read-only bind."""
    fixtures = {}
    for f in sorted(Path(in_dir).iterdir()):
        if f.is_file():
            fixtures[f.name] = _sha256(f)
    catalog_sha = None
    if catalog_mount is not None:
        catalog_sha = _sha256(Path(catalog_mount))
    return {
        "schema": 1,
        "fixtures": fixtures,
        "catalog_mount_sha": catalog_sha,
        "child_argv": list(child_argv),
        # code-version tokens: the image digest is the build, tree_sha/face
        # the attested sources behind it; entrypoint+runner the cell contract.
        "tool": spec.name,
        "version": spec.version,
        "runtime": spec.runtime,
        "image_digest": spec.image_digest,
        "tree_sha": getattr(spec, "tree_sha", ""),
        "face": getattr(spec, "face", ""),
        "entrypoint": spec.entrypoint,
        "runner_script": spec.runner_script,
        # the frozen execution-layer ceilings the cell ran under — the same
        # speaking tuple build_container_cmd places before the image token
        "caps": list(docker_cmd.all_caps_speaking()),
    }


def key_of(spec, in_dir: Path, catalog_mount, child_argv: list[str]) -> str:
    """Content-addressed key (hex). Pure: identical components => identical
    key; any bound component moving => a different key (pinned by tests)."""
    payload = _key_payload(spec, Path(in_dir), catalog_mount, list(child_argv))
    canon = json.dumps(payload, sort_keys=True, indent=1)
    return hashlib.sha256(canon.encode("utf-8")).hexdigest()


def _key_dir(root: Path, key: str) -> Path:
    return root / "keys" / key


def _verify(key_dir: Path, key: str) -> str | None:
    """``None`` when the entry is admissible for service, else the reason
    (every reason folds to a miss at the caller)."""
    entry = key_dir / "entry.json"
    payload_dir = key_dir / "payload"
    if not entry.is_file() or not payload_dir.is_dir():
        return "entry or payload dir absent"
    try:
        doc = json.loads(entry.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        return f"entry unparseable: {exc}"
    if not isinstance(doc, dict) or doc.get("schema") != 1 \
            or doc.get("key") != key:
        return "entry is not a well-formed v1 document for this key"
    files = doc.get("files")
    if not isinstance(files, dict) or not files:
        return "entry carries no file-digest map"
    if set(files) != {p.name for p in payload_dir.iterdir() if p.is_file()}:
        return "payload file set disagrees with the entry map"
    for name, want in files.items():
        got = _sha256(payload_dir / name)
        if got != want:
            return f"payload byte drift on {name!r}: {got[:12]}... != {want[:12]}..."
    return None


def serve_if_cached(*, spec, in_dir: Path, out_dir: Path, catalog_mount,
                    child_argv: list[str]) -> dict | None:
    """Serve the cell bytes from a verified hit (launching nothing); ``None``
    on the miss path (disabled, absent, corrupt). Fail-open by law."""
    root = cache_dir()
    if root is None:
        return None
    key = key_of(spec, in_dir, catalog_mount, child_argv)
    key_dir = _key_dir(root, key)
    reason = _verify(key_dir, key)
    if reason is not None:
        return None
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    t0 = time.monotonic()
    for name in sorted((key_dir / "payload").iterdir()):
        shutil.copy(name, out / name.name)
    served_s = round(time.monotonic() - t0, 6)
    sidecar = {"ru_utime": served_s, "ru_stime": 0.0,
               "cpu_seconds": served_s, "exit_status": 0,
               "measurement": CACHE_HIT_MEASUREMENT, "cache_key": key,
               "served_from": str(key_dir)}
    (out / "timing.json").write_text(json.dumps(sidecar, sort_keys=True,
                                                indent=1), encoding="utf-8")
    return {"cpu_seconds": 0.0, "sidecar": sidecar, "cache_hit": True}


def capture(*, spec, in_dir: Path, out_dir: Path, catalog_mount,
            child_argv: list[str]) -> None:
    """Populate the entry from a gate-passed fresh cell. Reachable only past
    run_container_cell's own validation; best-effort by law — cache trouble
    must never turn a good measurement into a failed leg."""
    root = cache_dir()
    if root is None:
        return
    out = Path(out_dir)
    files = {f.name: f for f in sorted(out.iterdir())
             if f.is_file() and f.name not in _EXCLUDED}
    if not files:
        return                                   # nothing worth storing
    key = key_of(spec, in_dir, catalog_mount, child_argv)
    key_dir = _key_dir(root, key)
    if _verify(key_dir, key) is None:
        return                                   # first-wins, already committed
    if key_dir.exists():
        shutil.rmtree(key_dir, ignore_errors=True)   # superseded corrupt entry
    payload = key_dir / "payload"
    payload.mkdir(parents=True, exist_ok=True)
    for name, src in files.items():
        shutil.copy(src, payload / name)
    measured = {}
    sidecar_path = out / "timing.json"
    if sidecar_path.is_file():
        try:
            doc = json.loads(sidecar_path.read_text(encoding="utf-8"))
            measured = {k: doc[k] for k in
                        ("ru_utime", "ru_stime", "cpu_seconds", "exit_status")
                        if k in doc}
        except (OSError, ValueError):
            measured = {}
    entry = {"schema": 1, "key": key,
             "components": _key_payload(spec, Path(in_dir), catalog_mount,
                                        child_argv),
             "files": {name: _sha256(src) for name, src in files.items()},
             "measured_sidecar": measured,
             "source": "measured-leg"}
    tmp = key_dir / f"entry.json.tmp{os.getpid()}"
    tmp.write_text(json.dumps(entry, sort_keys=True, indent=1),
                   encoding="utf-8")
    tmp.replace(key_dir / "entry.json")          # the commit point
