"""签名矩阵 provider（许可红线 D3：COSMIC 绝不入库）。

两个 provider：

1. SyntheticProvider（默认）：Dirichlet 生成的合成签名，测试与开发全用这档。
   结构刻意模仿真值集的功能语义（slot 标签沿用 SBS1/2/13/5/40，但数值
   不是 COSMIC 签名）：clock 型尖峰、APOBEC 型 T[C>T]/T[C>G] 双签名、
   近重复平坦对（P1 机制 (i) 探针的合成类比）。构造公式完全文档化、
   完全由种子确定。
   冻结真值组合轴（grid.COMPOSITIONS，adjudication §3 ≥6 组）所需的扩展
   槽（SBS4/SBS7 强签名、MMR 群 SBS6/15/20/21/26/44、POLE 群
   SBS10a/b/c/d/28）同为**功能类似物**（数值非 COSMIC）：强签名按其文献
   主导通道做 boost；MMR/POLE 群按"共同主成分 + 独立 Dirichlet 噪声"的
   近重复家族构造（相关群整组同真的可辨识性压力正是被测对象）。真实
   数值在正式执行时由 cosmic-file provider（COSMIC v3.6 全 101 签名）提供。

2. CosmicFileProvider：从环境变量 G0_SIGNATURES_PATH 读用户自行获取的
   签名矩阵 CSV（数据获取与许可接受是用户动作，harness 只做格式校验）。
   加载时对照 tools/channel-reference/SBS96.txt 的标签规范序强校验：
   通道轴标签序列必须与规范序逐项相等（顺序敏感），否则拒绝加载。
   这与 tools/channel-reference 的保守姿态同一逻辑。

本模块不包含、不嵌入、不派生任何 COSMIC 数值。

PI 裁决补充（2026-10-06，解除"用户自备文件"歧义）：cosmic-file 的
输入文件允许从**仓库内已捆绑的 COSMIC v3.6 参考**（refdb v1，
inst/reference/refdb/COSMIC_v3.6/，sha256 pin ff61b0f，BSD-2 许可、
许可与溯源治理在 A13/refdb 治理链内）本地派生——派生脚本
tools/g0-derive-inputs.R 把两个文件写到 bench/g0/cache/（gitignore
已覆盖），文件本体永不入库，D3 红线维持（"不入库"而非"不存在"）。
签名名映射记录：SBS17a→SBS17、SBS40a→SBS40（v3.6 拆分名归并到
TRUTH_NAMES 槽位）。
"""

from __future__ import annotations

import csv
import os
from pathlib import Path

import numpy as np

TRUTH_NAMES = ("SBS1", "SBS2", "SBS13", "SBS5", "SBS40")

_REPO_ROOT = Path(__file__).resolve().parents[3]
SBS96_REF_PATH = _REPO_ROOT / "tools" / "channel-reference" / "SBS96.txt"

# 通道索引数学（与 SBS96.txt 顺序绑定，加载时校验）：
#   ref     = i // 24          (A, C, G, T)
#   subtype = (i % 24) // 4    (C>A, C>G, C>T, T>A, T>C, T>G)
#   flank3  = i % 4            (A, C, G, T)


def load_sbs96_labels(path: Path = SBS96_REF_PATH) -> tuple:
    """读取通道标签规范序（模拟器输出向量顺序锚）。"""
    lines = Path(path).read_text(encoding="utf-8").splitlines()
    labels = tuple(ln.strip() for ln in lines if ln.strip())
    if len(labels) != 96:
        raise ValueError(f"SBS96 reference must have 96 labels, got {len(labels)}")
    return labels


class ProviderError(RuntimeError):
    pass


# ---------------------------------------------------------------- synthetic


class SyntheticProvider:
    """确定性合成签名（默认开发/测试档）。

    构造（全部由 derive_seed("synthetic", seed) 的 rng 确定，公式冻结于
    本 docstring）：

      flat_a   ~ Dirichlet(1,...,1)                       # 平坦签名 A
      flat_b   = normalize(0.97*flat_a + 0.03*e)          # 近重复平坦对 B
               e ~ Dirichlet(1,...,1)
      clock    = boost(Dirichlet(0.2,...,0.2), subtype=C>T, ×15)   # 时钟型尖峰
      apo_1    = boost(Dirichlet(0.2,...,0.2), T[C>T], ×40)
      apo_2    = boost(Dirichlet(0.2,...,0.2), T[C>G], ×40)        # APOBEC 对

      boost(m, mask, k) = normalize(m * (1 + (k-1)*mask))

    组合轴扩展槽（功能类似物，数值非 COSMIC；同 rng 顺序确定）：

      smoke4   = boost(Dir(0.2), C>A 全通道, ×25)          # 烟草 SBS4 类（C>A 主导）
      uv7      = boost(Dir(0.2), C[C>T]/C[T>C] 二嘧啶, ×25)  # UV SBS7 类（二嘧啶 C>T）
      mmr_common = boost(Dir(0.2), C>A ∪ C>T 全通道, ×8)
      SBS6/15/20/21/26/44 = normalize(0.85·mmr_common + 0.15·Dir(0.5)_i)
                  # MMR 相关群：共同主成分 + 独立噪声的近重复家族
      pole_common = boost(Dir(0.2), T 背景 C>A ∪ C>T, ×12)
      SBS10a/b/c/d/28    = normalize(0.85·pole_common + 0.15·Dir(0.5)_i)
                  # POLE 群：同上（外切酶缺陷特征通道的粗粒度类似物）

    目录 = 5 真值 slot + K_EXTRA 个"缺席"签名（absent ~ Dirichlet(0.5)，
    供 presence LRT 的 size 校准（H0 签名）使用）+ 组合轴扩展槽。
    """

    K_EXTRA = 5

    def __init__(self, seed: int = 0):
        from .seeds import derive_seed

        rng = np.random.default_rng(derive_seed("synthetic", int(seed)))
        n = 96

        def boost(base, mask, k):
            return _normalize(base * (1.0 + (k - 1) * mask))

        # 通道 mask
        subtype = np.arange(n) % 24 // 4
        ref = np.arange(n) // 24
        flank3 = np.arange(n) % 4
        m_ct = (subtype == 2).astype(float)                    # C>T（任意 ref）
        m_apobec_ct = ((subtype == 2) & (ref == 3)).astype(float)   # T[C>T]
        m_apobec_cg = ((subtype == 1) & (ref == 3)).astype(float)   # T[C>G]

        flat_a = rng.dirichlet(np.ones(n))
        flat_b = _normalize(0.97 * flat_a + 0.03 * rng.dirichlet(np.ones(n)))
        clock = boost(rng.dirichlet(np.full(n, 0.2)), m_ct, 15)
        apo1 = boost(rng.dirichlet(np.full(n, 0.2)), m_apobec_ct, 40)
        apo2 = boost(rng.dirichlet(np.full(n, 0.2)), m_apobec_cg, 40)

        self.truth = {
            "SBS1": clock, "SBS2": apo1, "SBS13": apo2,
            "SBS5": flat_a, "SBS40": flat_b,
        }
        self.absent = {f"ABS{i+1}": rng.dirichlet(np.full(n, 0.5))
                       for i in range(self.K_EXTRA)}

        # ---- 组合轴扩展槽（功能类似物；见类 docstring 公式） ------------
        m_ca = (subtype == 0).astype(float)                    # C>A（任意 ref）
        m_uv = ((ref == 1) & (subtype == 2)
                & ((flank3 == 1) | (flank3 == 3))).astype(float)  # C[C>T]/C[T…C>T] 二嘧啶
        m_mmr = ((subtype == 0) | (subtype == 2)).astype(float)   # C>A ∪ C>T
        m_pole = ((ref == 3) & ((subtype == 0) | (subtype == 2))).astype(float)

        def family_like(mask, k, members, common_weight=0.85):
            common = boost(rng.dirichlet(np.full(n, 0.2)), mask, k)
            return {m: _normalize(common_weight * common
                                  + (1.0 - common_weight) * rng.dirichlet(np.full(n, 0.5)))
                    for m in members}

        extended = {
            "SBS4": boost(rng.dirichlet(np.full(n, 0.2)), m_ca, 25),
            "SBS7": boost(rng.dirichlet(np.full(n, 0.2)), m_uv, 25),
        }
        extended.update(family_like(m_mmr, 8,
                                    ("SBS6", "SBS15", "SBS20", "SBS21",
                                     "SBS26", "SBS44")))
        extended.update(family_like(m_pole, 12,
                                    ("SBS10a", "SBS10b", "SBS10c", "SBS10d",
                                     "SBS28")))
        self.extended = extended

        self.catalog = dict(self.truth)
        self.catalog.update(self.absent)
        self.catalog.update(self.extended)
        self.channel_labels = load_sbs96_labels()

    def signature(self, name: str) -> np.ndarray:
        """按名取归一化签名谱（组合轴真值装配用）。

        v3.6 拆分名解析：SBS40 → SBS40a（+SBS40b/c 等权并分）、
        SBS17 → SBS17a/b 等权并分（PI 派生裁决的映射记录，memo
        providers 头注）。真值槽位经 _truth_signature 查询。"""
        resolved = self._resolve_name(name)
        if resolved is not None:
            return resolved
        try:
            return self.catalog[name]
        except KeyError:
            raise ProviderError(
                f"synthetic provider has no slot '{name}' "
                f"(composition axis requests an unknown signature)") from None

    def catalog_matrix(self, names=None) -> tuple:
        """(names, W 96×K)，W 列序与 names 一致，各列和为 1。"""
        names = list(self.catalog) if names is None else list(names)
        return names, np.column_stack([self.catalog[k] for k in names])


def _normalize(v: np.ndarray) -> np.ndarray:
    s = v.sum()
    if s <= 0:
        raise ProviderError("cannot normalize non-positive vector")
    return v / s


# ------------------------------------------------------------- cosmic-file


class CosmicFileProvider:
    """用户自备签名矩阵 CSV（环境变量 G0_SIGNATURES_PATH）。

    接受两种朝向（自动检测）：
      - 行 = 签名、列 = 通道（首行通道标签）；
      - 行 = 通道、列 = 签名（首列通道标签）。
    校验（任何一条不满足即拒绝，ProviderError）：
      1. 通道轴长度 = 96；
      2. 通道标签序列与 SBS96.txt 规范序逐项相等（顺序敏感——
         错序文件必须拒，防止下游向量错位静默污染覆盖率）；
      3. 含全部 5 个真值签名名（SBS1/SBS2/SBS13/SBS5/SBS40）；
      4. 各签名通道和 > 0（加载时归一化为和 1）。
    """

    def __init__(self, path: str | os.PathLike):
        path = Path(os.environ.get("G0_SIGNATURES_PATH", path))
        if not path.exists():
            raise ProviderError(
                f"signature file not found: {path} "
                f"(set G0_SIGNATURES_PATH or pass an explicit path)")
        self.channel_labels = load_sbs96_labels()
        self.truth, self.catalog = self._load(path)
        # The full F3 fitting catalog (G0_CATALOG_PATH, 101 signatures)
        # feeds the truth-composition axis beyond the 5 truth slots
        # (MMR/POLE groups etc., grid.COMPOSITIONS) — the audited first
        # wiring left the provider's catalog at the 5-col truth file,
        # which crashed the primary profile on SBS6 (PI adjudication
        # derivation 2026-10-06).
        catalog_path = os.environ.get("G0_CATALOG_PATH")
        if catalog_path and Path(catalog_path).exists():
            self._loading_full_catalog = True
            _, full_catalog = self._load(Path(catalog_path))
            self._loading_full_catalog = False
            self.catalog = full_catalog

    @staticmethod
    def _read_rows(path: Path):
        with Path(path).open(newline="", encoding="utf-8") as fh:
            return [row for row in csv.reader(fh) if any(c.strip() for c in row)]

    def _load(self, path: Path):
        rows = self._read_rows(path)
        label_set = set(self.channel_labels)

        def hits(cells):
            return sum(1 for c in cells if c.strip() in label_set)

        first = [c.strip() for c in rows[0]]
        col0 = [r[0].strip() for r in rows[1:] if r]
        if hits(first) >= 90:
            # 转置朝向：首行 = 通道轴（可能带一个角落单元，如 "signature"）
            corner = [c for c in first if c not in label_set]
            channel_labels = tuple(c for c in first if c in label_set)
            if len(channel_labels) != 96:
                raise ProviderError(
                    f"channel axis has {len(channel_labels)} labels, expected 96")
            sig_names = [r[0].strip() for r in rows[1:] if r]
            vals = [[float(x) for x in r[1:]] for r in rows[1:] if r]
            mat = np.array(vals, dtype=float)
            if len(corner) != 1 or mat.shape[0] != len(sig_names):
                raise ProviderError("malformed signature-major matrix")
        elif sum(1 for c in col0 if c in label_set) >= 90:
            # 通道主序朝向：首列 = 通道，首行 = 签名名。行列数可以不对称
            #（通道 96 × 签名 101），切片须按 (rows, 1+96) 矩形读入后
            #转置——首稿的 [r[1:1+96]] 切片在签名数 ≠ 通道数时丢列
            #（PI 派生文件 101 签名实测触发，CI/本地双审 2026-10-06）。
            channel_labels = tuple(col0)
            sig_names = [c.strip() for c in first[1:]]
            vals = [[float(x) for x in r[1:]] for r in rows[1:] if r]
            mat = np.array(vals, dtype=float).T   # (m, n_sig)
        else:
            raise ProviderError(
                "cannot locate a channel-label axis (neither header row nor "
                "first column matches the SBS96 label set)")

        self._validate_channels(channel_labels)

        if mat.shape[0] != len(sig_names) or mat.shape[0] == 0:
            raise ProviderError("signature axis malformed")

        catalog = {}
        for name, vec in zip(sig_names, mat):
            s = vec.sum()
            if not np.isfinite(vec).all() or s <= 0:
                raise ProviderError(f"signature '{name}' has non-positive/invalid channel sum")
            catalog[name] = vec / s

        # The 5-slot TRUTH_NAMES check belongs to the truth-file load
        # (G0_SIGNATURES_PATH, the first _load call). The full catalog
        # (G0_CATALOG_PATH) uses v3.6 split names — SBS40 exists only as
        # SBS40a/b/c there, so requiring the unsplit names here was a
        # category error (PI derivation, 2026-10-06).
        missing = [k for k in TRUTH_NAMES if k not in catalog]
        if missing and not getattr(self, "_loading_full_catalog", False):
            raise ProviderError(f"truth signatures missing from file: {missing}")
        truth = {}
        for k in TRUTH_NAMES:
            if k in catalog:
                truth[k] = catalog[k]
            elif getattr(self, "_loading_full_catalog", False):
                v = self._resolve_name(k) if hasattr(self, "catalog") else None
                if v is not None:
                    truth[k] = v / v.sum()
        return truth, catalog

    def signature(self, name: str) -> np.ndarray:
        """按名取归一化签名谱（组合轴真值装配用）。

        v3.6 拆分名解析：SBS40 → SBS40a（+SBS40b/c 等权并分）、
        SBS17 → SBS17a/b 等权并分（PI 派生裁决的映射记录，memo
        providers 头注）。真值槽位经 _truth_signature 查询。"""
        resolved = self._resolve_name(name)
        if resolved is not None:
            return resolved
        try:
            return self.catalog[name]
        except KeyError:
            raise ProviderError(
                f"signature '{name}' not present in the user catalog file — "
                f"frozen composition axis (grid.COMPOSITIONS) requires it; "
                f"F3 catalog = COSMIC v3.6 SBS96 GRCh37 full signature set") from None

    def _resolve_name(self, name: str):
        """Split-name resolution for the frozen truth slots: SBS40 ->
        SBS40a (+SBS40b/c) and SBS17 -> SBS17a/b, equally weighted when
        the unsplit name is absent (v3.6 naming, PI derivation)."""
        if name in ("SBS40", "SBS17"):
            prefix = name
            members = sorted(k for k in self.catalog
                             if k.startswith(prefix)
                             and k[len(prefix):].isdigit() is False
                             and len(k) == len(prefix) + 1
                             and k[len(prefix)].isalpha())
            if members:
                n = len(members)
                return sum(self.catalog[k] for k in members) / n
        return None

    def _validate_channels(self, labels):
        if len(labels) != 96:
            raise ProviderError(
                f"channel axis has {len(labels)} labels, expected 96")
        for i, (got, want) in enumerate(zip(labels, self.channel_labels)):
            if got != want:
                raise ProviderError(
                    f"channel label order mismatch at position {i}: "
                    f"got '{got}', expected '{want}' (SBS96.txt canonical order). "
                    f"Refusing to load a mis-ordered matrix.")


def provider_by_name(name: str, seed: int = 0):
    if name == "synthetic":
        return SyntheticProvider(seed=seed)
    if name == "cosmic-file":
        return CosmicFileProvider(os.environ.get("G0_SIGNATURES_PATH", ""))
    raise ValueError(f"unknown provider: {name} (expected 'synthetic' or 'cosmic-file')")
