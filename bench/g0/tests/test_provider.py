"""④ cosmic-file provider label validation (a wrong order must be rejected) + synthetic provider determinism.

No pytest dependency: temp dirs are handled with tempfile (run_all calls test_*() directly).
"""

import csv
import os
import tempfile
from pathlib import Path

import numpy as np

from g0 import providers
from g0.providers import CosmicFileProvider, ProviderError, load_sbs96_labels

# Deterministic pseudo-data (not COSMIC — never committed): value = 1 + ((i*7+j) % 13)/13


def _pseudo_mat(n_sig=5):
    labels = list(load_sbs96_labels())
    mat = np.array([[1.0 + ((i * 7 + j) % 13) / 13.0 for j in range(n_sig)]
                    for i in range(96)])
    return labels, mat


def _tmpfile(name: str) -> Path:
    d = Path(tempfile.mkdtemp(prefix="g0test_"))
    return d / name


def _write_channel_major(path, labels, mat, sig_names=("SBS1", "SBS2", "SBS13",
                                                      "SBS5", "SBS40")):
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["channel", *sig_names])
        for i, lab in enumerate(labels):
            w.writerow([lab, *(f"{v:.6f}" for v in mat[i])])


def _write_sig_major(path, labels, mat, sig_names=("SBS1", "SBS2", "SBS13",
                                                   "SBS5", "SBS40")):
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["signature", *labels])
        for j, name in enumerate(sig_names):
            w.writerow([name, *(f"{v:.6f}" for v in mat[:, j])])


def _expect_reject(path, needle):
    try:
        CosmicFileProvider(path)
    except ProviderError as e:
        assert needle in str(e), f"unexpected message: {e}"
    else:
        raise AssertionError(f"must reject: {path}")


def test_sbs96_reference_shape():
    labels = load_sbs96_labels()
    assert len(labels) == 96
    assert labels[0] == "A[C>A]A" and labels[-1] == "T[T>G]T"
    # ref-major: rows 0–23 start with A, rows 24–47 with C
    assert all(l.startswith("A[") for l in labels[:24])
    assert all(l.startswith("C[") for l in labels[24:48])


def test_synthetic_provider_determinism():
    a = providers.SyntheticProvider(seed=0)
    b = providers.SyntheticProvider(seed=0)
    c = providers.SyntheticProvider(seed=1)
    for k in providers.TRUTH_NAMES:
        assert np.array_equal(a.truth[k], b.truth[k])
        assert not np.array_equal(a.truth[k], c.truth[k])
    names, W = a.catalog_matrix()
    assert np.allclose(W.sum(axis=0), 1.0)
    # the near-duplicate flat pair (P1 mechanism (i) synthetic probe): cosine ≥ 0.999
    va, vb = a.truth["SBS5"], a.truth["SBS40"]
    cos = float(np.dot(va, vb) / np.linalg.norm(va) / np.linalg.norm(vb))
    assert cos >= 0.999
    # the absent signatures (the H0 set of the LRT) exist and their count is right
    assert len(a.absent) == a.K_EXTRA


def test_cosmic_provider_accepts_canonical_order():
    labels, mat = _pseudo_mat()
    p = _tmpfile("ok.csv")
    _write_channel_major(p, labels, mat)
    prov = CosmicFileProvider(p)
    assert set(providers.TRUTH_NAMES) <= set(prov.catalog)
    for k in providers.TRUTH_NAMES:
        assert abs(prov.truth[k].sum() - 1.0) < 1e-9


def test_cosmic_provider_accepts_transposed():
    labels, mat = _pseudo_mat()
    p = _tmpfile("t.csv")
    _write_sig_major(p, labels, mat)
    prov = CosmicFileProvider(p)
    assert abs(prov.truth["SBS5"].sum() - 1.0) < 1e-9


def test_cosmic_provider_rejects_shuffled_channels():
    """A wrong-order file must be rejected (a downstream vector misalignment must not silently pollute coverage)."""
    labels, mat = _pseudo_mat()
    perm = list(range(96))
    perm[0], perm[1] = perm[1], perm[0]           # swap the first two channels
    p = _tmpfile("shuffled.csv")
    _write_channel_major(p, [labels[i] for i in perm], mat[perm])
    _expect_reject(p, "order mismatch")


def test_cosmic_provider_rejects_missing_truth_signature():
    labels, mat = _pseudo_mat(n_sig=4)
    p = _tmpfile("missing.csv")
    _write_channel_major(p, labels, mat, sig_names=("SBS1", "SBS2", "SBS13", "SBS5"))
    _expect_reject(p, "missing")


def test_cosmic_provider_rejects_wrong_channel_count():
    labels, mat = _pseudo_mat()
    p = _tmpfile("short.csv")
    _write_channel_major(p, labels[:-1], mat[:-1])
    _expect_reject(p, "96")


# ---------------------------------------------------------------------------
# Env-shadowing hardening (controller dry-run witness, 2026-10-13).
# The constructor's own error text promises "set G0_SIGNATURES_PATH or pass
# an explicit path": an explicit path must therefore WIN over an ambient
# environment value. Before this gate, os.environ.get(G0_SIGNATURES_PATH,
# path) silently preferred the environment, so a test or harness passing an
# explicit file would load the ambient one instead -- a silent-wrong-input
# hazard for the truth-axis that D3 governs.
# ---------------------------------------------------------------------------

def _env_saved(fn):
    """Run fn() with G0_SIGNATURES_PATH set, restoring the prior state."""
    def run():
        old = os.environ.get("G0_SIGNATURES_PATH")
        try:
            fn()
        finally:
            if old is None:
                os.environ.pop("G0_SIGNATURES_PATH", None)
            else:
                os.environ["G0_SIGNATURES_PATH"] = old
    return run


def _norm(v):
    v = np.asarray(v, dtype=float)
    return v / v.sum()


def test_cosmic_provider_explicit_path_beats_ambient_env():
    labels, mat = _pseudo_mat()
    env_file = _tmpfile("env_wins_bug.csv")
    exp_file = _tmpfile("explicit.csv")
    # Distinguish the two files AFTER normalization: different column
    # multipliers make the normalized SBS1 profiles differ measurably.
    _write_channel_major(env_file, labels, mat)
    mat_b = np.array([[1.0 + ((i * 11 + j) % 13) / 13.0
                       for j in range(5)] for i in range(96)])
    _write_channel_major(exp_file, labels, mat_b)
    want = _norm([float(f"{mat_b[i, 0]:.6f}") for i in range(96)])

    @_env_saved
    def go():
        os.environ["G0_SIGNATURES_PATH"] = str(env_file)
        prov = CosmicFileProvider(exp_file)          # explicit path wins?
        got = prov.signature("SBS1")
        assert np.allclose(got, want, rtol=0, atol=1e-9), (
            "explicit path was shadowed by the ambient G0_SIGNATURES_PATH")
    go()


def test_cosmic_provider_empty_path_still_uses_env():
    """The harness route (provider_by_name passes '') must keep working."""
    labels, mat = _pseudo_mat()
    env_file = _tmpfile("env_route.csv")
    _write_channel_major(env_file, labels, mat)

    @_env_saved
    def go():
        os.environ["G0_SIGNATURES_PATH"] = str(env_file)
        prov = CosmicFileProvider("")                # falsy path -> env route
        for k in providers.TRUTH_NAMES:
            assert abs(prov.truth[k].sum() - 1.0) < 1e-9
    go()
