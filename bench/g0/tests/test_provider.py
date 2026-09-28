"""④ cosmic-file provider 标签校验（错序必须拒）+ synthetic provider 确定性。

不依赖 pytest：临时目录用 tempfile 自理（run_all 直接调用 test_*()）。
"""

import csv
import tempfile
from pathlib import Path

import numpy as np

from g0 import providers
from g0.providers import CosmicFileProvider, ProviderError, load_sbs96_labels

# 确定性伪数据（非 COSMIC——绝不入库）：值 = 1 + ((i*7+j) % 13)/13


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
    # ref-major：行 0–23 以 A 开头，24–47 以 C 开头
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
    # 近重复平坦对（P1 机制 (i) 合成探针）：cosine ≥ 0.999
    va, vb = a.truth["SBS5"], a.truth["SBS40"]
    cos = float(np.dot(va, vb) / np.linalg.norm(va) / np.linalg.norm(vb))
    assert cos >= 0.999
    # 缺席签名（LRT 的 H0 集）存在且数量正确
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
    """喂错序文件必须拒（防止下游向量错位静默污染覆盖率）。"""
    labels, mat = _pseudo_mat()
    perm = list(range(96))
    perm[0], perm[1] = perm[1], perm[0]           # 交换前两个通道
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
