"""G0 网格与实验剖面配置（全部数字为冻结协议值，勿改）。

网格来源（冻结裁决 docs/devlog/2026-09-28-G0-pi-adjudication.md「PI 已裁决」
第 3 条，采现实性备忘 §2）：
- 几何网格 N ≈ 30–10⁶（现实性备忘 §2：panel/ctDNA 端 30–100 必须入网格；
  上端 10⁶ 覆盖 WGS 常见臂上限，Alexandrov 2020 PMID 32025018）；
- 10²–10⁴ 覆盖率悬崖区 ≥6 点加密（裁决对协议原 5 点 {100…10000} 的上调）。

PRIMARY_GRID 共 19 点；其中 [10², 10⁴] 区间内 9 点 ≥ 6（加密达标），
判决相关区 N≥300 的最大相邻比 ≈ 1.87×。

真值组合轴（冻结裁决第 3 条 + F3，≥6 组；签名集与占比按 realism memo §3
组合清单构造，占比取现实锚点，文献依据见各条注释）：
master（=F3 冻结 5 签名，组合清单 ②"+APOBEC"）+ clock_only / mmr / pole /
flat_triple / strong_flat 共 6 组。master 同时是 §2.4 easy/flat 分层与
P1 机制 (i) 探针的参照组成。

POLE 组合钉在高 N 档（POLE_N_SUBSET）：POLE/POLD1 超突变 >100 mut/Mb
（Campbell 2017 PMID 28810159），WGS 等效 N ≥ 3×10⁵——低 N 格点对该
组合无物理学意义。

降级档（协议备忘 §6/§7-R7，冻结裁决明示保留）：3 点档 {100, 1000, 10000}
或 reps=100；降级必须记入 memo（run_grid 会在结果表中写 profile 字段）。

重复数（协议 §2.3，冻结）：200/工具/签名/网格点；gray 重判 = 400。
"""

from __future__ import annotations

from dataclasses import dataclass, field

# ---- 冻结数字（F1–F4 范围内；改动=违反预注册纪律） --------------------

PRIMARY_GRID = (30, 60, 100, 180, 300, 560, 1000, 1800, 3000, 5600, 10000,
                18000, 30000, 56000, 100000, 180000, 300000, 560000, 1000000)
DEGRADED_GRID = (100, 1000, 10000)          # §6 降级：3 点档
POLE_N_SUBSET = (100000, 300000, 1000000)   # pole 组合的高 N 档（Campbell 2017）
REPS_PRIMARY = 200                          # §2.3 功效核算对应的重复数
REPS_DEGRADED = 100                         # §6 降级：reps=100（−10pp 判定功效仍 >0.95）
REPS_GRAY = 400                             # §2.4 gray：borderline cells 加倍至 400
JUDGE_N_MIN = 300                           # §2.4 判定的 N 下界（N≥300 cells）

MASTER_TRUTH_COMPOSITION = {                # F3 冻结：5 签名固定组成（=组合轴 "master"）
    "SBS1": 0.15,
    "SBS2": 0.15,
    "SBS13": 0.15,
    "SBS5": 0.30,
    "SBS40": 0.25,
}

# ---- 冻结真值组合轴（adjudication §3「真值组合 ≥6 组」；realism memo §3） ----
# 占比为现实锚点（各组合和恒为 1）；文献依据逐条内注。

COMPOSITIONS = {
    # ② "+APOBEC" = F3 冻结主组成：APOBEC 对 SBS2/13 整组同真（realism memo §3
    # 强制连带）+ clock + 平坦近重复对；§2.4 easy/flat 分层定义在此组成上。
    "master": dict(MASTER_TRUTH_COMPOSITION),

    # ① clock-only：SBS1（5mC 自发脱氨，随分裂线性累积）与 SBS5（clock-like
    # 平坦）几乎普遍存在（Alexandrov et al. 2020, Nature 578:94, PMID 32025018）；
    # PCAWG 中 SBS5 通常为最大的 clock-like 成分 → SBS5 份额 > SBS1。
    "clock_only": {"SBS1": 0.30, "SBS5": 0.70},

    # ③ +MMR 群：MMR 缺陷/MSI-H 肿瘤以相关群 SBS6/15/20/21/26/44 整组同真为
    # 特征（realism memo §3 强制连带；Alexandrov 2020），SBS44 与 SBS6 相关且
    # 份额更小；群合计 ~40% + clock 背景（SBS1/SBS5）。
    "mmr": {"SBS6": 0.10, "SBS15": 0.08, "SBS20": 0.07, "SBS21": 0.07,
            "SBS26": 0.05, "SBS44": 0.03, "SBS1": 0.20, "SBS5": 0.40},

    # ④ POLE 超突变：POLE/POLD1 外切酶缺陷肿瘤以 SBS10a 为主 + SBS10b/c/d 与
    # SBS28（Alexandrov 2020；Campbell et al. 2017, Cell 171:1042, PMID 28810159
    # —— >100 mut/Mb ⇒ 钉高 N 档 POLE_N_SUBSET）。
    "pole": {"SBS10a": 0.30, "SBS10b": 0.10, "SBS10c": 0.05, "SBS10d": 0.05,
             "SBS28": 0.05, "SBS1": 0.10, "SBS5": 0.35},

    # ⑤ 平坦三联小 exposure：SBS1/5/40 同族平坦各 <10%（realism memo §3：
    # "必须设小 exposure（各 <10%）共存 cell"）；余额由 APOBEC 整组 SBS2/13
    # 承载（burst 型 APOBEC 肿瘤 + 小 clock 平坦背景）。
    "flat_triple": {"SBS1": 0.08, "SBS5": 0.08, "SBS40": 0.08,
                    "SBS2": 0.38, "SBS13": 0.38},

    # ⑥ 强签名 + 平坦背景：SBS4（烟草）/SBS7（UV）为经典大 exposure 强签名
    # （Alexandrov 2020），叠加普遍存在的平坦 clock-like 背景 SBS5/40。
    "strong_flat": {"SBS4": 0.35, "SBS7": 0.35, "SBS5": 0.15, "SBS40": 0.15},
}

EASY_LAYER = ("SBS1", "SBS2", "SBS13")      # §2.4 分层（master 组成语境）
FLAT_LAYER = ("SBS5", "SBS40")              # §2.4 flat 层（近重复对，P1 机制 (i) 探针）

# 组合轴扩展签名族的报告分层（不进 §2.4 判定子句；仅覆盖表 layer 列）。
SIGNATURE_FAMILY = {
    **{k: "easy" for k in EASY_LAYER},
    **{k: "flat" for k in FLAT_LAYER},
    **{k: "mmr" for k in ("SBS6", "SBS15", "SBS20", "SBS21", "SBS26", "SBS44")},
    **{k: "pole" for k in ("SBS10a", "SBS10b", "SBS10c", "SBS10d", "SBS28")},
    **{k: "strong" for k in ("SBS4", "SBS7")},
}

NB_SIZE = 8                                 # 现实性备忘 §4 / P3：mSigAct 默认 size=8 语义
CLOCK_PURITY = 0.4                          # clock 混入臂：purity≈0.4 等效（裁决第 3 条）
SPARSE_SIGNATURE = "SBS13"                  # §4 辅助稀疏臂：SBS13 份额改为 2%
SPARSE_SHARE = 0.02
SPARSE_N = 1000                             # 稀疏臂单点（期望 SBS13 ≈ 20 counts）
SENS_POINT_N = 1000                         # 敏感性臂（NB / clock）单点口径（§2.2）

SUPPORT_A_LOWER = 0.85                      # F1 冻结：支持 A 的 −10pp 线
SUPPORT_A_CI_UPPER_MAX = 0.90               # F1 冻结：clause ① 的 CI 上界排除线
FLAT_SUPPORT_UPPER = 0.90                   # F1 冻结：clause ② flat 层全 cell ≤ 0.90
KILL_LOWER = 0.90                           # F1 冻结：kill→B 的 −5pp 线

TIER1_TOOLS = ("sigfit", "stl")             # F2 冻结：sigfit v2.2.0 + signature.tools.lib v2.5.2


@dataclass(frozen=True)
class ArmSpec:
    """一个模拟臂：名称、生成参数、N 列表与重复数。

    judge（P0-2，冻结增补条款 b）：该臂是否进 §2.4 判定。main 模型臂
    （主多项 + 冻结真值组合轴 comp_*，adjudication §3 场景升级）= True；
    敏感性臂（nb/clock/sparse）= False——只细化不推翻判定，仅出报告列。

    arms:
      main              多项主臂（协议 §2.2 主生成模型），master 组成，全网格；
      comp_clock_only   组合①（clock-only），全网格；
      comp_mmr          组合③（MMR 群），全网格；
      comp_pole         组合④（POLE 超突变），高 N 档 POLE_N_SUBSET；
      comp_flat_triple  组合⑤（平坦三联小 exposure），全网格；
      comp_strong_flat  组合⑥（强签名+平坦背景），全网格；
      nb                NB 过散臂（必选，裁决第 3 条；size=8，Gamma-Poisson 实现），
                        单点 N=1000，敏感性（不进判定）；
      clock             clock 混入臂（purity=0.4 等效），单点 N=1000，敏感性；
      sparse            稀疏臂（SBS13→2% @ N=1000，协议 §4），敏感性。
    """

    name: str
    n_list: tuple
    reps: int
    params: dict = field(default_factory=dict)
    judge: bool = True


def arms_for_profile(profile: str = "primary") -> list:
    """返回某实验剖面的臂配置列表。

    primary：6 个 main 模型臂（组合轴）+ 3 个敏感性臂；全网格 200 reps。
    degraded：3 点档 × 100 reps（协议 §6/§7-R7 降级档；pole 组合保留其
    物理必需的高 N 档，敏感性臂同 100 reps）。
    smoke：管线自检用极小剖面（不属 G0 正式执行，仅验证 harness 本身）；
    含一个组合臂以覆盖组合轴代码路径。
    """
    if profile == "primary":
        return [
            ArmSpec("main", PRIMARY_GRID, REPS_PRIMARY, {"composition": "master"}),
            ArmSpec("comp_clock_only", PRIMARY_GRID, REPS_PRIMARY,
                    {"composition": "clock_only"}),
            ArmSpec("comp_mmr", PRIMARY_GRID, REPS_PRIMARY, {"composition": "mmr"}),
            ArmSpec("comp_pole", POLE_N_SUBSET, REPS_PRIMARY, {"composition": "pole"}),
            ArmSpec("comp_flat_triple", PRIMARY_GRID, REPS_PRIMARY,
                    {"composition": "flat_triple"}),
            ArmSpec("comp_strong_flat", PRIMARY_GRID, REPS_PRIMARY,
                    {"composition": "strong_flat"}),
            ArmSpec("nb", (SENS_POINT_N,), REPS_PRIMARY, {"nb_size": NB_SIZE},
                    judge=False),
            ArmSpec("clock", (SENS_POINT_N,), REPS_PRIMARY, {"purity": CLOCK_PURITY},
                    judge=False),
            ArmSpec("sparse", (SPARSE_N,), REPS_PRIMARY,
                    {"sparse_signature": SPARSE_SIGNATURE, "sparse_share": SPARSE_SHARE},
                    judge=False),
        ]
    if profile == "degraded":
        return [
            ArmSpec("main", DEGRADED_GRID, REPS_DEGRADED, {"composition": "master"}),
            ArmSpec("comp_clock_only", DEGRADED_GRID, REPS_DEGRADED,
                    {"composition": "clock_only"}),
            ArmSpec("comp_mmr", DEGRADED_GRID, REPS_DEGRADED, {"composition": "mmr"}),
            ArmSpec("comp_pole", POLE_N_SUBSET, REPS_DEGRADED, {"composition": "pole"}),
            ArmSpec("comp_flat_triple", DEGRADED_GRID, REPS_DEGRADED,
                    {"composition": "flat_triple"}),
            ArmSpec("comp_strong_flat", DEGRADED_GRID, REPS_DEGRADED,
                    {"composition": "strong_flat"}),
            ArmSpec("nb", (SENS_POINT_N,), REPS_DEGRADED, {"nb_size": NB_SIZE},
                    judge=False),
            ArmSpec("clock", (SENS_POINT_N,), REPS_DEGRADED, {"purity": CLOCK_PURITY},
                    judge=False),
            ArmSpec("sparse", (SPARSE_N,), REPS_DEGRADED,
                    {"sparse_signature": SPARSE_SIGNATURE, "sparse_share": SPARSE_SHARE},
                    judge=False),
        ]
    if profile == "smoke":
        return [
            ArmSpec("main", (100, 1000), 5, {"composition": "master"}),
            ArmSpec("comp_clock_only", (SENS_POINT_N,), 5, {"composition": "clock_only"}),
            ArmSpec("nb", (SENS_POINT_N,), 5, {"nb_size": NB_SIZE}, judge=False),
        ]
    raise ValueError(f"unknown profile: {profile}")


def all_seed_specs(arms: list) -> list:
    """展开臂配置为逐 (arm, N, rep) SeedSpec 列表（Seeds.txt 的行集）。"""
    from .seeds import SeedSpec

    specs = []
    for arm in arms:
        for n in arm.n_list:
            for rep in range(arm.reps):
                specs.append(SeedSpec(arm.name, n, rep))
    return specs
