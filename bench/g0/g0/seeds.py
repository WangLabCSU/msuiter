"""G0 种子纪律（协议 §2.3，冻结）。

master seed = 20260928；逐 (arm, N, rep) 确定性派生，全部种子落盘 Seeds.txt
manifest（research/05 §6 指出的领域缺失实践，本实验先行示范）。

派生布局（确定性、跨平台、跨 Python 版本可复现；与 ARCH §2 rng.rs 的
SplitMix64 计数器流设计同构）：

    label   = "g0/v1|" + "|".join(str(p) for p in parts)
    key     = fnv1a64(label)                 # 流标签 -> 64-bit 流 key
    seed    = splitmix64_final(MASTER_SEED XOR key)   # 计数器 + finalizer

- fnv1a64：FNV-1a 64-bit（仅做字符串 -> 64-bit 压缩；无随机化，不用
  Python 内建 hash()——它对 str 有 PYTHONHASHSEED 随机化，禁用）。
- splitmix64_final：SplitMix64 的三次混合 finalizer（Steele et al. 2014,
  public domain），与 rng.rs 流派生同族。
- 派生出的 64-bit 整数喂给 numpy Generator(PCG64)（np.random.default_rng）。

工具侧随机性（HMC / bootstrap）单独派生：derive_seed(tool, arm, N, rep)，
与数据种子互不重叠（标签不同）。
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

MASK64 = (1 << 64) - 1

MASTER_SEED = 20260928  # 冻结（协议 §2.3）
STREAM_VERSION = "g0/v1"


def _splitmix64(x: int) -> int:
    """SplitMix64 finalizer：一个 64-bit 计数器 -> 均匀 64-bit 输出。"""
    x = (x + 0x9E3779B97F4A7C15) & MASK64
    z = x
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK64
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK64
    return z ^ (z >> 31)


def _fnv1a64(s: str) -> int:
    h = 0xCBF29CE484222325
    for byte in s.encode("utf-8"):
        h ^= byte
        h = (h * 0x100000001B3) & MASK64
    return h


def derive_seed(*parts: Iterable) -> int:
    """由任意标签元组确定性地派生 64-bit 种子。

    例：derive_seed("main", 1000, 7) 为 (arm=main, N=1000, rep=7) 的
    数据种子；derive_seed("sigfit", "main", 1000, 7) 为该 cell 喂给
    sigfit 容器的种子。
    """
    label = STREAM_VERSION + "|" + "|".join(str(p) for p in parts)
    key = _fnv1a64(label)
    return _splitmix64(MASTER_SEED ^ key)


def make_rng(*parts) -> "np.random.Generator":
    import numpy as np  # 局部导入：纯派生函数不依赖 numpy

    return np.random.default_rng(derive_seed(*parts))


@dataclass(frozen=True)
class SeedSpec:
    """一个模拟 cell：arm × N × rep。"""

    arm: str
    n: int
    rep: int

    @property
    def data_seed(self) -> int:
        return derive_seed(self.arm, self.n, self.rep)


def write_seeds_manifest(path: Path, specs: Sequence[SeedSpec],
                         tool_names: Sequence[str] = ("sigfit", "stl"),
                         header_note: str = "") -> Path:
    """Seeds.txt manifest 落盘（协议 §2.3：全部种子落盘）。

    格式：制表符分隔，含头两行注释（# 开头）+ 列头。
    每行：arm, N, rep, data_seed, 以及逐工具种子列。
    """
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        fh.write(f"# G0 Seeds manifest | master_seed={MASTER_SEED} | "
                 f"derivation={STREAM_VERSION}: splitmix64(master ^ fnv1a64(label))\n")
        if header_note:
            fh.write(f"# note: {header_note}\n")
        cols = ["arm", "N", "rep", "data_seed"] + [f"seed_{t}" for t in tool_names]
        fh.write("\t".join(cols) + "\n")
        for s in specs:
            tool_seeds = [derive_seed(t, s.arm, s.n, s.rep) for t in tool_names]
            fh.write("\t".join(str(v) for v in
                               (s.arm, s.n, s.rep, s.data_seed, *tool_seeds)) + "\n")
    return path
