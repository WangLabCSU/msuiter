"""The empirical coverage-rate computation + the Clopper–Pearson interval + the frozen judgment rule (the protocol §2.4/F1, a verbatim implementation).

The main estimand (the protocol §2.1): the frequency coverage rate of the default deployment pipeline's
95% exposure intervals (including the default zeroing/filtering) over the truth's absolute exposure h_j = f_j·N (counts).
The compositional version and the raw (un-zeroed) column are secondary reports and never enter the judgment (distinguished by the estimand column).

The aggregation discipline: per signature per grid point (cell = tool × arm × N × signature); easy/flat
stratification; **the cross-signature averaging that masks the flat layer is forbidden** (the protocol §5). The flat-layer rows carry an added
P1 mechanism (i) attribution column (the near-duplicate catalogue mechanism; assumption-audit-memo P1).

The judgment (F1 frozen, the §2.4 table verbatim):
  Supporting A  ① any Tier-1 tool's any cell with ĉ ≤ 0.85 and the binomial 95% CI upper bound < 0.90;
          or ② the flat layer N≥300 all the cells ĉ ≤ 0.90.
  kill→B  both Tier-1 tools' every N≥300 cell ĉ ≥ 0.90 and no monotone worsening along N.
  gray    the remaining cases → double the borderline cells' reps to 400 and re-judge; still gray
          defaults to going B (the risk asymmetry, the final say by the author).
The "monotone worsening" operationalized definition (documented): for each (tool, signature), the N≥300 grid points'
ascending ĉ series' every adjacent difference ≤ 0 with at least one strictly < 0.
The borderline cells operationalized definition (P2b): both the protocol-memo §2.4 original wording and the adjudication §5
carry **no N≥300 qualification** → every grid point with ĉ<0.90 (including N<300) is a re-judgment candidate, for the
--profile gray doubling. The judgment-input contract (P0-2) and the tool filtering (P2a) see the
judge() docstring.

The Clopper–Pearson exact binomial interval: the self-implemented regularized incomplete beta (the continued fraction,
the Numerical Recipes betacf algorithm) + the bisection inversion; no scipy.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

# ------------------------------------------------ the regularized incomplete beta (own)

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
    """The regularized incomplete beta I_x(a,b)."""
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
    """The quantile of Beta(a,b) (the bisection inversion, 200 rounds to the double-precision limit)."""
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
    """The Clopper–Pearson exact binomial interval (lo, hi)."""
    if n <= 0:
        return (0.0, 1.0)
    if not 0 <= k <= n:
        raise ValueError(f"k={k} out of [0, n={n}]")
    a = 1.0 - conf
    lo = 0.0 if k == 0 else beta_ppf(a / 2.0, k, n - k + 1)
    hi = 1.0 if k == n else beta_ppf(1.0 - a / 2.0, k + 1, n - k)
    return (lo, hi)


# ------------------------------------------------ the coverage rate and the judgment

@dataclass
class IntervalRecord:
    """One tool-interval record (a long-table row after parsing the adapter output)."""

    tool: str
    arm: str
    n: int
    signature: str
    rep: int
    estimate: float
    lo95: float
    hi95: float
    estimand: str = "absolute"      # absolute (the main) | fraction | raw (secondary)
    zeroed: bool = False            # the sigfit zeroing-rule trigger / the STL filtering collapse
    error: bool = False             # the refusal-to-run/error (the deployment behavior, counted honestly)


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
    filtered_rate: float = 0.0      # the zeroing/filtering trigger rate (the secondary column)
    error_rate: float = 0.0
    p1_mechanism_i: bool = False    # the flat layer's P1 mechanism (i) attribution column (the addendum diagnostic column)


def cell_coverage(records, truth_h_by_sig: dict, layer_of) -> list:
    """Computes per cell the empirical coverage rate and the CP interval (only estimand='absolute' and non-error enter the main-judgment denominator).

    The error/refusal-to-run records do not count into the denominator but count into the error_rate (the protocol §2.1: the deployment behavior is the evidence;
    the N=100-end guardline trigger rate forms its own column).
    """
    cells = {}
    for r in records:
        if r.signature not in truth_h_by_sig:
            continue                      # the non-truth signature in the catalogue (the absent column) has no estimand
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
    """Every adjacent difference ≤ 0 with at least one strictly < 0 (the documented operationalized definition)."""
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
    """The frozen judgment rule (the §2.4/F1, a verbatim implementation).

    The input contract (P0-2, the frozen addendum clause b): the sensitivity arms (nb/clock/sparse) only refine,
    they never overturn the judgment — the caller passes judge_arms (the set of the main model arms admitted to the judgment,
    namely the main multinomial + the frozen truth composition axis); the non-judge arms' cells are ignored wholesale and noted.

    The tool contract (P2a): every judgment sub-clause is filtered by the tier1_tools — the "any/all/both
    tools" all mean the Tier-1 pair; the kill additionally requires both tools to have cells in the judgment
    region (N≥300) (the literal semantics of the "two Tier-1 tools", guarding against a single tool silently passing).

    borderline (P2b): the protocol-memo §2.4 original wording "only for the borderline cells double the reps
    to 400 and re-judge" and the adjudication §5 restatement both carry **no N≥300 qualification** → the miscalibrated
    cells of every grid point (including N<300) may enter the gray doubling flow, per the frozen text.

    The "monotone worsening" operationalized definition (documented): for each (tool, signature), the N≥300 grid points'
    ascending ĉ series' every adjacent difference ≤ 0 with at least one strictly < 0.
    Only the main-table cells with estimand='absolute' are accepted (guaranteed upstream).
    """
    j = Judgment(verdict="GRAY")
    pool = [c for c in cells if c.n_reps > 0]
    if judge_arms is not None:
        excluded = sorted({c.arm for c in pool if c.arm not in judge_arms})
        pool = [c for c in pool if c.arm in judge_arms]
        if excluded:
            j.notes.append("the sensitivity arms only emit report columns and do not enter the judgment (the frozen addendum clause b): "
                           + ", ".join(excluded))
    t1 = set(tier1_tools)

    # Supporting A ①: any Tier-1 tool's any cell
    for c in pool:
        if (c.tool in t1 and c.coverage <= support_lower
                and c.cp_hi < ci_upper_max):
            j.clause_a1_cells.append(f"{c.tool}|{c.arm}|N={c.n}|{c.signature}")
    # Supporting A ②: the flat layer N≥300 all the Tier-1 cells
    flat_cells = [c for c in pool
                  if c.tool in t1 and c.layer == "flat" and c.n >= judge_n_min]
    j.clause_a2 = bool(flat_cells) and all(c.coverage <= flat_upper for c in flat_cells)
    if j.clause_a1_cells or j.clause_a2:
        j.verdict = "A"
        return j

    # kill→B: both Tier-1 tools' every N≥300 cell ĉ ≥ 0.90 and no monotone worsening
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

    # gray: the borderline cells = the Tier-1 cells with ĉ<0.90 at all the N (P2b: the frozen text
    # carries no N≥300 qualification; the candidates to double the reps to 400 and re-judge)
    j.borderline_cells = [f"{c.tool}|{c.arm}|N={c.n}|{c.signature}"
                          for c in pool if c.tool in t1 and c.coverage < kill_lower]
    j.notes.append("gray: the borderline cells need their reps doubled to 400 and re-judged (the protocol §2.4); "
                   "still gray → the author's adjudication, defaulting to B (the risk asymmetry).")
    return j
