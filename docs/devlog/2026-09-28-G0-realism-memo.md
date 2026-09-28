# G0 先导覆盖实验——生物学与数据现实性备忘

> 2026-09-28。计算生物学家独立备忘（与协议设计备忘并行、互不假设）。对象：ARCHITECTURE §8 G0 段 + ROADMAP G 门（2 竞品工具 × TMB 网格，exposure 区间名义 vs 实际覆盖率；kill-criterion 门）。

## 1. 先例文献核查（最重要）

**检索词**："mutational signature exposure" × {"confidence interval","coverage probability","interval coverage","empirical coverage","calibration"}（2019–2026，Google/PubMed/PMC）；"conformal prediction mutational signature"；"uncertainty calibration signature exposure 2025/2026"。

**结论：未发现任何已发表工作测量 signature exposure 区间的名义 vs 实际覆盖率。** 最接近的三项，均不构成抢跑：

1. **MSA**（Senkin 2021, BMC Bioinformatics 22:540; PMC8567580）——参数 bootstrap 百分位 CI，但评估只报灵敏度/特异度/MCC 及"用 CI 下限做阈值"的操作特性，**未测经验覆盖率**（2026-09-28 直接读全文核实）。
2. **Diffsig**（Park 2024, Cancer Epidemiol Biomarkers Prev 33(5):721; PMC11062813）——报告了 80% credible interval 覆盖率，但对象是其自身贝叶斯模型的**关联回归系数 β**，非拟合层 exposure 区间；且其上游 NNLS 明确不产区间（直接核实）。
3. **Medo 2024**（Nat Commun 15:9467; PMID 39487150）——证实平坦签名（SBS5/40）系统性低估与 TMB 依赖，并**明示 CI 覆盖率验证为 open question**（依 research/02 已核实引文；全文付费墙未独立复读，标注）。

辅助核查：Jiang 2025（Brief Bioinform bbaf042）校准的是 presence 检测的 precision/recall，非区间；MuSiCal（Jin 2024）in-silico 校准的是剪枝阈值；sigfit/signeR 产 HPD 但无已发表覆盖审计。**SigFormer（bioRxiv 2026, 10.64898/2026.01.20.700228）**为 transformer 点估计分解 + 显式残差分量，摘要未声明区间校准——竞争者逼近中但未抢跑。**判定：G0 叙事成立；但 kill criterion"竞品发布校准 CI"的近似形态已现，G0 须按 2 周窗口出数并冻结时间戳。**

## 2. TMB 网格现实性

G0 以总突变数 N 为轴（无平台轴），需保证覆盖真实谱：

| 臂 | 真实范围 | 锚 |
|---|---|---|
| WGS 常见 | ~1–100 mut/Mb（N≈3×10³–3×10⁵ @3.1 Gb） | Alexandrov 2020, Nature 578:94 (PMID 32025018) |
| 儿童/低 TMB | 中位 ~1 mut/Mb，下探 <10³ | Gröbner 2018, Nature 555:321 (PMID 29489754) |
| 超突变臂 | POLE/POLD1/MSI >100 mut/Mb（≥100× 常见臂） | Campbell 2017, Cell 171:1042 (PMID 28810159) |
| panel/ctDNA | 1–1.5 Mb panel 常 10–100 突变；ctDNA <30 | Chalmers 2017, Cell 170:316 (PMID 28198573) |

**建议网格**：几何扫 N≈30–10⁶（≥10 点）；**10²–10⁴ 是覆盖率悬崖区，必须加密（≥6 点）**。ARCH §8 的 10² 下限偏高，panel 端 30–100 必须入网格。

## 3. 真值组合现实性

- **平坦组**：SBS1/5/40 同族平坦、SBS40 与 SBS5 谱相近（COSMIC 归 clock-like 家族），是 Medo 低估主体与可辨识度最差组；必须设小 exposure（各 <10%）共存 cell。
- **强制连带**：APOBEC 须 SBS2/13 整组同真同假；POLE 组 SBS10a/b/c/d(+28)；MMR 群 SBS6/15/20/21/26(/44) 相关群。
- **建议组合 ≥6**：①clock-only（SBS1+5）；②+APOBEC；③+MMR 群；④POLE 超突变（高 N + 10 群）；⑤平坦三联小 exposure；⑥强签名（SBS4/SBS7）+ 平坦背景。
- **纯度稀释方向**：正常细胞贡献 clock 型突变，稀释等效于肿瘤有效 N 下降 + clock 份额抬升——**平坦签名与亚克隆限制的 APOBEC 先失真**（机制同 Medo 低 N + TrackSig 亚克隆 exposures, doi:10.1038/s41467-020-14352-7）。G0 不必全网格交叉纯度，做一层 clock 混入（purity 0.8/0.4 等效）即可。

## 4. 生成器保真度

| 生成器 | 性质 | 已知局限 | 对 G0 适用性 |
|---|---|---|---|
| SigProfilerSimulator（Bergstrom 2020, BMC Bioinform 21:438） | 上下文保持重采样零模型 | 本质多项、无过散/亚克隆 | 校准臂主生成器 |
| SynSig（Rozen lab；Wu 2022/Jiang 2024 用） | 可控 exposure/相关性注入 | 仍多项世界观 | 对抗臂（相关性/小 exposure） |
| PCAWG 锚定真实混合 | 过散/机会失配真实 | **无真值 exposure** | 仅 sanity，不进覆盖率分母 |

**关键缺口**：三者共享"给定 (W,H) 即多项采样"世界观；真实目录过散（mSigAct 默认 NB size=8 即证据）。纯多项真值 × 多项工具 → 覆盖率系统性乐观。**G0 必须加至少一档 NB 过散注入臂。**

## 5. caller/平台轴裁决

**建议 G0 固定 one-caller（实质为无 caller：合成目录直接喂两工具），平台单点 WGS 机会。** 理由：(a) G0 的问题是区间覆盖率，caller 轴会把目录生成噪声与拟合噪声混淆，污染 kill-criterion 判读；(b) 2 周窗口装不下 BAM 级双 caller 重复；(c) 竞品均收目录输入，目录级天然公平；(d) panel 机会不对称（SPA 有 exome 参考集、MuSiCal 无）本身会制造伪差异。caller/平台轴留给 M7 全网格（ARCH §8 已列）。

## 6. 风险清单（G0 结果不 informative 的场景）

1. 多项理想世界 → 覆盖率虚高，结论不外推真实过散数据（§4）。
2. 竞品区间语义不一致：SPA 类不产 exposure CI、mSigAct 类只有 LRT p 值——"名义覆盖率"对无区间工具无定义；贝叶斯 HPD 与"95% 频率覆盖"是解释性选择，协议须写死口径。
3. N 网格过粗（10² 以下/低端稀疏）→ 假阴性"覆盖率尚可"。
4. 真值组合过弱（只测 SBS4/7 类强签名）→ 高估领域表现；平坦组/MMR 群才是失败主场。
5. 单 WGS 机会 → 结论不覆盖 panel/ctDNA（恰是 MSU-LowCount 卖点），叙事决策须限定 scope。
6. 若 G0 仅复现 Medo 的点估计/TMB 发现而无区间覆盖率增量，Framing A 贡献减薄——设计必须以区间为中心，非 L1/cosine。

## 7. 建议的场景裁决点

1. **NB 过散臂必选**（≥1 档），否则 kill-criterion 判定建立在多项理想世界上。
2. **两族竞品各取一**：区间族（bootstrap/HPD）+ 检验族（LRT 名义 α vs 经验 size/power）并列计入 G0 门。
3. **低 N 端分辨率**：N∈[30,2000] ≥6 点 + 一层 clock 混入（purity 0.4 等效）；高 N 4 点。

## 文献依据

Alexandrov 2020 PMID 32025018；Gröbner 2018 PMID 29489754；Campbell 2017 PMID 28810159；Chalmers 2017 PMID 28198573；Medo 2024 PMID 39487150 / doi:10.1038/s41467-024-53711-6；Jiang 2025 doi:10.1093/bib/bbaf042；Senkin 2021 PMC8567580；Park 2024 PMC11062813；Bergstrom 2020 BMC Bioinform 21:438；Rubanova 2020 doi:10.1038/s41467-020-14352-7；SigFormer bioRxiv 2026 doi:10.64898/2026.01.20.700228。
