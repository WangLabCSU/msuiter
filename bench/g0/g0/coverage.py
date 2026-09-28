"""经验覆盖率计算 + Clopper–Pearson 区间 + 冻结判定规则（协议 §2.4/F1，逐字实现）。

主 estimand（协议 §2.1）：工具 T 默认部署管线（含默认清零/过滤）输出的
95% exposure 区间对真值绝对 exposure h_j = f_j·N（counts）的频率覆盖率。
成分版与 raw（未清零）列为次要报告，不进判定（estimand 列区分）。

汇总纪律：逐签名逐格点（cell = tool × arm × N × signature）；easy/flat
分层；**禁止跨签名平均掩盖 flat 层**（协议 §5）。flat 层行附加
P1 机制 (i) 归因列（近重复目录机制；assumption-audit-memo P1）。

判定（F1 冻结，§2.4 表逐字）：
  支持 A  ①任一 Tier-1 工具任一 cell ĉ ≤ 0.85 且 binomial 95% CI 上界 < 0.90；
          或 ②flat 层 N≥300 全部 cell ĉ ≤ 0.90。
  kill→B  两 Tier-1 工具全部 N≥300 cell ĉ ≥ 0.90 且随 N 无单调恶化。
  gray    其余情形 → borderline cells 加倍 reps 至 400 重判；仍 gray
          默认走 B（风险不对称，最终由作者裁决）。
"单调恶化"操作化定义（文档化）：对每 (tool, signature)，N≥300 格点按
升序的 ĉ 序列全体相邻差 ≤ 0 且至少一个严格 < 0。
borderline cells 操作化定义（P2b）：protocol-memo §2.4 原文与裁决 §5
均**无 N≥300 限定** → ĉ<0.90 的全部格点（含 N<300）为重判候选，供
--profile gray 加倍重复。判定输入契约（P0-2）与工具过滤（P2a）见
judge() docstring。

Clopper–Pearson 精确二项区间：自实现正则化不完全 beta（连分式，
Numerical Recipes betacf 算法）+ 二分反演；无 scipy。
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

# ------------------------------------------------ 正则化不完全 beta（自有）

_MAXIT, _EPS, _FPMIN = 300, 3e-16, 1e-300


def _betacf(a: float, b: float, x: float) -> float:
    qab, qap, qam = a + b, a + 1.0, a - 1.0
    c = 1.0
    d = 1.0 - qab * x / qap
    if abs(d) < _FPMIN:
        d = _FPMIN
    d = 1.0 / d
    h = d
    for m in range(1, _MAXIT + 1):
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        if abs(d) < _FPMIN:
            d = _FPMIN
        c = 1.0 + aa / c
        if abs(c) < _FPMIN:
            c = _FPMIN
        d = 1.0 / d
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        if abs(d) < _FPMIN:
            d = _FPMIN
        c = 1.0 + aa / c
        if abs(c) < _FPMIN:
            c = _FPMIN
        d = 1.0 / d
        de = d * c
        h *= de
        if abs(de - 1.0) < _EPS:
            break
    return h


def betainc_reg(a: float, b: float, x: float) -> float:
    """正则化不完全 beta I_x(a,b)。"""
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    ln_bt = (math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b)
             + a * math.log(x) + b * math.log1p(-x))
    bt = math.exp(ln_bt)
    if x < (a + 1.0) / (a + b + 2.0):
        return bt * _betacf(a, b, x) / a
    return 1.0 - bt * _betacf(b, a, 1.0 - x) / b


def beta_ppf(q: float, a: float, b: float) -> float:
    """Beta(a,b) 分位数（二分反演，200 轮到双精度极限）。"""
    if not 0.0 <= q <= 1.0:
        raise ValueError(q)
    lo, hi = 0.0, 1.0
    for _ in range(200):
        mid = 0.5 * (lo + hi)
        if betainc_reg(a, b, mid) < q:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


def clopper_pearson(k: int, n: int, conf: float = 0.95) -> tuple:
    """Clopper–Pearson 精确二项区间 (lo, hi)。"""
    if n <= 0:
        return (0.0, 1.0)
    if not 0 <= k <= n:
        raise ValueError(f"k={k} out of [0, n={n}]")
    a = 1.0 - conf
    lo = 0.0 if k == 0 else beta_ppf(a / 2.0, k, n - k + 1)
    hi = 1.0 if k == n else beta_ppf(1.0 - a / 2.0, k + 1, n - k)
    return (lo, hi)


# ------------------------------------------------ 覆盖率与判定

@dataclass
class IntervalRecord:
    """一条工具区间记录（adapter 输出经解析后的长表行）。"""

    tool: str
    arm: str
    n: int
    signature: str
    rep: int
    estimate: float
    lo95: float
    hi95: float
    estimand: str = "absolute"      # absolute（主）| fraction | raw（次要）
    zeroed: bool = False            # sigfit 清零规则触发 / STL 过滤塌缩
    error: bool = False             # 拒跑/报错（部署行为，如实计入）


@dataclass
class CellCoverage:
    tool: str
    arm: str
    n: int
    signature: str
    layer: str                      # easy / flat
    truth_h: float
    k: int
    n_reps: int
    coverage: float
    cp_lo: float
    cp_hi: float
    filtered_rate: float = 0.0      # 清零/过滤触发率（次要列）
    error_rate: float = 0.0
    p1_mechanism_i: bool = False    # flat 层 P1 机制 (i) 归因列（增补诊断列）


def cell_coverage(records, truth_h_by_sig: dict, layer_of) -> list:
    """逐 cell 计算经验覆盖率与 CP 区间（仅 estimand='absolute' 且非 error 进主判定分母）。

    错误/拒跑记录不计入分母但计入 error_rate（协议 §2.1：部署行为即证据；
    N=100 端 guardline 触发率单独成列）。
    """
    cells = {}
    for r in records:
        if r.signature not in truth_h_by_sig:
            continue                      # 目录中非真值签名（absent 列）无 estimand
        cells.setdefault((r.tool, r.arm, r.n, r.signature), []).append(r)
    out = []
    for (tool, arm, n, sig), rs in sorted(cells.items()):
        valid = [r for r in rs if not r.error and r.estimand == "absolute"]
        k = sum(1 for r in valid if r.lo95 <= truth_h_by_sig[sig] <= r.hi95)
        n_reps = len(valid)
        lo, hi = clopper_pearson(k, n_reps)
        out.append(CellCoverage(
            tool=tool, arm=arm, n=n, signature=sig, layer=layer_of(sig),
            truth_h=truth_h_by_sig[sig], k=k, n_reps=n_reps,
            coverage=(k / n_reps) if n_reps else float("nan"),
            cp_lo=lo, cp_hi=hi,
            filtered_rate=(sum(1 for r in valid if r.zeroed) / n_reps) if n_reps else 0.0,
            error_rate=(sum(1 for r in rs if r.error) / len(rs)) if rs else 0.0,
            p1_mechanism_i=(layer_of(sig) == "flat"),
        ))
    return out


def _monotone_worsening(series: list) -> bool:
    """全体相邻差 ≤ 0 且至少一个严格 < 0（文档化操作化定义）。"""
    if len(series) < 2:
        return False
    diffs = [series[i + 1] - series[i] for i in range(len(series) - 1)]
    return all(d <= 1e-12 for d in diffs) and any(d < -1e-12 for d in diffs)


@dataclass
class Judgment:
    verdict: str                                    # "A" | "B" | "GRAY"
    clause_a1_cells: list = field(default_factory=list)
    clause_a2: bool = False
    kill_ok: bool = False
    monotone_worse: list = field(default_factory=list)
    borderline_cells: list = field(default_factory=list)
    notes: list = field(default_factory=list)

    def summary(self) -> str:
        lines = [f"verdict: {self.verdict}"]
        if self.clause_a1_cells:
            lines.append("A-clause① cells (ĉ≤0.85 & CP_hi<0.90): "
                         + "; ".join(self.clause_a1_cells))
        lines.append(f"A-clause② flat all ≤0.90 @N≥300: {self.clause_a2}")
        lines.append(f"kill conditions met: {self.kill_ok}")
        if self.monotone_worse:
            lines.append("monotone worsening (tool,signature): "
                         + "; ".join(self.monotone_worse))
        if self.borderline_cells:
            lines.append("borderline cells (ĉ<0.90, all N, reps→400): "
                         + "; ".join(self.borderline_cells))
        lines += [f"note: {n}" for n in self.notes]
        return "\n".join(lines)


def judge(cells: list, tier1_tools=("sigfit", "stl"),
          judge_n_min: int = 300, support_lower: float = 0.85,
          ci_upper_max: float = 0.90, flat_upper: float = 0.90,
          kill_lower: float = 0.90, judge_arms=None) -> Judgment:
    """冻结判定规则（§2.4/F1，逐字实现）。

    输入契约（P0-2，冻结增补条款 b）：敏感性臂（nb/clock/sparse）只细化
    不推翻判定——调用方传 judge_arms（允许进判定的 main 模型臂集合，
    即主多项 + 冻结真值组合轴），非 judge 臂的 cell 一律忽略并记 note。

    工具契约（P2a）：全部判定子句按 tier1_tools 过滤——"任一/全部/两
    工具"均指 Tier-1 对；kill 另要求两工具在判定区（N≥300）均有 cell
    （"两 Tier-1 工具"的字面语义，防单工具静默通过）。

    borderline（P2b）：protocol-memo §2.4 原文"仅对 borderline cells 加倍
    重复至 400 后重判"与裁决 §5 转述均**无 N≥300 限定** → 所有格点
    （含 N<300）的失准 cell 都可进 gray 加倍流程，照冻结文本实现。

    "单调恶化"操作化定义（文档化）：对每 (tool, signature)，N≥300 格点按
    升序的 ĉ 序列全体相邻差 ≤ 0 且至少一个严格 < 0。
    只接受 estimand='absolute' 的主表 cells（由上游保证）。
    """
    j = Judgment(verdict="GRAY")
    pool = [c for c in cells if c.n_reps > 0]
    if judge_arms is not None:
        excluded = sorted({c.arm for c in pool if c.arm not in judge_arms})
        pool = [c for c in pool if c.arm in judge_arms]
        if excluded:
            j.notes.append("敏感性臂只出报告列不进判定（冻结增补条款 b）: "
                           + ", ".join(excluded))
    t1 = set(tier1_tools)

    # 支持 A ①：任一 Tier-1 工具任一 cell
    for c in pool:
        if (c.tool in t1 and c.coverage <= support_lower
                and c.cp_hi < ci_upper_max):
            j.clause_a1_cells.append(f"{c.tool}|{c.arm}|N={c.n}|{c.signature}")
    # 支持 A ②：flat 层 N≥300 全部 Tier-1 cell
    flat_cells = [c for c in pool
                  if c.tool in t1 and c.layer == "flat" and c.n >= judge_n_min]
    j.clause_a2 = bool(flat_cells) and all(c.coverage <= flat_upper for c in flat_cells)
    if j.clause_a1_cells or j.clause_a2:
        j.verdict = "A"
        return j

    # kill→B：两 Tier-1 工具全部 N≥300 cell ĉ ≥ 0.90 且无单调恶化
    high_cells = [c for c in pool if c.tool in t1 and c.n >= judge_n_min]
    tools_present = {c.tool for c in high_cells}
    j.kill_ok = (bool(high_cells) and t1 <= tools_present
                 and all(c.coverage >= kill_lower for c in high_cells))
    worse = []
    for tool in tier1_tools:
        for sig in sorted({c.signature for c in pool}):
            seq = sorted([c for c in high_cells
                          if c.tool == tool and c.signature == sig],
                         key=lambda c: c.n)
            if _monotone_worsening([c.coverage for c in seq]):
                worse.append(f"({tool},{sig})")
    j.monotone_worse = worse
    if j.kill_ok and not worse:
        j.verdict = "B"
        return j

    # gray：borderline cells = 全部 N 的 ĉ<0.90 Tier-1 cell（P2b：冻结文本
    # 无 N≥300 限定；加倍 reps 至 400 重判候选）
    j.borderline_cells = [f"{c.tool}|{c.arm}|N={c.n}|{c.signature}"
                          for c in pool if c.tool in t1 and c.coverage < kill_lower]
    j.notes.append("gray: borderline cells 需加倍 reps 至 400 重判（协议 §2.4）；"
                   "仍 gray → 作者裁决，默认走 B（风险不对称）。")
    return j
