# 评审 05：Nature 期刊编辑视角（独立评估，2026-09-28）

> 评审人设定：资深编辑，负责计算生物学方法论文（Nature/Nature Methods 视角），desk assessment，诚实优先。
> **一句话总评：这个项目的调研质量与工程卫生在前 5%，但按当前包装等于把一手好牌按 Genome Biology 的赔率打出去。**

## 1. Venue 判定（先说结论）

**按当前计划执行完毕，这不是一篇 Nature 论文，也大概率不是 Nature Methods 论文。它是（写得好的话）一篇 Genome Biology 或 Nature Communications 论文。**

领域自己的发表记录（比任何论证都有说服力）：

| 旗舰工具/方法 | 实际发表去处 |
|---|---|
| MuSiCal | Nat Genet 2024 |
| SigProfilerExtractor | Cell Genomics 2022 |
| SigProfilerMatrixGenerator | BMC Genomics 2023 |
| PASA/mSigAct | Brief Bioinformatics |
| SUITOR | PLoS Comput Biol |
| BASCULE | Genome Biology 2025 |
| Medo 基准 | Nat Commun 2024 |
| Cornet | bioRxiv（2026-09，尚在预印本） |
| PCAWG/Degasperi/Everall | Nature/Science/Nat Genet（**发现论文**） |

规律：**这个领域里 Nature/NG 给发现论文；工具和方法论文落在 Cell Genomics、Genome Biology、PLoS CB、Brief Bioinform、Nat Commun。**"架构/性能/应用"三段式是 Bioinformatics/Genome Biology 的结构——把三段式对齐"Nature 级"是 category error。

**唯一够得上 NM/NC 叙事核心的统计贡献：MSU-Fit / MSU-LowCount / MSU-Infer 这一簇——"exposure 推断的校准统计学"。**

## 2. 新颖性层级排序

1. **MSU-Fit：首个对 exposure 区间做经验覆盖率测量的推断层**——Medo 2024 白纸黑字留的 open question，无 incumbent 占领；可证伪、可基准化。**全计划唯一够顶刊叙事核心的贡献。**
2. **MSU-LowCount：panel/ctDNA 的原则性推断（conformal）**——SigMA 后的真实荒地，临床样本池最大。
3. **MSU-Infer：CoDA/差丰正式统计**——无竞争，让"exposure 的统计学"成为完整主题。
4. 五模态端到端 + Catalog IR + 版本化 refdb——真实生态位但是 **Genome Biology 级**。
5. Rust 性能——真实但只值一句 "enabling"；Alexandrov 组正在向矩阵生成/QC 移动，速度护城河有保质期。
6. MSU-Extract——SigProfiler 共识 + SUITOR CV 的工程综合。Reviewer 一句话："engineering synthesis of SigProfiler and SUITOR, in Rust."
7. **MSU-Corr——危险最高**。Cornet 是 Park 组两周前的预印本，正式发表大概率 NG/NM 级；会被写 "derivative of Cornet"。除非五模态联合做出 Cornet 做不到的发现，否则降级为组件。
8. MSU-Tempo/Tensor——应用组件，不进 abstract。

**八个 MSU-* 名字必须砍到 2–3 个**——被 reviewer 识破一次"wrapper"，全部名号一起贬值。

## 3. 竞争定位

- 四大 power center（Alexandrov/Park/Rozen/Nik-Zainal）各守自己的楔子，**"集成生态"这条道恰好是他们结构性不会走的**——无正面竞争，但也结构性低声望。
- **"exposure 推断的统计"（校准 CI、CoDA、conformal 低计数）是四组都没占的中间地带**：Rozen 有检验没有区间校准，Park 有稀疏点估计没有覆盖率验证，DCEG 只管 K 选择。这是唯一能先占且占住后有防守纵深的高地。
- 当前计划下 reviewer **会**把 msuiter 读作 "derivative of SigProfiler+MuSiCal engineering synthesis"。防御方式不是更好的工程，而是有一个别人没有的命题句。
- 作者是 sigminer 作者——双刃剑：可信度加分，但会被读作 "sigminer v3 换了 Rust"。论文叙事必须让 MSU-Fit 的统计学独立于作者前史成立。

## 4. 三段式框架缺了什么

1. **一个由工具使能的发现作 headline**——Cornet 预印本自己就是模板（方法 + "SBS92a 追踪 ERCC2 顺铂状态"）。当前应用案例全是"在公开数据上跑 workflow"——装饰性。
2. **采纳/社区证据**——"领域的 PI 明天会换 pipeline 吗"。
3. 框架机会：**速度不是产品，速度是"校准统计学买得起"的前提**——bootstrap/conformal/CV 全是计算饥饿的，SigProfiler 天级运行时间让覆盖率校准研究事实上不可行。"We are fast *so that* we can afford statistical honesty" 是没有 competitor 讲过的、内在自洽的话——写进 abstract。

## 5. 顶刊证据标准

- 基准面已达标（三协议逐位复刻罕见）。注意 PASA 已示明 DBS/ID 是 MuSiCal 软肋——主攻那里，不在 SBS 跟 MuSiCal 打平手仗。
- **校准面（headline 所需）**：13 工具 × TMB 网格的名义 vs 实际覆盖率热图——**如果主流工具的 "95% CI" 在临床 TMB 下真实覆盖只有 60–80%，这张图就是 Nature Methods 的 Figure 1。** 必须做实，否则叙事塌方。
- **真实数据后果（当前完全缺失）**：校准 CI 要改变一个已发表的真实结论（如 Nacer 2026 的 7 种 HRD 方法 vs FDA 检测不一致，用校准不确定性重新裁决）。
- 案例从装饰变有力三选一：(a) 治疗史法证 + 真实治疗记录 concordance；(b) RNA-seq-only 队列（matched DNA-RNA 子集给 concordance，unmatched 多数给新信息）；(c) 低计数 panel 的 conformal 有效性 + MUTYH/MSI 诊断级检出。

## 6. 战略风险 Top 8

| # | 风险 | 严重度 | 缓解 |
|---|---|---|---|
| 1 | MSU-Corr 被 Cornet 正式发表压制 | 高 | 五模态是 Cornet 没有的——12 个月内做出多模态独特结果则保留，否则降级；不在 abstract 承诺 |
| 2 | 无发现/无临床后果的案例 = 顶刊一票否决 | 高 | 立刻启动队列合作（治疗记录/RNA-only），比任何代码优先 |
| 3 | 时间线幻想（单人现实 12–18 个月到投稿） | 高 | 砍范围；每季度复核竞争格局 |
| 4 | 8 个 MSU-* 稀释单一真贡献 | 中高 | 只命名 2–3 个；其余降为 features |
| 5 | bus factor = 1；无统计 co-author 时 conformal/CoDA 理论会被攻击 | 中高 | 找统计学 co-author + 临床/队列合作者 + 共同维护者 |
| 6 | "sigminer 重写"知觉 | 中 | 叙事绕开 sigminer 谱系，以 MSU-Fit 统计学自立 |
| 7 | 覆盖率校准可能证伪自己（竞品 CI 也许没那么糟） | 中 | **kill criterion——先花两周做最小覆盖实验（2 工具 × TMB 网格）再写任何叙事** |
| 8 | R-only 受众受限；COSMIC 许可 | 中 | CLI + parquet/arrow 交换层让 Python 可消费；许可已审慎 |

## 7. 候选论文 Framing

- **A（推荐主攻）"Calibrated inference of mutational signature exposures"**：领域所有 exposure 区间从未被验证；LRT + 支撑条件 bootstrap + 覆盖率校准 + conformal 低计数的第一套完整推断层；Rust 性能使校准在 cohort 规模分钟级可行。Target：**Nature Methods（冲刺）/ Nat Commun（现实落点）**。Figure 1 = 13 工具 × TMB 覆盖率热图（红色荒原）+ 校准曲线。
- **B（保底 upgraded）"A unified, bit-compatible ecosystem for five classes of mutational signatures"**：Target **Genome Biology（高概率）/ NC**。Figure 1 = 能力覆盖矩阵 vs 全部竞品 + 速度墙 + 12k WGS 端到端。
- **C（天花板最高，需合作者）"Signature surveillance beyond WGS"**：panel/ctDNA/RNA-only 的原则性推断 + 真实临床队列验证。Target：NC；若临床验证强 NM 有戏。**唯一可能长出发现故事的路径。**
- A+B 可合并；A+C 合并是最大化顶刊概率的组合。

## 8. 概率估计（诚实版）

| 期刊 | 当前计划顺利执行 | Framing A/C 重构 + 真实队列 |
|---|---|---|
| Nature Methods | ~5% | 15–25% |
| Nature Communications | 20–30% | 35–45% |
| Genome Biology | 50–60% | 60–70% |
| Bioinformatics（保底） | 75–85% | 同级 |

Nature/NG：只有 Framing C 长出真正的发现论文才进入对话。

## 9. Kill criteria / pivot 触发

1. 提取基准 parity 而非优势 → headline 切换 Framing A 校准统计，GB 保底。
2. **先导覆盖实验显示竞品 CI 基本校准 → MSU-Fit headline 证伪 → 接受 Framing B，不要硬造差异。**
3. Cornet 被 NG/NM 接收且扩展到 DBS/ID（在 M5 之前）→ MSU-Corr 降级。
4. M3 结束前没有锁定任何真实队列/临床合作 → 案例注定装饰性 → 主动接受 GB/NC 上限。
5. SPA/MuSiCal 发布校准 CI/conformal → 空白关闭 → 转向应用/发现论文。
6. M3 滑期 >100% → 砍 CN/SV/Tensor/RNA，只发 SBS/DBS/ID + MSU-Fit 核心。
7. 持续单人无共同维护者 → M1 前找到 co-maintainer。
